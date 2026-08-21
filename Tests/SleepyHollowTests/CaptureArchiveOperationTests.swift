import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("ArchiveOperation")
struct CaptureArchiveOperationTests {
    @Test
    @MainActor
    func `archive output is a parseable webarchive plist containing the main resource`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            let url = URL(string: "capture-tall.html", relativeTo: base)!
            _ = try await host.load(url)
            let output = try await host.execute(ArchiveOperation())
            #expect(!output.archive.isEmpty)

            let plist = try #require(
                try PropertyListSerialization.propertyList(from: output.archive, format: nil) as? [String: Any],
            )
            let mainResource = try #require(plist["WebMainResource"] as? [String: Any])
            let resourceURL = try #require(mainResource["WebResourceURL"] as? String)
            #expect(resourceURL == url.absoluteString)
            let resourceData = try #require(mainResource["WebResourceData"] as? Data)
            #expect(!resourceData.isEmpty)
        }
    }

    @Test func `the operation is Friendly and round-trips through its envelope`() throws {
        #expect(ArchiveOperation.kind == "archive")
        let envelope = try OperationEnvelope(ArchiveOperation())
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(OperationEnvelope.self, from: data)
        #expect(decoded.kind == ArchiveOperation.kind)
        var registry = OperationRegistry()
        registry.register(ArchiveOperation.self)
        let operation = try registry.decode(decoded)
        #expect(operation is ArchiveOperation)
    }
}
