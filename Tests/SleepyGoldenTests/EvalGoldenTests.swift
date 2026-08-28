import Foundation
import Testing
import TestSupport

/// `sleepy eval` end to end: JSON on stdout, the world flag and its help,
/// `--js`/`--file` script sources, a bare expression answered rather than
/// nulled, page failures as teaching errors, and `false` as the
/// clean-negative exit.
///
/// `.serialized` and `--budget 60000`: see ``CaptureGoldenTests`` — WebKit
/// contention across parallel golden subprocesses pushes loads past the
/// 30-second default.
@Suite(.serialized)
struct EvalGoldenTests {
    private func url(_ page: String, _ baseURL: URL) -> String {
        baseURL.appendingPathComponent(page).absoluteString
    }

    @Test func `a result is printed as JSON, exit 0`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL), "--js", "return 1 + 1;", "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "2")
        }
    }

    @Test func `await and --args compose into one answer`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL),
                "--js", "return await Promise.resolve(factor * 6);",
                "--args", #"{"factor": 7}"#,
                "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "42")
        }
    }

    @Test func `the page world is the default and --world isolated opts out of it`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let page = url("eval-world.html", baseURL)
            let shared = try await GoldenBinary.runOffPool([
                "eval", page, "--js", "return window.sleepyPageValue ?? null;", "--budget", "60000",
            ])
            #expect(shared.exitCode == 0)
            #expect(shared.standardOutput.contains("page-world"))

            let isolated = try await GoldenBinary.runOffPool([
                "eval", page, "--js", "return window.sleepyPageValue ?? null;",
                "--world", "isolated", "--budget", "60000",
            ])
            #expect(isolated.exitCode == 0)
            #expect(isolated.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "null")
        }
    }

    @Test func `an upgraded custom element's method answers in the default world`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let page = url("eval-custom-element.html", baseURL)
            let probe = "typeof document.getElementById('chip').reportStatus"
            let byDefault = try await GoldenBinary.runOffPool([
                "eval", page, "--js", probe, "--format", "text", "--budget", "60000",
            ])
            #expect(byDefault.exitCode == 0)
            #expect(byDefault.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "function")

            let isolated = try await GoldenBinary.runOffPool([
                "eval", page, "--js", probe, "--world", "isolated",
                "--format", "text", "--budget", "60000",
            ])
            #expect(isolated.exitCode == 0)
            #expect(isolated.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "undefined")
        }
    }

    @Test func `--help states what an isolated world does not carry across`() async throws {
        let help = try await GoldenBinary.runOffPool(["eval", "--help"])
        #expect(help.exitCode == 0)
        #expect(help.standardOutput.contains("--world"))
        #expect(help.standardOutput.contains("custom element"))
        #expect(help.standardOutput.contains("customElements.get()"))
    }

    @Test func `a bare expression is answered, not turned into null`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL), "--js", "document.title",
                "--format", "text", "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            let printed = result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(!printed.isEmpty)
            #expect(printed != "null")
        }
    }

    @Test func `a call with a trailing semicolon runs and answers its value`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let clicked = try await GoldenBinary.runOffPool([
                "eval", url("form.html", baseURL),
                "--js", "document.querySelector('#publish').click();", "--budget", "60000",
            ])
            #expect(clicked.exitCode == 0)
            #expect(clicked.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "null")

            let answered = try await GoldenBinary.runOffPool([
                "eval", url("eval-custom-element.html", baseURL),
                "--js", "document.getElementById('chip').reportStatus();",
                "--format", "text", "--budget", "60000",
            ])
            #expect(answered.exitCode == 0)
            #expect(answered.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "ready")
        }
    }

    @Test func `a script that cannot be wrapped exits 2 naming the fix`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL), "--js", "const n = 1; document.title;", "--budget", "60000",
            ])
            #expect(result.exitCode == 2)
            #expect(result.standardError.contains("return"))
        }
    }

    @Test func `--file reads a multi-line script from a path`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let script = FileManager.default.temporaryDirectory
                .appendingPathComponent("eval-golden-\(UUID().uuidString).js")
            try """
            const title = document.title;
            return title.length > 0;
            """.write(to: script, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: script) }

            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL), "--file", script.path, "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "true")
        }
    }

    @Test func `--file - reads the script from standard input`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool(
                ["eval", url("static.html", baseURL), "--file", "-", "--format", "text", "--budget", "60000"],
                standardInput: Data("return document.title;\n".utf8),
            )
            #expect(result.exitCode == 0)
            #expect(!result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test func `--js and --file together, or neither, is a usage error`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let page = url("static.html", baseURL)
            let both = try await GoldenBinary.runOffPool([
                "eval", page, "--js", "return 1;", "--file", "/nonexistent.js", "--budget", "60000",
            ])
            #expect(both.exitCode == 2)
            #expect(both.standardError.contains("--file"))

            let neither = try await GoldenBinary.runOffPool(["eval", page, "--budget", "60000"])
            #expect(neither.exitCode == 2)
            #expect(neither.standardError.contains("--js"))
        }
    }

    @Test func `--format text unwraps a string result`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL),
                "--js", "return document.title;", "--format", "text", "--budget", "60000",
            ])
            #expect(result.exitCode == 0)
            #expect(!result.standardOutput.contains("\""))
        }
    }

    @Test func `a false result is a clean negative`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL),
                "--js", "return document.querySelectorAll('h9').length > 0;", "--budget", "60000",
            ])
            #expect(result.exitCode == 1)
            #expect(result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) == "false")
        }
    }

    @Test func `a page error exits 2 with the page's own message, not a stack trace`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let result = try await GoldenBinary.runOffPool([
                "eval", url("static.html", baseURL),
                "--js", "return (() => { throw new Error('boom'); })();", "--budget", "60000",
            ])
            #expect(result.exitCode == 2)
            #expect(result.standardError.contains("boom"))
            #expect(!result.standardError.contains("Error Domain="))
        }
    }

    @Test func `--session with no such session is a teaching environment error`() async throws {
        let result = try await GoldenBinary.runOffPool(["eval", "--session", "nope", "--js", "return 1;"])
        #expect(result.exitCode == 5)
        #expect(result.standardError.contains("session"))
    }
}
