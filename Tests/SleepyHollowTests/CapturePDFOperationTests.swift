import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("PDFOperation")
struct CapturePDFOperationTests {
    @Test
    @MainActor
    func `pdf output starts with the PDF magic bytes and is non-trivial`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let output = try await host.execute(PDFOperation())
            #expect(output.pdf.count > 512)
            let header = output.pdf.prefix(5)
            #expect(header == Data("%PDF-".utf8))
        }
    }

    @Test func `the operation is Friendly and round-trips through its envelope`() throws {
        #expect(PDFOperation.kind == "pdf")
        let envelope = try OperationEnvelope(PDFOperation())
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(OperationEnvelope.self, from: data)
        #expect(decoded.kind == PDFOperation.kind)
        var registry = OperationRegistry()
        registry.register(PDFOperation.self)
        let operation = try registry.decode(decoded)
        #expect(operation is PDFOperation)
    }
}
