import AppKit
import Foundation
@testable import SleepyHollow
import Testing
import TestSupport
import WebKit

/// The measurement behind the `--leave` step
/// (`project/2026-11-06-trusted-click.md` § Leaving the page): which route, from the
/// host's off-screen key-claiming window, moves the pointer so the clicked
/// element stops matching `:hover` and receives `mouseleave`/`pointerleave`.
///
/// Off unless `SLEEPY_MEASURE` is set: it prints rather than asserts. Run
/// `SLEEPY_MEASURE=1 swift test --filter PointerParkMeasurement`.
@Suite(
    "Pointer park measurement",
    .serialized,
    .enabled(if: ProcessInfo.processInfo.environment["SLEEPY_MEASURE"] != nil),
)
struct PointerParkMeasurementTests {
    /// One way of getting the pointer off the page, given the web view and
    /// its window.
    private struct Route {
        let label: String
        let send: @MainActor (WKWebView, NSWindow) -> Void
    }

    @MainActor
    private static func moved(_ location: NSPoint, in window: NSWindow) -> NSEvent? {
        NSEvent.mouseEvent(
            with: .mouseMoved,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 0,
            pressure: 0,
        )
    }

    @MainActor
    private static func exited(_ location: NSPoint, in window: NSWindow) -> NSEvent? {
        NSEvent.enterExitEvent(
            with: .mouseExited,
            location: location,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            trackingNumber: 0,
            userData: nil,
        )
    }

    @MainActor
    private static func simulate(_ location: NSPoint, on view: WKWebView, in window: NSWindow) {
        guard let event = moved(location, in: window) else { return }
        let selector = NSSelectorFromString(InputSPI.simulateMouseMove)
        typealias Move = @convention(c) (AnyObject, Selector, NSEvent) -> Void
        let move = unsafeBitCast(view.method(for: selector), to: Move.self)
        move(view, selector, event)
    }

    private static let routes: [Route] = [
        Route(label: "_simulateMouseMove: to (-1, -1), just outside the view's bottom-left") { view, window in
            simulate(NSPoint(x: -1, y: -1), on: view, in: window)
        },
        Route(label: "_simulateMouseMove: to (width + 50, height / 2), outside the right edge") { view, window in
            simulate(NSPoint(x: view.bounds.width + 50, y: view.bounds.height / 2), on: view, in: window)
        },
        Route(label: "_simulateMouseMove: to (-100000, -100000), far outside") { view, window in
            simulate(NSPoint(x: -100_000, y: -100_000), on: view, in: window)
        },
        Route(label: "-[WKWebView mouseExited:] with a mouseMoved event at (-1, -1)") { view, window in
            guard let event = moved(NSPoint(x: -1, y: -1), in: window) else { return }
            view.mouseExited(with: event)
        },
        Route(label: "NSWindow.sendEvent mouseMoved at (-1, -1)") { _, window in
            guard let event = moved(NSPoint(x: -1, y: -1), in: window) else { return }
            window.sendEvent(event)
        },
        Route(label: "-[WKWebView mouseExited:] with a real mouseExited event at (-1, -1)") { view, window in
            guard let event = exited(NSPoint(x: -1, y: -1), in: window) else { return }
            view.mouseExited(with: event)
        },
        Route(label: "_simulateMouseMove: with a real mouseExited event at (-1, -1)") { view, window in
            guard let event = exited(NSPoint(x: -1, y: -1), in: window) else { return }
            let selector = NSSelectorFromString(InputSPI.simulateMouseMove)
            typealias Move = @convention(c) (AnyObject, Selector, NSEvent) -> Void
            let move = unsafeBitCast(view.method(for: selector), to: Move.self)
            move(view, selector, event)
        },
        Route(label: "resign first responder, _simulateMouseMove: to (-1, -1), restore") { view, window in
            window.makeFirstResponder(nil)
            simulate(NSPoint(x: -1, y: -1), on: view, in: window)
            window.makeFirstResponder(view)
        },
        Route(label: "_simulateMouseMove: to (1, 1) inside the view, over the page background") { view, window in
            simulate(view.convert(NSPoint(x: 1, y: view.isFlipped ? 1 : view.bounds.height - 1), to: nil), on: view, in: window)
        },
    ]

    @MainActor
    private func state(_ host: PageHost) async throws -> String {
        try await host.evaluate("""
        const e = window.parkEvents; window.parkEvents = [];
        return JSON.stringify({
          hovered: Array.from(document.querySelectorAll(':hover')).map((n) => n.id || n.tagName).join('>'),
          goHover: document.getElementById('go').matches(':hover'),
          active: document.activeElement && document.activeElement.id,
          focusVisible: !!document.querySelector(':focus-visible'),
          hasFocus: document.hasFocus(),
          events: e,
        });
        """, in: .page)
    }

    @Test
    @MainActor
    func `which route takes the pointer off the page after a click`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let page = URL(string: "click-trusted.html", relativeTo: base)!
            for route in Self.routes {
                let host = PageHost()
                _ = try await host.load(page)
                _ = try await host.evaluate("""
                window.parkEvents = [];
                for (const t of ['blur', 'focus']) window.addEventListener(t, (ev) => { if (ev.target === window) window.parkEvents.push('window-' + t); });
                const field = document.createElement('input');
                field.id = 'field';
                field.style.cssText = 'position:absolute;left:600px;top:20px';
                document.body.appendChild(field);
                for (const t of ['blur', 'focus', 'focusin', 'focusout']) field.addEventListener(t, () => window.parkEvents.push(t + '@field'));
                for (const t of ['mouseleave', 'pointerleave', 'mouseout', 'pointerout', 'mousemove', 'pointermove']) {
                  document.getElementById('go').addEventListener(t, (ev) => window.parkEvents.push(
                    t + '@' + (ev.target.id || ev.target.tagName) + (ev.isTrusted ? '' : '!')));
                }
                return 1;
                """, as: Int.self, in: .page)
                let input = try TrustedInput(for: host, action: "click")
                let r: [Double] = try await host.evaluate(
                    "const r = document.getElementById('go').getBoundingClientRect();"
                        + "return [r.left + r.width / 2, r.top + r.height / 2];",
                    as: [Double].self,
                )
                try await input.click(atViewport: CGPoint(x: r[0], y: r[1]))
                // A focused text field, as after a --focus or a click into it:
                // whether a route disturbs focus is the side effect to watch.
                _ = try await host.evaluate("document.getElementById('field').focus(); return 1;", as: Int.self, in: .page)
                let before = try await state(host)
                let responder = input.window.firstResponder === host.webView
                let started = Date()
                route.send(host.webView, input.window)
                try await input.pointerLanded()
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                let after = try await state(host)
                print("== \(route.label) (\(ms) ms, web view first responder: \(responder), now \(input.window.firstResponder === host.webView))\n   after click: \(before)\n   after park:  \(after)")
            }
        }
    }
}
