import Foundation

/// Where a transcription runs.
public enum TranscriptionProvider: String, Codable, CaseIterable, Sendable {
    /// Groq's hosted Whisper models, using the user's own API key.
    case groq
    /// WhisperKit Core ML models running on the phone.
    case onDevice

    public var displayName: String {
        switch self {
        case .groq: "Groq"
        case .onDevice: "On-device"
        }
    }
}

/// One selectable dictation model.
public struct TranscriptionModel: Codable, Hashable, Sendable, Identifiable {
    public var provider: TranscriptionProvider
    /// The id sent to Groq, or the WhisperKit model folder name.
    public var modelID: String
    public var name: String
    public var detail: String
    /// Rough download size for on-device models.
    public var approximateSizeMB: Int?

    public var id: String { "\(provider.rawValue):\(modelID)" }

    public init(provider: TranscriptionProvider, modelID: String, name: String, detail: String, approximateSizeMB: Int? = nil) {
        self.provider = provider
        self.modelID = modelID
        self.name = name
        self.detail = detail
        self.approximateSizeMB = approximateSizeMB
    }
}

public enum ModelCatalog {
    public static let defaultGroqModelID = "whisper-large-v3-turbo"
    public static let defaultOnDeviceModelID = "openai_whisper-base"
    public static let defaultCleanupModelID = "llama-3.1-8b-instant"

    public static let groq: [TranscriptionModel] = [
        TranscriptionModel(
            provider: .groq, modelID: "whisper-large-v3-turbo", name: "Whisper Large V3 Turbo",
            detail: "Fastest and cheapest. Accuracy close to Large V3."
        ),
        TranscriptionModel(
            provider: .groq, modelID: "whisper-large-v3", name: "Whisper Large V3",
            detail: "Most accurate, especially for accents and other languages."
        ),
    ]

    /// Folder names in the `argmaxinc/whisperkit-coreml` Hugging Face repo.
    public static let onDevice: [TranscriptionModel] = [
        TranscriptionModel(
            provider: .onDevice, modelID: "openai_whisper-tiny", name: "Whisper Tiny",
            detail: "Instant, rough accuracy. Runs on any iPhone.", approximateSizeMB: 75
        ),
        TranscriptionModel(
            provider: .onDevice, modelID: "openai_whisper-base", name: "Whisper Base",
            detail: "Fast with decent accuracy. A good default.", approximateSizeMB: 145
        ),
        TranscriptionModel(
            provider: .onDevice, modelID: "openai_whisper-small", name: "Whisper Small",
            detail: "Noticeably better accuracy, still quick on recent iPhones.", approximateSizeMB: 485
        ),
        TranscriptionModel(
            provider: .onDevice, modelID: "openai_whisper-large-v3-v20240930_turbo_632MB", name: "Whisper Large V3 Turbo",
            detail: "Near Large V3 accuracy, much faster. iPhone 14 Pro or newer.", approximateSizeMB: 632
        ),
        TranscriptionModel(
            provider: .onDevice, modelID: "openai_whisper-large-v3-v20240930_626MB", name: "Whisper Large V3",
            detail: "Best accuracy, slowest. iPhone 14 Pro or newer.", approximateSizeMB: 626
        ),
    ]

    /// The known models for a provider, plus any extra Groq models discovered from the API.
    public static func models(for provider: TranscriptionProvider, extraGroqModelIDs: [String] = []) -> [TranscriptionModel] {
        switch provider {
        case .onDevice:
            return onDevice
        case .groq:
            let known = Set(groq.map(\.modelID))
            let extras = extraGroqModelIDs
                .filter { !known.contains($0) }
                .sorted()
                .map { TranscriptionModel(provider: .groq, modelID: $0, name: displayName(forGroqModelID: $0), detail: "Available on your Groq account.") }
            return groq + extras
        }
    }

    public static func model(provider: TranscriptionProvider, modelID: String) -> TranscriptionModel? {
        models(for: provider).first { $0.modelID == modelID }
    }

    /// A readable name for a model, falling back to a prettified id for models we don't know.
    public static func displayName(provider: TranscriptionProvider, modelID: String) -> String {
        if let known = model(provider: provider, modelID: modelID) { return known.name }
        switch provider {
        case .groq: return displayName(forGroqModelID: modelID)
        case .onDevice: return displayName(forGroqModelID: modelID.replacingOccurrences(of: "openai_", with: ""))
        }
    }

    static func displayName(forGroqModelID id: String) -> String {
        id.split(separator: "-")
            .map { part in
                let word = String(part)
                if word.first == "v", word.dropFirst().allSatisfy(\.isNumber) { return word.uppercased() }
                return word.prefix(1).uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }
}
