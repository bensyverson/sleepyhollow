import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The `--leave` step (Ben's ruling, 2026-11-06,
/// `project/2026-11-06-trusted-click.md`): a click leaves the pointer where it
/// clicked, as a user's does, and `leave` is the explicit, ordered way to take
/// it off the page — so a capture after a click need not also show hover.
@Suite("Leave step", .serialized)
struct LeaveStepTests {
    /// What the page says after a load with `steps`.
    private struct Facts: Decodable {
        /// Whether `#go` matches `:hover`.
        let hovered: Bool
        /// The leave events `#go` heard, `!` marking an untrusted one.
        let leaves: [String]
    }

    @MainActor
    private func facts(after steps: [ActionStep], base: URL) async throws -> Facts {
        var options = LoadOptions()
        options.steps = steps
        options.budget = TestSupport.livenessBudget
        let host = PageHost(options: options)
        _ = try await host.load(#require(URL(string: "click-trusted.html", relativeTo: base)))
        let json: String = try await host.evaluate(
            "return { hovered: document.getElementById('go').matches(':hover'), leaves: window.goLeaves };",
            in: .page,
        )
        return try JSONDecoder().decode(Facts.self, from: Data(json.utf8))
    }

    @Test
    @MainActor
    func `a click alone leaves the pointer over what it clicked`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let facts = try await facts(after: [.click(selector: "#go")], base: base)
            #expect(facts.hovered)
            #expect(facts.leaves.isEmpty)
        }
    }

    @Test
    @MainActor
    func `a leave after a click takes the pointer off the clicked element, with trusted leave events`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let facts = try await facts(after: [.click(selector: "#go"), .leave], base: base)
            #expect(!facts.hovered)
            #expect(facts.leaves == ["pointerleave", "mouseleave"])
        }
    }

    @Test
    @MainActor
    func `a leave after a hover clears the hover it set`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let facts = try await facts(after: [.hover(selector: "#go"), .leave], base: base)
            #expect(!facts.hovered)
            #expect(facts.leaves == ["pointerleave", "mouseleave"])
        }
    }

    @Test
    @MainActor
    func `a leave keeps keyboard focus where it was`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.steps = [.click(selector: "#go"), .focus(selector: "#agree"), .leave]
            options.budget = TestSupport.livenessBudget
            let host = PageHost(options: options)
            _ = try await host.load(#require(URL(string: "click-trusted.html", relativeTo: base)))
            let state: String = try await host.evaluate(
                "return [document.activeElement.id, document.getElementById('agree').matches(':focus-visible'),"
                    + " window.agreeBlurs, document.getElementById('go').matches(':hover')].join(' ');",
                in: .page,
            )
            #expect(state == "\"agree true 0 false\"")
        }
    }

    @Test
    @MainActor
    func `the leave operation reports itself and starts no navigation`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(#require(URL(string: "click-trusted.html", relativeTo: base)))
            let outcome = try await host.execute(LeaveOperation())
            #expect(outcome.action == .leave)
            #expect(outcome.selector == nil)
            #expect(!outcome.startedNavigation)
        }
    }

    @Test
    @MainActor
    func `a windowless host refuses a leave rather than pretend`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(hosting: .windowless)
            _ = try await host.load(#require(URL(string: "click-trusted.html", relativeTo: base)))
            do {
                _ = try await host.execute(LeaveOperation())
                Issue.record("left without a window")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
                #expect(error.description.contains("windowless"))
            }
        }
    }
}
