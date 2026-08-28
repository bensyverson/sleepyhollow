import CoreGraphics
import Foundation
import SleepyHollow
import Testing
import TestSupport

/// `shot --scale`: device pixels per CSS px in the PNG, with the layout,
/// the breakpoints and the reported rects left exactly where `--size` put
/// them.
@Suite("shot --scale")
struct CaptureShotScaleTests {
    @Test
    @MainActor
    func `a scale-2 viewport shot has twice the pixels of the scale-1 one`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-breakpoint.html", relativeTo: base)!)
            let dense = try await host.execute(ShotOperation(scale: ShotScale(factor: 2)))
            let image = try #require(dense.images.first)
            let dimensions = try #require(pixelDimensions(ofPNG: image.png))
            #expect(dimensions.width == LoadOptions().size.width * 2)
            #expect(dimensions.height == LoadOptions().size.height * 2)
            #expect(image.scale == 2)
            #expect(image.rect == CGRect(x: 0, y: 0, width: 1280, height: 800))
            #expect(Double(image.pixelsPerCSSPixel) == 2)
        }
    }

    @Test
    @MainActor
    func `halving a scale-2 capture reproduces the scale-1 capture`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-breakpoint.html", relativeTo: base)!)
            let plain = try await host.execute(ShotOperation())
            let dense = try await host.execute(ShotOperation(scale: ShotScale(factor: 2)))
            let one = try #require(decodedImage(ofPNG: plain.images[0].png))
            let two = try #require(decodedImage(ofPNG: dense.images[0].png))
            let difference = try #require(meanChannelDifference(two, one, width: one.width, height: one.height))
            // Antialiasing noise only: the two rasters are the same layout.
            #expect(difference < 4)
        }
    }

    @Test
    @MainActor
    func `a 1000px media query resolves the same at scale 1 and scale 2`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let wide = PageHost(options: LoadOptions(size: ViewportSize(width: 1280, height: 400)))
            _ = try await wide.load(URL(string: "capture-breakpoint.html", relativeTo: base)!)
            let plain = try #require(try await decodedImage(ofPNG: wide.execute(ShotOperation()).images[0].png))
            let dense = try #require(
                try await decodedImage(ofPNG: wide.execute(ShotOperation(scale: ShotScale(factor: 2))).images[0].png),
            )
            // The probe is blue above the breakpoint — at both densities.
            let plainProbe = try #require(pixelColor(of: plain, x: 150, y: 150))
            let denseProbe = try #require(pixelColor(of: dense, x: 300, y: 300))
            #expect(plainProbe.blue > 200)
            #expect(plainProbe.red < 50)
            #expect(denseProbe.blue > 200)
            #expect(denseProbe.red < 50)

            let narrow = PageHost(options: LoadOptions(size: ViewportSize(width: 480, height: 400)))
            _ = try await narrow.load(URL(string: "capture-breakpoint.html", relativeTo: base)!)
            let below = try #require(
                try await decodedImage(ofPNG: narrow.execute(ShotOperation(scale: ShotScale(factor: 2))).images[0].png),
            )
            let belowProbe = try #require(pixelColor(of: below, x: 300, y: 300))
            #expect(belowProbe.red > 200)
            #expect(belowProbe.blue < 50)
        }
    }

    @Test
    @MainActor
    func `an element capture at scale 2 is exactly twice the scale-1 pixels`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let plain = try await host.execute(ShotOperation(region: .element("#target")))
            let dense = try await host.execute(ShotOperation(region: .element("#target"), scale: ShotScale(factor: 2)))
            let one = try #require(pixelDimensions(ofPNG: plain.images[0].png))
            let two = try #require(pixelDimensions(ofPNG: dense.images[0].png))
            #expect(two.width == one.width * 2)
            #expect(two.height == one.height * 2)
            #expect(dense.images[0].rect == plain.images[0].rect)
        }
    }

    @Test
    @MainActor
    func `a full-page capture at scale 2 is exactly twice the scale-1 pixels`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let plain = try await host.execute(ShotOperation(region: .fullPage))
            let dense = try await host.execute(ShotOperation(region: .fullPage, scale: ShotScale(factor: 2)))
            let one = try #require(pixelDimensions(ofPNG: plain.images[0].png))
            let two = try #require(pixelDimensions(ofPNG: dense.images[0].png))
            #expect(two.width == one.width * 2)
            #expect(two.height == one.height * 2)
            #expect(dense.images[0].rect == plain.images[0].rect)
        }
    }

    @Test
    @MainActor
    func `a rect capture at scale 2 is exactly twice the scale-1 pixels`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let rect = CGRect(x: 0, y: 850, width: 1280, height: 1285)
            let dense = try await host.execute(ShotOperation(region: .rect(rect), scale: ShotScale(factor: 2)))
            let dimensions = try #require(pixelDimensions(ofPNG: dense.images[0].png))
            #expect(dimensions.width == 2560)
            #expect(dimensions.height == 2570)
            #expect(dense.images[0].rect == rect)
        }
    }

    @Test
    @MainActor
    func `a scale past the host's own density is refused rather than upsampled`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-breakpoint.html", relativeTo: base)!)
            do {
                _ = try await host.execute(ShotOperation(scale: ShotScale(factor: 3)))
                Issue.record("expected an environment SleepyError on a 2x host")
            } catch let error as SleepyError {
                #expect(error.kind == .environment)
                #expect(error.exitStatus == ExitStatus.environment)
                #expect(error.message.contains("--scale 3"))
                #expect(error.message.contains("upsample"))
            }
        }
    }

    @Test
    @MainActor
    func `a gridded scale-2 capture keeps the page rect and adds one gutter`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-breakpoint.html", relativeTo: base)!)
            let gridded = try await host.execute(
                ShotOperation(scale: ShotScale(factor: 2), grid: ShotGrid.Options(mode: .rulers)),
            )
            let image = try #require(gridded.images.first)
            let dimensions = try #require(pixelDimensions(ofPNG: image.png))
            #expect(dimensions.height == LoadOptions().size.height * 2 + ShotGrid.minimumGutter)
            #expect(image.rect == CGRect(x: 0, y: 0, width: 1280, height: 800))
        }
    }
}
