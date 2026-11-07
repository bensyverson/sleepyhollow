import AppKit
import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The `--hover` and `--focus` staging steps (leaf `fFz9DI`): a real pointer
/// for `:hover`, and a keyboard-style focus for `:focus-visible`.
@Suite("Hover and focus steps", .serialized)
struct HoverFocusStepTests {
    /// What `stage-hover-focus.html` reports.
    private struct StageFacts: Decodable {
        struct Entry: Decodable {
            let type: String
            let isTrusted: Bool
            let target: String
        }

        let hover: Bool
        let focus: Bool
        let focusVisible: Bool
        let log: [Entry]
    }

    @MainActor
    private func facts(after steps: [ActionStep], base: URL) async throws -> StageFacts {
        var options = LoadOptions(size: ViewportSize(width: 400, height: 240))
        options.steps = steps
        options.budget = TestSupport.livenessBudget
        let host = PageHost(options: options)
        _ = try await host.load(#require(URL(string: "stage-hover-focus.html", relativeTo: base)))
        let json: String = try await host.evaluate("return window.stageFacts();", in: .page)
        return try JSONDecoder().decode(StageFacts.self, from: Data(json.utf8))
    }

    @Test
    @MainActor
    func `a hover step puts a real pointer over the element`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let facts = try await facts(after: [.hover(selector: "#card")], base: base)
            #expect(facts.hover)
            let over = try #require(facts.log.first { $0.type == "mouseover" })
            #expect(over.isTrusted)
            #expect(over.target == "card")
        }
    }

    @Test
    @MainActor
    func `a focus step focuses as a keyboard would, so focus-visible matches`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let facts = try await facts(after: [.focus(selector: "#action")], base: base)
            #expect(facts.focus)
            #expect(facts.focusVisible)
        }
    }

    @Test
    @MainActor
    func `a focus step after a pointer click still shows the keyboard focus style`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 400, height: 240)))
            _ = try await host.load(#require(URL(string: "stage-hover-focus.html", relativeTo: base)))
            // A real pointer click on the button: after one, WebKit gives a
            // plain `focus()` no :focus-visible (measured 2026-11-06).
            let window = try #require(host.webView.window)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                let event = try #require(NSEvent.mouseEvent(
                    with: type,
                    location: host.webView.convert(NSPoint(x: 300, y: 70), to: nil),
                    modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber,
                    context: nil,
                    eventNumber: 0,
                    clickCount: 1,
                    pressure: 0,
                ))
                window.sendEvent(event)
            }
            // The click lands asynchronously; wait for it, as a liveness
            // bound rather than a race.
            var clicked = false
            for _ in 0 ..< 600 where !clicked {
                clicked = try await host.evaluate(
                    "return window.stageFacts().log.some((e) => e.type === 'click' && e.isTrusted);",
                    as: Bool.self,
                    in: .page,
                )
                if !clicked { try await Task.sleep(nanoseconds: 50_000_000) }
            }
            try #require(clicked)
            let outcome = try await host.execute(FocusOperation(selector: "#action"))
            #expect(outcome.action == .focus)
            #expect(outcome.tagName == "button")
            let visible: Bool = try await host.evaluate(
                "return document.getElementById('action').matches(':focus-visible');",
                as: Bool.self,
                in: .page,
            )
            #expect(visible)
        }
    }

    @Test
    @MainActor
    func `focusing an element that cannot take focus is a usage error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(#require(URL(string: "stage-hover-focus.html", relativeTo: base)))
            do {
                _ = try await host.execute(FocusOperation(selector: "#card"))
                Issue.record("focused a plain div")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
                #expect(error.message.contains("focus"))
            }
        }
    }

    @Test
    @MainActor
    func `hovering nothing is a clean negative`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(#require(URL(string: "stage-hover-focus.html", relativeTo: base)))
            do {
                _ = try await host.execute(HoverOperation(selector: "#nowhere"))
                Issue.record("hovered nothing")
            } catch let error as SleepyError {
                #expect(error.kind == .negative)
            }
        }
    }

    @Test
    @MainActor
    func `a windowless host refuses to hover rather than pretend`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(hosting: .windowless)
            _ = try await host.load(#require(URL(string: "stage-hover-focus.html", relativeTo: base)))
            do {
                _ = try await host.execute(HoverOperation(selector: "#card"))
                Issue.record("hovered without a window")
            } catch let error as SleepyError {
                #expect(error.kind == .usage)
            }
        }
    }
}
