import ArgumentParser
import Foundation
import SleepyCLIKit

/// `sleepy recipes` — goal-to-verb routing for an agent that knows what it
/// wants to do but not which verb does it.
///
/// The top-level `--help` lists every verb by name; that answers "what can
/// this tool do", not "which of those does *my* goal need" — the gap the
/// first field agent hit, using three of nineteen verbs for two hours
/// (2026-08-24-first-agent-user-feedback.md). This is the answer, indexed by
/// goal instead of by verb.
///
/// `run()` and `configuration.discussion` share one string so `sleepy
/// recipes` and `sleepy help recipes` show the same text: ArgumentParser's
/// built-in `help` subcommand prints a subcommand's `discussion`, not
/// anything `run()` does, so the text has to live in both places to answer
/// both invocations.
struct RecipesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "recipes",
        abstract: "Goal-to-verb routing: find the right verb for what you're trying to do.",
        discussion: recipesText,
    )

    /// The routing table itself, printed verbatim by both `sleepy recipes`
    /// and `sleepy help recipes`.
    ///
    /// Every `sleepy` invocation here is real and checked against its verb's
    /// own `--help`; `peep compare` is PixelPeeper, a sibling tool that
    /// compares arbitrary PNGs in pixel space (2026-08-28-agent-feedback-
    /// synthesis.md, "Sleepy vs PixelPeeper") — its own flags aren't
    /// Sleepy's to promise, so only the subcommand name is given.
    static let recipesText: String = """
    Prove the page makes no external requests → wire
      sleepy wire http://localhost:3000/app --format text

    Check a semantic or structural fact — roles, names, states; whether an
    element exists or how many match; whether text is on the rendered page →
    ax, query, find
      sleepy ax http://localhost:3000/ | grep 'button "Save"'
      sleepy query http://localhost:3000/ --selector '.error' --exists
      sleepy find http://localhost:3000/ --text 'Welcome back'

    Check that every label is legible against what it sits on → contrast
      sleepy contrast http://localhost:3000/report --min wcag-aa

    Check that nothing spills the viewport sideways, at every breakpoint → overflow
      sleepy overflow http://localhost:3000/report --size 390x800 --size 1280x900

    Drive an interaction and see the result → open, then click/fill/submit,
    then shot --session
      sleepy open http://localhost:3000/login --name login
      sleepy click --session login --selector '#sign-in'
      sleepy shot --session login --out after.png

    Click something a component renders inside an open shadow root, which no
    selector can address → query for the host's box, then click --at
      sleepy query --session app --selector 'my-widget'
      sleepy click --session app --at 620,180

    Click as a user would, so a page that checks isTrusted takes it → click is
    already real input. A click refused as covered names what is on top:
    dismiss it, or click that instead
      sleepy press --session app Escape
      sleepy click --session app --selector '#save'

    Check another breakpoint without reopening → resize
      sleepy resize --session app 390x844
      sleepy shot --session app --out narrow.png

    Make a screenshot Retina-sharp, whole page or one element → shot --scale
    2 (or 3). Layout, breakpoints and --size are unchanged; only the raster is
    denser. A full-page bitmap is width x height x scale squared x 4 bytes
    before PNG encoding, so 1280 x 9,000 points at 2x is about 184 MB
      sleepy shot http://localhost:3000/ --size 1280x800 --scale 2 --out retina.png
      sleepy shot http://localhost:3000/ --selector '.card' --scale 2 --out card.png

    Compare a screenshot against a baseline → peep compare (PixelPeeper, a
    sibling tool: it works on any PNG in pixel space; Sleepy owns the page
    and its CSS-px coordinates)
      sleepy shot http://localhost:3000/ --out after.png
      peep compare before.png after.png

    Wait until the page is actually ready before reading it → --wait-for, on
    any loading verb. The page pushes and the host holds the budget, so no
    verb needs a sleep: 'js:<expr>' is re-evaluated inside the page until it
    is truthy, and 'message:<name>' settles when the page itself posts to
    window.webkit.messageHandlers.<name>
      sleepy shot http://localhost:3000/app --wait-for '#chart' --out chart.png
      sleepy load http://localhost:3000/app --wait-for 'js:window.ready === true'
      sleepy load http://localhost:3000/app --wait-for message:appReady
    Capture something that animates, the same way every run → shot with
    --wait-for on its end state. Pages animate as in a browser
    (requestAnimationFrame, CSS transitions and Web Animations all run), so a
    shot of something still moving can differ from run to run
      sleepy shot http://localhost:3000/ --wait-for '.done' --out done.png
      sleepy shot http://localhost:3000/ --wait-for "js:document.getAnimations().every(a => a.playState !== 'running')" --out settled.png
    Capture a page that uses webfonts, without catching it mid-fallback →
    just shot; the load event already waits for a @font-face the page's own
    stylesheet asks for
      sleepy shot http://localhost:3000/report --out report.png
    Do not add a sleep, and do not reach for --wait-for
    "js:document.fonts.status === 'loaded'": a shot flushes the page's
    rendering before it rasterizes, and both document.fonts.status and
    document.fonts.check() already read ready on a page that has not
    requested the font. Wait for what the page does instead.

    Check the page works with JavaScript off (progressive enhancement) → any
    loading verb with --no-js. <noscript> renders and @media (scripting: none)
    matches; eval needs --world isolated, and console and --wait-for
    js:/message: refuse
      sleepy query http://localhost:3000/signup --selector 'noscript p, form' --no-js --format text
      sleepy shot http://localhost:3000/signup --no-js --out no-js.png
      sleepy load http://localhost:3000/signup --no-js --fill '#email=a@b.c' --submit '#signup'
    Read console errors → load, console
      sleepy load http://localhost:3000/app
      sleepy console http://localhost:3000/app --format text

    Get a value out of the page → eval. The script runs in the page's own
    world by default, so page globals and upgraded custom elements are there;
    --world isolated shares the DOM but none of the page's JavaScript. For a
    check, return a sentence that says what was found rather than a bool: a
    failing run then explains itself
      sleepy eval http://localhost:3000/ --js 'return document.title;'
      sleepy eval http://localhost:3000/ --js "const h = document.querySelector('h1'); return h ? 'h1 reads ' + h.textContent.trim() : 'no h1 on the page';"

    Something failed and you don't know why → doctor
      sleepy doctor

    Sandbox note: WebKit cannot start under a restrictive sandbox — a load
    that "never finishes" and times out is usually this, not a slow page. In
    Claude Code, run the sleepy call with the Bash sandbox disabled.
    """

    @OptionGroup var quiet: QuietOption

    func run() throws {
        print(Self.recipesText)
    }
}
