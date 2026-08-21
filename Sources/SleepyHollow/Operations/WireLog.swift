/// The wire log's two layers, in one result: the output of `sleepy wire`.
///
/// The layers answer different halves of "what did the page ask for, and what
/// came back?", and neither subsumes the other:
///
/// - ``inventory`` — *everything* the page requested (subresources, XHR,
///   images, the document itself), with the timing and sizes WebKit exposes,
///   but no methods, no headers, no bodies, and no status except the main
///   frame's. That is a platform limit, not a design choice.
/// - ``fetches`` — the full exchange for every `window.fetch` call in the main
///   frame: method, headers, both bodies, status.
public struct WireLog: Friendly {
    /// Every request the page made, main frame first.
    public var inventory: [ResourceEntry]

    /// Every `window.fetch` exchange, ordered by when the call was made.
    public var fetches: [FetchExchange]

    /// Creates a wire log.
    public init(inventory: [ResourceEntry] = [], fetches: [FetchExchange] = []) {
        self.inventory = inventory
        self.fetches = fetches
    }

    /// The terse form: both layers, each headed by its count, one line per
    /// entry. Both headings always print — an empty layer is information.
    public var terseText: String {
        var lines = ["inventory (\(inventory.count))"]
        lines.append(contentsOf: inventory.map(\.terseLine))
        lines.append("fetches (\(fetches.count))")
        lines.append(contentsOf: fetches.map(\.terseLine))
        return lines.joined(separator: "\n")
    }
}
