import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// What a page's handlers see of a fractional `click --at` coordinate.
///
/// WebKit's `MouseEvent` truncates `clientX`/`clientY` to integers whatever
/// the init dictionary says, and a `PointerEvent` keeps the fraction for every
/// type except `click` and `auxclick`. So the pointer events carry exactly what
/// the agent typed, and `mousedown`/`mouseup`/`click` carry the truncation.
/// The second test is a canary: if it fails, WebKit has started keeping the
/// fraction on click, and the caveat in `click --help` can go.
@Suite("Click at a fractional point", .serialized)
struct ClickFractionalPointTests {
    /// Clicks `100.75, 300.25` on a page that records each event type's
    /// `[clientX, clientY, scrollX, scrollY]`, and returns what `type` saw.
    @MainActor
    private func seen(_ type: String) async throws -> [Double] {
        var result: [Double] = []
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "shadow-click.html", relativeTo: base)!)
            _ = try await host.execute(EvalOperation(
                source: """
                const gap = document.getElementById('gap');
                gap.addEventListener(type, (event) => {
                  window.sleepySeen = [event.clientX, event.clientY, window.scrollX, window.scrollY];
                });
                return 'armed';
                """,
                argumentsJSON: "{\"type\": \"\(type)\"}",
                world: .page,
            ))
            _ = try await host.execute(ClickOperation(point: DocumentPoint(x: 100.75, y: 300.25)))
            let text: String = try await host.execute(EvalOperation(source: "return window.sleepySeen;", world: .page))
            result = try JSONDecoder().decode([Double].self, from: Data(text.utf8))
        }
        return result
    }

    @Test(arguments: ["pointerdown", "pointerup"])
    @MainActor
    func `a pointer event carries the fractional clientX and clientY that were asked for`(type: String) async throws {
        let seen: [Double] = try await seen(type)
        #expect(seen[0] == 100.75 - seen[2], "\(type) saw \(seen)")
        #expect(seen[1] == 300.25 - seen[3], "\(type) saw \(seen)")
    }

    @Test(arguments: ["mousedown", "mouseup", "click"])
    @MainActor
    func `WebKit truncates a mouse event's clientX and clientY to whole pixels`(type: String) async throws {
        let seen: [Double] = try await seen(type)
        #expect(seen[0] == (100.75 - seen[2]).rounded(.down), "\(type) saw \(seen)")
        #expect(seen[1] == (300.25 - seen[3]).rounded(.down), "\(type) saw \(seen)")
    }
}
