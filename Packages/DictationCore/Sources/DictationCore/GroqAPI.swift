import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Builds requests for Groq's OpenAI-compatible API and decodes its responses.
/// Sending them is up to the caller, so all of this is testable without a network.
public enum GroqAPI {
    public static let baseURL = URL(string: "https://api.groq.com/openai/v1")!
    public static let keysPageURL = URL(string: "https://console.groq.com/keys")!

    // MARK: - Requests

    public static func transcriptionRequest(
        apiKey: String,
        audio: Data,
        fileName: String = "dictation.wav",
        mimeType: String = "audio/wav",
        model: String,
        language: String?,
        prompt: String?,
        boundary: String = "OpenWhisper-\(UUID().uuidString)"
    ) -> URLRequest {
        var form = MultipartForm(boundary: boundary)
        form.addField("model", model)
        form.addField("response_format", "json")
        form.addField("temperature", "0")
        if let language, !language.isEmpty { form.addField("language", language) }
        if let prompt, !prompt.isEmpty { form.addField("prompt", prompt) }
        form.addFile("file", fileName: fileName, mimeType: mimeType, data: audio)

        var request = authorizedRequest(path: "audio/transcriptions", apiKey: apiKey)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()
        request.timeoutInterval = 60
        return request
    }

    public static func chatRequest(apiKey: String, model: String, messages: [ChatMessage], temperature: Double = 0) throws -> URLRequest {
        var request = authorizedRequest(path: "chat/completions", apiKey: apiKey)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(model: model, messages: messages, temperature: temperature))
        request.timeoutInterval = 30
        return request
    }

    public static func modelsRequest(apiKey: String) -> URLRequest {
        var request = authorizedRequest(path: "models", apiKey: apiKey)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        return request
    }

    private static func authorizedRequest(path: String, apiKey: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.setValue("Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: - Responses

    public static func decodeTranscription(status: Int, data: Data) throws -> String {
        try checkStatus(status, data: data)
        do {
            return try JSONDecoder().decode(TranscriptionResponse.self, from: data).text
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw GroqError.invalidResponse
        }
    }

    public static func decodeChat(status: Int, data: Data) throws -> String {
        try checkStatus(status, data: data)
        guard let response = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = response.choices.first?.message.content
        else { throw GroqError.invalidResponse }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func decodeModels(status: Int, data: Data) throws -> [GroqModel] {
        try checkStatus(status, data: data)
        guard let response = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            throw GroqError.invalidResponse
        }
        return response.data.filter { $0.active ?? true }
    }

    /// Model ids that do speech-to-text.
    public static func transcriptionModelIDs(in models: [GroqModel]) -> [String] {
        models.map(\.id).filter { $0.localizedCaseInsensitiveContains("whisper") }.sorted()
    }

    /// Model ids that can plausibly clean up text: everything except speech, TTS and safety models.
    public static func chatModelIDs(in models: [GroqModel]) -> [String] {
        let excluded = ["whisper", "tts", "guard", "playai", "orpheus", "distil"]
        return models.map(\.id)
            .filter { id in !excluded.contains { id.localizedCaseInsensitiveContains($0) } }
            .sorted()
    }

    static func checkStatus(_ status: Int, data: Data) throws {
        guard !(200..<300).contains(status) else { return }
        throw error(status: status, data: data)
    }

    public static func error(status: Int, data: Data) -> GroqError {
        let body = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
        let message = body?.error.message ?? String(data: data, encoding: .utf8)?.prefix(200).description ?? ""
        let code = body?.error.code ?? ""
        switch status {
        case 401, 403:
            return .unauthorized
        case 404 where code == "model_not_found" || message.localizedCaseInsensitiveContains("model"):
            return .modelNotFound(message)
        case 413:
            return .audioTooLarge
        case 429:
            return .rateLimited(message)
        default:
            if code == "model_not_found" || code == "model_decommissioned" { return .modelNotFound(message) }
            return .server(status: status, message: message)
        }
    }

    // MARK: - Types

    public struct ChatMessage: Codable, Equatable, Sendable {
        public var role: String
        public var content: String
        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public struct GroqModel: Codable, Equatable, Sendable {
        public var id: String
        public var active: Bool?
        public init(id: String, active: Bool? = nil) {
            self.id = id
            self.active = active
        }
    }

    struct ChatRequest: Encodable {
        var model: String
        var messages: [ChatMessage]
        var temperature: Double
    }

    struct TranscriptionResponse: Decodable { var text: String }

    struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { var content: String? }
            var message: Message
        }
        var choices: [Choice]
    }

    struct ModelsResponse: Decodable { var data: [GroqModel] }

    struct ErrorEnvelope: Decodable {
        struct Body: Decodable {
            var message: String?
            var type: String?
            var code: String?
        }
        var error: Body
    }
}

public enum GroqError: Error, Equatable, LocalizedError, Sendable {
    case missingAPIKey
    case unauthorized
    case modelNotFound(String)
    case audioTooLarge
    case rateLimited(String)
    case server(status: Int, message: String)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey: "Add your Groq API key in Settings."
        case .unauthorized: "Groq rejected the API key. Check it in Settings."
        case .modelNotFound(let message): "Groq doesn't offer this model any more. Pick another one. (\(message))"
        case .audioTooLarge: "The recording is too long for Groq. Try a shorter dictation."
        case .rateLimited: "Groq rate limit reached. Wait a moment and try again."
        case .server(let status, let message): "Groq error \(status)\(message.isEmpty ? "" : ": \(message)")"
        case .invalidResponse: "Groq sent a response the app couldn't read."
        }
    }
}

/// A minimal multipart/form-data body builder.
struct MultipartForm {
    let boundary: String
    private var body = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(_ name: String, fileName: String, mimeType: String, data: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(data)
        append("\r\n")
    }

    func finalized() -> Data {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ string: String) {
        body.append(Data(string.utf8))
    }
}
