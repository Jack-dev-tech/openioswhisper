import Foundation

/// Names shared by the app and the keyboard.
public enum IPC {
    public static let appGroupID = "group.com.jackmatsuzaki.openwhisper"
    public static let urlScheme = "openwhisper"
    /// Opened by the keyboard to start a background session and begin recording right away,
    /// so the user can swipe back to their app and keep talking.
    public static let startSessionURL = URL(string: "openwhisper://session?record=1")!

    /// Whether a session URL asks the app to start recording as soon as the session is up.
    public static func wantsRecording(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains { $0.name == "record" && $0.value == "1" } ?? false
    }

    /// Darwin notification names. They carry no payload: data travels through `SharedStore`.
    public enum Notification {
        /// Keyboard → app: start recording.
        public static let start = "com.jackmatsuzaki.openwhisper.start"
        /// Keyboard → app: stop recording and transcribe.
        public static let stop = "com.jackmatsuzaki.openwhisper.stop"
        /// Keyboard → app: stop recording and throw the audio away.
        public static let cancel = "com.jackmatsuzaki.openwhisper.cancel"
        /// App → keyboard: a new transcript is in the store.
        public static let result = "com.jackmatsuzaki.openwhisper.result"
        /// App → keyboard: the session status changed.
        public static let status = "com.jackmatsuzaki.openwhisper.status"
        /// Either side: settings were changed, reload them.
        public static let settings = "com.jackmatsuzaki.openwhisper.settings"
    }

    /// The app writes a heartbeat this often, and the keyboard treats a session as gone after `heartbeatTimeout`.
    public static let heartbeatInterval: TimeInterval = 1
    public static let heartbeatTimeout: TimeInterval = 3
    /// A transcript older than this is never inserted.
    public static let resultMaxAge: TimeInterval = 120
}

public enum SessionPhase: String, Codable, Sendable {
    /// No session: the keyboard has to open the app.
    case inactive
    /// Session running, microphone open, not recording.
    case ready
    case recording
    case transcribing
    /// The last dictation failed; `message` says why. Recording can start again.
    case failed
}

/// The app's session state, written by the app and read by the keyboard.
public struct SessionStatus: Codable, Equatable, Sendable {
    public var phase: SessionPhase
    public var message: String?
    /// Input level from 0 to 1 while recording.
    public var level: Float
    public var heartbeat: Date
    /// When the session will end if nothing else happens. Nil means no timeout.
    public var expiresAt: Date?

    public init(phase: SessionPhase, message: String? = nil, level: Float = 0, heartbeat: Date = Date(), expiresAt: Date? = nil) {
        self.phase = phase
        self.message = message
        self.level = level
        self.heartbeat = heartbeat
        self.expiresAt = expiresAt
    }

    public static let inactive = SessionStatus(phase: .inactive, heartbeat: .distantPast)

    /// Whether the app is running a session right now. A stale heartbeat means the app was killed.
    public func isAlive(now: Date = Date()) -> Bool {
        phase != .inactive && now.timeIntervalSince(heartbeat) < IPC.heartbeatTimeout
    }

    /// Whether the keyboard can start a new recording.
    public func canStartRecording(now: Date = Date()) -> Bool {
        isAlive(now: now) && (phase == .ready || phase == .failed)
    }
}

/// A finished transcript waiting for the keyboard to insert it.
public struct TranscriptResult: Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date

    public init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
    }

    /// Whether the keyboard should insert this result: not already inserted, and recent.
    public func shouldInsert(lastConsumedID: UUID?, now: Date = Date()) -> Bool {
        id != lastConsumedID
            && now.timeIntervalSince(createdAt) < IPC.resultMaxAge
            && !text.isEmpty
    }
}

/// Written by the keyboard each time it appears, so the app can tell that it is installed with Full Access.
public struct KeyboardCheckIn: Codable, Equatable, Sendable {
    public var date: Date
    public init(date: Date = Date()) { self.date = date }
}
