import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The `window.sleepy` helper library, exercised as JavaScript against real
/// fixtures — the layer both assertion verbs and an agent's own `eval` call.
///
/// Everything here runs in ``InjectedScript/World/page``, because that is
/// where the library is installed and where `sleepy eval` now looks by
/// default.
@Suite("SleepyHelpers")
struct SleepyHelpersTests {
    /// What `sleepy.effectiveBackground()` answers, decoded for assertions.
    private struct Background: Decodable {
        let kind: String
        let rgba: [Double]?
        let reason: String?
    }

    /// `sleepy.rect()` plus the scroll offset that proves its coordinates.
    private struct ScrolledRect: Decodable {
        let scrollY: Double
        let rect: DocumentRect?
    }

    private func decode<Value: Decodable>(_: Value.Type, from json: String) throws -> Value {
        try JSONDecoder().decode(Value.self, from: Data(json.utf8))
    }

    @Test
    @MainActor
    func `the namespace is installed in the page world`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "helpers.html", relativeTo: base)!)
            let kind: String = try await host.evaluate("return typeof window.sleepy;", in: .page)
            #expect(kind == "\"object\"")
            let functions: String = try await host.evaluate(
                "return Object.keys(window.sleepy).sort();",
                in: .page,
            )
            #expect(functions.contains("contrast"))
            #expect(functions.contains("effectiveBackground"))
            #expect(functions.contains("overflow"))
            #expect(functions.contains("rect"))
        }
    }

    @Test
    @MainActor
    func `the namespace is absent from the isolated world`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "helpers.html", relativeTo: base)!)
            let kind: String = try await host.evaluate("return typeof window.sleepy;", in: .isolated)
            #expect(kind == "\"undefined\"")
        }
    }

    @Test
    @MainActor
    func `rect reports the element's CSS-px box`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "helpers.html", relativeTo: base)!)
            let json: String = try await host.evaluate("return sleepy.rect('h1');", in: .page)
            let rect: DocumentRect = try decode(DocumentRect.self, from: json)
            #expect(rect.x == 0)
            #expect(rect.y == 0)
            #expect(rect.height == 60)
            #expect(rect.width == 1280)
        }
    }

    @Test
    @MainActor
    func `rect is in document coordinates, not viewport ones`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "helpers.html", relativeTo: base)!)
            let json: String = try await host.evaluate(
                "window.scrollTo(0, 200); return { scrollY: window.scrollY, rect: sleepy.rect('h1') };",
                in: .page,
            )
            let scrolled: ScrolledRect = try decode(ScrolledRect.self, from: json)
            #expect(scrolled.scrollY == 200)
            #expect(scrolled.rect?.y == 0)
        }
    }

    @Test
    @MainActor
    func `rect answers null when nothing matches, and a box when something does`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "helpers.html", relativeTo: base)!)
            let missing: String = try await host.evaluate("return sleepy.rect('.no-such-thing');", in: .page)
            #expect(missing == "null")
            let matched: String = try await host.evaluate("return sleepy.rect('h1') !== null;", in: .page)
            #expect(matched == "true")
            let malformed: String = try await host.evaluate("return sleepy.rect('>>>');", in: .page)
            #expect(malformed == "null")
        }
    }

    @Test
    @MainActor
    func `effectiveBackground composites a translucent layer over its ancestor`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "helpers.html", relativeTo: base)!)
            let json: String = try await host.evaluate(
                "return sleepy.effectiveBackground(document.getElementById('over-half'));",
                in: .page,
            )
            let background: Background = try decode(Background.self, from: json)
            #expect(background.kind == "color")
            let rgba: [Double] = try #require(background.rgba)
            // 50% white over black is mid grey; anything that ignored the
            // alpha would answer 255 or 0.
            #expect(abs(rgba[0] - 127.5) < 1.0)
            #expect(abs(rgba[1] - 127.5) < 1.0)
            #expect(abs(rgba[2] - 127.5) < 1.0)
            #expect(rgba[3] == 1)
        }
    }

    @Test
    @MainActor
    func `effectiveBackground reports unknown at the first background image`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "helpers.html", relativeTo: base)!)
            let json: String = try await host.evaluate(
                "return sleepy.effectiveBackground(document.getElementById('over-image'));",
                in: .page,
            )
            let background: Background = try decode(Background.self, from: json)
            #expect(background.kind == "unknown")
            #expect(background.reason == "image")
            #expect(background.rgba == nil)
        }
    }

    @Test
    @MainActor
    func `contrast and overflow answer directly from the page world`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "helpers.html", relativeTo: base)!)
            let contrast: String = try await host.evaluate("return sleepy.contrast().checked;", in: .page)
            #expect(Int(contrast) ?? 0 > 0)
            let overflow: String = try await host.evaluate("return sleepy.overflow().viewportWidth;", in: .page)
            #expect(overflow == "1280")
        }
    }
}
