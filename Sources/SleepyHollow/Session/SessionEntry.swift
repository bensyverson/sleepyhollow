import Foundation

/// One session as the registry sees it: its name, what its helper wrote, and
/// what probing found.
///
/// This is the row `sleepy sessions list` renders and the value `prune`
/// filters on.
public struct SessionEntry: Friendly {
    /// The session's name.
    public let name: SessionName

    /// What the helper recorded when it started.
    public let record: SessionRecord

    /// What probing the process and the socket found, just now.
    public let liveness: SessionLiveness

    /// Creates an entry.
    public init(name: SessionName, record: SessionRecord, liveness: SessionLiveness) {
        self.name = name
        self.record = record
        self.liveness = liveness
    }

    /// One line for `sleepy sessions list`: name, pid, liveness, age, URL.
    ///
    /// A dead session says *why* it is dead, because that is the difference
    /// between "prune it" and "something is wrong with this machine".
    public var terseLine: String {
        let status: String = liveness.isLive ? "live" : "dead"
        let reason: String = liveness.isLive ? "" : (liveness.explanation.map { " (\($0))" } ?? "")
        let at: String = record.url.map { "  \($0.absoluteString)" } ?? ""
        return "\(name.rawValue)  pid \(record.processID)  \(status)\(reason)  \(Self.terseAge(record.age))\(at)"
    }

    /// `seconds` as the coarsest unit that still says something: `12s`, `4m`,
    /// `2h`. A session's age is context, never a measurement.
    static func terseAge(_ seconds: TimeInterval) -> String {
        let whole: Int = max(0, Int(seconds))
        if whole < 60 { return "\(whole)s" }
        if whole < 3600 { return "\(whole / 60)m" }
        return "\(whole / 3600)h"
    }
}
