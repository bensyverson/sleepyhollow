import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy ax` — the accessibility tree: the page as assistive technology
/// reads it, and the flagship read of the tool.
///
/// The default output is an indented outline, one node per line, because
/// "is there a button named Publish, and is it disabled?" should be one line
/// of `grep` rather than a JSON walk. `--format json` emits the same tree in
/// the stable machine shape.
struct AXCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ax",
        abstract: "Read the accessibility tree: roles, names and states, presentation stripped away.",
        discussion: """
        The outline is one node per line, indented by depth:

          document "Publish an article"
            form
              textbox "Article title" (value="Sleepy Hollow ships")
              checkbox "Notify subscribers" (checked)
              button "Publish" (disabled)

        So the flagship query is a grep:

          sleepy ax http://localhost:3000/editor | grep 'button "Publish"'
          sleepy ax http://localhost:3000/ --format json --out tree.json
          sleepy ax http://localhost:3000/ --theme dark --budget 5000

        Formats: outline (default) and json.

        The tree is computed in the page from WAI-ARIA and AccName, not copied
        from WebKit's internal accessibility tree — a headless process cannot
        reach that one. Known limits: shadow DOM is not descended, cross-origin
        frames come back as empty document nodes, and aria-owns does not
        reparent.
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var format: FormatOption
    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
        let chosen: OutputFormat = try format.resolve(
            default: .outline,
            supporting: [.outline, .json],
            verb: "ax",
        )
        let steps: [ActionStep] = try ActionStepParser.parse(CommandLine.arguments)
        let options: LoadOptions = try flags.resolveLoadOptions(steps: steps)
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
            let tree: AXNode = try await host.execute(AXOperation())
            try out.sink.write(Self.encode(tree, as: chosen))
        }
    }

    /// The outline as text, or the tree as pretty, key-sorted JSON — the same
    /// shape every other verb's `--format json` emits.
    private static func encode(_ tree: AXNode, as format: OutputFormat) throws -> Data {
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return try encoder.encode(tree)
        default:
            return Data(AXOutline.render(tree).utf8)
        }
    }
}
