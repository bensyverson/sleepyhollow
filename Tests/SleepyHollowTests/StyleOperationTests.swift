import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `StyleOperation`: computed values for the first match, and the honest
/// empty-value answer for a property the platform doesn't recognize.
@Suite("StyleOperation")
struct StyleOperationTests {
    @Test
    @MainActor
    func `computed values reflect the fixture's own CSS`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "theme.html", relativeTo: base)!)
            let result = try await host.execute(
                StyleOperation(selector: "body", properties: ["display", "background-color"]),
            )
            #expect(result.matched == true)
            #expect(result.values["display"] == "block")
            #expect(result.values["background-color"] == "rgb(255, 255, 255)")
        }
    }

    @Test
    @MainActor
    func `a selector matching nothing reports matched false and no values`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let result = try await host.execute(StyleOperation(selector: "#nope", properties: ["display"]))
            #expect(result.matched == false)
            #expect(result.values.isEmpty)
        }
    }

    @Test
    @MainActor
    func `an unrecognized property returns its empty computed value`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let result = try await host.execute(
                StyleOperation(selector: "h1", properties: ["not-a-real-property"]),
            )
            #expect(result.matched == true)
            #expect(result.values["not-a-real-property"] == "")
        }
    }

    @Test
    @MainActor
    func `only the first match is read when several elements match`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "dom-hidden.html", relativeTo: base)!)
            // The first <p> in document order is #visible.
            let result = try await host.execute(StyleOperation(selector: "p", properties: ["display"]))
            #expect(result.matched == true)
            #expect(result.values["display"] == "block")
        }
    }
}
