import Foundation
import Testing

/// Shared apparatus for the determinism suites: the pinned rendering
/// environment, the run-it-twice probe, and the byte-identity assertion.
///
/// Lives beside `GoldenBinary` rather than inside either suite, because both
/// `ByteStabilityGoldenTests` and `ArtifactDeterminismGoldenTests` state the
/// same contract: the same invocation emits the same bytes (vision doc,
/// Philosophy rules 1 and 5), measurements excepted.
enum GoldenDeterminism {
    /// The fixed rendering environment every determinism invocation pins:
    /// a named viewport and a named theme, so nothing ambient can move, plus
    /// the generous budget WebKit contention needs (see `project/gotchas.md`).
    static let rendering: [String] = [
        "--size", "1280x800",
        "--theme", "light",
        "--budget", "60000",
    ]

    /// Runs one argument vector twice, each in its own fresh subprocess —
    /// the only honest way to ask whether *the invocation* is deterministic
    /// rather than whether one process is.
    static func twice(_ arguments: [String]) async throws -> (CliInvocation, CliInvocation) {
        let first: CliInvocation = try await GoldenBinary.runOffPool(arguments)
        let second: CliInvocation = try await GoldenBinary.runOffPool(arguments)
        return (first, second)
    }

    /// Asserts the pair succeeded and emitted the same bytes on both streams.
    static func expectStable(
        _ pair: (CliInvocation, CliInvocation),
        sourceLocation: SourceLocation = #_sourceLocation,
    ) {
        #expect(pair.0.exitCode == 0, sourceLocation: sourceLocation)
        #expect(pair.1.exitCode == 0, sourceLocation: sourceLocation)
        #expect(pair.0.standardOutput == pair.1.standardOutput, sourceLocation: sourceLocation)
        #expect(pair.0.standardError == pair.1.standardError, sourceLocation: sourceLocation)
    }
}
