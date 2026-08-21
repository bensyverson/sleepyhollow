import ArgumentParser
import Darwin
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy query` — matched elements as facts: text, attributes, geometry,
/// visibility. `--exists`/`--count` carry an assertion in the exit code.
///
/// `--selector` is a flag rather than a bare positional deliberately: this
/// codebase's shared page-source group (``PageSourceOptions``) already
/// contributes an *optional* positional (the URL, absent when `--session`
/// is used), and `ArgumentParser` fills positionals left to right without
/// knowing which named options will supply the alternative — verified with
/// a throwaway probe package: `sleepy query --session foo display` silently
/// consumed `"display"` into the URL slot and left the selector missing,
/// even though the URL slot is optional and the selector is required. The
/// vision doc's own `--element <selector>` flag on `shot` sidesteps the
/// exact same trap; `--selector` here follows that precedent.
struct QueryCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "query",
        abstract: "Match a CSS selector and report each element's text, attributes, geometry, and visibility.",
        discussion: """
        Examples:
          sleepy query http://localhost:3000/ --selector '#publish'
          sleepy query http://localhost:3000/ --selector '.error' --exists
          sleepy query http://localhost:3000/ --selector 'li' --count 3
          sleepy query http://localhost:3000/ --selector 'button' --format text
        """,
    )

    /// The formats `query` supports: the full facts as JSON, or one terse
    /// line per element.
    static let supportedFormats: Set<OutputFormat> = [.json, .text]

    @OptionGroup var source: PageSourceOptions

    @Option(name: .long, help: "CSS selector to match.")
    var selector: String

    @Flag(name: .long, help: "Exit 0 if at least one element matches, exit 1 if none do.")
    var exists: Bool = false

    @Option(name: .long, help: "Exit 0 if exactly this many elements match, exit 1 otherwise.")
    var count: Int?

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
            verb: "query",
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
            let elements: [ElementFact] = try await host.execute(QueryOperation(selector: selector))
            try write(elements, as: resolvedFormat)
            if isNegative(elements) {
                Darwin.exit(ExitStatus.negative.rawValue)
            }
        }
    }

    /// Whether the requested assertions (`--exists`, `--count`) fail.
    private func isNegative(_ elements: [ElementFact]) -> Bool {
        if exists, elements.isEmpty { return true }
        if let count, count != elements.count { return true }
        return false
    }

    private func write(_ elements: [ElementFact], as format: OutputFormat) throws {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try out.sink.write(encoder.encode(elements))
        case .text:
            let lines = elements.map(Self.textLine)
            try out.sink.write(lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
        case .html, .outline:
            throw SleepyError(
                kind: .usage,
                message: "'query' doesn't support --format \(format.rawValue).",
                nextMove: "Choose one of: json, text.",
            )
        }
    }

    /// One terse line: tag, quoted rendered text, visibility, and geometry.
    private static func textLine(_ element: ElementFact) -> String {
        let geometry = element.geometry
        let rect = "x=\(Int(geometry.x)) y=\(Int(geometry.y)) w=\(Int(geometry.width)) h=\(Int(geometry.height))"
        return "\(element.tagName) \"\(element.text)\" visible=\(element.visible) \(rect)"
    }
}
