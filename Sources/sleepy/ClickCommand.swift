import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy click` — click an element, or a point, in a live session, with a
/// real click (``ClickOperation``).
///
/// An act verb: it requires `--session`, because acting on a page that
/// vanishes at exit is write-only. For a one-shot flow, ride a loading verb
/// instead: `sleepy dom <url> --click '#go'`.
///
/// `--selector` and `--at` are the two ways to say what to press, and they
/// are exclusive: the pair resolves through ``ActionTarget/clicking(selector:at:)``,
/// so the CLI carries no part of that decision.
struct ClickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click an element by selector, or whatever renders at a point, in a live session.",
        discussion: """
        A real click (isTrusted true): the pointer moves to the target and the button goes down and up through the page's window, so the page sees pointermove, pointerdown, mousedown, pointerup, mouseup, click, and the browser runs the default action — a link is followed, a form submitted, a checkbox toggled — even with --no-js. Focus moves as in Safari (a field or link takes it, a button does not), and the pointer stays where it clicked, so :hover matches there afterwards. To capture the clicked state without the hover one, follow a one-shot --click with --leave, which moves the pointer off the page; the element then gets mouseleave/pointerleave, so a menu that opens on hover closes.

        WebKit hit-tests the click, as it does a user's: it lands on whatever is on top at the point. --selector clicks the element's center, and refuses (exit 1) when something else covers that point, when the element is disabled, or when it has no box; as a one-shot --click step it waits for that to clear instead.

        --at x,y is in document CSS px: the page's top-left corner is 0,0, unscrolled — the same space `query` reports geometry in and `shot --rect` crops in, so a rect measured off a full-page capture, a tile index, or a query pastes straight across, at any scroll position. The point is scrolled into view and clicked; the output's hit names what is there, found with elementFromPoint and followed down through every open shadow root, so the button a component renders is what gets clicked and named.

        --at takes fractions (--at 100.75,300.25) and the click carries them, but WebKit gives a mouse event whole-px clientX/clientY: a page's mousedown, mouseup and click handlers see 100,300, and pointerdown and pointerup see 100.75,300.25. A handler that rescales clientX on a canvas drawn below 1x can land one box off; read the position from pointerdown/pointerup, or click the element's center with --selector.

        A --selector click cannot reach a button inside a shadow root, because CSS does not cross a shadow boundary; click its coordinates instead. A closed shadow root exposes nothing to anyone, this tool included, so the hit names its host.

        Examples:
          sleepy click --session login --selector '#sign-in'
          sleepy click --session app --at 620,180             # pierces shadow roots
          sleepy dom http://localhost:3000/ --click '#go'     # one shot, no session

        Exit codes: 0 clicked, 1 nothing matched, the element is disabled, covered or has no box, or nothing but the page background is at the point (the reason is on stderr; nothing on stdout), 2 usage — including a URL instead of --session, or naming both --selector and --at, 5 no such session.
        """,
    )

    /// The one-shot flag that does the same thing, named by every failure.
    static let oneShotExample: String = "--click '#go'"

    @OptionGroup var source: PageSourceOptions

    /// `--element` is the same flag: `shot` shipped with that spelling, so
    /// both names reach the one concept from either verb.
    @Option(
        name: [.long, .customLong("element")],
        help: "CSS selector; the first match is clicked (--element is the same flag).",
    )
    var selector: String?

    @Option(
        name: .long,
        help: "Click x,y in document CSS px: a real click, on whatever is on top there, shadow roots included.",
    )
    var at: String?

    @OptionGroup var out: OutOption

    @OptionGroup var quiet: QuietOption

    @MainActor
    mutating func run() async throws {
        let target: ActionTarget = try ActionTarget.clicking(selector: selector, at: at)
        let session: SessionName = try ActTarget.session(
            from: source,
            verb: ClickOperation.kind,
            example: Self.oneShotExample,
        )
        try await ActTarget.act(ClickOperation(target: target), in: session, to: out.sink)
    }
}
