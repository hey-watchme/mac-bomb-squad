import Foundation

/// `ReviewProvider` backed by the product gateway (docs/api-contract.md).
/// This is the production path: no LLM provider keys on the device, the
/// server owns prompts/model routing, and usage is metered per tenant.
/// The BYOK clients remain as a developer fallback when no gateway URL is
/// configured.
struct GatewayReviewClient: ReviewProvider {
    private let baseURL: URL
    private let session: URLSession

    /// Usable only when the gateway URL is configured and a user is signed in.
    static func make() -> GatewayReviewClient? {
        let config = BombSquadConfig.snapshot()
        guard
            let raw = config.apiBaseURL.value?.trimmingCharacters(in: .whitespacesAndNewlines),
            !raw.isEmpty,
            let url = URL(string: raw),
            BombSquadAuthClient.shared.currentSession() != nil
        else { return nil }
        return GatewayReviewClient(baseURL: url)
    }

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func review(
        draft: String,
        mode: ReviewMode,
        language: OutputLanguage,
        context: SituationalContext?,
        memory: MemoryInjection?
    ) async throws -> ReviewResult {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProviderError.emptyDraft }

        let token = try await BombSquadAuthClient.shared.accessToken()

        var request = URLRequest(url: reviewEndpoint())
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: requestBody(draft: trimmed, mode: mode, language: language, context: context, memory: memory)
        )

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProviderError.http(status: -1, body: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.http(status: -1, body: "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw gatewayError(status: http.statusCode, data: data)
        }

        return try decodeResult(from: data)
    }

    // MARK: - Request

    /// `BOMB_SQUAD_API_BASE_URL` may or may not include the `/api` base path.
    private func reviewEndpoint() -> URL {
        let path = baseURL.path.hasSuffix("/api") ? "ai/review" : "api/ai/review"
        return baseURL.appendingPathComponent(path)
    }

    private func requestBody(
        draft: String,
        mode: ReviewMode,
        language: OutputLanguage,
        context: SituationalContext?,
        memory: MemoryInjection?
    ) -> [String: Any] {
        var input: [String: Any] = ["draft": draft]
        if let context {
            var contextPayload: [String: Any] = ["app_name": context.appName]
            if let title = context.windowTitle { contextPayload["window_title"] = title }
            if let excerpt = context.conversationExcerpt { contextPayload["conversation_excerpt"] = excerpt }
            input["context"] = contextPayload
        }
        if let memory {
            var memoryPayload: [String: Any] = [:]
            if let persona = memory.personaMD { memoryPayload["persona_md"] = persona }
            if let subject = memory.relationshipSubject { memoryPayload["relationship_subject"] = subject }
            if let relationship = memory.relationshipMD { memoryPayload["relationship_md"] = relationship }
            if !memoryPayload.isEmpty { input["memory"] = memoryPayload }
        }

        let bundle = Bundle.main
        return [
            "request_id": UUID().uuidString,
            "operation": "review",
            "mode": mode == .transform ? "transform" : "compose",
            "input": input,
            "preferences": [
                "output_language": language.rawValue,
            ],
            "client": [
                "platform": "macos",
                "app_version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0",
                "build_number": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0",
            ],
        ]
    }

    // MARK: - Response

    private func decodeResult(from data: Data) throws -> ReviewResult {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = root["result"]
        else {
            throw ProviderError.decoding("unexpected gateway response shape")
        }
        do {
            let resultData = try JSONSerialization.data(withJSONObject: result)
            return try JSONDecoder().decode(ReviewResult.self, from: resultData)
        } catch {
            throw ProviderError.decoding(error.localizedDescription)
        }
    }

    /// Maps the gateway error contract to user-facing messages.
    private func gatewayError(status: Int, data: Data) -> Error {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errorObject = root["error"] as? [String: Any],
            let code = errorObject["code"] as? String
        else {
            let body = String(data: data, encoding: .utf8) ?? ""
            return ProviderError.http(status: status, body: String(body.prefix(500)))
        }

        let message: String
        switch code {
        case "UNAUTHENTICATED":
            message = "ログインの有効期限が切れました。アカウントから再ログインしてください。"
        case "QUOTA_EXCEEDED":
            message = "今月の利用枠を使い切りました。来月のリセットをお待ちいただくか、プランをご検討ください。"
        case "PAYMENT_REQUIRED":
            message = "現在のプランではこの操作を利用できません。"
        case "PROVIDER_ERROR":
            // The gateway already produces a user-facing Japanese message
            // (rate-limit guidance vs. generic failure); show it as-is.
            message = (errorObject["message"] as? String)
                ?? "AI エンジン側で一時的なエラーが発生しました。少し待ってから再試行してください。"
        default:
            message = (errorObject["message"] as? String) ?? "サーバーエラーが発生しました。"
        }
        return ProviderError.gateway(message: message)
    }
}
