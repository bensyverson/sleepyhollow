import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// With the page's scripts off, whether an action started a navigation is
/// judged by the host from the navigation delegate, ordered after the action
/// rather than polled against a grace period (issue `OI4gWa`).
///
/// The form's target is a ``FixtureGate`` the test never opens, so the
/// navigation can start but cannot finish: what is asserted is the start.
@Suite("Navigation start", .serialized)
struct NavigationStartTests {
    @MainActor
    private func host(_ server: FixtureServer, _ base: URL) async throws -> (PageHost, FixtureGate) {
        let gate = FixtureGate()
        await gate.install(on: server)
        let host = PageHost(options: LoadOptions(pageScripts: .disabled))
        _ = try await host.load(#require(URL(string: "no-js-gated-form.html", relativeTo: base)))
        return (host, gate)
    }

    @Test
    @MainActor
    func `a click that submits reports the navigation it started`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let (host, gate) = try await host(server, base)
            let outcome: ActionOutcome = try await host.execute(ClickOperation(selector: "#send"))
            #expect(outcome.startedNavigation)
            await gate.open()
        }
    }

    @Test
    @MainActor
    func `a click that does nothing reports no navigation`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let (host, gate) = try await host(server, base)
            let outcome: ActionOutcome = try await host.execute(ClickOperation(selector: "#stay"))
            #expect(outcome.startedNavigation == false)
            #expect(await gate.requestCount == 0)
            await gate.open()
        }
    }

    @Test
    @MainActor
    func `the host counts main-frame navigation requests as the delegate decides them`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let (host, gate) = try await host(server, base)
            let before: Int = host.navigationRequestCount
            _ = try await host.execute(SubmitOperation(selector: "#gated"))
            #expect(host.navigationRequestCount == before + 1)
            await gate.open()
        }
    }
}
