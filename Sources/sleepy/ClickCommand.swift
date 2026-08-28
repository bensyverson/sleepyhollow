import ArgumentParser
import Foundation
import SleepyCLIKit
import SleepyHollow

/// `sleepy click` — press an element, or a point, in a live session.
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
        Synthesized events, not OS-level hit-testing: pointerdown, mousedown, pointerup, mouseup, click.

        --at x,y is in document CSS px: the page's top-left corner is 0,0, unscrolled — the space `shot --rect` crops in, so a rect measured off a full-page capture pastes straight across. (`query` reports geometry relative to the viewport: the same numbers on an unscrolled page, off by the scroll offset otherwise — add window.scrollX/scrollY.) The point is scrolled into view, hit-tested with elementFromPoint, and followed down through every open shadow root, so the button a component renders is what gets clicked.

        A --selector click cannot reach that button: CSS does not cross a shadow boundary, and an event dispatched at the host travels up to the document, never down into what the host renders. A closed shadow root exposes nothing to anyone, this tool included, so a point over one clicks its host.

        Examples:
          sleepy click --session login --selector '#sign-in'
          sleepy click --session app --at 620,180             # pierces shadow roots
          sleepy dom http://localhost:3000/ --click '#go'     # one shot, no session

        Exit codes: 0 clicked, 1 nothing matched, the element is disabled, or nothing but the page background is at the point (the reason is on stderr; nothing on stdout), 2 usage — including a URL instead of --session, or naming both --selector and --at, 5 no such session.
        """,
    )

    /// The one-shot flag that does the same thing, named by every failure.
    static let oneShotExample: String = "--click '#go'"

    @OptionGroup var source: PageSourceOptions

    @Option(name: .long, help: "CSS selector; the first match is clicked.")
    var selector: String?

    @Option(
        name: .long,
        help: "Click x,y in document CSS px with a real hit test, descending through open shadow roots.",
    )
    var at: String?

    @OptionGroup var out: OutOption

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
