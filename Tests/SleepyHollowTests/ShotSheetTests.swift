import CoreGraphics
import Foundation
import SleepyHollow
import Testing

@Suite("ShotSheet")
struct ShotSheetTests {
    // MARK: - Layout

    @Test func `two cells lay out side by side`() {
        let layout = ShotSheet.Layout(count: 2, contentAspect: 800.0 / 1280.0, maxSize: 2000)
        #expect(layout.columns == 2)
        #expect(layout.rows == 1)
        #expect(layout.width == 2000)
        #expect(layout.cellWidth == 1000)
        #expect(layout.cellHeight == 625)
        #expect(layout.height == 625 + ShotSheet.labelGutter)
    }

    @Test func `the column count is the square root, rounded up`() {
        #expect(ShotSheet.Layout(count: 1, contentAspect: 1, maxSize: 800).columns == 1)
        #expect(ShotSheet.Layout(count: 3, contentAspect: 1, maxSize: 800).columns == 2)
        #expect(ShotSheet.Layout(count: 4, contentAspect: 1, maxSize: 800).columns == 2)
        #expect(ShotSheet.Layout(count: 5, contentAspect: 1, maxSize: 800).columns == 3)
        #expect(ShotSheet.Layout(count: 3, contentAspect: 1, maxSize: 800).rows == 2)
        #expect(ShotSheet.Layout(count: 5, contentAspect: 1, maxSize: 800).rows == 2)
    }

    @Test func `tall cells are shrunk until the sheet fits the budget`() {
        let layout = ShotSheet.Layout(count: 2, contentAspect: 3, maxSize: 2000)
        #expect(layout.height <= 2000)
        #expect(layout.width <= 2000)
        #expect(max(layout.width, layout.height) == 2000)
    }

    @Test func `a cell's origin walks the grid left to right, top to bottom`() {
        let layout = ShotSheet.Layout(count: 4, contentAspect: 1, maxSize: 800)
        let row = layout.cellHeight + ShotSheet.labelGutter
        #expect(layout.cellOrigin(0) == CGPoint(x: 0, y: 0))
        #expect(layout.cellOrigin(1) == CGPoint(x: layout.cellWidth, y: 0))
        #expect(layout.cellOrigin(2) == CGPoint(x: 0, y: row))
        #expect(layout.cellOrigin(3) == CGPoint(x: layout.cellWidth, y: row))
    }

    // MARK: - Composition

    @Test func `a mosaic of two captures is one image inside the budget`() throws {
        let cells = [
            ShotSheet.Cell(capture: syntheticCapture(rect: CGRect(x: 0, y: 0, width: 390, height: 800)), label: "390×800"),
            ShotSheet.Cell(
                capture: syntheticCapture(rect: CGRect(x: 0, y: 0, width: 1280, height: 800)),
                label: "1280×800",
            ),
        ]
        let sheet = try ShotSheet.compose(cells, maxSize: 1200)
        // Both captures are 800 tall, so the set's bounding aspect is the
        // widest render's — two of those side by side hit the budget on width.
        #expect(max(sheet.image.width, sheet.image.height) == 1200)
        #expect(sheet.image.width == 1200)
        #expect(sheet.pixelSize == CGSize(width: sheet.image.width, height: sheet.image.height))
    }

    @Test func `a mosaic encodes as a PNG`() throws {
        let cells = [
            ShotSheet.Cell(capture: syntheticCapture(rect: CGRect(x: 0, y: 0, width: 200, height: 100)), label: "a"),
            ShotSheet.Cell(capture: syntheticCapture(rect: CGRect(x: 0, y: 0, width: 200, height: 100)), label: "b"),
        ]
        let image = try ShotSheet.compose(cells, maxSize: 600).encoded()
        let dimensions = try #require(pixelDimensions(ofPNG: image.png))
        #expect(dimensions.width == 600)
    }

    @Test func `a sheet of nothing is a usage error`() {
        do {
            _ = try ShotSheet.compose([], maxSize: 600)
            Issue.record("expected a usage SleepyError")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    // MARK: - Decoding back into the pipeline

    @Test func `an encoded capture decodes back to the same pixels`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 10, y: 20, width: 200, height: 100), scale: 2)
        let decoded = try ShotCapture(decoding: capture.encoded())
        #expect(decoded.image.width == 400)
        #expect(decoded.image.height == 200)
        #expect(decoded.rect == capture.rect)
        #expect(decoded.scale == 2)
    }
}
