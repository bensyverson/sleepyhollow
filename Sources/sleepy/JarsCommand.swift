import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy jars` — the management verb for named cookie state.
///
/// A management verb takes no page source (vision doc, "The grammar"), so the
/// jar's name is a plain positional here rather than a flag: there is no URL
/// slot for `ArgumentParser` to misassign it to, which is the whole reason
/// page verbs use `--selector` and friends.
///
/// Jars are not created here. Naming one on a loading verb — `sleepy load
/// <url> --jar login` — is what creates it; this verb only shows, empties and
/// deletes what already exists.
struct JarsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "jars",
        abstract: "List, empty, and delete named cookie jars.",
        discussion: """
        Jars live under $SLEEPYHOLLOW_HOME/jars (default ~/.sleepyhollow/jars).
        Naming a jar creates it: `sleepy load <url> --jar login`.

        Examples:
          sleepy jars list
          sleepy jars list --format json
          sleepy jars clear login
          sleepy jars rm login
        """,
        subcommands: [List.self, Clear.self, Remove.self],
        defaultSubcommand: List.self,
    )

    /// `sleepy jars list` — every jar, its cookie count, and its last write.
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "Show every jar with its cookie count and last write.",
        )

        /// The formats `jars list` supports.
        static let supportedFormats: Set<OutputFormat> = [.text, .json]

        @OptionGroup var format: FormatOption
        @OptionGroup var out: OutOption

        func run() throws {
            let summaries: [JarSummary] = JarStore().summaries()
            let resolved: OutputFormat = try format.resolve(
                default: .text,
                supporting: Self.supportedFormats,
                verb: "jars list",
            )
            switch resolved {
            case .json:
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                try out.sink.write(encoder.encode(summaries))
            default:
                let lines: [String] = summaries.map(\.terseLine)
                try out.sink.write(lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n"))
            }
        }
    }

    /// `sleepy jars clear <name>` — empty a jar, keeping it.
    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Drop every cookie in a jar, keeping the jar itself.",
        )

        @Argument(help: "The jar to empty.")
        var name: JarName

        func run() throws {
            try JarStore().clear(name)
        }
    }

    /// `sleepy jars rm <name>` — delete a jar outright.
    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rm",
            abstract: "Delete a jar and everything in it.",
        )

        @Argument(help: "The jar to delete.")
        var name: JarName

        func run() throws {
            try JarStore().remove(name)
        }
    }
}
