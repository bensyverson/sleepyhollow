import ArgumentParser
import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// `--size` and `--theme` are repeatable, because `shot` sweeps them — so
/// every other verb has to say plainly that it renders one page, and the
/// width-only `--size 480` shorthand has to mean the default height.
struct RenderAxisOptionTests {
    private static func flags(_ arguments: [String]) throws -> LoadFlagOptions {
        try LoadFlagOptions.parse(arguments)
    }

    // MARK: - The width-only shorthand

    @Test func `--size 480 means 480 by the default height`() throws {
        #expect(try LoadFlagOptions.viewportSize(parsing: "480") == ViewportSize(width: 480, height: 800))
    }

    @Test func `--size WxH still parses both`() throws {
        #expect(try LoadFlagOptions.viewportSize(parsing: "390x844") == ViewportSize(width: 390, height: 844))
    }

    @Test func `a malformed --size teaches both shapes`() {
        do {
            _ = try LoadFlagOptions.viewportSize(parsing: "wide")
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.nextMove?.contains("1280x800") == true)
            #expect(error.nextMove?.contains("480") == true)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    @Test func `a zero width is refused`() {
        #expect(throws: SleepyError.self) { try LoadFlagOptions.viewportSize(parsing: "0") }
    }

    // MARK: - Repeating an axis

    @Test func `a repeated --size parses into the array`() throws {
        let flags: LoadFlagOptions = try Self.flags(["--size", "480", "--size", "1280"])
        #expect(flags.size == ["480", "1280"])
    }

    @Test func `a repeated --theme parses into the array`() throws {
        let flags: LoadFlagOptions = try Self.flags(["--theme", "light", "--theme", "dark"])
        #expect(flags.theme == [.light, .dark])
    }

    @Test func `a verb that renders one page refuses a repeated --size`() throws {
        let flags: LoadFlagOptions = try Self.flags(["--size", "480", "--size", "1280"])
        do {
            _ = try flags.resolveLoadOptions(steps: [])
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.message.contains("--size"))
            #expect(error.nextMove?.contains("shot") == true)
        }
    }

    @Test func `a verb that renders one page refuses a repeated --theme`() throws {
        let flags: LoadFlagOptions = try Self.flags(["--theme", "light", "--theme", "dark"])
        #expect(throws: SleepyError.self) { try flags.resolveLoadOptions(steps: []) }
    }

    @Test func `a single value on each axis resolves as before`() throws {
        let flags: LoadFlagOptions = try Self.flags(["--size", "390x844", "--theme", "dark"])
        let options: LoadOptions = try flags.resolveLoadOptions(steps: [])
        #expect(options.size == ViewportSize(width: 390, height: 844))
        #expect(options.theme == .dark)
    }

    @Test func `the sweep form supplies the two axes and skips the refusal`() throws {
        let flags: LoadFlagOptions = try Self.flags(["--size", "480", "--size", "1280", "--budget", "5000"])
        let options: LoadOptions = try flags.resolveLoadOptions(
            steps: [],
            size: ViewportSize(width: 1280, height: 800),
            theme: .dark,
        )
        #expect(options.size == ViewportSize(width: 1280, height: 800))
        #expect(options.theme == .dark)
        #expect(options.budget == 5)
    }

    // MARK: - The session refusal still sees them

    @Test func `a repeated --size is still a load-shaping flag a session refuses`() throws {
        let flags: LoadFlagOptions = try Self.flags(["--size", "480", "--size", "1280"])
        #expect(PageExecution.loadShapingFlags(flags) == ["--size"])
        #expect(throws: SleepyError.self) { try PageExecution.requireSessionCompatible(flags) }
    }
}
