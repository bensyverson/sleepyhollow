import Foundation
import Testing
import TestSupport

/// `sleepy console` and `sleepy wire` end to end, as an agent invokes them.
struct ObserveGoldenTests {
    @Test func `console reports the page's log as JSON and exits 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("observe-console.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["console", url])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("\"level\" : \"warn\""))
            #expect(result.standardOutput.contains("a warn line"))
            #expect(result.standardOutput.contains("\"origin\" : \"unhandledRejection\""))
            #expect(result.standardError.isEmpty)
        }
    }

    @Test func `console --format text prints one line per message`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("observe-console.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["console", url, "--format", "text"])
            #expect(result.exitCode == 0)
            let lines = result.standardOutput.split(separator: "\n").map(String.init)
            #expect(lines.contains { $0.hasPrefix("debug") && $0.hasSuffix("a debug line") })
            #expect(lines.contains { $0.hasPrefix("error") && $0.hasSuffix("an error line") })
            #expect(lines.contains { $0.hasPrefix("rejection") })
        }
    }

    @Test func `wire reports both layers as JSON, with the fixture's POST`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("fetch.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["wire", url])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("\"inventory\""))
            #expect(result.standardOutput.contains("\"fetches\""))
            #expect(result.standardOutput.contains("\"method\" : \"POST\""))
            #expect(result.standardOutput.contains("field=starlight"))
            #expect(result.standardError.isEmpty)
        }
    }

    @Test func `wire --format text prints both sections`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("fetch.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["wire", url, "--format", "text"])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("inventory ("))
            #expect(result.standardOutput.contains("fetches (2)"))
            #expect(result.standardOutput.contains("POST"))
        }
    }

    @Test func `--out writes the wire log to a file instead of stdout`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let destination = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("observe-wire-\(UUID().uuidString).json")
            defer { try? FileManager.default.removeItem(at: destination) }
            let url = baseURL.appendingPathComponent("fetch.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["wire", url, "--out", destination.path])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.isEmpty)
            let written = try String(contentsOf: destination, encoding: .utf8)
            #expect(written.contains("\"fetches\""))
        }
    }

    @Test func `--inject installs a user script before the document starts`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            // The probe records `document.readyState` at injection time, then —
            // once there is a DOM — hands the value to the page world through a
            // script element, where the console capture can see it. "loading"
            // proves the user script ran before the document was parsed.
            let probe = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("observe-probe-\(UUID().uuidString).js")
            defer { try? FileManager.default.removeItem(at: probe) }
            let source = """
            var readyStateAtInjection = document.readyState;
            document.addEventListener('DOMContentLoaded', function () {
              var element = document.createElement('script');
              element.textContent = "console.warn('injected-at:" + readyStateAtInjection + "');";
              (document.head || document.documentElement).appendChild(element);
            });
            """
            try source.write(to: probe, atomically: true, encoding: .utf8)

            let url = baseURL.appendingPathComponent("static.html").absoluteString
            let result = try await GoldenBinary.runOffPool(["console", url, "--format", "text", "--inject", probe.path])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.contains("injected-at:loading"))
        }
    }

    @Test func `console --session teaches that sessions are pending`() async throws {
        let result = try await GoldenBinary.runOffPool(["console", "--session", "nope"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }

    @Test func `wire --session teaches that sessions are pending`() async throws {
        let result = try await GoldenBinary.runOffPool(["wire", "--session", "nope"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }
}
