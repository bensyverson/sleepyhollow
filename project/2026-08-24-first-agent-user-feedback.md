# First Agent User — Field Report

**Date:** 2026-08-24. Written by Claude (Fable), the first real user, after ~two hours of production use: verifying a WebComponent-heavy proposal page (full-page shots at 1440/390, `ax`, `wire`, `console`, `eval`, a live session with `click`, and `pdf` running in a parallel subagent). Every claim below has a repro from that session. Concrete recommendations are in the `job import` YAML at the end.

## What is exactly right

- **The verb-and-exit-code model is the correct shape for agents.** One call, structured JSON on stdout, exit codes with meaning, no daemon, no protocol, no lifecycle to manage. This matches tool-call ergonomics exactly — each invocation is a complete thought. The stateful alternatives (Playwright-style MCP servers) make an agent manage a browser; sleepy lets it ask a question.
- **It is fast, and sessions are effectively free.** Measured on a real 9,200px-tall page: `load` 0.63s, ephemeral `--full-page` shot 2.3s, a session-scoped element shot **0.055s**. An agent's wall-clock is dominated by its own reasoning, not the tool.
- **`--full-page` + `--size` are the two screenshot features agents actually need.** For contrast: the same afternoon, a subagent using Firefox's `--screenshot` had to invent a negative-margin contortion to photograph a scrolled state with fixed elements, because Firefox captures page coordinates. Sleepy made that whole gotcha obsolete.
- **`ax` as a first-class verb is quietly brilliant.** It's the cheapest semantic verification there is (no pixels to interpret), and it doubles as the accessibility audit. It confirmed a `dl`-based spec-sheet grammar read correctly as term/definition pairs in one call.
- **`wire` earns its keep immediately.** Full fetch exchanges including response bodies proved a page's zero-external-requests claim in one call — evidence, not assertion.
- **Help text is genuinely good** — examples first, exit codes documented per verb, and `open`'s "the only place loading options can be given: a --session invocation later refuses them rather than pretending to apply them" is exactly the right kind of honest.
- **Idle-TTL session reaping** means an agent that crashes mid-task doesn't leave zombie helpers. Agent-safe by default.

## Bugs found (in severity order)

1. **`open` resolves the session-helper binary against the caller's cwd, not the invoked binary.** From `/Users/ben/git/nobedan`, with sleepy on PATH at `~/.swiftpm/bin/sleepy`: `sleepy open URL --name prop` → *"Couldn't start a session helper from '/Users/ben/git/nobedan/sleepy': The file "sleepy" doesn't exist."* Invoking by absolute path works. Agents always invoke via PATH from arbitrary cwds, so as shipped, **sessions don't work for the intended user**. (Likely argv[0] resolution; wants the executable's own resolved path.)
2. **`eval` runs in an isolated content world, silently — and it produces convincing false negatives.** DOM state crosses the boundary (`shadowRoot` presence, attributes); page-world JS does not (an upgraded custom element reads as bare `HTMLElement`: `instanceof` false, prototype methods `undefined`). I burned a full debugging spiral concluding a *working* component had failed its upgrade, complete with control experiments — the control finally showed a visibly-working element "failing" the same probes. Maximally confusing detail: `customElements.get()` **does** return the page's real class across the boundary, so the world-split is invisible until it bites. Wants: the semantics documented in `eval --help` and the README, and ideally `--world page|isolated` (stated default either way).
3. **`pdf` is not paginated and does not apply print media, despite its help text.** *(Found by a second agent using it for a real print pass.)* `PDFOperation.swift` calls `WKWebView.pdf(WKPDFConfiguration())` — a screen-media snapshot on one long page: a 9,200px page came back as a single 1280×8533pt sheet with `.no-print` elements still visible. The doc comment and CLI help both say "paginated"; today that's aspirational. The agent had to build its own `NSPrintOperation` harness, and left two load-bearing notes for the fix: the print operation must be driven with `runModal(for:delegate:didRun:contextInfo:)` — synchronous `.run()` produced infinite *empty* pages (a 666 MB PDF before it was killed) — and the web view must live in a window; park it off-screen at (−20000, −20000) with activation policy `.prohibited` so nothing appears on the user's display. (Which is also praise, recorded here deliberately: sleepy's own windowless rendering is a real virtue — the harness popped visible windows on the user's Mac until it adopted those two settings, and the user noticed immediately.)
4. **The unknown-option suggester proposes flags that don't exist on the verb.** `sleepy shot --full` → *"Did you mean '--fill'?"* — `--fill` is not a `shot` option (fill is a different subcommand); the right suggestion was `--full-page`. An agent will take that suggestion literally and burn a turn.

## Paper cuts and wants

4. **Flag-name consistency:** `shot` addresses elements with `--element`; `click`/`fill` use `--selector` for the same concept. An agent that learned one verb guesses wrong on the next. Pick one; alias the other.
5. **Element shots of zero-area targets emit a blank PNG silently.** I shot a light-DOM container that an upgraded component had hidden and got a valid-but-empty image; a stderr note ("matched element has zero rendered area") would have saved the round trip.
6. **There is no interaction path into shadow DOM.** `--selector` can't address shadow content (correctly, per CSS), and a synthetic click on the host doesn't hit-test through to the shadow-rendered button underneath — my click on a component reported success and changed nothing. With `eval` in the wrong world (bug 2), a progressively-enhanced WebComponent page — the pattern agents will meet constantly — currently has *no* way to be driven. Wants: a coordinate click with a real hit test (`--at x,y`, viewport- or element-relative), and/or explicit piercing syntax.
7. **Captures aren't model-sized.** A 1440×9,208 full-page PNG exceeds what vision models ingest well; I ran `sips` resample/crop after every capture. A `--max-pixels`/`--scale` flag, or `--slices` emitting viewport-sized page PNGs (the `pdf` verb's pagination, but for images), would make output directly consumable by the intended user's eyes.
8. **Discoverability: I used 3 of 19 verbs for the first two hours.** `wire`, `query`, `find`, `console`, and sessions all existed while I was hand-rolling worse versions. The top-level help lists verbs, but an agent mid-task searches by *goal*. A short agent-facing recipes doc (goal → verb: "prove no external requests → wire"; "did the page really render X → find/query"; "drive an interaction → open/click/shot --session") — or a `sleepy help recipes` — would route it. Related: a note that in agent sandboxes, WebKit's XPC and port-binding typically require running unsandboxed.

