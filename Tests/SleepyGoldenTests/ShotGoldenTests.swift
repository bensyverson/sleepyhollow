import Foundation
import Testing
import TestSupport

/// `sleepy shot`'s argument surface as an agent meets it: the aliases a
/// typist reaches for first, and the promise that a mistyped flag is only
/// ever corrected to a flag the invoked verb actually has.
///
/// Pixel behaviour lives in ``CaptureGoldenTests``; this suite is about the
/// parse.
struct ShotGoldenTests {
    // MARK: - Aliases

    @Test func `shot --full is accepted as --full-page`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-tall.html").absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(["shot", url, "--full", "--budget", "60000", "--out", out.path])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            let data = try Data(contentsOf: out)
            let dimensions = try #require(Self.pixelDimensions(ofPNG: data))
            #expect(dimensions.height > 800)
        }
    }

    @Test func `-o is accepted as --out`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-tall.html").absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool(["shot", url, "--budget", "60000", "-o", out.path])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
            #expect(FileManager.default.fileExists(atPath: out.path))
        }
    }

    /// `-o` is declared on the shared `OutOption`, so it is not shot's alone.
    @Test(arguments: ["shot", "pdf", "archive", "dom"])
    func `every artifact verb's help offers -o`(verb: String) async throws {
        let result = try await GoldenBinary.runOffPool([verb, "--help"])
        #expect(result.standardOutput.contains("-o, --out"), "`sleepy \(verb) --help` doesn't offer -o")
    }

    // MARK: - Zero-area elements

    @Test func `shot --element on a display-none element exits 1 and writes nothing`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-zero-area.html").absoluteString
            let out = Self.temporaryFile()
            defer { try? FileManager.default.removeItem(at: out) }
            let result = try await GoldenBinary.runOffPool([
                "shot", url, "--element", "#hidden", "--budget", "60000", "--out", out.path,
            ])
            #expect(result.exitCode == 1)
            #expect(result.standardError.contains("#hidden"))
            #expect(result.standardError.contains("0×0"))
            #expect(!FileManager.default.fileExists(atPath: out.path))
        }
    }

    // MARK: - The did-you-mean suggester

    /// Mistyped flags, each with the verb it was typed against.
    static let mistypedFlags: [[String]] = [
        ["shot", "--full-pag"],
        ["shot", "--elemnt"],
        ["shot", "--sesion"],
        ["shot", "--selectr"],
        ["shot", "--fil"],
        ["query", "--elemnt"],
        ["load", "--full"],
        ["pdf", "--elemnt"],
    ]

    /// A suggestion for a flag the verb does not have is worse than none: it
    /// sends an agent to a second usage error. Whatever the parser proposes
    /// must appear in that verb's own `--help`.
    @Test(arguments: mistypedFlags)
    func `a did-you-mean names only a flag the invoked verb has`(invocation: [String]) async throws {
        let result = try await GoldenBinary.runOffPool(invocation)
        #expect(result.exitCode == 2)
        guard let suggested = Self.suggestedFlag(in: result.standardError) else { return }
        let help = try await GoldenBinary.runOffPool([invocation[0], "--help"])
        let complaint = "`sleepy \(invocation.joined(separator: " "))` suggested '\(suggested)', "
            + "which is not a flag on `sleepy \(invocation[0])`"
        #expect(help.standardOutput.contains(suggested), "\(complaint)")
    }

    /// The flag named in ArgumentParser's `Did you mean '--x'?`, when it made
    /// a suggestion at all.
    static func suggestedFlag(in text: String) -> String? {
        guard let match = text.firstMatch(of: /Did you mean '(-[^']+)'\?/) else { return nil }
        return String(match.1)
    }

    // MARK: - Helpers

    /// A fresh `.png` path in the temporary directory, never created.
    ///
    /// ``CaptureGoldenTests`` keeps its own copy of this and of
    /// ``pixelDimensions(ofPNG:)``; both are private there, and six lines of
    /// duplication beat coupling two golden suites through a shared helper.
    private static func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
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
