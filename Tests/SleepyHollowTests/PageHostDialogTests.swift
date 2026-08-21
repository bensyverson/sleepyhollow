import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("PageHost dialog policy")
struct PageHostDialogTests {
    private static func autoDialogURL(base: URL) -> URL {
        URL(string: "dialogs.html?auto", relativeTo: base)!
    }

    @Test
    @MainActor
    func `the default policy declines everything and records all three dialogs`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            let facts: PageFacts = try await host.load(Self.autoDialogURL(base: base))
            #expect(facts.dialogs == [
                DialogRecord(kind: .alert, message: "fixture alert", response: .acknowledged),
                DialogRecord(kind: .confirm, message: "fixture confirm", response: .dismissed),
                DialogRecord(kind: .prompt, message: "fixture prompt", response: .dismissed),
            ])
            let log: String = try await host.evaluate(
                "return document.getElementById('log').textContent;",
                in: .page,
            )
            #expect(log == "\"alerted;confirm:false;prompt:null;\"")
        }
    }

    @Test
    @MainActor
    func `accepting confirms and answering prompts overrides the defaults`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.dialogs = DialogPolicy(acceptsConfirms: true, promptResponse: "typed by the agent")
            let host = PageHost(options: options)
            let facts: PageFacts = try await host.load(Self.autoDialogURL(base: base))
            #expect(facts.dialogs == [
                DialogRecord(kind: .alert, message: "fixture alert", response: .acknowledged),
                DialogRecord(kind: .confirm, message: "fixture confirm", response: .accepted),
                DialogRecord(
                    kind: .prompt,
                    message: "fixture prompt",
                    response: .answered("typed by the agent"),
                ),
            ])
            let log: String = try await host.evaluate(
                "return document.getElementById('log').textContent;",
                in: .page,
            )
            #expect(log == "\"alerted;confirm:true;prompt:typed by the agent;\"")
        }
    }

    @Test
    @MainActor
    func `a beforeunload handler never blocks the next navigation`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.budget = 5
            let host = PageHost(options: options)
            _ = try await host.load(URL(string: "before-unload.html", relativeTo: base)!)
            let next: PageFacts = try await host.load(URL(string: "static.html", relativeTo: base)!)
            #expect(next.finalURL?.lastPathComponent == "static.html")
            // WKUIDelegate has no public beforeunload panel, so nothing is recorded.
            #expect(next.dialogs.isEmpty)
        }
    }

    @Test
    @MainActor
    func `a page without dialogs records none`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            let facts: PageFacts = try await host.load(URL(string: "dialogs.html", relativeTo: base)!)
            #expect(facts.dialogs.isEmpty)
        }
    }
}
