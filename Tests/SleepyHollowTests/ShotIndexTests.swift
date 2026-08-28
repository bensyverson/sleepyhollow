import CoreGraphics
import Foundation
import SleepyHollow
import Testing

@Suite("ShotIndex")
struct ShotIndexTests {
    static let image = ShotImage(
        png: Data([1, 2, 3]),
        rect: CGRect(x: 0, y: 960, width: 1280, height: 2000),
        scale: 1,
        pixelSize: CGSize(width: 1280, height: 2000),
    )

    @Test func `an entry describes the image's document rect and its density`() {
        let tile = ShotIndex.Tile(file: "strips-02.png", image: Self.image)
        #expect(tile.file == "strips-02.png")
        #expect(tile.y == 960)
        #expect(tile.height == 2000)
        #expect(tile.x == 0)
        #expect(tile.width == 1280)
        #expect(tile.scale == 1)
    }

    @Test func `a fitted image reports the fractional pixels it actually holds`() {
        let fitted = ShotImage(
            png: Data(),
            rect: CGRect(x: 0, y: 0, width: 1280, height: 12982),
            scale: 1,
            pixelSize: CGSize(width: 197, height: 2000),
        )
        let tile = ShotIndex.Tile(file: "over.png", image: fitted)
        #expect(abs(tile.scale - 197.0 / 1280.0) < 0.0001)
    }

    @Test func `the index round-trips and prints the documented keys`() throws {
        let index = ShotIndex(tiles: [ShotIndex.Tile(file: "strips-01.png", image: Self.image)])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(index)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"tiles\""))
        #expect(text.contains("\"file\":\"strips-01.png\""))
        #expect(text.contains("\"y\":960"))
        #expect(text.contains("\"height\":2000"))
        #expect(try JSONDecoder().decode(ShotIndex.self, from: data) == index)
    }
}
