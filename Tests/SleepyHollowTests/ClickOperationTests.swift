import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `ClickOperation`: an honest synthesized event sequence, and the answers a
/// page gives back when the target can't be clicked.
@Suite("ClickOperation", .serialized)
struct ClickOperationTests {
    @MainActor
    private func host(loading page: String, base: URL) async throws -> PageHost {
        let host = PageHost()
        _ = try await host.load(URL(string: page, relativeTo: base)!)
        return host
    }

    @MainActor
    private func text(of selector: String, in host: PageHost) async throws -> String {
        try await host.execute(EvalOperation(
            source: "return document.querySelector(selector).textContent;",
            argumentsJSON: "{\"selector\": \"\(selector)\"}",
            world: .page,
        ))
    }

    @Test
    @MainActor
    func `a click dispatches the pointer, mouse and click events a page listens for`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            _ = try await host.execute(ClickOperation(selector: "#go"))
            let log: String = try await text(of: "#click-log", in: host)
            #expect(log.contains("\\\"clicks\\\":1"))
            #expect(log.contains("\\\"type\\\":\\\"click\\\""))
            #expect(log.contains("\\\"bubbles\\\":true"))
            #expect(log.contains("\\\"button\\\":0"))
            #expect(log.contains("[\\\"pointerdown\\\",\\\"mousedown\\\",\\\"pointerup\\\",\\\"mouseup\\\"]"))
        }
    }

    @Test
    @MainActor
    func `the synthesized click is honest about being untrusted, and lands on the element`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            _ = try await host.execute(ClickOperation(selector: "#go"))
            let log: String = try await text(of: "#click-log", in: host)
            #expect(log.contains("\\\"isTrusted\\\":false"))
            #expect(log.contains("\\\"insideX\\\":true"))
            #expect(log.contains("\\\"insideY\\\":true"))
        }
    }

    @Test
    @MainActor
    func `the outcome names what was clicked`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            let outcome = try await host.execute(ClickOperation(selector: "#go"))
            #expect(outcome.action == .click)
            #expect(outcome.selector == "#go")
            #expect(outcome.tagName == "button")
            #expect(outcome.startedNavigation == false)
        }
    }

    @Test
    @MainActor
    func `a selector matching nothing is a clean negative naming it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            do {
                _ = try await host.execute(ClickOperation(selector: "#nowhere"))
                Issue.record("expected a clean negative")
            } catch let error as SleepyError {
                #expect(error.kind == .negative)
                #expect(error.description.contains("#nowhere"))
            }
        }
    }

    @Test
    @MainActor
    func `a disabled control is a clean negative, not a pretended click`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            do {
                _ = try await host.execute(ClickOperation(selector: "#off"))
                Issue.record("expected a clean negative")
            } catch let error as SleepyError {
                #expect(error.kind == .negative)
                #expect(error.description.contains("disabled"))
            }
        }
    }

    @Test
    @MainActor
    func `an unparseable selector is a usage error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            do {
                _ = try await host.execute(ClickOperation(selector: "#("))
                Issue.record("expected a usage error")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
            }
        }
    }

    @Test
    @MainActor
    func `clicking a submit button submits its form, and a prevented submit is not a navigation`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            let outcome = try await host.execute(ClickOperation(selector: "#local-save"))
            #expect(outcome.startedNavigation == false)
            let log: String = try await text(of: "#submit-log", in: host)
            #expect(log.contains("\\\"submitted\\\":true"))
            #expect(log.contains("filled"))
        }
    }

    @Test
    @MainActor
    func `clicking a submit button whose form really submits reports a navigation`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "form.html", base: base)
            let outcome = try await host.execute(ClickOperation(selector: "#save"))
            #expect(outcome.startedNavigation == true)
        }
    }

    @Test func `the operation's wire identity is stable`() throws {
        #expect(ClickOperation.kind == "click")
        var registry = OperationRegistry()
        registry.register(ClickOperation.self)
        let operation = ClickOperation(selector: "#go")
        let decoded = try registry.decode(OperationEnvelope(operation)) as? ClickOperation
        #expect(decoded == operation)
    }
}
