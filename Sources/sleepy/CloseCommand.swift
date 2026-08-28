import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy close <name>` — end a named session and free the name.
///
/// The vision doc spells this two ways — `sleepy close login` in the
/// already-open error, and `sleepy sessions close` in the self-supervision
/// bullet — so both work, and `--session <name>` is accepted as well because
/// that is how every other verb names a session. They are one act:
/// ``SessionShutdown``.
///
/// Closing a session whose helper already died is a success, not a failure:
/// there is nothing left to stop, and the registry entry is reaped. Only a
/// name nobody ever claimed is an error.
struct CloseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "close",
        abstract: "End a named session; the name is free when this returns.",
        discussion: """
        The helper is asked to stop over its own socket — never signalled — and `close`
        waits for it to go, so `open` can reuse the name immediately afterwards.

        Examples:
          sleepy close login
          sleepy close --session login

        Exit codes: 0 closed (or already gone), 2 usage, 5 no session by that name.
        """,
    )

    @Argument(help: "The session to close.")
    var name: String?

    @Option(name: .long, help: "The session to close, spelled the way page verbs spell it.")
    var session: String?

    @OptionGroup var quiet: QuietOption

    mutating func run() async throws {
        let target: SessionName = try CloseCommand.resolve(name: name, session: session)
        try await SessionShutdown.close(target, in: SessionRegistry())
    }

    /// Resolves the two spellings to one name.
    ///
    /// - Throws: `SleepyError` of kind `SleepyError.Kind.usage` when both
    ///   or neither was given, or the name is not a valid session name.
    static func resolve(name: String?, session: String?) throws -> SessionName {
        let raw: String
        switch (name, session) {
        case let (.some(positional), .none):
            raw = positional
        case let (.none, .some(named)):
            raw = named
        case (.some, .some):
            throw SleepyError(
                kind: .usage,
                message: "Name the session once: as an argument or as --session, not both.",
                nextMove: "`sleepy close <name>`.",
            )
        case (.none, .none):
            throw SleepyError(
                kind: .usage,
                message: "`close` needs a session to close.",
                nextMove: "`sleepy close <name>`; `sleepy sessions list` shows the sessions there are.",
            )
        }
        guard let resolved = SessionName(raw) else {
            throw SleepyError(
                kind: .usage,
                message: "'\(raw)' is not a valid session name.",
                nextMove: "Start with a letter or digit, then letters, digits, '.', '_', or '-'.",
            )
        }
        return resolved
    }
}
