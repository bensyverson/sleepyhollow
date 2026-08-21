import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `QueryOperation`: matched-element facts, and the visibility definition.
@Suite("QueryOperation")
struct QueryOperationTests {
    @Test
    @MainActor
    func `the disabled Publish button reports its facts`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "form.html", relativeTo: base)!)
            let elements = try await host.execute(QueryOperation(selector: "#publish"))
            let publish = try #require(elements.first)
            #expect(elements.count == 1)
            #expect(publish.tagName == "button")
            #expect(publish.text == "Publish")
            #expect(publish.attributes["disabled"] == "")
            #expect(publish.geometry.width > 0)
            #expect(publish.geometry.height > 0)
            #expect(publish.visible == true)
        }
    }

    @Test
    @MainActor
    func `a selector matching nothing returns an empty array, not an error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let elements = try await host.execute(QueryOperation(selector: "#does-not-exist"))
            #expect(elements.isEmpty)
        }
    }

    @Test
    @MainActor
    func `display none, visibility hidden, opacity zero, and zero size are all invisible`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "dom-hidden.html", relativeTo: base)!)
            let elements = try await host.execute(QueryOperation(selector: "p"))
            let byID = Dictionary(uniqueKeysWithValues: elements.map { ($0.attributes["id"] ?? "", $0) })
            #expect(byID["visible"]?.visible == true)
            #expect(byID["display-none"]?.visible == false)
            #expect(byID["visibility-hidden"]?.visible == false)
            #expect(byID["opacity-zero"]?.visible == false)
            #expect(byID["zero-size"]?.visible == false)
        }
    }
}
