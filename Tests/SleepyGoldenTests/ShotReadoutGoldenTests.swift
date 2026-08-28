import Foundation
import Testing
import TestSupport

/// `sleepy shot --max-size` and `--tile` as an agent runs them: one capped
/// overview, or a numbered set of strips plus the JSON index that names the
/// document rows each strip holds.
///
/// The fixture is `capture-banded.html` — 1280×12982, the shape of the
/// report page that motivated both flags.
struct ShotReadoutGoldenTests {
    // MARK: - --max-size

    @Test func `--full-page --max-size 2000 writes one PNG with a longest side of 2000`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-banded.html").absoluteString
            let out = Self.temporaryDirectory().appendingPathComponent("over.png")
            defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--full-page", "--max-size", "2000", "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let dimensions = try #require(try Self.pixelDimensions(ofPNG: Data(contentsOf: out)))
            #expect(max(dimensions.width, dimensions.height) == 2000)
            #expect(dimensions.width == 197)
        }
    }

    @Test func `--max-size 0 is a usage error`() async throws {
        let result = try await GoldenBinary.runOffPool(["shot", "http://127.0.0.1:1/", "--max-size", "0"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--max-size"))
    }

    // MARK: - --tile

    @Test func `--tile writes numbered strips whose adjacent rows share 40 CSS px`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-banded.html").absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let out = directory.appendingPathComponent("strips.png")
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--full-page", "--max-size", "2000", "--tile",
                "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")

            let index = try #require(Self.decodeIndex(result.standardOutput))
            #expect(index.tiles.count == 7)
            for (previous, next) in zip(index.tiles, index.tiles.dropFirst()) {
                #expect(previous.y + previous.height - next.y == 40)
            }
            #expect(index.tiles[0].y == 0)
            #expect(index.tiles[0].height == 2000)

            // Every named file exists, is a PNG, and is as tall as it claims.
            for tile in index.tiles {
                let data = try Data(contentsOf: URL(fileURLWithPath: tile.file))
                let dimensions = try #require(Self.pixelDimensions(ofPNG: data))
                #expect(dimensions.height == Int(tile.height * tile.scale))
            }
            #expect(index.tiles[0].file == out.deletingLastPathComponent()
                .appendingPathComponent("strips-01.png").path)
            #expect(FileManager.default.fileExists(atPath: out.path) == false)
        }
    }

    @Test func `an index entry pastes straight back into --rect`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-banded.html").absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let out = directory.appendingPathComponent("strips.png")
            let tiled = try await GoldenBinary.runOffPool([
                "shot", url, "--full-page", "--tile", "3000", "--budget", "60000", "--out", out.path,
            ])
            #expect(tiled.exitCode == 0, "stderr: \(tiled.standardError)")
            let index = try #require(Self.decodeIndex(tiled.standardOutput))
            let entry = index.tiles[1]

            let pasted = directory.appendingPathComponent("pasted.png")
            let rect = "\(entry.x),\(entry.y),\(entry.width),\(entry.height)"
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--rect", rect, "--budget", "60000", "--out", pasted.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let strip = try #require(try Self.pixelDimensions(ofPNG: Data(contentsOf: URL(fileURLWithPath: entry.file))))
            let again = try #require(try Self.pixelDimensions(ofPNG: Data(contentsOf: pasted)))
            #expect(strip.width == again.width)
            #expect(strip.height == again.height)
        }
    }

    @Test func `--tile without --out is a usage error`() async throws {
        let result = try await GoldenBinary.runOffPool(["shot", "http://127.0.0.1:1/", "--tile"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--out"))
    }

    @Test func `a tile height no taller than the overlap is a usage error`() async throws {
        let out = Self.temporaryDirectory().appendingPathComponent("strips.png")
        defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
        let result = try await GoldenBinary.runOffPool([
            "shot", "http://127.0.0.1:1/", "--tile", "20", "--out", out.path,
        ])
        #expect(result.exitCode == 2)
    }

    // MARK: - Helpers

    /// The JSON index shape the command prints, decoded independently of the
    /// library's own type so the wire contract is what is asserted.
    private struct Index: Decodable {
        struct Tile: Decodable {
            let file: String
            let x: Double
            let y: Double
            let width: Double
            let height: Double
            let scale: Double
        }

        let tiles: [Tile]
    }

    private static func decodeIndex(_ text: String) -> Index? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Index.self, from: data)
    }

    /// A fresh directory in the temporary directory, created — `--tile`
    /// writes a whole set of siblings, so each run gets its own.
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
