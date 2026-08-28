import CoreGraphics
import Foundation
import SleepyHollow
import Testing

@Suite("ShotGrid")
struct ShotGridTests {
    // MARK: - Ticks

    @Test func `ticks start at the first step boundary inside the crop, in CSS document px`() {
        // A --rect 0,850,… crop rendered at half density: the first ruler
        // label below the origin is 900, not 50 (pixels) and not 100 (a
        // crop-relative step).
        let ticks = ShotGrid.ticks(fromCSSOrigin: 850, acrossPixels: 120, pixelsPerCSSPixel: 0.5, step: 100)
        #expect(ticks.first?.cssPosition == 900)
        #expect(ticks.first?.label == "900")
        #expect(ticks.first?.pixelOffset == 25)
    }

    @Test func `ticks cover the crop and stop at its far edge`() {
        // 120 px at 0.5 px per CSS px is 240 CSS px: 850…1090.
        let ticks = ShotGrid.ticks(fromCSSOrigin: 850, acrossPixels: 120, pixelsPerCSSPixel: 0.5, step: 100)
        #expect(ticks.map(\.cssPosition) == [900, 1000])
        #expect(ticks.map(\.pixelOffset) == [25, 75])
    }

    @Test func `a crop whose origin is a step boundary gets a tick at zero`() {
        let ticks = ShotGrid.ticks(fromCSSOrigin: 0, acrossPixels: 250, pixelsPerCSSPixel: 1, step: 100)
        #expect(ticks.map(\.cssPosition) == [0, 100, 200])
        #expect(ticks.map(\.pixelOffset) == [0, 100, 200])
    }

    @Test func `a fitted capture keeps document labels and moves the pixel offsets`() {
        // --max-size shrank the image to a quarter of a device pixel per CSS
        // px; the labels are unchanged document coordinates.
        let ticks = ShotGrid.ticks(fromCSSOrigin: 137, acrossPixels: 100, pixelsPerCSSPixel: 0.25, step: 100)
        #expect(ticks.map(\.cssPosition) == [200, 300, 400, 500])
        #expect(ticks.first?.pixelOffset == 15.75)
    }

    @Test func `a scale 2 capture labels in CSS px, not device px`() {
        let ticks = ShotGrid.ticks(fromCSSOrigin: 0, acrossPixels: 500, pixelsPerCSSPixel: 2, step: 100)
        #expect(ticks.map(\.cssPosition) == [0, 100, 200])
        #expect(ticks.map(\.pixelOffset) == [0, 200, 400])
    }

    // MARK: - Layout

    @Test func `the layout labels both rulers from the capture's own rect and density`() throws {
        let capture = try ShotCapture(
            image: syntheticImage(width: 200, height: 120),
            rect: CGRect(x: 0, y: 850, width: 400, height: 240),
            scale: 1,
        )
        let layout = ShotGrid.Layout(for: capture, options: .init(), pixelsPerCSSPixel: 0.5)
        #expect(layout.rows.map(\.cssPosition) == [900, 1000])
        #expect(layout.columns.map(\.cssPosition) == [0, 100, 200, 300])
        #expect(layout.topGutter == 24)
        #expect(layout.leftGutter >= 24)
        #expect(layout.pageWidth == 200)
        #expect(layout.pageHeight == 120)
    }

    // MARK: - Drawing

    @Test func `the gridded capture grows by its gutters and keeps its rect and scale`() throws {
        let capture = try ShotCapture(
            image: syntheticImage(width: 200, height: 120),
            rect: CGRect(x: 0, y: 850, width: 400, height: 240),
            scale: 2,
        )
        let layout = ShotGrid.Layout(for: capture, options: .init(), pixelsPerCSSPixel: 0.5)
        let gridded = try ShotGrid.draw(.init(), on: capture, pixelsPerCSSPixel: 0.5)
        #expect(gridded.image.width == 200 + layout.leftGutter)
        #expect(gridded.image.height == 120 + layout.topGutter)
        #expect(gridded.rect == capture.rect)
        #expect(gridded.scale == 2)
    }

