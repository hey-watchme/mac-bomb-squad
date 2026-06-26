import Foundation
import SwiftUI

/// Owns the staging → review → deploy flow and all UI state.
@MainActor
final class ReviewViewModel: ObservableObject {
    /// Staging draft the user is editing.
    @Published var draft: String = ""
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

    /// The exact draft text that produced the current `result`. Used to decide
    /// whether the next ⌘⌘ should re-review (draft changed) or deploy (unchanged).
    private var reviewedDraft: String?

    /// Optional fixed provider (used by tests/previews). When nil, the provider
    /// is built from the user's selection at review time.
    private let overrideProvider: ReviewProvider?
    private let deployer: Deployer

    nonisolated init(provider: ReviewProvider? = nil, deployer: Deployer = ClipboardDeployer()) {
        self.overrideProvider = provider
        self.deployer = deployer
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
        isLoading = true
        let model = AppSettings.selectedModel()
        let started = Date()
        defer { isLoading = false }
        let input = draft
        do {
            let result = try await currentProvider().review(draft: input)
            self.lastDurationMs = Int(Date().timeIntervalSince(started) * 1000)
            self.lastModelName = model.displayName
            self.result = result
            self.revisedDraft = result.revisedText
            self.reviewedDraft = input
        } catch {
            self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Reset the adopted revision back to the model's suggestion.
    func resetRevisionToSuggestion() {
        revisedDraft = result?.revisedText ?? ""
    }

    var canDeployDraft: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// True when there is nothing to act on — used so ⌘⌘ on an empty panel
    /// closes it (a "never mind" gesture) instead of doing nothing.
    var isEmptyDraft: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    /// True when a review exists but the draft has changed since it was made,
    /// so the current review is stale and ⌘⌘ should re-review rather than deploy.
    var needsReReview: Bool {
        result != nil && reviewedDraft != draft
    }

    /// One unified "next step":
    /// - no review yet, or draft changed since the last review → review
    /// - review is current (draft unchanged) → deploy the revision
    /// Driven by both ⌘⌘ and Enter.
    func advance() {
        if result != nil && !needsReReview {
            deployRevision()
        } else if canReview {
            Task { await runReview() }
        }
    }

    /// Deploy the original draft as-is (skip review).
    func deployDraft() {
        deploy(text: draft)
    }

    /// Deploy the reviewed/edited revision (falls back to the draft if empty).
    func deployRevision() {
        deploy(text: revisedDraft.isEmpty ? draft : revisedDraft)
    }

    /// Deploy text to the live destination (clipboard, or paste into the
    /// originating field for the hotkey panel).
    private func deploy(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            try deployer.deploy(text)
            didDeploy = true
            Task {
                try? await Task.sleep(nanoseconds: 1_800_000_000)
                self.didDeploy = false
            }
        } catch {
            errorMessage = "デプロイに失敗しました: \(error.localizedDescription)"
        }
    }
}
