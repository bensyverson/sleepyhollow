/// One request in the wire log's **inventory** layer: what the page asked for,
/// as `PerformanceResourceTiming` (plus the main frame's own navigation).
///
/// Every optional field here is a platform truth, not an oversight — the wire
/// spike measured which ones WebKit provides:
///
/// - ``httpStatus`` exists **only for the main frame**. `responseStatus` has
///   never shipped in any Safari, so a subresource's status is unknowable from
///   this layer; the fetch log has it for `fetch` calls.
/// - ``transferSize``, ``encodedBodySize`` and ``decodedBodySize`` need Safari
///   16.4+ **and** a same-origin request. Cross-origin entries report `0` even
///   with `Timing-Allow-Origin`, so they are reported absent rather than as a
///   misleading zero.
/// - ``timing`` detail is `Timing-Allow-Origin`-gated cross-origin; ``startTime``
///   and ``duration`` are always real.
///
/// See `project/2026-08-20-wire-spike.md` for the field-by-field table.
public struct ResourceEntry: Friendly {
    /// The timestamps `PerformanceResourceTiming` exposes, in milliseconds
    /// since the document's time origin.
    ///
    /// Each is absent when WebKit reports it as `0` — which cross-origin
    /// without `Timing-Allow-Origin` means "withheld", and same-origin means
    /// "this phase did not happen" (no redirect, a reused connection, no TLS).
    public struct Timing: Friendly {
        /// When the fetch started.
        public var fetchStart: Double?
        /// When the DNS lookup started.
        public var domainLookupStart: Double?
        /// When the DNS lookup ended.
        public var domainLookupEnd: Double?
        /// When the connection started.
        public var connectStart: Double?
        /// When the connection was established.
        public var connectEnd: Double?
        /// When the TLS handshake started.
        public var secureConnectionStart: Double?
        /// When the request went out.
        public var requestStart: Double?
        /// When the first response byte arrived.
        public var responseStart: Double?
        /// When the last response byte arrived.
        public var responseEnd: Double?

        /// Creates a timing record.
        public init(
            fetchStart: Double? = nil,
            domainLookupStart: Double? = nil,
            domainLookupEnd: Double? = nil,
            connectStart: Double? = nil,
            connectEnd: Double? = nil,
            secureConnectionStart: Double? = nil,
            requestStart: Double? = nil,
            responseStart: Double? = nil,
            responseEnd: Double? = nil,
        ) {
            self.fetchStart = fetchStart
            self.domainLookupStart = domainLookupStart
            self.domainLookupEnd = domainLookupEnd
            self.connectStart = connectStart
            self.connectEnd = connectEnd
            self.secureConnectionStart = secureConnectionStart
            self.requestStart = requestStart
            self.responseStart = responseStart
            self.responseEnd = responseEnd
        }
    }

    /// The requested URL.
    public var url: String

    /// What asked for it: `navigation` for the main frame, else the
    /// `initiatorType` WebKit reports (`script`, `img`, `link`, `css`,
    /// `xmlhttprequest`, `fetch`, …).
    public var initiatorType: String

    /// Milliseconds from the document's time origin to the start of the request.
    public var startTime: Double

    /// How long the request took, in milliseconds.
    public var duration: Double

    /// The negotiated protocol (`http/1.1`, `h2`), when WebKit exposes it —
    /// empty cross-origin without `Timing-Allow-Origin`.
    public var nextHopProtocol: String?

    /// The main frame's HTTP status. Always absent for subresources.
    public var httpStatus: Int?

    /// Bytes on the wire, headers included. Same-origin only.
    public var transferSize: Int?

    /// Body bytes as sent. Same-origin only.
    public var encodedBodySize: Int?

    /// Body bytes after decoding. Same-origin only.
    public var decodedBodySize: Int?

    /// Whether the entry's origin differs from the document's — the reason the
    /// sizes and the timing detail may be absent.
    public var isCrossOrigin: Bool

    /// The phase timestamps, when any of them survived the cross-origin gate.
    public var timing: Timing?

    /// Creates an inventory entry.
    public init(
        url: String,
        initiatorType: String,
        startTime: Double,
        duration: Double,
        nextHopProtocol: String? = nil,
        httpStatus: Int? = nil,
        transferSize: Int? = nil,
        encodedBodySize: Int? = nil,
        decodedBodySize: Int? = nil,
        isCrossOrigin: Bool = false,
        timing: Timing? = nil,
    ) {
        self.url = url
        self.initiatorType = initiatorType
        self.startTime = startTime
        self.duration = duration
        self.nextHopProtocol = nextHopProtocol
        self.httpStatus = httpStatus
        self.transferSize = transferSize
        self.encodedBodySize = encodedBodySize
        self.decodedBodySize = decodedBodySize
        self.isCrossOrigin = isCrossOrigin
        self.timing = timing
    }

    /// One terse line: type, status, URL, duration, and the size when there is
    /// an honest one.
    public var terseLine: String {
        let status: String = httpStatus.map(String.init) ?? "-"
        let size: String = transferSize.map { "  \($0)B" } ?? ""
        return "  " + initiatorType.paddedToColumn(12) + " " + status.paddedToColumn(4) + " "
            + url + "  " + "\(Int(duration.rounded()))ms" + size
    }
}
