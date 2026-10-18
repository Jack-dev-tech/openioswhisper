import CoreML
import DictationCore
import Foundation
@preconcurrency import WhisperKit

/// Runs WhisperKit models on the phone. Keeps one model loaded so dictations after the first are quick.
actor OnDeviceEngine {
    private var pipeline: WhisperKit?
    private var loadedFolder: URL?
    /// A load in progress, shared by callers that ask for the same model meanwhile.
    private var loading: (folder: URL, task: Task<WhisperKit, Error>)?

    /// Loads the model in `folder`, compiling it for this device on first use. Does nothing if it is already loaded.
    func prepare(folder: URL, tokenizerFolder: URL) async throws {
        if pipeline != nil, loadedFolder == folder { return }
        if let loading, loading.folder == folder {
            // Whichever caller resumes first stores the shared result.
            let loaded = try await loading.task.value
            if loadedFolder != folder || pipeline == nil {
                pipeline = loaded
                loadedFolder = folder
            }
            return
        }
        await unload()
        let task = Task { try await Self.load(folder: folder, tokenizerFolder: tokenizerFolder) }
        loading = (folder, task)
        do {
            let loaded = try await task.value
            if loading?.folder == folder { loading = nil }
            pipeline = loaded
            loadedFolder = folder
        } catch {
            if loading?.folder == folder { loading = nil }
            throw error
        }
    }

    private static func load(folder: URL, tokenizerFolder: URL) async throws -> WhisperKit {
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
        return try await WhisperKit(config)
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
        loading?.task.cancel()
        loading = nil
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
