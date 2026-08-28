import AppKit
import CoreGraphics
import CoreText
import Foundation

/// The contact-sheet stage: N captures laid out as one labeled mosaic.
///
/// "Which breakpoint breaks?" is a question about the *set* of renders, and an
/// agent that has to open four PNGs in turn has to hold three of them in its
/// head. A sheet answers it in one image: a `columns × rows` grid inside the
/// caller's pixel budget, every cell fitted to the same box with its
/// parameters burned into a gutter above it. The sheet says *where* something
/// changed; the full-size file — written alongside, and named in the same
/// ``ShotVariantIndex`` — is where the detail is.
///
/// Deliberately not for `--tile`: a tall page cut into strips and then shrunk
/// into a mosaic scrambles exactly the reading order the strips preserved.
public enum ShotSheet {
    /// The default pixel budget for a sheet's longest side: the same ~2,000px
    /// an agent reads a single capture through (see ``ShotFit``).
    public static let defaultMaxSize: Int = 2000

    /// The label strip above each cell, in pixels.
    public static let labelGutter: Int = 18

    /// One cell: the pixels, and what to write above them.
    ///
    /// Not `Friendly` — it holds a ``ShotCapture``, which is in-process
    /// currency rather than a wire shape.
    public struct Cell: Sendable {
        /// The capture this cell shows.
        public let capture: ShotCapture
        /// The line burned into the cell's gutter — a variant's
        /// ``ShotPlan/Variant/label``.
        public let label: String

        /// Creates a cell.
        public init(capture: ShotCapture, label: String) {
            self.capture = capture
            self.label = label
        }
    }

    /// Where every cell goes, in pixels. Separated from the drawing so the
    /// geometry can be asserted without rasterizing anything.
    public struct Layout: Friendly {
        /// Cells across.
        public let columns: Int
        /// Cells down.
        public let rows: Int
        /// The image box inside one cell, excluding its gutter.
        public let cellWidth: Int
        /// The image box's height inside one cell.
        public let cellHeight: Int

        /// Lays out `count` cells inside a pixel budget.
        ///
        /// - Parameters:
        ///   - count: how many cells.
        ///   - contentAspect: the *set's* bounding height ÷ bounding width —
        ///     the tallest capture's height over the widest capture's width.
        ///     Sizing the box to that, and then drawing every capture at one
        ///     shared factor, is what keeps a 390-wide render visibly narrower
        ///     than a 1280-wide one instead of blowing both up to fill their
        ///     own cells.
        ///   - maxSize: the longest side the whole sheet may have.
        public init(count: Int, contentAspect: CGFloat, maxSize: Int) {
            let cells = max(1, count)
            let budget = max(1, maxSize)
            columns = max(1, Int(Double(cells).squareRoot().rounded(.up)))
            rows = max(1, Int((Double(cells) / Double(columns)).rounded(.up)))

            let width: Int = max(1, budget / columns)
            let height: Int = max(1, Int((CGFloat(width) * max(contentAspect, 0.01)).rounded()))
            let tall: Int = rows * (height + ShotSheet.labelGutter)
            guard tall > budget else {
                cellWidth = width
                cellHeight = height
                return
            }
            // Reserve the gutters first — they never shrink, or the labels stop
            // being legible at exactly the sheet sizes that need them most —
            // then give the rows what is left, exactly, and take the width from
            // the height so the cell keeps the tallest capture's aspect.
            let room: Int = max(1, budget - rows * ShotSheet.labelGutter)
            cellHeight = max(1, room / rows)
            cellWidth = max(1, Int((CGFloat(width) * CGFloat(cellHeight) / CGFloat(height)).rounded(.down)))
        }

        /// The sheet's pixel width.
        public var width: Int {
            columns * cellWidth
        }

        /// The sheet's pixel height, gutters included.
        public var height: Int {
            rows * (cellHeight + ShotSheet.labelGutter)
        }

        /// The top-left corner of cell `index`, counted from the sheet's
        /// top-left — reading order, left to right then down.
        public func cellOrigin(_ index: Int) -> CGPoint {
            CGPoint(
                x: CGFloat((index % columns) * cellWidth),
                y: CGFloat((index / columns) * (cellHeight + ShotSheet.labelGutter)),
            )
        }
    }

