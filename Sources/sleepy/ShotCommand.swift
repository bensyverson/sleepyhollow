import ArgumentParser
import Darwin
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy shot` — render at a given `--size`, write a PNG.
///
/// *Need:* the baseline act of seeing. `--element` crops to one element's
/// rect — the thing under test is rarely the whole page — and `--full-page`
/// captures the entire scroll height instead of the viewport.
///
/// Exit 1 is `--element`'s clean negative: the selector matched nothing.
/// Every other failure follows the shared scheme (2 usage, 4 load failure,
/// 5 environment).
struct ShotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shot",
        abstract: "Screenshot a page: the viewport, one element, or the full scrollable page.",
        discussion: """
        Examples:
          sleepy shot http://localhost:3000/ --out shot.png
          sleepy shot http://localhost:3000/ --element '#save-button' --out button.png
          sleepy shot http://localhost:3000/ --full-page --theme dark --out page.png

        Exit codes: 0 success, 1 --element matched nothing, 2 usage, 4 load failure, 5 environment.
        """,
    )

    @OptionGroup var source: PageSourceOptions
    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var out: OutOption

    @Option(name: .long, help: "Crop the screenshot to this CSS selector's rect. Exits 1 if nothing matches.")
    var element: String?

    @Flag(name: .long, help: "Capture the full scrollable page instead of the viewport.")
    var fullPage: Bool = false

    @MainActor
    mutating func run() async throws {
        let output = try await PageExecution.run(
            ShotOperation(element: element, fullPage: fullPage),
            on: source.resolve(),
            flags: flags,
        )
        try out.sink.write(output.png)
    }
}
