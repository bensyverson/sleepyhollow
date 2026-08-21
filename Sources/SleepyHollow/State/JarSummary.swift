import Foundation

/// One line of `sleepy jars list`: a jar's name, how much it holds, and when
/// it last changed.
public struct JarSummary: Friendly {
    /// The jar's name.
    public var name: JarName

    /// How many cookies the jar currently holds, expired ones already pruned.
    public var cookieCount: Int

    /// When the jar was last written; `nil` when its file is missing or
    /// unreadable, which ``JarStore/summaries()`` reports rather than hides.
    public var updatedAt: Date?

    /// Creates a summary.
    public init(name: JarName, cookieCount: Int, updatedAt: Date?) {
        self.name = name
        self.cookieCount = cookieCount
        self.updatedAt = updatedAt
    }

    /// One terse line: name, cookie count, and the last write.
    public var terseLine: String {
        let noun: String = cookieCount == 1 ? "cookie" : "cookies"
        let written: String = updatedAt.map(CookieRecord.iso8601) ?? "never written"
        return "\(name.rawValue)  \(cookieCount) \(noun)  \(written)"
    }
}
