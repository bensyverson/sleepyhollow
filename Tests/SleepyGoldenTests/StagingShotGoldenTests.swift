import CoreGraphics
import Foundation
import ImageIO
import Testing
import TestSupport

/// A shot staged with `--hover` shows the `:hover` style, and one staged
/// with `--focus` shows the keyboard focus style, end to end through the
/// real binary (leaf `fFz9DI`, criterion `bzl`). A `--click` leaves the
/// clicked element hovered, as a user's click does, and `--leave` takes the
/// pointer off the page so the shot shows neither (Ben's ruling,
/// 2026-11-06).
///
/// `stage-hover-focus.html` paints flat colors only a real pointer or real
/// focus produce: `#card` gray, green under `:hover`; `#action` gray, orange
/// under `:focus`, blue under `:focus-visible`. The unstaged shot is the
/// control that proves the colors come from the steps.
@Suite(.serialized)
struct StagingShotGoldenTests {
    /// An sRGB pixel, 0–255 per channel.
    private struct Pixel: Equatable, CustomStringConvertible {
        let red: Int
        let green: Int
        let blue: Int

        var description: String {
            "rgb(\(red), \(green), \(blue))"
        }

        /// Whether every channel is within `tolerance` of `other`'s.
        func isClose(to other: Pixel, tolerance: Int = 6) -> Bool {
            abs(red - other.red) <= tolerance && abs(green - other.green) <= tolerance
                && abs(blue - other.blue) <= tolerance
        }
    }

    private static let gray = Pixel(red: 0x88, green: 0x88, blue: 0x88)
    private static let green = Pixel(red: 0x00, green: 0xAA, blue: 0x00)
    private static let blue = Pixel(red: 0x00, green: 0x00, blue: 0xFF)

    /// The center of `#card`, then of `#action`, in CSS px (= pixels at
    /// `--scale 1`).
    private static let cardCenter = (x: 100, y: 70)
    private static let actionCenter = (x: 300, y: 70)

    @Test func `an unstaged shot shows neither hover nor focus`() async throws {
        let image = try await shot(staging: [])
        let card = try #require(Self.pixel(in: image, at: Self.cardCenter))
        let action = try #require(Self.pixel(in: image, at: Self.actionCenter))
        #expect(card.isClose(to: Self.gray), "card: \(card)")
        #expect(action.isClose(to: Self.gray), "action: \(action)")
    }

    @Test func `a shot staged with --hover shows the hover style`() async throws {
        let image = try await shot(staging: ["--hover", "#card"])
        let card = try #require(Self.pixel(in: image, at: Self.cardCenter))
        #expect(card.isClose(to: Self.green), "card: \(card)")
    }

    @Test func `a shot after --click shows the clicked element's hover style`() async throws {
        let image = try await shot(staging: ["--click", "#card"])
        let card = try #require(Self.pixel(in: image, at: Self.cardCenter))
        #expect(card.isClose(to: Self.green), "card: \(card)")
    }

    @Test func `a shot after --click then --leave shows no hover style`() async throws {
        let image = try await shot(staging: ["--click", "#card", "--leave"])
        let card = try #require(Self.pixel(in: image, at: Self.cardCenter))
        #expect(card.isClose(to: Self.gray), "card: \(card)")
    }

    @Test func `a shot after --hover then --leave shows no hover style`() async throws {
        let image = try await shot(staging: ["--hover", "#card", "--leave"])
        let card = try #require(Self.pixel(in: image, at: Self.cardCenter))
        #expect(card.isClose(to: Self.gray), "card: \(card)")
    }

    @Test func `recipes shows capturing the after-click state without hover`() async throws {
        let recipes = try await GoldenBinary.runOffPool(["recipes"])
        #expect(recipes.exitCode == 0)
        #expect(recipes.standardOutput.contains("--click '#btn' --leave"))
    }

    @Test func `a shot staged with --focus shows the keyboard focus style`() async throws {
        let image = try await shot(staging: ["--focus", "#action"])
        let action = try #require(Self.pixel(in: image, at: Self.actionCenter))
        #expect(action.isClose(to: Self.blue), "action: \(action)")
    }

    /// Shoots the fixture at 400×240, scale 1, with the given step flags.
    private func shot(staging steps: [String]) async throws -> CGImage {
        let data: Data = try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("stage-hover-focus.html").absoluteString
            let out = FileManager.default.temporaryDirectory
                .appendingPathComponent("sleepy-staging-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(
                ["shot", url, "--size", "400x240", "--scale", "1", "--budget", "60000", "--out", out.path] + steps,
            )
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            return try Data(contentsOf: out)
        }
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        return try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    /// The sRGB pixel at a point, origin top-left.
    private static func pixel(in image: CGImage, at point: (x: Int, y: Int)) -> Pixel? {
        var sample = [UInt8](repeating: 0, count: 4)
        let drawn: Bool = sample.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else {
                return false
            }
            // Draw the image shifted so the wanted pixel lands on the 1×1
            // context; CoreGraphics' origin is bottom-left.
            let flippedY: Int = image.height - 1 - point.y
            context.draw(image, in: CGRect(x: -point.x, y: -flippedY, width: image.width, height: image.height))
            return true
        }
        guard drawn else { return nil }
        return Pixel(red: Int(sample[0]), green: Int(sample[1]), blue: Int(sample[2]))
    }
}
