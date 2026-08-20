import Foundation
@testable import SleepyCLIKit
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
}
