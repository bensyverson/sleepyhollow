import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy console` — everything the page said: console output at every level,
/// uncaught errors, and unhandled rejections.
///
/// The log covers the current document from its first byte through the moment
/// the page settles, in the page's own order. Exit 0 means the page loaded and
/// the log was read — the page complaining is the *answer*, not a failure.
struct ConsoleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "console",
        abstract: "Report the page's console output, uncaught errors and unhandled rejections.",
        discussion: """
        The log covers the current document, in the page's own order, up to the
        moment it is read — a page that talks later needs --wait-for.

        Formats: json (default), text — one labelled line per message.

        Examples:
          sleepy console http://localhost:3000/
          sleepy console http://localhost:3000/app --format text
          sleepy console http://localhost:3000/app --inject probe.js --out console.json
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var format: FormatOption
    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
        let chosen: OutputFormat = try format.resolve(
            default: .json,
            supporting: [.json, .text],
            verb: "console",
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
            let log: ConsoleLog = try await host.execute(ConsoleOperation())
            let rendered: Data = try ObserveRendering.render(log, text: log.terseText, as: chosen)
            try out.sink.write(rendered)
        }
    }
}
