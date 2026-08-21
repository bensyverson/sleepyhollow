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
          sleepy archive http://localhost:3000/r --wait-for '#ready' --out r.webarchive
          sleepy archive --session app --out app.webarchive

        Exit codes: 0 success, 2 usage, 3 budget ran out, 4 load failure, 5 no such session.
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
        let output = try await PageExecution.run(ArchiveOperation(), on: source.resolve(), flags: flags)
        try out.sink.write(output.archive)
    }
}
