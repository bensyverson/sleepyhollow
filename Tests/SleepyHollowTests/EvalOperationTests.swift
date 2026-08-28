import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `EvalOperation`: the universal escape hatch — JSON out, `await` supported,
/// arguments in, page failures as structured errors, a bare expression
/// wrapped rather than answered with `null`, and the page world as the
/// default.
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

    @Test func `a script's shape is read from its return keyword and its semicolons`() {
        #expect(EvalOperation.shape(of: "return 1;") == .functionBody)
        #expect(EvalOperation.shape(of: "const n = 1; return n;") == .functionBody)
        #expect(EvalOperation.shape(of: "document.title") == .expression)
        #expect(EvalOperation.shape(of: "  rows().length > 0\n") == .expression)
        #expect(EvalOperation.shape(of: "const unused = 1;") == .unreturnedStatements)
        #expect(EvalOperation.shape(of: "") == .unreturnedStatements)
    }

    @Test func `a word merely containing return is not a return statement`() {
        #expect(EvalOperation.shape(of: "form.returnValue") == .expression)
        #expect(EvalOperation.shape(of: "returned") == .expression)
        #expect(EvalOperation.shape(of: "document.querySelector('[data-return]')") == .expression)
    }

    @Test func `a return that opens a line or follows a brace is a return statement`() {
        #expect(EvalOperation.shape(of: "const rows = table.rows\nreturn rows.length") == .functionBody)
        #expect(EvalOperation.shape(of: "if (ready) { return 1; }") == .functionBody)
        #expect(EvalOperation.shape(of: "if (ready) return 1;") == .functionBody)
    }

    @Test func `a single trailing semicolon still reads as an expression`() {
        #expect(EvalOperation.shape(of: "document.querySelector('#save').click();") == .expression)
        #expect(EvalOperation.shape(of: "  document.title;  ") == .expression)
        #expect(EvalOperation.shape(of: "const n = 1; document.title;") == .unreturnedStatements)
        #expect(EvalOperation.shape(of: ";") == .unreturnedStatements)
    }

    @Test func `a trailing semicolon is dropped before wrapping`() throws {
        let clicker = EvalOperation(source: "document.querySelector('#save').click();")
        #expect(try clicker.evaluatedSource() == "return (document.querySelector('#save').click());")
        #expect(try EvalOperation(source: "document.title;").evaluatedSource() == "return (document.title);")
    }

    @Test func `a script opening with a statement keyword is refused rather than wrapped`() {
        #expect(EvalOperation.shape(of: "const unused = 1;") == .unreturnedStatements)
        #expect(EvalOperation.shape(of: "throw new Error('boom');") == .unreturnedStatements)
        #expect(EvalOperation.shape(of: "if (ready) alert('hi');") == .unreturnedStatements)
        #expect(EvalOperation.shape(of: "constant.value;") == .expression)
    }

    @Test func `a bare expression is wrapped, a function body is passed through`() throws {
        #expect(try EvalOperation(source: "document.title").evaluatedSource() == "return (document.title);")
        #expect(try EvalOperation(source: "return 1;").evaluatedSource() == "return 1;")
    }

    @Test func `statements with no return are refused, naming the fix`() throws {
        let operation = EvalOperation(source: "const el = document.querySelector('h1'); el.click();")
        do {
            _ = try operation.evaluatedSource()
            Issue.record("expected the unreturnable script to be refused")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.description.contains("return"))
        }
    }

    @Test
    @MainActor
    func `a bare expression evaluates to its value rather than null`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "static.html", base: base)
            #expect(try await host.execute(EvalOperation(source: "1 + 1")) == "2")
        }
    }

    @Test
    @MainActor
    func `a body with statements and no return never reaches the page`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "static.html", base: base)
            await #expect(throws: SleepyError.self) {
                try await host.execute(EvalOperation(source: "const unused = 1;"))
            }
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
                let thrower = "return (() => { throw new Error('boom'); })();"
                _ = try await host.execute(EvalOperation(source: thrower))
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
    func `the page world is the default, so the page's own globals are visible`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "eval-world.html", base: base)
            let operation = EvalOperation(source: "return window.sleepyPageValue;")
            #expect(try await host.execute(operation) == "\"page-world\"")
        }
    }

    @Test
    @MainActor
    func `the isolated world hides page globals`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "eval-world.html", base: base)
            let operation = EvalOperation(source: "return typeof window.sleepyPageValue;", world: .isolated)
            #expect(try await host.execute(operation) == "\"undefined\"")
        }
    }

    @Test
    @MainActor
    func `an upgraded custom element's method is visible by default and not in the isolated world`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "eval-custom-element.html", base: base)
            let probe = "typeof document.getElementById('chip').reportStatus"
            #expect(try await host.execute(EvalOperation(source: probe)) == "\"function\"")
            #expect(try await host.execute(EvalOperation(source: probe, world: .isolated)) == "\"undefined\"")
        }
    }

    @Test
    @MainActor
    func `customElements get still answers from the isolated world`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "eval-custom-element.html", base: base)
            let probe = "typeof customElements.get('status-chip')"
            let operation = EvalOperation(source: probe, world: .isolated)
            #expect(try await host.execute(operation) == "\"function\"")
        }
    }

    @Test
    @MainActor
    func `both worlds read the same DOM`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(loading: "eval-world.html", base: base)
            let source = "return document.getElementById('marker').textContent;"
            #expect(try await host.execute(EvalOperation(source: source, world: .isolated)) == "\"page state\"")
            #expect(try await host.execute(EvalOperation(source: source, world: .page)) == "\"page state\"")
        }
    }

    @Test func `the operation's wire identity is stable`() throws {
        #expect(EvalOperation.kind == "eval")
        let operation = EvalOperation(source: "return 1;", argumentsJSON: "{}", world: .isolated)
        let envelope = try OperationEnvelope(operation)
        var registry = OperationRegistry()
        registry.register(EvalOperation.self)
        let decoded = try #require(try registry.decode(envelope) as? EvalOperation)
        #expect(decoded == operation)
    }
}
