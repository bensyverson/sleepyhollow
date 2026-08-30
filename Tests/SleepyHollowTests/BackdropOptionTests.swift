import ArgumentParser
import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// `--transparent`: the CLI spelling of ``LoadOptions/Backdrop/transparent``.
///
/// It lives on the shared loading flags rather than on `shot` alone, because
/// the backdrop is fixed when the web view is built: putting it anywhere else
/// would leave `sleepy open --transparent` with nowhere to say it, and a
/// session's backdrop cannot be changed afterwards.
struct BackdropOptionTests {
    private static let noSteps: [ActionStep] = []

    @Test func `no flag resolves to an opaque backdrop`() throws {
        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [], injectWorld: nil, waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.backdrop == .opaque)
    }

    @Test func `--transparent resolves to a transparent backdrop`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--transparent"])
        let options: LoadOptions = try flags.resolveLoadOptions(steps: Self.noSteps)
        #expect(options.backdrop == .transparent)
    }

    @Test func `--transparent survives the shot sweep's per-render resolve`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--transparent"])
        let options: LoadOptions = try flags.resolveLoadOptions(
            steps: Self.noSteps,
            size: ViewportSize(width: 480, height: 800),
            theme: .dark,
        )
        #expect(options.backdrop == .transparent)
        #expect(options.size == ViewportSize(width: 480, height: 800))
    }

    @Test func `--transparent shapes a load, so a session refuses it`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--transparent"])
        #expect(PageExecution.loadShapingFlags(flags) == ["--transparent"])
        #expect(throws: SleepyError.self) {
            try PageExecution.requireSessionCompatible(flags)
        }
    }

    @Test func `--transparent reaches the session helper`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--transparent"])
        let forwarded: [String] = flags.sessionArguments(steps: Self.noSteps)
        #expect(forwarded.contains("--transparent"))
        let reparsed: LoadFlagOptions = try LoadFlagOptions.parse(forwarded)
        #expect(try reparsed.resolveLoadOptions(steps: Self.noSteps).backdrop == .transparent)
    }

    @Test func `a backdrop survives JSON transport`() throws {
        let options = LoadOptions(backdrop: .transparent, fileAccessRoot: URL(fileURLWithPath: "/tmp/root"))
        let decoded = try JSONDecoder().decode(LoadOptions.self, from: JSONEncoder().encode(options))
        #expect(decoded == options)
        #expect(decoded.backdrop == .transparent)
        #expect(decoded.fileAccessRoot?.path == "/tmp/root")
    }
}
