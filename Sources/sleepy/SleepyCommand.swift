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
/// option groups (`SleepyCLIKit`), and error rendering.
@main
struct SleepyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sleepy",
        abstract: "A headless WebKit browser for agents.",
        subcommands: [LoadCommand.self, ShotCommand.self, PdfCommand.self, ArchiveCommand.self, DomCommand.self, QueryCommand.self, StyleCommand.self, FindCommand.self, AXCommand.self, ConsoleCommand.self, WireCommand.self, EvalCommand.self, ClickCommand.self, FillCommand.self, SubmitCommand.self, OpenCommand.self, CloseCommand.self, SessionsCommand.self, JarsCommand.self, CookiesCommand.self, HostCommand.self],
    )

    /// The prefix ArgumentParser puts in front of its own diagnoses.
    ///
    /// The tool's own failures are written as `SleepyError`s and print bare —
    /// message, then next move — so a parser diagnosis wearing "Error: "
    /// would be the only thing in the CLI that shouts. `sleepy: ` matches the
    /// Unix convention and the rest of the output.
    static let _errorPrefix: String = "sleepy: "

    /// What the tool is, the three most common invocations, and where help
    /// lives. Printed verbatim by a bare `sleepy`.
    static let primer = """
    SleepyHollow is a headless WebKit browser for agents: it renders real pages with the system's WebKit engine and exposes them — pixels, DOM, computed style, the accessibility tree, the wire log — as verbs that emit structured text and exit codes that mean something.

    Common invocations:
      sleepy load <url>                       load a page once; report status, console errors, dialogs
      sleepy ax <url> | grep 'button "Save"'  read the page the way assistive technology does
      sleepy open <url> --name app            keep one page alive, then act on it: `sleepy click --session app --selector '#save'`

    Every page verb takes a URL (a fresh page that exits with the command) or --session <name> (a live one).
    Help: `sleepy <verb> --help` for a verb's flags, examples and exit codes; `sleepy --help` to list every verb.
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
            let name: String = configuration.commandName ?? "sleepy"
            if let typed: String = unknownVerb(in: CommandLine.arguments) {
                emit(ErrorRendering.renderUnknownVerb(typed, knownVerbs: visibleVerbs, commandName: name))
            }
            emit(ErrorRendering.renderParsingFailure(fullText: fullMessage(for: error), commandName: name))
        }
    }

    /// Every verb an agent may type. `_host` is excluded because nobody
    /// should ever type it, and suggesting it would be advice to break
    /// something.
    static var visibleVerbs: [String] {
        var names: [String] = []
        for subcommand in configuration.subcommands {
            let subconfiguration: CommandConfiguration = subcommand.configuration
            guard subconfiguration.shouldDisplay, let name: String = subconfiguration.commandName else { continue }
            names.append(name)
        }
        return names
    }

    /// The word in the verb slot, when it is not a verb.
    ///
    /// The verb slot is the first argument that isn't a flag — so
    /// `sleepy --format json frobnicate` and `sleepy frobnicate` both land
    /// here, and `sleepy load --budget -1` does not (the `-1` is a flag's
    /// value, and `load` is a verb).
    static func unknownVerb(in arguments: [String]) -> String? {
        guard let typed: String = arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else { return nil }
        for subcommand in configuration.subcommands where subcommand.configuration.commandName == typed {
            return nil
        }
        return typed
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
