import SwiftUI

/// Settings: pick the review model and store each vendor's API key in the Keychain.
struct SettingsView: View {
    @AppStorage(AppSettings.selectedModelKey) private var selectedModelID = ReviewModel.defaultModel.id

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
        .frame(width: 460, height: 460)
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
}
