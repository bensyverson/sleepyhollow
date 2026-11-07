import AppKit
import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// A page's copy lands in a pasteboard private to this process, never in the
/// clipboard of whoever runs `sleepy` (issue `OqJ4a7`).
///
/// WebKit's web content process hard-codes `NSPasteboardNameGeneral` for copy
/// and paste (`Pasteboard::createForCopyAndPaste`) and the UI process opens it
/// with `+[NSPasteboard pasteboardWithName:]`; no `WKWebView` or
/// `WKPreferences` lever picks another name. These tests go red if the
/// redirect in ``PasteboardIsolation`` stops reaching WebKit.
///
/// `.serialized`: the pasteboards are process-wide.
@Suite("Pasteboard isolation", .serialized)
struct PasteboardIsolationTests {
    @Test
    @MainActor
    func `a page's copy leaves the user's clipboard alone and lands in the private one`() async throws {
        PasteboardIsolation.ensureApplied()
        let user: NSPasteboard = try #require(PasteboardIsolation.userPasteboard)
        let saved: String? = user.string(forType: .string)
        // Restores the user's text clipboard even if the isolation is broken
        // and the page's copy reached it.
        defer {
            if let saved, user.string(forType: .string) != saved {
                user.clearContents()
                user.setString(saved, forType: .string)
            }
        }
        let before: Int = user.changeCount

        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(steps: [.click(selector: "#b")]))
            let url = try #require(URL(string: "copy-button.html", relativeTo: base))
            _ = try await host.load(url)
        }

        let copied: String? = PasteboardIsolation.pagePasteboard?.string(forType: .string)
        #expect(copied == "PAGE-COPY-SENTINEL-42")
        #expect(user.changeCount == before, "the page's copy changed the user's clipboard")
        #expect(user.string(forType: .string) == saved)
    }

    @Test
    @MainActor
    func `isolation is the default`() {
        #expect(PageHost.clipboardIsolation == .isolated)
    }

    @Test
    @MainActor
    func `choosing shared restores the system pasteboard and choosing isolated redirects it again`() throws {
        PasteboardIsolation.ensureApplied()
        defer { PageHost.clipboardIsolation = .isolated }
        let user = try #require(PasteboardIsolation.userPasteboard)
        let page = try #require(PasteboardIsolation.pagePasteboard)

        PageHost.clipboardIsolation = .shared
        #expect(NSPasteboard.general === user)
        #expect(NSPasteboard(name: .general) === user)
        #expect(!PasteboardIsolation.isIsolated)

        PageHost.clipboardIsolation = .isolated
        #expect(NSPasteboard.general === page)
        #expect(NSPasteboard(name: .general) === page)
        #expect(PasteboardIsolation.isIsolated)
    }

    @Test
    @MainActor
    func `doctor passes when the embedder chose shared, and says so`() {
        defer { PageHost.clipboardIsolation = .isolated }
        PageHost.clipboardIsolation = .shared
        let check: DoctorCheck = Doctor.checkPasteboardIsolation()
        #expect(check.status == .ok)
        #expect(check.detail.contains("shared"))
    }

    @Test
    @MainActor
    func `doctor reports the pasteboard isolation`() {
        let check: DoctorCheck = Doctor.checkPasteboardIsolation()
        #expect(check.status == .ok, "\(check.detail)")
        #expect(check.name == .pasteboard)
    }
}
