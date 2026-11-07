import Foundation

/// What ``OverflowSweep`` found: one ``OverflowReport`` per viewport, in the
/// order the sizes were given.
///
/// Each entry is the single-size report unchanged, under the viewport it was
/// measured at — so a reader that knows `overflow`'s one-size output reads
/// every entry the same way, and nothing is re-shaped for the sweep. The
/// sibling of ``ShotVariantIndex``: it, too, names each render by its axes
/// outright rather than leaving them to be inferred.
public struct OverflowSweepReport: Friendly {
    /// One viewport's answer.
    public struct Entry: Friendly {
        /// Viewport width in CSS px.
        public let width: Int
        /// Viewport height in CSS px.
        public let height: Int
        /// What spills, and what scrolls on purpose, at this viewport.
        public let report: OverflowReport

        /// Creates an entry for the report measured at `size`.
        public init(size: ViewportSize, report: OverflowReport) {
            width = size.width
            height = size.height
            self.report = report
        }
    }

    /// The viewports, in the order they were given.
    public let sizes: [Entry]

    /// Whether the page holds its width at every viewport: one spill anywhere
    /// fails the sweep, since the question is always "at every breakpoint".
    public var passes: Bool {
        sizes.allSatisfy(\.report.passes)
    }

    /// Creates a report.
    public init(sizes: [Entry]) {
        self.sizes = sizes
    }
}
