import Foundation

/// Speech-to-text via Groq's OpenAI-compatible audio transcription endpoint.
/// BYOK developer fallback; the production path is GatewayTranscriber.
struct GroqTranscriber: Transcriber {
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private let model = "whisper-large-v3"

    func transcribe(fileURL: URL) async throws -> String {
        guard let apiKey = KeychainStore.apiKey(account: APIVendor.groq.keychainAccount) else {
            throw ProviderError.missingAPIKey
        }
        let audioData = try Data(contentsOf: fileURL)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, audioData: audioData)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.http(status: -1, body: "no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ProviderError.http(status: http.statusCode, body: String(body.prefix(500)))
        }

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.decoding("transcription response was not JSON")
        }

        // verbose_json returns per-segment confidence. Drop segments that look
        // like silence-driven hallucinations, then rebuild the text from what's
        // left. Fall back to the top-level text if no segments are present.
        if let segments = root["segments"] as? [[String: Any]] {
            let kept = segments.filter { !Self.isHallucinated($0) }
            let rebuilt = kept
                .compactMap { $0["text"] as? String }
                .joined()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rebuilt
        }

        guard let text = root["text"] as? String else {
            throw ProviderError.decoding("transcription response had no text")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whisper's own silence heuristic plus a repetition guard. A segment is
    /// treated as a hallucination when the model is both confident there is no
    /// speech and uncertain about its tokens, or when the output is degenerate
    /// (highly repetitive text compresses far more than natural language).
    private static func isHallucinated(_ segment: [String: Any]) -> Bool {
        let noSpeechProb = (segment["no_speech_prob"] as? Double) ?? 0
        let avgLogprob = (segment["avg_logprob"] as? Double) ?? 0
        let compressionRatio = (segment["compression_ratio"] as? Double) ?? 0
        if noSpeechProb > 0.6 && avgLogprob < -1.0 { return true }
        if compressionRatio > 2.4 { return true }
        return false
    }

    private func multipartBody(boundary: String, audioData: Data) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("model", model)
        field("temperature", "0")
        // verbose_json gives per-segment confidence used to filter hallucinations.
        field("response_format", "verbose_json")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
