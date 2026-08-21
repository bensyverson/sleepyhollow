import Foundation
import Network

/// The helper loop behind a named session: one page, one socket, one clock.
///
/// A host claims a name, listens on `~/.sleepyhollow/sessions/<name>/sock`,
/// owns a single ``PageHost`` on the main actor, and answers
/// ``SessionRequest``s by decoding each ``OperationEnvelope`` with the
/// ``OperationRegistry`` it was built with and executing it against that page.
/// Because the operation registry is injected, the session layer never learns
/// what verbs exist — the seam the whole design turns on.
///
/// **Nobody supervises this.** There is no daemon: a host self-terminates
/// after its idle timeout (``defaultIdleTimeout`` unless the caller says
/// otherwise) passes without work, or when a client sends
/// ``SessionRequest/shutdown``, and it takes its directory with it on the way
/// out. What a crash leaves behind is reaped lazily by ``SessionRegistry``.
///
/// ```swift
/// let host = SessionHost(name: name, url: url, registry: SessionRegistry())
/// try await host.start()          // listening, page loaded
/// await host.waitUntilStopped()   // returns on shutdown or idle TTL
/// ```
@MainActor
public final class SessionHost {
    /// How long a session may sit idle before its helper exits: 15 minutes.
    ///
    /// Long enough that a human-paced multi-step flow never loses its page,
    /// short enough that a forgotten session is not a permanent process.
    public nonisolated static let defaultIdleTimeout: TimeInterval = 15 * 60

    /// How long ``start()`` waits for the socket to bind before giving up.
    public nonisolated static let bindTimeout: TimeInterval = 10

    /// The session's name.
    public let name: SessionName

    /// Where this host's directory lives.
    public let registry: SessionRegistry

    /// The page every operation runs against.
    public let page: PageHost

    /// What this host wrote to disk once it was listening; `nil` before
    /// ``start()`` and after ``stop()``.
    public private(set) var record: SessionRecord?

    /// What this helper can decode and run — read by the serving half.
    let operations: OperationRegistry

    /// Whether the host has stopped — read by the serving half.
    private(set) var isStopped = false

    private let url: URL?
    private let idleTimeout: TimeInterval

    private var listener: NWListener?
    private(set) var lastActivity: Date = .init()
    private var idleTask: Task<Void, Never>?
    private var isReady = false
    private var didClaim = false
    private var readyWaiters: [CheckedContinuation<Void, Never>] = []
    private var stopWaiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a host. Nothing touches the filesystem until ``start()``.
    ///
    /// - Parameters:
    ///   - name: the session's name; it becomes a directory under the registry.
    ///   - url: loaded before the session answers any work, when given.
    ///   - options: the load options the page is built with.
    ///   - registry: where the session directory goes.
    ///   - operations: the operations this helper can decode and run.
    ///   - idleTimeout: seconds of idleness before self-termination.
    public init(
        name: SessionName,
        url: URL?,
        options: LoadOptions = LoadOptions(),
        registry: SessionRegistry = SessionRegistry(),
        operations: OperationRegistry = SessionOperations.registry,
        idleTimeout: TimeInterval = SessionHost.defaultIdleTimeout,
    ) {
        self.name = name
        self.url = url
        self.registry = registry
        self.operations = operations
        self.idleTimeout = idleTimeout
        page = PageHost(options: options)
    }

    /// Claims the name, starts listening, records the helper, and loads the
    /// session's URL. Returns once the session is ready for work.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the name is already open or the socket cannot be bound, or whatever
    ///   ``PageHost/load(_:)`` throws for the initial URL — in which case the
    ///   host has already cleaned up after itself.
    public func start() async throws {
        guard listener == nil, !isStopped else {
            throw SleepyError(
                kind: .usage,
                message: "This session host has already been started.",
                nextMove: "Create one host per session.",
            )
        }
        let path: String = try claimSocketPath()
        let listener: NWListener = try makeListener(atPath: path)
        self.listener = listener
        try await awaitReady(listener, atPath: path)

        let record = SessionRecord(
            processID: getpid(),
            url: url,
            startedAt: Date(),
            idleTimeout: idleTimeout,
        )
        try registry.write(record, for: name)
        self.record = record
        noteActivity()
        startIdleTimer()

        do {
            if let url {
                try await page.load(url)
            }
        } catch {
            await stop()
            throw error
        }
        becomeReady()
    }

