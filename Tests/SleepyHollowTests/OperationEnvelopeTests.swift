import Foundation
@testable import SleepyHollow
import Testing

/// A minimal operation standing in for the real verbs.
private struct ProbeOperation: PageOperation {
    struct Output: Friendly {
        let echoed: String
    }

    static let kind = "probe"

    let message: String
}

/// Covers the envelope + registry seam the session layer ships verbs through.
struct OperationEnvelopeTests {
    @Test func `envelope carries the operation kind`() throws {
        let envelope = try OperationEnvelope(ProbeOperation(message: "hello"))
        #expect(envelope.kind == "probe")
    }

    @Test func `registry decodes an envelope back to the original operation`() throws {
        var registry = OperationRegistry()
        registry.register(ProbeOperation.self)

        let original = ProbeOperation(message: "round trip")
        let decoded = try registry.decode(OperationEnvelope(original))
        let probe = try #require(decoded as? ProbeOperation)
        #expect(probe == original)
    }

    @Test func `envelope survives JSON transport`() throws {
        var registry = OperationRegistry()
        registry.register(ProbeOperation.self)

        let original = ProbeOperation(message: "over the socket")
        let wire: Data = try JSONEncoder().encode(OperationEnvelope(original))
        let received: OperationEnvelope = try JSONDecoder().decode(OperationEnvelope.self, from: wire)
        let probe = try #require(try registry.decode(received) as? ProbeOperation)
        #expect(probe == original)
    }

    @Test func `unknown kind throws a teaching environment error`() throws {
        let registry = OperationRegistry()
        let envelope = try OperationEnvelope(ProbeOperation(message: "nobody home"))

        let thrown = #expect(throws: SleepyError.self) {
            _ = try registry.decode(envelope)
        }
        let error = try #require(thrown)
        #expect(error.exitStatus == .environment)
        #expect(error.message.contains("probe"))
    }
}
