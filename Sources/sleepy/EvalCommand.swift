import ArgumentParser
import Darwin
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy eval` — run JavaScript against a page and print its value as JSON.
///
/// The script is an async function body: `await` works, and a `return` sends
/// the value back. It runs in an isolated world by default so it cannot
/// collide with page script; `--page-world` opts into the page's own globals.
///
/// The exit code carries the verdict: 0 with the JSON result, 1 when that
/// result is exactly `false` — so an assertion is one invocation — and 2 when
/// the page rejected the script, with the page's own message.
///
/// `--js` is a flag, not a positional — see ``QueryCommand``'s discussion for
/// why (the shared page-source group's optional URL positional silently
/// steals a same-position verb argument when `--session` is used).
struct EvalCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "eval",
        abstract: "Evaluate JavaScript against a page; print the result as JSON. Exit 1 if it is false.",
        discussion: """
        The script is an async function body: use 'return' to send a value back, and 'await' freely.

        Examples:
          sleepy eval http://localhost:3000/ --js 'return document.title;'
          sleepy eval http://localhost:3000/ --js 'return await fetch("/health").then(r => r.status);'
          sleepy eval http://localhost:3000/ --js 'return rows() === n;' --args '{"n": 3}' --page-world
        """,
    )

    /// The formats `eval` supports: the JSON value, or its text when the
    /// value is a string.
    static let supportedFormats: Set<OutputFormat> = [.json, .text]

    @OptionGroup var source: PageSourceOptions

    @Option(name: .long, help: "JavaScript to evaluate: an async function body, so use 'return'.")
    var js: String

    @Option(name: .long, help: "JSON object whose keys arrive in scope as named arguments.")
    var args: String?

    @Flag(name: .long, help: "Evaluate in the page's own world instead of the tool's isolated one.")
    var pageWorld: Bool = false

    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var format: FormatOption
    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
        let steps: [ActionStep] = try ActionStepParser.parse(CommandLine.arguments)
        let options: LoadOptions = try flags.resolveLoadOptions(steps: steps)
        let resolvedFormat: OutputFormat = try format.resolve(
            default: .json,
            supporting: Self.supportedFormats,
            verb: "eval",
        )
        let operation = EvalOperation(
            source: js,
            argumentsJSON: args,
            world: pageWorld ? .page : .isolated,
        )
        switch try source.resolve() {
        case .session:
            throw SleepyError(
                kind: .environment,
                message: "Sessions are not available yet.",
                nextMove: "Give a URL to load ephemerally; sessions arrive with the session leaves.",
            )
        case let .url(url):
            let host = PageHost(options: options)
            _ = try await host.load(url)
            let result: String = try await host.execute(operation)
            try write(result, as: resolvedFormat)
            if result == "false" {
                Darwin.exit(ExitStatus.negative.rawValue)
            }
        }
    }

    /// Writes the JSON value; `--format text` unwraps a JSON string so its
    /// text can be piped without a de-quoting step.
    private func write(_ result: String, as format: OutputFormat) throws {
        switch format {
        case .json:
            try out.sink.write(result + "\n")
        case .text:
            let unwrapped: String? = try? JSONDecoder().decode(String.self, from: Data(result.utf8))
            try out.sink.write((unwrapped ?? result) + "\n")
        case .html, .outline:
            throw SleepyError(
                kind: .usage,
                message: "'eval' doesn't support --format \(format.rawValue).",
                nextMove: "Choose one of: json, text.",
            )
        }
    }
}
