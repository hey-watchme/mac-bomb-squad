import Foundation

/// Speech-to-text abstraction: the gateway proxy is the production path,
/// the BYOK Groq client remains as a developer fallback.
protocol Transcriber {
    func transcribe(fileURL: URL) async throws -> String
}

/// ASR via the product gateway (POST /api/ai/transcribe). The server owns the
/// Groq key and the hallucination filter; usage is metered per tenant.
struct GatewayTranscriber: Transcriber {
    private let api: GatewayAPI
    private let session: URLSession

    static func make() -> GatewayTranscriber? {
        guard let api = GatewayAPI.make() else { return nil }
        return GatewayTranscriber(api: api)
    }

    init(api: GatewayAPI, session: URLSession = .shared) {
        self.api = api
        self.session = session
    }

    func transcribe(fileURL: URL) async throws -> String {
        let audioData = try Data(contentsOf: fileURL)

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try await api.authorizedRequest("ai/transcribe")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(boundary: boundary, audioData: audioData)

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

        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let result = root["result"] as? [String: Any],
            let text = result["text"] as? String
        else {
            throw ProviderError.decoding("unexpected gateway response shape")
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
        let client = GatewayAPI.clientPayload()
        field("request_id", UUID().uuidString)
        field("platform", client["platform"] as? String ?? "macos")
        field("app_version", client["app_version"] as? String ?? "0")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
