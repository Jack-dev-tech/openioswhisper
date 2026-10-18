import XCTest
@testable import DictationCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GroqAPITests: XCTestCase {
    func testTranscriptionRequestIsMultipartWithAllFields() throws {
        let audio = Data([0x01, 0x02, 0x03])
        let request = GroqAPI.transcriptionRequest(
            apiKey: "  gsk_test \n", audio: audio, model: "whisper-large-v3-turbo",
            language: "en", prompt: "OpenWhisper, Groq", boundary: "BOUNDARY"
        )

        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gsk_test")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "multipart/form-data; boundary=BOUNDARY")

        let body = try XCTUnwrap(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"model\"\r\n\r\nwhisper-large-v3-turbo\r\n"))
        XCTAssertTrue(text.contains("name=\"language\"\r\n\r\nen\r\n"))
        XCTAssertTrue(text.contains("name=\"prompt\"\r\n\r\nOpenWhisper, Groq\r\n"))
        XCTAssertTrue(text.contains("name=\"response_format\"\r\n\r\njson\r\n"))
        XCTAssertTrue(text.contains("name=\"file\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n"))
        XCTAssertTrue(text.hasSuffix("--BOUNDARY--\r\n"))
        XCTAssertNotNil(body.range(of: audio))
    }

    func testAutoLanguageAndEmptyPromptAreOmitted() throws {
        let request = GroqAPI.transcriptionRequest(apiKey: "k", audio: Data(), model: "m", language: nil, prompt: "", boundary: "B")
        let text = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)
        XCTAssertFalse(text.contains("name=\"language\""))
        XCTAssertFalse(text.contains("name=\"prompt\""))
    }

    func testChatRequestEncodesJSON() throws {
        let request = try GroqAPI.chatRequest(apiKey: "k", model: "llama", messages: [.init(role: "user", content: "hi")])
        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/chat/completions")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "llama")
        XCTAssertEqual((json["messages"] as? [[String: String]])?.first?["content"], "hi")
    }

    func testDecodesTranscription() throws {
        let data = Data(#"{"text":"  Hello there. ","x_groq":{"id":"req"}}"#.utf8)
        XCTAssertEqual(try GroqAPI.decodeTranscription(status: 200, data: data), "Hello there.")
    }

    func testDecodesChat() throws {
        let data = Data(#"{"choices":[{"index":0,"message":{"role":"assistant","content":"Clean."}}]}"#.utf8)
        XCTAssertEqual(try GroqAPI.decodeChat(status: 200, data: data), "Clean.")
    }

    func testMapsErrors() {
        let unauthorized = Data(#"{"error":{"message":"Invalid API Key","type":"invalid_request_error","code":"invalid_api_key"}}"#.utf8)
        XCTAssertEqual(GroqAPI.error(status: 401, data: unauthorized), .unauthorized)

        let missing = Data(#"{"error":{"message":"The model `x` does not exist","code":"model_not_found"}}"#.utf8)
        XCTAssertEqual(GroqAPI.error(status: 404, data: missing), .modelNotFound("The model `x` does not exist"))

        let decommissioned = Data(#"{"error":{"message":"gone","code":"model_decommissioned"}}"#.utf8)
        XCTAssertEqual(GroqAPI.error(status: 400, data: decommissioned), .modelNotFound("gone"))

        XCTAssertEqual(GroqAPI.error(status: 413, data: Data()), .audioTooLarge)
        XCTAssertEqual(GroqAPI.error(status: 500, data: Data("oops".utf8)), .server(status: 500, message: "oops"))
        XCTAssertThrowsError(try GroqAPI.decodeTranscription(status: 429, data: Data())) { error in
            XCTAssertEqual(error as? GroqError, .rateLimited(""))
        }
    }

    func testSplitsModelsIntoTranscriptionAndChat() throws {
        let data = Data("""
        {"object":"list","data":[
          {"id":"whisper-large-v3","active":true},
          {"id":"whisper-large-v3-turbo","active":true},
          {"id":"llama-3.1-8b-instant","active":true},
          {"id":"meta-llama/llama-guard-4-12b","active":true},
          {"id":"playai-tts","active":true},
          {"id":"old-model","active":false}
        ]}
        """.utf8)
        let models = try GroqAPI.decodeModels(status: 200, data: data)
        XCTAssertEqual(GroqAPI.transcriptionModelIDs(in: models), ["whisper-large-v3", "whisper-large-v3-turbo"])
        XCTAssertEqual(GroqAPI.chatModelIDs(in: models), ["llama-3.1-8b-instant"])
    }
}
