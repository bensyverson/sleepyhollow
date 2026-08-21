import Foundation
@testable import SleepyHollow
import Testing

/// The length-prefixed JSON framing the session socket carries.
@Suite("Session frame codec")
struct SessionFrameTests {
    @Test func `a request frame round-trips through the codec`() throws {
        let request: SessionRequest = try .operation(OperationEnvelope(ReadFactsOperation()))
        var buffer: Data = try SessionFrame.encode(request)
        let decoded: SessionRequest = try #require(SessionFrame.decode(SessionRequest.self, from: &buffer))
        #expect(decoded == request)
        #expect(buffer.isEmpty)
    }

    @Test func `a shutdown request round-trips`() throws {
        var buffer: Data = try SessionFrame.encode(SessionRequest.shutdown)
        let decoded: SessionRequest = try #require(SessionFrame.decode(SessionRequest.self, from: &buffer))
        #expect(decoded == .shutdown)
    }

    @Test func `an output reply carries the operation's JSON payload`() throws {
        let facts = PageFacts(finalURL: URL(string: "http://example.com/"), httpStatus: 200)
        let payload: Data = try JSONEncoder().encode(facts)
        var buffer: Data = try SessionFrame.encode(SessionReply.output(payload))
        let decoded: SessionReply = try #require(SessionFrame.decode(SessionReply.self, from: &buffer))
        guard case let .output(received) = decoded else {
            Issue.record("expected an output reply, got \(decoded)")
            return
        }
        #expect(try JSONDecoder().decode(PageFacts.self, from: received) == facts)
    }

    @Test func `a failure reply carries the error whole`() throws {
        let error = SleepyError(
            kind: .environment,
            message: "No session named 'ghost'.",
            nextMove: "`sleepy sessions list` shows the open sessions.",
        )
        var buffer: Data = try SessionFrame.encode(SessionReply.failure(error))
        let decoded: SessionReply = try #require(SessionFrame.decode(SessionReply.self, from: &buffer))
        #expect(decoded == .failure(error))
    }

    @Test func `decoding waits for the whole frame`() throws {
        let whole: Data = try SessionFrame.encode(SessionReply.acknowledged)
        var empty = Data()
        #expect(try SessionFrame.decode(SessionReply.self, from: &empty) == nil)
        var partial = Data(whole.dropLast())
        #expect(try SessionFrame.decode(SessionReply.self, from: &partial) == nil)
        #expect(partial.count == whole.count - 1)
    }

    @Test func `two frames in one buffer decode in order`() throws {
        var buffer: Data = try SessionFrame.encode(SessionRequest.operation(OperationEnvelope(ReadFactsOperation())))
        buffer += try SessionFrame.encode(SessionRequest.shutdown)
        let first: SessionRequest = try #require(SessionFrame.decode(SessionRequest.self, from: &buffer))
        let second: SessionRequest = try #require(SessionFrame.decode(SessionRequest.self, from: &buffer))
        if case .operation = first {} else {
            Issue.record("expected the operation frame first, got \(first)")
        }
        #expect(second == .shutdown)
        #expect(buffer.isEmpty)
    }

    @Test func `a frame claiming more than the ceiling is refused`() throws {
        var buffer = Data([0xFF, 0xFF, 0xFF, 0xFF])
        let thrown = #expect(throws: SleepyError.self) {
            _ = try SessionFrame.decode(SessionReply.self, from: &buffer)
        }
        #expect(try #require(thrown).exitStatus == .environment)
    }
}
