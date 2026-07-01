import Foundation

struct OpenAIVisionClient: VisionProvider {
    private let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    private let model: String
    private let fallbackModel = "gpt-4.1-mini"
    private let session: URLSession

    init(model: String = AppSettings.selectedVisionModelID(), session: URLSession = .shared) {
        self.model = model
        self.session = session
    }

    func interpret(
        imageURL: URL,
        instruction: String?,
        language: OutputLanguage
    ) async throws -> VisionInterpretationResult {
        guard let apiKey = KeychainStore.apiKey(account: APIVendor.openAI.keychainAccount) else {
            throw ProviderError.missingAPIKey
        }

        let imageData = try Data(contentsOf: imageURL)
        let dataURL = "data:image/png;base64,\(imageData.base64EncodedString())"
        let models = [model, fallbackModel].reduce(into: [String]()) { result, item in
            if !result.contains(item) { result.append(item) }
        }

        var lastError: Error?
        for candidate in models {
            do {
                var result = try await requestInterpretation(
                    model: candidate,
                    apiKey: apiKey,
                    imageDataURL: dataURL,
                    instruction: instruction,
                    language: language
                )
                result.modelID = candidate
                return result
            } catch {
                lastError = error
                if case ProviderError.http(let status, _) = error,
                   (status == 400 || status == 404),
                   candidate != models.last {
                    continue
                }
                throw error
            }
        }

        throw lastError ?? ProviderError.noStructuredOutput
    }

    private func requestInterpretation(
        model: String,
        apiKey: String,
        imageDataURL: String,
        instruction: String?,
        language: OutputLanguage
    ) async throws -> VisionInterpretationResult {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody(
            model: model,
            imageDataURL: imageDataURL,
            instruction: instruction,
            language: language
        ))

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
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.http(status: http.statusCode, body: String(body.prefix(500)))
        }

        return try decodeResult(from: data)
    }

    private func requestBody(
        model: String,
        imageDataURL: String,
        instruction: String?,
        language: OutputLanguage
    ) -> [String: Any] {
        let userInstruction = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = userInstruction?.isEmpty == false
            ? userInstruction!
            : "このスクリーンショットを読み取り、ユーザーが次に何をすればよいか分かるように説明してください。"

        return [
            "model": model,
            "max_output_tokens": 2048,
            "input": [
                [
                    "role": "developer",
                    "content": [
                        [
                            "type": "input_text",
                            "text": Self.systemPrompt(language: language),
                        ],
                    ],
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": task,
                        ],
                        [
                            "type": "input_image",
                            "image_url": imageDataURL,
                            "detail": "auto",
                        ],
                    ],
                ],
            ],
        ]
    }

    private static func systemPrompt(language: OutputLanguage) -> String {
        """
        You help the user understand the current computer screen.
        Describe only what can be inferred from the screenshot.
        Extract important visible text.
        Explain the likely meaning for a non-expert user.
        List concrete next actions.
        Call out uncertainty instead of guessing.
        Return exactly one JSON object. Do not wrap it in Markdown.
        The JSON keys must be: summary, visible_text, interpretation, suggested_actions, uncertainties.
        All values must be written in \(language.promptName).
        """
    }

    private func decodeResult(from data: Data) throws -> VisionInterpretationResult {
        guard let outputText = Self.outputText(from: data),
              let jsonData = Self.extractJSON(from: outputText)
        else {
            throw ProviderError.noStructuredOutput
        }

        do {
            return try VisionInterpretationResult.decodeFlexible(from: jsonData)
        } catch {
            throw ProviderError.decoding(error.localizedDescription)
        }
    }

    private static func outputText(from data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let text = root["output_text"] as? String {
            return text
        }

        guard let output = root["output"] as? [[String: Any]] else { return nil }
        for item in output where item["type"] as? String == "message" {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for part in content {
                if part["type"] as? String == "output_text",
                   let text = part["text"] as? String {
                    return text
                }
            }
        }
        return nil
    }

    private static func extractJSON(from raw: String) -> Data? {
        guard
            let start = raw.firstIndex(of: "{"),
            let end = raw.lastIndex(of: "}"),
            start <= end
        else { return nil }
        return String(raw[start...end]).data(using: .utf8)
    }
}
