import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy sessions` — the management verb for named sessions.
///
/// A management verb takes no page source (vision doc, "The grammar"), so a
/// session's name is a plain positional here rather than `--session`.
///
/// Sessions are not created here: `sleepy open <url> --name <n>` is what
/// creates one. This verb shows what is running, reaps what is not, and closes
/// what should stop.
struct SessionsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sessions",
        abstract: "List, reap, and close named sessions.",
        discussion: """
        Sessions live under $SLEEPYHOLLOW_HOME/sessions (default ~/.sleepyhollow/sessions). Nothing supervises them: each helper reaps itself on an idle TTL, and whatever a crash leaves behind is reaped lazily, here.

        Examples:
          sleepy sessions list
          sleepy sessions list --format json
          sleepy sessions prune
          sleepy sessions close login
        """,
        subcommands: [List.self, Prune.self, Close.self],
        defaultSubcommand: List.self,
    )

    /// `sleepy sessions list` — every session, probed, then reaped if dead.
    ///
    /// The listing reports the orphan *and then removes it*: that is what
    /// "reaped lazily" means — you see what died once, and the next listing is
    /// clean. A live session is never touched.
    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Show every session with its pid, liveness, age and URL; reap the dead ones.",
            discussion: """
            A dead session is reported once and then removed, so the next listing is clean.

            Formats: text (default) — one line per session; json — the same entries with ISO dates.

            Examples:
              sleepy sessions list
              sleepy sessions list --format json

            Exit codes: 0 always — an empty list is an answer, not a failure.
            """,
        )

        /// The formats `sessions list` supports.
        static let supportedFormats: Set<OutputFormat> = [.text, .json]

        @OptionGroup var format: FormatOption
        @OptionGroup var out: OutOption
        @OptionGroup var quiet: QuietOption

        func run() throws {
            let registry = SessionRegistry()
            let entries: [SessionEntry] = registry.entries()
            let resolved: OutputFormat = try format.resolve(
                default: .text,
                supporting: Self.supportedFormats,
                verb: "sessions list",
            )
            switch resolved {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try out.sink.write(encoder.encode(entries))
            default:
                let lines: [String] = entries.map(\.terseLine)
                try out.sink.write(lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
            }
            registry.prune()
        }
    }

    /// `sleepy sessions prune` — remove every session that is not live.
    struct Prune: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "prune",
            abstract: "Remove every session whose helper is gone, and report what went.",
            discussion: """
            Prints one name per removed session. Live sessions are never touched — use
            `sleepy close <name>` for those.

            Examples:
              sleepy sessions prune

            Exit codes: 0 always — nothing to reap is an answer, not a failure.
            """,
        )

        @OptionGroup var out: OutOption

        @OptionGroup var quiet: QuietOption

        func run() throws {
            let removed: [SessionName] = SessionRegistry().prune()
            let lines: [String] = removed.map(\.rawValue)
            try out.sink.write(lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
        }
    }

    /// `sleepy sessions close <name>` — the same act as `sleepy close`.
    struct Close: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "close",
            abstract: "End a named session; the name is free when this returns.",
            discussion: """
            The same act as `sleepy close <name>`, spelled the way the management verb reads.

            Examples:
              sleepy sessions close login

            Exit codes: 0 closed (or already gone), 2 usage, 5 no session by that name.
            """,
        )

        @Argument(help: "The session to close.")
        var name: String

        @OptionGroup var quiet: QuietOption

        func run() async throws {
            let target: SessionName = try CloseCommand.resolve(name: name, session: nil)
            try await SessionShutdown.close(target, in: SessionRegistry())
        }
    }
}
