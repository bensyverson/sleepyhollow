/// One `window.fetch` call and what came back: the wire log's **fetch** layer,
/// assembled from the recorder's `request`, `response` and `body` messages.
///
/// This is the layer the inventory cannot reach — method, headers, request and
/// response bodies, status. Its honest limits, all measured by the wire spike:
///
/// - It covers `window.fetch` in the **main frame's page world** only. XHR,
///   workers, service workers, beacons, `EventSource`, WebSockets and ordinary
///   subresources appear in the inventory instead; fetches made *inside* a
///   worker appear in neither.
/// - Bodies are read from a clone with a byte cap, and ``truncated`` says so
///   when the cap or the host's budget cut the read short.
/// - An opaque (`no-cors`, cross-origin) response really is `status` 0 with no
///   headers and no body. That is not a failure — ``error`` is what a failure
///   looks like.
public struct FetchExchange: Friendly {
    /// Why a response body is not the whole body.
    public enum Truncation: String, Friendly {
        /// The recorder's byte cap stopped the read.
        case size
        /// The body had not arrived when the host's budget ran out.
        case budget
    }

    /// The recorder's correlation id, which is also the call order.
    public var id: Int

    /// The HTTP method, as `Request` normalized it.
    public var method: String

    /// The resolved request URL.
    public var url: String

    /// The request's `mode` (`cors`, `no-cors`, `same-origin`, `navigate`).
    public var mode: String?

    /// The request headers, names lowercased. Includes what `Request` itself
    /// adds — a string body brings `content-type: text/plain;charset=UTF-8`.
    public var requestHeaders: [String: String]

    /// The request body as text, when there was one.
    public var requestBody: String?

    /// The response status. `0` with ``responseType`` `opaque` is an opaque
    /// response, not a failure.
    public var status: Int?

    /// The response's status text.
    public var statusText: String?

    /// The response type: `basic`, `cors`, `opaque`, `opaqueredirect`, `error`.
    public var responseType: String?

    /// Whether the response followed a redirect.
    public var redirected: Bool?

    /// The response headers, names lowercased. Empty for opaque responses —
    /// the page cannot see them either.
    public var responseHeaders: [String: String]

    /// The response body as text, capped, absent when it was skipped, never
    /// arrived, or was not text.
    public var responseBody: String?

    /// How many body bytes the recorder read before stopping.
    public var responseBodyBytes: Int?

    /// Why the body is short, when it is.
    public var truncated: Truncation?

    /// Milliseconds from the call to the response head.
    public var elapsedMilliseconds: Double?

    /// Milliseconds from the document's time origin to the call — the ordering
    /// key of the log.
    public var startedAtMilliseconds: Double

    /// The failure, when there was one: a network error, a CORS refusal, or an
    /// abort — either of the fetch itself or of the body read that followed it
    /// (an abort mid-stream leaves a real ``status`` and a failed body).
    public var error: String?

    /// Creates a fetch exchange.
    public init(
        id: Int,
        method: String,
        url: String,
        mode: String? = nil,
        requestHeaders: [String: String] = [:],
        requestBody: String? = nil,
        status: Int? = nil,
        statusText: String? = nil,
        responseType: String? = nil,
        redirected: Bool? = nil,
        responseHeaders: [String: String] = [:],
        responseBody: String? = nil,
        responseBodyBytes: Int? = nil,
        truncated: Truncation? = nil,
        elapsedMilliseconds: Double? = nil,
        startedAtMilliseconds: Double,
        error: String? = nil,
    ) {
        self.id = id
        self.method = method
        self.url = url
        self.mode = mode
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.status = status
        self.statusText = statusText
        self.responseType = responseType
        self.redirected = redirected
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.responseBodyBytes = responseBodyBytes
        self.truncated = truncated
        self.elapsedMilliseconds = elapsedMilliseconds
        self.startedAtMilliseconds = startedAtMilliseconds
        self.error = error
    }

    /// One terse line: method, URL, outcome, body size and any truncation.
    public var terseLine: String {
        let outcome: String = error.map { "error: \($0)" } ?? (status.map(String.init) ?? "-")
        let bytes: String = responseBodyBytes.map { "  \($0)B" } ?? ""
        let cut: String = truncated.map { "  truncated:\($0.rawValue)" } ?? ""
        return "  " + method.paddedToColumn(6) + " " + url + "  " + outcome + bytes + cut
    }
}
