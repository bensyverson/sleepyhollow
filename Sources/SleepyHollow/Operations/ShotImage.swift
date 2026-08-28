import CoreGraphics
import Foundation

/// One encoded capture and where it came from: the wire shape of a
/// ``ShotOperation`` result.
///
/// A capture is never just pixels. An agent reading a PNG needs to know
/// which CSS-px rect of the document it shows and how many device pixels
/// stand for one CSS px, or it cannot turn a thing it sees back into a
/// selector, a `--rect`, or a click. Carrying ``rect`` and ``scale`` beside
/// the bytes is what lets a tile index, a contact sheet, or a `--scale 2`
/// capture stay addressable.
public struct ShotImage: Friendly {
    /// The encoded PNG.
    public let png: Data

    /// The document rect this image shows, in CSS px (full-page space).
    public let rect: CGRect

    /// Device pixels per CSS px: 1 for a point-for-pixel capture, 2 for a
    /// Retina-density one.
    public let scale: Int

    /// Creates an image record.
    public init(png: Data, rect: CGRect, scale: Int = 1) {
        self.png = png
        self.rect = rect
        self.scale = scale
    }

    /// The PNG's pixel size implied by ``rect`` and ``scale``.
    public var pixelSize: CGSize {
        CGSize(width: rect.width * CGFloat(scale), height: rect.height * CGFloat(scale))
    }
}
