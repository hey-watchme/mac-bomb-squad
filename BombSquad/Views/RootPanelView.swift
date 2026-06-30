import SwiftUI

struct RootPanelView: View {
    @StateObject private var authViewModel = AuthViewModel()
    @ObservedObject var reviewViewModel: ReviewViewModel
    let config: BombSquadConfig.Snapshot
    @State private var didAutoReviewAfterLogin = false

    init(
        reviewViewModel: ReviewViewModel,
        config: BombSquadConfig.Snapshot = BombSquadConfig.snapshot()
    ) {
        self.reviewViewModel = reviewViewModel
        self.config = config
    }

    var body: some View {
        Group {
            if authViewModel.hasSession {
                ContentView(viewModel: reviewViewModel)
            } else {
                LoginRequiredView(viewModel: authViewModel, config: config)
            }
        }
        .onChange(of: authViewModel.hasSession) { _, isLoggedIn in
            guard isLoggedIn else { return }
            guard reviewViewModel.mode == .transform else { return }
            guard reviewViewModel.result == nil else { return }
            guard !reviewViewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            guard !didAutoReviewAfterLogin else { return }

            didAutoReviewAfterLogin = true
            Task { await reviewViewModel.runReview() }
        }
    }
}
