import Foundation

/// The environment diagnosis behind `sleepy doctor`: four questions asked in
/// order, each answering with a ``DoctorCheck`` that teaches on failure.
///
/// The order is deliberate — the running binary, then WebKit under the
/// current sandbox, then the sessions directory, then the temp directory. It
/// runs cheapest and most fundamental first, so the *first* failure is nearly
/// always the cause and the rest are symptoms; the CLI throws that one.
///
/// Every check is separately callable, and every one takes its subject as a
/// parameter, so a caller can diagnose an environment other than this
/// process's own and a test can prove both the pass and the fail.
///
/// ```swift
/// let report = await Doctor.run()
/// if let error = report.error { throw error }
/// ```
public enum Doctor {
    /// The page ``checkWebKit(budget:)`` loads.
    ///
    /// `about:blank` needs no network and no server, and WebKit still needs
    /// its web content process to render nothing — which is exactly the fact
    /// under test.
    public static let probeURL: URL = .init(string: "about:blank")!

    /// The session name ``checkSessions(registry:)`` measures a socket path
    /// against. Nothing is created for it; it is a ruler, not a session.
    public static let sampleSessionName: SessionName = .init("doctor")!

    /// The directory ``checkTemporaryDirectory(_:)`` probes by default:
    /// Foundation's own answer, which on macOS is Darwin's per-user temp
    /// directory — *not* whatever `$TMPDIR` says.
    ///
    /// The two really can be different places, so which one is checked
    /// matters. Measured 2026-08-28 with a `swiftc` probe run inside Claude
    /// Code's Bash sandbox: with `TMPDIR=/tmp/claude-501` exported, both
    /// `NSTemporaryDirectory()` and `FileManager.default.temporaryDirectory`
    /// still answered `/var/folders/…/T`. Foundation resolves the directory
    /// itself and ignores the variable, so this checks the directory
    /// Foundation and WebKit will actually use — and the next move on a
    /// failure must not tell anyone to set `TMPDIR`, which would change
    /// nothing.
    public static var defaultTemporaryDirectory: URL {
        FileManager.default.temporaryDirectory
    }

    /// The ceiling ``checkWebKit(budget:)`` gives the probe load, in seconds.
    ///
    /// Far shorter than ``LoadOptions/defaultBudget``: a content process that
    /// can launch renders `about:blank` immediately, and one that cannot is
    /// reported the moment WebKit says so — so a long wait here would only
    /// ever be a slow way to say the same thing.
    public static let defaultBudget: TimeInterval = 10

    /// Runs every check, in diagnosis order.
    ///
    /// - Parameters:
    ///   - registry: the session registry to diagnose; the default honours
    ///     `SLEEPYHOLLOW_HOME`.
    ///   - temporaryDirectory: the temp directory to diagnose.
    ///   - budget: seconds the WebKit launch check may take.
    @MainActor
    public static func run(
        registry: SessionRegistry = SessionRegistry(),
        temporaryDirectory: URL = Doctor.defaultTemporaryDirectory,
        budget: TimeInterval = defaultBudget,
    ) async -> DoctorReport {
        let webKit: DoctorCheck = await checkWebKit(budget: budget)
        return DoctorReport(checks: [
            checkBinary(),
            webKit,
            checkSessions(registry: registry),
            checkTemporaryDirectory(temporaryDirectory),
        ])
    }

    // MARK: - The checks

