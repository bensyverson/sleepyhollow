import ArgumentParser
import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// `--inject-world` decides which JavaScript world `--inject`'s scripts land
/// in: the tool's isolated world by default, the page's own on request.
///
/// The default is isolated because instrumentation that collides with page
/// script is worse than useless; `page` exists for the cases where the page's
/// own globals *are* the subject.
struct InjectWorldOptionTests {
    private static let noSteps: [ActionStep] = []

    /// Writes `source` to a throwaway `.js` file and returns its path.
    private static func scriptFile(_ source: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".js")
        try source.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    @Test func `--inject alone lands the script in the isolated world`() throws {
        let file: URL = try Self.scriptFile("window.marked = true;")
        defer { try? FileManager.default.removeItem(at: file) }

        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [file.path], injectWorld: nil, waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.scripts.count == 1)
        #expect(options.scripts[0].world == .isolated)
    }

    @Test func `--inject-world page lands the script in the page's own world`() throws {
        let file: URL = try Self.scriptFile("window.marked = true;")
        defer { try? FileManager.default.removeItem(at: file) }

        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [file.path], injectWorld: .page, waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.scripts[0].world == .page)
    }

    @Test func `--inject-world isolated is spellable, and is the default`() throws {
        let file: URL = try Self.scriptFile("window.marked = true;")
        defer { try? FileManager.default.removeItem(at: file) }

        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [file.path], injectWorld: .isolated, waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.scripts[0].world == .isolated)
    }

    @Test func `one --inject-world applies to every injected script`() throws {
        let first: URL = try Self.scriptFile("window.one = 1;")
        let second: URL = try Self.scriptFile("window.two = 2;")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil,
            injectPaths: [first.path, second.path], injectWorld: .page, waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.scripts.count == 2)
        #expect(options.scripts.allSatisfy { $0.world == .page })
    }

    @Test func `every injected script still runs at document start`() throws {
        let file: URL = try Self.scriptFile("window.marked = true;")
        defer { try? FileManager.default.removeItem(at: file) }

        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [file.path], injectWorld: .page, waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.scripts[0].injectAt == .documentStart)
    }

    // MARK: - The flag itself

    @Test func `ArgumentParser parses --inject-world page`() throws {
        let options = try LoadFlagOptions.parse(["--inject-world", "page"])
        #expect(options.injectWorld == .page)
    }

    @Test func `--inject-world is absent until given`() throws {
        let options = try LoadFlagOptions.parse([])
        #expect(options.injectWorld == nil)
    }

    @Test func `a world this tool has no name for is refused`() {
        #expect(throws: (any Error).self) {
            _ = try LoadFlagOptions.parse(["--inject-world", "martian"])
        }
    }

    // MARK: - Against a session

    @Test func `--inject-world shapes a load, so a session refuses it`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--inject-world", "page"])
        #expect(PageExecution.loadShapingFlags(flags) == ["--inject-world"])
        #expect(throws: SleepyError.self) {
            try PageExecution.requireSessionCompatible(flags)
        }
    }
}
