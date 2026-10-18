import Foundation

/// Cross-process signals between the app and the keyboard through the Darwin notify center.
/// Notifications carry no data; the receiver reads `SharedStore` when one arrives.
final class DarwinNotifier: @unchecked Sendable {
    static let shared = DarwinNotifier()

    private let lock = NSLock()
    private var handlers: [String: [UUID: @MainActor () -> Void]] = [:]
    private var center: CFNotificationCenter { CFNotificationCenterGetDarwinNotifyCenter() }

    private init() {}

    func post(_ name: String) {
        CFNotificationCenterPostNotification(center, CFNotificationName(name as CFString), nil, nil, true)
    }

    /// Calls `handler` on the main actor each time `name` is posted, until the token is cancelled.
    @discardableResult
    func observe(_ name: String, handler: @escaping @MainActor () -> Void) -> Token {
        let id = UUID()
        lock.lock()
        let isFirst = handlers[name] == nil
        handlers[name, default: [:]][id] = handler
        lock.unlock()

        if isFirst {
            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    let notifier = Unmanaged<DarwinNotifier>.fromOpaque(observer).takeUnretainedValue()
                    notifier.fire(name.rawValue as String)
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }
        return Token(name: name, id: id, notifier: self)
    }

    private func fire(_ name: String) {
        lock.lock()
        let current = handlers[name].map { Array($0.values) } ?? []
        lock.unlock()
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for handler in current { handler() }
            }
        }
    }

    fileprivate func remove(name: String, id: UUID) {
        lock.lock()
        handlers[name]?[id] = nil
        let isEmpty = handlers[name]?.isEmpty ?? true
        if isEmpty { handlers[name] = nil }
        lock.unlock()

        if isEmpty {
            CFNotificationCenterRemoveObserver(
                center, Unmanaged.passUnretained(self).toOpaque(), CFNotificationName(name as CFString), nil
            )
        }
    }

    /// Stops observing when cancelled or deallocated.
    final class Token: @unchecked Sendable {
        private let name: String
        private let id: UUID
        private weak var notifier: DarwinNotifier?
        private var cancelled = false

        fileprivate init(name: String, id: UUID, notifier: DarwinNotifier) {
            self.name = name
            self.id = id
            self.notifier = notifier
        }

        func cancel() {
            guard !cancelled else { return }
            cancelled = true
            notifier?.remove(name: name, id: id)
        }

        deinit { cancel() }
    }
}
