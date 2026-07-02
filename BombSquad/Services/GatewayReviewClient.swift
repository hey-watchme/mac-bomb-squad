import Foundation

/// `ReviewProvider` backed by the product gateway (docs/api-contract.md).
/// This is the production path: no LLM provider keys on the device, the
/// server owns prompts/model routing, and usage is metered per tenant.
/// The BYOK clients remain as a developer fallback when no gateway URL is
/// configured.
struct GatewayReviewClient: ReviewProvider {
    private let api: GatewayAPI
    private let session: URLSession

    /// Usable only when the gateway URL is configured and a user is signed in.
    static func make() -> GatewayReviewClient? {
        guard let api = GatewayAPI.make() else { return nil }
        return GatewayReviewClient(api: api)
    }

    init(api: GatewayAPI, session: URLSession = .shared) {
        self.api = api
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

        var request = try await api.authorizedRequest("ai/review")
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
            throw GatewayAPI.error(status: http.statusCode, data: data)
        }

        return try decodeResult(from: data)
    }

    // MARK: - Request

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

        return [
            "request_id": UUID().uuidString,
            "operation": "review",
            "mode": mode == .transform ? "transform" : "compose",
            "input": input,
            "preferences": [
                "output_language": language.rawValue,
            ],
            "client": GatewayAPI.clientPayload(),
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
        GatewayAPI.captureQuota(fromResponseRoot: root)
        do {
            let resultData = try JSONSerialization.data(withJSONObject: result)
            return try JSONDecoder().decode(ReviewResult.self, from: resultData)
        } catch {
            throw ProviderError.decoding(error.localizedDescription)
        }
    }
}
