import Foundation

/// How long a background session stays open after the last dictation.
public enum SessionTimeout: Int, Codable, CaseIterable, Sendable {
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case oneHour = 3600
    case never = 0

    public var interval: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue)
    }

    public var label: String {
        switch self {
        case .fiveMinutes: "5 minutes"
        case .fifteenMinutes: "15 minutes"
        case .oneHour: "1 hour"
        case .never: "Never"
        }
    }
}

/// Everything the app and the keyboard share about how to dictate.
/// The Groq API key is not here: it stays in the app's Keychain.
public struct DictationSettings: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version = DictationSettings.currentVersion
    public var provider: TranscriptionProvider = .groq
    public var groqModelID = ModelCatalog.defaultGroqModelID
    public var onDeviceModelID = ModelCatalog.defaultOnDeviceModelID
    /// An ISO-639-1 code, or nil to let Whisper detect the language.
    public var language: String?
    /// Names, jargon and spellings passed to Whisper as its prompt.
    public var vocabulary = ""
    public var cleanupEnabled = false
    public var cleanupModelID = ModelCatalog.defaultCleanupModelID
    public var sessionTimeout: SessionTimeout = .fifteenMinutes
    /// Groq transcription models found on the account beyond the built-in ones.
    public var extraGroqModelIDs: [String] = []
    /// Groq chat models found on the account, offered for cleanup.
    public var groqChatModelIDs: [String] = []
    /// On-device models that are downloaded, so the keyboard can offer them.
    public var downloadedOnDeviceModelIDs: [String] = []

    public init() {}

    public var selectedModelID: String {
        provider == .groq ? groqModelID : onDeviceModelID
    }

    public var selectedModelName: String {
        ModelCatalog.displayName(provider: provider, modelID: selectedModelID)
    }

    /// The models the keyboard's quick switcher offers: every Groq model and the downloaded on-device ones.
    public var switchableModels: [TranscriptionModel] {
        let downloaded = Set(downloadedOnDeviceModelIDs)
        return ModelCatalog.models(for: .groq, extraGroqModelIDs: extraGroqModelIDs)
            + ModelCatalog.onDevice.filter { downloaded.contains($0.modelID) }
    }

    public mutating func select(_ model: TranscriptionModel) {
        provider = model.provider
        switch model.provider {
        case .groq: groqModelID = model.modelID
        case .onDevice: onDeviceModelID = model.modelID
        }
    }

    public func isSelected(_ model: TranscriptionModel) -> Bool {
        model.provider == provider && model.modelID == selectedModelID
    }

    private enum CodingKeys: String, CodingKey {
        case version, provider, groqModelID, onDeviceModelID, language, vocabulary, cleanupEnabled,
             cleanupModelID, sessionTimeout, extraGroqModelIDs, groqChatModelIDs, downloadedOnDeviceModelIDs
    }

    /// Missing or unknown values fall back to defaults, so older or newer files still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DictationSettings()
        version = (try? c.decodeIfPresent(Int.self, forKey: .version)) ?? defaults.version
        provider = (try? c.decodeIfPresent(TranscriptionProvider.self, forKey: .provider)) ?? defaults.provider
        groqModelID = (try? c.decodeIfPresent(String.self, forKey: .groqModelID)) ?? defaults.groqModelID
        onDeviceModelID = (try? c.decodeIfPresent(String.self, forKey: .onDeviceModelID)) ?? defaults.onDeviceModelID
        language = (try? c.decodeIfPresent(String.self, forKey: .language)) ?? defaults.language
        vocabulary = (try? c.decodeIfPresent(String.self, forKey: .vocabulary)) ?? defaults.vocabulary
        cleanupEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .cleanupEnabled)) ?? defaults.cleanupEnabled
        cleanupModelID = (try? c.decodeIfPresent(String.self, forKey: .cleanupModelID)) ?? defaults.cleanupModelID
        sessionTimeout = (try? c.decodeIfPresent(SessionTimeout.self, forKey: .sessionTimeout)) ?? defaults.sessionTimeout
        extraGroqModelIDs = (try? c.decodeIfPresent([String].self, forKey: .extraGroqModelIDs)) ?? defaults.extraGroqModelIDs
        groqChatModelIDs = (try? c.decodeIfPresent([String].self, forKey: .groqChatModelIDs)) ?? defaults.groqChatModelIDs
        downloadedOnDeviceModelIDs = (try? c.decodeIfPresent([String].self, forKey: .downloadedOnDeviceModelIDs)) ?? defaults.downloadedOnDeviceModelIDs
    }
}
