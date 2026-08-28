import Foundation
import Testing
import TestSupport

/// `sleepy shot --scale` as an agent types it: a denser raster of the same
/// layout, and a refusal rather than an upsample when the host cannot render
/// that densely.
struct ShotScaleGoldenTests {
    @Test func `--size 1280x800 --scale 2 writes a 2560x1600 PNG`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-breakpoint.html").absoluteString
            let out = Self.temporaryDirectory().appendingPathComponent("dense.png")
            defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--size", "1280x800", "--scale", "2", "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let dimensions = try #require(Self.pixelDimensions(ofPNG: Data(contentsOf: out)))
            #expect(dimensions.width == 2560)
            #expect(dimensions.height == 1600)
        }
    }

    @Test func `--rect 0,850,1280,1285 --scale 2 writes a 2560x2570 PNG`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-banded.html").absoluteString
            let out = Self.temporaryDirectory().appendingPathComponent("band.png")
            defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--rect", "0,850,1280,1285", "--scale", "2", "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let dimensions = try #require(Self.pixelDimensions(ofPNG: Data(contentsOf: out)))
            #expect(dimensions.width == 2560)
            #expect(dimensions.height == 2570)
        }
    }

    @Test func `a scale denser than the host exits 5 naming the host's density`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-breakpoint.html").absoluteString
            let out = Self.temporaryDirectory().appendingPathComponent("nope.png")
            defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--scale", "3", "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 5, "stderr: \(result.standardError)")
            #expect(result.standardError.contains("upsample"))
            #expect(FileManager.default.fileExists(atPath: out.path) == false)
        }
    }

    @Test func `--scale 0 is a usage error`() async throws {
        let result = try await GoldenBinary.runOffPool(["shot", "http://127.0.0.1:1/", "--scale", "0"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--scale"))
    }

    @Test func `--scale 4 is a usage error`() async throws {
        let result = try await GoldenBinary.runOffPool(["shot", "http://127.0.0.1:1/", "--scale", "4"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--scale"))
    }

    // MARK: - Helpers

    /// A fresh directory in the temporary directory, created.
    private static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A PNG's pixel dimensions, read from the IHDR chunk.
    private static func pixelDimensions(ofPNG data: Data) -> (width: Int, height: Int)? {
        guard data.count >= 24 else { return nil }
        let bytes = [UInt8](data)
        func integer(at offset: Int) -> Int {
            Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
        }
        return (integer(at: 16), integer(at: 20))
    }
}
