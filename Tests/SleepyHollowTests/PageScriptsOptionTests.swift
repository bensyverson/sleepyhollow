import ArgumentParser
import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// `--no-js`: the CLI spelling of ``LoadOptions/PageScripts/disabled``.
///
/// A shared loading flag, like `--transparent`, because the setting is fixed
/// when the web view is built: `sleepy open --no-js` has to be able to say it,
/// and a session cannot change it afterwards.
struct PageScriptsOptionTests {
    private static let noSteps: [ActionStep] = []

    @Test func `no flag leaves the page's scripts on`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse([])
        #expect(try flags.resolveLoadOptions(steps: Self.noSteps).pageScripts == .enabled)
    }

    @Test func `--no-js turns the page's scripts off`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--no-js"])
        #expect(try flags.resolveLoadOptions(steps: Self.noSteps).pageScripts == .disabled)
    }

    @Test func `--no-js survives the shot sweep's per-render resolve`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--no-js"])
        let options: LoadOptions = try flags.resolveLoadOptions(
            steps: Self.noSteps,
            size: ViewportSize(width: 480, height: 800),
            theme: .dark,
        )
        #expect(options.pageScripts == .disabled)
    }

    @Test func `--no-js shapes a load, so a session refuses it`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--no-js"])
        #expect(PageExecution.loadShapingFlags(flags) == ["--no-js"])
        #expect(throws: SleepyError.self) {
            try PageExecution.requireSessionCompatible(flags)
        }
    }

    @Test func `--no-js reaches the session helper`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--no-js"])
        let forwarded: [String] = flags.sessionArguments(steps: Self.noSteps)
        #expect(forwarded.contains("--no-js"))
        let reparsed: LoadFlagOptions = try LoadFlagOptions.parse(forwarded)
        #expect(try reparsed.resolveLoadOptions(steps: Self.noSteps).pageScripts == .disabled)
    }

    @Test func `--no-js refuses a page-world injection that could never run`() throws {
        let script: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-no-js-\(UUID().uuidString).js")
        try Data("window.injected = true;".utf8).write(to: script)
        defer { try? FileManager.default.removeItem(at: script) }
        let flags: LoadFlagOptions = try LoadFlagOptions.parse([
            "--no-js", "--inject", script.path, "--inject-world", "page",
        ])
        let error = try #require(throws: SleepyError.self) {
            try flags.resolveLoadOptions(steps: Self.noSteps)
        }
        #expect(error.kind == .usage)
        #expect(error.nextMove?.contains("--inject-world isolated") == true)
    }

    @Test func `--no-js keeps an isolated-world injection`() throws {
        let script: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-no-js-\(UUID().uuidString).js")
        try Data("window.injected = true;".utf8).write(to: script)
        defer { try? FileManager.default.removeItem(at: script) }
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--no-js", "--inject", script.path])
        let options: LoadOptions = try flags.resolveLoadOptions(steps: Self.noSteps)
        #expect(options.scripts.map(\.world) == [.isolated])
    }
}
