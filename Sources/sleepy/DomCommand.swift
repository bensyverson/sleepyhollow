import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy dom` — the page's serialized DOM: its native markup by default,
/// a typed tree with `--format json`.
struct DomCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dom",
        abstract: "Serialize the page's DOM: HTML by default, a typed tree with --format json.",
        discussion: """
        The DOM is the *rendered* one — script has run, so this is what the page became, not what the server sent.

        Formats: html (default), json.

        Examples:
          sleepy dom http://localhost:3000/
          sleepy dom http://localhost:3000/ --format json
          sleepy dom http://localhost:3000/ --out page.html
          sleepy dom --session app --format json

        Exit codes: 0 success, 2 usage, 3 budget ran out, 4 load failure, 5 no such session.
        """,
    )

    /// The formats `dom` supports: its native markup, and the typed tree.
    static let supportedFormats: Set<OutputFormat> = [.html, .json]

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var format: FormatOption
    @OptionGroup var out: OutOption
    @OptionGroup var quiet: QuietOption

    @MainActor
    mutating func run() async throws {
        let resolvedFormat: OutputFormat = try format.resolve(
            default: .html,
            supporting: Self.supportedFormats,
            verb: "dom",
        )
        let result: DOMResult = try await PageExecution.run(
            DOMOperation(),
            on: source.resolve(),
            flags: flags,
        )
        try write(result, as: resolvedFormat)
    }

    private func write(_ result: DOMResult, as format: OutputFormat) throws {
        switch format {
        case .html:
            try out.sink.write(result.html)
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try out.sink.write(encoder.encode(result.tree))
        case .text, .outline:
            throw SleepyError(
                kind: .usage,
                message: "'dom' doesn't support --format \(format.rawValue).",
                nextMove: "Choose one of: html, json.",
            )
        }
    }
}
