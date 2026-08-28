import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// `--out <file>` resolves to a file sink; its absence resolves to standard
/// output.
struct OutputSinkTests {
    @Test func `no path resolves to standard output`() {
        let sink = OutputSink(path: nil)
        #expect(sink.destination == .standardOutput)
    }

    @Test func `a path resolves to a file destination`() {
        let sink = OutputSink(path: "/tmp/out.txt")
        #expect(sink.destination == .file(URL(fileURLWithPath: "/tmp/out.txt")))
    }

    @Test func `writing text to a file sink writes UTF-8 bytes`() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }

        let sink = OutputSink(path: file.path)
        try sink.write("hello")

        let written = try String(contentsOf: file, encoding: .utf8)
        #expect(written == "hello")
    }

    @Test func `writing to a file in a missing directory creates the directory`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("shot.png")

        let sink = OutputSink(path: file.path)
        try sink.write(Data([0x89, 0x50]))

        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(try Data(contentsOf: file) == Data([0x89, 0x50]))
    }

    @Test func `writing to a file several missing directories deep creates every level`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("a/b/c/shot.png")

        let sink = OutputSink(path: file.path)
        try sink.write("bytes")

        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func `a parent path that is an ordinary file names the directory, not the file`() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: blocker) }
        try Data("not a directory".utf8).write(to: blocker)
        let file = blocker.appendingPathComponent("shot.png")

        let sink = OutputSink(path: file.path)
        do {
            try sink.write("bytes")
            Issue.record("expected writing below an ordinary file to throw")
        } catch let error as SleepyError {
            #expect(error.message.contains(blocker.path))
            #expect(!error.message.contains("shot.png"))
            #expect(error.exitStatus == ExitStatus.environment)
        }
    }

    @Test func `an existing directory is left alone`() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("shot.png")

        try OutputSink(path: file.path).write("first")
        try OutputSink(path: file.path).write("second")

        #expect(try String(contentsOf: file, encoding: .utf8) == "second")
    }
}
