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
        The submission goes through a real, cancellable submit event: a page that calls preventDefault() stops it, and an invalid form is refused with the field that failed.

        Examples:
          sleepy submit --session login --selector '#sign-in-form'
          sleepy submit --session login --selector '#email'      # its own form
          sleepy dom http://localhost:3000/ --submit '#editor'   # one shot

        Exit codes: 0 submitted, 1 nothing matched, or the form failed its constraints (the failing field is on stderr; nothing on stdout), 2 usage — including a URL instead of --session, or an element that is not in a form, 5 no such session.
        """,
    )

    /// The one-shot flag that does the same thing, named by every failure.
    static let oneShotExample: String = "--submit '#editor'"

    @OptionGroup var source: PageSourceOptions

    /// `--element` is the same flag: `shot` shipped with that spelling, so
    /// both names reach the one concept from either verb.
    @Option(
        name: [.long, .customLong("element")],
        help: "CSS selector naming the form, or an element inside it (--element is the same flag).",
    )
    var selector: String

    @OptionGroup var out: OutOption

    @OptionGroup var quiet: QuietOption

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
