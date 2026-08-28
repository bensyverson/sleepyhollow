import AppKit
import CoreGraphics
import CoreText
import Foundation

/// Rasterizing the grid: the gutter blit, the in-page lines, the ruler marks
/// and the Core Text labels.
///
/// Split from the types so the geometry — ``ShotGrid/Layout`` and
/// ``ShotGrid/ticks(fromCSSOrigin:acrossPixels:pixelsPerCSSPixel:step:)`` —
/// can be read and tested without wading through drawing state.
extension ShotGrid {
    /// Draws the grid, returning a capture whose image is the original
    /// surrounded by gutters.
    ///
    /// The result keeps the input's ``ShotCapture/rect`` and
    /// ``ShotCapture/scale`` — the gutter is chrome, not content, and the
    /// pixels still show exactly that document rect — so
    /// ``ShotCapture/pixelSize`` is deliberately larger than
    /// `rect × scale` for a gridded capture.
    ///
    /// In ``Mode/rulers`` the page area is byte-identical to the input: the
    /// pixels are blitted at an integer offset with
    /// `CGBlendMode.copy` and no interpolation, every ruler mark lands
    /// inside the gutter, and the label text is clipped to the gutter so no
    /// antialiased edge bleeds into the page.
    ///
    /// - Parameters:
    ///   - options: the mode and step.
    ///   - capture: the capture to draw around.
    ///   - pixelsPerCSSPixel: image pixels per CSS px after any `--max-size`
    ///     fit — see the type's discussion for why this is not read from
    ///     ``ShotCapture/scale``.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` for a
    ///   non-positive step or density; ``SleepyError/Kind/environment``
    ///   when the bitmap context cannot be built — a seam bug, never a page
    ///   fact.
    public static func draw(
        _ options: Options = Options(),
        on capture: ShotCapture,
        pixelsPerCSSPixel: CGFloat,
    ) throws -> ShotCapture {
        guard options.step > 0 else {
            throw SleepyError(
                kind: .usage,
                message: "'--grid-step' wants a positive number of CSS px; got \(options.step).",
                nextMove: "Pass a step above 0, e.g. --grid-step 100.",
            )
        }
        guard pixelsPerCSSPixel > 0 else {
            throw SleepyError(
                kind: .usage,
                message: "The grid needs a positive pixels-per-CSS-px density; got \(pixelsPerCSSPixel).",
                nextMove: "This is a pipeline seam: the fit stage should never hand on a zero density.",
            )
        }
        let layout = Layout(for: capture, options: options, pixelsPerCSSPixel: pixelsPerCSSPixel)
        let width = layout.pageWidth + layout.leftGutter
        let height = layout.pageHeight + layout.topGutter
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            throw SleepyError(
                kind: .environment,
                message: "Could not build a \(width)×\(height) bitmap for the grid.",
                nextMove: "Retry with a smaller --max-size; if this persists, it is a seam bug against CGContext.",
            )
        }
        context.setShouldAntialias(false)
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.setFillColor(background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.draw(
            capture.image,
            in: CGRect(x: layout.leftGutter, y: 0, width: layout.pageWidth, height: layout.pageHeight),
        )
        context.setBlendMode(.normal)
        if options.mode == .rulersAndLines { drawLines(layout, in: context) }
        drawRulers(layout, in: context)
        guard let image = context.makeImage() else {
            throw SleepyError(
                kind: .environment,
                message: "Could not read the gridded bitmap back as an image.",
                nextMove: "Retry; if this persists, it is a seam bug against CGContext.makeImage.",
            )
        }
        return ShotCapture(image: image, rect: capture.rect, scale: capture.scale)
    }

    // MARK: - Drawing

    /// Faint full-width and full-height lines at every step, inside the page
    /// area. A mid-gray at low alpha rather than a light or dark tint, so it
    /// stays visible over both a white page and a dark-theme one.
    private static func drawLines(_ layout: Layout, in context: CGContext) {
        context.saveGState()
        context.setFillColor(line)
        for tick in layout.columns {
            context.fill(CGRect(
                x: CGFloat(layout.leftGutter) + tick.pixelOffset.rounded(.down),
                y: 0,
                width: 1,
                height: CGFloat(layout.pageHeight),
            ))
        }
        for tick in layout.rows {
            context.fill(CGRect(
                x: CGFloat(layout.leftGutter),
                y: CGFloat(layout.pageHeight) - 1 - tick.pixelOffset.rounded(.down),
                width: CGFloat(layout.pageWidth),
                height: 1,
            ))
        }
        context.restoreGState()
    }