    /// Composes `cells` into one mosaic.
    ///
    /// The result's ``ShotCapture/rect`` is the sheet's own pixel box, not a
    /// document rect: a mosaic shows several documents at once, so there is no
    /// single region to paste back into `--rect`. That is what the full-size
    /// files beside it are for.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` for an
    ///   empty set of cells; ``SleepyError/Kind/environment`` when the bitmap
    ///   cannot be built.
    public static func compose(_ cells: [Cell], maxSize: Int = defaultMaxSize) throws -> ShotCapture {
        guard !cells.isEmpty else {
            throw SleepyError(
                kind: .usage,
                message: "A contact sheet needs at least one capture, and none was rendered.",
                nextMove: "Repeat --size, --scale or --theme so there is more than one render to lay out.",
            )
        }
        let bounds: CGSize = boundingSize(of: cells)
        let layout = Layout(count: cells.count, contentAspect: bounds.height / bounds.width, maxSize: maxSize)
        // One factor for every cell, so relative widths survive the mosaic.
        let factor: CGFloat = min(CGFloat(layout.cellWidth) / bounds.width, CGFloat(layout.cellHeight) / bounds.height)
        guard let context = CGContext(
            data: nil,
            width: layout.width,
            height: layout.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            throw SleepyError(
                kind: .environment,
                message: "Could not build a \(layout.width)×\(layout.height) bitmap for the contact sheet.",
                nextMove: "Retry with a smaller --max-size; if this persists, it is a seam bug against CGContext.",
            )
        }
        context.setFillColor(ShotGrid.background)
        context.fill(CGRect(x: 0, y: 0, width: layout.width, height: layout.height))
        for (index, cell) in cells.enumerated() {
            draw(cell, at: index, layout: layout, factor: factor, in: context)
        }
        guard let image = context.makeImage() else {
            throw SleepyError(
                kind: .environment,
                message: "Could not read the contact sheet back as an image.",
                nextMove: "Retry; if this persists, it is a seam bug against CGContext.makeImage.",
            )
        }
        return ShotCapture(
            image: image,
            rect: CGRect(x: 0, y: 0, width: layout.width, height: layout.height),
            scale: 1,
        )
    }

    /// The bounding box of every capture in `cells`, in pixels — never zero,
    /// so it can be divided by.
    private static func boundingSize(of cells: [Cell]) -> CGSize {
        CGSize(
            width: max(1, cells.map(\.capture.image.width).max() ?? 1),
            height: max(1, cells.map(\.capture.image.height).max() ?? 1),
        )
    }

    /// Draws one cell: its label in the gutter, its capture below at the
    /// sheet's shared scale, outlined so neighbouring white pages do not run
    /// into one another.
    private static func draw(_ cell: Cell, at index: Int, layout: Layout, factor: CGFloat, in context: CGContext) {
        let origin: CGPoint = layout.cellOrigin(index)
        // CGContext counts from the bottom-left; the layout counts from the top.
        let top = CGFloat(layout.height) - origin.y
        let box = CGRect(
            x: origin.x,
            y: top - CGFloat(labelGutter + layout.cellHeight),
            width: CGFloat(layout.cellWidth),
            height: CGFloat(layout.cellHeight),
        )
        let placed: CGRect = placement(cell.capture.image, in: box, factor: factor)

        context.saveGState()
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        context.clip(to: CGRect(
            x: origin.x,
            y: top - CGFloat(labelGutter),
            width: CGFloat(layout.cellWidth),
            height: CGFloat(labelGutter),
        ))
        // Over the capture's own left edge, not the cell's: a narrow render is
        // letterboxed, and a label floating in the margin reads as its
        // neighbour's.
        ShotGrid.draw(
            cell.label,
            at: CGPoint(x: placed.minX + CGFloat(labelInset), y: top - CGFloat(labelGutter) + 5),
            font: ShotGrid.labelFont(ofSize: labelFontSize),
            in: context,
        )
        context.restoreGState()

        context.saveGState()
        context.interpolationQuality = .high
        context.draw(cell.capture.image, in: placed)
        context.setStrokeColor(ShotGrid.tick)
        context.setLineWidth(1)
        context.stroke(placed.insetBy(dx: 0.5, dy: 0.5))
        context.restoreGState()
    }

    /// Where `image` lands inside `box`: scaled by the sheet's shared
    /// `factor` and centred, so a narrow render reads as narrow and a cell is
    /// letterboxed rather than cropped — a cropped breakpoint is the one thing
    /// a contact sheet must not hide.
    private static func placement(_ image: CGImage, in box: CGRect, factor: CGFloat) -> CGRect {
        let width: CGFloat = max(1, CGFloat(image.width) * factor)
        let height: CGFloat = max(1, CGFloat(image.height) * factor)
        return CGRect(
            x: (box.midX - width / 2).rounded(),
            y: (box.maxY - height).rounded(),
            width: width.rounded(),
            height: height.rounded(),
        )
    }

    /// The cell label's point size — larger than a ruler's, because it is read
    /// rather than counted.
    private static let labelFontSize: CGFloat = 11

    /// The gap between a label and its cell's left edge.
    private static let labelInset: Int = 4
}
