import CoreML
import DictationCore
import Foundation
@preconcurrency import WhisperKit

/// Runs WhisperKit models on the phone. Keeps one model loaded so dictations after the first are quick.
actor OnDeviceEngine {
    private var pipeline: WhisperKit?
    private var loadedFolder: URL?

    /// Loads the model in `folder`, compiling it for this device on first use. Does nothing if it is already loaded.
    func prepare(folder: URL, tokenizerFolder: URL) async throws {
        if pipeline != nil, loadedFolder == folder { return }
        await unload()
        let config = WhisperKitConfig(
            modelFolder: folder.path,
            tokenizerFolder: tokenizerFolder,
            // The GPU is off limits in the background, and dictation mostly runs while another app is in front.
            computeOptions: ModelComputeOptions(
                melCompute: .cpuOnly,
                audioEncoderCompute: .cpuAndNeuralEngine,
                textDecoderCompute: .cpuAndNeuralEngine
            ),
            verbose: false,
            logLevel: .error,
            prewarm: false,
            load: true,
            download: false
        )
        pipeline = try await WhisperKit(config)
        loadedFolder = folder
    }

    func transcribe(samples: [Float], language: String?, prompt: String?) async throws -> String {
        guard let pipeline else { throw OnDeviceError.notLoaded }
        var options = DecodingOptions(
            task: .transcribe,
            language: language,
            temperature: 0,
            usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true,
            withoutTimestamps: true
        )
        if let prompt, let tokenizer = pipeline.tokenizer {
            options.promptTokens = tokenizer.encode(text: " " + prompt)
                .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
        }
        let results = try await pipeline.transcribe(audioArray: samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func unload() async {
        await pipeline?.unloadModels()
        pipeline = nil
        loadedFolder = nil
    }
}

enum OnDeviceError: LocalizedError {
    case notLoaded
    case notDownloaded(String)

    var errorDescription: String? {
        switch self {
        case .notLoaded: "The on-device model isn't loaded yet."
        case .notDownloaded(let name): "\(name) isn't downloaded. Download it in Models, or pick another model."
        }
    }
}
