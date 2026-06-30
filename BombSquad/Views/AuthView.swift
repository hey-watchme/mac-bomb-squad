import SwiftUI

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel
    let config: BombSquadConfig.Snapshot

    var body: some View {
        Section("アカウント") {
            if config.hasSupabaseConfig {
                if viewModel.hasSession {
                    LabeledContent("ログイン状態", value: "ログイン済み")
                    if let email = viewModel.accountSummary?.email ?? viewModel.signedInEmail {
                        LabeledContent("メール", value: email)
                    }
                    if let authMethodLabel = viewModel.authMethodLabel {
                        LabeledContent("ログイン方法", value: authMethodLabel)
                    }
                    if let summary = viewModel.accountSummary {
                        LabeledContent("アカウント種別", value: summary.tier.label)
                        LabeledContent("契約状態", value: summary.state.label)
                        LabeledContent("月間レビュー枠", value: "\(summary.monthlyReviewLimit) 回")
                    }
                    if let tenantID = viewModel.accountSummary?.tenantID ?? viewModel.tenantID {
                        LabeledContent("テナント", value: redact(tenantID.uuidString))
                    }
                    Button("ログアウト", action: viewModel.signOut)
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isBusy)
                } else {
                    LabeledContent("ログイン状態", value: "未ログイン")
                    Text("Bomb Squad を使うにはログインが必要です。初回登録はフリーアカウントから始まります。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Google で続ける", action: viewModel.signInWithGoogle)
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canSignInWithGoogle)

                    Text("またはメールアドレスでログイン")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("メールアドレス", text: $viewModel.email)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isBusy)

                    Button("メールリンクを送信", action: viewModel.sendMagicLink)
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canSendMagicLink)
                }

                if let statusMessage = viewModel.statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }

                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Supabase の URL と anon key を設定すると、ここから Bomb Squad アカウントでログインできます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func redact(_ value: String) -> String {
        if value.count <= 12 { return value }
        return "\(value.prefix(8))...\(value.suffix(4))"
    }
}
