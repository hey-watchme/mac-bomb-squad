import Foundation

/// LLM calls that build and grow memory cards. Uses the Groq OpenAI-compatible
/// endpoint with the default high-quality model — memory work happens off the
/// review hot path, so a missing key or a failed call must never surface as a
/// user-facing error (except in the explicit bootstrap flow, which reports).
///
/// M3 moves these calls behind the Gateway; keep this surface small.
enum MemoryDistiller {
    private static let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!
    private static let modelID = "openai/gpt-oss-120b"

    enum DistillerError: LocalizedError {
        case missingAPIKey
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "Groq API キーが未設定です。設定から登録してください。"
            case .badResponse(let detail):
                return "プロファイル生成に失敗しました: \(detail)"
            }
        }
    }

    // MARK: - Bootstrap (onboarding)

    /// Generate a persona card from pasted past messages. Throws so the
    /// onboarding UI can show what went wrong.
    static func generatePersonaCard(fromSamples samples: String) async throws -> String {
        let user = "以下はユーザーが過去に実際に送ったメッセージのサンプルです。スタイルプロファイルを作成してください。\n\n\(samples)"
        let content = try await chat(system: PersonaPrompt.bootstrapSystem, user: user, jsonMode: false)
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DistillerError.badResponse("empty result") }
        return trimmed
    }

    // MARK: - Post-deploy distillation

    /// Observe one deploy (original → suggestion → final) and append any
    /// high-confidence notes to the memory cards. Fire-and-forget: failures
    /// are logged, never shown.
    static func distillAfterDeploy(
        original: String,
        suggestion: String,
        final: String,
        context: SituationalContext?
    ) async {
        do {
            let user = PersonaPrompt.distillUser(
                original: original, suggestion: suggestion, final: final, context: context
            )
            let content = try await chat(system: PersonaPrompt.distillSystem, user: user, jsonMode: true)
            guard
                let jsonData = extractJSON(from: content),
                let root = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
            else { return }

            if let note = nonEmptyString(root["persona_note"]) {
                try await MemoryStore.shared.appendPersonaNote(note)
            }
            if let subject = nonEmptyString(root["relationship_subject"]),
               let note = nonEmptyString(root["relationship_note"]) {
                try await MemoryStore.shared.appendRelationshipNote(subject: subject, note: note)
            }
        } catch {
            NSLog("BombSquad memory distillation skipped: \(error.localizedDescription)")
        }
    }

    // MARK: - Shared chat call

    private static func chat(system: String, user: String, jsonMode: Bool) async throws -> String {
        guard let apiKey = KeychainStore.apiKey(account: APIVendor.groq.keychainAccount) else {
            throw DistillerError.missingAPIKey
        }

        var body: [String: Any] = [
            "model": modelID,
            "max_tokens": 2048,
            "reasoning_effort": "low",
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        if jsonMode {
            body["response_format"] = ["type": "json_object"]
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DistillerError.badResponse("HTTP \(status) \(String(body.prefix(200)))")
        }

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw DistillerError.badResponse("unexpected response shape")
        }
        return content
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.lowercased() == "null" ? nil : trimmed
    }

    /// Tolerates reasoning blocks or stray prose around the JSON object.
    private static func extractJSON(from raw: String) -> Data? {
        var text = raw
        if let thinkEnd = text.range(of: "</think>", options: .backwards) {
            text = String(text[thinkEnd.upperBound...])
        }
        guard
            let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}"),
            start <= end
        else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }
}
