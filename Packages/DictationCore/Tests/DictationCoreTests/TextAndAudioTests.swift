import XCTest
@testable import DictationCore

final class TextAndAudioTests: XCTestCase {
    func testVocabularyPromptJoinsTerms() {
        XCTAssertNil(VocabularyPrompt.make(from: "  \n , "))
        XCTAssertEqual(VocabularyPrompt.make(from: "Groq\nWhisperKit, SwiftUI\n\n  Matsuzaki "), "Groq, WhisperKit, SwiftUI, Matsuzaki")
    }

    func testVocabularyPromptStopsAtLimit() {
        XCTAssertEqual(VocabularyPrompt.make(from: "alpha, beta, gamma", maxCharacters: 12), "alpha, beta")
        XCTAssertEqual(VocabularyPrompt.make(from: "one very long term", maxCharacters: 10), "one very")
    }

    func testCleanupMessagesIncludeVocabulary() {
        let messages = CleanupPrompt.messages(for: "um hello", vocabulary: "Groq")
        XCTAssertEqual(messages.map(\.role), ["system", "user"])
        XCTAssertTrue(messages[0].content.contains("Groq"))
        XCTAssertEqual(messages[1].content, "um hello")
    }

    func testCleanupAcceptance() {
        XCTAssertEqual(CleanupPrompt.accept(cleaned: "Hello, world.", raw: "um hello world"), "Hello, world.")
        XCTAssertEqual(CleanupPrompt.accept(cleaned: "\"Hello.\"", raw: "hello"), "Hello.")
        XCTAssertEqual(CleanupPrompt.accept(cleaned: "  ", raw: "hello"), "hello")
        let essay = String(repeating: "This is an answer instead of a cleanup. ", count: 5)
        XCTAssertEqual(CleanupPrompt.accept(cleaned: essay, raw: "what is groq"), "what is groq")
    }

    func testInsertionSpacing() {
        XCTAssertEqual(Insertion.text("hello", after: nil), "hello")
        XCTAssertEqual(Insertion.text("hello", after: ""), "hello")
        XCTAssertEqual(Insertion.text("hello", after: "Say"), " hello")
        XCTAssertEqual(Insertion.text(" hello ", after: "Say "), "hello")
        XCTAssertEqual(Insertion.text("hello", after: "Line\n"), "hello")
        XCTAssertEqual(Insertion.text(", then", after: "first"), ", then")
    }

    func testWAVHeaderAndSamples() {
        let data = WAVEncoder.encode(samples: [0, 1, -1, 2, .nan], sampleRate: 16_000)
        XCTAssertEqual(data.count, 44 + 10)
        XCTAssertEqual(String(decoding: data[0..<4], as: UTF8.self), "RIFF")
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), "WAVE")
        XCTAssertEqual(readUInt32(data, at: 4), 36 + 10)
        XCTAssertEqual(readUInt32(data, at: 24), 16_000)
        XCTAssertEqual(readUInt32(data, at: 28), 32_000)
        XCTAssertEqual(readUInt32(data, at: 40), 10)
        XCTAssertEqual(readInt16(data, at: 44), 0)
        XCTAssertEqual(readInt16(data, at: 46), Int16.max)
        XCTAssertEqual(readInt16(data, at: 48), -Int16.max)
        XCTAssertEqual(readInt16(data, at: 50), Int16.max) // clamped
        XCTAssertEqual(readInt16(data, at: 52), 0) // NaN becomes silence
    }

    func testAudioLevel() {
        XCTAssertEqual(AudioLevel.normalized(rms: 0), 0)
        XCTAssertEqual(AudioLevel.normalized(rms: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(AudioLevel.normalized(rms: 0.01), 0.2, accuracy: 0.0001) // -40 dB
        XCTAssertEqual(AudioLevel.rms([0.5, -0.5]), 0.5, accuracy: 0.0001)
    }

    func testRecordingLimits() {
        XCTAssertFalse(RecordingLimits.isLongEnough(sampleCount: 1_000))
        XCTAssertTrue(RecordingLimits.isLongEnough(sampleCount: 16_000))
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        data[offset..<offset + 4].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }

    private func readInt16(_ data: Data, at offset: Int) -> Int16 {
        Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8)
    }
}
