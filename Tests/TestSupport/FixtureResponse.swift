import Foundation
import SleepyHollow

/// One HTTP response the fixture server sends back, from a static file or a
/// registered route handler.
public struct FixtureResponse: Friendly {
    /// The HTTP status code.
    public var status: Int
    /// The `Content-Type` the response declares.
    public var contentType: FixtureContentType
    /// Extra headers (`Set-Cookie`, …); `Content-Type`, `Content-Length` and
    /// `Connection` are emitted automatically.
    public var headers: [String: String]
    /// The response body.
    public var body: Data

    /// Creates a response.
    public init(
        status: Int,
        contentType: FixtureContentType,
        headers: [String: String] = [:],
        body: Data,
    ) {
        self.status = status
        self.contentType = contentType
        self.headers = headers
        self.body = body
    }

    /// A `404 Not Found` with a small plain-text body.
    public static func notFound() -> FixtureResponse {
        FixtureResponse(
            status: 404,
            contentType: FixtureContentType.plainText,
            body: Data("not found\n".utf8),
        )
    }

    /// A `400 Bad Request` for unparseable input.
    public static func badRequest() -> FixtureResponse {
        FixtureResponse(
            status: 400,
            contentType: FixtureContentType.plainText,
            body: Data("bad request\n".utf8),
        )
    }

    /// The response serialized as HTTP/1.1 wire bytes, `Connection: close`.
    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(for: status))\r\n"
        head += "Content-Type: \(contentType.rawValue)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        for (name, value) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        head += "\r\n"
        return Data(head.utf8) + body
    }

    /// The reason phrase for the statuses fixtures actually use.
    private static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 204: "No Content"
        case 302: "Found"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        default: "Status"
        }
    }
}
