import DictationCore
import Foundation

/// Turns recorded samples into the final text: the chosen engine, then the optional Groq cleanup.
@MainActor
final class TranscriptionPipeline {
    private let settings: SettingsStore
    private let models: ModelStore
    private let onDevice: OnDeviceEngine
    private let groq = GroqClient()

    init(settings: SettingsStore, models: ModelStore, onDevice: OnDeviceEngine) {
        self.settings = settings
        self.models = models
        self.onDevice = onDevice
    }

    /// Loads the on-device model ahead of the first dictation, if one is selected.
    func prepare() async throws {
        let current = settings.settings
        guard current.provider == .onDevice else { return }
        try await onDevice.prepare(folder: try onDeviceFolder(for: current), tokenizerFolder: models.baseFolder)
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        // Read from disk: the keyboard may have just switched the model.
        settings.reload()
        let current = settings.settings
        let prompt = VocabularyPrompt.make(from: current.vocabulary)

        let raw: String
        switch current.provider {
        case .groq:
            guard let key = Keychain.groqAPIKey else { throw GroqError.missingAPIKey }
            let wav = WAVEncoder.encode(samples: samples)
            raw = try await groq.transcribe(wav: wav, apiKey: key, model: current.groqModelID, language: current.language, prompt: prompt)
        case .onDevice:
            try await onDevice.prepare(folder: try onDeviceFolder(for: current), tokenizerFolder: models.baseFolder)
            raw = try await onDevice.transcribe(samples: samples, language: current.language, prompt: prompt)
        }

        guard current.cleanupEnabled, !raw.isEmpty, let key = Keychain.groqAPIKey else { return raw }
        do {
            return try await groq.clean(raw, apiKey: key, model: current.cleanupModelID, vocabulary: prompt)
        } catch {
            // Cleanup is a nicety: never lose a dictation because it failed.
            return raw
        }
    }

    private func onDeviceFolder(for settings: DictationSettings) throws -> URL {
        guard let folder = models.folder(for: settings.onDeviceModelID) else {
            throw OnDeviceError.notDownloaded(settings.selectedModelName)
        }
        return folder
    }
}