    @Test func `rulers mode leaves every page pixel byte-identical`() throws {
        let image = try syntheticImage(width: 200, height: 120)
        let capture = ShotCapture(image: image, rect: CGRect(x: 0, y: 850, width: 400, height: 240), scale: 1)
        let options = ShotGrid.Options(mode: .rulers, step: 100)
        let layout = ShotGrid.Layout(for: capture, options: options, pixelsPerCSSPixel: 0.5)
        let gridded = try ShotGrid.draw(options, on: capture, pixelsPerCSSPixel: 0.5)
        let page = try #require(gridded.image.cropping(to: CGRect(
            x: layout.leftGutter,
            y: layout.topGutter,
            width: 200,
            height: 120,
        )))
        #expect(try rgbaBytes(of: page) == rgbaBytes(of: image))
    }

    @Test func `lines mode draws over the page at each step and rulers mode does not`() throws {
        let image = try syntheticImage(width: 200, height: 120)
        let capture = ShotCapture(image: image, rect: CGRect(x: 0, y: 850, width: 400, height: 240), scale: 1)
        let options = ShotGrid.Options(mode: .rulersAndLines, step: 100)
        let layout = ShotGrid.Layout(for: capture, options: options, pixelsPerCSSPixel: 0.5)
        let gridded = try ShotGrid.draw(options, on: capture, pixelsPerCSSPixel: 0.5)
        let page = try #require(gridded.image.cropping(to: CGRect(
            x: layout.leftGutter,
            y: layout.topGutter,
            width: 200,
            height: 120,
        )))
        let drawn = try rgbaBytes(of: page)
        let original = try rgbaBytes(of: image)
        #expect(drawn != original)
        // The lines land on the steps: 900 CSS px is 25 px down, 100 CSS px
        // is 50 px across, and a pixel on neither is untouched.
        #expect(pixel(x: 120, y: 25, of: drawn, width: 200) != pixel(x: 120, y: 25, of: original, width: 200))
        #expect(pixel(x: 50, y: 60, of: drawn, width: 200) != pixel(x: 50, y: 60, of: original, width: 200))
        #expect(pixel(x: 25, y: 60, of: drawn, width: 200) == pixel(x: 25, y: 60, of: original, width: 200))
    }

    @Test func `both gutters carry ink, so the labels actually rendered`() throws {
        let capture = try ShotCapture(
            image: syntheticImage(width: 200, height: 120),
            rect: CGRect(x: 0, y: 850, width: 400, height: 240),
            scale: 1,
        )
        let options = ShotGrid.Options(mode: .rulers, step: 100)
        let layout = ShotGrid.Layout(for: capture, options: options, pixelsPerCSSPixel: 0.5)
        let gridded = try ShotGrid.draw(options, on: capture, pixelsPerCSSPixel: 0.5)
        let top = try #require(gridded.image.cropping(to: CGRect(
            x: layout.leftGutter,
            y: 0,
            width: 200,
            height: layout.topGutter,
        )))
        let left = try #require(gridded.image.cropping(to: CGRect(
            x: 0,
            y: layout.topGutter,
            width: layout.leftGutter,
            height: 120,
        )))
        #expect(try darkPixelCount(in: top) > 10)
        #expect(try darkPixelCount(in: left) > 10)
    }

    @Test func `a non-positive step is a usage error`() throws {
        let capture = try ShotCapture(
            image: syntheticImage(width: 20, height: 20),
            rect: CGRect(x: 0, y: 0, width: 20, height: 20),
            scale: 1,
        )
        #expect(throws: SleepyError.self) {
            _ = try ShotGrid.draw(.init(mode: .rulers, step: 0), on: capture, pixelsPerCSSPixel: 1)
        }
    }

    // MARK: - Mode

    @Test func `the mode parses the two CLI spellings and refuses anything else`() throws {
        #expect(try ShotGrid.Mode(parsing: "lines") == .rulersAndLines)
        #expect(try ShotGrid.Mode(parsing: "rulers") == .rulers)
        #expect(throws: SleepyError.self) { _ = try ShotGrid.Mode(parsing: "gutter") }
    }
}

// MARK: - Helpers

/// A deterministic RGBA image whose every pixel differs from its neighbours,
/// so any stray drawing over the page area shows up as a byte difference.
private func syntheticImage(width: Int, height: Int) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    for y in 0 ..< height {
        for x in 0 ..< width {
            let index = (y * width + x) * 4
            bytes[index] = UInt8((x * 7) % 256)
            bytes[index + 1] = UInt8((y * 5) % 256)
            bytes[index + 2] = UInt8((x + y) % 256)
            bytes[index + 3] = 255
        }
    }
    let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
    return try #require(CGImage(
        width: width,
        height: height,
        bitsPerComponent: 8,
        bitsPerPixel: 32,
        bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
        provider: provider,
        decode: nil,
        shouldInterpolate: false,
        intent: .defaultIntent,
    ))
}

/// The image's pixels as tightly packed RGBA bytes, top row first.
private func rgbaBytes(of image: CGImage) throws -> [UInt8] {
    let width = image.width
    let height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    try bytes.withUnsafeMutableBytes { raw in
        let context = try #require(CGContext(
            data: raw.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ))
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return bytes
}

/// One pixel of a tightly packed RGBA buffer, counting down from the top.
private func pixel(x: Int, y: Int, of bytes: [UInt8], width: Int) -> ArraySlice<UInt8> {
    let start = (y * width + x) * 4
    return bytes[start ..< (start + 4)]
}

/// How many pixels are dark enough to be ink rather than gutter background.
private func darkPixelCount(in image: CGImage) throws -> Int {
    let bytes = try rgbaBytes(of: image)
    return stride(from: 0, to: bytes.count, by: 4).reduce(into: 0) { total, index in
        if Int(bytes[index]) + Int(bytes[index + 1]) + Int(bytes[index + 2]) < 300 { total += 1 }
    }
}
