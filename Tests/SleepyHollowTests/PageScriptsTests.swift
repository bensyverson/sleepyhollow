import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// ``LoadOptions/pageScripts``: a load with the page's own JavaScript off.
///
/// The point is a progressive-enhancement check in the browser rather than
/// over `URLSession`: the `<noscript>` fallback renders, nothing the page's
/// scripts would do happens, and every verb either answers or refuses with a
/// teaching error — never a plausible wrong answer. One test per verb family;
/// `no-js.html` enhances itself in every way a scripted page would show, and
/// keeps its CSS 3D inside the `<noscript>`, so the caveat can only come from
/// the fallback.
@Suite("Page scripts off")
struct PageScriptsTests {
    /// A host with the page's scripts off, loaded with `page`.
    @MainActor
    private func host(
        loading page: String,
        base: URL,
        wait: WaitCondition? = nil,
        wire: Bool = false,
    ) async throws -> PageHost {
        var options = LoadOptions(pageScripts: .disabled)
        options.wait = wait
        options.budget = TestSupport.livenessBudget
        if wire { options = options.recordingWire() }
        let host = PageHost(options: options)
        _ = try await host.load(URL(string: page, relativeTo: base)!)
        return host
    }

    @Test func `page scripts run by default`() {
        #expect(LoadOptions().pageScripts == .enabled)
    }

    @Test func `the setting survives JSON transport`() throws {
        let options = LoadOptions(pageScripts: .disabled)
        let decoded = try JSONDecoder().decode(LoadOptions.self, from: JSONEncoder().encode(options))
        #expect(decoded.pageScripts == .disabled)
    }

    // MARK: - The page as a scripting-off browser renders it

