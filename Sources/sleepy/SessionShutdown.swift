import Foundation
import SleepyHollow

/// Ending a session, whichever verb asked — `sleepy close` and `sleepy
/// sessions close` are the same act under two spellings the vision doc uses.
///
/// Closing is idempotent by design: a helper that is already gone is not an
/// error, it is a directory to reap. What `close` guarantees is the thing a
/// caller actually needs — when it returns, the name is free for the next
/// `sleepy open`.
enum SessionShutdown {
    /// How long to wait for a helper to finish going away, in seconds.
    ///
    /// The helper answers the shutdown frame *before* it stops listening and
    /// deletes its directory, so returning the instant the reply lands would
    /// hand back a name that is not free yet.
    static let exitTimeout: TimeInterval = 10

    /// How often the wait re-probes, in seconds.
    static let pollInterval: TimeInterval = 0.05

    /// Closes `name`, waits for it to be gone, and reaps whatever is left.
    ///
    /// - Throws: `SleepyError` of kind `SleepyError.Kind.environment`
    ///   when nothing on disk ever claimed the name.
    static func close(_ name: SessionName, in registry: SessionRegistry) async throws {
        switch registry.liveness(of: name) {
        case .noRecord:
            throw SleepyError(
                kind: .environment,
                message: "No session named '\(name)'.",
                nextMove: "`sleepy sessions list` shows the sessions there are.",
            )
        case .deadProcess, .unreachableSocket:
            registry.remove(name)
        case .live:
            try await SessionClient(name: name, registry: registry).shutdown()
            await waitUntilGone(name, in: registry)
            registry.remove(name)
        }
    }

    /// Polls until the helper stops answering, or the timeout passes.
    private static func waitUntilGone(_ name: SessionName, in registry: SessionRegistry) async {
        let deadline = Date().addingTimeInterval(exitTimeout)
        while Date() < deadline {
            guard registry.liveness(of: name).isLive else { return }
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
    }
}
