import Foundation

/// How an act primitive chooses what to act on: a CSS selector, or a point on
/// the page.
///
/// One type rather than two optionals, because the two are exclusive and a
/// pair of optionals can spell states that do not exist — neither given, or
/// both. The addressing decision therefore lives here, in the library, and
/// the CLI only hands over what the agent typed.
///
/// A point is the only way into an open shadow root: CSS selectors cannot
/// cross a shadow boundary and a synthesized click on the host does not
/// propagate down to what the host renders (the 2026-08-24 field report,
/// item 6). ``ClickOperation`` resolves a point by hit test instead.
public enum ActionTarget: Friendly, CustomStringConvertible {
    /// The first element a CSS selector matches, in document order.
    case selector(String)
    /// Whatever is rendered at a point in document CSS px — hit-tested, and
    /// descended through open shadow roots.
    case point(DocumentPoint)

    /// Resolves the `--selector` / `--at` pair a click was invoked with.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when both
    ///   were given (they name different targets) or neither was (there is
    ///   nothing to click), and when `at` is not a point.
    public static func clicking(selector: String?, at: String?) throws -> ActionTarget {
        switch (selector, at) {
        case let (.some(selector), .none):
            return .selector(selector)
        case let (.none, .some(at)):
            return try .point(DocumentPoint(parsing: at))
        case (.some, .some):
            throw SleepyError(
                kind: .usage,
                message: "'--selector' and '--at' name different targets; pick one.",
                nextMove: "Drop one of them: --selector for an element, --at x,y for whatever renders at a point "
                    + "(the way into an open shadow root).",
            )
        case (.none, .none):
            throw SleepyError(
                kind: .usage,
                message: "'click' needs something to click.",
                nextMove: "Pass --selector '<css>' for an element, or --at x,y in document CSS px "
                    + "for whatever renders at a point.",
            )
        }
    }

    /// The target as the failure messages read it: a quoted selector, or the
    /// point named in the `x,y` form the agent typed.
    public var description: String {
        switch self {
        case let .selector(selector): "'\(selector)'"
        case let .point(point): "the point \(point.description)"
        }
    }

    /// The target at the head of a sentence: a quoted selector reads the
    /// same either way, but a point needs its article capitalized rather
    /// than opening a message in lower case.
    public var sentenceDescription: String {
        switch self {
        case .selector: description
        case let .point(point): "The point \(point.description)"
        }
    }

    /// The selector, when this target is one — `nil` for a point, which
    /// names no selector rather than inventing a plausible wrong one.
    public var selector: String? {
        switch self {
        case let .selector(selector): selector
        case .point: nil
        }
    }
}
