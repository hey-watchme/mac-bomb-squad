import SwiftUI

/// Left pane: the staging area where the user drafts/pastes the message
/// before it is reviewed. Nothing here is "live" yet.
struct StagingEditorView: View {
    @ObservedObject var viewModel: ReviewViewModel
    /// Shared focus across both editors (drives the blue highlight).
    @Binding var focusedField: FocusField?
    /// Drives the help popover anchored to the (?) button.
    @State private var showHelp = false

    private var isFocused: Bool { focusedField == .draft }

    /// Hotkeys shown in the help popover. Kept terse: keys only.
    private let shortcuts: [(String, String)] = [
        ("Enter", "送信"),
        ("Shift+Enter", "改行"),
        ("右Shift ×2", "次へ"),
        ("右Shift 長押し", "音声"),
        ("Esc", "閉じる"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("原文", systemImage: "doc.plaintext")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.draft.count) 文字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

            HStack(spacing: 8) {
                SettingsLink {
                    Label("設定", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("APIキーとモデルを設定します")

                Button {
                    showHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("使い方を表示します")
                .popover(isPresented: $showHelp, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("使い方").font(.headline)
                        ForEach(shortcuts, id: \.0) { key, action in
                            HStack(spacing: 8) {
                                Text(key)
                                    .font(.caption.monospaced())
                                    .frame(width: 96, alignment: .leading)
                                Text(action).font(.caption)
                            }
                        }
                    }
                    .padding(12)
                }

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
