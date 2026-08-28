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
    ///
    /// This is a fact about the *page*, so no readout stage changes it: a
    /// fitted capture shows the same rect with fewer pixels, and a tile shows
    /// a shorter rect. It is what makes a capture addressable — the number an
    /// agent pastes back into `--rect`.
    public let rect: CGRect

    /// Device pixels per CSS px **as rendered** — 1 for a point-for-pixel
    /// capture, 2 for a Retina-density one.
    ///
    /// This is the density WebKit rasterized at, not the density the image
    /// ended up with: ``ShotFit`` thins the pixels afterwards and deliberately
    /// leaves this alone, because it says which page was drawn and at which
    /// device pixel ratio (``ShotScale``) rather than how many pixels
    /// survived. For "how much detail does this image actually hold", read
    /// ``pixelsPerCSSPixel``.
    public let scale: Int

    /// Creates a capture.
    public init(image: CGImage, rect: CGRect, scale: Int = 1) {
        self.image = image
        self.rect = rect
        self.scale = scale
    }

    /// Decodes an encoded capture back into the pipeline's currency.
    ///
    /// The inverse of ``encoded()``, for a stage that runs *after* the wire
    /// shape exists — a contact sheet composes captures a page host already
    /// handed back as PNGs, and re-decoding costs one lossless pass rather
    /// than a second render.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment``
    ///   when the bytes are not a readable image.
    public init(decoding image: ShotImage) throws {
        guard let bitmap = NSBitmapImageRep(data: image.png), let pixels = bitmap.cgImage else {
            throw SleepyError(
                kind: .environment,
                message: "Could not read a capture back from its PNG.",
                nextMove: "Retry; if this persists, it is a seam bug against NSBitmapImageRep.",
            )
        }
        self.init(image: pixels, rect: image.rect, scale: image.scale)
    }

    /// The image's own pixel size.
    public var pixelSize: CGSize {
        CGSize(width: image.width, height: image.height)
    }

    /// Pixels this image actually holds per CSS px of ``rect``.
    ///
    /// Equal to ``scale`` until ``ShotFit`` downsamples, then a fraction of
    /// it — 0.154 for a 12,982px page fitted to 2,000. Derived from the
    /// pixels rather than stored, so it cannot drift from the image it
    /// describes, and it is the number every later reader wants: what a grid
    /// labels its rulers with, what ``ShotIndex`` reports, and what turns a
    /// pixel an agent noticed back into a CSS coordinate.
    public var pixelsPerCSSPixel: CGFloat {
        rect.width > 0 ? CGFloat(image.width) / rect.width : CGFloat(scale)
    }

    /// Encodes the capture as a ``ShotImage``.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment``
    ///   when PNG encoding fails — a seam bug, never a page fact.
    public func encoded() throws -> ShotImage {
        let bitmap = NSBitmapImageRep(cgImage: image)
        // `size` is the rep's *logical* size, and the PNG writer turns the
        // ratio between it and the pixel count into the file's pHYs
        // resolution: 72 dpi at scale 1, 144 at scale 2. Without it a
        // `--scale 2` capture opens at twice its CSS size everywhere.
        bitmap.size = CGSize(
            width: CGFloat(image.width) / CGFloat(scale),
            height: CGFloat(image.height) / CGFloat(scale),
        )
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw SleepyError(
                kind: .environment,
                message: "Could not encode the snapshot as PNG.",
                nextMove: "Retry; if this persists, it is a seam bug against NSBitmapImageRep.",
            )
        }
        return ShotImage(png: png, rect: rect, scale: scale, pixelSize: pixelSize)
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
    /// How many device pixels `image` actually holds per point — the *host's*
    /// density, since that is what `WKWebView.takeSnapshot` rasterizes at.
    ///
    /// This is the ceiling `--scale` is checked against: a requested density
    /// above it could only be reached by upscaling, which would hand back a
    /// soft image with a convincing pixel count. Read from the backing
    /// representation rather than from `NSScreen`, because it is the raster in
    /// hand that decides, not the machine's headline configuration.
    static func density(of image: NSImage) -> CGFloat {
        guard let representation = image.representations.first, image.size.width > 0 else { return 1 }
        return CGFloat(representation.pixelsWide) / image.size.width
    }

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
