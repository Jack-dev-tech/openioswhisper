import DictationCore
import Foundation

/// Sends `GroqAPI` requests.
struct GroqClient: Sendable {
    var session: URLSession = .shared

    func transcribe(wav: Data, apiKey: String, model: String, language: String?, prompt: String?) async throws -> String {
        let request = GroqAPI.transcriptionRequest(apiKey: apiKey, audio: wav, model: model, language: language, prompt: prompt)
        let (data, status) = try await send(request)
        return try GroqAPI.decodeTranscription(status: status, data: data)
    }

    func clean(_ transcript: String, apiKey: String, model: String, vocabulary: String?) async throws -> String {
        let request = try GroqAPI.chatRequest(apiKey: apiKey, model: model, messages: CleanupPrompt.messages(for: transcript, vocabulary: vocabulary))
        let (data, status) = try await send(request)
        return CleanupPrompt.accept(cleaned: try GroqAPI.decodeChat(status: status, data: data), raw: transcript)
    }

    func models(apiKey: String) async throws -> [GroqAPI.GroqModel] {
        let (data, status) = try await send(GroqAPI.modelsRequest(apiKey: apiKey))
        return try GroqAPI.decodeModels(status: status, data: data)
    }

    private func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GroqError.invalidResponse }
        return (data, http.statusCode)
    }
}
