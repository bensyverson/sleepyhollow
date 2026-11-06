import ArgumentParser
import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// `--viewport` is the name people reach for, so it is accepted wherever
/// `--size` is. Every loading verb takes `--size` through the one
/// ``LoadFlagOptions`` group, so the alias lands everywhere or nowhere.
struct ViewportAliasOptionTests {
    @Test func `--viewport parses into the same value as --size`() throws {
        let aliased: LoadFlagOptions = try LoadFlagOptions.parse(["--viewport", "390x844"])
        let canonical: LoadFlagOptions = try LoadFlagOptions.parse(["--size", "390x844"])
        #expect(aliased.size == canonical.size)
        #expect(try aliased.resolveLoadOptions(steps: []).size == ViewportSize(width: 390, height: 844))
    }

    @Test func `--viewport takes the width-only shorthand`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--viewport", "480"])
        #expect(try flags.resolveLoadOptions(steps: []).size == ViewportSize(width: 480, height: 800))
    }

    @Test func `--viewport repeats and mixes with --size, so shot can sweep it`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--viewport", "480", "--size", "1280"])
        #expect(flags.size == ["480", "1280"])
    }

    @Test func `a verb that renders one page refuses a repeated --viewport`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--viewport", "480", "--viewport", "1280"])
        #expect(throws: SleepyError.self) { try flags.resolveLoadOptions(steps: []) }
    }

    @Test func `a session refuses --viewport as the load-shaping flag it is`() throws {
        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--viewport", "480"])
        #expect(PageExecution.loadShapingFlags(flags) == ["--size"])
    }

    @Test func `the action-step scan skips the value of --viewport`() throws {
        let steps: [ActionStep] = try ActionStepParser.parse(["--viewport", "--click", "--click", "#go"])
        #expect(steps == [.click(selector: "#go")])
    }
}
