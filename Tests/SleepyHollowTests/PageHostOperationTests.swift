import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

@Suite("PageHost operation seam")
struct PageHostOperationTests {
    @Test
    @MainActor
    func `an executable operation runs against the host and returns its output`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            let url = URL(string: "static.html", relativeTo: base)!
            _ = try await host.load(url)
            let facts: PageFacts = try await host.execute(ReadFactsOperation())
            #expect(facts.finalURL?.absoluteString == url.absoluteURL.absoluteString)
            #expect(facts.httpStatus == 200)
        }
    }

    @Test
    func `the operation is a Friendly value that round-trips through its envelope`() throws {
        #expect(ReadFactsOperation.kind == "readFacts")
        let envelope: OperationEnvelope = try OperationEnvelope(ReadFactsOperation())
        let data: Data = try JSONEncoder().encode(envelope)
        let decoded: OperationEnvelope = try JSONDecoder().decode(OperationEnvelope.self, from: data)
        #expect(decoded.kind == ReadFactsOperation.kind)
        var registry = OperationRegistry()
        registry.register(ReadFactsOperation.self)
        #expect(try registry.decode(decoded) is ReadFactsOperation)
    }
}
