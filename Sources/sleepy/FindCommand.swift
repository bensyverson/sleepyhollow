import ArgumentParser
import Darwin
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy find` — does the *rendered* page say this, the way ⌘F would?
/// The answer is chiefly the exit code (0 matched, 1 clean negative); the
/// body is a small confirmation, terse text by default.
///
/// `--text` is a flag, not a positional — see ``QueryCommand``'s discussion
/// for why (the shared page-source group's optional URL positional silently
/// steals a same-position verb argument when `--session` is used).
struct FindCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Search the rendered page for text, the way ⌘F would. Exit 0 if found, 1 if not.",
        discussion: """
        The search is over rendered text, so a string split across elements still matches and a display:none one does not.

        Formats: text (default) — 'matched' or 'no match'; json — a bare boolean.

        Examples:
          sleepy find http://localhost:3000/ --text 'Welcome back'
          sleepy find http://localhost:3000/ --text 'Welcome back' --format json
          sleepy find --session app --text 'Saved'

        Exit codes: 0 found, 1 not found — 'no match' is still printed on stdout, 2 usage, 3 budget ran out, 4 load failure, 5 no such session.
        """,
    )

    /// The formats `find` supports: a one-word confirmation, or a bare JSON
    /// boolean.
    static let supportedFormats: Set<OutputFormat> = [.text, .json]

    @OptionGroup var source: PageSourceOptions

    @Option(name: .long, help: "Text to search for in the rendered page.")
    var text: String

    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var format: FormatOption
    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
        let resolvedFormat: OutputFormat = try format.resolve(
            default: .text,
            supporting: Self.supportedFormats,
            verb: "find",
        )
        let matched: Bool = try await PageExecution.run(
            FindOperation(text: text),
            on: source.resolve(),
            flags: flags,
        )
        try write(matched, as: resolvedFormat)
        if !matched {
            Darwin.exit(ExitStatus.negative.rawValue)
        }
    }

    private func write(_ matched: Bool, as format: OutputFormat) throws {
        switch format {
        case .text:
            try out.sink.write(matched ? "matched\n" : "no match\n")
        case .json:
            try out.sink.write(JSONEncoder().encode(matched))
        case .html, .outline:
            throw SleepyError(
                kind: .usage,
                message: "'find' doesn't support --format \(format.rawValue).",
                nextMove: "Choose one of: text, json.",
            )
        }
    }
}
