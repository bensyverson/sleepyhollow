import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `PageHost.press(_:focusing:)` and `type(_:focusing:)`: real keystrokes,
/// delivered through the window the way a keyboard's are, so the page sees
/// `isTrusted` and the browser runs each key's default action (leaf `XerXuw`).
@Suite("Press", .serialized)
struct PressTests {
    /// What `press-keys.html` reports.
    private struct KeyFacts: Decodable {
        struct Entry: Decodable {
            let type: String
            let key: String
            let code: String
            let isTrusted: Bool
            let shift: Bool
            let meta: Bool
            let target: String
        }

        let log: [Entry]
        let active: String?
        let name: String
        let second: String
        let guarded: String
        let search: String
    }

    @MainActor
    private func host(_ base: URL, options: LoadOptions = LoadOptions()) async throws -> PageHost {
        let host = PageHost(options: options)
        _ = try await host.load(#require(URL(string: "press-keys.html", relativeTo: base)))
        return host
    }

    @MainActor
    private func facts(_ host: PageHost) async throws -> KeyFacts {
        let json: String = try await host.evaluate("return window.keyFacts();", in: .page)
        return try JSONDecoder().decode(KeyFacts.self, from: Data(json.utf8))
    }

    @Test
    @MainActor
    func `typed text lands in the focused field as trusted keystrokes`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            let outcome = try await host.type("Hello", focusing: "#name")
            let facts = try await facts(host)
            #expect(facts.name == "Hello")
            #expect(facts.log.filter { $0.type == "keydown" }.map(\.key) == ["Shift", "H", "e", "l", "l", "o"])
            let untrusted: Int = facts.log.count { !$0.isTrusted }
            #expect(untrusted == 0)
            #expect(outcome.action == .press)
            #expect(outcome.selector == "#name")
            #expect(outcome.tagName == "input")
            #expect(outcome.value == "Hello")
            #expect(outcome.startedNavigation == false)
        }
    }

    @Test
    @MainActor
    func `a field that refuses untrusted keys accepts these`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            try await host.type("ok", focusing: "#guarded")
            #expect(try await facts(host).guarded == "ok")
        }
    }

    @Test
    @MainActor
    func `Tab moves focus to the next field`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            try await host.press([KeyChord(parsing: "Tab")], focusing: "#name")
            let facts = try await facts(host)
            #expect(facts.active == "second")
            #expect(facts.log.first?.key == "Tab")
            #expect(facts.log.first?.code == "Tab")
        }
    }

    @Test
    @MainActor
    func `Shift+Tab moves focus back, with Shift held`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            try await host.press([KeyChord(parsing: "Shift+Tab")], focusing: "#second")
            let facts = try await facts(host)
            #expect(facts.active == "name")
            let tab = try #require(facts.log.first { $0.type == "keydown" && $0.key == "Tab" })
            #expect(tab.shift)
        }
    }

    @Test
    @MainActor
    func `keys without a selector go to whatever has focus`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            _ = try await host.evaluate("document.getElementById('second').focus(); return true;", in: .page)
            let outcome = try await host.press([KeyChord(parsing: "x"), KeyChord(parsing: "y")])
            #expect(try await facts(host).second == "xy")
            #expect(outcome.selector == nil)
            #expect(outcome.tagName == "input")
        }
    }

    @Test
    @MainActor
    func `Enter submits the form, and the outcome says the page navigated`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            try await host.type("abc", focusing: "#name")
            let outcome = try await host.press([KeyChord(parsing: "Enter")])
            #expect(outcome.startedNavigation)
            let search = try await settledSearch(of: host)
            #expect(search.contains("name=abc"))
        }
    }

    @Test
    @MainActor
    func `a key whose page handler navigates reports the navigation`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            let outcome = try await host.type("j", focusing: "#jump")
            #expect(outcome.startedNavigation)
        }
    }

    @Test
    @MainActor
    func `with the page's scripts off, typing and Enter still work and the navigation is seen`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base, options: LoadOptions(pageScripts: .disabled))
            try await host.type("quiet", focusing: "#name")
            let outcome = try await host.press([KeyChord(parsing: "Enter")])
            #expect(outcome.startedNavigation)
            for _ in 0 ..< 200 where host.webView.url?.query == nil {
                try await Task.sleep(nanoseconds: 50_000_000)
            }
            #expect(host.webView.url?.query?.contains("name=quiet") == true)
        }
    }

    @Test
    @MainActor
    func `a Meta chord reaches the page with metaKey set`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            try await host.press([KeyChord(parsing: "Meta+k")], focusing: "#name")
            let facts = try await facts(host)
            let keyDown = try #require(facts.log.first { $0.type == "keydown" && $0.key == "k" })
            #expect(keyDown.meta)
            #expect(keyDown.isTrusted)
        }
    }

    @Test
    @MainActor
    func `a character with no US key is typed, and its code is unidentified`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            try await host.type("é", focusing: "#name")
            let facts = try await facts(host)
            #expect(facts.name == "é")
            let keyDown = try #require(facts.log.first { $0.type == "keydown" })
            #expect(keyDown.key == "é")
            #expect(keyDown.code == "Unidentified")
        }
    }

    @Test
    @MainActor
    func `a selector that matches nothing is a clean negative`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            await #expect(throws: SleepyError.self) {
                try await host.press([KeyChord(parsing: "Enter")], focusing: "#nowhere")
            }
            do {
                try await host.press([KeyChord(parsing: "Enter")], focusing: "#nowhere")
            } catch let error as SleepyError {
                #expect(error.kind == .negative)
            }
        }
    }

    @Test
    @MainActor
    func `nothing to press is a usage error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base)
            do {
                _ = try await host.execute(PressOperation())
                Issue.record("pressed nothing")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
            }
        }
    }

    @Test
    @MainActor
    func `a windowless host refuses rather than faking keys`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(hosting: .windowless)
            _ = try await host.load(#require(URL(string: "press-keys.html", relativeTo: base)))
            do {
                try await host.type("x", focusing: "#name")
                Issue.record("typed without a window")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
                #expect(error.message.contains("windowless"))
            }
            #expect(try await facts(host).name == "")
        }
    }

    @Test func `the operation crosses the session wire`() throws {
        var registry = OperationRegistry()
        registry.register(PressOperation.self)
        let operation = try PressOperation(keys: [KeyChord(parsing: "Shift+Tab")], text: "hi", selector: "#q")
        let decoded = try registry.decode(OperationEnvelope(operation)) as? PressOperation
        #expect(decoded == operation)
        #expect(PressOperation.kind == "press")
    }

    /// The query string once the submitted page has loaded.
    @MainActor
    private func settledSearch(of host: PageHost) async throws -> String {
        for _ in 0 ..< 200 {
            if let query = host.webView.url?.query, !host.webView.isLoading {
                return "?" + query
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return ""
    }
}
