import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The load pipeline's action-step phase: ordered `--click`/`--fill`/`--submit`
/// steps executed after the load event, each auto-waiting for its selector,
/// with the wait condition gating the read after them.
@Suite("PageHost action steps", .serialized)
struct PageHostActionStepTests {
    @MainActor
    private func load(
        _ page: String,
        base: URL,
        steps: [ActionStep],
        wait: WaitCondition? = nil,
    ) async throws -> PageHost {
        var options = LoadOptions()
        options.steps = steps
        options.wait = wait
        let host = PageHost(options: options)
        _ = try await host.load(URL(string: page, relativeTo: base)!)
        return host
    }

    @MainActor
    private func bodyText(of host: PageHost) async throws -> String {
        try await host.execute(EvalOperation(source: "return document.body.innerText;", world: .page))
    }

    /// The wait-vs-steps ruling (vision doc, corrected 2026-08-20) moved
    /// `--wait-for` after the steps, so this flow no longer pre-gates on the
    /// form's own button — the step auto-waits for it instead.
    @Test
    @MainActor
    func `a fill then a click reaches the page the click navigates to`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await load(
                "form.html",
                base: base,
                steps: [.fill(selector: "#title", value: "Hello"), .click(selector: "#save")],
            )
            let text: String = try await bodyText(of: host)
            #expect(text.contains("received: title=Hello"))
        }
    }

    @Test
    @MainActor
    func `a step waits for its selector to appear before acting`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.steps = [ActionStep.click(selector: "#go")]
            options.budget = 10
            let host = PageHost(options: options)
            // #go only exists ~300ms after the load event; the step must wait
            // for it rather than failing on the empty page.
            _ = try await host.load(URL(string: "act-late.html", relativeTo: base)!)
        }
    }

    @Test
    @MainActor
    func `the wait condition gates the read after the steps run`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.steps = [ActionStep.click(selector: "#go")]
            options.wait = .selector(".results")
            options.budget = 8
            let host = PageHost(options: options)
            // .results exists only because the click happened: a wait that ran
            // before the steps could never see it.
            _ = try await host.load(URL(string: "act-late.html", relativeTo: base)!)
            let results = try await host.execute(EvalOperation(
                source: "return document.querySelector('.results').textContent;",
                world: .page,
            ))
            #expect(results == "\"Results!\"")
        }
    }

    @Test
    @MainActor
    func `a step that navigates refreshes the load's facts`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await load(
                "form.html",
                base: base,
                steps: [.fill(selector: "#title", value: "Hello"), .click(selector: "#save")],
            )
            #expect(host.facts.finalURL?.path == "/submit", "facts must describe the page the steps produced")
            #expect(host.facts.httpStatus == 200)
        }
    }

    @Test
    @MainActor
    func `steps run in the order they were given`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await load(
                "act-events.html",
                base: base,
                steps: [
                    .fill(selector: "#title", value: "first"),
                    .fill(selector: "#title", value: "second"),
                    .click(selector: "#go"),
                ],
            )
            let log = try await host.execute(EvalOperation(
                source: "return document.getElementById('field-log').textContent;",
                world: .page,
            ))
            let first = try #require(log.range(of: "first"))
            let second = try #require(log.range(of: "second"))
            #expect(first.lowerBound < second.lowerBound)
            let clicks = try await host.execute(EvalOperation(
                source: "return document.getElementById('click-log').textContent;",
                world: .page,
            ))
            #expect(clicks.contains("\\\"clicks\\\":1"))
        }
    }

    /// The ruling makes a never-actionable step a timeout (it waited,
    /// honestly, and ran out of budget), not an instant clean negative.
    @Test
    @MainActor
    func `a step whose selector never appears times out and leaves the page readable`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.steps = [ActionStep.click(selector: "#nowhere")]
            options.budget = 2
            let host = PageHost(options: options)
            do {
                _ = try await host.load(URL(string: "form.html", relativeTo: base)!)
                Issue.record("expected the step to fail the load")
            } catch let error as SleepyError {
                #expect(error.kind == .timeout)
                #expect(error.description.contains("#nowhere"))
            }
            let title = try await host.execute(EvalOperation(source: "return document.title;"))
            #expect(title == "\"Form fixture\"")
        }
    }

    @Test
    @MainActor
    func `no steps means the pipeline does nothing`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await load("form.html", base: base, steps: [])
            #expect(try await bodyText(of: host).contains("Form fixture"))
        }
    }
}
