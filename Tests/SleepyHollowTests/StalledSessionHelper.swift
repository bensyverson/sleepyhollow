import Foundation
import Network
@testable import SleepyHollow

/// A session helper that answers nothing: it claims a name in the registry,
/// listens on that session's socket, accepts every connection — and then goes
/// quiet, exactly like a helper whose main thread is wedged.
///
/// The double is the *wire protocol* rather than a stalled ``SessionHost``,
/// because that is the smaller apparatus for the question: the client's
/// deadline is a property of the socket conversation, so a listener plus a
/// ``SessionRecord`` is the whole helper it needs — no WebKit, no page, no
/// second process. The record names this process's own pid, so
/// ``SessionRegistry/liveness(of:)`` reports ``SessionLiveness/live`` and the
/// client gets as far as sending its request.
///
/// Accepted connections are held open on purpose: a dropped `NWConnection`
/// closes its socket, which the client reads as an EOF — a different failure
/// from the one under test.
final class StalledSessionHelper: @unchecked Sendable {
    /// The listener's queue, and the only place ``accepted`` is touched.
    private let queue = DispatchQueue(label: "sleepy.tests.stalled-helper")

    private let listener: NWListener

    /// Connections accepted and deliberately never read from or answered.
    /// Guarded by ``queue``, which is serial and is the listener's own queue.
    private var accepted: [NWConnection] = []

    private init(listener: NWListener) {
        self.listener = listener
    }

    /// Starts a silent helper for `name` and returns once a client would find
    /// it live.
    ///
    /// - Parameters:
    ///   - name: the session name to claim.
    ///   - registry: the throwaway root to claim it in.
    ///   - budget: what the record says this helper's own clock is, which a
    ///     client with no `--budget` of its own adopts.
    /// - Throws: whatever binding the session's socket throws, or a
    ///   ``SleepyError`` when the listener never comes up.
    static func start(
        name: SessionName,
        in registry: SessionRegistry,
        budget: TimeInterval = LoadOptions.defaultBudget,
    ) async throws -> StalledSessionHelper {
        let path: String = try registry.socketPath(for: name)
        try registry.createDirectory(for: name)
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: path)
        parameters.allowLocalEndpointReuse = true
        let helper = try StalledSessionHelper(listener: NWListener(using: parameters))
        helper.listener.newConnectionHandler = { [helper] connection in
            helper.keep(connection)
        }
        helper.listener.start(queue: helper.queue)
        try registry.write(
            SessionRecord(
                processID: getpid(),
                url: nil,
                startedAt: Date(),
                idleTimeout: 600,
                budget: budget,
            ),
            for: name,
        )
        try await helper.awaitListening(atPath: path)
        return helper
    }

    /// Cancels the listener and every connection it swallowed.
    func stop() {
        listener.cancel()
        queue.sync {
            for connection in accepted {
                connection.cancel()
            }
            accepted = []
        }
    }

    /// Adopts a connection and does nothing else with it, forever.
    private func keep(_ connection: NWConnection) {
        dispatchPrecondition(condition: .onQueue(queue))
        accepted.append(connection)
        connection.start(queue: queue)
    }

    /// Polls until the socket accepts connections. Bounded, because
    /// everything here is.
    private func awaitListening(atPath path: String) async throws {
        for _ in 0 ..< 300 {
            if SocketProbe.isListening(atPath: path) { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw SleepyError(
            kind: .environment,
            message: "The stalled test helper never started listening at '\(path)'.",
        )
    }
}
