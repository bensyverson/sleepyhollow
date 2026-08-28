import CoreGraphics
import Foundation
import SleepyHollow
import Testing

@Suite("ShotScale")
struct ShotScaleTests {
    @Test func `one, two and three are the densities a caller may ask for`() throws {
        #expect(try ShotScale(factor: 1).factor == 1)
        #expect(try ShotScale(factor: 2).factor == 2)
        #expect(try ShotScale(factor: 3).factor == 3)
        #expect(ShotScale.one.factor == 1)
    }

    @Test func `a scale below one is a usage error naming the flag`() throws {
        do {
            _ = try ShotScale(factor: 0)
            Issue.record("expected a usage SleepyError")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.message.contains("--scale"))
        }
    }

    @Test func `a scale past three is a usage error naming the supported densities`() throws {
        do {
            _ = try ShotScale(factor: 4)
            Issue.record("expected a usage SleepyError")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.message.contains("4"))
            #expect(error.nextMove?.contains("3") == true)
        }
    }

    @Test func `the DPI a scale writes is 72 times the density`() throws {
        let two = try ShotScale(factor: 2)
        let three = try ShotScale(factor: 3)
        #expect(ShotScale.one.dotsPerInch == 72)
        #expect(two.dotsPerInch == 144)
        #expect(three.dotsPerInch == 216)
    }

    // MARK: - The DPI the encoded PNG carries

    @Test func `a point-for-pixel capture encodes at 72 dpi`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 200, height: 100))
        let image = try capture.encoded()
        let dpi = try #require(dotsPerInch(ofPNG: image.png))
        #expect(dpi == 72)
    }

    @Test func `a scale-2 capture encodes at 144 dpi without losing a pixel`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 200, height: 100), scale: 2)
        let image = try capture.encoded()
        let dpi = try #require(dotsPerInch(ofPNG: image.png))
        #expect(dpi == 144)
        let dimensions = try #require(pixelDimensions(ofPNG: image.png))
        #expect(dimensions.width == 400)
        #expect(dimensions.height == 200)
        #expect(image.scale == 2)
        #expect(image.pixelSize == CGSize(width: 400, height: 200))
    }

    // MARK: - The grid still counts in CSS px

    @Test func `grid ticks on a scale-2 capture label CSS px at doubled offsets`() {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 850, width: 1280, height: 400), scale: 2)
        #expect(Double(capture.pixelsPerCSSPixel) == 2)
        let layout = ShotGrid.Layout(
            for: capture,
            options: ShotGrid.Options(),
            pixelsPerCSSPixel: capture.pixelsPerCSSPixel,
        )
        #expect(layout.columns[0].cssPosition == 0)
        #expect(layout.columns[1].cssPosition == 100)
        #expect(Double(layout.columns[1].pixelOffset) == 200)
        #expect(layout.rows[0].cssPosition == 900)
        #expect(Double(layout.rows[0].pixelOffset) == 100)
        #expect(layout.rows.last?.cssPosition == 1200)
    }
}
