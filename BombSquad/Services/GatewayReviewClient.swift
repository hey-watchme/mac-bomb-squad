import Foundation

/// One event of a streaming review (SSE from the gateway).
enum ReviewStreamEvent {
    /// An increment of `revised_text` as the model produces it.
    case delta(String)
    /// The fully parsed result; always the last event of a successful stream.
    case result(ReviewResult)
}

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

    /// Streaming review over SSE. Yields `delta` events with revised_text
    /// increments, then one `result` event; the first token typically arrives
    /// well under a second, which is what makes rich models feel instant.
    func reviewStream(
        draft: String,
        mode: ReviewMode,
        language: OutputLanguage,
        context: SituationalContext?,
        memory: MemoryInjection?
    ) async throws -> AsyncThrowingStream<ReviewStreamEvent, Error> {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ProviderError.emptyDraft }

        var request = try await api.authorizedRequest("ai/review")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("text/event-stream", forHTTPHeaderField: "accept")
        var body = requestBody(draft: trimmed, mode: mode, language: language, context: context, memory: memory)
        body["stream"] = true
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw ProviderError.http(status: -1, body: error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.http(status: -1, body: "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            // Error responses are plain JSON; read a bounded amount for the message.
            var data = Data()
            for try await byte in bytes {
                data.append(byte)
                if data.count > 4096 { break }
            }
            throw GatewayAPI.error(status: http.statusCode, data: data)
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                var eventName = ""
                do {
                    // The gateway sends exactly one `data:` line per event, so
                    // dispatch on the data line (no reliance on blank separators,
                    // which AsyncLineSequence may swallow).
                    for try await line in bytes.lines {
                        if line.hasPrefix("event:") {
                            eventName = line.dropFirst("event:".count)
                                .trimmingCharacters(in: .whitespaces)
                            continue
                        }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst("data:".count)
                            .trimmingCharacters(in: .whitespaces)
                        guard
                            let data = payload.data(using: .utf8),
                            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }

                        switch eventName {
                        case "delta":
                            if let text = root["text"] as? String, !text.isEmpty {
                                continuation.yield(.delta(text))
                            }
                        case "result":
                            GatewayAPI.captureQuota(fromResponseRoot: root)
                            guard let result = root["result"] else {
                                throw ProviderError.decoding("stream result had no payload")
                            }
                            let resultData = try JSONSerialization.data(withJSONObject: result)
                            let parsed = try JSONDecoder().decode(ReviewResult.self, from: resultData)
                            continuation.yield(.result(parsed))
                        case "error":
                            throw GatewayAPI.error(status: 502, data: data)
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
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
