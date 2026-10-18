import Foundation

/// Small JSON files in the App Group container that the app and the keyboard both read and write.
///
/// Files rather than shared UserDefaults: each read goes to disk, so one process always sees
/// the other's latest atomic write without waiting for a defaults sync.
public final class SharedStore: @unchecked Sendable {
    public let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL) {
        self.directory = directory
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithFractionalSeconds
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    #if os(iOS) || os(macOS)
    /// The store in the shared App Group container, or nil when the container is unavailable
    /// (for example, a keyboard without Full Access).
    public static func appGroup() -> SharedStore? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: IPC.appGroupID) else {
            return nil
        }
        let directory = container.appendingPathComponent("Shared", isDirectory: true)
        let store = SharedStore(directory: directory)
        return store.isWritable ? store : nil
    }
    #endif

    /// Whether this process can write to the store.
    public var isWritable: Bool {
        FileManager.default.isWritableFile(atPath: directory.path)
    }

    // MARK: - Values

    public func loadSettings() -> DictationSettings {
        read(DictationSettings.self, from: .settings) ?? DictationSettings()
    }

    public func saveSettings(_ settings: DictationSettings) {
        write(settings, to: .settings)
    }

    public func loadStatus() -> SessionStatus {
        read(SessionStatus.self, from: .status) ?? .inactive
    }

    public func saveStatus(_ status: SessionStatus) {
        write(status, to: .status)
    }

    public func loadResult() -> TranscriptResult? {
        read(TranscriptResult.self, from: .result)
    }

    public func saveResult(_ result: TranscriptResult) {
        write(result, to: .result)
    }

    /// The id of the last transcript a keyboard inserted, so no keyboard inserts it twice.
    public func loadConsumedResultID() -> UUID? {
        read(UUID.self, from: .consumed)
    }

    public func saveConsumedResultID(_ id: UUID) {
        write(id, to: .consumed)
    }

    public func loadKeyboardCheckIn() -> KeyboardCheckIn? {
        read(KeyboardCheckIn.self, from: .keyboardCheckIn)
    }

    public func saveKeyboardCheckIn(_ checkIn: KeyboardCheckIn) {
        write(checkIn, to: .keyboardCheckIn)
    }

    // MARK: - Files

    enum File: String {
        case settings = "settings.json"
        case status = "status.json"
        case result = "result.json"
        case consumed = "consumed.json"
        case keyboardCheckIn = "keyboard.json"
    }

    func url(for file: File) -> URL {
        directory.appendingPathComponent(file.rawValue)
    }

    private func read<Value: Decodable>(_ type: Value.Type, from file: File) -> Value? {
        guard let data = try? Data(contentsOf: url(for: file)) else { return nil }
        return try? decoder.decode(Value.self, from: data)
    }

    private func write<Value: Encodable>(_ value: Value, to file: File) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(for: file), options: .atomic)
    }
}

extension JSONEncoder.DateEncodingStrategy {
    /// ISO 8601 with milliseconds: heartbeats and result ordering need sub-second precision.
    static var iso8601WithFractionalSeconds: Self {
        .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.formatter().string(from: date))
        }
    }
}

extension JSONDecoder.DateDecodingStrategy {
    static var iso8601WithFractionalSeconds: Self {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = ISO8601.formatter().date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(string)")
            }
            return date
        }
    }
}

private enum ISO8601 {
    static func formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
