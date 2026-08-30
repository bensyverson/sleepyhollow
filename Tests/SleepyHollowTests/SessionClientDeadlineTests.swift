import Foundation
@testable import SleepyHollow
import Testing

/// The client's own clock: a helper that accepts a request and never answers
/// must cost the client its budget, not its life.
///
/// The field failure this pins (2026-08-29, job issue MN69b): three
/// `sleepy _host` helpers parked their main thread under machine-wide load and
/// their `shot --session` / `find --session` clients waited 7–11 minutes with
/// no reply and no timeout. Every bound here is an *upper* bound — "this must
/// end" — never a claim that the host beat a clock.
@Suite("Session client deadline")
struct SessionClientDeadlineTests {
    /// Long enough that a loaded Mac cannot fail it by being slow, short
    /// enough that a hang is still a red rather than a wedged suite.
    private static let mustEndWithin: TimeInterval = 120

    @Test func `a helper that never answers fails the client with a timeout`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("stalled"))
        // The record says 30s; the invocation says 1. The invocation wins, and
        // the test is over in about three seconds rather than thirty-two.
        let helper = try await StalledSessionHelper.start(name: name, in: registry)
        defer { helper.stop() }

        let client = SessionClient(name: name, registry: registry, budget: 1)
        let started = Date()
        let thrown: SleepyError? = await #expect(throws: SleepyError.self) {
            _ = try await client.run(ReadFactsOperation())
        }
        let elapsed: TimeInterval = Date().timeIntervalSince(started)

        let error: SleepyError = try #require(thrown)
        #expect(error.kind == .timeout)
        #expect(error.message.contains("stalled"))
        #expect(error.message.contains(ReadFactsOperation.kind))
        #expect(error.nextMove?.contains("sleepy sessions list") == true)
        #expect(error.nextMove?.contains("sleepy close stalled") == true)
        #expect(elapsed < Self.mustEndWithin, "the client waited \(elapsed)s on a helper that never replied")
    }

    @Test func `shutdown is bounded too`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("mute"))
        let helper = try await StalledSessionHelper.start(name: name, in: registry)
        defer { helper.stop() }

        let client = SessionClient(name: name, registry: registry, budget: 1)
        let started = Date()
        let thrown: SleepyError? = await #expect(throws: SleepyError.self) {
            try await client.shutdown()
        }
        let elapsed: TimeInterval = Date().timeIntervalSince(started)
        #expect(try #require(thrown).kind == .timeout)
        #expect(elapsed < Self.mustEndWithin)
    }

    @Test func `the deadline is the budget plus a transport margin`() throws {
        let name: SessionName = try #require(SessionName("clocked"))
        #expect(SessionClient(name: name, budget: 12).budget == 12)
        #expect(SessionClient(name: name).budget == nil, "no --budget defers to the session's own")
        #expect(SessionClient.deadline(forBudget: 12) == 12 + SessionClient.transportMargin)
    }

    /// The bug the first full-suite run of this change caught: the client
    /// defaulted to 30 s while the helper had been opened with `--budget
    /// 60000`, so a session working inside its own budget was reported as
    /// wedged. The number in the error is the proof of which clock was read.
    @Test func `a client with no --budget takes the session's recorded one`() async throws {
        let root = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        let registry = SessionRegistry(root: root)
        let name: SessionName = try #require(SessionName("patient"))
        let helper = try await StalledSessionHelper.start(name: name, in: registry, budget: 1)
        defer { helper.stop() }
        #expect(try #require(registry.record(for: name)).budget == 1)

        let started = Date()
        let thrown: SleepyError? = await #expect(throws: SleepyError.self) {
            _ = try await SessionClient(name: name, registry: registry).run(ReadFactsOperation())
        }
        let error: SleepyError = try #require(thrown)
        #expect(error.kind == .timeout)
        #expect(error.message.contains("1s budget"), "got: \(error.message)")
        #expect(Date().timeIntervalSince(started) < Self.mustEndWithin)
    }
}
