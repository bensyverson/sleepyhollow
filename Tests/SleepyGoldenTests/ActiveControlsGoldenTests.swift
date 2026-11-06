import CoreGraphics
import Foundation
import ImageIO
import Testing
import TestSupport

/// The host window claims to be key, so a one-shot shot draws native controls
/// the way an active browser window does, end to end through the real binary.
///
/// Leaf `AuYtct`; the ruling is `project/2026-11-06-true-3d-shots.md`
/// § Ruling on the capture path, and the measurement behind the threshold is
/// `project/2026-11-06-compositor-capture.md` question 7.
@Suite(.serialized)
struct ActiveControlsGoldenTests {
    @Test func `a focused native control draws active, with a colored focus ring`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("controls-focused.html").absoluteString
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("sleepy-controls-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--element", "body", "--scale", "1", "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let image = try #require(Self.decoded(Data(contentsOf: out)))
            // An inactive window draws every control gray: no saturated pixel
            // at all (measured 0 in `project/2026-11-06-compositor-capture.md`
            // question 7). Active controls draw the checked box, the radio,
            // the range fill and the focus ring in the accent color — which
            // hue depends on the Mac, so saturation is what is counted.
            let saturated = Self.saturatedPixelCount(in: image)
            #expect(saturated > 500, "saturated pixels: \(saturated)")
        }
    }

    /// Decodes a PNG.
    private static func decoded(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Pixels whose channels spread by more than 80 levels: color, as opposed
    /// to the white, black and grays an inactive control is drawn in.
    private static func saturatedPixelCount(in image: CGImage) -> Int {
        let width = image.width
        let height = image.height
        var samples = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = samples.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return 0 }
        var count = 0
        for offset in stride(from: 0, to: samples.count, by: 4) {
            let channels = samples[offset ..< offset + 3]
            if let high = channels.max(), let low = channels.min(), Int(high) - Int(low) > 80 {
                count += 1
            }
        }
        return count
    }
}
