import CoreGraphics
import Foundation

/// What part of the page a ``ShotOperation`` captures.
///
/// One type for the four addressing modes, because they are exclusive: a
/// shot is of the viewport, or of the whole scroll height, or of one
/// element's box, or of a rect the caller already measured — never two at
/// once. Every rect here is in CSS px of the *document* (full-page space,
/// origin at the top-left of the page, unscrolled), the coordinate system
/// every other verb reports in, so a rect read from `query`, from a tile
/// index, or from a gridded capture pastes straight back.
public enum ShotRegion: Friendly {
    /// The viewport the host was built with (``LoadOptions/size``).
    case viewport
    /// The whole scrollable page: viewport width, document scroll height.
    case fullPage
    /// The bounding box of the first element matching a CSS selector.
    /// A selector that matches nothing, or matches a box with no rendered
    /// area, is the clean negative (exit 1).
    case element(String)
    /// An explicit `x, y, width, height` in CSS document px.
    case rect(CGRect)

    /// Parses the CLI's `--rect x,y,w,h` form.
    ///
    /// - Parameter text: four decimal numbers separated by commas; spaces
    ///   around them are ignored.
    /// - Returns: ``rect(_:)`` for a well-formed, positive-area rect.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` for
    ///   anything else, naming the expected shape.
    public static func rect(parsing text: String) throws -> ShotRegion {
        let parts: [Double] = text.split(separator: ",", omittingEmptySubsequences: false)
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 4, text.split(separator: ",").count == 4 else {
            throw SleepyError(
                kind: .usage,
                message: "'--rect' wants x,y,width,height in CSS px; got '\(text)'.",
                nextMove: "Pass four numbers, e.g. --rect 0,850,1280,1285 — the values a tile index or `query` reports.",
            )
        }
        // `CGRect.width` reports a magnitude, so the sign is checked on the raw parts.
        guard parts[2] > 0, parts[3] > 0 else {
            throw SleepyError(
                kind: .usage,
                message: "'--rect' needs a positive width and height; got \(parts[2])×\(parts[3]).",
                nextMove: "Give the rect a real area: --rect x,y,width,height with width and height above 0.",
            )
        }
        return .rect(CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]))
    }
}
