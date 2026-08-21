import Foundation

/// The thin client behind every `--session` verb: connect by name, ship one
/// operation, take the typed answer back.
///
/// The same ``PageOperation`` value a one-shot invocation executes locally
/// travels here as an ``OperationEnvelope`` and comes back as its own
/// `Output` — so a verb's code differs between "a URL" and "a session" only
/// in which of the two it calls.
///
/// Every failure is a ``SleepyError`` that teaches: a name nobody claimed, a
/// helper that died, a socket that will not answer. A helper that vanishes
/// mid-operation closes its socket, which arrives here as an error rather than
/// a wait. The clock for the work itself lives *host*-side, in the page host's
/// budget: this side bounds only the connection, because only the helper knows
/// when its page gave up.
///
/// ```swift
/// let facts: PageFacts = try await SessionClient(name: name).run(operation)
/// ```
public struct SessionClient: Sendable {
    /// The session to talk to.
    public let name: SessionName

    /// Where that session's directory is looked up.
    public let registry: SessionRegistry

    /// How long a connection may take to come up, in seconds.
    public let connectTimeout: TimeInterval

    /// Creates a client. Nothing connects until a request is sent.
    public init(
        name: SessionName,
        registry: SessionRegistry = SessionRegistry(),
        connectTimeout: TimeInterval = 5,
    ) {
        self.name = name
        self.registry = registry
        self.connectTimeout = connectTimeout
    }

    /// Runs `operation` in the session and returns its output.
    ///
    /// - Throws: the helper's own ``SleepyError`` when the operation failed
    ///   there, or one of kind ``SleepyError/Kind/environment`` when the
    ///   session is missing, dead, or unreachable.
    public func run<Operation: PageOperation>(_ operation: Operation) async throws -> Operation.Output {
        let reply: SessionReply = try await send(.operation(OperationEnvelope(operation)))
        switch reply {
        case let .output(payload):
            return try JSONDecoder().decode(Operation.Output.self, from: payload)
        case .acknowledged:
            throw SleepyError(
                kind: .environment,
                message: "Session '\(name)' acknowledged '\(Operation.kind)' without answering it.",
                nextMove: "The helper is from a different build — `sleepy close \(name)` and open it again.",
            )
        case let .failure(error):
            throw error
        }
    }

    /// Asks the helper to shut down, and waits for it to say it will.
    public func shutdown() async throws {
        _ = try await send(.shutdown)
    }

    /// Sends one request over a fresh connection and reads one reply.
    ///
    /// A connection per request: sessions are driven by separate CLI
    /// invocations, so a long-lived one would have nobody to belong to.
    private func send(_ request: SessionRequest) async throws -> SessionReply {
        let liveness: SessionLiveness = registry.liveness(of: name)
        guard liveness.isLive else { throw unreachable(liveness) }
        let path: String = try registry.socketPath(for: name)
        let connection: SessionConnection = try await SessionConnection.connect(
            toPath: path,
            timeout: connectTimeout,
        )
        do {
            try await connection.send(request)
            guard let reply: SessionReply = try await connection.receive(SessionReply.self) else {
                await connection.close()
                throw SleepyError(
                    kind: .environment,
                    message: "Session '\(name)' closed its socket without answering.",
                    nextMove: "Its helper probably died mid-operation — `sleepy sessions prune`, then open it again.",
                )
            }
            await connection.close()
            return reply
        } catch {
            await connection.close()
            throw error
        }
    }

    /// The teaching error for a session that cannot take work.
    private func unreachable(_ liveness: SessionLiveness) -> SleepyError {
        switch liveness {
        case .live:
            return SleepyError(kind: .environment, message: "Session '\(name)' is live.")
        case .noRecord:
            return SleepyError(
                kind: .environment,
                message: "No session named '\(name)'.",
                nextMove: "`sleepy sessions list` shows the open sessions; `sleepy open <url> --name \(name)` starts this one.",
            )
        case .deadProcess, .unreachableSocket:
            let reason: String = liveness.explanation ?? "it is not answering"
            return SleepyError(
                kind: .environment,
                message: "Session '\(name)' is not running: \(reason).",
                nextMove: "`sleepy sessions prune` clears it, then `sleepy open <url> --name \(name)` starts a live one.",
            )
        }
    }
}
