import Foundation
import Testing
import TestSupport

/// `sleepy shot` on CSS 3D it cannot draw faithfully: the PNG is still
/// written and the exit is still 0, but stderr says the shot is flat — once
/// per render, whatever `--quiet` says, and never for 3D-looking CSS the flat
/// paint draws right.
///
/// The fixture is `capture-3d.html`: four flagged cases in row 1, the
/// look-alikes in row 2, one more flagged case below the fold.
struct ShotFlattened3DGoldenTests {
    private static let fixture = "capture-3d.html"

    /// Each flagged case's cell, and the element the note must name.
    static let flaggedCases: [[String]] = [
        ["#case-parent", "div#tilted"],
        ["#case-own", "div#own"],
        ["#case-stack", "div#stack"],
        ["#case-back", "div#back"],
        ["#case-css3d", "div#css3d-scene"],
    ]

    @Test(arguments: flaggedCases)
    func `each 3D case writes the PNG, exits 0 and notes the flat render`(pair: [String]) async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--selector", pair[0], "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(FileManager.default.fileExists(atPath: out.path))
            #expect(
                result.standardError
                    == "sleepy: this shot draws CSS 3D flat — 1 element in it uses perspective, preserve-3d or "
                    + "backface-visibility, which this renderer drops: \(pair[1]). "
                    + "For a faithful render, capture it in Chrome.\n",
            )
        }
    }

    @Test func `the viewport counts every case and lists the first three`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(["shot", url, "--budget", "60000", "--out", out.path])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(result.standardError.contains("4 elements in it use"), "stderr: \(result.standardError)")
            #expect(result.standardError.contains("and 1 more"), "stderr: \(result.standardError)")
            #expect(Self.lines(of: result.standardError).count == 1)
        }
    }

    @Test(arguments: [
        ["--selector", "#flat-2d"],
        ["--selector", "#flat-ortho"],
        ["--selector", "#flat-front"],
        ["--selector", "#flat-hacks"],
        ["--rect", "0,300,1000,250"],
        ["--rect", "0,260,1280,30"],
    ])
    func `a shot whose area holds no flattened 3D says nothing`(region: [String]) async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(
                ["shot", url] + region + ["--budget", "60000", "--out", out.path],
            )
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(result.standardError.isEmpty, "stderr: \(result.standardError)")
        }
    }

    @Test func `--quiet does not silence the caveat`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--selector", "#case-back", "--quiet", "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(result.standardError.contains("draws CSS 3D flat"), "stderr: \(result.standardError)")
        }
    }

    @Test func `a tiled shot notes once, not once per strip`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let out = directory.appendingPathComponent("strips.png")
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--full-page", "--tile", "600", "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let notes = Self.lines(of: result.standardError).filter { $0.contains("draws CSS 3D flat") }
            #expect(notes.count == 1, "stderr: \(result.standardError)")
            #expect(notes.first?.contains("6 elements") == true)
        }
    }

    @Test func `a sweep notes once per render, naming each`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.fixture).absoluteString
            let directory = Self.temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let out = directory.appendingPathComponent("sweep.png")
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--selector", "#case-own", "--size", "1100", "--size", "1280",
                "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let notes = Self.lines(of: result.standardError)
            #expect(notes.count == 2, "stderr: \(result.standardError)")
            #expect(notes.first?.hasPrefix("sleepy: the 1100×800 render draws CSS 3D flat") == true)
            #expect(notes.last?.hasPrefix("sleepy: the 1280×800 render draws CSS 3D flat") == true)
        }
    }

    @Test func `shot --help describes the caveat`() async throws {
        let result = try await GoldenBinary.runOffPool(["shot", "--help"])
        // Help wraps to the terminal, so read it as one run of words.
        let help: String = result.standardOutput.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        #expect(help.contains("draws CSS 3D flat"))
        #expect(help.contains("--quiet does not silence it"))
    }

    private static func lines(of text: String) -> [Substring] {
        text.split(separator: "\n")
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
