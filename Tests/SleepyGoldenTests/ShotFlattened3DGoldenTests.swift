import Foundation
import Testing
import TestSupport

/// `sleepy shot` on CSS 3D, end to end.
///
/// By default a shot renders through the compositor, which draws CSS 3D as a
/// browser does, so it has nothing to warn about: stderr stays empty. When
/// the shot area holds a `<video>` the shot falls back to `takeSnapshot`,
/// and then stderr says so — which renderer, and why — followed by the CSS
/// 3D that renderer draws flat. Both lines are correctness caveats: the PNG
/// is still written, the exit is still 0, and `--quiet` silences neither.
///
/// The fixtures are `capture-3d.html` (four flagged cases in row 1, the
/// look-alikes in row 2, one more below the fold) and
/// `compositor-video.html` (a source-less `<video>` at x 20–260, a
/// perspective tile `#tilted` at x 300–520, a plain swatch at x 560–760).
struct ShotFlattened3DGoldenTests {
    private static let fixture = "capture-3d.html"
    private static let videoFixture = "compositor-video.html"
    private static let videoSize = ["--size", "800x300"]

    static let flaggedCases: [String] = ["#case-parent", "#case-own", "#case-stack", "#case-back", "#case-css3d"]

    @Test(arguments: flaggedCases)
    func `a 3D case renders through the compositor and says nothing`(selector: String) async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--selector", selector, "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(FileManager.default.fileExists(atPath: out.path))
            #expect(result.standardError.isEmpty, "stderr: \(result.standardError)")
        }
    }

    @Test func `a shot over a video falls back, names the renderer, then the flat 3D`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.videoFixture).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(
                ["shot", url] + Self.videoSize + ["--budget", "60000", "--out", out.path],
            )
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(FileManager.default.fileExists(atPath: out.path))
            let lines = Self.lines(of: result.standardError)
            #expect(lines.count == 2, "stderr: \(result.standardError)")
            #expect(
                lines.first == "sleepy: this shot was drawn by takeSnapshot, not the compositor, because its area "
                    + "holds a <video>, which the compositor draws blank. takeSnapshot draws the video "
                    + "but flattens CSS 3D and drops backdrop-filter.",
            )
            #expect(
                lines.last == "sleepy: this shot draws CSS 3D flat — 1 element in it uses perspective, preserve-3d or "
                    + "backface-visibility, which this renderer drops: div#tilted. "
                    + "For a faithful render, capture it in Chrome.",
            )
        }
    }

    @Test(arguments: [
        ["--selector", "#tilted"],
        ["--selector", "#plain"],
        ["--rect", "280,0,520,300"],
    ])
    func `a shot that leaves the video out stays on the compositor and says nothing`(region: [String]) async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.videoFixture).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(
                ["shot", url] + Self.videoSize + region + ["--budget", "60000", "--out", out.path],
            )
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(result.standardError.isEmpty, "stderr: \(result.standardError)")
        }
    }

    @Test func `--quiet silences neither caveat`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.videoFixture).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(
                ["shot", url] + Self.videoSize + ["--quiet", "--budget", "60000", "--out", out.path],
            )
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(result.standardError.contains("drawn by takeSnapshot"), "stderr: \(result.standardError)")
            #expect(result.standardError.contains("draws CSS 3D flat"), "stderr: \(result.standardError)")
        }
    }

    @Test func `a tiled shot notes once, not once per strip, and its index names the renderer`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.videoFixture).absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let out = directory.appendingPathComponent("strips.png")
            let result = try await GoldenBinary.runOffPool(
                ["shot", url] + Self.videoSize + ["--tile", "120", "--budget", "60000", "--out", out.path],
            )
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let lines = Self.lines(of: result.standardError)
            #expect(lines.count(where: { $0.contains("drawn by takeSnapshot") }) == 1, "stderr: \(result.standardError)")
            #expect(lines.count(where: { $0.contains("draws CSS 3D flat") }) == 1, "stderr: \(result.standardError)")
            let index = try JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
            let renderer = index?["renderer"] as? [String: String]
            #expect(renderer == ["name": "snapshot", "fallback": "video"], "stdout: \(result.standardOutput)")
        }
    }

    @Test func `a compositor tile index names the compositor`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let out = directory.appendingPathComponent("strips.png")
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--full-page", "--tile", "600", "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(result.standardError.isEmpty, "stderr: \(result.standardError)")
            let index = try JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
            #expect(index?["renderer"] as? [String: String] == ["name": "compositor"], "stdout: \(result.standardOutput)")
        }
    }

    @Test func `a sweep notes once per render, naming each, and its index names each renderer`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.videoFixture).absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let out = directory.appendingPathComponent("sweep.png")
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--size", "800x300", "--size", "1000x300",
                "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let lines = Self.lines(of: result.standardError)
            #expect(lines.count == 4, "stderr: \(result.standardError)")
            #expect(lines.first?.hasPrefix("sleepy: the 800×300 render was drawn by takeSnapshot") == true)
            #expect(lines.dropFirst().first?.hasPrefix("sleepy: the 800×300 render draws CSS 3D flat") == true)
            #expect(lines.last?.hasPrefix("sleepy: the 1000×300 render draws CSS 3D flat") == true)
            let index = try JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any]
            let variants = index?["variants"] as? [[String: Any]] ?? []
            #expect(variants.map { $0["renderer"] as? [String: String] } == [
                ["name": "snapshot", "fallback": "video"],
                ["name": "snapshot", "fallback": "video"],
            ], "stdout: \(result.standardOutput)")
        }
    }

    @Test func `shot --help describes both renderers and the caveats`() async throws {
        let result = try await GoldenBinary.runOffPool(["shot", "--help"])
        // Help wraps to the terminal, so read it as one run of words.
        let help: String = result.standardOutput.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(help.contains("compositor"))
        #expect(help.contains("takeSnapshot"))
        #expect(help.contains("draws CSS 3D flat"))
        #expect(help.contains("--quiet does not silence"))
    }

    private static func lines(of text: String) -> [String] {
        text.split(separator: "\n").map(String.init)
    }

    private static func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
    }

    private static func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
