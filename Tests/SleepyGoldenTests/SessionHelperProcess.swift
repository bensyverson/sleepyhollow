import Foundation
@testable import SleepyHollow

/// A real `sleepy _host` helper, spawned the way `sleepy open` will spawn one.
///
/// The golden session tests need the *binary*, not an in-process host: only a
/// separate process can be `kill -9`'d out from under the registry, and only
/// the binary proves the hidden subcommand is wired up.
struct SessionHelperProcess {
    /// The registry root the helper was pointed at, via `SLEEPYHOLLOW_HOME`.
    let root: URL

    /// The running helper.
    let process: Process

    /// A throwaway registry root, short enough for a Unix socket path.
    static func makeRoot() throws -> URL {
        let stamp = String(UInt32.random(in: 0 ..< UInt32.max), radix: 16)
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sg\(stamp)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// Launches `sleepy _host` against `root`.
    static func start(
        name: SessionName,
        url: URL?,
        root: URL,
        idleTimeout: Double? = nil,
    ) throws -> SessionHelperProcess {
        let process = Process()
        process.executableURL = GoldenBinary.productsDirectory().appendingPathComponent("sleepy")
        var arguments: [String] = ["_host", "--name", name.rawValue]
        if let url {
            arguments += ["--url", url.absoluteString]
        }
        if let idleTimeout {
            arguments += ["--idle-timeout", String(idleTimeout)]
        }
        process.arguments = arguments
        var environment: [String: String] = ProcessInfo.processInfo.environment
        environment[SessionRegistry.homeEnvironmentVariable] = root.path
        process.environment = environment
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        return SessionHelperProcess(root: root, process: process)
    }

    /// Waits until the registry reports the session live, or gives up.
    ///
    /// Returns `false` on the deadline rather than hanging — a helper that
    /// never comes up is a test failure, not a stuck suite.
    func waitUntilLive(_ name: SessionName, within seconds: Double = 20) async -> Bool {
        let registry = SessionRegistry(root: root)
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if registry.liveness(of: name).isLive { return true }
            guard process.isRunning else { return false }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    /// Waits until the helper's process has exited, or gives up.
    func waitUntilExited(within seconds: Double = 30) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if !process.isRunning { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    /// Kills the helper outright — the orphan the registry must detect.
    func kill() {
        guard process.isRunning else { return }
        Foundation.kill(process.processIdentifier, SIGKILL)
        process.waitUntilExit()
    }

    /// Kills the helper if it is still up and deletes the registry root.
    func tearDown() {
        kill()
        try? FileManager.default.removeItem(at: root)
    }
}
