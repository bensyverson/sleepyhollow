# SleepyHollow 1.0 — implementation plan

*2026-08-20 · Ben Syverson & Claude · status: draft for review*

Companion to [2026-08-20-vision.md](2026-08-20-vision.md); covers everything
in "What — required for 1.0". The YAML block at the end is the `job import`
source of truth for tasks and blocking; the prose here is the why, the file
ownership map, and the guidance for executing it in parallel.

## Architecture decisions the plan builds on

These are settled here so no leaf has to make them.

- **Every verb is a `PageOperation`.** A `Friendly` struct describing one
  read or act (shoot this rect, query this selector, evaluate this JS),
  executed against a `PageHost`. One-shot invocations execute the operation
  locally; sessions ship the *same struct* over the Unix socket to a helper
  that executes it identically. This is the seam that makes the verb
  families and the session layer independent workstreams — the session
  layer never needs to know what operations exist, only how to decode and
  run one.
- **One binary, including the helper.** The session helper is the `sleepy`
  binary itself, launched with a hidden `_host` subcommand — preserving the
  vision's one-binary claim, and sparing us a third product.
- **`PageHost` owns everything per-page**: the headless `WKWebView`, the
  load pipeline, the default timeout, dialog policy (decline-and-record),
  theme, size, the wait engine, and baseline console capture (the
  console-error count in `load`'s facts). Verb families consume it; only
  the foundation leaves modify it.
- **Waiting lives in the load pipeline, not in verbs.** `--wait-for` /
  `--budget` are `LoadOptions`; loading verbs pass them through and never
  implement waiting. Consequence: verb families do **not** block on the
  wait engine — they compile against `LoadOptions` from day one and gain
  waiting for free when the engine lands.
- **Exit codes, one scheme for every verb**: 0 success / assertion true;
  1 clean negative (`--exists` absent, `find` no match); 2 usage error;
  3 timeout, with the page's last state attached; 4 load/navigation
  failure; 5 environment error (no such session, dead helper, bad jar).
  Defined once in `Core/`, documented in DocC, mapped centrally by the CLI.
- **Fixtures are an in-process HTTP server**, built on Network.framework's
  `NWListener` in a `TestSupport` target — no dependency, real `http://`
  URLs so cookies, wire observation and navigation behave honestly.
  (Custom-scheme handlers stay post-1.0; this is test apparatus, not a
  feature.)
- **Only external runtime dependency: `swift-argument-parser`.** The
  `swift-docc-plugin` already in the initial scaffold stays — it is docs
  tooling, not linked code.

### Source layout (file ownership follows this)

```text
Sources/
  SleepyHollow/            # the library — all behaviour
    Core/                  # PageSource, LoadOptions, PageOperation, errors, exit codes
    Host/                  # PageHost, dialog policy, wait engine, console capture
    Operations/            # one file per operation: Shot, PDF, Archive, DOM, Query,
                           #   Style, AX, Find, Eval, Actions, Wire, Console, Cookies
    Output/                # OutputFormat, JSON encoding, the AX outline renderer
    State/                 # jars: store, persistence, pruning
    Session/               # socket protocol, helper host loop, client, registry
  sleepy/                  # the CLI — thin ArgumentParser consumer
    Options/               # shared option groups: page source, load, --format, --out
    Commands/              # one file per verb
Tests/
  SleepyHollowTests/       # library tests, folders mirroring Sources
  SleepyGoldenTests/       # CLI golden-output tests
  TestSupport/             # fixture server + fixture pages
```

## Execution guidance

Four waves. Within a wave, every leaf is independent — disjoint files, no
mutual blocking — and can go to a parallel agent in its own worktree.
Between waves, the main thread integrates, runs the full suite once,
commits, pushes, and closes leaves (per `project/agents/delegation.md`;
push *before* dispatching the next wave, since worktrees branch from
`origin/main`).

- **Wave 0 — foundation.** `scaffold` first (everything needs a package to
  build in), then `core-types`, then `pagehost` — this chain is the one
  genuinely serial spine, so it stays on the main thread or with a single
  strong agent. `fixtures` and `cli-scaffold` fork off it as soon as their
  blockers land, and both **spikes are unblocked from minute zero** — run
  them alongside wave 0 so their findings are waiting when wave 1 starts.
- **Wave 1 — verb families, wide open.** Six leaves, one agent each, all
  blocked only on the foundation (plus one spike each for `ax` and
  `observe`, and the wait engine for `act-eval`). Each family owns its
  operation files in `Operations/`, its command files in `Commands/`, its
  test folder, and its fixture pages — named per-leaf below so no two
  agents touch one file. The session protocol (`sess-protocol`) also
  belongs to this wave: it needs only `pagehost` and the `PageOperation`
  seam, not any particular verb.
- **Wave 2 — sessions meet verbs.** `sess-verbs` (open/close/list/prune,
  `--session` routing, fail-loud `open`) once the protocol stands;
  `sess-integration` proves every verb against `--session` once the
  families land. This is the convergence point — expect it to surface seam
  bugs; budget main-thread attention here rather than delegating it all.
- **Wave 3 — polish.** Help/primer audit, the golden e2e suite, README +
  DocC pass. Parallel again; low risk.

Blocking is deliberately minimal — the listed `blockedBy` edges are the
real ones. In particular: loading-verb families do **not** wait for the
wait engine; nothing waits for `jars` except final integration; the spikes
block only their own family. If an agent finds an undeclared dependency,
that's a finding for the seam (usually `Core/`), not a reason to serialize
two families.

Delegation mechanics (summarized from the guide, which governs): settle
ambiguity before dispatch and record decisions as `job note`s on the leaf;
unique `--as` per agent with an absolute `--db`; agents claim, note and
release — never `done`, never commit; every brief names the files the
agent owns, the files it must not touch, and ends with "what in this brief
is wrong?"; TDD red-first in every brief.

## Tasks

```yaml
tasks:
  - title: Foundation
    children:
      - title: Package scaffold
        ref: scaffold
        labels: [wave-0]
        desc: >
          Create the SwiftPM package: library product SleepyHollow and
          executable product sleepy (thin ArgumentParser consumer) — this
          naming is deliberate and overrides the FooBarCore/FooBarCommand
          convention. Sole external runtime dependency:
          swift-argument-parser; the swift-docc-plugin build-tool
          dependency already present stays. A `swift package init`
          template (empty library target, placeholder test) already
          exists in the repo — replace it, don't assume a bare tree.
          Add the swiftformat configuration, a pre-commit hook running
          `swiftformat . --lint` and `swift test --quiet` (the hook must
          not recurse into .claude/worktrees/), the test targets from the
          source layout in the implementation plan, and an MIT LICENSE
          placeholder pending Ben's confirmation. macOS platform 12+,
          Swift 6 strict concurrency.
        criteria:
          - swift build and swift test succeed from a clean checkout
          - pre-commit hook runs lint and tests and skips .claude/worktrees
          - the only external runtime dependency is swift-argument-parser
      - title: Fixture kit
        ref: fixtures
        blockedBy: [scaffold]
        labels: [wave-0]
        desc: >
          TestSupport target: an in-process HTTP fixture server on
          Network.framework's NWListener (no dependency) serving pages
          from a fixtures directory over real localhost URLs, plus the
          initial fixture pages every family's TDD needs: static text,
          a form, dialog-raising, theme-aware CSS, a slow resource, a
          fetch-making page, and a cookie-setting page. Families add
          their own fixtures later in their own files; this leaf owns the
          server and the shared pages.
        criteria:
          - server serves fixture pages over localhost HTTP in-process
          - start/stop is async-safe and leaks no ports across test runs
          - shared fixture pages listed in the desc all exist and load
      - title: Core types
        ref: core-types
        blockedBy: [scaffold]
        labels: [wave-0]
        desc: >
          Sources/SleepyHollow/Core and Output: PageSource (url vs
          session), LoadOptions (size, theme, jar, inject, dialog policy,
          wait condition, budget, ordered action steps), the PageOperation
          protocol with a Friendly envelope for socket transport, the
          SleepyError taxonomy, the exit-code scheme from the plan (0
          success / 1 clean negative / 2 usage / 3 timeout / 4 load
          failure / 5 environment), and OutputFormat with the
          tersest-faithful-default rule. Everything conforms to Friendly.
          This leaf is the seam the whole plan leans on — precision here
          buys wave-1 its independence.
        criteria:
          - PageOperation envelope round-trips arbitrary operations through JSON
          - exit-code scheme has DocC and tests
          - all new types conform to Friendly
      - title: PageHost
        ref: pagehost
        blockedBy: [core-types]
        labels: [wave-0]
        desc: >
          Sources/SleepyHollow/Host: the headless WKWebView owner. Load
          pipeline with default timeout (every operation terminates),
          explicit frame/size, NSAppearance theme, non-persistent data
          store by default, WKUIDelegate dialog policy defaulting to
          decline-and-record (alert acknowledged, confirm/prompt
          cancelled, beforeunload leaves; every dialog recorded in
          output; flags override), baseline console capture for the
          console-error count in load facts, and generic user-script /
          script-message-handler plumbing for families to register
          instrumentation. Executes any PageOperation. Does not include
          the wait engine (separate leaf, same folder — coordinate if
          run concurrently; by default run wait after this lands).
        criteria:
          - loads a fixture headless and reports final URL, status, console-error count
          - a hanging load becomes a structured timeout error, never a hang
          - dialog fixture shows decline-and-record defaults and flag overrides
          - theme fixture renders differently under light and dark
      - title: Wait engine
        ref: wait
        blockedBy: [pagehost]
        labels: [wave-0]
        desc: >
          The --wait-for conditions (selector, js-predicate, idle, load)
          and --budget ceiling, implemented inside the Host load pipeline
          so every loading verb inherits them by passing LoadOptions
          through. Push-driven where WebKit allows (mutation observers,
          navigation callbacks) rather than polling. On budget
          exhaustion: exit-code 3 with the page's last state attached.
        criteria:
          - all four condition kinds verified against fixtures
          - budget exhaustion exits 3 with last state attached
          - loading verbs gain waiting without code changes of their own
      - title: CLI scaffold
        ref: cli-scaffold
        blockedBy: [core-types]
        labels: [wave-0]
        desc: >
          Sources/sleepy: the root command whose bare invocation is the
          primer (what the tool is, three most common invocations, where
          help lives), the shared option groups families consume (page
          source url-or-session, load options, --format, --out), central
          error rendering that states the next move, exit-code mapping,
          and the exemplar verb: sleepy load, the base loading verb
          (one-shot smoke test emitting final URL, status, console-error
          count). Owns Options/ and the root + LoadCommand files only;
          families own their own Commands/ files.
        criteria:
          - bare sleepy prints the primer
          - sleepy load works end-to-end against a fixture with meaningful exit codes
          - shared option groups are consumable by a subcommand without modification
          - errors render as next-move guidance, not stack traces
  - title: Spikes
    desc: >
      Findings land as dated docs in project/ (YYYY-MM-DD-title.md), each
      figure naming the tool and flags that reproduce it. Unblocked from
      the start; run alongside wave 0 so wave 1 never waits on them.
    children:
      - title: 'Spike: ax mechanism'
        ref: spike-ax
        labels: [wave-0, spike]
        desc: >
          Decide how sleepy ax reads the accessibility tree: the JS
          accessibility computation, the macOS AX API against the
          headless web view, or both. The verb's contract (outline
          default, --format json full tree) is fixed either way; this
          settles mechanism, fidelity (roles, names, states on real
          pages), and whether a windowless WKWebView exposes an AX tree
          at all. Prototype throwaway code; deliverable is the findings
          doc and a recommendation.
        criteria:
          - findings doc in project/ recommends a mechanism with evidence from a real page
          - names/roles/states fidelity assessed on at least one nontrivial fixture
      - title: 'Spike: wire feasibility details'
        ref: spike-wire
        labels: [wave-0, spike]
        desc: >
          The two open wire questions from the vision doc: which
          PerformanceResourceTiming fields (notably responseStatus)
          exist on the oldest WebKit we support, and the fetch
          recorder's response-body limits (opaque responses, streaming
          bodies, body-size guards). Deliverable: findings doc with a
          field-by-field availability table and a recommended recorder
          shape.
        criteria:
          - findings doc tabulates inventory-layer field availability on the minimum OS
          - response-body capture limits are demonstrated, not assumed
  - title: Verb families
    desc: >
      One agent per leaf, one worktree each; all independent. Each family
      owns its Operations/ files, its Commands/ files, its test folder,
      and its own fixture pages, and includes DocC for everything public
      plus golden-output tests for its verbs' default and json formats.
    children:
      - title: 'Family: capture'
        ref: fam-capture
        blockedBy: [pagehost, cli-scaffold, fixtures]
        labels: [wave-1]
        desc: >
          sleepy shot (--element via WKSnapshotConfiguration rect,
          --full-page, --size, --theme), sleepy pdf (createPDF), sleepy
          archive (createWebArchive). Owns Operations/Shot|PDF|Archive,
          Commands/Shot|PDF|ArchiveCommand, capture fixtures.
        criteria:
          - element capture crops to the element rect on a fixture placed below the fold
          - full-page capture exceeds viewport height on a long fixture
          - pdf and archive emit valid artifacts via --out
      - title: 'Family: dom reads'
        ref: fam-dom
        blockedBy: [pagehost, cli-scaffold, fixtures]
        labels: [wave-1]
        desc: >
          sleepy dom (HTML default, --format json tree), sleepy query
          (JSON facts: text, attributes, geometry, visibility; --count
          and --exists carrying the assertion in the exit code), sleepy
          style (computed styles), sleepy find (WKWebView.find). Owns
          Operations/DOM|Query|Style|Find, their Commands, their
          fixtures.
        criteria:
          - dom defaults to HTML and offers a JSON tree
          - query --exists and --count answer in the exit code (0 true, 1 clean negative)
          - style returns computed values for requested properties
          - find matches rendered text the way ⌘F would
      - title: 'Family: ax'
        ref: fam-ax
        blockedBy: [pagehost, cli-scaffold, fixtures, spike-ax]
        labels: [wave-1]
        desc: >
          The flagship read: sleepy ax with the indented outline default
          (button "Publish" (disabled)) and --format json full tree,
          built on the mechanism the spike recommends. Owns
          Operations/AX, Output's outline renderer file, AXCommand, ax
          fixtures.
        criteria:
          - outline is the default and is materially terser than the JSON tree
          - the flagship query (a named, disabled button) is answerable from output alone
          - roles, names and states verified against a form fixture
      - title: 'Family: act & eval'
        ref: fam-act
        blockedBy: [pagehost, cli-scaffold, fixtures, wait]
        labels: [wave-1]
        desc: >
          sleepy eval via callAsyncJavaScript — await, JSON args, JSON
          result, page errors as structured failures; isolated
          WKContentWorld by default with --page-world opt-in. The act
          primitives click/fill/submit as synthesized-event operations
          (session verbs), and the ordered one-shot action flags
          (--click/--fill/--submit executed in flag order after settle,
          before the read) wired into the load pipeline's LoadOptions
          steps. Owns Operations/Eval|Actions, Eval/Click/Fill/Submit
          Commands, act fixtures. Blocked on wait because step
          execution interleaves with settle semantics.
        criteria:
          - eval returns JSON, supports await, and surfaces page errors structurally
          - isolated world is default and --page-world reaches page state
          - a one-shot fill-click-wait-read flow passes against the form fixture
          - act verbs without --session fail with a teaching usage error
      - title: 'Family: observe'
        ref: fam-observe
        blockedBy: [pagehost, cli-scaffold, fixtures, spike-wire]
        labels: [wave-1]
        desc: >
          sleepy console (page console and errors; stderr on one-shot
          loads), and sleepy wire's two layers: the inventory
          (WKNavigationDelegate + PerformanceResourceTiming — URL,
          type, timing, sizes, status where the platform provides it)
          and the fetch log (document-start page-world recorder
          normalizing through new Request(input, init), reporting
          method, headers, request and response bodies, status via
          script message handler). Also the --inject <file> flag on
          loading verbs. Owns Operations/Wire|Console, the recorder JS
          resource, Wire/Console Commands, wire fixtures. The Starlight
          acceptance shape governs: one edit ⇒ exactly one POST,
          urlencoded, status 200, body contains the value.
        criteria:
          - inventory lists subresources with the fields the spike found available
          - fetch log survives Headers-instance and Request-object call styles
          - the one-edit-one-POST assertion passes against the form-fetch fixture
          - --inject installs a user script before document start
      - title: 'Family: jars & cookies'
        ref: fam-jars
        blockedBy: [pagehost, cli-scaffold, fixtures]
        labels: [wave-1]
        desc: >
          Named cookie jars under ~/.sleepyhollow/jars/: naming creates,
          --jar on loading verbs attaches, sessions without --jar stay
          in-memory. sleepy jars list|clear|rm and sleepy cookies
          get|set against a live store or a named jar
          (WKHTTPCookieStore). Owns State/, Operations/Cookies,
          Jars/Cookies Commands, cookie fixtures.
        criteria:
          - a jar minted by one invocation authenticates a later unrelated invocation
          - a bare invocation writes nothing under ~/.sleepyhollow
          - jars list/clear/rm behave and are golden-tested
  - title: Sessions
    children:
      - title: Session protocol & helper
        ref: sess-protocol
        blockedBy: [pagehost, cli-scaffold]
        labels: [wave-1]
        desc: >
          Sources/SleepyHollow/Session: the Unix-socket protocol under
          ~/.sleepyhollow/sessions/<name>/ shipping Friendly
          PageOperation envelopes, the helper host loop (the sleepy
          binary's hidden _host subcommand owning one web view), the
          thin client, idle-TTL self-termination, and the registry that
          detects dead helpers (stale socket + dead pid). No supervising
          daemon — each helper supervises itself. Independent of every
          verb family by construction of the PageOperation seam; needs
          no verb but load to prove itself.
        criteria:
          - a helper executes an arbitrary PageOperation shipped over the socket
          - a short-TTL helper self-terminates after idling
          - a kill -9'd helper is detected as dead by the registry
      - title: Session verbs & routing
        ref: sess-verbs
        blockedBy: [sess-protocol]
        labels: [wave-2]
        desc: >
          sleepy open <url> --name (fails loudly on an existing name
          with the teaching error from the vision doc), close, sessions
          list|prune, generic --session routing in the shared page-source
          option group so every verb transparently executes remotely,
          and load --session navigation. Owns Session verb Commands and
          the routing glue in Options/ (coordinate: Options/ was created
          by cli-scaffold, which is closed by now).
        criteria:
          - open on an existing name exits 5 with the teaching error
          - load --session navigates an open session
          - sessions list/prune reap orphans lazily and are golden-tested
      - title: Session integration proof
        ref: sess-integration
        blockedBy: [sess-verbs, fam-capture, fam-dom, fam-ax, fam-act, fam-observe, fam-jars]
        labels: [wave-2]
        desc: >
          The convergence leaf, main-thread heavy: an e2e suite proving
          every 1.0 verb behaves identically against a URL and against
          --session, plus the canonical multi-step flow (open, log in
          via jar, navigate, assert via ax, shot) as a test. Seam bugs
          between families and the session layer surface here; fixing
          them may touch shared files, which is why this leaf runs alone
          after the waves merge.
        criteria:
          - every 1.0 verb's core test passes against --session
          - the canonical open/login/navigate/assert/shot flow passes end-to-end
  - title: Polish
    children:
      - title: Primer, help & error audit
        ref: polish-help
        blockedBy: [sess-verbs, fam-capture, fam-dom, fam-ax, fam-act, fam-observe, fam-jars]
        labels: [wave-3]
        desc: >
          The CLI-as-feature pass: every subcommand's --help carries
          examples, not just flags; the primer reflects the real verb
          set; every failure path is audited to state the next move
          (the job doctrine); exit codes documented per verb in help
          and DocC.
        criteria:
          - every subcommand --help contains at least one example
          - error audit finds no failure without a stated next move
      - title: Golden e2e suite
        ref: polish-golden
        blockedBy: [sess-integration]
        labels: [wave-3]
        desc: >
          The full golden-output suite across every verb's default and
          json formats, byte-stable (the same invocation emits the same
          bytes), plus determinism checks: fixed size, named theme,
          repeated invocations identical.
        criteria:
          - golden coverage for every verb's default and json formats
          - repeated identical invocations produce identical bytes
      - title: README, DocC & license
        ref: polish-docs
        blockedBy: [sess-verbs, fam-capture, fam-dom, fam-ax, fam-act, fam-observe, fam-jars]
        labels: [wave-3]
        desc: >
          The README per the documentation practice (name, one-line
          6th-grade description, what it is, install, quick start with
          examples, links to docs, authorship and license); a DocC
          coverage pass to 100% on public API with the archive
          building cleanly; the AGENTS.md head's docs list updated;
          license confirmed with Ben (MIT assumed) and LICENSE
          finalized.
        criteria:
          - README exists and follows the documentation practice
          - DocC builds clean at 100% public-API coverage
          - license confirmed and LICENSE file final
```
