import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy archive` — a `.webarchive` of the page and its subresources
/// (`WKWebView.createWebArchiveData`).
///
/// *Need:* evidence. A bug report that carries the page as it was — assets
/// included — outlives the server state that produced it.
struct ArchiveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "archive",
        abstract: "Save a page and its subresources as a .webarchive.",
        discussion: """
        Examples:
          sleepy archive http://localhost:3000/ --out page.webarchive
          sleepy archive http://localhost:3000/report --out report.webarchive

        Exit codes: 0 success, 2 usage, 4 load failure, 5 environment.
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
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
            let output = try await host.execute(ArchiveOperation())
            try out.sink.write(output.archive)
        }
    }
}
