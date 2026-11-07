import Foundation

/// `sleepy overflow` at several viewports in one call.
///
/// "Does anything spill?" is always asked at every breakpoint, and an agent
/// asking it one size per invocation pays a process, a load and a parse per
/// breakpoint and then has to stitch the answers together. This takes the
/// sizes, gives each its own load — the viewport is a ``LoadOptions`` fact,
/// fixed when the page lays out — runs ``OverflowOperation`` on each, and
/// returns one ``OverflowSweepReport``.
///
/// The loads run as members of one ``HostGroup``, as `shot`'s sweep does, so
/// every size reads and writes one cookie store and one jar: a jar is
/// imported once for the whole sweep, not once per size.
public struct OverflowSweep: Friendly {
    /// The viewports to measure at, in order; empty means the single default.
    public let sizes: [ViewportSize]

    /// Creates a sweep over `sizes`.
    public init(sizes: [ViewportSize]) {
        self.sizes = sizes
    }

    /// Whether this asks at more than one viewport — the point at which the
    /// answer is an ``OverflowSweepReport`` rather than a single
    /// ``OverflowReport``. One size, or none, is the plain single-page check.
    public var isSweep: Bool {
        sizes.count > 1
    }

    /// Loads `url` once per size and measures each.
    ///
    /// - Parameter url: the page to check.
    /// - Parameter options: every load option but the viewport, which each
    ///   load takes from ``sizes``.
    /// - Parameter group: the browser every load shares; its jar must agree
    ///   with `options`' (``PageHost/member(of:options:hosting:)``).
    /// - Returns: one report per size, in order.
    /// - Throws: whatever the first load or measurement that fails throws —
    ///   a sweep with a size missing would read as a page that holds there.
    @MainActor
    public func run(_ url: URL, options: LoadOptions, group: HostGroup) async throws -> OverflowSweepReport {
        var entries: [OverflowSweepReport.Entry] = []
        for size in sizes {
            var sized: LoadOptions = options
            sized.size = size
            let host: PageHost = try PageHost.member(of: group, options: sized)
            _ = try await host.load(url)
            let report: OverflowReport = try await host.execute(OverflowOperation())
            entries.append(OverflowSweepReport.Entry(size: size, report: report))
        }
        return OverflowSweepReport(sizes: entries)
    }
}
