import Foundation
import Testing
import TestSupport

/// `sleepy shot --sheet`: every render of a sweep in one labeled mosaic, with
/// the full-size files written beside it.
struct ShotSheetGoldenTests {
    @Test func `--size 390 --size 1280 --sheet writes one mosaic and both full-size files`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-breakpoint.html").absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let out = directory.appendingPathComponent("s.png")
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--size", "390", "--size", "1280", "--sheet",
                "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")

            let index = try #require(Self.decodeIndex(result.standardOutput))
            #expect(index.variants.map(\.file) == [
                directory.appendingPathComponent("s-390.png").path,
                directory.appendingPathComponent("s-1280.png").path,
            ])
            for entry in index.variants {
                let data = try Data(contentsOf: URL(fileURLWithPath: entry.file))
                let dimensions = try #require(Self.pixelDimensions(ofPNG: data))
                #expect(dimensions.width == entry.width)
            }

            // The mosaic itself is the --out path, and holds both cells.
            let sheet = try Data(contentsOf: out)
            let mosaic = try #require(Self.pixelDimensions(ofPNG: sheet))
            #expect(max(mosaic.width, mosaic.height) <= 2000)
            #expect(mosaic.width != 390)
            #expect(mosaic.width != 1280)
        }
    }

    @Test func `--sheet with --tile is a usage error`() async throws {
        let out = Self.temporaryDirectory().appendingPathComponent("s.png")
        defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
        let result = try await GoldenBinary.runOffPool([
            "shot", "http://127.0.0.1:1/", "--size", "390", "--size", "1280",
            "--sheet", "--tile", "--out", out.path,
        ])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--tile"))
    }

    @Test func `--sheet with nothing to sweep is a usage error`() async throws {
        let out = Self.temporaryDirectory().appendingPathComponent("s.png")
        defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
        let result = try await GoldenBinary.runOffPool([
            "shot", "http://127.0.0.1:1/", "--sheet", "--out", out.path,
        ])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--sheet"))
    }

    // MARK: - Helpers

    private struct Index: Decodable {
        struct Variant: Decodable {
            let file: String
            let width: Int
            let height: Int
            let scale: Int
            let theme: String
        }

        let variants: [Variant]
    }

    private static func decodeIndex(_ text: String) -> Index? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Index.self, from: data)
    }

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
