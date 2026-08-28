import CoreGraphics
import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// One coordinate space across the verbs that report or take a rect.
///
/// The loop these tests defend is the one an agent actually runs: `query` a
/// box, `click --at` its centre, `shot --rect` the same numbers. Each step
/// can move the scroll offset, so a rect that was viewport-relative is wrong
/// by the time it is pasted back — the bug the coordinate-click leaf found
/// on 2026-08-28. Every assertion here is therefore made *after* a scroll.
@Suite("Geometry space", .serialized)
struct GeometrySpaceTests {
    /// The fixture's `#target`: `left: 100px; top: 2400px; 200×150`.
    private static let tallTarget = ElementFact.Geometry(x: 100, y: 2400, width: 200, height: 150)

    /// The wide fixture's `#target`: `left: 900px; top: 2400px; 300×200`.
    private static let wideTarget = ElementFact.Geometry(x: 900, y: 2400, width: 300, height: 200)

    @MainActor
    private func host(_ fixture: String, base: URL) async throws -> PageHost {
        let host = PageHost()
        _ = try await host.load(URL(string: fixture, relativeTo: base)!)
        return host
    }

    /// Scrolls the page and returns where it actually landed, so a test that
    /// depends on being scrolled fails loudly if it is not.
    @MainActor
    @discardableResult
    private func scroll(_ host: PageHost, to point: CGPoint) async throws -> CGPoint {
        let text: String = try await host.execute(EvalOperation(
            source: "window.scrollTo(x, y); return [window.scrollX, window.scrollY];",
            argumentsJSON: "{\"x\": \(point.x), \"y\": \(point.y)}",
            world: .page,
        ))
        let parts: [Double] = try JSONDecoder().decode([Double].self, from: Data(text.utf8))
        return CGPoint(x: parts[0], y: parts[1])
    }

    @MainActor
    private func geometry(of selector: String, on host: PageHost) async throws -> ElementFact.Geometry {
        let facts = try await host.execute(QueryOperation(selector: selector))
        return try #require(facts.first).geometry
    }

    @Test
    @MainActor
    func `a vertical scroll does not move the geometry query reports`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host("capture-tall.html", base: base)
            let unscrolled = try await geometry(of: "#target", on: host)
            #expect(unscrolled == Self.tallTarget)
            #expect(try await scroll(host, to: CGPoint(x: 0, y: 1500)).y == 1500)
            #expect(try await geometry(of: "#target", on: host) == unscrolled)
        }
    }

    @Test
    @MainActor
    func `a horizontal scroll does not move the geometry query reports`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host("capture-wide.html", base: base)
            let unscrolled = try await geometry(of: "#target", on: host)
            #expect(unscrolled == Self.wideTarget)
            #expect(try await scroll(host, to: CGPoint(x: 800, y: 0)).x == 800)
            #expect(try await geometry(of: "#target", on: host) == unscrolled)
        }
    }

    @Test
    @MainActor
    func `the centre of a queried rect is what click --at hits, on a scrolled page`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host("capture-tall.html", base: base)
            try await scroll(host, to: CGPoint(x: 0, y: 1500))
            let rect = try await geometry(of: "#target", on: host)
            let centre = DocumentPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
            let outcome = try await host.execute(ClickOperation(point: centre))
            let hit = try #require(outcome.hit)
            #expect(hit.tagName == "div")
            #expect(hit.id == "target")
        }
    }

    @Test
    @MainActor
    func `a queried rect crops the same pixels as the element shot, on a scrolled page`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host("capture-tall.html", base: base)
            try await scroll(host, to: CGPoint(x: 0, y: 1500))
            let rect = try await geometry(of: "#target", on: host)
            let byRect = try await host.execute(ShotOperation(region: .rect(CGRect(
                x: rect.x,
                y: rect.y,
                width: rect.width,
                height: rect.height,
            ))))
            try await scroll(host, to: CGPoint(x: 0, y: 1500))
            let byElement = try await host.execute(ShotOperation(region: .element("#target")))
            #expect(byRect.images[0].png == byElement.images[0].png)
        }
    }

    @Test
    @MainActor
    func `a horizontally scrolled page still crops shot --rect in document space`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host("capture-wide.html", base: base)
            try await scroll(host, to: CGPoint(x: 800, y: 0))
            let byRect = try await host.execute(ShotOperation(region: .rect(CGRect(
                x: Self.wideTarget.x,
                y: Self.wideTarget.y,
                width: Self.wideTarget.width,
                height: Self.wideTarget.height,
            ))))
            try await scroll(host, to: CGPoint(x: 800, y: 0))
            let byElement = try await host.execute(ShotOperation(region: .element("#target")))
            #expect(byRect.images[0].png == byElement.images[0].png)
        }
    }
}
