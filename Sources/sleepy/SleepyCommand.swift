import ArgumentParser
import SleepyHollow

/// The `sleepy` command-line entry point.
///
/// Placeholder pending the CLI scaffold leaf (7ZGKR): the real root command is
/// a primer — what the tool is, the three most common invocations, where help
/// lives.
@main
struct SleepyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sleepy",
        abstract: "A headless WebKit browser for agents.",
    )
}
