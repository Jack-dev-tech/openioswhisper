import XCTest
@testable import DictationCore

final class SettingsAndStoreTests: XCTestCase {
    private var directory: URL!
    private var store: SharedStore!

    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = SharedStore(directory: directory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }

    func testDefaults() {
        let settings = DictationSettings()
        XCTAssertEqual(settings.provider, .groq)
        XCTAssertEqual(settings.selectedModelID, "whisper-large-v3-turbo")
        XCTAssertEqual(settings.selectedModelName, "Whisper Large V3 Turbo")
        XCTAssertNil(settings.language)
        XCTAssertFalse(settings.cleanupEnabled)
    }

    func testMissingFieldsDecodeToDefaults() throws {
        let settings = try JSONDecoder().decode(DictationSettings.self, from: Data(#"{"provider":"onDevice","language":"fr","unknown":1}"#.utf8))
        XCTAssertEqual(settings.provider, .onDevice)
        XCTAssertEqual(settings.language, "fr")
        XCTAssertEqual(settings.groqModelID, ModelCatalog.defaultGroqModelID)
        XCTAssertEqual(settings.sessionTimeout, .fifteenMinutes)
    }

    func testUnknownEnumValueFallsBack() throws {
        let settings = try JSONDecoder().decode(DictationSettings.self, from: Data(#"{"provider":"martian","sessionTimeout":42}"#.utf8))
        XCTAssertEqual(settings.provider, .groq)
        XCTAssertEqual(settings.sessionTimeout, .fifteenMinutes)
    }

    func testSwitchableModelsOnlyOfferDownloadedOnDeviceModels() {
        var settings = DictationSettings()
        settings.extraGroqModelIDs = ["whisper-large-v4"]
        settings.downloadedOnDeviceModelIDs = ["openai_whisper-small"]
        let ids = settings.switchableModels.map(\.id)
        XCTAssertEqual(ids, ["groq:whisper-large-v3-turbo", "groq:whisper-large-v3", "groq:whisper-large-v4", "onDevice:openai_whisper-small"])

        settings.select(settings.switchableModels.last!)
        XCTAssertEqual(settings.provider, .onDevice)
        XCTAssertEqual(settings.onDeviceModelID, "openai_whisper-small")
        XCTAssertEqual(settings.groqModelID, "whisper-large-v3-turbo")
        XCTAssertTrue(settings.isSelected(settings.switchableModels.last!))
    }

    func testUnknownGroqModelGetsReadableName() {
        XCTAssertEqual(ModelCatalog.displayName(provider: .groq, modelID: "whisper-large-v4-turbo"), "Whisper Large V4 Turbo")
    }

    func testStoreRoundTrips() {
        XCTAssertEqual(store.loadSettings(), DictationSettings())
        XCTAssertEqual(store.loadStatus(), .inactive)
        XCTAssertNil(store.loadResult())

        var settings = DictationSettings()
        settings.vocabulary = "Matsuzaki"
        store.saveSettings(settings)
        XCTAssertEqual(store.loadSettings().vocabulary, "Matsuzaki")

        let status = SessionStatus(phase: .recording, level: 0.5, heartbeat: Date(timeIntervalSince1970: 1_000.25))
        store.saveStatus(status)
        XCTAssertEqual(store.loadStatus(), status)

        let result = TranscriptResult(text: "Hi", createdAt: Date(timeIntervalSince1970: 2_000.5))
        store.saveResult(result)
        XCTAssertEqual(store.loadResult(), result)

        store.saveConsumedResultID(result.id)
        XCTAssertEqual(store.loadConsumedResultID(), result.id)
        XCTAssertTrue(store.isWritable)
    }

    func testSessionLiveness() {
        let now = Date()
        XCTAssertFalse(SessionStatus.inactive.isAlive(now: now))
        XCTAssertTrue(SessionStatus(phase: .ready, heartbeat: now.addingTimeInterval(-1)).isAlive(now: now))
        XCTAssertFalse(SessionStatus(phase: .ready, heartbeat: now.addingTimeInterval(-5)).isAlive(now: now))
        XCTAssertTrue(SessionStatus(phase: .failed, heartbeat: now).canStartRecording(now: now))
        XCTAssertFalse(SessionStatus(phase: .transcribing, heartbeat: now).canStartRecording(now: now))
    }

    func testResultIsInsertedOnceAndOnlyWhenFresh() {
        let now = Date()
        let result = TranscriptResult(text: "Hello", createdAt: now)
        XCTAssertTrue(result.shouldInsert(lastConsumedID: nil, now: now))
        XCTAssertFalse(result.shouldInsert(lastConsumedID: result.id, now: now))
        XCTAssertFalse(result.shouldInsert(lastConsumedID: nil, now: now.addingTimeInterval(IPC.resultMaxAge + 1)))
        XCTAssertFalse(TranscriptResult(text: "", createdAt: now).shouldInsert(lastConsumedID: nil, now: now))
    }

    func testLanguages() {
        XCTAssertEqual(WhisperLanguage.all.count, 100)
        XCTAssertEqual(Set(WhisperLanguage.all.map(\.code)).count, 100)
        XCTAssertEqual(WhisperLanguage.named(nil), "Auto-detect")
        XCTAssertEqual(WhisperLanguage.named("ja"), "Japanese")
        XCTAssertEqual(WhisperLanguage.all.first?.name, "Afrikaans")
    }
}

final class IPCTests: XCTestCase {
    func testSessionURLAsksForRecording() {
        XCTAssertTrue(IPC.wantsRecording(IPC.startSessionURL))
        XCTAssertFalse(IPC.wantsRecording(URL(string: "openwhisper://session")!))
        XCTAssertEqual(IPC.startSessionURL.scheme, IPC.urlScheme)
    }
}
