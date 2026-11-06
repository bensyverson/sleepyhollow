import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `--viewport` is the same flag as `--size`, end to end through the binary.
///
/// `--budget 60000` throughout: see ``CaptureGoldenTests``.
@Suite(.serialized)
struct ViewportAliasGoldenTests {
    @Test func `shot --viewport writes the same PNG as shot --size`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("capture-breakpoint.html").absoluteString
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("viewport-alias-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }

            let canonical = directory.appendingPathComponent("size.png")
            let aliased = directory.appendingPathComponent("viewport.png")
            let first = try await GoldenBinary.runOffPool([
                "shot", url, "--size", "390x600", "--budget", "60000", "--out", canonical.path,
            ])
            #expect(first.exitCode == 0, "stderr: \(first.standardError)")
            let second = try await GoldenBinary.runOffPool([
                "shot", url, "--viewport", "390x600", "--budget", "60000", "--out", aliased.path,
            ])
            #expect(second.exitCode == 0, "stderr: \(second.standardError)")
            #expect(try Data(contentsOf: canonical) == Data(contentsOf: aliased))
        }
    }

    @Test func `another loading verb accepts --viewport`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let url = baseURL.appendingPathComponent("static.html").absoluteString
            let result = try await GoldenBinary.runOffPool([
                "dom", url, "--viewport", "480", "--budget", "60000",
            ])
            #expect(result.exitCode == 0, "stderr: \(result.standardError)")
        }
    }

    @Test func `help names --viewport as the same flag`() async throws {
        let result = try await GoldenBinary.runOffPool(["shot", "--help"])
        #expect(result.standardOutput.contains("--viewport"))
    }
}