    /// Suspends until the host stops — the helper process's whole main loop.
    public func waitUntilStopped() async {
        guard !isStopped else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            stopWaiters.append(continuation)
        }
    }

    /// ``start()`` followed by ``waitUntilStopped()``: what `sleepy _host` runs.
    public func run() async throws {
        try await start()
        await waitUntilStopped()
    }

    /// Stops listening and deletes the session's directory. Stopping twice is
    /// a no-op.
    public func stop() async {
        guard !isStopped else { return }
        isStopped = true
        idleTask?.cancel()
        idleTask = nil
        listener?.cancel()
        listener = nil
        record = nil
        // Only ever delete a directory this host claimed: another helper may
        // own this name, and a host that failed to claim it must leave it be.
        // The listener never unlinks its socket, so removing the directory is
        // what frees the name for the next `open`.
        if didClaim {
            registry.remove(name)
            didClaim = false
        }
        becomeReady()
        let waiting: [CheckedContinuation<Void, Never>] = stopWaiters
        stopWaiters = []
        for continuation in waiting {
            continuation.resume()
        }
    }

    // MARK: - Claiming and listening

    /// The socket path to bind, once we know nobody else owns this name.
    private func claimSocketPath() throws -> String {
        let path: String = try registry.socketPath(for: name)
        guard !SocketProbe.isListening(atPath: path) else {
            throw alreadyOpen()
        }
        // Whatever is left here belongs to a helper that is gone: the record
        // is stale and the socket file is debris a fresh bind would trip over.
        registry.remove(name)
        try registry.createDirectory(for: name)
        didClaim = true
        return path
    }

    private func alreadyOpen() -> SleepyError {
        var detail = ""
        if let existing: SessionRecord = registry.record(for: name) {
            let at: String = existing.url.map { ", at \($0.absoluteString)" } ?? ""
            detail = " (\(Int(existing.age / 60))m\(at))"
        }
        return SleepyError(
            kind: .environment,
            message: "Session '\(name)' is already open\(detail).",
            nextMove: "`sleepy load --session \(name) <url>` navigates it, `sleepy close \(name)` replaces it.",
        )
    }

    private func makeListener(atPath path: String) throws -> NWListener {
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: path)
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.adopt(connection)
                }
            }
            return listener
        } catch {
            throw bindFailure(path: path, reason: "\(error)")
        }
    }

    /// Starts `listener` and waits for it to bind, inside ``bindTimeout``.
    ///
    /// The wait is bounded because everything here is: a listener that never
    /// reaches `.ready` would otherwise be a helper stuck before it ever
    /// served anything, which is the hang the tool refuses to have.
    private func awaitReady(_ listener: NWListener, atPath path: String) async throws {
        let deadline = Task { @MainActor in
            try await Task.sleep(nanoseconds: UInt64(Self.bindTimeout * 1_000_000_000))
            listener.cancel()
        }
        let failure: SleepyError? = await withCheckedContinuation { (continuation: CheckedContinuation<SleepyError?, Never>) in
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: nil)
                case let .failed(error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: SessionHost.bindFailure(
                        path: path,
                        reason: error.localizedDescription,
                    ))
                case .cancelled:
                    listener.stateUpdateHandler = nil
                    continuation.resume(returning: SessionHost.bindFailure(
                        path: path,
                        reason: "it did not start listening within \(Self.bindTimeout)s",
                    ))
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue.global())
        }
        deadline.cancel()
        if let failure {
            await stop()
            throw failure
        }
    }

    private func bindFailure(path: String, reason: String) -> SleepyError {
        Self.bindFailure(path: path, reason: reason)
    }

    private nonisolated static func bindFailure(path: String, reason: String) -> SleepyError {
        SleepyError(
            kind: .environment,
            message: "Could not listen on '\(path)': \(reason).",
            nextMove: "`sleepy sessions prune` clears dead sessions, then open this one again.",
        )
    }

    // MARK: - Readiness and idleness

    /// Suspends until the session's first load has finished.
    func waitUntilReady() async {
        guard !isReady else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            readyWaiters.append(continuation)
        }
    }

    private func becomeReady() {
        guard !isReady else { return }
        isReady = true
        let waiting: [CheckedContinuation<Void, Never>] = readyWaiters
        readyWaiters = []
        for continuation in waiting {
            continuation.resume()
        }
    }

    /// Restarts the idle clock; the serving half calls it around every request.
    func noteActivity() {
        lastActivity = Date()
    }

    /// The clock lives host-side, never in the page: a headless web view
    /// throttles its own timers, so only the host can be trusted to notice
    /// that nothing has happened for a quarter of an hour.
    private func startIdleTimer() {
        guard idleTimeout > 0 else { return }
        idleTask = Task { @MainActor [weak self] in
            while true {
                guard let self, !isStopped else { return }
                let remaining: TimeInterval = lastActivity.addingTimeInterval(idleTimeout).timeIntervalSinceNow
                if remaining <= 0 {
                    await stop()
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000) + 10_000_000)
                if Task.isCancelled { return }
            }
        }
    }
}
