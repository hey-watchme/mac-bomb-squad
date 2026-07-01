import Foundation
import SwiftUI

private enum ComposeDraftStore {
    private static let key = "ReviewViewModel.composeDraft"

    static func load() -> String {
        UserDefaults.standard.string(forKey: key) ?? ""
    }

    static func save(_ draft: String) {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(draft, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}

/// Owns the staging → review → deploy flow and all UI state.
@MainActor
final class ReviewViewModel: ObservableObject {
    /// Staging draft the user is editing.
    @Published var draft: String = "" {
        didSet {
            guard mode == .compose else { return }
            ComposeDraftStore.save(draft)
        }
    }
    /// Latest review result, if any.
    @Published var result: ReviewResult?
    /// Adopted/edited revision that will actually be deployed.
    @Published var revisedDraft: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Wall-clock latency of the last successful review, in milliseconds.
    @Published var lastDurationMs: Int?
    /// Display name of the model used for the last review.
    @Published var lastModelName: String?
    /// Hold-to-talk dictation state.
    @Published var isRecording = false
    @Published var isTranscribing = false
    /// Briefly toggled true after a successful deploy for toast feedback.
    @Published var didDeploy = false
    @Published var focusedField: FocusField?
    @Published private(set) var recentHistoryEntries: [HistoryEntry] = []
    @Published private(set) var isLoadingRecentHistory = false
    /// Target language for the deliverable (`revisedDraft`). Default Japanese.
    @Published var outputLanguage: OutputLanguage = .japanese

    /// The exact draft text and language that produced the current `result`.
    private var reviewedDraft: String?
    private var reviewedLanguage: OutputLanguage?
    private var hasLoadedRecentHistory = false

    /// Direction of this session: composing an outgoing draft (review/soften)
    /// or transforming a received message (make it readable). Drives the prompt.
    let mode: ReviewMode

    /// Optional fixed provider (used by tests/previews). When nil, the provider
    /// is built from the user's selection at review time.
    private let overrideProvider: ReviewProvider?
    private let deployer: Deployer

    init(
        provider: ReviewProvider? = nil,
        deployer: Deployer = ClipboardDeployer(),
        mode: ReviewMode = .compose
    ) {
        self.overrideProvider = provider
        self.deployer = deployer
        self.mode = mode
    }

    /// Resolve the engine to use for the next review, based on the selected model.
    private func currentProvider() -> ReviewProvider {
        if let overrideProvider { return overrideProvider }
        let model = AppSettings.selectedModel()
        switch model.vendor {
        case .anthropic: return ClaudeClient(model: model.apiModelID)
        case .openAI, .groq: return OpenAICompatibleClient(model: model)
        }
    }

    var canReview: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }

    func runReview() async {
        errorMessage = nil
        if result != nil {
            result = nil
            revisedDraft = ""
        }
        isLoading = true
        let model = AppSettings.selectedModel()
        let started = Date()
        defer { isLoading = false }
        let input = draft
        let language = outputLanguage
        do {
            let result = try await currentProvider().review(draft: input, mode: mode, language: language)
            self.lastDurationMs = Int(Date().timeIntervalSince(started) * 1000)
            self.lastModelName = model.displayName
            self.result = result
            self.revisedDraft = result.revisedText
            self.reviewedDraft = input
            self.reviewedLanguage = language
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    var canDeployDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when there is nothing to act on — used so a Right-Shift double-tap on an empty draft
    /// closes the panel instead of doing nothing.
    var isEmptyDraft: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canFocusRevision: Bool {
        result != nil
    }

    /// Restore the last in-progress compose draft after reopening the panel.
    func restorePersistedDraftIfNeeded() {
        guard mode == .compose else { return }
        guard draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draft = ComposeDraftStore.load()
    }

    func loadRecentHistoryIfNeeded() async {
        guard mode == .compose else { return }
        guard !hasLoadedRecentHistory else { return }
        hasLoadedRecentHistory = true
        await reloadRecentHistory()
    }

    func applyRecentHistory(_ entry: HistoryEntry) {
        deploy(text: entry.finalText, historyInput: .init(
            mode: historyMode,
            sourceText: entry.finalText,
            finalText: entry.finalText,
            modelID: entry.modelID,
            modelName: entry.modelName,
            outputLanguage: entry.outputLanguage,
            action: historyAction
        ))
    }

    func toggleFocusedField() {
        guard canFocusRevision else {
            focusedField = .draft
            return
        }
        switch focusedField {
        case .revision:
            focusedField = .draft
        default:
            focusedField = .revision
        }
    }

    /// Append dictated text to the draft (with a separating space as needed).
    func appendTranscription(_ text: String) {
        let piece = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !piece.isEmpty else { return }
        if draft.isEmpty {
            draft = piece
        } else {
            let needsSpace = !(draft.hasSuffix(" ") || draft.hasSuffix("\n"))
            draft += (needsSpace ? " " : "") + piece
        }
    }

    /// True when a review exists but the draft has changed since it was made.
    var needsReReview: Bool {
        result != nil && (reviewedDraft != draft || reviewedLanguage != outputLanguage)
    }

    /// Right-Shift double-tap requests a review only from the left draft editor.
    func requestReviewFromHotkey() {
        guard canReview else { return }
        Task { await runReview() }
    }

    /// Deploy the original draft as-is (skip review).
    func deployDraft() {
        deploy(text: draft, historyInput: .init(
            mode: historyMode,
            sourceText: draft,
            finalText: draft,
            modelID: nil,
            modelName: nil,
            outputLanguage: nil,
            action: historyAction
        ))
    }

    /// Deploy the reviewed/edited revision (falls back to the draft if empty).
    func deployRevision() {
        let finalText = revisedDraft.isEmpty ? draft : revisedDraft
        let model = result == nil ? nil : AppSettings.selectedModel()
        deploy(text: finalText, historyInput: .init(
            mode: historyMode,
            sourceText: draft,
            finalText: finalText,
            modelID: model?.id,
            modelName: lastModelName ?? model?.displayName,
            outputLanguage: outputLanguage.displayName,
            action: historyAction
        ))
    }

    /// Deploy text to the live destination (clipboard, or paste into the
    /// originating field for the hotkey panel).
    private func deploy(text: String, historyInput: HistoryEntryInput) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try deployer.deploy(text)
            Task {
                await LocalHistoryStore.shared.record(historyInput)
                await self.reloadRecentHistory()
            }
            if mode == .compose {
                ComposeDraftStore.clear()
            }
            didDeploy = true
            Task {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                self.didDeploy = false
            }
        } catch {
            errorMessage = "デプロイに失敗しました: \(error.localizedDescription)"
        }
    }

    private var historyMode: HistoryEntryMode {
        switch mode {
        case .compose: return .compose
        case .transform: return .transform
        }
    }

    private var historyAction: HistoryAction {
        switch mode {
        case .compose: return .sent
        case .transform: return .copied
        }
    }

    private func reloadRecentHistory() async {
        guard mode == .compose else { return }
        guard AppSettings.isHistoryEnabled() else {
            recentHistoryEntries = []
            isLoadingRecentHistory = false
            return
        }

        isLoadingRecentHistory = true
        defer { isLoadingRecentHistory = false }

        do {
            recentHistoryEntries = try await LocalHistoryStore.shared.fetchEntries(
                limit: 5,
                mode: .compose,
                action: .sent
            )
        } catch {
            recentHistoryEntries = []
        }
    }
}
