import CoreGraphics
import Foundation
import ImageIO
import SleepyHollow
import Testing
import TestSupport

/// The readout stages against a real render: `--max-size` fitting and
/// `--tile` cutting of `capture-banded.html`, a 1280×12982 document whose
/// 1000px colour bands say which slice of the page a strip actually shows.
@Suite("ShotOperation readout stages")
struct CaptureShotReadoutTests {
    @Test
    @MainActor
    func `a full-page capture fitted to 2000 has a longest side of exactly 2000`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-banded.html", relativeTo: base)!)
            let output = try await host.execute(
                ShotOperation(region: .fullPage, fit: ShotFit(maxSize: 2000)),
            )
            #expect(output.images.count == 1)
            let image = try #require(output.images.first)
            let dimensions = try #require(pixelDimensions(ofPNG: image.png))
            #expect(max(dimensions.width, dimensions.height) == 2000)
            #expect(dimensions.width == 197)
            // The rect is still the CSS document rect; only the pixels thinned.
            #expect(image.rect == CGRect(x: 0, y: 0, width: 1280, height: 12982))
            #expect(image.scale == 1)
        }
    }

    @Test
    @MainActor
    func `tiles default to the viewport height and overlap by 40 CSS px`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-banded.html", relativeTo: base)!)
            let output = try await host.execute(ShotOperation(region: .fullPage, tile: .automatic))
            #expect(output.images.count > 1)
            #expect(output.images[0].rect.height == CGFloat(LoadOptions().size.height))
            for (previous, next) in zip(output.images, output.images.dropFirst()) {
                #expect(previous.rect.maxY - next.rect.minY == 40)
            }
            #expect(output.images.last?.rect.maxY == 12982)
        }
    }

    @Test
    @MainActor
    func `a tile height derived from --max-size cuts 2000 CSS px strips`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-banded.html", relativeTo: base)!)
            let output = try await host.execute(
                ShotOperation(region: .fullPage, fit: ShotFit(maxSize: 2000), tile: .automatic),
            )
            #expect(output.images.map(\.rect.minY) == [0, 1960, 3920, 5880, 7840, 9800, 11760])
            // 1280×2000 is already inside the cap, so the fit changes nothing.
            let dimensions = try #require(pixelDimensions(ofPNG: output.images[0].png))
            #expect(dimensions.width == 1280)
            #expect(dimensions.height == 2000)
        }
    }

    @Test
    @MainActor
    func `an index entry's rect captures the same pixels as the tile`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-banded.html", relativeTo: base)!)
            let tiles = try await host.execute(ShotOperation(region: .fullPage, tile: .cssPixels(3000)))
            let entry = try #require(tiles.images.dropFirst().first)
            let pasted = try await host.execute(ShotOperation(region: .rect(entry.rect)))
            let pastedPNG = try #require(pasted.images.first).png
            let tileImage = try #require(Self.decodePNG(entry.png))
            let rectImage = try #require(Self.decodePNG(pastedPNG))
            #expect(tileImage.width == rectImage.width)
            #expect(tileImage.height == rectImage.height)
            for y in [0, 500, 1500, 2999] {
                let tilePixel = try #require(redChannel(of: tileImage, x: 640, y: y))
                #expect(redChannel(of: rectImage, x: 640, y: y) == tilePixel)
                // The band the document row (entry.rect.minY + y) lives in.
                let expected = (Int(entry.rect.minY) + y) / 1000 * 17
                #expect(abs(Int(tilePixel) - expected) <= 8)
            }
        }
    }

    @Test
    @MainActor
    func `tiling a capture that fits in one strip still yields one image`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-banded.html", relativeTo: base)!)
            let output = try await host.execute(ShotOperation(tile: .cssPixels(4000)))
            #expect(output.images.count == 1)
            #expect(output.images[0].rect.height == CGFloat(LoadOptions().size.height))
        }
    }

    /// A PNG's pixels, for comparing two captures of the same document rect.
    private static func decodePNG(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
