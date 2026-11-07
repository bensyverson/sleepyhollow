import AppKit
import Foundation
import WebKit

/// Real keyboard and pointer input for a hosted page: `NSEvent`s sent through
/// the host's window, so the page receives them with `isTrusted` true and the
/// browser runs their default actions — text typed into a field, Tab moving
/// focus, Enter submitting a form, `:hover` following the pointer.
///
/// This is what separates `press`, `click` and the hover step from the
/// synthesized DOM events of `fill` and `submit` (``ActionScript``): those
/// are dispatched page-side and the page can tell; these come from AppKit,
/// the way a keyboard's and a mouse's do. It works because every ``PageHost/Hosting/live``
/// host is parked in an ``OffscreenWindow`` that claims key status: the web
/// view is made first responder there, and WebKit treats key events sent to
/// that window as the frontmost window's. A ``PageHost/Hosting/windowless``
/// host has no window to send through, and is refused rather than faked.
///
/// **Keys** go through `NSWindow.sendEvent(_:)`: a `flagsChanged` per
/// modifier going down, `keyDown`/`keyUp`, then the modifiers released in
/// reverse — so the page sees `keydown Shift` before `keydown Tab`, as from
/// a keyboard. **The pointer moves** through
/// `-[WKWebView _simulateMouseMove:]`, WebKit's own entry for a pointer move
/// in a window that is not frontmost: measured 2026-11-06, a `mouseMoved`
/// event sent to the window, to the web view, or to the web view's
/// tracking-area owner reaches no page (the app is never active). **Its
/// button** goes through `NSWindow.sendEvent(_:)` like a key, so WebKit
/// hit-tests the press itself (`TrustedInput+Pointer.swift`).
///
/// **Landing is awaited, not slept on.** WebKit queues input in the UI
/// process and sends the next event only once the page has handled the last,
/// so an evaluate sent right after a burst of keys overtakes the tail of it
/// (measured: three keys sent, one evaluate later the field held two).
/// `-[WKWebView _doAfterProcessingAllPendingKeyEvents:]` and its mouse twin
/// call back once the queue is empty, inside the host's call budget.
///
/// **Private API.** `_simulateMouseMove:` and the two `_doAfterProcessing…`
/// calls are WebKit SPI, joining
/// ``OffscreenWindow``'s occlusion switch and `AccentPin`; each is guarded by `responds(to:)`
/// and a missing one is an ``SleepyError/Kind/environment`` error naming it,
/// never a silent fallback to untrusted events. The names live in
/// `InputSPI`, which `sleepy doctor`'s `input` check reads too.
@MainActor
struct TrustedInput {
    /// The host whose page receives the input.
    let host: PageHost

    /// The window the events are sent through.
    let window: NSWindow

    /// Prepares to send real input to `host`'s page.
    ///
    /// - Parameter action: what is about to be sent, for the refusal.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/usage`` when the
    ///   host is ``PageHost/Hosting/windowless``.
    init(for host: PageHost, action: String) throws {
        guard let window = host.webView.window else {
            throw SleepyError(
                kind: .usage,
                message: "This host is windowless (PageHost.Hosting.windowless), so a real \(action) has no window "
                    + "to arrive through — and dispatching untrusted events in its place would be a pretence.",
                nextMove: "Build the host with the default hosting, .live; every sleepy verb and session already is.",
            )
        }
        self.host = host
        self.window = window
    }

    // MARK: - Keys

    /// Sends `strokes` in order to whatever has focus in the page, making the
    /// web view the window's first responder first.
    func send(_ strokes: [Keystroke]) {
        if window.firstResponder !== host.webView {
            window.makeFirstResponder(host.webView)
        }
        for stroke in strokes {
            send(stroke)
        }
    }

    /// Waits until WebKit has delivered every key event sent so far.
    func keysLanded() async throws {
        try await drain(InputSPI.afterPendingKeyEvents, naming: "the pending key events")
    }

    private func send(_ stroke: Keystroke) {
        var flags: NSEvent.ModifierFlags = []
        for modifier in stroke.modifiers {
            flags.insert(Self.flag(for: modifier))
            post(.flagsChanged, keyCode: Self.keyCode(of: modifier), flags: flags)
        }
        if let alone = stroke.modifierKey {
            flags.insert(Self.flag(for: alone))
            post(.flagsChanged, keyCode: Self.keyCode(of: alone), flags: flags)
            flags.remove(Self.flag(for: alone))
            post(.flagsChanged, keyCode: Self.keyCode(of: alone), flags: flags)
        } else {
            post(.keyDown, keyCode: stroke.keyCode, flags: flags, stroke: stroke)
            post(.keyUp, keyCode: stroke.keyCode, flags: flags, stroke: stroke)
        }
        for modifier in stroke.modifiers.reversed() {
            flags.remove(Self.flag(for: modifier))
            post(.flagsChanged, keyCode: Self.keyCode(of: modifier), flags: flags)
        }
    }

    private func post(
        _ type: NSEvent.EventType,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        stroke: Keystroke? = nil,
    ) {
        guard let event = NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            characters: stroke?.characters ?? "",
            charactersIgnoringModifiers: stroke?.charactersIgnoringModifiers ?? "",
            isARepeat: false,
            keyCode: keyCode,
        ) else { return }
        window.sendEvent(event)
    }

    private static func flag(for modifier: KeyChord.Modifier) -> NSEvent.ModifierFlags {
        switch modifier {
        case .shift: .shift
        case .control: .control
        case .alt: .option
        case .meta: .command
        }
    }

    private static func keyCode(of modifier: KeyChord.Modifier) -> UInt16 {
        Keystroke.modifierKeyCodes[modifier] ?? Keystroke.unidentifiedKeyCode
    }

    // MARK: - Landing

    /// Calls a WebKit "after all pending events" SPI and waits for its
    /// callback, inside the host's call budget.
    func drain(_ name: String, naming call: String) async throws {
        let view: WKWebView = host.webView
        let selector = NSSelectorFromString(name)
        guard view.responds(to: selector) else { throw Self.missing(name, for: call) }
        typealias After = @convention(c) (AnyObject, Selector, @escaping @convention(block) () -> Void) -> Void
        let after = unsafeBitCast(view.method(for: selector), to: After.self)
        let _: Void = try await host.answer(call, within: host.callBudget) { answered in
            after(view, selector) {
                MainActor.assumeIsolated { answered(.success(())) }
            }
        }
    }

    /// The refusal for a WebKit that lacks the SPI `name`, which `call`
    /// needed — an environment fault, never a fallback to untrusted events.
    static func missing(_ name: String, for call: String) -> SleepyError {
        SleepyError(
            kind: .environment,
            message: "This WebKit has no -[WKWebView \(name)], so the host cannot deliver \(call) as real input.",
            nextMove: "Report this macOS version as a seam bug, and run `sleepy doctor` to see which input "
                + "calls it lacks; --fill and --submit still work, as synthesized events.",
        )
    }
}
