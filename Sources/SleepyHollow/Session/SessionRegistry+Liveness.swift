import Foundation

/// Probing and reaping: the half of the registry that decides who is alive.
public extension SessionRegistry {
    /// Probes `name` right now.
    ///
    /// Both halves must hold for ``SessionLiveness/live``: the recorded
    /// process must exist *and* something must accept a connection on the
    /// socket. Either alone lies — a `kill -9`'d helper leaves its socket file
    /// behind, and a recycled process id would vouch for a stranger.
    func liveness(of name: SessionName) -> SessionLiveness {
        guard let record: SessionRecord = record(for: name) else { return .noRecord }
        guard ProcessProbe.isAlive(record.processID) else { return .deadProcess }
        guard let path: String = try? socketPath(for: name), SocketProbe.isListening(atPath: path) else {
            return .unreachableSocket
        }
        return .live
    }

    /// `name`'s entry, probed, or `nil` when nothing on disk claims the name.
    func entry(for name: SessionName) -> SessionEntry? {
        guard let record: SessionRecord = record(for: name) else { return nil }
        return SessionEntry(name: name, record: record, liveness: liveness(of: name))
    }

    /// Every session with a readable record, sorted by name and probed.
    ///
    /// Directories without a readable record are debris rather than sessions;
    /// they are invisible here and swept by ``prune()``.
    func entries() -> [SessionEntry] {
        sessionDirectoryNames()
            .compactMap { name in entry(for: name) }
            .sorted { $0.name.rawValue < $1.name.rawValue }
    }

    /// Removes every session that is not live, and every directory that is not
    /// a readable session at all.
    ///
    /// This is the lazy reaping the vision doc describes: no daemon watches the
    /// fleet, so `list` and `prune` clean up whatever the last crash left.
    ///
    /// - Returns: the names removed, sorted.
    @discardableResult
    func prune() -> [SessionName] {
        var removed: [SessionName] = []
        for name in sessionDirectoryNames() where !liveness(of: name).isLive {
            remove(name)
            removed.append(name)
        }
        return removed.sorted { $0.rawValue < $1.rawValue }
    }

    /// The teaching failure for a name somebody already claimed.
    ///
    /// Naming a session is a claim: silently reusing another flow's cookies,
    /// scripts and history is the ambient state the vision doc forbids, so
    /// `open` fails loudly and the error separates the two intents — navigate
    /// the session you have, or replace it.
    func alreadyOpen(_ name: SessionName) -> SleepyError {
        var detail = ""
        if let existing: SessionRecord = record(for: name) {
            let at: String = existing.url.map { ", at \($0.absoluteString)" } ?? ""
            detail = " (\(Int(existing.age / 60))m\(at))"
        }
        return SleepyError(
            kind: .environment,
            message: "Session '\(name)' is already open\(detail).",
            nextMove: "`sleepy load --session \(name) <url>` navigates it, `sleepy close \(name)` replaces it.",
        )
    }

    /// The valid session names that have a directory under the root.
    ///
    /// A directory whose name fails ``SessionName``'s rule was not written by
    /// this tool; it is left strictly alone, because the root is a path a user
    /// can point anywhere.
    internal func sessionDirectoryNames() -> [SessionName] {
        let contents: [URL] = (try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
        )) ?? []
        return contents.compactMap { url in
            let isDirectory: Bool = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDirectory else { return nil }
            return SessionName(url.lastPathComponent)
        }
    }
}
