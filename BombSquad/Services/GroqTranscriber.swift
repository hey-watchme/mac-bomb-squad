import Foundation

/// Speech-to-text via Groq's OpenAI-compatible audio transcription endpoint.
/// MVP uses whisper-large-v3; an ASR model catalog can come later.
struct GroqTranscriber {
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

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = root["text"] as? String
        else {
            throw ProviderError.decoding("transcription response had no text")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        field("response_format", "json")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
