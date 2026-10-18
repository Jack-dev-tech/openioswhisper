import DictationCore
import Foundation
import Observation
@preconcurrency import WhisperKit

/// Downloads, tracks and deletes on-device WhisperKit models.
@MainActor
@Observable
final class ModelStore {
    enum State: Equatable {
        case notDownloaded
        case downloading(Double)
        /// Downloaded; compiling for this device's Neural Engine.
        case preparing
        case downloaded
        case failed(String)
    }

    private(set) var states: [String: State] = [:]
    /// Model folder names WhisperKit says this device can run. Empty until known.
    private(set) var supportedModelIDs: Set<String> = []

    private let settings: SettingsStore
    private let engine: OnDeviceEngine
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    private let defaults = UserDefaults.standard
    private static let pathsKey = "onDeviceModelPaths"

    /// Models and tokenizers live in Application Support, which is backed up only if small, and never purged.
    let baseFolder = URL.applicationSupportDirectory.appendingPathComponent("OnDeviceModels", isDirectory: true)

    init(settings: SettingsStore, engine: OnDeviceEngine) {
        self.settings = settings
        self.engine = engine
        try? FileManager.default.createDirectory(at: baseFolder, withIntermediateDirectories: true)
        for model in ModelCatalog.onDevice {
            states[model.modelID] = folder(for: model.modelID) == nil ? .notDownloaded : .downloaded
        }
        supportedModelIDs = Set(WhisperKit.recommendedModels().supported)
        syncDownloadedList()
    }

    func state(of modelID: String) -> State {
        states[modelID] ?? .notDownloaded
    }

    /// False only when WhisperKit knows this device is too slow or lacks memory for the model.
    func isSupported(_ modelID: String) -> Bool {
        supportedModelIDs.isEmpty || supportedModelIDs.contains(modelID)
    }

    /// Asks Hugging Face for the latest device support list; the built-in list is used until then.
    func refreshSupport() async {
        let support = await WhisperKit.recommendedRemoteModels()
        if !support.supported.isEmpty { supportedModelIDs = Set(support.supported) }
    }

    /// The local folder of a downloaded model.
    func folder(for modelID: String) -> URL? {
        guard let relative = (defaults.dictionary(forKey: Self.pathsKey) as? [String: String])?[modelID] else { return nil }
        let url = baseFolder.appendingPathComponent(relative, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func download(_ modelID: String) {
        guard tasks[modelID] == nil else { return }
        states[modelID] = .downloading(0)
        tasks[modelID] = Task { [weak self] in
            guard let self else { return }
            do {
                let folder = try await WhisperKit.download(
                    variant: modelID,
                    downloadBase: baseFolder,
                    progressCallback: { progress in
                        let fraction = progress.fractionCompleted
                        Task { @MainActor [weak self] in
                            if case .downloading = self?.states[modelID] { self?.states[modelID] = .downloading(fraction) }
                        }
                    }
                )
                try Task.checkCancellation()
                savePath(folder, for: modelID)
                states[modelID] = .preparing
                // Compile now, while the user is watching, rather than on the first dictation.
                try await engine.prepare(folder: folder, tokenizerFolder: baseFolder)
                states[modelID] = .downloaded
            } catch is CancellationError {
                states[modelID] = folder(for: modelID) == nil ? .notDownloaded : .downloaded
            } catch {
                states[modelID] = .failed(error.localizedDescription)
            }
            tasks[modelID] = nil
            syncDownloadedList()
        }
    }

    func cancelDownload(_ modelID: String) {
        tasks[modelID]?.cancel()
    }

    func delete(_ modelID: String) async {
        if let folder = folder(for: modelID) {
            await engine.unload()
            try? FileManager.default.removeItem(at: folder)
        }
        var paths = defaults.dictionary(forKey: Self.pathsKey) as? [String: String] ?? [:]
        paths[modelID] = nil
        defaults.set(paths, forKey: Self.pathsKey)
        states[modelID] = .notDownloaded
        syncDownloadedList()
    }

    /// Bytes on disk for a downloaded model.
    func sizeOnDisk(_ modelID: String) -> Int64? {
        guard let folder = folder(for: modelID),
              let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey])
        else { return nil }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            total += Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    private func savePath(_ folder: URL, for modelID: String) {
        // Store the path relative to the base: the app container's absolute path changes between installs.
        let base = baseFolder.standardizedFileURL.path
        var relative = folder.standardizedFileURL.path
        if relative.hasPrefix(base) { relative = String(relative.dropFirst(base.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
        var paths = defaults.dictionary(forKey: Self.pathsKey) as? [String: String] ?? [:]
        paths[modelID] = relative
        defaults.set(paths, forKey: Self.pathsKey)
    }

    /// Tells the keyboard which on-device models it can switch to.
    private func syncDownloadedList() {
        let downloaded = ModelCatalog.onDevice.map(\.modelID).filter { folder(for: $0) != nil }
        if settings.settings.downloadedOnDeviceModelIDs != downloaded {
            settings.settings.downloadedOnDeviceModelIDs = downloaded
        }
    }
}
