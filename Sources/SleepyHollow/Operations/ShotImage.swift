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

    /// Device pixels per CSS px **as rendered**: 1 for a point-for-pixel
    /// capture, 2 for a Retina-density one. A readout stage that thins the
    /// pixels (`--max-size`) leaves this alone — see
    /// ``ShotCapture/scale`` — so read ``pixelsPerCSSPixel`` for the density
    /// the bytes actually carry.
    public let scale: Int

    /// The PNG's pixel size.
    ///
    /// Stored rather than derived from ``rect`` and ``scale``, because those
    /// two stop implying it the moment a readout stage runs: `--max-size`
    /// fits the pixels without moving the page, and a grid gutter will add
    /// pixels that show no page at all.
    public let pixelSize: CGSize

    /// Creates an image record.
    ///
    /// - Parameter pixelSize: the PNG's real dimensions; defaults to the
    ///   point-for-pixel size ``rect`` and `scale` imply.
    public init(png: Data, rect: CGRect, scale: Int = 1, pixelSize: CGSize? = nil) {
        self.png = png
        self.rect = rect
        self.scale = scale
        self.pixelSize = pixelSize
            ?? CGSize(width: rect.width * CGFloat(scale), height: rect.height * CGFloat(scale))
    }

    /// Pixels this PNG holds per CSS px of ``rect`` — ``scale`` until
    /// `--max-size` thins it, a fraction of it afterwards.
    public var pixelsPerCSSPixel: CGFloat {
        rect.width > 0 ? pixelSize.width / rect.width : CGFloat(scale)
    }
}
