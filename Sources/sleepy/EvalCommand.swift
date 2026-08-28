import ArgumentParser
import Darwin
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy eval` — run JavaScript against a page and print its value as JSON.
///
/// The script is an async function body: `await` works, and a `return` sends
/// the value back; a single expression — one trailing `;` allowed — is
/// wrapped for you (see ``EvalOperation/SourceShape``). It comes from `--js`
/// or, for anything
/// multi-line, `--file <path>` (`-` for standard input) — exactly one of the
/// two.
///
/// It runs in the page's own world by default, because that is where the
/// agent's question almost always lives; `--world isolated` opts into a world
/// that shares the DOM but not the page's JavaScript.
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
        The script is an async function body: use 'return' to send a value back, and 'await' freely. A single expression is wrapped as 'return (…);' for you, one trailing ';' and all — 'document.title' answers the title, and 'el.click();' answers null because that is what the call returns. A script with an interior ';', or one opening with a statement keyword like 'const' or 'if', has no value to send back and is refused rather than answered with null.

        Give the script with --js, or with --file <path> for a multi-line script; --file - reads standard input. Exactly one of the two.

        Worlds. --world page (the default) runs in the page's own JavaScript world, so page globals, page classes and the methods a custom element gained when it upgraded are all there. --world isolated runs in Sleepy's world: it shares the DOM — nodes, attributes, shadow roots — but nothing of the page's JavaScript, so page globals, classes and upgraded custom-element prototypes read as undefined (an upgraded element looks like a bare HTMLElement). Confusingly, customElements.get() still answers from the isolated world, because the registry is DOM-side — so the split is invisible until a prototype method is missing. Use isolated when page script must not observe or shadow what you run.

        Formats: json (default), text — a string result comes back unquoted.

        Examples:
          sleepy eval http://localhost:3000/ --js 'document.title'
          sleepy eval http://localhost:3000/ --js 'return await probe();'
          sleepy eval http://localhost:3000/ --js 'return rows()===n;' --args '{"n":3}'
          sleepy eval --session app --file checks.js
          sleepy eval --session app --js 'return window.store.ready;' --world isolated

        Exit codes: 0 success, 1 the result was exactly false — 'false' is still printed on stdout, 2 usage or the page rejected the script, 3 budget ran out, 4 load failure, 5 no such session.
        """,
    )

    /// The formats `eval` supports: the JSON value, or its text when the
    /// value is a string.
    static let supportedFormats: Set<OutputFormat> = [.json, .text]

    /// The `--file` value that means standard input.
    private static let standardInputPath: String = "-"

    @OptionGroup var source: PageSourceOptions

    @Option(name: .long, help: "JavaScript to evaluate: an async function body, or a single expression.")
    var js: String?

    @Option(name: .long, help: "Read the script from this file instead of --js; '-' reads standard input.")
    var file: String?

    @Option(name: .long, help: "JSON object whose keys arrive in scope as named arguments.")
    var args: String?

    @Option(name: .long, help: "Which JavaScript world to evaluate in: page (the default) or isolated.")
    var world: InjectedScript.World = .page

    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var format: FormatOption
    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
        let resolvedFormat: OutputFormat = try format.resolve(
            default: .json,
            supporting: Self.supportedFormats,
            verb: "eval",
        )
        let operation = try EvalOperation(
            source: script(),
            argumentsJSON: args,
            world: world,
        )
        let result: String = try await PageExecution.run(operation, on: source.resolve(), flags: flags)
        try write(result, as: resolvedFormat)
        if result == "false" {
            Darwin.exit(ExitStatus.negative.rawValue)
        }
    }

    /// The script to evaluate, from `--js`, a file, or standard input.
    ///
    /// - Throws: `SleepyError` of kind `SleepyError.Kind.usage` when both
    ///   flags or neither were given, or when the file cannot be read.
    private func script() throws -> String {
        switch (js, file) {
        case let (.some(inline), .none):
            return inline
        case let (.none, .some(path)):
            return try Self.readScript(at: path)
        case (.some, .some):
            throw SleepyError(
                kind: .usage,
                message: "--js and --file both name a script, and eval evaluates exactly one.",
                nextMove: "Keep --js for a one-liner, or --file <path> for a script on disk; drop the other.",
            )
        case (.none, .none):
            throw SleepyError(
                kind: .usage,
                message: "eval has no script to run.",
                nextMove: "Pass --js '<javascript>' for a one-liner, "
                    + "or --file <path> (or --file - for standard input) for a multi-line script.",
            )
        }
    }

    /// Reads a script from `path`, or from standard input when it is `-`.
    private static func readScript(at path: String) throws -> String {
        if path == standardInputPath {
            return String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        }
        do {
            return try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        } catch {
            throw SleepyError(
                kind: .usage,
                message: "--file couldn't read '\(path)': \(error.localizedDescription)",
                nextMove: "Name a readable UTF-8 file, or pass '--file -' to read the script from standard input.",
            )
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