    /// Whether `executable` is a file this process could run — and therefore
    /// whether `sleepy open` could spawn a session helper from it.
    ///
    /// The helper *is* `sleepy` (see ``SessionLauncher/currentExecutable()``),
    /// so binary resolution and helper resolution are one question, and
    /// answering it means naming the path: an agent that installed two copies
    /// learns here which one is running.
    public static func checkBinary(executable: URL = SessionLauncher.currentExecutable()) -> DoctorCheck {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            return .failed(
                .binary,
                "The running executable resolves to '\(executable.path)', which is not an executable file.",
                nextMove: "Rebuild with `swift build`, or reinstall sleepy — `sleepy open` spawns its session "
                    + "helper from this same path.",
            )
        }
        return .passed(
            .binary,
            "Running from '\(executable.path)'; `sleepy open` spawns its session helper from that same file.",
        )
    }

    /// Whether WebKit can start its web content process under the current
    /// sandbox.
    ///
    /// The check every other verb depends on, and the one an agent hits
    /// first: a denied launch is reported as
    /// ``WebContentProcessFailure/neverLaunched``, whose own error supplies
    /// both the message and the next move so `doctor` and a failed `load` say
    /// the same words.
    @MainActor
    public static func checkWebKit(budget: TimeInterval = defaultBudget) async -> DoctorCheck {
        let host = PageHost(options: LoadOptions(budget: budget))
        do {
            _ = try await host.load(probeURL)
            return .passed(.webKit, "WebKit launched its web content process and rendered \(probeURL.absoluteString).")
        } catch {
            if let failure: WebContentProcessFailure = host.contentProcessFailure {
                return .failed(.webKit, failure.error(url: probeURL))
            }
            if let sleepy = error as? SleepyError {
                return .failed(.webKit, sleepy)
            }
            return .failed(
                .webKit,
                "WebKit could not load \(probeURL.absoluteString): \(error.localizedDescription)",
                nextMove: "Run `sleepy load \(probeURL.absoluteString)` to see the failure on its own.",
            )
        }
    }

    /// Whether `registry`'s sessions directory can be created and written,
    /// and whether a session's socket path would still fit what the kernel
    /// can address.
    ///
    /// The length question is asked because it cannot be asked later: a path
    /// over ``SocketProbe/maximumPathLength`` bytes is refused at `open`
    /// time, and an agent with a long `SLEEPYHOLLOW_HOME` would otherwise
    /// only find out when its first session failed.
    ///
    /// - Note: this creates the sessions directory when it is missing — the
    ///   same thing `sleepy open` does, and the only honest way to prove it
    ///   is writable.
    public static func checkSessions(registry: SessionRegistry = SessionRegistry()) -> DoctorCheck {
        let directory: URL = registry.sessionsDirectory
        do {
            try probeWritable(directory)
        } catch {
            return .failed(
                .sessions,
                "Could not write to the sessions directory '\(directory.path)': \(error.localizedDescription)",
                nextMove: "Point \(SessionRegistry.homeEnvironmentVariable) at a directory you can write.",
            )
        }
        do {
            let socket: String = try registry.socketPath(for: sampleSessionName)
            return .passed(
                .sessions,
                "Sessions live in '\(directory.path)', which is writable; '\(sampleSessionName)' would bind a "
                    + "\(socket.utf8.count)-byte socket path of the \(SocketProbe.maximumPathLength) available.",
            )
        } catch let error as SleepyError {
            return .failed(.sessions, error)
        } catch {
            return .failed(
                .sessions,
                "Could not resolve a socket path under '\(directory.path)': \(error.localizedDescription)",
                nextMove: "Point \(SessionRegistry.homeEnvironmentVariable) at a shorter directory.",
            )
        }
    }

    /// Whether `directory` — ``defaultTemporaryDirectory`` by default — can
    /// be written.
    ///
    /// `sleepy` itself stages nothing here; WebKit, Foundation and every
    /// `--out $TMPDIR/shot.png` an agent writes do. It is the one place an
    /// agent assumes it can write without asking, so a sandbox that took it
    /// away is worth naming before it turns into a failure with somebody
    /// else's name on it.
    public static func checkTemporaryDirectory(
        _ directory: URL = Doctor.defaultTemporaryDirectory,
    ) -> DoctorCheck {
        do {
            try probeWritable(directory)
        } catch {
            return .failed(
                .temporaryDirectory,
                "Could not write to the temp directory '\(directory.path)': \(error.localizedDescription)",
                nextMove: "Run the command outside the sandbox, or allow writes to that directory — Foundation "
                    + "picks it itself and ignores $TMPDIR, so exporting one changes nothing.",
            )
        }
        return .passed(.temporaryDirectory, "The temp directory '\(directory.path)' is writable.")
    }

    // MARK: - Probing

    /// Creates `directory` if it is missing, then writes and removes one file
    /// inside it — the only test of writability that cannot be wrong.
    ///
    /// `isWritableFile(atPath:)` answers from the permission bits, which a
    /// read-only mount, a full disk or a sandbox will all cheerfully
    /// contradict.
    private static func probeWritable(_ directory: URL) throws {
        let manager: FileManager = .default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let probe: URL = directory.appendingPathComponent("sleepy-doctor-\(UUID().uuidString)")
        try Data("sleepy doctor".utf8).write(to: probe)
        try manager.removeItem(at: probe)
    }
}
