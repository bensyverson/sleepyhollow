import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// A step that starts a navigation is waited for on the navigation
/// delegate's own signals — the commit, or the provisional failure WebKit
/// reports for a navigation it decided and then dropped — rather than on a
/// fixed window for the navigation to start (issue `7mWLWK`, the class of
/// `OI4gWa`).
///
/// What lost the old 0.5 s window is a navigation the host has been asked to
/// decide but that has not started yet: `isLoading` is still false and the
/// old document still answers. Measured 2026-11-06 (`NavigationSignalMeasurementTests`),
/// a cross-site link leaves that gap open 60–80 ms on an idle Mac while
/// WebKit swaps web content processes, and a loaded one stretches it past
/// any fixed window. The test holds the decision itself for a second through
/// ``PageHostDelegate/holdDecision``, which reproduces the gap on any machine.
@Suite("Step navigation settle", .serialized)
struct StepNavigationSettleTests {
    /// The page the link lands on.
    private static let landing: String = "<!doctype html><title>Landed</title><p id=landed>landed</p>"

    /// Longer than any start window the settle could plausibly bet on.
    private static let heldStart: TimeInterval = 1.5

    @MainActor
    private func host(steps: [ActionStep], scripts: LoadOptions.PageScripts = .enabled) -> PageHost {
        var options = LoadOptions(pageScripts: scripts)
        options.steps = steps
        options.budget = TestSupport.livenessBudget
        return PageHost(options: options)
    }

    private static func registerLanding(on server: FixtureServer) async {
        await server.register(path: "/landing") { _ in
            FixtureResponse(status: 200, contentType: .html, body: Data(Self.landing.utf8))
        }
    }

    /// Holds the decision for `/landing` for ``heldStart`` seconds; every
    /// other navigation is allowed at once.
    @MainActor
    private static func holdLandingStart(on host: PageHost) {
        host.delegate.holdDecision = { url, allow in
            guard url?.path == "/landing" else { return allow() }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(heldStart * 1_000_000_000))
                allow()
            }
        }
    }

    @Test(arguments: [LoadOptions.PageScripts.enabled, .disabled])
    @MainActor
    func `a click whose navigation starts late is read on the page it lands on`(
        scripts: LoadOptions.PageScripts,
    ) async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await Self.registerLanding(on: server)
            let host = host(steps: [.click(selector: "#here")], scripts: scripts)
            Self.holdLandingStart(on: host)
            _ = try await host.load(URL(string: "step-navigation.html", relativeTo: base)!)
            #expect(host.facts.finalURL?.path == "/landing")
            let title: String = try await host.evaluate("return document.title;", as: String.self, in: .isolated)
            #expect(title == "Landed")
        }
    }

    /// A `204` is decided, starts, and ends in a provisional failure without
    /// committing: the settle must end on that, not wait out the budget for a
    /// commit that never comes.
    @Test
    @MainActor
    func `a click on a 204 link settles at once on the page it never left`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            await server.register(path: "/no-content") { _ in
                FixtureResponse(status: 204, contentType: .plainText, body: Data())
            }
            let host = host(steps: [.click(selector: "#nothing")])
            let started = Date()
            _ = try await host.load(URL(string: "step-navigation.html", relativeTo: base)!)
            #expect(Date().timeIntervalSince(started) < TestSupport.livenessBudget / 2)
            let title: String = try await host.evaluate("return document.title;", as: String.self)
            #expect(title == "Step navigation fixture")
        }
    }
}
