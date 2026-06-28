import SwiftUI

/// Left pane: the staging area where the user drafts/pastes the message
/// before it is reviewed. Nothing here is "live" yet.
struct StagingEditorView: View {
    @ObservedObject var viewModel: ReviewViewModel
    /// Shared focus across both editors (drives the blue highlight).
    @Binding var focusedField: FocusField?

    private var isFocused: Bool { focusedField == .draft }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("原文", systemImage: "doc.plaintext")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.draft.count) 文字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SettingsLink {
                    Label("設定", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .help("APIキーとモデルを設定します")
            }

            // Enter sends the original text as-is (after the IME confirms any
            // in-progress conversion); Shift+Enter inserts a newline.
            SendableTextEditor(
                text: $viewModel.draft,
                focusedField: $focusedField,
                field: .draft,
                onSend: { viewModel.deployDraft() },
                onEscape: { NotificationCenter.default.post(name: .closePanel, object: nil) }
            )
                .padding(8)
                .background(EditorFocusBackground(isFocused: isFocused))
                .overlay(alignment: .topLeading) {
                    if viewModel.draft.isEmpty {
                        Text("ここに送る前の下書きを入力／ペースト（Enter で送信 / 右Shift2回で次へ / Shift+Enter で改行 / Esc で閉じる / 右Shift長押しで音声）")
                            .foregroundStyle(.tertiary)
                            .padding(16)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 8) {
                if viewModel.isRecording {
                    Image(systemName: "mic.fill").foregroundStyle(.red)
                    Text("録音中…（離すと文字起こし）").font(.caption).foregroundStyle(.secondary)
                } else if viewModel.isTranscribing {
                    ProgressView().controlSize(.small)
                    Text("文字起こし中…").font(.caption).foregroundStyle(.secondary)
                } else if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button {
                    viewModel.deployDraft()
                } label: {
                    Label("送信", systemImage: "paperplane.fill")
                }
                .disabled(!viewModel.canDeployDraft)
                .help("レビューを使わず、原文のまま送信先へ入力します")

                Button {
                    Task { await viewModel.runReview() }
                } label: {
                    Label("レビュー", systemImage: "checkmark.shield")
                }
                .disabled(!viewModel.canReview)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
