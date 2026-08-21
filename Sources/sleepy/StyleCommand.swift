import ArgumentParser
import Darwin
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy style` — computed CSS values for the first element a selector
/// matches. A selector matching nothing exits 1 (clean negative), the same
/// contract `find` uses for "the page doesn't have this."
///
/// `--selector` and `--property` are flags, not positionals — see
/// ``QueryCommand``'s discussion for why (the shared page-source group's
/// optional URL positional silently steals a same-position verb argument
/// when `--session` is used).
struct StyleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "style",
        abstract: "Read computed CSS values for the first element a selector matches.",
        discussion: """
        Examples:
          sleepy style http://localhost:3000/ --selector 'h1' --property display
          sleepy style http://localhost:3000/ --selector body --property background-color --property color
          sleepy style http://localhost:3000/ --selector 'h1' --property display --format text
        """,
    )

    /// The formats `style` supports: computed values as JSON, or one
    /// `property: value` line per requested property.
    static let supportedFormats: Set<OutputFormat> = [.json, .text]

    @OptionGroup var source: PageSourceOptions

    @Option(name: .long, help: "CSS selector; computed style is read from its first match.")
    var selector: String

    @Option(name: .long, parsing: .singleValue, help: "Computed property to read, e.g. display (repeatable).")
    var property: [String] = []

    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var format: FormatOption
    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
        guard !property.isEmpty else {
            throw SleepyError(
                kind: .usage,
                message: "'style' needs at least one --property.",
                nextMove: "Add --property <name>, e.g. --property display.",
            )
        }
        let resolvedFormat: OutputFormat = try format.resolve(
            default: .json,
            supporting: Self.supportedFormats,
            verb: "style",
        )
        let result: StyleResult = try await PageExecution.run(
            StyleOperation(selector: selector, properties: property),
            on: source.resolve(),
            flags: flags,
        )
        try write(result, as: resolvedFormat)
        if !result.matched {
            Darwin.exit(ExitStatus.negative.rawValue)
        }
    }

    private func write(_ result: StyleResult, as format: OutputFormat) throws {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try out.sink.write(encoder.encode(result))
        case .text:
            guard result.matched else {
                try out.sink.write("no match\n")
                return
            }
            let lines = property.map { "\($0): \(result.values[$0] ?? "")" }
            try out.sink.write(lines.joined(separator: "\n") + "\n")
        case .html, .outline:
            throw SleepyError(
                kind: .usage,
                message: "'style' doesn't support --format \(format.rawValue).",
                nextMove: "Choose one of: json, text.",
            )
        }
    }
}
