import Foundation
import SleepyHollow

/// One parsed HTTP request as the fixture server hands it to route handlers.
public struct FixtureRequest: Friendly {
    /// The HTTP method, uppercased (`GET`, `POST`, …).
    public var method: String
    /// The percent-decoded request path, query stripped (`/form.html`).
    public var path: String
    /// The decoded query items; later duplicates of a name win.
    public var queryItems: [String: String]
    /// The request headers, names lowercased.
    public var headers: [String: String]
    /// The request body, empty when the request carried none.
    public var body: Data

    /// Creates a request; primarily useful for tests that call handlers directly.
    public init(
        method: String,
        path: String,
        queryItems: [String: String] = [:],
        headers: [String: String] = [:],
        body: Data = Data(),
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
    }

    /// The value of a header, looked up case-insensitively.
    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

extension FixtureRequest {
    /// A wire-parsing failure the server answers with `400 Bad Request`.
    enum ParseError: Error {
        /// The request line or a header line was not valid HTTP/1.1.
        case malformed
    }

    /// Parses one HTTP/1.1 request from accumulated bytes.
    ///
    /// Returns `nil` while the buffer is incomplete (head or declared body
    /// still arriving); throws ``ParseError`` on malformed input. Bodies are
    /// framed by `Content-Length` only — the fixtures never need chunked
    /// transfer encoding.
    static func parse(_ buffer: Data) throws -> FixtureRequest? {
        let headTerminator = Data("\r\n\r\n".utf8)
        guard let terminatorRange = buffer.range(of: headTerminator) else { return nil }

        let head = String(decoding: buffer[buffer.startIndex ..< terminatorRange.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw ParseError.malformed }

        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else { throw ParseError.malformed }
        let method = String(requestLine[0]).uppercased()
        let target = String(requestLine[1])

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.malformed }
            let name = String(line[line.startIndex ..< colon]).lowercased()
            let value = String(line[line.index(after: colon)...])
                .trimmingCharacters(in: CharacterSet.whitespaces)
            headers[name] = value
        }

        let contentLength = headers["content-length"].flatMap { Int($0) } ?? 0
        let bodyStart = terminatorRange.upperBound
        guard buffer.endIndex - bodyStart >= contentLength else { return nil }
        let body = Data(buffer[bodyStart ..< bodyStart + contentLength])

        guard let components = URLComponents(string: target) else { throw ParseError.malformed }
        var queryItems: [String: String] = [:]
        for item in components.queryItems ?? [] {
            queryItems[item.name] = item.value ?? ""
        }

        return FixtureRequest(
            method: method,
            path: components.path,
            queryItems: queryItems,
            headers: headers,
            body: body,
        )
    }
}
