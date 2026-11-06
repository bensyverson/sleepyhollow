import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("PageHost decoded evaluate")
struct PageHostDecodeTests {
    private struct Heading: Decodable, Equatable {
        var title: String
        var count: Int
    }

    @Test
    @MainActor
    func `a string comes back decoded, not as quoted JSON text`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let title: String = try await host.evaluate("return document.title;", as: String.self)
            #expect(title == "Static fixture")
        }
    }

    @Test
    @MainActor
    func `numbers, booleans, optionals and structs decode into their types`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let number: Int = try await host.evaluate("return 6 * 7;", as: Int.self)
            let flag: Bool = try await host.evaluate("return !!document.body;", as: Bool.self)
            let absent: String? = try await host.evaluate("return document.querySelector('nav');", as: String?.self)
            let heading: Heading = try await host.evaluate(
                "return { title: document.title, count: n };",
                as: Heading.self,
                arguments: ["n": 3],
            )
            #expect(number == 42)
            #expect(flag)
            #expect(absent == nil)
            #expect(heading == Heading(title: "Static fixture", count: 3))
        }
    }

    @Test
    @MainActor
    func `a value of the wrong type throws a typed mismatch carrying the page's JSON`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            do {
                let number: Int = try await host.evaluate("return document.title;", as: Int.self)
                Issue.record("expected a type mismatch, got \(number)")
            } catch let error as EvaluationError {
                guard case let .typeMismatch(expected, json, _) = error else {
                    Issue.record("expected a type mismatch, got \(error)")
                    return
                }
                #expect(expected == "Int")
                #expect(json == "\"Static fixture\"")
                #expect(error.localizedDescription.contains("Int"), "the description teaches the expected type")
                #expect(error.localizedDescription.contains("\"Static fixture\""), "and shows what the page sent")
            }
        }
    }
}
