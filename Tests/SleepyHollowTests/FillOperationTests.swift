import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `FillOperation`: values set natively, `input` and `change` dispatched, and
/// the element kinds a fill can and cannot reach.
@Suite("FillOperation", .serialized)
struct FillOperationTests {
    @MainActor
    private func host(base: URL) async throws -> PageHost {
        let host = PageHost()
        _ = try await host.load(URL(string: "act-events.html", relativeTo: base)!)
        return host
    }

    @MainActor
    private func fieldLog(in host: PageHost) async throws -> String {
        try await host.execute(EvalOperation(
            source: "return document.getElementById('field-log').textContent;",
            world: .page,
        ))
    }

    @MainActor
    private func failure(for operation: FillOperation, in host: PageHost) async -> SleepyError? {
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
    func `filling a text input sets its value and fires input then change`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let outcome = try await host.execute(FillOperation(selector: "#title", value: "webkit"))
            #expect(outcome.action == .fill)
            #expect(outcome.tagName == "input")
            #expect(outcome.value == "webkit")
            let log: String = try await fieldLog(in: host)
            #expect(log.contains("\\\"type\\\":\\\"input\\\",\\\"value\\\":\\\"webkit\\\""))
            #expect(log.contains("\\\"type\\\":\\\"change\\\",\\\"value\\\":\\\"webkit\\\""))
        }
    }

    @Test
    @MainActor
    func `filling a textarea works the same way`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let outcome = try await host.execute(FillOperation(selector: "#notes", value: "two\nlines"))
            #expect(outcome.tagName == "textarea")
            #expect(outcome.value == "two\nlines")
        }
    }

    @Test
    @MainActor
    func `filling a checkbox takes a boolean word and checks it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let outcome = try await host.execute(FillOperation(selector: "#agree", value: "true"))
            #expect(outcome.value == "true")
            let log: String = try await fieldLog(in: host)
            #expect(log.contains("\\\"checked\\\":true"))
            _ = try await host.execute(FillOperation(selector: "#agree", value: "false"))
            let checked = try await host.execute(EvalOperation(
                source: "return document.getElementById('agree').checked;",
                world: .page,
            ))
            #expect(checked == "false")
        }
    }

    @Test
    @MainActor
    func `filling a select chooses by option value or by visible label`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            #expect(try await host.execute(FillOperation(selector: "#colour", value: "g")).value == "g")
            #expect(try await host.execute(FillOperation(selector: "#colour", value: "Red")).value == "r")
        }
    }

    @Test
    @MainActor
    func `a select with no such option is a clean negative`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let error = await failure(for: FillOperation(selector: "#colour", value: "Mauve"), in: host)
            #expect(error?.kind == .negative)
        }
    }

    @Test
    @MainActor
    func `a read-only field is a clean negative`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let error = await failure(for: FillOperation(selector: "#locked", value: "new"), in: host)
            #expect(error?.kind == .negative)
            #expect(error?.description.contains("read-only") == true)
        }
    }

    @Test
    @MainActor
    func `a disabled control is a clean negative`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let error = await failure(for: FillOperation(selector: "#off", value: "x"), in: host)
            #expect(error?.kind == .negative)
        }
    }

    @Test
    @MainActor
    func `an element that holds no value is a usage error naming what fill accepts`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let error = await failure(for: FillOperation(selector: "h1", value: "x"), in: host)
            #expect(error?.kind == .usage)
            #expect(error?.description.contains("h1") == true)
        }
    }

    @Test
    @MainActor
    func `a selector matching nothing is a clean negative`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            #expect(await failure(for: FillOperation(selector: "#nowhere", value: "x"), in: host)?.kind == .negative)
        }
    }

    @Test func `the operation's wire identity is stable`() throws {
        #expect(FillOperation.kind == "fill")
        var registry = OperationRegistry()
        registry.register(FillOperation.self)
        let operation = FillOperation(selector: "#q", value: "webkit")
        let decoded = try registry.decode(OperationEnvelope(operation)) as? FillOperation
        #expect(decoded == operation)
    }
}
