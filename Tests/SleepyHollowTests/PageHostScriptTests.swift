import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("PageHost script plumbing")
struct PageHostScriptTests {
    @Test
    @MainActor
    func `a document-start page-world script runs before the page's own scripts`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.scripts = [InjectedScript(
                source: "window.__injectedMarker = 'before-the-page';",
                injectAt: .documentStart,
                world: .page,
            )]
            let host = PageHost(options: options)
            _ = try await host.load(URL(string: "inject-order.html", relativeTo: base)!)
            let seen: String = try await host.evaluate(
                "return document.getElementById('marker').textContent;",
            )
            #expect(seen == "\"before-the-page\"")
        }
    }

    @Test
    @MainActor
    func `a document-end script runs after the page's own scripts`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.scripts = [InjectedScript(
                source: "window.__injectedMarker = 'too-late';",
                injectAt: .documentEnd,
                world: .page,
            )]
            let host = PageHost(options: options)
            _ = try await host.load(URL(string: "inject-order.html", relativeTo: base)!)
            let seen: String = try await host.evaluate(
                "return document.getElementById('marker').textContent;",
            )
            #expect(seen == "\"undefined\"")
        }
    }

    @Test
    @MainActor
    func `isolated is the default world and cannot see page globals`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.scripts = [InjectedScript(
                source: "window.__pageOnly = 42;",
                injectAt: .documentStart,
                world: .page,
            )]
            let host = PageHost(options: options)
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let fromIsolated: String = try await host.evaluate("return typeof window.__pageOnly;")
            let fromPage: String = try await host.evaluate("return typeof window.__pageOnly;", in: .page)
            #expect(fromIsolated == "\"undefined\"")
            #expect(fromPage == "\"number\"")
        }
    }

    @Test
    @MainActor
    func `evaluate returns JSON text, forwards arguments and awaits`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let object: String = try await host.evaluate(
                "await null; return { title: document.title, n: count };",
                arguments: ["count": 3],
            )
            #expect(object == "{\"title\":\"Static fixture\",\"n\":3}")
            let nothing: String = try await host.evaluate("return undefined;")
            #expect(nothing == "null")
        }
    }

    @Test
    @MainActor
    func `a page error in evaluate surfaces as a failure, not a hang`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            await #expect(throws: (any Error).self) {
                try await host.evaluate("throw new Error('deliberate');")
            }
        }
    }

    @Test
    @MainActor
    func `script messages reach a named stream`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            var options = LoadOptions()
            options.scripts = [InjectedScript(
                source: "window.webkit.messageHandlers.probe.postMessage('hello from the page');",
                injectAt: .documentEnd,
                world: .isolated,
            )]
            let host = PageHost(options: options)
            let messages: AsyncStream<String> = host.messages(named: "probe")
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            var first: String?
            for await message in messages {
                first = message
                break
            }
            #expect(first == "hello from the page")
        }
    }
}
