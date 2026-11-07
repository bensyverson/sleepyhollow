import AppKit
import Foundation
import QuartzCore
@testable import SleepyHollow
import Testing
import TestSupport
import WebKit

/// The compositor path's moving parts on their own: the private WebKit hook
/// it waits on, and the layer surgery `CARenderer` forces on it.
@Suite("Compositor renderer")
struct CompositorRendererTests {
    /// Red if WebKit drops or renames the readiness hook: shots would then
    /// fall back to `takeSnapshot` on every page (and say so), which is
    /// survivable, but it is a change to notice rather than discover.
    @Test
    @MainActor
    func `WebKit still offers the presentation-update hook`() {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(CompositorSPI.supportsPresentationUpdate(webView))
    }

    @Test
    @MainActor
    func `the presentation-update hook calls back on a live page`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(#require(URL(string: "static.html", relativeTo: base)))
            try await host.waitForPresentationUpdate()
        }
    }

    @Test
    @MainActor
    func `a detached layer goes back where it was, even when the render throws`() throws {
        let parent = CALayer()
        let before = CALayer()
        let layer = CALayer()
        let after = CALayer()
        parent.sublayers = [before, layer, after]
        struct Failure: Error {}
        #expect(throws: Failure.self) {
            try CompositorRenderer.withLayer(layer, in: CALayer()) { _ in throw Failure() }
        }
        #expect(layer.superlayer === parent)
        #expect(parent.sublayers?.map(ObjectIdentifier.init) == [before, layer, after].map(ObjectIdentifier.init))
    }

    /// AppKit builds the window's own layers on its first display pass, so a
    /// view parked a moment ago has a backing layer with no superlayer yet —
    /// nothing to put it back into after the render. Seen under load in
    /// `CaptureShotWindowedFullPageTests`, which parks its host just before
    /// loading.
    @Test
    @MainActor
    func `a freshly parked view's layer is placed in its window before rendering`() throws {
        let host = PageHost(hosting: .windowless)
        host.ensureOffscreenWindow(rendering: .live)
        let layer = try host.compositedLayer()
        #expect(layer.superlayer != nil)
    }

    @Test
    @MainActor
    func `a capture leaves the web view's layer in its window`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(#require(URL(string: "static.html", relativeTo: base)))
            // Through compositedLayer(), which runs the window's first display
            // pass: straight after a load on a loaded machine, a just-parked
            // view's layer may have no superlayer yet, and this test is about
            // the capture moving it, not about when the first pass runs.
            let layer = try host.compositedLayer()
            let parent = layer.superlayer
            #expect(parent != nil)
            let capture = try await ShotOperation().render(on: host)
            #expect(capture.renderer == .compositor)
            #expect(layer.superlayer === parent)
            #expect(host.webView.layer === layer)
        }
    }

    @Test
    func `strips never exceed the texture limit and cover every row`() {
        let rows = CompositorRenderer.strips(height: 25964, width: 640)
        #expect(rows.first?.lowerBound == 0)
        #expect(rows.last?.upperBound == 25964)
        for (one, next) in zip(rows, rows.dropFirst()) {
            #expect(one.upperBound == next.lowerBound)
        }
        #expect(rows.allSatisfy { $0.count <= CompositorRenderer.maximumTextureSide })
        #expect(rows.allSatisfy { $0.count * 640 * 4 <= CompositorRenderer.stripByteBudget })
    }
}
