import CoreGraphics
import Foundation

/// What `shot --tile` prints on stdout: which file holds which rows of the
/// document.
///
/// A set of numbered PNGs is only useful if an agent can say *where* it saw
/// something. Each entry carries the strip's rect in CSS document px — the
/// coordinate system `query`, `--rect` and `click --at` all speak — so
/// picking a strip and looking closer is `--rect x,y,width,height` with the
/// numbers already in hand, no arithmetic and no filename parsing.
public struct ShotIndex: Friendly {
    /// One strip: the file it was written to, the document rect it shows,
    /// and how densely it shows it.
    public struct Tile: Friendly {
        /// The path the strip was written to, as `--out` named it.
        public let file: String

        /// Left edge in CSS document px.
        public let x: Double

        /// Top edge in CSS document px.
        public let y: Double

        /// Width in CSS document px.
        public let width: Double

        /// Height in CSS document px.
        public let height: Double

        /// Pixels in this file per CSS px — 1 for a plain capture, 2 for a
        /// Retina-density one, a fraction once `--max-size` has thinned it.
        public let scale: Double

        /// Creates an entry.
        public init(file: String, x: Double, y: Double, width: Double, height: Double, scale: Double) {
            self.file = file
            self.x = x
            self.y = y
            self.width = width
            self.height = height
            self.scale = scale
        }

        /// Describes `image` as the file it was written to.
        public init(file: String, image: ShotImage) {
            self.init(
                file: file,
                x: Double(image.rect.minX),
                y: Double(image.rect.minY),
                width: Double(image.rect.width),
                height: Double(image.rect.height),
                scale: Double(image.pixelsPerCSSPixel),
            )
        }
    }

    /// The strips, top to bottom.
    public let tiles: [Tile]

    /// Creates an index.
    public init(tiles: [Tile]) {
        self.tiles = tiles
    }
}
