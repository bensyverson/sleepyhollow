import Foundation
import SleepyHollow
import Testing
import TestSupport

/// `createWebArchiveData` is a completion handler with no timeout of its own:
/// it waits on the content process, so a page parked on synchronous work
/// left `sleepy archive` suspended for as long as the park lasted — forever,
/// for a process that had stalled. The archive now answers within the host's
/// ``PageHost/callBudget`` or times out.
///
/// The bound asserted is "this ends", never "this was fast" — nothing is
/// compared with the elapsed time (`project/2026-08-28-wait-test-timing.md`).
@Suite("ArchiveOperation deadline")
struct ArchiveDeadlineTests {
    @Test
    @MainActor
    func `an archive the page cannot answer in time times out at the host's call budget and abandons the host`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let gate = FixtureGate()
            await gate.install(on: server)
            var options = LoadOptions()
            options.callBudget = 0.5
            let host = PageHost(options: options)
            try await PageHostDeadlineTests.navigate(host, to: #require(URL(string: "static.html", relativeTo: base)))
            await PageHostDeadlineTests.park(host.webView, until: gate)
            do {
                _ = try await host.execute(ArchiveOperation())
                Issue.record("expected a timeout")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.message.contains("archive"), "the timeout must name the call: \(error.message)")
                #expect(error.message.contains("0.5s"), "the timeout must name its budget: \(error.message)")
            }
            #expect(host.abandonedCall?.reason == .deadline(0.5))
            await gate.open()
        }
    }
}
