import SwiftUI

/// Which editor currently has focus. Drives the blue focus highlight and
/// determines which side gets deployed.
enum FocusField: Hashable {
    case draft     // left: original
    case revision  // right: review result
}

/// Root layout: staging on the left, review on the right.
/// The split mirrors the "staging → live" deploy metaphor.
struct ContentView: View {
    @StateObject private var viewModel: ReviewViewModel

    /// Defaults to a clipboard-deploying view model (standalone window). The
    /// hotkey panel injects a `PasteDeployer`-backed one.
    @MainActor
    init() {
        _viewModel = StateObject(wrappedValue: ReviewViewModel())
    }

    @MainActor
    init(viewModel: @autoclosure @escaping () -> ReviewViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        Group {
            if viewModel.sessionKind == .vision {
                VisionPanelView(viewModel: viewModel)
                    .frame(minWidth: 760, minHeight: 520)
            } else {
                HSplitView {
                    StagingEditorView(viewModel: viewModel, focusedField: $viewModel.focusedField)
                        .frame(minWidth: 360, idealWidth: 440)
                    ReviewPanelView(viewModel: viewModel, focusedField: $viewModel.focusedField)
                        .frame(minWidth: 380, idealWidth: 460)
                }
                .frame(minWidth: 820, minHeight: 560)
            }
        }
        .onAppear {
            // Defer so the panel is key before focusing the original editor.
            DispatchQueue.main.async {
                if viewModel.sessionKind == .text {
                    viewModel.focusedField = .draft
                }
            }
        }
    }
}
