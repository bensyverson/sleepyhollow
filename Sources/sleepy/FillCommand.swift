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
        Text fields take the value as typed; a checkbox or radio takes true/1/on/yes/checked;
        a <select> takes an option's value or its visible label.

        Examples:
          sleepy fill --session login --selector '#email' --value 'agent@example.com'
          sleepy dom http://localhost:3000/ --fill '#q=webkit'   # the same action, one shot
        """,
    )

    /// The one-shot flag that does the same thing, named by every failure.
    static let oneShotExample: String = "--fill '#q=webkit'"

    @OptionGroup var source: PageSourceOptions

    @Option(name: .long, help: "CSS selector; the first match is filled.")
    var selector: String

    @Option(name: .long, help: "Value to set, interpreted by the field's kind.")
    var value: String

    @MainActor
    mutating func run() async throws {
        let session: SessionName = try ActTarget.session(
            from: source,
            verb: FillOperation.kind,
            example: Self.oneShotExample,
        )
        throw ActTarget.pendingRouting(
            verb: FillOperation.kind,
            session: session,
            example: "--fill '\(selector)=\(value)'",
        )
    }
}
