import Foundation
import Testing
import TestSupport

/// `sleepy shot` with a repeated render axis: one invocation, one file per
/// combination, and a JSON index so nothing has to parse a file name.
struct ShotSweepGoldenTests {
    @Test func `two sizes and two themes write four files and one index`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-breakpoint.html").absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let out = directory.appendingPathComponent("header.png")
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--size", "480", "--size", "1280",
                "--theme", "light", "--theme", "dark",
                "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")

            let index = try #require(Self.decodeIndex(result.standardOutput))
            #expect(index.variants.count == 4)
            #expect(index.variants.map(\.file) == [
                directory.appendingPathComponent("header-480-light.png").path,
                directory.appendingPathComponent("header-480-dark.png").path,
                directory.appendingPathComponent("header-1280-light.png").path,
                directory.appendingPathComponent("header-1280-dark.png").path,
            ])
            #expect(index.variants.map(\.width) == [480, 480, 1280, 1280])
            #expect(index.variants.map(\.theme) == ["light", "dark", "light", "dark"])
            #expect(index.variants.allSatisfy { $0.scale == 1 })
            for entry in index.variants {
                let data = try Data(contentsOf: URL(fileURLWithPath: entry.file))
                let dimensions = try #require(Self.pixelDimensions(ofPNG: data))
                #expect(dimensions.width == entry.width)
            }
            // The base path itself is never written — only the suffixed files.
            #expect(FileManager.default.fileExists(atPath: out.path) == false)
        }
    }

    @Test func `a single-valued axis adds no suffix`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-breakpoint.html").absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let out = directory.appendingPathComponent("header.png")
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--size", "480", "--size", "1280", "--theme", "dark",
                "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let index = try #require(Self.decodeIndex(result.standardOutput))
            #expect(index.variants.map(\.file) == [
                directory.appendingPathComponent("header-480.png").path,
                directory.appendingPathComponent("header-1280.png").path,
            ])
            #expect(index.variants.allSatisfy { $0.theme == "dark" })
        }
    }

    @Test func `a scale sweep suffixes every file, one times included`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-breakpoint.html").absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let out = directory.appendingPathComponent("header.png")
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--size", "600", "--scale", "1", "--scale", "2",
                "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let index = try #require(Self.decodeIndex(result.standardOutput))
            #expect(index.variants.map(\.file) == [
                directory.appendingPathComponent("header@1x.png").path,
                directory.appendingPathComponent("header@2x.png").path,
            ])
            let dense = try Data(contentsOf: URL(fileURLWithPath: index.variants[1].file))
            let dimensions = try #require(Self.pixelDimensions(ofPNG: dense))
            #expect(dimensions.width == 1200)
        }
    }

    @Test func `a sweep without --out is a usage error`() async throws {
        let result = try await GoldenBinary.runOffPool([
            "shot", "http://127.0.0.1:1/", "--size", "480", "--size", "1280",
        ])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--out"))
    }

    @Test func `a sweep with --tile is a usage error`() async throws {
        let out = Self.temporaryDirectory().appendingPathComponent("s.png")
        defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }
        let result = try await GoldenBinary.runOffPool([
            "shot", "http://127.0.0.1:1/", "--size", "480", "--size", "1280", "--tile", "--out", out.path,
        ])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--tile"))
    }

    @Test func `another verb refuses a repeated --size`() async throws {
        let result = try await GoldenBinary.runOffPool([
            "dom", "http://127.0.0.1:1/", "--size", "480", "--size", "1280",
        ])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--size"))
        #expect(result.standardError.contains("shot"))
    }

    // MARK: - Helpers

    /// The index shape the command prints, decoded independently of the
    /// library's own type so the wire contract is what is asserted.
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

    /// A fresh directory in the temporary directory, created — a sweep writes
    /// a whole set of siblings, so each run gets its own.
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
