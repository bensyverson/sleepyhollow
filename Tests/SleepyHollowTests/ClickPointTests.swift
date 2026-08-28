import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `sleepy click --at x,y`: a real hit test, in document CSS px, that
/// descends through open shadow roots.
///
/// The pairing matters more than either test alone — the same button is
/// unreachable by `--selector` on its host (the first field report's item 6)
/// and reachable by its coordinates, which is the whole point of the verb.
@Suite("Click at a point", .serialized)
struct ClickPointTests {
    @MainActor
    private func host(base: URL) async throws -> PageHost {
        let host = PageHost()
        _ = try await host.load(URL(string: "shadow-click.html", relativeTo: base)!)
        return host
    }

    /// The document-space centre of the button inside `hostID`'s shadow root,
    /// measured the way an agent would: `getBoundingClientRect` plus scroll.
    @MainActor
    private func shadowButtonCentre(in hostID: String, on host: PageHost) async throws -> DocumentPoint {
        let text: String = try await host.execute(EvalOperation(
            source: """
            const element = document.getElementById(id);
            const rect = element.shadowRoot.querySelector('#inner').getBoundingClientRect();
            return [
              rect.left + rect.width / 2 + window.scrollX,
              rect.top + rect.height / 2 + window.scrollY,
            ];
            """,
            argumentsJSON: "{\"id\": \"\(hostID)\"}",
            world: .page,
        ))
        let parts: [Double] = try JSONDecoder().decode([Double].self, from: Data(text.utf8))
        return DocumentPoint(x: parts[0], y: parts[1])
    }

    @MainActor
    private func title(of host: PageHost) async throws -> String {
        try await host.execute(EvalOperation(source: "return document.title;", world: .page))
    }

    @MainActor
    private func activated(_ hostID: String, on host: PageHost) async throws -> String {
        try await host.execute(EvalOperation(
            source: "return document.getElementById(id).dataset.activated;",
            argumentsJSON: "{\"id\": \"\(hostID)\"}",
            world: .page,
        ))
    }

    @Test
    @MainActor
    func `a click at its coordinates activates a button inside an open shadow root`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let point: DocumentPoint = try await shadowButtonCentre(in: "panel", on: host)
            _ = try await host.execute(ClickOperation(point: point))
            #expect(try await activated("panel", on: host) == "\"yes\"")
            #expect(try await title(of: host) == "\"activated:panel\"")
        }
    }

    @Test
    @MainActor
    func `a selector click on the host does not reach the shadow button`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let outcome = try await host.execute(ClickOperation(selector: "#panel"))
            #expect(outcome.tagName == "shadow-panel")
            #expect(try await activated("panel", on: host) == "\"no\"")
            #expect(try await title(of: host) == "\"idle\"")
        }
    }

    @Test
    @MainActor
    func `the outcome names what was hit, and that it was inside a shadow root`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let point: DocumentPoint = try await shadowButtonCentre(in: "panel", on: host)
            let outcome = try await host.execute(ClickOperation(point: point))
            #expect(outcome.action == .click)
            #expect(outcome.selector == nil)
            #expect(outcome.tagName == "button")
            #expect(outcome.startedNavigation == false)
            let hit = try #require(outcome.hit)
            #expect(hit.tagName == "button")
            #expect(hit.id == "inner")
            #expect(hit.classes == ["go", "primary"])
            #expect(hit.shadowDepth == 1)
            #expect(hit.insideShadowRoot)
            #expect(hit.point == point)
        }
    }

    @Test
    @MainActor
    func `a selector click reports no hit-test result, because it did none`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let outcome = try await host.execute(ClickOperation(selector: "#panel"))
            #expect(outcome.hit == nil)
            #expect(outcome.selector == "#panel")
        }
    }

    @Test
    @MainActor
    func `a point on nothing but the page background is a clean negative naming it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            do {
                _ = try await host.execute(ClickOperation(point: DocumentPoint(x: 1000, y: 600)))
                Issue.record("expected a clean negative")
            } catch let error as SleepyError {
                #expect(error.kind == .negative)
                #expect(error.description.contains("1000,600"))
            }
        }
    }

    @Test
    @MainActor
    func `a point past the end of the document is a clean negative naming it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            do {
                _ = try await host.execute(ClickOperation(point: DocumentPoint(x: 40, y: 99000)))
                Issue.record("expected a clean negative")
            } catch let error as SleepyError {
                #expect(error.kind == .negative)
                #expect(error.description.contains("40,99000"))
            }
        }
    }

    @Test
    @MainActor
    func `--at is document space: a point below the fold is scrolled to and clicked`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = try await host(base: base)
            let point: DocumentPoint = try await shadowButtonCentre(in: "deep", on: host)
            #expect(point.y > 800, "the deep panel must start below the 800px viewport for this to test anything")
            let outcome = try await host.execute(ClickOperation(point: point))
            #expect(outcome.tagName == "button")
            #expect(try await activated("deep", on: host) == "\"yes\"")
            #expect(try await title(of: host) == "\"activated:deep\"")
        }
    }
}
