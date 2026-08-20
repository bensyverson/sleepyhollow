import Testing

/// The scaffold's own golden coverage: the primer, `--help`, and a rejected
/// flag. Every verb-family suite that lands after this one reuses
/// `GoldenBinary` to drive the same built executable.
struct ScaffoldGoldenTests {
    @Test func `bare invocation prints the primer`() throws {
        let result = try GoldenBinary.run([])
        #expect(result.exitCode == 0)
        #expect(result.standardOutput == Self.expectedPrimer)
        #expect(result.standardError.isEmpty)
    }

    @Test func `--help exits zero`() throws {
        let result = try GoldenBinary.run(["--help"])
        #expect(result.exitCode == 0)
        #expect(!result.standardOutput.isEmpty)
    }

    @Test func `an unknown flag exits 2 with teaching text on stderr`() throws {
        let result = try GoldenBinary.run(["--this-flag-does-not-exist"])
        #expect(result.exitCode == 2)
        #expect(!result.standardError.isEmpty)
        #expect(result.standardError.contains("--help"))
        #expect(result.standardOutput.isEmpty)
    }

    /// Byte-stable copy of `SleepyCommand.primer` (plus the trailing
    /// newline `print` adds) — the executable target can't be imported, so
    /// this is the golden fixture itself; keep it in sync by hand.
    private static let expectedPrimer = """
    SleepyHollow is a headless WebKit browser for agents: it renders real pages with the system's WebKit engine and exposes them — pixels, DOM, computed style, the accessibility tree, the wire log — as verbs that emit structured text and exit codes that mean something.

    Common invocations:
      sleepy load <url>                  load a page, report status and console errors
      sleepy shot <url> --out shot.png   screenshot a page
      sleepy ax --session <name>         read a live session's accessibility tree

    Help: `sleepy <verb> --help` for a verb's flags and examples, `sleepy --help` to list every verb.

    """
}
