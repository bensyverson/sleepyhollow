import Foundation

/// What one jar holds on disk: `<home>/jars/<name>/cookies.json`.
///
/// A versioned envelope rather than a bare array so the format can grow —
/// a jar is the one thing in the tool that outlives an invocation, and a
/// file that cannot say what it is cannot be migrated.
public struct CookieJarFile: Friendly {
    /// The format version this build writes.
    public static let currentVersion: Int = 1

    /// The format version this file was written with.
    public var version: Int

    /// When the jar was last written.
    public var updatedAt: Date

    /// The cookies the jar holds.
    public var cookies: [CookieRecord]

    /// Creates a jar file.
    public init(
        cookies: [CookieRecord],
        updatedAt: Date = Date(),
        version: Int = CookieJarFile.currentVersion,
    ) {
        self.cookies = cookies
        self.updatedAt = updatedAt
        self.version = version
    }
}
