import SwiftUI

struct LoginRequiredView: View {
    @ObservedObject var viewModel: AuthViewModel
    let config: BombSquadConfig.Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Bomb Squad を使うにはログインが必要です")
                    .font(.title2.weight(.semibold))
                Text("最初の利用はフリーアカウントから始まります。Google またはメールリンクでログインしてください。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Form {
                AuthView(viewModel: viewModel, config: config)
            }
            .formStyle(.grouped)

            if viewModel.hasSession {
                Text("ログインが完了しました。このまま入力ウィンドウを利用できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 420)
    }
}
