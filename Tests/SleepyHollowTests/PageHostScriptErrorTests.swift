import Foundation
import SleepyHollow
import Testing
import TestSupport

/// Regression for the 2026-08-30 Woodcase report, item 4: a thrown or
/// unparseable body must surface as an error naming the page's own message,
/// never as an empty answer.
@Suite("PageHost script errors")
struct PageHostScriptErrorTests {
    @Test
    @MainActor
    func `a thrown body throws, naming the page's message`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            do {
                let answer: String = try await host.evaluate("throw new Error('deliberate failure');")
                Issue.record("expected a throw, got \(answer.debugDescription)")
            } catch let EvaluationError.javaScript(message) {
                #expect(message.contains("deliberate failure"))
            }
        }
    }

    @Test
    @MainActor
    func `a syntactically invalid body throws, naming the syntax error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            do {
                let answer: String = try await host.evaluate("return (1 +;")
                Issue.record("expected a throw, got \(answer.debugDescription)")
            } catch let EvaluationError.javaScript(message) {
                #expect(message.contains("SyntaxError"))
            }
        }
    }

    @Test
    @MainActor
    func `the decoded evaluate throws the same JavaScript error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            do {
                let answer: String = try await host.evaluate("throw new TypeError('typed');", as: String.self)
                Issue.record("expected a throw, got \(answer.debugDescription)")
            } catch let EvaluationError.javaScript(message) {
                #expect(message.contains("TypeError"))
                #expect(message.contains("typed"))
            }
        }
    }
}
