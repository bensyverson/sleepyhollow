import Foundation

/// The render stage's density: how many device pixels the PNG spends on one
/// CSS px.
///
/// `--scale` is a choice about the *output raster*, never about the page. The
/// viewport stays at ``LoadOptions/size``, so media queries evaluate against
/// the same widths and the layout is the one a reader of that size sees; only
/// the pixels get denser. That is the property the CSS-`zoom` workaround
/// breaks — doubling the viewport renders the wrong breakpoint
/// (`project/2026-08-28-shot-scale-flag.md`).
///
/// The ceiling is deliberate: `WKWebView.takeSnapshot` rasterizes at the
/// *host machine's* screen backing scale, so a density above what the host
/// rendered could only be reached by upscaling a softer image. A capture that
/// silently upsampled would be a plausible wrong answer — a 2×-sized PNG that
/// holds 1× detail — so ``ShotOperation`` refuses instead. That is the
/// intended behaviour for an embedder pinning a scale: a consumer that
/// requires 2× would rather get a loud failure on a non-Retina host than a
/// silent 1× image passed off as Retina-dense.
public struct ShotScale: Friendly {
    /// The densest raster the flag accepts. Beyond 3× a screenshot is a
    /// memory bill, not a legibility gain.
    public static let maximumFactor: Int = 3

    /// Point-for-pixel: the default, and what every capture was before
    /// `--scale` existed.
    public static let one = ShotScale(unchecked: 1)

    /// Device pixels per CSS px, between 1 and ``maximumFactor``.
    public let factor: Int

    /// Creates a density.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` for a
    ///   factor outside 1…``maximumFactor``.
    public init(factor: Int) throws {
        guard factor >= 1, factor <= Self.maximumFactor else {
            throw SleepyError(
                kind: .usage,
                message: "'--scale' wants device pixels per CSS px between 1 and \(Self.maximumFactor); got \(factor).",
                nextMove: "Pass --scale 1 for a point-for-pixel capture, "
                    + "--scale 2 for a Retina-density one, or --scale 3 at most.",
            )
        }
        self.factor = factor
    }

    /// The unchecked form, for the constants this type owns.
    private init(unchecked factor: Int) {
        self.factor = factor
    }

    /// The resolution the encoded PNG declares: 72 dpi per device pixel per
    /// CSS px, so a document viewer places the image at its CSS size rather
    /// than at its pixel size.
    public var dotsPerInch: Int {
        72 * factor
    }
}
