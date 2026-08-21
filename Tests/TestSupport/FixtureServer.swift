import Foundation
import Network

/// An in-process HTTP server for tests: real `http://127.0.0.1` URLs so
/// cookies, wire observation and navigation behave honestly, with no
/// dependency beyond Network.framework.
///
/// The server binds an ephemeral port, serves static files from a fixtures
/// directory (see ``FixturePage`` for the shared pages), and supports
/// dynamic routes registered as closures. Two routes are built in:
///
/// - `/delay/<ms>/<path>` serves whatever `/<path>` would serve after an
///   artificial delay of `<ms>` milliseconds — the slow-resource fixture.
/// - `/cookie` serves the cookie fixture page with a
///   `Set-Cookie: sleepy=hollow; Path=/` header.
/// - `POST /submit` answers 200 echoing the received body — the target the
///   form and fetch fixtures post to.
///
/// Responses close their connection (`Connection: close`); bodies are framed
/// by `Content-Length`, which is all the fixtures need.
public actor FixtureServer {
    /// A dynamic route handler: one request in, one response out.
    public typealias Handler = @Sendable (FixtureRequest) async -> FixtureResponse

    /// A lifecycle failure starting or addressing the server.
    public enum ServerError: Error {
        /// The listener reached `ready` without reporting a port.
        case noPort
        /// ``url(for:)`` or ``baseURL`` was used before ``start()``.
        case notRunning
    }

    /// Identifies a registered dynamic route.
    private struct RouteKey: Hashable {
        let method: String
        let path: String
    }

    private let fixturesDirectory: URL
    private var listener: NWListener?
    private var runningBaseURL: URL?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var routes: [RouteKey: Handler] = [:]

    /// Creates a server over a fixtures directory; ``start()`` binds the port.
    public init(fixturesDirectory: URL = TestSupport.fixturesDirectory) {
        self.fixturesDirectory = fixturesDirectory
    }

    /// The base URL of the running server.
    public var baseURL: URL {
        get throws {
            guard let runningBaseURL else { throw ServerError.notRunning }
            return runningBaseURL
        }
    }

    /// Starts listening on an ephemeral localhost port and returns the base URL.
    public func start() async throws -> URL {
        precondition(listener == nil, "FixtureServer is already running")
        let listener = try NWListener(using: NWParameters.tcp)
        listener.newConnectionHandler = { [weak self] connection in
            Task { await self?.adopt(connection) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { [weak listener] state in
                switch state {
                case .ready:
                    listener?.stateUpdateHandler = nil
                    continuation.resume()
                case let .failed(error):
                    listener?.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: DispatchQueue.global())
        }
        guard let port = listener.port, let url = URL(string: "http://127.0.0.1:\(port.rawValue)/") else {
            listener.cancel()
            throw ServerError.noPort
        }
        self.listener = listener
        runningBaseURL = url
        return url
    }

    /// Stops the server: the port is released and open connections cancelled
    /// before this returns. Stopping a stopped server is a no-op.
    public func stop() async {
        guard let listener else { return }
        self.listener = nil
        runningBaseURL = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            listener.stateUpdateHandler = { state in
                if case .cancelled = state {
                    continuation.resume()
                }
            }
            listener.cancel()
        }
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
    }

    /// Registers a dynamic route; it wins over built-in routes and files.
    ///
    /// Registering the same method and path again replaces the handler.
    public func register(method: String = "GET", path: String, handler: @escaping Handler) {
        routes[RouteKey(method: method.uppercased(), path: path)] = handler
    }

    /// The full URL that serves a shared fixture page on this running server.
    public func url(for page: FixturePage) throws -> URL {
        var components = try URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = page.path
        guard let url = components?.url else { throw ServerError.notRunning }
        return url
    }

    /// Runs `body` against a started server, guaranteeing ``stop()`` after —
    /// the leak-proof shape for tests.
    ///
    /// Holds a ``WebKitGate`` slot for the duration, so the number of WebKit
    /// instances the suite keeps live at once stays bounded — the fix for the
    /// contention flakes a fully parallel run otherwise produces.
    public static func withRunning<T: Sendable>(
        fixturesDirectory: URL = TestSupport.fixturesDirectory,
        _ body: @Sendable (FixtureServer, URL) async throws -> T,
    ) async throws -> T {
        await WebKitGate.shared.acquire()
        do {
            let result: T = try await withStartedServer(fixturesDirectory: fixturesDirectory, body)
            await WebKitGate.shared.release()
            return result
        } catch {
            await WebKitGate.shared.release()
            throw error
        }
    }

    private static func withStartedServer<T: Sendable>(
        fixturesDirectory: URL,
        _ body: @Sendable (FixtureServer, URL) async throws -> T,
    ) async throws -> T {
        let server = FixtureServer(fixturesDirectory: fixturesDirectory)
        let baseURL = try await server.start()
        do {
            let result: T = try await body(server, baseURL)
            await server.stop()
            return result
        } catch {
            await server.stop()
            throw error
        }
    }

    // MARK: - Connection handling

    private func adopt(_ connection: NWConnection) {
        guard listener != nil else {
            connection.cancel()
            return
        }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: DispatchQueue.global())
        Task { [weak self] in
            await self?.serve(connection)
            await self?.forget(connection)
        }
    }

    private func forget(_ connection: NWConnection) {
        connections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    private func serve(_ connection: NWConnection) async {
        do {
            guard let request = try await readRequest(from: connection) else { return }
            let response = await response(for: request)
            try await connection.sendAll(response.serialized())
        } catch is FixtureRequest.ParseError {
            try? await connection.sendAll(FixtureResponse.badRequest().serialized())
        } catch {
            // Peer went away mid-exchange; nothing to answer.
        }
    }

    /// Accumulates bytes until one full request (head plus declared body) parses.
    private func readRequest(from connection: NWConnection) async throws -> FixtureRequest? {
        var buffer = Data()
        while true {
            if let request = try FixtureRequest.parse(buffer) { return request }
            guard let chunk = try await connection.receiveChunk() else { return nil }
            buffer.append(chunk)
        }
    }

    // MARK: - Dispatch

    private func response(for request: FixtureRequest) async -> FixtureResponse {
        if let (milliseconds, innerPath) = Self.delayComponents(of: request.path) {
            try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
            var inner = request
            inner.path = innerPath
            return await response(for: inner)
        }
        if let handler = routes[RouteKey(method: request.method, path: request.path)] {
            return await handler(request)
        }
        switch (request.method, request.path) {
        case ("GET", "/cookie"):
            return cookieResponse()
        case ("POST", "/submit"):
            return FixtureResponse(
                status: 200,
                contentType: FixtureContentType.plainText,
                body: Data("received: ".utf8) + request.body,
            )
        case ("GET", _):
            return fileResponse(for: request.path)
        default:
            return FixtureResponse.notFound()
        }
    }

    /// Splits `/delay/<ms>/<rest>` into its delay and inner path, else `nil`.
    private static func delayComponents(of path: String) -> (milliseconds: UInt64, innerPath: String)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "delay", let milliseconds = UInt64(parts[1]) else {
            return nil
        }
        return (milliseconds, "/" + parts.dropFirst(2).joined(separator: "/"))
    }

    /// The cookie fixture page with the fixture cookie attached.
    private func cookieResponse() -> FixtureResponse {
        var response = fileResponse(for: "/" + FixturePage.cookie.fileName)
        response.headers["Set-Cookie"] = "sleepy=hollow; Path=/"
        return response
    }

    /// Serves a file from the fixtures directory, refusing escapes from it.
    private func fileResponse(for path: String) -> FixtureResponse {
        let relative = String(path.drop(while: { $0 == "/" }))
        guard !relative.isEmpty else { return FixtureResponse.notFound() }
        let root = fixturesDirectory.standardizedFileURL
        let file = root.appendingPathComponent(relative).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else { return FixtureResponse.notFound() }
        guard let body = try? Data(contentsOf: file) else { return FixtureResponse.notFound() }
        return FixtureResponse(
            status: 200,
            contentType: FixtureContentType.forFileExtension(file.pathExtension),
            body: body,
        )
    }
}
