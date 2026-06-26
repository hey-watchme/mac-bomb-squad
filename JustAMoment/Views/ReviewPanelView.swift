import SwiftUI

/// Right pane: shows the review findings, the diff, the editable revision,
/// and the "deploy to live" action.
struct ReviewPanelView: View {
    @ObservedObject var viewModel: ReviewViewModel
    /// Shared focus across both editors (drives the blue highlight).
    let focus: FocusState<FocusField?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("レビュー結果", systemImage: "text.magnifyingglass")
                    .font(.headline)
                Spacer()
                if let ms = viewModel.lastDurationMs {
                    Text("\(viewModel.lastModelName ?? "") · \(ms) ms")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let message = viewModel.errorMessage {
                errorBanner(message)
            }

            if let result = viewModel.result {
                resultBody(result)
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
    }

    @ViewBuilder
    private func resultBody(_ result: ReviewResult) -> some View {
        if viewModel.needsReReview {
            Label("原文が変更されました。次の ⌘⌘ で再レビューします。",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.orange)
        }

        // Result editor on top, aligned with the original editor on the left
        // (both sit directly under their column header).
        TextEditor(text: $viewModel.revisedDraft)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .frame(maxHeight: .infinity)
            .background(EditorFocusBackground(isFocused: focus.wrappedValue == .revision))
            .focused(focus, equals: .revision)

        HStack {
            Button("提案にリセット", action: viewModel.resetRevisionToSuggestion)
                .buttonStyle(.borderless)
            Spacer()
            Button {
                viewModel.deployRevision()
            } label: {
                Label("レビュー結果をデプロイ", systemImage: "paperplane.fill")
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
                    Label("指摘はありません。そのまま送れます。", systemImage: "checkmark.seal")
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(result.sortedIssues) { IssueCard(issue: $0) }
                }

                Text("変更点（原文 → 提案）").font(.subheadline).bold()
                DiffView(original: viewModel.draft, revised: viewModel.revisedDraft)
                    .frame(height: 120)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 240)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.left")
                .font(.largeTitle).foregroundStyle(.tertiary)
            Text("左で下書きをレビューすると、ここに結果が出ます。")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

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

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(issue.category.label)
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
            Text("→ \(issue.suggestion)").font(.callout).foregroundStyle(.blue)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    private var categoryColor: Color {
        switch issue.category {
        case .typo: return .orange
        case .impoliteness: return .red
        case .unclear: return .purple
        }
    }
}
