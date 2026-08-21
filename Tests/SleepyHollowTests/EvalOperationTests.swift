import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `EvalOperation`: the universal escape hatch — JSON out, `await` supported,
/// arguments in, page failures as structured errors, and the isolated world
/// as the default.
@Suite("EvalOperation", .serialized)
struct EvalOperationTests {
    @MainActor
    private func host(loading page: String, base: URL) async throws -> PageHost {
        let host = PageHost()
        _ = try await host.load(URL(string: page, relativeTo: base)!)
        return host
    }

    @Test
    @MainActor
    func `a body's return value comes back as JSON text`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "static.html", base: base)
            let result = try await host.execute(EvalOperation(source: "return 1 + 1;"))
            #expect(result == "2")
        }
    }

    @Test
    @MainActor
    func `an object result is transported as JSON`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "static.html", base: base)
            let result = try await host.execute(EvalOperation(source: "return { marks: [1, 2], ok: true };"))
            #expect(result.contains("\"marks\""))
            #expect(result.contains("[1,2]"))
        }
    }

    @Test
    @MainActor
    func `a body that returns nothing comes back as null`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "static.html", base: base)
            #expect(try await host.execute(EvalOperation(source: "const unused = 1;")) == "null")
        }
    }

    @Test
    @MainActor
    func `await is supported, on a real deferred promise`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "static.html", base: base)
            let result = try await host.execute(EvalOperation(source: """
            const later = new Promise((resolve) => setTimeout(() => resolve('after'), 20));
            return await later;
            """))
            #expect(result == "\"after\"")
        }
    }

    @Test
    @MainActor
    func `arguments arrive in scope under their names`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "static.html", base: base)
            let operation = EvalOperation(
                source: "return { product: factor * count, label };",
                argumentsJSON: #"{"factor": 6, "count": 7, "label": "answer"}"#,
            )
            let result = try await host.execute(operation)
            #expect(result.contains("\"product\":42"))
            #expect(result.contains("\"label\":\"answer\""))
        }
    }

    @Test
    @MainActor
    func `arguments that are not a JSON object are a usage error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "static.html", base: base)
            for bad in ["{", "[1, 2]", "\"text\""] {
                let operation = EvalOperation(source: "return 1;", argumentsJSON: bad)
                await #expect(throws: SleepyError.self) {
                    try await host.execute(operation)
                }
            }
        }
    }

    @Test
    @MainActor
    func `a thrown page error becomes a structured failure carrying its message`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "static.html", base: base)
            do {
                _ = try await host.execute(EvalOperation(source: "throw new Error('boom');"))
                Issue.record("expected the page error to surface")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
                #expect(error.description.contains("boom"))
                #expect(!error.description.contains("Error Domain="))
            }
        }
    }

    @Test
    @MainActor
    func `a syntax error becomes a structured failure too`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "static.html", base: base)
            do {
                _ = try await host.execute(EvalOperation(source: "return (;"))
                Issue.record("expected the syntax error to surface")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
                #expect(error.nextMove?.isEmpty == false)
            }
        }
    }

    @Test
    @MainActor
    func `the isolated world is the default, so page globals are invisible`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "eval-world.html", base: base)
            let operation = EvalOperation(source: "return typeof window.sleepyPageValue;")
            #expect(try await host.execute(operation) == "\"undefined\"")
        }
    }

    @Test
    @MainActor
    func `the page world reaches the page's own state`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "eval-world.html", base: base)
            let operation = EvalOperation(source: "return window.sleepyPageValue;", world: .page)
            #expect(try await host.execute(operation) == "\"page-world\"")
        }
    }

    @Test
    @MainActor
    func `both worlds read the same DOM`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "eval-world.html", base: base)
            let source = "return document.getElementById('marker').textContent;"
            #expect(try await host.execute(EvalOperation(source: source)) == "\"page state\"")
            #expect(try await host.execute(EvalOperation(source: source, world: .page)) == "\"page state\"")
        }
    }

    @Test func `the operation's wire identity is stable`() throws {
        #expect(EvalOperation.kind == "eval")
        let operation = EvalOperation(source: "return 1;", argumentsJSON: "{}", world: .page)
        let envelope = try OperationEnvelope(operation)
        var registry = OperationRegistry()
        registry.register(EvalOperation.self)
        let decoded = try #require(try registry.decode(envelope) as? EvalOperation)
        #expect(decoded == operation)
    }
}
