import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy fill` — set a field's value in a live session.
///
/// An act verb: it requires `--session`. The selector and the value are
/// separate flags here; the one-shot flag joins them with `=`
/// (`--fill '#q=webkit'`) because a flag can carry only one word.
struct FillCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fill",
        abstract: "Set a field's value in a live session, dispatching input and change.",
        discussion: """
        Text fields take the value as typed; a checkbox or radio takes true/1/on/yes/checked; a <select> takes an option's value or its visible label.

        Examples:
          sleepy fill --session login --selector '#email' --value 'a@example.com'
          sleepy fill --session login --selector '#terms' --value true
          sleepy dom http://localhost:3000/ --fill '#q=webkit'   # one shot

        Exit codes: 0 filled, 1 nothing matched, or the field is disabled, read-only, or has no such option (the reason is on stderr; nothing on stdout), 2 usage — including a URL instead of --session, or a field that holds no value, 5 no such session.
        """,
    )

    /// The one-shot flag that does the same thing, named by every failure.
    static let oneShotExample: String = "--fill '#q=webkit'"

    @OptionGroup var source: PageSourceOptions

    /// `--element` is the same flag: `shot` shipped with that spelling, so
    /// both names reach the one concept from either verb.
    @Option(
        name: [.long, .customLong("element")],
        help: "CSS selector; the first match is filled (--element is the same flag).",
    )
    var selector: String

    @Option(name: .long, help: "Value to set, interpreted by the field's kind.")
    var value: String

    @OptionGroup var out: OutOption

    @OptionGroup var quiet: QuietOption

    @MainActor
    mutating func run() async throws {
        let session: SessionName = try ActTarget.session(
            from: source,
            verb: FillOperation.kind,
            example: Self.oneShotExample,
        )
        try await ActTarget.act(FillOperation(selector: selector, value: value), in: session, to: out.sink)
    }
}
