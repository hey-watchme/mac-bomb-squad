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
        ("右Shift ×2", "起動 / レビュー / 画面"),
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

            if let context = viewModel.situationalContext, !viewModel.isContextExcluded {
                SituationalContextChip(context: context) {
                    viewModel.excludeContext()
                }
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

            if viewModel.needsScreenCapturePermission {
                ScreenCapturePermissionBanner()
            }

            HStack(spacing: 8) {
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

                Button {
                    NotificationCenter.default.post(name: .captureScreenshot, object: nil)
                } label: {
                    Image(systemName: "camera.viewfinder")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .disabled(viewModel.isCapturingScreenshot)
                .help("ビジョン入力としてスクリーンショットを撮影します")

                if viewModel.isRecording {
                    Image(systemName: "mic.fill").foregroundStyle(.red)
                    Text("録音中…").font(.caption).foregroundStyle(.secondary)
                } else if viewModel.isTranscribing {
                    ProgressView().controlSize(.small)
                    Text("文字起こし中…").font(.caption).foregroundStyle(.secondary)
                } else if viewModel.isCapturingScreenshot {
                    ProgressView().controlSize(.small)
                    Text("スクショ中…").font(.caption).foregroundStyle(.secondary)
                } else if viewModel.isLoading {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button {
                    Task { await viewModel.runReview() }
                } label: {
                    Label("レビュー", systemImage: "checkmark.shield")
                }
                .disabled(!viewModel.canReview)
                .help("原文をレビューします")

                Button {
                    viewModel.deployDraft()
                } label: {
                    Label("送信", systemImage: "paperplane.fill")
                }
                .disabled(!viewModel.canDeployDraft)
                .buttonStyle(.borderedProminent)
                .help("レビューを使わず、原文のまま送信先へ入力します")
            }
        }
        .padding()
    }
}

/// L1 context chip: shows which screen the review will reference. Click to
/// inspect exactly what was captured; ✕ excludes it for this session. Making
/// the captured text inspectable/removable is a privacy commitment, not a
/// nicety.
private struct SituationalContextChip: View {
    let context: SituationalContext
    let onExclude: () -> Void
    @State private var showDetail = false

    var body: some View {
        HStack(spacing: 6) {
            Button {
                showDetail.toggle()
            } label: {
                Label(context.chipLabel, systemImage: "paperclip")
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .buttonStyle(.plain)
            .help("この画面の内容をレビューの参考にします。クリックで内容を確認")
            .popover(isPresented: $showDetail, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("参照中の周辺コンテクスト").font(.headline)
                    Text(context.chipLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let excerpt = context.conversationExcerpt, !excerpt.isEmpty {
                        ScrollView {
                            Text(excerpt)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(width: 380, height: 220)
                    } else {
                        Text("画面のテキストは読み取れませんでした。アプリ名とウィンドウ名だけを参考にします。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 380, alignment: .leading)
                    }
                    Text("この情報は保存されず、このセッションのレビューにだけ使われます。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
            }

            Button {
                onExclude()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("このセッションでは周辺コンテクストを使いません")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.6), in: Capsule())
    }
}

private struct ScreenCapturePermissionBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.slash")
                .foregroundStyle(.orange)
            Text("スクリーンショットには画面収録の許可が必要です。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button {
                NotificationCenter.default.post(name: .openScreenCaptureSettings, object: nil)
            } label: {
                Label("設定を開く", systemImage: "gearshape")
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
