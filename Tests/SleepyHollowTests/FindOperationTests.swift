import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `FindOperation`: `WKWebView.find` against real fixtures — proving the
/// ⌘F claim empirically rather than assuming it: rendered text matches,
/// `display: none` text does not, and a bare tag name (markup, never
/// rendered as text) does not either.
@Suite("FindOperation")
struct FindOperationTests {
    @Test
    @MainActor
    func `rendered text is found`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "dom-hidden.html", relativeTo: base)!)
            let matched = try await host.execute(FindOperation(text: "rendered and visible"))
            #expect(matched == true)
        }
    }

    @Test
    @MainActor
    func `display none text is not found`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "dom-hidden.html", relativeTo: base)!)
            let matched = try await host.execute(FindOperation(text: "display none"))
            #expect(matched == false)
        }
    }

    @Test
    @MainActor
    func `a tag name present only in markup is not found`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "dom-nested.html", relativeTo: base)!)
            // "main" never appears as rendered text on this fixture — only
            // as the <main> tag name.
            let matched = try await host.execute(FindOperation(text: "main"))
            #expect(matched == false)
        }
    }

    @Test
    @MainActor
    func `text absent from the page entirely is not found`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let matched = try await host.execute(FindOperation(text: "nonexistent phrase"))
            #expect(matched == false)
        }
    }
}
