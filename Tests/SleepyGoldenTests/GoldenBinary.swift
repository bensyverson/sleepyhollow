import Foundation

/// One run of the built `sleepy` binary: its exit code and captured output.
struct CliInvocation {
    /// The process's termination status.
    let exitCode: Int32
    /// Everything written to standard output.
    let standardOutput: String
    /// Everything written to standard error.
    let standardError: String
}

/// Runs the built `sleepy` executable as a subprocess.
///
/// A SwiftPM executable target can't be imported into a test target, so the
/// golden suites shell out to the real binary — the only way to exercise
/// what an agent actually invokes.
enum GoldenBinary {
    /// Locates the build products directory that also holds the `sleepy`
    /// executable, by walking up from a candidate starting point until a
    /// sibling `sleepy` turns up.
    ///
    /// `swift test` runs the suite several directories below the shared
    /// products directory, and neither the exact nesting nor which process
    /// is actually running the tests is stable across toolchains — some
    /// pass `--test-bundle-path <bundle>` to a separate testing-helper
    /// process (where `CommandLine.arguments[0]` is the helper, not the
    /// bundle), others load the `.xctest` bundle in-process (where it shows
    /// up in `Bundle.allBundles`). Trying every candidate in turn is what
    /// makes this portable instead of tied to one toolchain's layout.
    static func productsDirectory() -> URL {
        for start in candidateStartingPoints() {
            if let found = searchUpward(from: start) {
                return found
            }
        }
        fatalError("Couldn't find a 'sleepy' binary above any of: \(candidateStartingPoints()).")
    }

    private static func candidateStartingPoints() -> [URL] {
        var points: [URL] = []

        if
            let index = CommandLine.arguments.firstIndex(of: "--test-bundle-path"),
            CommandLine.arguments.indices.contains(index + 1)
        {
            points.append(URL(fileURLWithPath: CommandLine.arguments[index + 1]).deletingLastPathComponent())
        }

        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            points.append(bundle.bundleURL.deletingLastPathComponent())
        }

        if let first = CommandLine.arguments.first {
            points.append(URL(fileURLWithPath: first).deletingLastPathComponent())
        }

        return points
    }

    private static func searchUpward(from start: URL) -> URL? {
        let fileManager = FileManager.default
        var directory = start
        while true {
            let candidate = directory.appendingPathComponent("sleepy")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return directory
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { return nil }
            directory = parent
        }
    }

    /// Runs `sleepy` with `arguments` and captures its exit code and output.
    static func run(_ arguments: [String]) throws -> CliInvocation {
        let process = Process()
        process.executableURL = productsDirectory().appendingPathComponent("sleepy")
        process.arguments = arguments

        let standardOutput = Pipe()
        let standardError = Pipe()
        process.standardOutput = standardOutput
        process.standardError = standardError

        try process.run()
        process.waitUntilExit()

        let outputData = standardOutput.fileHandleForReading.readDataToEndOfFile()
        let errorData = standardError.fileHandleForReading.readDataToEndOfFile()

        return CliInvocation(
            exitCode: process.terminationStatus,
            standardOutput: String(decoding: outputData, as: UTF8.self),
            standardError: String(decoding: errorData, as: UTF8.self),
        )
    }
}
