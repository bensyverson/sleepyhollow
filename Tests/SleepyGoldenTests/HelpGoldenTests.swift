import Foundation
import Testing

/// The CLI as a feature: a bare `sleepy` primes, every subcommand teaches
/// itself with an example, and a mistyped invocation says what was wrong.
///
/// These assert *shape*, never the exact bytes of a help screen — help text
/// must stay editable, so the pins are "there is an Examples: block" and
/// "the exit codes are stated", not a golden transcript.
struct HelpGoldenTests {
    /// Every subcommand an agent can type, including the nested ones. The
    /// hidden `_host` is deliberately absent: nobody should ever type it.
    static let visibleSubcommands: [[String]] = [
        ["load"], ["shot"], ["pdf"], ["archive"],
        ["dom"], ["query"], ["style"], ["find"], ["ax"],
        ["console"], ["wire"], ["eval"],
        ["click"], ["fill"], ["submit"],
        ["open"], ["close"],
        ["sessions"], ["sessions", "list"], ["sessions", "prune"], ["sessions", "close"],
        ["jars"], ["jars", "list"], ["jars", "clear"], ["jars", "rm"],
        ["cookies"], ["cookies", "get"], ["cookies", "set"],
    ]

    /// The commands whose help must state which exit codes they produce:
    /// every verb that can fail as something other than a usage error.
    static let commandsStatingExitCodes: [[String]] = [
        ["load"], ["shot"], ["pdf"], ["archive"],
        ["dom"], ["query"], ["style"], ["find"], ["ax"],
        ["console"], ["wire"], ["eval"],
        ["click"], ["fill"], ["submit"],
        ["open"], ["close"],
        ["sessions", "close"],
        ["jars", "clear"], ["jars", "rm"],
        ["cookies", "get"], ["cookies", "set"],
    ]

    @Test(arguments: visibleSubcommands)
    func `every subcommand's help carries at least one example`(command: [String]) async throws {
        let result = try await GoldenBinary.runOffPool(command + ["--help"])
        #expect(result.exitCode == 0)
        #expect(
            result.standardOutput.contains("Examples:"),
            "`sleepy \(command.joined(separator: " ")) --help` has no Examples: block",
        )
        #expect(
            result.standardOutput.contains("sleepy \(command.joined(separator: " "))"),
            "the examples don't show the verb being invoked",
        )
    }

    @Test(arguments: commandsStatingExitCodes)
    func `every failing verb's help states its exit codes`(command: [String]) async throws {
        let result = try await GoldenBinary.runOffPool(command + ["--help"])
        #expect(
            result.standardOutput.contains("Exit codes:"),
            "`sleepy \(command.joined(separator: " ")) --help` doesn't state its exit codes",
        )
    }

    /// ArgumentParser re-wraps a discussion at the terminal width, so a phrase
    /// can land across two lines. Collapse the whitespace before matching.
    private static func unwrapped(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The verbs whose exit 1 still prints its answer say so, because an agent
    /// that treats exit 1 as "no output" would throw the facts away.
    @Test(arguments: [["query"], ["style"], ["find"], ["eval"]])
    func `a verb whose clean negative still prints says so`(command: [String]) async throws {
        let result = try await GoldenBinary.runOffPool(command + ["--help"])
        #expect(Self.unwrapped(result.standardOutput).contains("printed on stdout"))
    }

    /// And the one whose exit 1 prints nothing says *that*, so the two shapes
    /// are told apart in the only place an agent will look.
    @Test func `shot's clean negative says no file is written`() async throws {
        let result = try await GoldenBinary.runOffPool(["shot", "--help"])
        #expect(Self.unwrapped(result.standardOutput).contains("no PNG written"))
    }

    // MARK: - The primer

    @Test func `a bare sleepy prints the primer and exits 0`() async throws {
        let result = try await GoldenBinary.runOffPool([])
        #expect(result.exitCode == 0)
        #expect(result.standardError.isEmpty)
        #expect(result.standardOutput.contains("headless WebKit browser"))
    }

    @Test func `the primer shows the three most common invocations`() async throws {
        let result = try await GoldenBinary.runOffPool([])
        let primer: String = result.standardOutput
        #expect(primer.contains("sleepy load "))
        #expect(primer.contains("sleepy ax "))
        #expect(primer.contains("--session"))
    }

    /// The primer is where an agent learns the sibling tool exists at all;
    /// without it, `peep compare` is a name nobody in this CLI ever says.
    @Test func `the primer names peep compare for baselines`() async throws {
        let result = try await GoldenBinary.runOffPool([])
        #expect(result.standardOutput.contains("peep compare"))
    }

    @Test func `the primer says where help lives`() async throws {
        let result = try await GoldenBinary.runOffPool([])
        #expect(result.standardOutput.contains("sleepy <verb> --help"))
        #expect(result.standardOutput.contains("sleepy --help"))
    }

    // MARK: - Mistyped invocations

    @Test func `a missing required flag names the flag and the verb`() async throws {
        let result = try await GoldenBinary.runOffPool(["query", "http://example.com/"])
        #expect(result.exitCode == 2)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("--selector"))
        #expect(result.standardError.contains("sleepy query"))
    }

    @Test func `an unknown flag names the flag it didn't understand`() async throws {
        let result = try await GoldenBinary.runOffPool(["load", "--nonsense"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("--nonsense"))
        #expect(result.standardError.contains("sleepy load"))
    }

    @Test func `an unknown verb points at the verb list`() async throws {
        let result = try await GoldenBinary.runOffPool(["frobnicate"])
        #expect(result.exitCode == 2)
        #expect(result.standardError.contains("frobnicate"))
        #expect(result.standardError.contains("sleepy --help"))
    }

    @Test func `a parsing failure never shows a stack trace`() async throws {
        let result = try await GoldenBinary.runOffPool(["eval", "http://example.com/"])
        #expect(result.exitCode == 2)
        #expect(!result.standardError.contains("Fatal error"))
        #expect(!result.standardError.contains(".swift:"))
        #expect(result.standardError.contains("--js"))
    }

    @Test func `--help is a clean exit, not a failure`() async throws {
        let result = try await GoldenBinary.runOffPool(["--help"])
        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("SUBCOMMANDS"))
    }

    @Test func `the hidden helper verb stays out of the verb list`() async throws {
        let result = try await GoldenBinary.runOffPool(["--help"])
        #expect(!result.standardOutput.contains("_host"))
    }

    // MARK: - Recipes

    /// The goal-to-verb routing table, reachable both as its own verb and
    /// through ArgumentParser's built-in `help` subcommand.
    @Test func `sleepy help recipes lists goal to verb pairs and names peep`() async throws {
        let result = try await GoldenBinary.runOffPool(["help", "recipes"])
        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("wire"))
        #expect(result.standardOutput.contains("ax"))
        #expect(result.standardOutput.contains("eval"))
        #expect(result.standardOutput.contains("peep"))
    }
}
