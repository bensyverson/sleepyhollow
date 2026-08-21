import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy load` — the base loading verb: load, settle, report the facts.
///
/// Every other loading verb is `load` plus a read; this one is the smoke
/// test. Exit 0 means the navigation completed — an HTTP error page (404,
/// 500) still *loads*, so its status lands in the facts and the exit stays 0.
/// Exit 4 means the navigation itself failed; exit 3 means the budget ran
/// out.
struct LoadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "load",
        abstract: "Load a page and report the facts: final URL, HTTP status, console errors, dialogs.",
        discussion: """
        Examples:
          sleepy load http://localhost:3000/
          sleepy load http://localhost:3000/app --wait-for '#ready' --budget 5000
          sleepy load http://localhost:3000/ --theme dark --out facts.json
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
            let facts = try await host.load(url)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let encoded: Data = try encoder.encode(facts)
            try out.sink.write(encoded)
        }
    }
}
