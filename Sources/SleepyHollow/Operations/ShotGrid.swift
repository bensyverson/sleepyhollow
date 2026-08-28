import AppKit
import CoreGraphics
import CoreText
import Foundation

/// The grid stage of the shot pipeline: rulers in a padded gutter, and
/// optionally faint lines across the image, both labeled in **CSS document
/// px**.
///
/// A vision model reads landmarks; it does not count pixels. Without labels
/// on the image an agent has to estimate "about a third of the way down" and
/// turn that into a `--rect`, and an off-by-one at 100 px is a wrong rect.
/// So the coordinates are burned in: a 24 px gutter along the top and left
/// edges carrying tick marks and numbers, plus (in
/// ``Mode/rulersAndLines``) a faint line across the page at every step so a
/// mid-image element can be triangulated between two rulers.
///
/// **Document coordinates, not image coordinates.** Every label is the
/// capture's ``ShotCapture/rect`` origin plus the pixel offset divided by
/// the density, so a `--rect 0,850,…` crop's first horizontal ruler reads
/// `900`, not `50`. That number pastes straight back into `--rect`,
/// `--element`'s neighbours, or a click.
///
/// **Density is an argument, not a field.** The stage takes
/// `pixelsPerCSSPixel` explicitly rather than reading ``ShotCapture/scale``,
/// because the two diverge: `--scale 2` renders at 2 device px per CSS px,
/// and a later `--max-size` fit may shrink that to 0.37 without the capture
/// being any less addressable. Callers pass whatever the pipeline's fit
/// stage arrived at (`scale` when nothing was fitted), and the labels stay
/// correct either way.
///
/// **Order.** The grid is drawn *after* the `--max-size` fit, so the gutter
/// is legible rather than fitted down to unreadable numbers; the cost is
/// that a gridded capture exceeds the size cap by its own gutter width,
/// which the help text says out loud.
public enum ShotGrid {
    /// How much of the grid to draw.
    public enum Mode: String, Friendly, CaseIterable {
        /// Rulers in the gutter plus a faint line across the page at every
        /// step: the default, and what makes a mid-image element locatable.
        case rulersAndLines = "lines"
        /// The gutter only. The page pixels come through untouched, which is
        /// what a capture being judged for contrast, alignment or a visual
        /// diff needs.
        case rulers

        /// Parses the CLI's `--grid lines|rulers` value.
        ///
        /// - Parameter text: `lines` or `rulers`; surrounding spaces and
        ///   letter case are ignored.
        /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage``
        ///   naming both spellings, for anything else.
        public init(parsing text: String) throws {
            let cleaned = text.trimmingCharacters(in: .whitespaces).lowercased()
            guard let mode = Mode(rawValue: cleaned) else {
                throw SleepyError(
                    kind: .usage,
                    message: "'--grid' wants 'lines' or 'rulers'; got '\(text)'.",
                    nextMove: "Use --grid lines for rulers plus faint lines across the page, "
                        + "or --grid rulers for the gutter alone, leaving the page pixels untouched.",
                )
            }
            self = mode
        }
    }

    /// The grid a caller asked for.
    public struct Options: Friendly {
        /// How much to draw.
        public let mode: Mode
        /// The spacing between ruler ticks and lines, in CSS px.
        public let step: Int

        /// Creates grid options.
        public init(mode: Mode = .rulersAndLines, step: Int = 100) {
            self.mode = mode
            self.step = step
        }
    }

    /// One ruler mark: where it lands in the image, and what it reads.
    public struct Tick: Friendly {
        /// The document coordinate, in CSS px — what the label says.
        public let cssPosition: Int
        /// How far into the page area the mark sits, in image pixels,
        /// measured from the left edge (columns) or the top edge (rows).
        public let pixelOffset: CGFloat

        /// Creates a tick.
        public init(cssPosition: Int, pixelOffset: CGFloat) {
            self.cssPosition = cssPosition
            self.pixelOffset = pixelOffset
        }

        /// The number as the ruler prints it.
        public var label: String {
            String(cssPosition)
        }
    }

    /// Where everything goes for one capture: gutter widths and the two
    /// rulers' ticks. Separated from the drawing so the geometry can be
    /// asserted without rasterizing anything.
    public struct Layout: Friendly {
        /// The left gutter's width in pixels — ``minimumGutter``, widened
        /// when the tallest page's labels would not otherwise fit.
        public let leftGutter: Int
        /// The top gutter's height in pixels.
        public let topGutter: Int
        /// The top ruler's ticks, offsets measured from the page's left edge.
        public let columns: [Tick]
        /// The left ruler's ticks, offsets measured from the page's top edge.
        public let rows: [Tick]
        /// The un-gridded capture's pixel width.
        public let pageWidth: Int
        /// The un-gridded capture's pixel height.
        public let pageHeight: Int

        /// Lays out the grid for a capture at a given density.
        ///
        /// - Parameters:
        ///   - capture: the capture the grid will be drawn around; its
        ///     ``ShotCapture/rect`` origin is what the labels count from.
        ///   - options: the mode and step.
        ///   - pixelsPerCSSPixel: image pixels per CSS px *after* any
        ///     `--max-size` fit — see the type's discussion.
        public init(for capture: ShotCapture, options: Options, pixelsPerCSSPixel: CGFloat) {
            pageWidth = capture.image.width
            pageHeight = capture.image.height
            topGutter = ShotGrid.minimumGutter
            columns = ShotGrid.ticks(
                fromCSSOrigin: capture.rect.origin.x,
                acrossPixels: pageWidth,
                pixelsPerCSSPixel: pixelsPerCSSPixel,
                step: options.step,
            )
            rows = ShotGrid.ticks(
                fromCSSOrigin: capture.rect.origin.y,
                acrossPixels: pageHeight,
                pixelsPerCSSPixel: pixelsPerCSSPixel,
                step: options.step,
            )
            let widest: CGFloat = rows.map { ShotGrid.labelWidth($0.label) }.max() ?? 0
            leftGutter = max(
                ShotGrid.minimumGutter,
                Int((widest + CGFloat(ShotGrid.labelInset * 2)).rounded(.up)),
            )
        }
    }

    /// The gutter's thickness in pixels, and the floor for the left gutter.
    public static let minimumGutter: Int = 24

    /// The ticks a ruler shows for one axis.
    ///
    /// - Parameters:
    ///   - origin: the axis's document coordinate at pixel 0 — the capture
    ///     rect's `origin.x` for the top ruler, `origin.y` for the left one.
    ///   - pixels: the page area's extent along the axis, in image pixels.
    ///   - pixelsPerCSSPixel: image pixels per CSS px after any fit.
    ///   - step: the spacing in CSS px.
    /// - Returns: every multiple of `step` that falls inside the crop, in
    ///   ascending order, each with its pixel offset. Empty for a
    ///   non-positive step, density or extent.
    public static func ticks(
        fromCSSOrigin origin: CGFloat,
        acrossPixels pixels: Int,
        pixelsPerCSSPixel: CGFloat,
        step: Int,
    ) -> [Tick] {
        guard step > 0, pixelsPerCSSPixel > 0, pixels > 0 else { return [] }
        let stride = Double(step)
        var position = Int((Double(origin) / stride).rounded(.up)) * step
        var ticks: [Tick] = []
        while true {
            let offset = (Double(position) - Double(origin)) * Double(pixelsPerCSSPixel)
            guard offset < Double(pixels) else { return ticks }
            ticks.append(Tick(cssPosition: position, pixelOffset: CGFloat(offset)))
            position += step
        }
    }
}
