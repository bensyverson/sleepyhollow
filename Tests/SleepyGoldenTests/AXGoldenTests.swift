import Foundation
import SleepyHollow
import Testing
import TestSupport

/// `sleepy ax` end to end: the outline default, the JSON tree, and the
/// byte-stability an agent's diff depends on.
struct AXGoldenTests {
    @Test func `the default outline answers the flagship query and exits 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("form.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["ax", url])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("button \"Publish\" (disabled)\n"))
            #expect(result.standardError.isEmpty)
        }
    }

    @Test func `--format json emits the same tree the outline renders`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("form.html").absoluteString
            let outline = try await GoldenBinary.runOffPool(["ax", url])
            let json = try await GoldenBinary.runOffPool(["ax", url, "--format", "json"])
            #expect(json.exitCode == 0)
            #expect(json.standardError.isEmpty)

            let tree = try JSONDecoder().decode(AXNode.self, from: Data(json.standardOutput.utf8))
            #expect(AXOutline.render(tree) == outline.standardOutput)
        }
    }

    @Test func `the outline is materially terser than the JSON tree`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("ax-structure.html").absoluteString
            let outline = try await GoldenBinary.runOffPool(["ax", url])
            let json = try await GoldenBinary.runOffPool(["ax", url, "--format", "json"])
            #expect(outline.standardOutput.utf8.count * 3 < json.standardOutput.utf8.count)
        }
    }

    @Test func `two runs of the same page emit the same bytes`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("ax-states.html").absoluteString
            for arguments in [["ax", url], ["ax", url, "--format", "json"]] {
                let first = try await GoldenBinary.runOffPool(arguments)
                let second = try await GoldenBinary.runOffPool(arguments)
                #expect(first.exitCode == 0)
                #expect(first.standardOutput == second.standardOutput)
                #expect(!first.standardOutput.isEmpty)
            }
        }
    }

    @Test func `--out writes the outline to a file instead of standard output`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("form.html").absoluteString
            let file = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("sleepy-ax-\(UUID().uuidString).txt")
            let result = try await GoldenBinary.runOffPool(["ax", url, "--out", file.path])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.isEmpty)
            let written = try String(contentsOf: file, encoding: .utf8)
            #expect(written.contains("button \"Publish\" (disabled)"))
            try? FileManager.default.removeItem(at: file)
        }
    }

    @Test func `an unsupported format is a teaching usage error`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("form.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["ax", url, "--format", "html"])
            #expect(result.exitCode == 2)
            #expect(result.standardError.contains("json"))
            #expect(result.standardError.contains("outline"))
        }
    }

    @Test func `--session with no such session is a teaching environment error`() async throws {
        let result = try await GoldenBinary.runOffPool(["ax", "--session", "nope"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }
}
