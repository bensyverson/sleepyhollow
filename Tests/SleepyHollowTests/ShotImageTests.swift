import CoreGraphics
import Foundation
import SleepyHollow
import Testing

@Suite("ShotImage")
struct ShotImageTests {
    @Test func `an image carries its PNG, CSS rect and scale, and round-trips`() throws {
        let image = ShotImage(png: Data([1, 2, 3]), rect: CGRect(x: 0, y: 850, width: 1280, height: 1285), scale: 2)
        let data = try JSONEncoder().encode(image)
        let decoded = try JSONDecoder().decode(ShotImage.self, from: data)
        #expect(decoded == image)
        #expect(decoded.pixelSize == CGSize(width: 2560, height: 2570))
    }
}
