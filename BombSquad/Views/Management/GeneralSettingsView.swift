import SwiftUI

/// App configuration: review model selection, per-vendor API keys, and the
/// read-only backend/auth config snapshot. Account sign-in lives in `AccountView`;
/// this section is purely technical settings.
struct GeneralSettingsView: View {
    @AppStorage(AppSettings.selectedModelKey) private var selectedModelID = ReviewModel.defaultModel.id
    @AppStorage(AppSettings.isHistoryEnabledKey) private var isHistoryEnabled = true

    let config: BombSquadConfig.Snapshot
    @State private var openAIKey: String = ""
    @State private var anthropicKey: String = ""
    @State private var groqKey: String = ""
    @State private var saved = false

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

            Section("Backend / Auth") {
                configRow("Product API", entry: config.apiBaseURL)
                configRow("Supabase URL", entry: config.supabaseURL)
                configRow("Supabase anon key", entry: config.supabaseAnonKey)

                Text("値の読み取り順は `BombSquad.local.plist` → `ProcessInfo.environment` → `Info.plist` です。通常はリポジトリ直下の `BombSquad.local.plist` を使います。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("履歴") {
                Toggle("ローカル履歴を保存", isOn: $isHistoryEnabled)
                Text("現在の履歴はこの Mac の SQLite にだけ保存します。クラウド同期はまだ行いません。保存上限は最新 \(AppSettings.localHistoryLimit) 件です。")
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
        .navigationTitle("設定")
        .onAppear(perform: load)
        .onChange(of: openAIKey) { _, _ in saved = false }
        .onChange(of: anthropicKey) { _, _ in saved = false }
        .onChange(of: groqKey) { _, _ in saved = false }
    }

    private func load() {
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
