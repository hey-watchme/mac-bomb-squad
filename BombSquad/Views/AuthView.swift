import SwiftUI

struct AuthView: View {
    @ObservedObject var viewModel: AuthViewModel
    let config: BombSquadConfig.Snapshot

    var body: some View {
        Section("アカウント") {
            if config.hasSupabaseConfig {
                if viewModel.hasSession {
                    LabeledContent("ログイン状態", value: "ログイン済み")
                    if let email = viewModel.signedInEmail {
                        LabeledContent("メール", value: email)
                    }
                    if let tenantID = viewModel.tenantID {
                        LabeledContent("テナント", value: redact(tenantID.uuidString))
                    }
                    Button("ログアウト", action: viewModel.signOut)
                        .buttonStyle(.bordered)
                        .disabled(viewModel.isBusy)
                } else {
                    LabeledContent("ログイン状態", value: "未ログイン")
                }

                TextField("メールアドレス", text: $viewModel.email)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isBusy)

                HStack {
                    TextField("認証コード", text: $viewModel.verificationCode)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isBusy)

                    Button("コード送信", action: viewModel.sendCode)
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.canSendCode)

                    Button("ログイン", action: viewModel.verifyCode)
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canVerifyCode)
                }

                Text("まずはメールOTPを実装しています。Google / Apple は callback URL と配布導線を固めた段階で追加します。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
