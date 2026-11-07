import CoreGraphics

/// `sleepy click`: press what a selector matches, or what renders at a
/// point, with a real click from the host's window.
///
/// **Trusted.** The pointer moves to the target and the primary button goes
/// down and up through the host's window (``TrustedInput``), so the page
/// sees `pointermove`, `pointerdown`, `mousedown`, `pointerup`, `mouseup` and
/// `click` with `isTrusted` true, and WebKit runs the click's default action
/// — a link followed, a form submitted, a checkbox toggled — whether or not
/// the page's scripts run. A ``PageHost/Hosting/windowless`` host has no
/// window to click through and is refused, never answered with a script
/// click in its place.
///
/// **WebKit hit-tests the click, as it does a user's.** It lands on whatever
/// is on top at the point: into shadow roots, through transformed ancestors
/// and past `pointer-events: none`. So a selector click goes to the
/// element's center and is refused when something else covers that point —
/// the click would reach the cover, not the element — and a disabled control
/// is refused rather than pretended at. The step runner retries both, so a
/// toast that fades or a control that enables is waited for.
///
/// **A point is named before it is clicked.** ``ActionTarget/point(_:)``
/// resolves through `document.elementFromPoint` and then descends every open
/// `shadowRoot` at the same coordinates, so ``ActionOutcome/hit`` names the
/// button a component renders — the one thing a selector cannot reach,
/// because CSS does not cross a shadow boundary.
///
/// **What a user's click does that a script's did not:** focus moves the way
/// Safari moves it — a text field or link takes focus, a button does not —
/// and the pointer stays where it clicked, so `:hover` matches there
/// afterwards — for a caller driving the page, a hover-opened menu stays open
/// for the next click. To capture the clicked state without the hover one,
/// follow the click with ``LeaveOperation`` (the `--leave` step), which takes
/// the pointer off the page and fires `mouseleave`/`pointerleave` on what it
/// was over (Ben's ruling, 2026-11-06). **Whether the page navigated** is judged by the host
/// (``PageHost/navigationStarted(sinceRequests:)``), after the click has
/// landed.
///
/// **A fractional point reaches the pointer events, not the mouse events**:
/// `pointerdown` and `pointerup` keep the fraction, while WebKit gives
/// `mousedown`, `mouseup` and `click` whole-pixel `clientX`/`clientY`. See
/// ``ActionScript``'s coordinate click for the detail.
public struct ClickOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = ActionOutcome

    /// The wire identifier.
    public static let kind: String = "click"

    /// What gets clicked: a selector's first match, or whatever renders at a
    /// point in document CSS px.
    public var target: ActionTarget

    /// Creates the operation.
    public init(target: ActionTarget) {
        self.target = target
    }

    /// Creates a click on the first element a CSS selector matches.
    public init(selector: String) {
        self.init(target: .selector(selector))
    }

    /// Creates a click on whatever renders at a point in document CSS px.
    ///
    /// The point is scrolled into view before the hit test, so a coordinate
    /// read off a full-page capture works without the caller scrolling first.
    public init(point: DocumentPoint) {
        self.init(target: .point(point))
    }

    /// Clicks the target.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/negative`` when
    ///   nothing matches, the control is disabled, has no box or is covered,
    ///   or nothing but the page background is at the point;
    ///   ``SleepyError/Kind/usage`` when the selector cannot be parsed or the
    ///   host is windowless; ``SleepyError/Kind/timeout`` when the page does
    ///   not handle the click within the host's call budget.
    @MainActor
    public func execute(on host: PageHost) async throws -> ActionOutcome {
        let input = try TrustedInput(for: host, action: "click")
        var arguments: [String: Any] = [:]
        switch target {
        case let .selector(selector):
            arguments["selector"] = selector
        case let .point(point):
            arguments["point"] = ["x": point.x, "y": point.y]
        }
        let located: ActionScript.Report = try await ActionScript.report(
            for: .click,
            target: target,
            body: Self.body(for: target),
            arguments: arguments,
            on: host,
        )
        // A point the page did not name is never guessed: a click at the
        // origin would land on something and report a plausible success.
        guard let x = located.x, let y = located.y else {
            throw SleepyError(
                kind: .environment,
                message: "The page found the click's target but named no point to click it at.",
                nextMove: "Retry; this indicates a transport fault, not a page fault.",
            )
        }
        let requests: Int = host.navigationRequestCount
        try await input.click(atViewport: CGPoint(x: x, y: y))
        let navigating: Bool = await host.navigationStarted(sinceRequests: requests)
        return ActionOutcome(
            action: .click,
            selector: target.selector,
            tagName: located.tagName ?? "",
            startedNavigation: navigating,
            hit: located.hit,
        )
    }

    private static func body(for target: ActionTarget) -> String {
        switch target {
        case .selector: ActionScript.clickLocateBody
        case .point: ActionScript.pointClickBody
        }
    }
}
