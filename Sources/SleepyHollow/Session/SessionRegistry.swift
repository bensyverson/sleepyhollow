import Foundation

/// The on-disk directory of named sessions: where they live, what they
/// recorded, and which of them are still alive.
///
/// The layout is one directory per session under the registry root:
///
/// ```text
/// ~/.sleepyhollow/sessions/<name>/sock          the helper's Unix socket
/// ~/.sleepyhollow/sessions/<name>/session.json  its SessionRecord
/// ```
///
/// The root is overridable — by `SLEEPYHOLLOW_HOME` or by ``init(root:)`` —
/// so tests, and anyone sandboxing the tool, never touch the real home
/// directory. There is no daemon behind this: the registry is just a reader of
/// what self-supervising helpers leave behind, which is why every question it
/// answers is answered by probing, never by trusting the file.
public struct SessionRegistry: Sendable {
    /// The environment variable that overrides the registry root.
    public static let homeEnvironmentVariable: String = "SLEEPYHOLLOW_HOME"

    /// The directory under `$HOME` used when nothing overrides the root.
    public static let defaultDirectoryName: String = ".sleepyhollow"

    /// The sessions directory's name inside the root.
    public static let sessionsDirectoryName: String = "sessions"

    /// The socket's file name inside a session's directory. Short on purpose:
    /// the whole path must fit what the kernel can address (104 bytes), which
    /// ``socketPath(for:)`` enforces.
    public static let socketFileName: String = "sock"

    /// The record's file name inside a session's directory.
    public static let recordFileName: String = "session.json"

    /// Where this registry looks for sessions.
    public let root: URL

    /// Creates a registry over `root`, defaulting to ``defaultRoot(environment:)``.
    public init(root: URL = SessionRegistry.defaultRoot()) {
        self.root = root
    }

    /// The root `SLEEPYHOLLOW_HOME` names, or `~/.sleepyhollow`.
    public static func defaultRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
    ) -> URL {
        if let override = environment[homeEnvironmentVariable], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(defaultDirectoryName)
    }

    // MARK: - Layout

    /// The directory holding every session's directory.
    public var sessionsDirectory: URL {
        root.appendingPathComponent(Self.sessionsDirectoryName)
    }

    /// Where `name`'s socket and record live.
    public func directory(for name: SessionName) -> URL {
        sessionsDirectory.appendingPathComponent(name.rawValue)
    }

    /// Where `name`'s record file lives.
    public func recordURL(for name: SessionName) -> URL {
        directory(for: name).appendingPathComponent(Self.recordFileName)
    }

    /// The path of `name`'s Unix socket.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the path would exceed what the kernel can address. Truncating instead
    ///   would bind a socket at a path nothing could find, and `Network`'s
    ///   client side traps outright — so this fails early and says where to
    ///   put the root instead.
    public func socketPath(for name: SessionName) throws -> String {
        let path: String = directory(for: name).appendingPathComponent(Self.socketFileName).path
        guard path.utf8.count <= SocketProbe.maximumPathLength else {
            throw SleepyError(
                kind: .environment,
                message: "The socket path for session '\(name)' is \(path.utf8.count) bytes; "
                    + "a Unix socket path can be at most \(SocketProbe.maximumPathLength).",
                nextMove: "Point \(Self.homeEnvironmentVariable) at a shorter directory, or use a shorter name.",
            )
        }
        return path
    }

    // MARK: - Records

    /// Creates `name`'s directory if it is not already there.
    public func createDirectory(for name: SessionName) throws {
        try FileManager.default.createDirectory(
            at: directory(for: name),
            withIntermediateDirectories: true,
        )
    }

    /// Reads `name`'s record, or `nil` when there is none to read.
    public func record(for name: SessionName) -> SessionRecord? {
        guard let data: Data = try? Data(contentsOf: recordURL(for: name)) else { return nil }
        return try? JSONDecoder().decode(SessionRecord.self, from: data)
    }

    /// Writes `record` for `name`, creating the session's directory first.
    public func write(_ record: SessionRecord, for name: SessionName) throws {
        try createDirectory(for: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: recordURL(for: name), options: .atomic)
    }

    /// Deletes `name`'s directory, socket and record included. Removing a
    /// session that is not there is a no-op.
    public func remove(_ name: SessionName) {
        try? FileManager.default.removeItem(at: directory(for: name))
    }
}
