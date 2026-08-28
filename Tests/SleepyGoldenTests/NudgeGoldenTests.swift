import Foundation
import Testing
import TestSupport

/// Success nudges as an agent meets them: one advisory line on stderr when a
/// *successful* call had a cheaper path, never on stdout, never more than one,
/// never after a failure, and never at all under `--quiet`.
///
/// `--budget 60000` throughout: see ``CaptureGoldenTests`` — WebKit contention
/// across parallel golden subprocesses pushes loads past the 30-second default.
struct NudgeGoldenTests {
    /// The 1280×12982 report-shaped fixture both readout flags exist for.
    private static let tallFixture: String = "capture-banded.html"

    /// Every verb an agent can type that must accept `--quiet`, including the
    /// nested ones. The hidden `_host` is absent: nobody should ever type it.
    static let verbsAcceptingQuiet: [[String]] = [
        ["load"], ["shot"], ["pdf"], ["archive"],
        ["dom"], ["query"], ["style"], ["find"], ["ax"],
        ["contrast"], ["overflow"], ["console"], ["wire"], ["eval"],
        ["click"], ["fill"], ["submit"],
        ["open"], ["close"], ["recipes"], ["doctor"],
        ["sessions", "list"], ["sessions", "prune"], ["sessions", "close"],
        ["jars", "list"], ["jars", "clear"], ["jars", "rm"],
        ["cookies", "get"], ["cookies", "set"],
    ]

    // MARK: - The tall capture

    @Test func `a full-page capture past the vision budget prints one tip naming --max-size and --tile`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.tallFixture).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }

            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--full-page", "--budget", "60000", "--out", out.path,
            ])

            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(result.standardOutput.isEmpty)
            #expect(Self.lines(of: result.standardError).count == 1, "stderr: \(result.standardError)")
            #expect(result.standardError.contains("--max-size"))
            #expect(result.standardError.contains("--tile"))
            #expect(result.standardError.contains("12,982"))
        }
    }

    @Test func `--quiet silences the tip`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.tallFixture).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }

            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--full-page", "--budget", "60000", "--out", out.path, "--quiet",
            ])

            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(result.standardError.isEmpty)
        }
    }

    @Test func `--max-size already answers the tip, so none is printed`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.tallFixture).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }

            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--full-page", "--max-size", "2000", "--budget", "60000", "--out", out.path,
            ])

            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(!result.standardError.contains("Tip:"))
        }
    }

    // MARK: - The baseline tip

    @Test func `a shot with no --out names peep compare, and stdout is still the PNG`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(FixturePage.staticText.fileName).absoluteString

            let result = try await GoldenBinary.runOffPool(["shot", url, "--budget", "60000"])

            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(result.standardOutput.hasPrefix("\u{FFFD}PNG\r\n"), "stdout is not a PNG")
            #expect(Self.lines(of: result.standardError).count == 1, "stderr: \(result.standardError)")
            #expect(result.standardError.contains("peep compare"))
        }
    }

    @Test func `a tall capture with no --out still gets only the readout tip`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(Self.tallFixture).absoluteString

            let result = try await GoldenBinary.runOffPool(["shot", url, "--full-page", "--budget", "60000"])

            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(Self.lines(of: result.standardError).count == 1, "stderr: \(result.standardError)")
            #expect(result.standardError.contains("--max-size"))
            #expect(!result.standardError.contains("peep compare"))
        }
    }

    // MARK: - Never after a failure

    @Test func `a shot whose selector matched nothing prints no tip`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent(FixturePage.staticText.fileName).absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out.deletingLastPathComponent()) }

            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--selector", "#does-not-exist", "--budget", "60000", "--out", out.path,
            ])

            #expect(result.exitCode == 1)
            #expect(!result.standardError.contains("Tip:"))
        }
    }

    // MARK: - --quiet is global

    @Test(arguments: verbsAcceptingQuiet)
    func `every verb's help offers --quiet`(command: [String]) async throws {
        let result = try await GoldenBinary.runOffPool(command + ["--help"])
        #expect(result.exitCode == 0)
        #expect(
            result.standardOutput.contains("--quiet"),
            "`sleepy \(command.joined(separator: " ")) --help` doesn't offer --quiet",
        )
    }

    // MARK: - Helpers

    private static func lines(of text: String) -> [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: true)
    }

    /// A path inside a fresh temporary directory, so a test can delete the
    /// whole directory whatever the run wrote into it.
    private static func temporaryFile() -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("shot.png")
    }
}
