import AVFoundation
import DictationCore
import Foundation
import Observation

/// A background dictation session: keeps the microphone open, records when the keyboard asks,
/// transcribes, and hands the text back to the keyboard through the shared store.
@MainActor
@Observable
final class DictationSession {
    /// Who asked for the recording. Keyboard results go to the keyboard; in-app tests stay in the app.
    enum Source { case keyboard, app }

    private(set) var phase: SessionPhase = .inactive
    private(set) var message: String?
    private(set) var level: Float = 0
    private(set) var expiresAt: Date?
    /// The latest transcript recorded from inside the app.
    private(set) var lastTranscript: String?

    var isActive: Bool { phase != .inactive }

    private let store: SharedStore
    private let settings: SettingsStore
    private let pipeline: TranscriptionPipeline
    private let capture = AudioCapture()
    private let levelBox = LevelBox()
    @ObservationIgnored private var tokens: [DarwinNotifier.Token] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var lastActivity = Date()
    @ObservationIgnored private var recordingSource: Source = .keyboard
    @ObservationIgnored private var recordingStartedAt = Date()
    @ObservationIgnored private var publishedPhase: SessionPhase?

    init(store: SharedStore, settings: SettingsStore, pipeline: TranscriptionPipeline) {
        self.store = store
        self.settings = settings
        self.pipeline = pipeline
        // A previous run may have been killed mid-session; make sure the keyboard doesn't wait on it.
        store.saveStatus(.inactive)

        let levelBox = levelBox
        capture.onLevel = { levelBox.set($0) }
        capture.onInterruption = { [weak self] began in
            guard began else { return }
            Task { @MainActor in self?.cancelRecording(reason: "Interrupted by another app.") }
        }
    }

    // MARK: - Session

    func start() async {
        guard phase == .inactive else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            message = "Microphone access is off. Turn it on in Settings › OpenWhisper."
            return
        }
        do {
            try capture.start()
        } catch {
            message = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }
        phase = .ready
        message = nil
        lastActivity = Date()

        let notifier = DarwinNotifier.shared
        tokens = [
            notifier.observe(IPC.Notification.start) { [weak self] in self?.startRecording(source: .keyboard) },
            notifier.observe(IPC.Notification.stop) { [weak self] in self?.stopRecording() },
            notifier.observe(IPC.Notification.cancel) { [weak self] in self?.cancelRecording(reason: nil) },
        ]
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        publish()

        // Load the on-device model in the background so the first dictation doesn't wait for it.
        // Not awaited: recording can start meanwhile, and transcription waits for the same load.
        Task {
            do {
                try await pipeline.prepare()
            } catch {
                guard phase == .ready else { return }
                message = error.localizedDescription
                publish()
            }
        }
    }

    func end() {
        guard phase != .inactive else { return }
        timer?.invalidate()
        timer = nil
        tokens = []
        capture.stop()
        phase = .inactive
        level = 0
        expiresAt = nil
        publish()
    }

    // MARK: - Recording

    func startRecording(source: Source) {
        guard phase == .ready || phase == .failed else { return }
        capture.beginCapture()
        levelBox.set(0)
        recordingSource = source
        recordingStartedAt = Date()
        lastActivity = Date()
        phase = .recording
        message = nil
        publish()
    }

    func stopRecording() {
        guard phase == .recording else { return }
        let samples = capture.endCapture()
        level = 0
        lastActivity = Date()
        guard RecordingLimits.isLongEnough(sampleCount: samples.count) else {
            phase = .ready
            message = "Too short — hold on a moment longer."
            publish()
            return
        }
        phase = .transcribing
        publish()

        let source = recordingSource
        Task {
            do {
                let text = try await pipeline.transcribe(samples)
                finish(text, source: source)
            } catch {
                fail(error)
            }
        }
    }

    func cancelRecording(reason: String?) {
        guard phase == .recording else { return }
        _ = capture.endCapture()
        level = 0
        phase = .ready
        message = reason
        publish()
    }

    private func finish(_ text: String, source: Source) {
        guard phase == .transcribing else { return }
        lastActivity = Date()
        phase = .ready
        if text.isEmpty {
            message = "Didn't catch any speech."
        } else {
            message = nil
            switch source {
            case .keyboard:
                store.saveResult(TranscriptResult(text: text))
                DarwinNotifier.shared.post(IPC.Notification.result)
            case .app:
                lastTranscript = text
            }
        }
        publish()
    }

    private func fail(_ error: Error) {
        guard phase == .transcribing else { return }
        lastActivity = Date()
        phase = .failed
        message = error.localizedDescription
        publish()
    }

    // MARK: - Heartbeat

    private func tick() {
        ticks += 1
        if phase == .recording {
            level = levelBox.get()
            if Date().timeIntervalSince(recordingStartedAt) > RecordingLimits.maximumDuration {
                stopRecording()
                return
            }
            publish()
            return
        }
        if phase == .ready || phase == .failed,
           let timeout = settings.settings.sessionTimeout.interval,
           Date().timeIntervalSince(lastActivity) > timeout {
            end()
            return
        }
        if ticks % Int(IPC.heartbeatInterval * 10) == 0 { publish() }
    }

    /// Writes the status for the keyboard. Doubles as the heartbeat.
    private func publish() {
        if let timeout = settings.settings.sessionTimeout.interval, phase != .inactive {
            expiresAt = lastActivity.addingTimeInterval(timeout)
        } else {
            expiresAt = nil
        }
        store.saveStatus(SessionStatus(
            phase: phase,
            message: message,
            level: phase == .recording ? level : 0,
            heartbeat: phase == .inactive ? .distantPast : Date(),
            expiresAt: expiresAt
        ))
        if publishedPhase != phase {
            publishedPhase = phase
            DarwinNotifier.shared.post(IPC.Notification.status)
        }
    }
}

/// The latest input level, written on the audio thread and read on the main thread.
private final class LevelBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0

    func set(_ newValue: Float) { lock.withLock { value = newValue } }
    func get() -> Float { lock.withLock { value } }
}
