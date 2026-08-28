import CoreGraphics
import Foundation
import SleepyHollow
import Testing

@Suite("ShotTile")
struct ShotTileTests {
    @Test func `a capture shorter than one strip is a single unchanged tile`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 200, height: 600))
        let tiles = try ShotTile(height: 1000).applied(to: capture)
        #expect(tiles.count == 1)
        #expect(tiles[0].rect == capture.rect)
        #expect(tiles[0].pixelSize == capture.pixelSize)
    }

    @Test func `adjacent strips share exactly the overlap`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 1280, height: 12982))
        let tiles = try ShotTile(height: 2000).applied(to: capture)
        #expect(tiles.count > 1)
        for (previous, next) in zip(tiles, tiles.dropFirst()) {
            let shared = previous.rect.maxY - next.rect.minY
            #expect(shared == ShotTile.defaultOverlap)
        }
    }

    @Test func `strips advance by the height minus the overlap and cover the capture`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 100, height: 5000))
        let tiles = try ShotTile(height: 1000).applied(to: capture)
        // Advance 960: 0, 960, 1920, 2880, 3840, 4800 → the last is short.
        #expect(tiles.map(\.rect.minY) == [0, 960, 1920, 2880, 3840, 4800])
        #expect(tiles.last?.rect.maxY == 5000)
        #expect(tiles.last?.rect.height == 200)
        #expect(tiles.dropLast().allSatisfy { $0.rect.height == 1000 })
    }

    @Test func `a strip that would repeat only overlap is not emitted`() throws {
        // 1000-tall capture, 500-tall strips: 0…500, 460…960, 920…1000. The
        // third strip carries 40 new px, so it is real; a fourth would carry none.
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 100, height: 1000))
        let tiles = try ShotTile(height: 500).applied(to: capture)
        #expect(tiles.map(\.rect.minY) == [0, 460, 920])
        #expect(tiles.last?.rect.maxY == 1000)
    }

    @Test func `each strip carries the document y of the rows it shows`() throws {
        // The capture starts 850 CSS px down the document, as an --element or
        // --rect crop would; tile rects stay in document space.
        let capture = syntheticCapture(rect: CGRect(x: 40, y: 850, width: 200, height: 3000))
        let tiles = try ShotTile(height: 1000).applied(to: capture)
        #expect(tiles[0].rect == CGRect(x: 40, y: 850, width: 200, height: 1000))
        #expect(tiles[1].rect.minY == 1810)
        #expect(tiles.allSatisfy { $0.rect.minX == 40 && $0.rect.width == 200 })
    }

    @Test func `a strip's pixels are the rows its rect names`() throws {
        // Bands are 100 CSS px tall; strip 1 starts at y 960, inside band 9
        // (red 153), and its 40px overlap repeats the end of strip 0.
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 200, height: 3000))
        let tiles = try ShotTile(height: 1000).applied(to: capture)
        #expect(redChannel(of: tiles[0].image, x: 100, y: 5) == 0)
        #expect(redChannel(of: tiles[1].image, x: 100, y: 5) == UInt8(9 * 17))
        #expect(redChannel(of: tiles[1].image, x: 100, y: 45) == UInt8(10 * 17))
        #expect(tiles[1].pixelSize == CGSize(width: 200, height: 1000))
    }

    @Test func `a strip of a 2x capture cuts on pixel rows, not CSS rows`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 100, height: 2000), scale: 2)
        let tiles = try ShotTile(height: 1000).applied(to: capture)
        #expect(tiles[0].pixelSize == CGSize(width: 200, height: 2000))
        #expect(tiles[1].rect.minY == 960)
        #expect(tiles[1].pixelsPerCSSPixel == 2)
    }

    @Test func `a custom overlap is honoured`() throws {
        let capture = syntheticCapture(rect: CGRect(x: 0, y: 0, width: 100, height: 1000))
        let tiles = try ShotTile(height: 400, overlap: 0).applied(to: capture)
        #expect(tiles.map(\.rect.minY) == [0, 400, 800])
    }

    @Test(arguments: [40.0, 20.0, 0.0])
    func `a strip no taller than the overlap is a usage error`(height: Double) throws {
        do {
            _ = try ShotTile(height: CGFloat(height))
                .applied(to: syntheticCapture(rect: CGRect(x: 0, y: 0, width: 100, height: 1000)))
            Issue.record("expected a usage SleepyError")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.message.contains("40"))
        }
    }

    @Test func `the requested height is Friendly and round-trips`() throws {
        for height in [ShotTile.Height.automatic, .cssPixels(1000)] {
            let decoded = try JSONDecoder().decode(ShotTile.Height.self, from: JSONEncoder().encode(height))
            #expect(decoded == height)
        }
    }
}
