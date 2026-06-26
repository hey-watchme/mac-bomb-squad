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
    @FocusState private var focus: FocusField?

    /// Defaults to a clipboard-deploying view model (standalone window). The
    /// hotkey panel injects a `PasteDeployer`-backed one.
    init(viewModel: @autoclosure @escaping () -> ReviewViewModel = ReviewViewModel()) {
        _viewModel = StateObject(wrappedValue: viewModel())
    }

    var body: some View {
        HSplitView {
            StagingEditorView(viewModel: viewModel, focus: $focus)
                .frame(minWidth: 360, idealWidth: 440)
            ReviewPanelView(viewModel: viewModel, focus: $focus)
                .frame(minWidth: 380, idealWidth: 460)
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            // Defer so the panel is key before focusing the original editor.
            DispatchQueue.main.async { focus = .draft }
        }
        .onChange(of: viewModel.result) { _, newValue in
            // After a review, the result becomes the thing to deploy → focus it.
            if newValue != nil { focus = .revision }
        }
    }
}
