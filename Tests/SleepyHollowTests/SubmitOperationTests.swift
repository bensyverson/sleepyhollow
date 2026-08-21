import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `SubmitOperation`: a real `submit` event the page can prevent, the form
/// found from whatever the selector matched, and validity honoured.
@Suite("SubmitOperation", .serialized)
struct SubmitOperationTests {
    @MainActor
    private func host(loading page: String, base: URL) async throws -> PageHost {
        let host = PageHost()
        _ = try await host.load(URL(string: page, relativeTo: base)!)
        return host
    }

    @MainActor
    private func failure(for operation: SubmitOperation, in host: PageHost) async -> SleepyError? {
        do {
            _ = try await host.execute(operation)
            return nil
        } catch let error as SleepyError {
            return error
        } catch {
            return nil
        }
    }

    @Test
    @MainActor
    func `submitting a form fires a submit event the page can prevent`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            let outcome = try await host.execute(SubmitOperation(selector: "#local"))
            #expect(outcome.action == .submit)
            #expect(outcome.tagName == "form")
            #expect(outcome.startedNavigation == false)
            let log = try await host.execute(EvalOperation(
                source: "return document.getElementById('submit-log').textContent;",
                world: .page,
            ))
            #expect(log.contains("\\\"submitted\\\":true"))
        }
    }

    @Test
    @MainActor
    func `a control inside a form submits the form that owns it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            let outcome = try await host.execute(SubmitOperation(selector: "#local-name"))
            #expect(outcome.value == "local")
            let log = try await host.execute(EvalOperation(
                source: "return document.getElementById('submit-log').textContent;",
                world: .page,
            ))
            #expect(log.contains("\\\"submitted\\\":true"))
        }
    }

    @Test
    @MainActor
    func `a form that really submits reports a navigation`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "form.html", base: base)
            let outcome = try await host.execute(SubmitOperation(selector: "#editor"))
            #expect(outcome.startedNavigation == true)
        }
    }

    @Test
    @MainActor
    func `an element outside any form is a usage error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            let error = await failure(for: SubmitOperation(selector: "h1"), in: host)
            #expect(error?.kind == .usage)
            #expect(error?.description.contains("form") == true)
        }
    }

    @Test
    @MainActor
    func `a form the browser considers invalid is a clean negative naming the field`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            let error = await failure(for: SubmitOperation(selector: "#strict"), in: host)
            #expect(error?.kind == .negative)
            #expect(error?.description.contains("strict-name") == true)
        }
    }

    @Test
    @MainActor
    func `a selector matching nothing is a clean negative`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "act-events.html", base: base)
            #expect(await failure(for: SubmitOperation(selector: "#nowhere"), in: host)?.kind == .negative)
        }
    }

    @Test func `the operation's wire identity is stable`() throws {
        #expect(SubmitOperation.kind == "submit")
        var registry = OperationRegistry()
        registry.register(SubmitOperation.self)
        let operation = SubmitOperation(selector: "#editor")
        let decoded = try registry.decode(OperationEnvelope(operation)) as? SubmitOperation
        #expect(decoded == operation)
    }
}
