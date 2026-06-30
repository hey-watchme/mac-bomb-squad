import SwiftUI

/// Settings: pick the review model and store each vendor's API key in the Keychain.
struct SettingsView: View {
    @AppStorage(AppSettings.selectedModelKey) private var selectedModelID = ReviewModel.defaultModel.id

    @StateObject private var authViewModel = AuthViewModel()
    @State private var openAIKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var groqKey: String = ""
    @State private var saved = false
    @State private var config = BombSquadConfig.snapshot()

    private var selectedModel: ReviewModel {
        ReviewModel.find(id: selectedModelID)
    }

    var body: some View {
        Form {
            Section("レビューモデル") {
                Picker("使用するモデル", selection: $selectedModelID) {
                    ForEach(ReviewModel.catalog) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                Text(selectedModel.hint)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Groq API") {
                SecureField(APIVendor.groq.keyPlaceholder, text: $groqKey)
                    .textFieldStyle(.roundedBorder)
            }

            Section("OpenAI API") {
                SecureField(APIVendor.openAI.keyPlaceholder, text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Claude API") {
                SecureField(APIVendor.anthropic.keyPlaceholder, text: $anthropicKey)
                    .textFieldStyle(.roundedBorder)
            }

            AuthView(viewModel: authViewModel, config: config)

            Section("Backend / Auth 準備") {
                configRow("Product API", entry: config.apiBaseURL)
                configRow("Supabase URL", entry: config.supabaseURL)
                configRow("Supabase anon key", entry: config.supabaseAnonKey)

                Text("値の読み取り順は `BombSquad.local.plist` → `ProcessInfo.environment` → `Info.plist` です。通常はリポジトリ直下の `BombSquad.local.plist` を使います。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Text("キーは Keychain に保存され、リポジトリやファイルには書き込まれません。設定したベンダーのモデルだけ利用できます。")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("保存") { save() }
                        .buttonStyle(.borderedProminent)
                    if saved {
                        Label("保存しました", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green).font(.caption)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
        .onAppear(perform: load)
        .onChange(of: openAIKey) { _, _ in saved = false }
        .onChange(of: anthropicKey) { _, _ in saved = false }
        .onChange(of: groqKey) { _, _ in saved = false }
    }

    private func load() {
        config = BombSquadConfig.snapshot()
        groqKey = KeychainStore.apiKey(account: APIVendor.groq.keychainAccount) ?? ""
        openAIKey = KeychainStore.apiKey(account: APIVendor.openAI.keychainAccount) ?? ""
        anthropicKey = KeychainStore.apiKey(account: APIVendor.anthropic.keychainAccount) ?? ""
    }

    private func save() {
        KeychainStore.saveAPIKey(groqKey, account: APIVendor.groq.keychainAccount)
        KeychainStore.saveAPIKey(openAIKey, account: APIVendor.openAI.keychainAccount)
        KeychainStore.saveAPIKey(anthropicKey, account: APIVendor.anthropic.keychainAccount)
        saved = true
    }

    @ViewBuilder
    private func configRow(_ title: String, entry: BombSquadConfig.Entry) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(entry.redactedValue)
                .font(.caption)
                .foregroundStyle(entry.isConfigured ? Color.secondary : .red)
                .textSelection(.enabled)
        }
        .help(entry.key)
    }
}
