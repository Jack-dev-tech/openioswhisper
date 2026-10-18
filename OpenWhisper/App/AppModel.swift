import AVFoundation
import DictationCore
import Foundation
import Observation

/// Owns the app's services and the state the setup checklist needs.
@MainActor
@Observable
final class AppModel {
    enum Tab: Hashable { case dictate, models, settings }

    var selectedTab: Tab = .dictate
    private(set) var hasGroqKey = Keychain.groqAPIKey != nil
    private(set) var keyboardReady = false
    private(set) var microphoneGranted = false

    let shared: SharedStore
    let settings: SettingsStore
    let models: ModelStore
    let session: DictationSession
    private let groq = GroqClient()

    init() {
        let shared = SettingsStore.makeSharedStore()
        let settings = SettingsStore(shared: shared)
        let onDevice = OnDeviceEngine()
        let models = ModelStore(settings: settings, engine: onDevice)
        let pipeline = TranscriptionPipeline(settings: settings, models: models, onDevice: onDevice)
        self.shared = shared
        self.settings = settings
        self.models = models
        session = DictationSession(store: shared, settings: settings, pipeline: pipeline)
        refreshSetup()
    }

    /// `openwhisper://session?record=1`, opened by the keyboard when no session is running.
    func handle(_ url: URL) {
        guard url.scheme == IPC.urlScheme else { return }
        selectedTab = .dictate
        let record = IPC.wantsRecording(url)
        Task {
            await session.start()
            if record { session.startRecording(source: .keyboard) }
        }
    }

    func refreshSetup() {
        settings.reload()
        hasGroqKey = Keychain.groqAPIKey != nil
        keyboardReady = shared.loadKeyboardCheckIn() != nil
        microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
    }

    func requestMicrophone() async {
        microphoneGranted = await AVAudioApplication.requestRecordPermission()
    }

    var isSetupComplete: Bool {
        keyboardReady && microphoneGranted && hasTranscriptionEngine
    }

    /// A Groq key, or at least one downloaded on-device model.
    var hasTranscriptionEngine: Bool {
        hasGroqKey || !settings.settings.downloadedOnDeviceModelIDs.isEmpty
    }

    // MARK: - Groq

    func saveGroqKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.groqAPIKey = trimmed.isEmpty ? nil : trimmed
        hasGroqKey = Keychain.groqAPIKey != nil
    }

    /// Checks the key by listing the account's models, and remembers which ones it can use.
    /// Returns a message for the user.
    func refreshGroqModels() async -> String {
        guard let key = Keychain.groqAPIKey else { return GroqError.missingAPIKey.localizedDescription }
        do {
            let models = try await groq.models(apiKey: key)
            settings.settings.extraGroqModelIDs = GroqAPI.transcriptionModelIDs(in: models)
            settings.settings.groqChatModelIDs = GroqAPI.chatModelIDs(in: models)
            let count = settings.settings.extraGroqModelIDs.count
            return "Key works. \(count) transcription model\(count == 1 ? "" : "s") available."
        } catch {
            return error.localizedDescription
        }
    }
}
