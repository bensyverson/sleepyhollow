import AppKit
import CoreGraphics
import Foundation

/// A decoded capture in flight through the shot pipeline: pixels plus the
/// CSS-px rect and density that make them addressable.
///
/// This is the in-process currency the readout stages operate on — crop,
/// tile, fit-to-size, grid, sheet — each a function from captures to
/// captures. It deliberately holds a `CGImage` rather than PNG bytes so a
/// chain of stages never re-encodes between steps; ``encoded()`` turns the
/// final result into the ``ShotImage`` that crosses the wire. Not
/// `Friendly`, on purpose: a `CGImage` is not `Codable`, and this type never
/// leaves the process — ``ShotImage`` is its serializable twin.
public struct ShotCapture: Sendable {
    /// The pixels.
    public let image: CGImage

    /// The document rect these pixels show, in CSS px (full-page space).
    public let rect: CGRect

    /// Device pixels per CSS px.
    public let scale: Int

    /// Creates a capture.
    public init(image: CGImage, rect: CGRect, scale: Int = 1) {
        self.image = image
        self.rect = rect
        self.scale = scale
    }

    /// The image's own pixel size.
    public var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    /// Encodes the capture as a ``ShotImage``.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment``
    ///   when PNG encoding fails — a seam bug, never a page fact.
    public func encoded() throws -> ShotImage {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SleepyError(
                kind: .environment,
                message: "Could not encode the snapshot as PNG.",
                nextMove: "Retry; if this persists, it is a seam bug against NSBitmapImageRep.",
            )
        }
        return ShotImage(png: png, rect: rect, scale: scale)
    }

    /// Renders `image` into a fresh bitmap exactly `pixelSize` pixels wide
    /// and tall, independent of the source image's own backing resolution.
    ///
    /// Measured, not documented: `WKWebView.takeSnapshot` hands back an
    /// `NSImage` rasterized at the *host machine's* screen backing scale
    /// factor (2x on a Retina Mac, 1x elsewhere) even though the web view is
    /// never attached to a screen, and `snapshotWidth` only relabels the
    /// `NSImage`'s logical size. Re-rendering at the exact pixel size is what
    /// makes the output depend only on the requested rect and scale, never on
    /// which Mac ran the command — determinism by construction (vision doc
    /// §5).
    static func rasterize(_ image: NSImage, atPixelSize pixelSize: CGSize) -> CGImage? {
        let width = max(1, Int(pixelSize.width.rounded()))
        let height = max(1, Int(pixelSize.height.rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0,
        ) else {
            return nil
        }
        bitmap.size = CGSize(width: width, height: height)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(
            in: CGRect(x: 0, y: 0, width: width, height: height),
            from: .zero,
            operation: .copy,
            fraction: 1,
        )
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.cgImage
    }
}
