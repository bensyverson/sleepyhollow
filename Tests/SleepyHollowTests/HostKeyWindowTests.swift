import AppKit
import Foundation
import SleepyHollow
import Testing
import TestSupport

/// The host window claims key and main status, so the page has focus the way
/// a page in the frontmost browser window does (leaf `AuYtct`).
///
/// The pixel half — native controls drawn active — is
/// `ActiveControlsGoldenTests`, through the binary.
@Suite("Host key window")
struct HostKeyWindowTests {
    /// What `controls-focused.html` believes about focus.
    private struct FocusFacts: Decodable {
        let hasFocus: Bool
        let activeIsInput: Bool
        let focus: Bool
        let focusVisible: Bool
        let windowEvents: [String]
    }

    @Test
    @MainActor
    func `a default host's window claims key and main`() throws {
        let host = PageHost()
        let window = try #require(host.webView.window)
        #expect(window.isKeyWindow)
        #expect(window.isMainWindow)
        // Claimed, not taken: the app is never activated.
        #expect(NSApp.isActive == false)
    }

    @Test
    @MainActor
    func `a focused input matches focus and focus-visible, and the document has focus`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(#require(URL(string: "controls-focused.html", relativeTo: base)))
            let json = try await host.evaluate("return window.focusFacts();", in: .page)
            let facts = try JSONDecoder().decode(FocusFacts.self, from: Data(json.utf8))
            #expect(facts.activeIsInput)
            #expect(facts.hasFocus)
            #expect(facts.focus)
            #expect(facts.focusVisible)
            // The window never became key, so it never announced it.
            #expect(facts.windowEvents.isEmpty)
        }
    }
}
