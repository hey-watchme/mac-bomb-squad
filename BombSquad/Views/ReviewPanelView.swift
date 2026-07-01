import SwiftUI

/// Right pane: shows the review findings, the diff, the editable revision,
/// and the "deploy to live" action.
struct ReviewPanelView: View {
    @ObservedObject var viewModel: ReviewViewModel
    /// Shared focus across both editors (drives the blue highlight).
    @Binding var focusedField: FocusField?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label(headerTitle, systemImage: headerSystemImage)
                    .font(.headline)
                Spacer()
                if let ms = viewModel.lastDurationMs {
                    Text("\(viewModel.lastModelName ?? "") · \(ms) ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                // Output language for the result. Changing it marks the review
                // stale, so the next right-Shift double-tap re-runs in that language.
                Picker("出力言語", selection: $viewModel.outputLanguage) {
                    ForEach(OutputLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .help("レビュー結果（送る文／読みやすくした文）の言語")
            }

            if let message = viewModel.errorMessage {
                errorBanner(message)
            }

            if let result = viewModel.result {
                resultBody(result)
            } else if viewModel.isLoading {
                loadingState
            } else {
                emptyState
            }
        }
        .padding()
        .overlay(alignment: .bottom) {
            if viewModel.didDeploy {
                Label("クリップボードにコピーしました", systemImage: "checkmark.circle.fill")
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.green.opacity(0.9), in: Capsule())
                    .foregroundStyle(.white)
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: viewModel.didDeploy)
        .task {
            await viewModel.loadRecentHistoryIfNeeded()
        }
    }

    @ViewBuilder
    private func resultBody(_ result: ReviewResult) -> some View {
        if viewModel.needsReReview {
            Label("原文が変更されました。原文で 右Shift2回 すると再レビューします。",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        // Result editor on top, aligned with the original editor on the left
        // (both sit directly under their column header).
        // Enter sends the review result (after the IME confirms any in-progress
        // conversion); Shift+Enter inserts a newline.
        SendableTextEditor(
            text: $viewModel.revisedDraft,
            focusedField: $focusedField,
            field: .revision,
            onSend: { viewModel.deployRevision() }
        )
            .padding(8)
            .frame(maxHeight: .infinity)
            .background(EditorFocusBackground(isFocused: focusedField == .revision))

        HStack {
            Spacer()
            Button {
                viewModel.deployRevision()
            } label: {
                // Receiving side never sends back to the sender; it only copies
                // the readable version to the clipboard for the reader's own use.
                Label(viewModel.mode == .transform ? "コピー" : "送信",
                      systemImage: viewModel.mode == .transform ? "doc.on.clipboard.fill" : "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
        }

        Divider()

        // The process (summary, findings, diff) below the result.
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(result.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if result.issues.isEmpty {
                    Label(viewModel.mode == .transform
                            ? "取り除いたノイズはありませんでした。"
                            : "指摘はありません。そのまま送れます。",
                          systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(result.sortedIssues) { IssueCard(issue: $0, mode: viewModel.mode) }
                }

                // The original→revision diff only makes sense when editing one's
                // own outgoing draft. On the receiving side we are not correcting
                // the sender's text, so showing a diff is meaningless (and reads
                // as if we were rewriting them). Hide it in transform mode.
                if viewModel.mode != .transform {
                    Text("変更点（原文 → 提案）").font(.subheadline).bold()
                    DiffView(original: viewModel.draft, revised: viewModel.revisedDraft)
                        .frame(height: 120)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 240)
    }

    /// While the (auto-)review runs, fill the result field with a spinner so the
    /// one-stop receiving flow shows progress the instant the panel opens.
    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(viewModel.mode == .transform ? "読みやすく整理しています…" : "レビュー中…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(EditorFocusBackground(isFocused: false))
    }

    /// Before any review exists, show the (non-editable) result field with a
    /// faint placeholder, mirroring the left editor's frame so the layout is
    /// stable once a result fills it in.
    private var emptyState: some View {
        Group {
            if viewModel.mode == .compose, !viewModel.recentHistoryEntries.isEmpty {
                recentHistoryState
            } else if viewModel.mode == .compose, viewModel.isLoadingRecentHistory {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("履歴を読み込み中…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(16)
                .background(EditorFocusBackground(isFocused: false))
            } else if viewModel.mode == .compose {
                Text("レビュー結果がここに表示されます\n\nまだ履歴がありません。")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
                    .background(EditorFocusBackground(isFocused: false))
            } else {
                Text("レビュー結果がここに表示されます")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(16)
                    .background(EditorFocusBackground(isFocused: false))
            }
        }
    }

    private var recentHistoryState: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(viewModel.recentHistoryEntries) { entry in
                Button {
                    viewModel.applyRecentHistory(entry)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(Self.recentHistoryFormatter.string(from: entry.createdAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(entry.usedReview ? "レビューあり" : "レビューなし")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        Text(entry.finalText)
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(3)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(EditorFocusBackground(isFocused: false))
    }

    private var headerTitle: String {
        if viewModel.mode == .compose, viewModel.result == nil, !viewModel.isLoading {
            return "最近の履歴"
        }
        return viewModel.mode == .transform ? "読み取り結果" : "レビュー結果"
    }

    private var headerSystemImage: String {
        if viewModel.mode == .compose, viewModel.result == nil, !viewModel.isLoading {
            return "clock.arrow.circlepath"
        }
        return viewModel.mode == .transform ? "doc.text.magnifyingglass" : "text.magnifyingglass"
    }

    private static let recentHistoryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()

    private func errorBanner(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
            .foregroundStyle(.red)
    }
}

/// A single finding card.
private struct IssueCard: View {
    let issue: ReviewIssue
    let mode: ReviewMode

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(categoryLabel)
                    .font(.caption2).bold()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(categoryColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(categoryColor)
                Text("重要度: \(issue.severity.label)")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }
            if !issue.excerpt.isEmpty {
                Text("「\(issue.excerpt)」").font(.callout).italic()
            }
            Text(issue.explanation).font(.callout)
            if !issue.suggestion.isEmpty {
                // On the receiving side this is a note for the reader (how to read
                // it safely / what to confirm), not a fix to send back. So we drop
                // the "→" arrow (which implies an edit) and label it as a note.
                Text("\(suggestionPrefix)\(issue.suggestion)")
                    .font(.callout)
                    .foregroundStyle(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    /// In transform mode the categories describe what was filtered out / what to
    /// watch for when reading, not problems the sender must fix.
    private var categoryLabel: String {
        guard mode == .transform else { return issue.category.label }
        switch issue.category {
        case .impoliteness: return "取り除いたノイズ"
        case .unclear: return "確認するとよい点"
        case .typo: return issue.category.label
        }
    }

    /// Compose mode frames the suggestion as a fix ("→ …"); transform mode frames
    /// it as a reader-facing note, so no imperative arrow.
    private var suggestionPrefix: String {
        guard mode == .transform else { return "→ " }
        switch issue.category {
        case .unclear: return "確認: "
        default: return "受け止め方: "
        }
    }

    private var categoryColor: Color {
        switch issue.category {
        case .typo: return .orange
        case .impoliteness: return .red
        case .unclear: return .purple
        }
    }
}
