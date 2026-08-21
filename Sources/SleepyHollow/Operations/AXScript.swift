/// The accessibility computation, as JavaScript this library owns.
///
/// The `ax` verb computes roles, names and states *in the page*, because the
/// macOS accessibility tree of a headless `WKWebView` is unreachable to a
/// non-app CLI on public API — the spike settled that
/// (`project/2026-08-20-ax-spike.md`). The script is a Swift constant rather
/// than a bundle resource on purpose: the library stays resource-free, so
/// nothing depends on `Bundle.module` being present wherever it is embedded.
///
/// It is assembled from parts that follow the specs they implement — role
/// mapping (WAI-ARIA 1.2 + HTML-AAM), naming (AccName 1.2), states, and the
/// tree walk — and evaluated as one async function body, so every declaration
/// is function-scoped and the page's own globals are never touched. It runs
/// in the isolated world; the DOM is shared, page JavaScript is not.
///
/// The composed source is a *function body*: it ends in `return axSnapshot();`
/// and is handed straight to ``PageHost/evaluate(_:arguments:in:)``.
enum AXScript {
    /// The whole computation, in the order the parts depend on each other.
    static let source: String = [
        support,
        roles,
        names,
        states,
        tree,
    ].joined(separator: "\n\n")
}
