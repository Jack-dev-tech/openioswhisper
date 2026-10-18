import AVFoundation
import DictationCore

/// Keeps the microphone open for the whole session and collects 16 kHz mono samples while capturing.
///
/// The input tap runs even when not capturing: a running audio engine is what lets iOS keep
/// the app alive in the background, so the keyboard can start a recording at any time.
final class AudioCapture: @unchecked Sendable {
    /// Called on the audio thread with the input level (0...1) while capturing.
    var onLevel: (@Sendable (Float) -> Void)?
    /// Called on the main queue when an interruption (a phone call, Siri) ends or the route changes and the engine restarts.
    var onInterruption: (@Sendable (_ began: Bool) -> Void)?

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var samples: [Float] = []
    private var isCapturing = false
    private var converter: AVAudioConverter?
    private var observers: [NSObjectProtocol] = []
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!

    var isRunning: Bool { engine.isRunning }

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        // Mix with others so music and podcasts keep playing during a session.
        try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)
        try startEngine()
        observeSession()
    }

    func stop() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.withLock {
            isCapturing = false
            samples.removeAll()
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func beginCapture() {
        lock.withLock {
            samples.removeAll(keepingCapacity: true)
            isCapturing = true
        }
    }

    /// Stops capturing and returns everything captured since `beginCapture()`.
    func endCapture() -> [Float] {
        lock.withLock {
            isCapturing = false
            let captured = samples
            samples.removeAll()
            return captured
        }
    }

    private func startEngine() throws {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noInput }
        converter = AVAudioConverter(from: format, to: targetFormat)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard lock.withLock({ isCapturing }), let converter, let channel = buffer.floatChannelData?[0] else { return }

        let level = AudioLevel.normalized(rms: AudioLevel.rms(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))))
        onLevel?(level)

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let converted = output.floatChannelData?[0] else { return }
        let frames = UnsafeBufferPointer(start: converted, count: Int(output.frameLength))
        lock.withLock {
            if isCapturing { samples.append(contentsOf: frames) }
        }
    }

    private func observeSession() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }
            switch type {
            case .began:
                onInterruption?(true)
            case .ended:
                try? AVAudioSession.sharedInstance().setActive(true)
                try? startEngine()
                onInterruption?(false)
            @unknown default:
                break
            }
        })
        // A new input (AirPods connected) changes the input format, so the tap must be reinstalled.
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                  reason == .newDeviceAvailable || reason == .oldDeviceUnavailable
            else { return }
            engine.stop()
            try? startEngine()
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
            try? AVAudioSession.sharedInstance().setActive(true)
            try? startEngine()
        })
    }

    enum CaptureError: LocalizedError {
        case noInput
        var errorDescription: String? { "No microphone is available." }
    }
}
