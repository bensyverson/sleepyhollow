import Testing

/// The scaffold's own golden coverage: the primer, `--help`, and a rejected
/// flag. Every verb-family suite that lands after this one reuses
/// `GoldenBinary` to drive the same built executable.
struct ScaffoldGoldenTests {
    @Test func `bare invocation prints the primer`() async throws {
        let result = try await GoldenBinary.runOffPool([])
        #expect(result.exitCode == 0)
        #expect(result.standardOutput == Self.expectedPrimer)
        #expect(result.standardError.isEmpty)
    }

    @Test func `--help exits zero`() async throws {
        let result = try await GoldenBinary.runOffPool(["--help"])
        #expect(result.exitCode == 0)
        #expect(!result.standardOutput.isEmpty)
    }

    @Test func `an unknown flag exits 2 with teaching text on stderr`() async throws {
        let result = try await GoldenBinary.runOffPool(["--this-flag-does-not-exist"])
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
      sleepy load <url>                       load a page once; report status, console errors, dialogs
      sleepy ax <url> | grep 'button "Save"'  read the page the way assistive technology does
      sleepy open <url> --name app            keep one page alive, then act on it: `sleepy click --session app --selector '#save'`

    Every page verb takes a URL (a fresh page that exits with the command) or --session <name> (a live one).
    Help: `sleepy <verb> --help` for a verb's flags, examples and exit codes; `sleepy --help` to list every verb; `sleepy help recipes` to find a verb by goal instead of by name; `sleepy doctor` when a call failed and you don't know why.

    """
}
