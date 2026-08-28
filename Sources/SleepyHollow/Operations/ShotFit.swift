import CoreGraphics
import Foundation

/// The fit stage: caps the longest side of a capture's *pixels*, leaving the
/// page alone.
///
/// An agent reads an image through a fixed pixel budget — roughly 2,000px on
/// the long side before downsampling makes 16px text illegible — so a
/// full-page shot of a 12,982px document arrives unreadable and gets hand
/// sliced. `--max-size` is the "let me see the whole thing first" answer: the
/// page still renders at its own ``LoadOptions/size``, at its own breakpoint,
/// with its own layout, and only the *output* is thinned afterwards. That
/// ordering is the whole point — a CSS `zoom` or a narrower viewport would
/// render a different page (see `project/2026-08-28-shot-scale-flag.md`).
///
/// Because the pixels thin but ``ShotCapture/rect`` does not, a fitted
/// capture's ``ShotCapture/pixelsPerCSSPixel`` drops below its
/// ``ShotCapture/scale``; that ratio is what a later stage labels a grid
/// with, and what the tile index reports.
public struct ShotFit: Friendly {
    /// The longest side the output image may have, in pixels.
    public let maxSize: Int

    /// Creates a fit stage.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` for a cap
    ///   of zero or less, which names no image.
    public init(maxSize: Int) throws {
        guard maxSize > 0 else {
            throw SleepyError(
                kind: .usage,
                message: "'--max-size' wants a positive number of pixels; got \(maxSize).",
                nextMove: "Pass the longest side you can still read, e.g. --max-size 2000.",
            )
        }
        self.maxSize = maxSize
    }

    /// Downsamples `capture` until its longest side is at most ``maxSize``,
    /// or returns it untouched when it already fits.
    ///
    /// The result keeps the capture's CSS ``ShotCapture/rect`` and its render
    /// ``ShotCapture/scale``: the same region of the same page, drawn with
    /// fewer pixels.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment``
    ///   when Core Graphics can't build the smaller bitmap — a seam bug,
    ///   never a page fact.
    public func applied(to capture: ShotCapture) throws -> ShotCapture {
        let width: Int = capture.image.width
        let height: Int = capture.image.height
        let longest: Int = max(width, height)
        guard longest > maxSize else { return capture }

        let ratio = CGFloat(maxSize) / CGFloat(longest)
        let fittedWidth: Int = width >= height ? maxSize : Self.scaled(width, by: ratio)
        let fittedHeight: Int = height > width ? maxSize : Self.scaled(height, by: ratio)
        guard let smaller = Self.downsample(capture.image, toWidth: fittedWidth, height: fittedHeight) else {
            throw SleepyError(
                kind: .environment,
                message: "Could not downsample the capture to \(fittedWidth)×\(fittedHeight) pixels.",
                nextMove: "Retry; if this persists, it is a seam bug against CoreGraphics.",
            )
        }
        return ShotCapture(image: smaller, rect: capture.rect, scale: capture.scale)
    }

    /// One side, scaled and rounded, never smaller than a single pixel.
    private static func scaled(_ side: Int, by ratio: CGFloat) -> Int {
        max(1, Int((CGFloat(side) * ratio).rounded()))
    }

    /// Redraws `image` at the given pixel size with high-quality
    /// interpolation — the difference between readable 16px text and aliased
    /// mush at a 6:1 reduction.
    private static func downsample(_ image: CGImage, toWidth width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            return nil
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
