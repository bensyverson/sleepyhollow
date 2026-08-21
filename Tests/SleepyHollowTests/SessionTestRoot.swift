import Foundation
@testable import SleepyHollow

/// A throwaway `~/.sleepyhollow` for session tests.
///
/// Every session test runs against one of these: the registry root is
/// overridable precisely so no test ever touches the real home directory. The
/// directory name is deliberately short — a Unix socket path must fit the
/// kernel's `sun_path` (104 bytes), and the system temporary directory already
/// spends about half of that.
enum SessionTestRoot {
    /// Creates an empty registry root under the system temporary directory.
    static func make() throws -> URL {
        let stamp = String(UInt32.random(in: 0 ..< UInt32.max), radix: 16)
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sh\(stamp)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Deletes a root created by ``make()``, ignoring what is left inside it.
    static func remove(_ root: URL) {
        try? FileManager.default.removeItem(at: root)
    }

    /// The pid of a process that has certainly exited — the stale-record case.
    static func exitedProcessID() throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try process.run()
        process.waitUntilExit()
        return process.processIdentifier
    }
}