## The one-sentence verdict

The architecture is already the right one — verbs, JSON, exit codes, cheap sessions — and nothing above touches it; the work is in trueing the edges so an agent's *first guess* works, because agents don't build mental models between sessions the way returning humans do: they re-guess every time.

---

```yaml
tasks:
  - title: Session helper resolves the sleepy binary against cwd
    desc: >
      `sleepy open` invoked via PATH from another directory fails: "Couldn't start a session
      helper from '<cwd>/sleepy'". Resolve the helper from the invoked executable's own path
      (not argv[0] as given). Repro: install to ~/.swiftpm/bin, cd anywhere else, sleepy open.
      This blocks sessions entirely for agents, who always invoke via PATH.
    labels: [bug, sessions]
    criteria:
      - sleepy open works when invoked as a bare PATH command from an unrelated cwd
      - a regression test covers PATH invocation from a foreign cwd
  - title: Document and control eval's content world
    desc: >
      eval runs in an isolated world: DOM state crosses (shadowRoot, attributes), page JS does
      not (upgraded custom elements read as bare HTMLElement; prototype methods undefined) —
      while customElements.get() DOES return the page's class, hiding the split. Produces
      convincing false negatives about component state. Document the semantics in eval --help
      and the README; add --world page|isolated with a stated default.
    labels: [bug, eval, docs]
    criteria:
      - eval --help states which world scripts run in and what does not cross the boundary
      - "--world page makes `typeof el.someUpgradedMethod` return function for an upgraded custom element"
  - title: Make pdf actually paginate with print media
    desc: >
      WKWebView.pdf(WKPDFConfiguration()) renders a screen-media snapshot on one long page;
      no-print elements stay visible and nothing paginates, contradicting the verb's help text.
      Use the NSPrintOperation path (Safari's Save as PDF). Two hard-won details from the field
      harness: drive it with runModal(for:delegate:didRun:contextInfo:) - synchronous .run()
      yields infinite empty pages - and host the web view in a real NSWindow parked off-screen
      at (-20000,-20000) with NSApplication activation policy .prohibited, or windows appear on
      the user's display. Margins come from NSPrintInfo, not @page - decide and document which wins.
    labels: [bug, pdf]
    criteria:
      - pdf of a page with @media print rules emits multiple Letter/A4 pages with no-print elements absent
      - rendering opens no visible window and never activates the app
  - title: Suggester proposes flags the verb does not have
    desc: >
      `sleepy shot --full` suggests '--fill', which is not a shot option (fill is a different
      subcommand); the right answer was '--full-page'. Constrain did-you-mean candidates to the
      current verb's flags. Consider aliasing common guesses: -o for --out; --full for --full-page.
    labels: [bug, cli]
    criteria:
      - unknown-option suggestions only ever name flags valid on the invoked verb
  - title: Unify element addressing across verbs
    desc: shot uses --element; click/fill use --selector for the same concept. Pick one name and accept the other as an alias everywhere.
    labels: [cli, consistency]
  - title: Warn on zero-area element shots
    desc: An --element shot whose match has zero rendered area currently writes a blank PNG with exit 0. Emit a stderr note naming the condition (and consider a distinct exit code) so an agent doesn't reason from an empty image.
    labels: [cli, shot]
  - title: An interaction path into shadow DOM
    desc: >
      Synthetic clicks on a host element do not reach shadow-rendered controls, --selector cannot
      address them, and eval is in the wrong world - so progressively-enhanced WebComponent pages
      cannot be driven at all. Add a hit-tested coordinate click (--at x,y, viewport- or
      element-relative) and/or explicit shadow-piercing selector syntax.
    labels: [feature, interaction]
    criteria:
      - a click can activate a button rendered inside an open shadow root, verified by observable page state
  - title: Model-sized capture output
    desc: >
      Full-page PNGs of tall pages (1440x9208 measured) exceed what vision models ingest; the
      first user ran sips after every capture. Add --max-pixels or --scale, and/or --slices N
      emitting viewport-sized page images (pdf's pagination, for PNGs).
    labels: [feature, shot]
  - title: Agent-facing recipes doc
    desc: >
      Goal-to-verb routing for the intended user: prove no external requests -> wire; semantic
      check -> ax/query/find; console truth -> console; drive an interaction -> open/click/
      shot --session; plus the sandbox note (WebKit XPC and port binding need to run
      unsandboxed in agent harnesses). The first user hand-rolled worse versions of five verbs
      he had not discovered. Ship as AGENTS-facing doc or `sleepy help recipes`.
    labels: [docs]
```
