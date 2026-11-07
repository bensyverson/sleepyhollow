import CoreGraphics
import Foundation
import SleepyHollow
import Testing
import TestSupport

/// A shot says when its area holds CSS 3D that `takeSnapshot`'s flat paint
/// draws wrong — and, as much the point, stays quiet about 3D-looking CSS it
/// draws right, because a caveat that fires on every `translateZ(0)` teaches
/// an agent to ignore it.
///
/// `capture-3d.html` lays the four flagged cases out in its first row, the
/// look-alikes that flatten faithfully in its second, and one more flagged
/// case below the fold.
///
/// Every host here is windowless, so the shot falls back to `takeSnapshot`
/// (``ShotRenderer/Fallback/windowless``): the finding belongs to that flat
/// renderer, and a live host's compositor draws the same page in true 3D
/// with nothing to report (`CaptureShotRendererTests`).
@Suite("ShotOperation flattened 3D")
struct CaptureShotFlattened3DTests {
    /// Loads the fixture and runs `operation` against it.
    @MainActor
    private func shoot(_ operation: ShotOperation, base: URL) async throws -> ShotOperation.Output {
        let host = PageHost(hosting: .windowless)
        _ = try await host.load(URL(string: "capture-3d.html", relativeTo: base)!)
        return try await host.execute(operation)
    }

    @Test
    @MainActor
    func `a viewport shot names exactly the four cases flattening changes, with why`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let output = try await shoot(ShotOperation(), base: base)
            let byPath: [String: [FlattenedElement.Reason]] = Dictionary(
                uniqueKeysWithValues: output.flattened3D.map { ($0.path, $0.reasons) },
            )
            #expect(byPath == [
                "div#tilted": [.perspectiveAncestor],
                "div#own": [.perspectiveFunction],
                "div#stack": [.preserve3D],
                "div#back": [.hiddenBackface],
            ])
        }
    }

    @Test
    @MainActor
    func `each flagged element carries its document rect`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let output = try await shoot(ShotOperation(), base: base)
            let back = try #require(output.flattened3D.first { $0.path == "div#back" })
            // 200×100 at (775, 75); a 180° turn about its centre keeps the box.
            #expect(abs(back.rect.x - 775) < 1)
            #expect(abs(back.rect.y - 75) < 1)
            #expect(abs(back.rect.width - 200) < 1)
        }
    }

    @Test
    @MainActor
    func `2D transforms, a bare orthographic rotation and the usual hacks flag nothing`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            // Row 2 only: every look-alike, and nothing else.
            let output = try await shoot(ShotOperation(region: .rect(CGRect(x: 0, y: 300, width: 1000, height: 250))), base: base)
            #expect(output.flattened3D.isEmpty, "\(output.flattened3D)")
        }
    }

    @Test(arguments: ["#flat-2d", "#flat-ortho", "#flat-front", "#flat-hacks"])
    @MainActor
    func `an element shot of a look-alike flags nothing`(selector: String) async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let output = try await shoot(ShotOperation(region: .element(selector)), base: base)
            #expect(output.flattened3D.isEmpty, "\(output.flattened3D)")
        }
    }

    @Test
    @MainActor
    func `an element shot names only the 3D inside it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let output = try await shoot(ShotOperation(region: .element("#case-back")), base: base)
            #expect(output.flattened3D.map(\.path) == ["div#back"])
        }
    }

    @Test
    @MainActor
    func `a rect that excludes the 3D flags nothing`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            // Between the rows: touches no cell.
            let output = try await shoot(ShotOperation(region: .rect(CGRect(x: 0, y: 260, width: 1280, height: 30))), base: base)
            #expect(output.flattened3D.isEmpty, "\(output.flattened3D)")
        }
    }

    @Test
    @MainActor
    func `3D below the fold is in a full-page shot and not in the viewport`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let viewport = try await shoot(ShotOperation(), base: base)
            let full = try await shoot(ShotOperation(region: .fullPage), base: base)
            #expect(!viewport.flattened3D.contains { $0.path == "div#deep" })
            #expect(full.flattened3D.contains { $0.path == "div#deep" })
        }
    }

    /// three.js's CSS3DRenderer: a perspective camera div, a preserve-3d
    /// scene with its own matrix3d, panels placed by matrix3d inside it
    /// (field report, `project/2026-11-06-webgl-scene-feedback.md`). The
    /// scene is the outermost flagged element, so it is the one named.
    @Test
    @MainActor
    func `a CSS3DRenderer-shaped scene is flagged`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let output = try await shoot(ShotOperation(region: .element("#case-css3d")), base: base)
            #expect(output.flattened3D.map(\.path) == ["div#css3d-scene"])
            #expect(output.flattened3D.first?.reasons == [.perspectiveAncestor, .preserve3D])
        }
    }

    @Test
    @MainActor
    func `the render stage carries the finding for an in-process embedder`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(hosting: .windowless)
            _ = try await host.load(URL(string: "capture-3d.html", relativeTo: base)!)
            let capture: ShotCapture = try await ShotOperation(region: .element("#case-own")).render(on: host)
            #expect(capture.flattened3D.map(\.path) == ["div#own"])
        }
    }

    @Test
    @MainActor
    func `a tiled shot reports once per render, on the output`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let output = try await shoot(ShotOperation(region: .fullPage, tile: .cssPixels(600)), base: base)
            #expect(output.images.count > 1)
            #expect(output.flattened3D.map(\.path).sorted() == ["div#back", "div#css3d-scene", "div#deep", "div#own", "div#stack", "div#tilted"])
        }
    }

    @Test
    @MainActor
    func `a page with no 3D flags nothing`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(hosting: .windowless)
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let output = try await host.execute(ShotOperation(region: .fullPage))
            #expect(output.flattened3D.isEmpty)
        }
    }
}
