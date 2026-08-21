import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy submit` — submit a form in a live session.
///
/// An act verb: it requires `--session`. The selector may name the form
/// itself or any control inside it.
struct SubmitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "submit",
        abstract: "Submit the form a selector names, or the form its element belongs to.",
        discussion: """
        The submission goes through a real, cancellable submit event: a page that calls
        preventDefault() stops it, and an invalid form is refused with the field that failed.

        Examples:
          sleepy submit --session login --selector '#sign-in-form'
          sleepy dom http://localhost:3000/ --submit '#editor'   # the same action, one shot
        """,
    )

    /// The one-shot flag that does the same thing, named by every failure.
    static let oneShotExample: String = "--submit '#editor'"

    @OptionGroup var source: PageSourceOptions

    @Option(name: .long, help: "CSS selector naming the form, or an element inside it.")
    var selector: String

    @OptionGroup var out: OutOption

    @MainActor
    mutating func run() async throws {
        let session: SessionName = try ActTarget.session(
            from: source,
            verb: SubmitOperation.kind,
            example: Self.oneShotExample,
        )
        try await ActTarget.act(SubmitOperation(selector: selector), in: session, to: out.sink)
    }
}
