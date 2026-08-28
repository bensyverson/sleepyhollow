/// What ``ContrastOperation`` found: every rendered text node's WCAG 2
/// contrast ratio against the background actually behind it, split into the
/// ones that fail and the ones no honest number exists for.
///
/// ``unmeasured`` is the point of the split. Text over a `background-image`
/// or a gradient has no single background colour, so the tool reports the gap
/// instead of inventing a ratio — and, because a gap is not a proven failure,
/// it does not make the verb exit 1. A run with an empty ``failures`` and a
/// non-empty ``unmeasured`` means "nothing measurable is failing, and this
/// much was not measurable"; both halves are printed.
public struct ContrastReport: Friendly {
    /// One text node's verdict.
    public struct Finding: Friendly {
        /// A selector-ish path to the element holding the text, e.g.
        /// `main > p.lede` or `text#sub-label`.
        public var path: String

        /// The text itself, whitespace collapsed and cut to a readable
        /// excerpt.
        public var text: String

        /// The composited text colour, as `#rrggbb`.
        public var foreground: String

        /// The composited background colour, as `#rrggbb`; `nil` when it
        /// could not be determined — see ``reason``.
        public var background: String?

        /// The WCAG 2 contrast ratio, rounded to two places; `nil` when
        /// ``background`` is.
        public var ratio: Double?

        /// The ratio this text had to meet, given its size and the run's
        /// ``ContrastMinimum``.
        public var required: Double

        /// Whether WCAG counts this as large text (≥24px, or ≥18.66px bold),
        /// which is what lowers ``required``.
        public var isLargeText: Bool

        /// The computed font size in CSS pixels — the number behind
        /// ``isLargeText``.
        public var fontSize: Double

        /// Why the background could not be measured: `"image"` at a
        /// background-image or gradient. `nil` on a measured finding.
        public var reason: String?

        /// Creates a finding.
        public init(
            path: String,
            text: String,
            foreground: String,
            background: String?,
            ratio: Double?,
            required: Double,
            isLargeText: Bool,
            fontSize: Double,
            reason: String?,
        ) {
            self.path = path
            self.text = text
            self.foreground = foreground
            self.background = background
            self.ratio = ratio
            self.required = required
            self.isLargeText = isLargeText
            self.fontSize = fontSize
            self.reason = reason
        }
    }

    /// The bar this run held text to.
    public var minimum: ContrastMinimum

    /// How many text nodes got a ratio.
    public var checked: Int

    /// How many rendered-text nodes were passed over: hidden by `display`,
    /// `visibility` or `opacity`, or with no rendered area.
    public var skipped: Int

    /// How many elements `--selector` matched; `1` for the default whole-body
    /// scope.
    public var scopeMatches: Int

    /// Text below its required ratio, in document order.
    public var failures: [Finding]

    /// Text whose background has no single colour, in document order.
    public var unmeasured: [Finding]

    /// Whether the page passes: no measured failure. An empty
    /// ``unmeasured`` is not required — an honest gap is not a proven fault.
    public var passes: Bool {
        failures.isEmpty
    }

    /// Creates a report.
    public init(
        minimum: ContrastMinimum,
        checked: Int,
        skipped: Int,
        scopeMatches: Int,
        failures: [Finding],
        unmeasured: [Finding],
    ) {
        self.minimum = minimum
        self.checked = checked
        self.skipped = skipped
        self.scopeMatches = scopeMatches
        self.failures = failures
        self.unmeasured = unmeasured
    }
}
