import DictationCore
import Foundation
import Observation

/// The app's live copy of `DictationSettings`, saved to the shared store on every change.
@MainActor
@Observable
final class SettingsStore {
    let shared: SharedStore

    var settings: DictationSettings {
        didSet {
            guard settings != oldValue, !isReloading else { return }
            shared.saveSettings(settings)
            DarwinNotifier.shared.post(IPC.Notification.settings)
        }
    }

    @ObservationIgnored private var isReloading = false
    @ObservationIgnored private var token: DarwinNotifier.Token?

    init(shared: SharedStore) {
        self.shared = shared
        settings = shared.loadSettings()
        // The keyboard's model switcher writes settings too.
        token = DarwinNotifier.shared.observe(IPC.Notification.settings) { [weak self] in
            self?.reload()
        }
    }

    func reload() {
        let loaded = shared.loadSettings()
        guard loaded != settings else { return }
        isReloading = true
        settings = loaded
        isReloading = false
    }

    /// The App Group store, or a private one if the App Group isn't set up (for example, unsigned builds).
    static func makeSharedStore() -> SharedStore {
        if let store = SharedStore.appGroup() { return store }
        let fallback = URL.applicationSupportDirectory.appendingPathComponent("Shared", isDirectory: true)
        return SharedStore(directory: fallback)
    }
}
