import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// The `sleepy` command-line entry point.
///
/// A bare invocation prints the primer — what the tool is, the three most
/// common invocations, where help lives — the `job` doctrine (see the
/// vision doc, "The CLI itself"). Verb subcommands are wired in by the
/// leaves that build them; this scaffold owns only the primer, the shared
/// option groups (``SleepyCLIKit``), and error rendering.
@main
struct SleepyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sleepy",
        abstract: "A headless WebKit browser for agents.",
        subcommands: [LoadCommand.self, ShotCommand.self, PdfCommand.self, ArchiveCommand.self, DomCommand.self, QueryCommand.self, StyleCommand.self, FindCommand.self, AXCommand.self, ConsoleCommand.self, WireCommand.self, HostCommand.self],
    )

    /// What the tool is, the three most common invocations, and where help
    /// lives. Printed verbatim by a bare `sleepy`.
    static let primer = """
    SleepyHollow is a headless WebKit browser for agents: it renders real pages with the system's WebKit engine and exposes them — pixels, DOM, computed style, the accessibility tree, the wire log — as verbs that emit structured text and exit codes that mean something.

    Common invocations:
      sleepy load <url>                  load a page, report status and console errors
      sleepy shot <url> --out shot.png   screenshot a page
      sleepy ax --session <name>         read a live session's accessibility tree

    Help: `sleepy <verb> --help` for a verb's flags and examples, `sleepy --help` to list every verb.
    """

    func run() throws {
        print(Self.primer)
    }

    /// Overrides ArgumentParser's default entry point so every failure —
    /// ours or ArgumentParser's own — goes through one rendering path with
    /// Core's exit-code contract, never a stack trace. Async so verb
    /// subcommands can await the page host on the main actor.
    @MainActor
    static func main() async {
        do {
            var command = try parseAsRoot()
            if var asyncCommand = command as? any AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
        } catch let error as SleepyError {
            emit(ErrorRendering.render(sleepyError: error))
        } catch {
            // Help and version requests are a clean exit: let ArgumentParser
            // print its own text and exit 0.
            if exitCode(for: error) == .success {
                exit(withError: error)
            }
            emit(ErrorRendering.renderParsingFailure(
                usage: usageString(),
                commandName: configuration.commandName ?? "sleepy",
            ))
        }
    }
}

/// Writes a rendered failure to the right stream and exits with its code.
private func emit(_ rendered: ErrorRendering.Rendered) -> Never {
    if rendered.toStandardError {
        FileHandle.standardError.write(Data((rendered.text + "\n").utf8))
    } else {
        print(rendered.text)
    }
    exit(rendered.exitCode)
}
