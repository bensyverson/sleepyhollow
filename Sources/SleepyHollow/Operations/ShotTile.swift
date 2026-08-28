import CoreGraphics
import Foundation

/// The tile stage: cuts one capture into horizontal strips a reader can take
/// in, each overlapping its neighbour so a line cut at a boundary is still
/// whole somewhere.
///
/// A tall page read at a legible density is many images; slicing it by hand
/// (the field report's PIL loop) loses the one thing that makes a strip
/// actionable — which document rows it shows. Every strip here keeps its own
/// ``ShotCapture/rect`` in CSS document px, so ``ShotIndex`` can hand each
/// one back as a `--rect` for a closer look.
public struct ShotTile: Friendly {
    /// The CSS px adjacent strips share. 40px is about two lines of body
    /// text: enough that a heading or a row cut by one boundary reads whole
    /// in the neighbour.
    public static let defaultOverlap: CGFloat = 40

    /// How tall a strip should be, before the page is known.
    ///
    /// `--tile` is usable bare, so the height can be a promise rather than a
    /// number: ``automatic`` means "as tall as a reader's budget allows",
    /// resolved by ``resolved(maxSize:viewportHeight:)`` once the capture's
    /// context is in hand.
    public enum Height: Friendly {
        /// Derive the height: the `--max-size` cap when one was given, else
        /// the viewport height — a screenful, the unit a page is designed in.
        case automatic
        /// An explicit strip height in CSS px.
        case cssPixels(CGFloat)

        /// Checks a height the caller supplied, before a page is loaded.
        ///
        /// ``automatic`` always passes: what it resolves to isn't known until
        /// the capture is in hand, and ``ShotTile/init(height:overlap:)``
        /// catches an impossible resolution there.
        ///
        /// - Returns: the height, so this reads as a step in the caller's
        ///   pipeline.
        /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` for a
        ///   height the overlap would swallow.
        @discardableResult
        public func validated(overlap: CGFloat = ShotTile.defaultOverlap) throws -> Height {
            if case let .cssPixels(value) = self {
                try ShotTile.validate(height: value, overlap: overlap)
            }
            return self
        }

        /// The concrete strip height, in CSS px.
        ///
        /// - Parameters:
        ///   - maxSize: the `--max-size` cap, when one was given. Strips as
        ///     tall as the cap are 1:1 at a 1,280px viewport — exactly the
        ///     hand-made strips this replaces.
        ///   - viewportHeight: the height the page was rendered at.
        public func resolved(maxSize: Int?, viewportHeight: CGFloat) -> CGFloat {
            switch self {
            case .automatic: maxSize.map { CGFloat($0) } ?? viewportHeight
            case let .cssPixels(value): value
            }
        }
    }

    /// Strip height in CSS px.
    public let height: CGFloat

    /// CSS px shared by adjacent strips.
    public let overlap: CGFloat

    /// Creates a tile stage.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when the
    ///   overlap would consume the whole strip, which would emit strips that
    ///   never reach the bottom of the page.
    public init(height: CGFloat, overlap: CGFloat = ShotTile.defaultOverlap) throws {
        try Self.validate(height: height, overlap: overlap)
        self.height = height
        self.overlap = overlap
    }

    /// Cuts `capture` into strips, top to bottom.
    ///
    /// A capture no taller than one strip comes back as itself, so a caller
    /// never has to special-case the short page. Strips advance by
    /// ``height`` minus ``overlap``, so adjacent rects share exactly the
    /// overlap; the last is clipped to the capture's bottom edge.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment``
    ///   when a strip can't be cut out of the source bitmap.
    public func applied(to capture: ShotCapture) throws -> [ShotCapture] {
        guard capture.rect.height > height else { return [capture] }

        let density: CGFloat = capture.pixelsPerCSSPixel
        let bottom: CGFloat = capture.rect.maxY
        var strips: [ShotCapture] = []
        var top: CGFloat = capture.rect.minY

        while top < bottom {
            let stripHeight: CGFloat = min(height, bottom - top)
            let pixelTop: CGFloat = ((top - capture.rect.minY) * density).rounded()
            let pixelHeight: CGFloat = min((stripHeight * density).rounded(), CGFloat(capture.image.height) - pixelTop)
            let pixels = CGRect(x: 0, y: pixelTop, width: CGFloat(capture.image.width), height: pixelHeight)
            guard pixelHeight >= 1, let cropped = capture.image.cropping(to: pixels) else {
                throw SleepyError(
                    kind: .environment,
                    message: "Could not cut a \(Int(stripHeight))px strip at y \(Int(top)) out of the capture.",
                    nextMove: "Retry; if this persists, it is a seam bug against CGImage.cropping.",
                )
            }
            strips.append(ShotCapture(
                image: cropped,
                rect: CGRect(x: capture.rect.minX, y: top, width: capture.rect.width, height: stripHeight),
                scale: capture.scale,
            ))
            if top + stripHeight >= bottom { break }
            top += height - overlap
        }
        return strips
    }

    /// Refuses a strip the overlap would swallow: at `height <= overlap` the
    /// strips stop advancing and never reach the bottom of the page.
    private static func validate(height: CGFloat, overlap: CGFloat) throws {
        guard height > overlap else {
            throw SleepyError(
                kind: .usage,
                message: "A tile height of \(Int(height)) CSS px is not taller than the \(Int(overlap))px overlap "
                    + "adjacent strips share, so the strips would never reach the bottom of the page.",
                nextMove: "Ask for a taller strip — --tile 800 is a screenful, --tile 2000 an agent's whole budget.",
            )
        }
    }
}