    /// Tick marks and numbers, entirely within the gutters.
    private static func drawRulers(_ layout: Layout, in context: CGContext) {
        let pageTop = CGFloat(layout.pageHeight)
        let font = labelFont()

        context.saveGState()
        context.setFillColor(tick)
        for mark in layout.columns {
            context.fill(CGRect(
                x: CGFloat(layout.leftGutter) + mark.pixelOffset.rounded(.down),
                y: pageTop,
                width: 1,
                height: CGFloat(tickLength),
            ))
        }
        for mark in layout.rows {
            context.fill(CGRect(
                x: CGFloat(layout.leftGutter - tickLength),
                y: pageTop - 1 - mark.pixelOffset.rounded(.down),
                width: CGFloat(tickLength),
                height: 1,
            ))
        }
        context.restoreGState()

        context.saveGState()
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        context.setShouldSubpixelPositionFonts(false)
        context.setShouldSubpixelQuantizeFonts(false)

        context.saveGState()
        context.clip(to: CGRect(
            x: CGFloat(layout.leftGutter),
            y: pageTop,
            width: CGFloat(layout.pageWidth),
            height: CGFloat(layout.topGutter),
        ))
        var nextFreeX = -CGFloat.greatestFiniteMagnitude
        for mark in layout.columns {
            let x = CGFloat(layout.leftGutter) + mark.pixelOffset.rounded(.down) + 2
            guard x >= nextFreeX else { continue }
            draw(mark.label, at: CGPoint(x: x, y: pageTop + CGFloat(tickLength) + 3), font: font, in: context)
            nextFreeX = x + labelWidth(mark.label) + 6
        }
        context.restoreGState()

        context.saveGState()
        context.clip(to: CGRect(
            x: 0,
            y: 0,
            width: CGFloat(layout.leftGutter),
            height: pageTop + CGFloat(layout.topGutter),
        ))
        var nextFreeY = CGFloat.greatestFiniteMagnitude
        for mark in layout.rows {
            let y = pageTop - 1 - mark.pixelOffset.rounded(.down) + 3
            guard y <= nextFreeY else { continue }
            draw(mark.label, at: CGPoint(x: CGFloat(labelInset), y: y), font: font, in: context)
            nextFreeY = y - lineHeight
        }
        context.restoreGState()
        context.restoreGState()
    }

    /// One label, its baseline at `point`.
    private static func draw(_ text: String, at point: CGPoint, font: CTFont, in context: CGContext) {
        context.textPosition = point
        CTLineDraw(CTLineCreateWithAttributedString(attributed(text, font: font)), context)
    }

    // MARK: - Text

    /// The ruler's typeface: a small monospaced system font, so digits line
    /// up column-wise and a label's width is predictable.
    private static func labelFont() -> CTFont {
        NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular) as CTFont
    }

    /// A label as Core Text wants it.
    private static func attributed(_ text: String, font: CTFont) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink,
        ])
    }

    /// How wide a label prints, in pixels — what sizes the left gutter.
    static func labelWidth(_ text: String) -> CGFloat {
        let line = CTLineCreateWithAttributedString(attributed(text, font: labelFont()))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    // MARK: - Constants

    /// The ruler label's point size.
    private static let fontSize: CGFloat = 9
    /// Baseline-to-baseline spacing used to suppress overlapping labels.
    private static let lineHeight: CGFloat = 12
    /// The gap between a label and the gutter's outer edge. ``ShotGrid/Layout``
    /// pads the left gutter by it on both sides.
    static let labelInset: Int = 3
    /// How far a tick mark reaches into the gutter.
    private static let tickLength: Int = 5

    /// The gutter's fill: near-white, so dark numbers read on it whatever
    /// the page's own theme is.
    private static let background: CGColor = .init(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1)
    /// The label colour.
    private static let ink: CGColor = .init(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1)
    /// The tick mark colour.
    private static let tick: CGColor = .init(srgbRed: 0.45, green: 0.45, blue: 0.48, alpha: 1)
    /// The in-page line colour: mid-gray at low alpha, legible over a white
    /// page and a dark one alike.
    private static let line: CGColor = .init(srgbRed: 0.5, green: 0.5, blue: 0.55, alpha: 0.35)
}
