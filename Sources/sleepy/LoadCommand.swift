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
        `load` is the one verb that takes a URL *and* --session together: that pair
        navigates the open session to the URL. With --session alone it reports the page
        the session is already on.

        Examples:
          sleepy load http://localhost:3000/
          sleepy load http://localhost:3000/app --wait-for '#ready' --budget 5000
          sleepy load --session login http://localhost:3000/dashboard
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
        let target: PageSourceOptions.LoadTarget = try source.resolveLoadTarget()
        let facts: PageFacts = try await PageExecution.run(
            NavigateOperation(url: target.navigationURL),
            on: target.pageSource,
            flags: flags,
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try out.sink.write(encoder.encode(facts))
    }
}
