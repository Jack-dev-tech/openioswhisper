import DictationCore
import Foundation
import Observation
import UIKit

/// The keyboard's side of a dictation: asks the app to record, shows its progress,
/// and types the transcript when it arrives.
@MainActor
@Observable
final class KeyboardModel {
    private(set) var status: SessionStatus = .inactive
    /// Whether the app's session heartbeat is fresh. Stored, so the view updates when the app goes away.
    private(set) var isLive = false
    private(set) var settings = DictationSettings()
    private(set) var hasFullAccess = false
    private(set) var needsGlobeKey = true
    private(set) var canUndo = false
    private(set) var returnKeyTitle = "return"
    /// A keyboard-side notice, such as why the app couldn't be opened.
    var notice: String?
    var showingModels = false

    @ObservationIgnored private weak var controller: UIInputViewController?
    @ObservationIgnored private var store: SharedStore?
    @ObservationIgnored private var tokens: [DarwinNotifier.Token] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastInserted: String?
    /// After sending a command, keep showing the expected phase until the app confirms it.
    @ObservationIgnored private var expected: (phase: SessionPhase, until: Date)?

    init(controller: UIInputViewController) {
        self.controller = controller
    }

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    // MARK: - Lifecycle

    func appear() {
        disappear()
        guard let controller else { return }
        hasFullAccess = controller.hasFullAccess
        needsGlobeKey = controller.needsInputModeSwitchKey
        store = hasFullAccess ? SharedStore.appGroup() : nil
        notice = nil
        showingModels = false
        textDidChange()

        guard let store else { return }
        store.saveKeyboardCheckIn(KeyboardCheckIn())
        settings = store.loadSettings()
        refresh()

        let notifier = DarwinNotifier.shared
        tokens = [
            notifier.observe(IPC.Notification.result) { [weak self] in self?.insertPendingResult() },
            notifier.observe(IPC.Notification.status) { [weak self] in self?.refresh() },
            notifier.observe(IPC.Notification.settings) { [weak self] in self?.reloadSettings() },
        ]
        // Polling as well as notifications: cheap, and it notices when the app's heartbeat stops.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func disappear() {
        // A recording keeps going when the keyboard hides: it may be the one the app just started
        // when the keyboard opened it. The result is inserted when the keyboard comes back.
        timer?.invalidate()
        timer = nil
        tokens = []
    }

    func textDidChange() {
        switch proxy?.returnKeyType {
        case .go: returnKeyTitle = "go"
        case .search, .google, .yahoo: returnKeyTitle = "search"
        case .send: returnKeyTitle = "send"
        case .done: returnKeyTitle = "done"
        case .next: returnKeyTitle = "next"
        default: returnKeyTitle = "return"
        }
    }

    private func refresh() {
        guard let store else { return }
        let loaded = store.loadStatus()
        if let expected, Date() < expected.until, loaded.phase != expected.phase {
            // The app hasn't caught up with our command yet; only take the fresh heartbeat.
            if status.heartbeat != loaded.heartbeat { status.heartbeat = loaded.heartbeat }
        } else {
            expected = nil
            if status != loaded { status = loaded }
        }
        let live = status.isAlive()
        if isLive != live { isLive = live }
        insertPendingResult()
    }

    private func reloadSettings() {
        guard let store else { return }
        settings = store.loadSettings()
    }

    // MARK: - Dictation

    var isRecording: Bool { isLive && status.phase == .recording }
    var isTranscribing: Bool { isLive && status.phase == .transcribing }

    func micTapped() {
        notice = nil
        guard hasFullAccess, store != nil else {
            notice = "Turn on Allow Full Access in Settings › General › Keyboard › Keyboards › OpenWhisper."
            return
        }
        if isRecording {
            send(IPC.Notification.stop, expecting: .transcribing)
        } else if status.canStartRecording() {
            send(IPC.Notification.start, expecting: .recording)
        } else if isTranscribing {
            return
        } else if let controller, AppOpener.open(IPC.startSessionURL, from: controller) {
            notice = "Recording in OpenWhisper. Swipe back here and keep talking."
        } else {
            notice = "Open the OpenWhisper app and tap Start session."
        }
    }

    func cancelRecording() {
        guard isRecording else { return }
        send(IPC.Notification.cancel, expecting: .ready)
    }

    private func send(_ notification: String, expecting phase: SessionPhase) {
        DarwinNotifier.shared.post(notification)
        status.phase = phase
        status.message = nil
        expected = (phase, Date().addingTimeInterval(1))
    }

    private func insertPendingResult() {
        guard let store, let result = store.loadResult(),
              result.shouldInsert(lastConsumedID: store.loadConsumedResultID()),
              let proxy
        else { return }
        // Claim it first, so a second keyboard instance can't insert it too.
        store.saveConsumedResultID(result.id)
        let text = Insertion.text(result.text, after: proxy.documentContextBeforeInput)
        proxy.insertText(text)
        lastInserted = text
        canUndo = true
    }

    // MARK: - Keys

    func undoLastInsertion() {
        defer {
            lastInserted = nil
            canUndo = false
        }
        guard let proxy, let last = lastInserted, proxy.documentContextBeforeInput?.hasSuffix(last) == true else { return }
        for _ in 0..<last.count { proxy.deleteBackward() }
    }

    func insertSpace() { type(" ") }
    func insertReturn() { type("\n") }

    func deleteBackward() {
        proxy?.deleteBackward()
        canUndo = false
    }

    func nextKeyboard() {
        controller?.advanceToNextInputMode()
    }

    private func type(_ text: String) {
        proxy?.insertText(text)
        canUndo = false
    }

    // MARK: - Models

    func select(_ model: TranscriptionModel) {
        settings.select(model)
        store?.saveSettings(settings)
        DarwinNotifier.shared.post(IPC.Notification.settings)
        showingModels = false
    }

    // MARK: - Labels

    var statusLine: String {
        if let notice { return notice }
        guard hasFullAccess else { return "Full Access is needed to dictate." }
        guard isLive else { return "Tap the mic to start a session in OpenWhisper." }
        switch status.phase {
        case .recording: return "Listening… tap to finish."
        case .transcribing: return "Transcribing with \(settings.provider.displayName)…"
        case .failed: return status.message ?? "That didn't work. Try again."
        case .ready: return status.message ?? "Tap to dictate."
        case .inactive: return "Tap the mic to start a session in OpenWhisper."
        }
    }
}
