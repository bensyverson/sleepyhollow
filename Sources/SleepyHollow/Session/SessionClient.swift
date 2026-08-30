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
/// a wait.
///
/// ## The client owns a deadline
///
/// The whole exchange — connect, send, wait for the reply — is bounded by
/// ``deadline(forBudget:)``: the operation's budget plus ``transportMargin``.
/// The helper has a clock of its own on the *work*, and it is the only process
/// that knows when its page gave up, so the reply normally arrives well
/// inside this one. But a helper that accepts a request and then stops
/// answering has no clock at all, and until 2026-08-29 that hung the client
/// for as long as the helper lived: under machine-wide load three helpers
/// parked their main thread in WebKit's synchronous IPC and their clients
/// waited 7–11 minutes past a 60 s budget (job issue MN69b). "Nothing hangs"
/// is a promise this side has to keep on its own, so when the deadline
/// passes the connection is cancelled and the request fails with a
/// ``SleepyError/Kind/timeout`` naming the session, the verb and the budget.
///
/// There is only ever *one* budget in play, never a second one invented here:
/// this invocation's `--budget` when it carried one, and otherwise the
/// helper's own — ``SessionRecord/budget``, written when the session opened
/// and read back off the same record the liveness probe already reads.
///
/// ```swift
/// let facts: PageFacts = try await SessionClient(name: name).run(operation)
/// ```
public struct SessionClient: Sendable {
    /// What the deadline adds to ``budget`` for the socket itself: connecting,
    /// framing, and the hop back onto this process's main actor.
    ///
    /// Fixed and small on purpose. It exists so that a helper which really did
    /// spend its whole budget on the page still gets its answer through
    /// instead of racing the client's clock; it is not a second budget.
    public static let transportMargin: TimeInterval = 2

    /// How long a connection may take to come up when the caller says nothing.
    public static let defaultConnectTimeout: TimeInterval = 5

    /// The session to talk to.
    public let name: SessionName

    /// Where that session's directory is looked up.
    public let registry: SessionRegistry

    /// This invocation's ceiling in seconds — the CLI's `--budget` — or `nil`
    /// to take the helper's own, ``SessionRecord/budget``.
    public let budget: TimeInterval?

    /// How long a connection may take to come up, in seconds.
    public let connectTimeout: TimeInterval

    /// Creates a client. Nothing connects until a request is sent.
    ///
    /// - Parameters:
    ///   - name: the session to talk to.
    ///   - registry: where that session's directory is looked up.
    ///   - budget: this invocation's ceiling in seconds; `nil` defers to the
    ///     budget the session recorded when it opened.
    ///   - connectTimeout: how long the connection itself may take to come up;
    ///     it is bounded by the request's deadline whatever it says.
    public init(
        name: SessionName,
        registry: SessionRegistry = SessionRegistry(),
        budget: TimeInterval? = nil,
        connectTimeout: TimeInterval = SessionClient.defaultConnectTimeout,
    ) {
        self.name = name
        self.registry = registry
        self.budget = budget
        self.connectTimeout = connectTimeout
    }

    /// The whole request's ceiling for a given budget: `budget` plus
    /// ``transportMargin``.
    public static func deadline(forBudget budget: TimeInterval) -> TimeInterval {
        budget + transportMargin
    }

    /// Runs `operation` in the session and returns its output.
    ///
    /// - Throws: the helper's own ``SleepyError`` when the operation failed
    ///   there, one of kind ``SleepyError/Kind/environment`` when the session
    ///   is missing, dead, or unreachable, or one of kind
    ///   ``SleepyError/Kind/timeout`` when the helper took the request and did
    ///   not answer inside its deadline.
    public func run<Operation: PageOperation>(_ operation: Operation) async throws -> Operation.Output {
        let reply: SessionReply = try await send(
            .operation(OperationEnvelope(operation)),
            verb: Operation.kind,
        )
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
        _ = try await send(.shutdown, verb: "shutdown")
    }

    /// Sends one request over a fresh connection and reads one reply, inside the
    /// request's deadline.
    ///
    /// A connection per request: sessions are driven by separate CLI
    /// invocations, so a long-lived one would have nobody to belong to.
    ///
    /// The deadline is a task that cancels the connection rather than a race
    /// between two children of a task group: cancelling a Swift task does not
    /// interrupt an `NWConnection` receive, so a group would still wait for
    /// the child it had cancelled. Closing the socket is what actually lets
    /// the read finish.
    private func send(_ request: SessionRequest, verb: String) async throws -> SessionReply {
        guard let entry: SessionEntry = registry.entry(for: name) else { throw unreachable(.noRecord) }
        guard entry.liveness.isLive else { throw unreachable(entry.liveness) }
        let ceiling: TimeInterval = budget ?? entry.record.budget
        let path: String = try registry.socketPath(for: name)
        let expiresAt = Date().addingTimeInterval(Self.deadline(forBudget: ceiling))
        let connection: SessionConnection = try await SessionConnection.connect(
            toPath: path,
            timeout: min(connectTimeout, max(0, expiresAt.timeIntervalSinceNow)),
        )
        let expiry = Expiry()
        let deadlineTask = Task {
            let remaining: TimeInterval = max(0, expiresAt.timeIntervalSinceNow)
            try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            await expiry.expire()
            await connection.close()
        }
        defer { deadlineTask.cancel() }
        do {
            try await connection.send(request)
            if let reply: SessionReply = try await connection.receive(SessionReply.self) {
                await connection.close()
                return reply
            }
            await connection.close()
        } catch {
            await connection.close()
            if await expiry.hasExpired { throw timedOut(verb, budget: ceiling) }
            throw error
        }
        if await expiry.hasExpired { throw timedOut(verb, budget: ceiling) }
        throw SleepyError(
            kind: .environment,
            message: "Session '\(name)' closed its socket without answering.",
            nextMove: "Its helper probably died mid-operation — `sleepy sessions prune`, then open it again.",
        )
    }

    /// The teaching error for a helper that took the request and went quiet.
    private func timedOut(_ verb: String, budget: TimeInterval) -> SleepyError {
        SleepyError(
            kind: .timeout,
            message: "Session '\(name)' took the '\(verb)' request and did not answer "
                + "within its \(Self.seconds(budget)) budget.",
            nextMove: "The helper may be wedged. `sleepy sessions list` says whether it is still alive; "
                + "`sleepy close \(name)` ends it, and `sleepy open <url> --name \(name)` starts a fresh one. "
                + "If the page genuinely needs longer, --budget on this verb raises the wait.",
        )
    }

    /// A budget as an agent should read it back: `30s`, `2.5s`.
    private static func seconds(_ value: TimeInterval) -> String {
        String(format: "%gs", value)
    }

    /// The teaching error for a session that cannot take work.
    private func unreachable(_ liveness: SessionLiveness) -> SleepyError {
        switch liveness {
        case .live:
            return SleepyError(
                kind: .environment,
                message: "Session '\(name)' is live, but this operation was refused before reaching it.",
                nextMove: "Retry; if it happens again, `sleepy close \(name)` and open it fresh.",
            )
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

    /// One request's expiry flag.
    ///
    /// Cancelling the connection is how the deadline unblocks the read, so the
    /// read fails with a socket error; this is what tells the difference
    /// between that and a helper that really did die, so the client reports
    /// the timeout it caused rather than blaming the helper for it.
    private actor Expiry {
        /// Whether the deadline passed before the reply did.
        private(set) var hasExpired = false

        /// Records that the deadline passed.
        func expire() {
            hasExpired = true
        }
    }
}
