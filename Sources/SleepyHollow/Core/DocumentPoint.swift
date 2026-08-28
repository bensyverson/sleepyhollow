import Foundation

/// A point on the page in CSS pixels of the *document* — origin at the
/// top-left of the unscrolled page, the same space ``ShotRegion/rect(_:)``
/// crops in and a tile index reports in.
///
/// Document space, not viewport space, is the choice that makes coordinates
/// pasteable: a rect measured from one capture stays valid after the page
/// scrolls, so an agent can read a number out of one command and hand it to
/// the next. The verbs that consume a point are responsible for scrolling it
/// into view before they use it.
public struct DocumentPoint: Friendly, CustomStringConvertible {
    /// Distance from the document's left edge, in CSS px.
    public var x: Double

    /// Distance from the document's top edge, in CSS px.
    public var y: Double

    /// Creates a point.
    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Parses the CLI's `x,y` form.
    ///
    /// - Parameter text: two decimal numbers separated by a comma; spaces
    ///   around them are ignored.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` for
    ///   anything else, naming the expected shape.
    public init(parsing text: String) throws {
        let fields: [Substring] = text.split(separator: ",", omittingEmptySubsequences: false)
        let numbers: [Double] = fields.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard fields.count == 2, numbers.count == 2 else {
            throw SleepyError(
                kind: .usage,
                message: "A point wants x,y in CSS px; got '\(text)'.",
                nextMove: "Pass two numbers, e.g. --at 620,180 — document CSS px, "
                    + "the coordinates `sleepy shot --rect` crops in.",
            )
        }
        guard numbers[0] >= 0, numbers[1] >= 0 else {
            throw SleepyError(
                kind: .usage,
                message: "A point wants x,y at or past the document's origin; got '\(text)'.",
                nextMove: "Document coordinates start at 0,0 in the page's top-left corner: "
                    + "there is nothing above or left of it to click.",
            )
        }
        self.init(x: numbers[0], y: numbers[1])
    }

    /// The point as the agent typed it: `620,180`, with whole numbers written
    /// whole so a message never reads `620.0,180.0`.
    public var description: String {
        "\(Self.terse(x)),\(Self.terse(y))"
    }

    private static func terse(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value))
            : String(value)
    }
}
