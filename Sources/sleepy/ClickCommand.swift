import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy click` — press an element in a live session.
///
/// An act verb: it requires `--session`, because acting on a page that
/// vanishes at exit is write-only. For a one-shot flow, ride a loading verb
/// instead: `sleepy dom <url> --click '#go'`.
struct ClickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click the first element a selector matches, in a live session.",
        discussion: """
        Synthesized events, not OS-level hit-testing: pointerdown, mousedown, pointerup, mouseup, click.

        Examples:
          sleepy click --session login --selector '#sign-in'
          sleepy dom http://localhost:3000/ --click '#go'      # the same action, one shot
        """,
    )

    /// The one-shot flag that does the same thing, named by every failure.
    static let oneShotExample: String = "--click '#go'"

    @OptionGroup var source: PageSourceOptions

    @Option(name: .long, help: "CSS selector; the first match is clicked.")
    var selector: String

    @MainActor
    mutating func run() async throws {
        let session: SessionName = try ActTarget.session(
            from: source,
            verb: ClickOperation.kind,
            example: Self.oneShotExample,
        )
        throw ActTarget.pendingRouting(
            verb: ClickOperation.kind,
            session: session,
            example: "--click '\(selector)'",
        )
    }
}
