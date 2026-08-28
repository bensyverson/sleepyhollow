import Foundation

/// `sleepy contrast`: every rendered text node's WCAG 2 contrast ratio against
/// the background actually behind it.
///
/// The computation is `window.sleepy.contrast()` from ``SleepyHelpers`` —
/// installed on every ``PageHost``, so the verb is a thin caller and an agent
/// composing its own check through `sleepy eval` runs the identical code. What
/// makes it worth a verb rather than a hand-rolled loop is the background:
/// `getComputedStyle(el).backgroundColor` on the element holding the text is
/// almost always `rgba(0, 0, 0, 0)`, so the walk has to climb ancestors
/// compositing alpha, stop honestly at the first `background-image`, and — for
/// SVG `<text>`, which has no computed background at all — find the shape
/// whose fill is underneath.
public struct ContrastOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = ContrastReport

    /// The wire identifier.
    public static let kind: String = "contrast"

    /// The bar text must meet. Default ``ContrastMinimum/wcagAA``.
    public var minimum: ContrastMinimum

    /// A CSS selector scoping the walk to the matched elements' subtrees;
    /// `nil` walks the whole body.
    public var selector: String?

    /// Creates the operation.
    public init(minimum: ContrastMinimum = .wcagAA, selector: String? = nil) {
        self.minimum = minimum
        self.selector = selector
    }

    /// Measures the page's text.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when
    ///   ``selector`` matches nothing — an empty scope would otherwise pass
    ///   with `checked: 0`, which is the plausible wrong answer this tool
    ///   refuses to give — and ``SleepyError/Kind/environment`` when the page
    ///   cannot run the computation.
    @MainActor
    public func execute(on host: PageHost) async throws -> ContrastReport {
        var options: [String: Any] = [
            "minimum": minimum.description,
            "min": minimum.normalThreshold,
            "largeMin": minimum.largeThreshold,
        ]
        if let selector {
            options["selector"] = selector
        }
        let report: ContrastReport = try await SleepyHelpers.call(
            "contrast",
            options: options,
            as: ContrastReport.self,
            on: host,
        )
        if let selector, report.scopeMatches == 0 {
            throw SleepyError(
                kind: .usage,
                message: "'\(selector)' matched no element, so there was no text to measure.",
                nextMove: "Check the selector, or drop --selector to measure the whole page.",
            )
        }
        return report
    }
}
