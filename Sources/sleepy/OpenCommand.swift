import ArgumentParser
import Darwin
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy open <url> --name <n>` — claim a name and keep the page alive.
///
/// A session is a helper process that owns one web view and answers over a
/// Unix socket, so a multi-step flow — open, log in, navigate, assert,
/// screenshot — survives across separate invocations. Naming is the opt-in to
/// state: nothing is running until something is named.
///
/// Because `open` performs a load, it takes the loading options (`--size`,
/// `--theme`, `--jar`, `--inject`, `--inject-world`, `--wait-for`, the dialog
/// flags) and hands them to the helper, where they shape every page that
/// session ever loads.
/// This is the *only* place they can be given: a `--session` invocation later
/// refuses them rather than pretending to apply them.
///
/// If the name is already open, `open` fails loudly (exit 5): silently reusing
/// another flow's cookies, scripts and history is the ambient state the tool
/// exists to refuse. A name whose helper is *dead* is reaped and reused.
struct OpenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open a named session: a helper process holding one live page.",
        discussion: """
        The session outlives this invocation. Every page verb then takes --session <name>, and `sleepy close <name>` ends it; a forgotten session reaps itself on its idle TTL.

        This is the only place the loading options can be given: a --session invocation later refuses them rather than pretending to apply them.

        Examples:
          sleepy open http://localhost:3000/login --name login
          sleepy open http://localhost:3000/ --name app --size 1440x900 --jar login
          sleepy open http://localhost:3000/app --name app --wait-for '#ready'
          sleepy open http://localhost:3000/app --name app --record-wire

        Exit codes: 0 success, 2 usage, 3 the helper never reported ready, 4 load failure, 5 the name is already open.
        """,
    )

    /// Extra seconds beyond the load's budget allowed for spawning the helper
    /// and binding its socket — process start-up is not page time.
    static let spawnAllowance: TimeInterval = 10

    @Argument(help: "The URL the session opens on (needs a scheme).")
    var url: String

    @Option(name: .long, help: "The name that claims this session.")
    var name: String

    @Option(name: .long, help: "Seconds of idle time before the helper exits by itself. Default 900.")
    var idleTimeout: Double?

    @Flag(name: .long, help: "Install the fetch recorder, so `sleepy wire --session` can see exchanges.")
    var recordWire: Bool = false

    @OptionGroup var flags: LoadFlagOptions
    @OptionGroup var out: OutOption
    @OptionGroup var quiet: QuietOption

    @MainActor
    mutating func run() async throws {
        let sessionName: SessionName = try resolveName()
        let target: URL = try resolveURL()
        let registry = SessionRegistry()
        try claim(sessionName, in: registry)

        let launcher = SessionLauncher(executable: SessionLauncher.currentExecutable())
        let steps: [ActionStep] = try ActionStepParser.parse(CommandLine.arguments)
        do {
            _ = try await launcher.launch(
                arguments: hostArguments(name: sessionName, url: target, registry: registry, steps: steps),
                readyWithin: (flags.budget.map { TimeInterval($0) / 1000 } ?? LoadOptions.defaultBudget)
                    + Self.spawnAllowance,
            )
        } catch let failure as SessionLauncher.LaunchFailure {
            passThrough(failure)
        }

        let client = SessionClient(name: sessionName, registry: registry)
        let facts: PageFacts = try await client.run(NavigateOperation(url: nil))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try out.sink.write(encoder.encode(facts))
    }

    /// Refuses a live name, and reaps a dead one on the way past.
    ///
    /// Reaping here is the lazy cleanup the design turns on: nothing watches
    /// the fleet, so the next `open` is what clears the last crash.
    private func claim(_ sessionName: SessionName, in registry: SessionRegistry) throws {
        switch registry.liveness(of: sessionName) {
        case .live:
            throw registry.alreadyOpen(sessionName)
        case .noRecord:
            return
        case .deadProcess, .unreachableSocket:
            registry.remove(sessionName)
        }
    }

    /// The `_host` argument vector: the session's identity, its URL, and every
    /// loading option this invocation carried.
    private func hostArguments(
        name sessionName: SessionName,
        url target: URL,
        registry: SessionRegistry,
        steps: [ActionStep],
    ) -> [String] {
        var arguments: [String] = [
            "_host",
            "--name", sessionName.rawValue,
            "--url", target.absoluteString,
            "--home", registry.root.path,
        ]
        if let idleTimeout {
            arguments += ["--idle-timeout", String(idleTimeout)]
        }
        if recordWire {
            arguments.append("--record-wire")
        }
        if let size: String = flags.size {
            arguments += ["--size", size]
        }
        if let theme: ColorTheme = flags.theme {
            arguments += ["--theme", theme.rawValue]
        }
        if let jar: JarName = flags.jar {
            arguments += ["--jar", jar.rawValue]
        }
        for path in flags.inject {
            arguments += ["--inject", path]
        }
        if let injectWorld: InjectedScript.World = flags.injectWorld {
            arguments += ["--inject-world", injectWorld.rawValue]
        }
        if let waitFor: String = flags.waitFor {
            arguments += ["--wait-for", waitFor]
        }
        if let budget: Int = flags.budget {
            arguments += ["--budget", String(budget)]
        }
        if let confirm: LoadFlagOptions.DialogChoice = flags.confirm {
            arguments += ["--confirm", confirm.rawValue]
        }
        if let promptText: String = flags.promptText {
            arguments += ["--prompt-text", promptText]
        }
        return arguments + steps.flatMap(Self.arguments(for:))
    }

    /// One ordered action step, back in its flag form for the helper.
    private static func arguments(for step: ActionStep) -> [String] {
        switch step {
        case let .click(selector): ["--click", selector]
        case let .fill(selector, value): ["--fill", "\(selector)=\(value)"]
        case let .submit(selector): ["--submit", selector]
        }
    }

    /// Hands the helper's own rendered failure and exit code to the caller.
    ///
    /// The helper renders errors through the same path every verb uses, so
    /// re-wrapping it would only bury the page's real complaint.
    private func passThrough(_ failure: SessionLauncher.LaunchFailure) -> Never {
        var text: String = failure.standardError
        if text.isEmpty {
            text = "The session helper exited \(failure.exitCode) without saying why.\n"
        }
        FileHandle.standardError.write(Data(text.utf8))
        Darwin.exit(failure.exitCode == 0 ? ExitStatus.environment.rawValue : failure.exitCode)
    }

    private func resolveName() throws -> SessionName {
        guard let sessionName = SessionName(name) else {
            throw SleepyError(
                kind: .usage,
                message: "'\(name)' is not a valid session name.",
                nextMove: "Start with a letter or digit, then letters, digits, '.', '_', or '-'.",
            )
        }
        return sessionName
    }

    private func resolveURL() throws -> URL {
        guard let resolved = URL(string: url), let scheme = resolved.scheme, !scheme.isEmpty else {
            throw SleepyError(
                kind: .usage,
                message: "'\(url)' has no scheme.",
                nextMove: "Add http:// or file://, e.g. 'http://\(url)'.",
            )
        }
        return resolved
    }
}