    @Test
    @MainActor
    func `the noscript fallback renders and the page's script does not run`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js.html", base: base)
            let fallback: [ElementFact] = try await host.execute(QueryOperation(selector: "#fallback"))
            #expect(fallback.count == 1)
            #expect(fallback.first?.visible == true)
            let status: [ElementFact] = try await host.execute(QueryOperation(selector: "#status"))
            #expect(status.first?.text == "server")
            let enhanced: [ElementFact] = try await host.execute(QueryOperation(selector: "#enhanced"))
            #expect(enhanced.isEmpty)
        }
    }

    @Test
    @MainActor
    func `the scripting media feature reports none`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js.html", base: base)
            let result: String = try await host.execute(EvalOperation(
                source: "return matchMedia('(scripting: none)').matches;",
                world: .isolated,
            ))
            #expect(result == "true")
        }
    }

    // MARK: - Verbs that work

    @Test
    @MainActor
    func `eval in the isolated world reads the unenhanced DOM and finds the helpers`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js.html", base: base)
            let result: String = try await host.execute(EvalOperation(
                source: "return [document.getElementById('status').textContent, typeof window.sleepy.contrast];",
                world: .isolated,
            ))
            #expect(result == #"["server","function"]"#)
        }
    }

    @Test
    @MainActor
    func `ax reads the fallback and not the enhancement`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js.html", base: base)
            let tree: AXNode = try await host.execute(AXOperation())
            let names: [String] = tree.flattened.compactMap(\.name)
            #expect(tree.flattened.contains { $0.role == .button && $0.name == "Press" })
            #expect(names.contains { $0.contains("this is the fallback") })
            #expect(!names.contains { $0.contains("Added by script") })
        }
    }

    @Test
    @MainActor
    func `contrast and overflow answer from the helper library`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js.html", base: base)
            let contrast: ContrastReport = try await host.execute(ContrastOperation(selector: "#fallback"))
            #expect(contrast.scopeMatches == 1)
            #expect(contrast.checked == 1)
            let overflow: OverflowReport = try await host.execute(OverflowOperation())
            #expect(overflow.passes)
        }
    }

    @Test
    @MainActor
    func `a shot keeps its CSS 3D caveat`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js.html", base: base)
            let output: ShotOperation.Output = try await host.execute(ShotOperation())
            #expect(output.flattened3D.map(\.path) == ["div#tilt"])
        }
    }

    @Test
    @MainActor
    func `a click lands without running the page's handler`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js.html", base: base)
            _ = try await host.execute(ClickOperation(selector: "#button"))
            let button: [ElementFact] = try await host.execute(QueryOperation(selector: "#button"))
            #expect(button.first?.text == "Press")
        }
    }

    @Test
    @MainActor
    func `a submit step lands on the page the form posts to`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions(pageScripts: .disabled)
            options.steps = [.fill(selector: "#title", value: "Hello"), .submit(selector: "#editor")]
            options.budget = TestSupport.livenessBudget
            let host = PageHost(options: options)
            let facts: PageFacts = try await host.load(URL(string: "form.html", relativeTo: base)!)
            #expect(facts.finalURL?.path == "/submit")
        }
    }

    @Test
    @MainActor
    func `a click that submits a form reports the navigation it started`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "form.html", base: base)
            let outcome: ActionOutcome = try await host.execute(ClickOperation(selector: "#save"))
            #expect(outcome.startedNavigation)
        }
    }

    @Test
    @MainActor
    func `wire reads the inventory, and no page script fetched anything`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js.html", base: base, wire: true)
            let log: WireLog = try await host.execute(WireOperation())
            #expect(log.inventory.contains { $0.initiatorType == "navigation" && $0.httpStatus == 200 })
            #expect(log.fetches.isEmpty)
        }
    }

    @Test(arguments: [WaitCondition.idle, WaitCondition.selector("#fallback")])
    @MainActor
    func `the wait engine settles`(condition: WaitCondition) async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js.html", base: base, wait: condition)
            let status: [ElementFact] = try await host.execute(QueryOperation(selector: "#status"))
            #expect(status.first?.text == "server")
        }
    }

    @Test
    @MainActor
    func `the idle sampler reads the page from the isolated world`() async throws {
        // Not a timing test: with scripting off, WebKit's load event already
        // waits for webfonts and for lazy images (loaded eagerly, as the HTML
        // spec requires), so no fixture is still busy when idle starts
        // (measured 2026-11-06). What can be checked is that the sample is
        // real rather than "unreadable", which idle would read as quiet.
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js-font.html", base: base)
            let text: String = try await host.evaluate(IdleWatch.isolatedSampleBody, in: .isolated)
            let sample = try JSONDecoder().decode(IdleWatch.Sample.self, from: Data(text.utf8))
            #expect(sample.activity >= 1, "the webfont is a resource-timeline entry")
            #expect(sample.busy == 0)
        }
    }

    // MARK: - Verbs that refuse

    @Test
    @MainActor
    func `eval in the page world refuses and names the isolated world`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js.html", base: base)
            let error = try #require(await #expect(throws: SleepyError.self) {
                try await host.execute(EvalOperation(source: "return 1;"))
            })
            #expect(error.kind == .usage)
            #expect(error.nextMove?.contains("--world isolated") == true)
        }
    }

    @Test
    @MainActor
    func `console refuses, because no page script ran to write to it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "no-js.html", base: base)
            let error = try #require(await #expect(throws: SleepyError.self) {
                try await host.execute(ConsoleOperation())
            })
            #expect(error.kind == .usage)
            #expect(error.message.contains("--no-js"))
        }
    }

    @Test(arguments: [WaitCondition.predicate("true"), WaitCondition.message("appReady")])
    @MainActor
    func `a wait only page script could satisfy refuses before navigating`(condition: WaitCondition) async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions(pageScripts: .disabled)
            options.wait = condition
            options.budget = TestSupport.livenessBudget
            let host = PageHost(options: options)
            let started = Date()
            let error = try #require(await #expect(throws: SleepyError.self) {
                try await host.load(URL(string: "no-js.html", relativeTo: base)!)
            })
            #expect(error.kind == .usage)
            #expect(error.message.contains("--no-js"))
            #expect(Date().timeIntervalSince(started) < TestSupport.livenessBudget)
        }
    }
}
