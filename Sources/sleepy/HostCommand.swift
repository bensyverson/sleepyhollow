import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy _host` — the helper process behind a named session.
///
/// Hidden from `--help` because no agent should ever type it: `sleepy open`
/// spawns it, and every other verb talks to it through the socket. It is the
/// same binary by design (the vision's one-binary claim), so a session costs
/// no second product and no bundled runtime.
///
/// It prints one line of JSON — the session's `SessionRecord` — the moment
/// the socket is listening and the page has loaded, so whoever spawned it can
/// wait for readiness without polling. Then it serves until a client shuts it
/// down or the idle TTL expires, and exits 0 having deleted its directory.
struct HostCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "_host",
        abstract: "Run the helper process that owns a named session's page.",
        discussion: """
        Internal: `sleepy open` spawns this. Prints the session record as JSON when ready.
        """,
        shouldDisplay: false,
    )

    @Option(name: .long, help: "The session name this helper answers to.")
    var name: String

    @Option(name: .long, help: "URL to load before the session accepts work.")
    var url: String?

    @Option(name: .long, help: "Seconds of idle time before the helper exits. Default 900.")
    var idleTimeout: Double?

    @Option(name: .long, help: "Registry root, overriding SLEEPYHOLLOW_HOME.")
    var home: String?

    @Flag(name: .long, help: "Install the fetch recorder before the first load, for `sleepy wire --session`.")
    var recordWire: Bool = false

    @OptionGroup var flags: LoadFlagOptions

    @MainActor
    mutating func run() async throws {
        let sessionName: SessionName = try resolveName()
        let steps: [ActionStep] = try ActionStepParser.parse(CommandLine.arguments)
        var options: LoadOptions = try flags.resolveLoadOptions(steps: steps)
        if recordWire {
            options = options.recordingWire()
        }
        let host = try SessionHost(
            name: sessionName,
            url: resolveURL(),
            options: options,
            registry: resolveRegistry(),
            operations: SessionOperations.registry,
            idleTimeout: resolveIdleTimeout(),
        )
        try await host.start()
        announceReady(host.record)
        detachFromSpawner()
        await host.waitUntilStopped()
    }

    /// Survives the process that spawned it.
    ///
    /// `sleepy open` reads this helper's standard output for the readiness
    /// line and then exits, which closes its end of the pipe. Anything the
    /// helper wrote afterwards — a Foundation warning is enough — would raise
    /// `SIGPIPE`, whose default action is to kill the process: the session
    /// would die moments after being opened, for no reason a user could see.
    private func detachFromSpawner() {
        signal(SIGPIPE, SIG_IGN)
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

    private func resolveURL() throws -> URL? {
        guard let url else { return nil }
        guard let resolved = URL(string: url), let scheme = resolved.scheme, !scheme.isEmpty else {
            throw SleepyError(
                kind: .usage,
                message: "'\(url)' has no scheme.",
                nextMove: "Add http:// or file://, e.g. 'http://\(url)'.",
            )
        }
        return resolved
    }

    /// Refuses a helper that could never reap itself.
    ///
    /// A session with no idle clock is a process nobody is left to stop —
    /// exactly the orphan the self-supervising design exists to prevent.
    private func resolveIdleTimeout() throws -> Double {
        guard let idleTimeout else { return SessionHost.defaultIdleTimeout }
        guard idleTimeout > 0 else {
            throw SleepyError(
                kind: .usage,
                message: "'--idle-timeout \(idleTimeout)' must be positive.",
                nextMove: "Every session reaps itself; give a number of seconds, e.g. --idle-timeout 900.",
            )
        }
        return idleTimeout
    }

    private func resolveRegistry() -> SessionRegistry {
        guard let home else { return SessionRegistry() }
        return SessionRegistry(root: URL(fileURLWithPath: home))
    }

    /// Writes the readiness line straight to the descriptor: `print` buffers
    /// when stdout is a pipe, which is exactly how the spawning process reads
    /// it, and a buffered readiness signal is no signal at all.
    private func announceReady(_ record: SessionRecord?) {
        guard let record else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let encoded: Data = try? encoder.encode(record) else { return }
        FileHandle.standardOutput.write(encoded + Data("\n".utf8))
    }
}
