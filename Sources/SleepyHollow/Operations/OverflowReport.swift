/// What ``OverflowOperation`` found: elements whose rendered content reaches
/// past the right edge of the viewport, and — separately — the ancestors that
/// legitimately scroll.
///
/// The split is the whole point. "A wide table inside its own
/// `overflow-x: auto` box" is a design, not a bug, so those containers are
/// *listed* and their descendants are never walked; anything reported under
/// ``violations`` spills the page itself. And because the check works from
/// element geometry rather than `document.scrollWidth`, a page with
/// `body { overflow-x: hidden }` — where ``documentWidth`` equals
/// ``viewportWidth`` by construction — still reports its spill.
public struct OverflowReport: Friendly {
    /// How an element spills: its own box, or the content inside it.
    public enum Cause: String, Friendly {
        /// The element's own border box reaches past the viewport — a wide
        /// image, a fixed-width block.
        case box
        /// The element's box fits but its content does not — an unbreakable
        /// string, a `white-space: nowrap` run.
        case content
    }

    /// One element that spills the viewport.
    public struct Violation: Friendly {
        /// A selector-ish path to the element, e.g. `main > p#token`.
        public var path: String

        /// Whether the box or its content is what reaches too far.
        public var cause: Cause

        /// The document x of the far edge, in CSS pixels.
        public var right: Double

        /// How far past the viewport's right edge that is.
        public var overflowBy: Double

        /// The element's own border box, in document coordinates.
        public var rect: DocumentRect

        /// Creates a violation.
        public init(path: String, cause: Cause, right: Double, overflowBy: Double, rect: DocumentRect) {
            self.path = path
            self.cause = cause
            self.right = right
            self.overflowBy = overflowBy
            self.rect = rect
        }
    }

    /// An ancestor that scrolls horizontally on purpose, and by how much.
    public struct ScrollContainer: Friendly {
        /// A selector-ish path to the container.
        public var path: String

        /// The width of everything inside it, in CSS pixels.
        public var scrollWidth: Double

        /// The width visible at once.
        public var clientWidth: Double

        /// How far a reader can scroll it: ``scrollWidth`` less
        /// ``clientWidth``.
        public var scrollBy: Double

        /// Creates a scroll container entry.
        public init(path: String, scrollWidth: Double, clientWidth: Double, scrollBy: Double) {
            self.path = path
            self.scrollWidth = scrollWidth
            self.clientWidth = clientWidth
            self.scrollBy = scrollBy
        }
    }

    /// The viewport width every measurement is against, in CSS pixels.
    public var viewportWidth: Double

    /// What the document reports as its own scroll width — equal to
    /// ``viewportWidth`` whenever something clips the overflow, which is why
    /// it is reported rather than trusted.
    public var documentWidth: Double

    /// Elements that spill, innermost-first per subtree and in document
    /// order.
    public var violations: [Violation]

    /// Containers whose horizontal scrolling is deliberate.
    public var scrollContainers: [ScrollContainer]

    /// Whether the page holds its width: no violations.
    public var passes: Bool {
        violations.isEmpty
    }

    /// Creates a report.
    public init(
        viewportWidth: Double,
        documentWidth: Double,
        violations: [Violation],
        scrollContainers: [ScrollContainer],
    ) {
        self.viewportWidth = viewportWidth
        self.documentWidth = documentWidth
        self.violations = violations
        self.scrollContainers = scrollContainers
    }
}
