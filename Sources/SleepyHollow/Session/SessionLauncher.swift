import Foundation

/// Starts a session helper and waits for it to say it is ready — the half of
/// `sleepy open` that is behaviour rather than argument parsing.
///
/// There is no daemon to ask, so readiness is the helper's own announcement:
/// `sleepy _host` writes its ``SessionRecord`` as one line of JSON the moment
/// the socket is listening *and* the first page has loaded, then serves until
/// something stops it. This launcher spawns that process detached — the
/// helper outlives the invocation that started it, which is the entire point
/// of a session — and returns as soon as the line arrives.
///
/// A helper that dies instead of announcing (an unreachable URL, a name
/// somebody else claimed between the check and the spawn) is not a hang: the
/// launcher notices the exit, and hands back the child's own rendered failure
/// and exit code so `open` can pass them straight through.
///
/// ```swift
/// let launcher = SessionLauncher(executable: SessionLauncher.currentExecutable())
/// let record = try await launcher.launch(arguments: hostArguments, readyWithin: 30)
/// ```
public struct SessionLauncher: Sendable {
    /// How a helper failed before it ever announced itself.
    public struct LaunchFailure: Error, Sendable {
        /// The helper's exit code, for `open` to exit with in turn.
        public let exitCode: Int32
        /// Everything the helper wrote to standard error — already rendered
        /// by the same error path every other verb uses.
        public let standardError: String

        /// Creates a failure.
        public init(exitCode: Int32, standardError: String) {
            self.exitCode = exitCode
            self.standardError = standardError
        }
    }

    /// Collects a pipe's output off the reading queue.
    ///
    /// An actor rather than a lock: `readabilityHandler` fires on Foundation's
    /// own queue, and the polling side runs on the caller's — two isolation
    /// domains that must not share a buffer any other way.
    private actor Collector {
        private var data = Data()

        func append(_ more: Data) {
            data.append(more)
        }

        var text: String {
            String(decoding: data, as: UTF8.self)
        }

        /// The first complete line, if one has arrived.
        var firstLine: String? {
            guard let end: Data.Index = data.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
            return String(decoding: data[data.startIndex ..< end], as: UTF8.self)
        }
    }

    /// How often the launcher looks for the readiness line, in seconds.
    public static let pollInterval: TimeInterval = 0.05

    /// The binary to run `_host` with.
    public let executable: URL

    /// Creates a launcher over `executable`.
    public init(executable: URL) {
        self.executable = executable
    }

    /// This process's own binary, resolved to an absolute path.
    ///
    /// A session helper *is* `sleepy` — the vision's one-binary claim — so the
    /// only honest thing to spawn is the file currently running.
    public static func currentExecutable() -> URL {
        let argument0: String = CommandLine.arguments.first ?? "sleepy"
        let url = URL(fileURLWithPath: argument0)
        return url.standardizedFileURL.absoluteURL
    }

    /// Spawns `sleepy` with `arguments` and waits for its readiness line.
    ///
    /// - Parameters:
    ///   - arguments: the full `_host …` argument vector.
    ///   - environment: variables overlaid on this process's environment.
    ///   - readyWithin: seconds to wait for the announcement before giving up.
    /// - Returns: the record the helper announced.
    /// - Throws: ``LaunchFailure`` when the helper exited first, or a
    ///   ``SleepyError`` when it could not be started or never answered.
    public func launch(
        arguments: [String],
        environment: [String: String] = [:],
        readyWithin: TimeInterval,
    ) async throws -> SessionRecord {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        let announcements = Collector()
        let complaints = Collector()
        Self.collect(output, into: announcements)
        Self.collect(errors, into: complaints)

        do {
            try process.run()
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "Couldn't start a session helper from '\(executable.path)': \(error.localizedDescription).",
                nextMove: "Check the `sleepy` binary is where it was when this invocation started.",
            )
        }

        defer {
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
        }
        return try await waitForAnnouncement(
            from: process,
            announcements: announcements,
            complaints: complaints,
            readyWithin: readyWithin,
        )
    }

    private func waitForAnnouncement(
        from process: Process,
        announcements: Collector,
        complaints: Collector,
        readyWithin: TimeInterval,
    ) async throws -> SessionRecord {
        let deadline = Date().addingTimeInterval(readyWithin)
        while Date() < deadline {
            if let record: SessionRecord = await Self.decodeAnnouncement(announcements) {
                return record
            }
            if !process.isRunning {
                // The reading handlers run on their own queue; give whatever
                // the helper wrote on its way out a moment to land.
                try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 4 * 1_000_000_000))
                if let record: SessionRecord = await Self.decodeAnnouncement(announcements) {
                    return record
                }
                throw await LaunchFailure(
                    exitCode: process.terminationStatus,
                    standardError: complaints.text,
                )
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
        process.terminate()
        throw SleepyError(
            kind: .timeout,
            message: "The session helper did not report ready within \(Int(readyWithin))s.",
            nextMove: "Raise --budget, or check the page loads at all with `sleepy load <url>`.",
        )
    }

    private static func decodeAnnouncement(_ collector: Collector) async -> SessionRecord? {
        guard let line: String = await collector.firstLine, let data: Data = line.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(SessionRecord.self, from: data)
    }

    private static func collect(_ pipe: Pipe, into collector: Collector) {
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk: Data = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { await collector.append(chunk) }
        }
    }
}
