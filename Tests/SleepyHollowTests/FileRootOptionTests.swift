import ArgumentParser
import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// `--file-root <dir>`: the CLI spelling of ``LoadOptions/fileAccessRoot``.
///
/// The flag names a directory a `file:` page's own scripts may read, so the
/// value is checked against the file system at resolve time — a path that is
/// missing, or that names a file rather than a directory, is a usage error
/// rather than a load that silently grants nothing.
struct FileRootOptionTests {
    private static let noSteps: [ActionStep] = []

    private static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func `--file-root resolves to the directory's file URL`() throws {
        let directory: URL = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--file-root", directory.path])
        let options: LoadOptions = try flags.resolveLoadOptions(steps: Self.noSteps)
        let root: URL = try #require(options.fileAccessRoot)
        #expect(root.isFileURL)
        #expect(root.standardizedFileURL.path == directory.standardizedFileURL.path)
    }

    @Test func `no --file-root leaves the root unset`() throws {
        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [], injectWorld: nil, waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.fileAccessRoot == nil)
    }

    @Test func `a missing --file-root directory is a usage error`() throws {
        let missing = "/nonexistent-\(UUID().uuidString)"
        #expect(throws: SleepyError.self) {
            _ = try LoadFlagOptions.resolve(
                size: nil, theme: nil, jar: nil, injectPaths: [], injectWorld: nil, waitFor: nil,
                budgetMilliseconds: nil, confirm: nil, promptText: nil, fileRoot: missing,
                steps: Self.noSteps,
            )
        }
    }

    @Test func `a --file-root that names a file is a usage error`() throws {
        let directory: URL = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file: URL = directory.appendingPathComponent("not-a-directory.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: SleepyError.self) {
            _ = try LoadFlagOptions.resolve(
                size: nil, theme: nil, jar: nil, injectPaths: [], injectWorld: nil, waitFor: nil,
                budgetMilliseconds: nil, confirm: nil, promptText: nil, fileRoot: file.path,
                steps: Self.noSteps,
            )
        }
    }

    @Test func `--file-root shapes a load, so a session refuses it`() throws {
        let directory: URL = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--file-root", directory.path])
        #expect(PageExecution.loadShapingFlags(flags) == ["--file-root"])
        #expect(throws: SleepyError.self) {
            try PageExecution.requireSessionCompatible(flags)
        }
    }

    @Test func `--file-root reaches the session helper`() throws {
        let directory: URL = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let flags: LoadFlagOptions = try LoadFlagOptions.parse(["--file-root", directory.path])
        let forwarded: [String] = flags.sessionArguments(steps: Self.noSteps)
        let reparsed: LoadFlagOptions = try LoadFlagOptions.parse(forwarded)
        let options: LoadOptions = try reparsed.resolveLoadOptions(steps: Self.noSteps)
        let root: URL = try #require(options.fileAccessRoot)
        #expect(root.standardizedFileURL.path == directory.standardizedFileURL.path)
    }
}
