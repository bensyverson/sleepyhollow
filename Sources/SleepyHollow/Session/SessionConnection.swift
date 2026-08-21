import Foundation
import Network

/// One framed conversation over a session's Unix socket, in either direction.
///
/// An actor because a connection has exactly one piece of shared mutable
/// state — the bytes read but not yet framed — and both ends want it behind a
/// single access point. `Network.framework` carries the bytes: it gives the
/// same async shape the fixture server already uses, with no descriptor
/// bookkeeping. Its one trap is guarded here — a connection to a socket
/// nobody is listening on enters `.waiting` and retries *forever*, so waiting
/// is treated as the refusal it is.
actor SessionConnection {
    private let connection: NWConnection
    private var buffer = Data()
    private var isClosed = false

    /// Adopts a connection a listener just accepted, starting it.
    init(adopting connection: NWConnection, queue: DispatchQueue = DispatchQueue.global()) {
        self.connection = connection
        connection.start(queue: queue)
    }

    private init(connected connection: NWConnection) {
        self.connection = connection
    }

    /// Connects to the socket at `path`, inside `timeout` seconds.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   nothing is listening, the path is unaddressable, or the connection
    ///   does not come up in time.
    static func connect(toPath path: String, timeout: TimeInterval = 5) async throws -> SessionConnection {
        guard path.utf8.count <= SocketProbe.maximumPathLength else {
            throw SleepyError(
                kind: .environment,
                message: "The socket path '\(path)' is longer than a Unix socket path can be.",
                nextMove: "Point \(SessionRegistry.homeEnvironmentVariable) at a shorter directory.",
            )
        }
        let parameters = NWParameters()
        parameters.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        let connection = NWConnection(to: NWEndpoint.unix(path: path), using: parameters)
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
            connection.cancel()
        }
        defer { timeoutTask.cancel() }
        do {
            try await awaitReady(connection)
        } catch {
            connection.cancel()
            throw error
        }
        return SessionConnection(connected: connection)
    }

    /// Sends `value` as one frame.
    func send(_ value: some Encodable) async throws {
        let frame: Data = try SessionFrame.encode(value)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.send(
                content: frame,
                completion: NWConnection.SendCompletion.contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                },
            )
        }
    }

    /// Reads until one whole frame arrives and decodes it.
    ///
    /// - Returns: `nil` when the peer closed without sending another frame.
    func receive<Value: Decodable>(_ type: Value.Type) async throws -> Value? {
        while true {
            if let value: Value = try SessionFrame.decode(type, from: &buffer) { return value }
            guard let chunk: Data = try await receiveChunk() else { return nil }
            buffer.append(chunk)
        }
    }

    /// Closes the connection. Closing twice is a no-op.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        connection.cancel()
    }

    // MARK: - Network bridging

    private func receiveChunk(maximumLength: Int = 65536) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: maximumLength) { data, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, !data.isEmpty {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(returning: Data())
                }
            }
        }
    }

    /// Waits for the connection to become ready, treating `.waiting` as the
    /// refusal it is on a local socket.
    private static func awaitReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    continuation.resume()
                case let .waiting(error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: connectionFailure(error))
                case let .failed(error):
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: connectionFailure(error))
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    continuation.resume(throwing: SleepyError(
                        kind: .environment,
                        message: "The session socket did not answer in time.",
                        nextMove: "`sleepy sessions list` shows which sessions are still alive.",
                    ))
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue.global())
        }
    }

    private static func connectionFailure(_ error: NWError) -> SleepyError {
        SleepyError(
            kind: .environment,
            message: "Could not reach the session's helper: \(error.localizedDescription).",
            nextMove: "`sleepy sessions prune` clears dead sessions; reopen the session to get a live one.",
        )
    }
}
