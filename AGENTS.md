IMPORTANT: As you implement features, keep the DocC comments up to date; update README.md only when a doc file is added or new users must know.

## Overview

SleepyHollow is a headless WebKit browser for agents: it renders real pages with the system's `WebKit.framework` and exposes them — pixels, DOM, computed style, accessibility tree, wire log — through a small CLI (`sleepy`) that takes verbs and emits JSON. One SwiftPM package, two products: the `SleepyHollow` library owns all behaviour; the `sleepy` executable is a thin ArgumentParser consumer (this naming is deliberate and overrides the default `FooBarCore`/`FooBarCommand` convention). **Consciously macOS-only** (12+), against the cross-platform-library default: reaching for Apple frameworks (WebKit, Vision, PDFKit, NSAppearance) is the point.

## Documentation

- [project/](project/) — dated plans, findings and decisions
- [project/2026-08-20-vision.md](project/2026-08-20-vision.md) — the agreed direction: why, philosophy, required verbs, non-goals; read this first
- [project/2026-08-20-implementation-plan.md](project/2026-08-20-implementation-plan.md) — the 1.0 plan: architecture decisions, file ownership, waves, and the imported task tree
- [project/2026-08-20-ax-spike.md](project/2026-08-20-ax-spike.md) — findings: `sleepy ax` reads via injected JS computation; the native AX path is dead for a headless CLI
- [project/2026-08-20-wire-spike.md](project/2026-08-20-wire-spike.md) — findings: inventory-layer field availability, the fetch-recorder shape, and the headless timer-throttling trap (that last claim corrected in place — see the wait-engine note)
- [project/2026-08-20-wait-engine.md](project/2026-08-20-wait-engine.md) — findings: the settle phase, the exact `--wait-for idle` contract, and what a headless page's timers really do
- [project/2026-08-24-first-agent-user-feedback.md](project/2026-08-24-first-agent-user-feedback.md) — field report: the first agent's two hours of production use — what is right, four bugs, paper cuts, and a `job import` block
- [project/2026-08-28-shot-scale-flag.md](project/2026-08-28-shot-scale-flag.md) — recommendation: a `shot --scale` density flag; why the CSS-`zoom` workaround renders the wrong breakpoint, and how the existing snapshot normalization already holds the 2× pixels
- [project/2026-08-28-agent-readout-and-checks.md](project/2026-08-28-agent-readout-and-checks.md) — recommendation: `shot --max-size/--tile/--rect` composed with `--scale`, plus `contrast` and `overflow` assertion verbs and three small fixes, from two agents' field use on 2026-08-28
- [project/2026-08-28-agent-feedback-synthesis.md](project/2026-08-28-agent-feedback-synthesis.md) — agreed direction: the needs beneath the three field reports, rulings (Sleepy vs PixelPeeper, `eval` page-world default, never a plausible wrong answer), settled designs, and the `job import` block
- [project/gotchas.md](project/gotchas.md) — project quirks and rule corrections
- [project/recipes.md](project/recipes.md) — goal-to-verb routing for an agent that knows what it wants but not which verb does it; same content as `sleepy recipes` / `sleepy help recipes`
- [project/backlog.md](project/backlog.md) — work decided against: what it is, why it's parked, what would un-park it
- **API reference is DocC**, from doc comments in `Sources/` — build with `swift package generate-documentation` (archive lands in `.build/plugins/Swift-DocC/outputs/SleepyHollow.doccarchive`), browse with `swift package preview-documentation`
- [README.md](README.md) — the project's front door: what it is, install, quick start

<!-- agents:begin core@3a7a5e -->
## Working rules

**Understand the why.** If the goal behind a request isn't clear, ask before solving — beware the XY problem.

**Diverge, then converge.** First brainstorm options (create choices), weigh them against the user's goals, recommend one (make choices), confirm, then execute.

**Ambiguity.** If the *code* could go several ways, choose the idiomatic one for the language. If the *requirement* is ambiguous or the question is architectural, stop and ask — don't decide.

**Dependencies.** Avoid them unless re-implementing would be unreasonable; ask before adding one; each is security and maintenance surface.

**TDD, strictly red/green.** Write tests for every case and every new method first, watch them *all* fail, then implement. A test that is green during red tests nothing — remove or rewrite it. If an existing test must change to pass because the behavior or expectation has changed, explain why clearly. Every bug fix starts with a regression test.

**Plans and tasks live in `job`.** Open every session with `job orient` (no arguments), then read `project/gotchas.md` — while reading, prune it: delete any entry that's now fixed, obvious, or a general rule, marking it `rule:` first if it's general. Don't use Plan Mode or ad-hoc todo lists.

**Don't tour the codebase.** Start from the README and the docs (an Explore agent is fine); dig only where the task leads — once you have a specific need, read as much as that need requires.

**Scripts.** Analysis tooling goes in `scripts/` so it can be re-run — check there before writing one.

**Critique before declaring done.** Re-read the original request: is the need actually met? Do lint and tests pass? Are docs updated? What would an expert flag? Fix serious flaws before reporting.

**Tidiness.** No stray files in the repo root; delete transients, and file valuable artifacts (reports, scripts) where they belong.

**Documentation.** Keep the project docs current as you build. Touch the README only when a doc file is added or new users must know.

**Gotchas.** When a project quirk costs you time and no rule predicts it, append it to `project/gotchas.md`. If a rule in this file was wrong or misled you, record that there too, prefixed `rule:`.

**Where these rules come from.** The marked regions are generated and shared across repos via a CLI tool named `agents`; don't edit inside them. If a rule here is wrong or cost you time, say so in `project/gotchas.md` prefixed `rule:`; that is how shared rules get reviewed.

**Local rulings.** A repo-local ruling, or an override of a shared rule, lives in the project-owned head of `AGENTS.md`, above the generated regions — say plainly that it overrides, and link a dated project doc for the why.

## Git

- Offer to commit when a unit of work is complete and accepted. Rebase onto upstream; ask on real conflicts, explaining the conflict in plain terms first.
- Commit all uncommitted files together — later changes usually depend on earlier ones, and a half-working state helps nobody. Never amend.
- The subject completes "This commit…": present-tense verb first — "Adds…", "Fixes…", "Retires…". Detail goes in the body.
- Pass the message with `-F <file>`, not inline `-m`; the shell interprets `-m` first. Same for `job`: `note`, `done`, `add` and `edit` all take `-F <file>` (`-F -` reads stdin).
- Pre-commit hooks run the formatter and tests. Run them yourself first (see the stack rules).
- Never pipe a gating command (`git commit … | tail`) — the pipe swallows its exit status, so a following `&&` runs even after a failure.
<!-- agents:end core -->

<!-- agents:begin principles@7a5b19 -->
## Principles

Defaults, not laws. When we break one, we do it consciously and say so in the report and the docs.

- **Pragmatism.** Builders, not purists. Practical choices that serve the near-term goal and protect the long-term one.
- **Eat the frog.** No band-aids. Given an easy-but-compromised path and a correct one, take the correct one; fix problems at the source. Keep YAGNI in mind, but when a need is obvious, don't underdeliver.
- **Composability.** Simple, strong components composed into systems — never a monolith.
- **Library + thin executable.** Core logic in a library; the app or CLI is a light consumer, so the core can be reused elsewhere. An adapter that holds a decision rather than wiring one is a bug.
- **Decoupling.** Tight coupling makes testing, debugging and refactoring hard — separate concerns. Separating a model, its storage and its UI is the everyday case: databases and UI frameworks change; today's web app may grow a CLI or mobile app.
- **Just enough abstraction.** One layer around an LLM provider is prudent; a `TextGenerationProvider` above it is not.
- **Readable file sizes.** Aim for files a reader can hold in their head (a few hundred lines; ~400 is the comfortable ceiling). Past ~2k lines, navigation degrades and errors accumulate; splitting also makes functionality discoverable by filename.
- **Comments say why, not what.** Doc comments state *what* concisely; other comments only explain the non-obvious. No change history in comments. Most code needs none.
- **Strongly typed.** Prefer enums, named constants and config over magic strings and numbers; prefer typed structs over dictionaries, even for wire types. Two packages exchanging data across a serialization seam share **one** struct that both import, never a hand-written twin on each side — the type checker cannot see across encode/decode, and two definitions drift. Given a bool and a typed constant, take the typed constant: a bool named for one consequence gets reused to gate the others until it means several things, so name the underlying *fact* as a type and let the behaviors follow.
- **Previews.** Give each UI component a way to render in its various states — a SwiftUI `#Preview`, a demo page, a story — the foundation for tests and for human review.
- **Async by default.** Keep the app interactive during heavy work; surface loading and error states. On the web, prefer progressive enhancement over full reloads.
- **Event streams where they fit.** Append-only logs are auditable, undoable, and time-travelable.
<!-- agents:end principles -->

<!-- agents:begin stage-build@3d5d83 -->
## Stage: BUILD

Pre-launch, zero users, no existing data. Never spend effort on backward compatibility — assume every use is green-field — but flag breaking changes and update the affected tests. Be ambitious: if a feature is important, build it fully now rather than an MVP; balance that against over-engineering and future-proofing.
<!-- agents:end stage-build -->

<!-- agents:begin swift@8f5faf -->
## Swift

- Keep DocC coverage at 100% for any code you add or change.
- Before committing: `swiftformat . --lint` (then `swiftformat .` if needed) and the full suite (`swift test --quiet`, or the project's `xcodebuild` invocation named in the head). Both should be pre-commit hooks; if the repo has none, run them yourself.
- Swift 6 strict concurrency; resolve warnings as you go. No `nonisolated(unsafe)` without permission. Prefer async/await.
- Prefer `struct` for data; `final class` for durable shared-reference objects; `actor` for shared mutable state or a single access point (DB connection, queue).
- New types conform to `Friendly` (`Codable & Hashable & Equatable & Sendable`) even without current plans to serialize or compare.
- **Library packages are cross-platform by default**: stay in Foundation so they build on Linux; wrap Apple-only APIs in `@available` and cover at least macOS and iOS. App targets state their platforms in the head.
- Modern Swift Regex, not the legacy APIs.
- Help the type checker: annotate the type when an initializer's expression is generic, chained, or overloaded (`let output: String = …`) — but where swiftformat's `redundantType` rule disagrees, the formatter's output is the rule.
- **One type per file.** Nest small enums/structs inside their owner. Extensions go in `BaseType+Purpose.swift` (third-party types too). A file over ~200–300 lines wants splitting (tighter than the general guidance, on purpose).
- Sources and Tests organized in folders, at most one level deep. New test suites (new struct) get their own file.
- **A new combined library + CLI package** `FooBar` = library target `FooBarCore` + CLI target `FooBarCommand`.
<!-- agents:end swift -->

<!-- agents:begin docs@7ba2fd -->
## Documentation practice

- **Plans, findings, designs and decisions go in `project/` as dated documents** (`YYYY-MM-DD-title.md`) — the written history of the project. They are point-in-time records: correct an earlier one *in place*, as a marked block quote, rather than silently editing a number or leaving a stale claim standing.
- **Every figure names the tool and flags that reproduce it.**
- **Work decided against goes in `project/backlog.md`**, not into silence: one dated H2 per item — what it is, why it's parked, and *what would un-park it*. Nothing there is scheduled or blocking; active work lives in `job`. Check it before proposing something that sounds novel.
- **When a finding overturns a premise, edit the premise.** Readers act on the title and opening; a correction appended underneath doesn't reach them.
- **A wrong documented cause is worse than none** — it stops the next reader looking. Correcting one means saying it was wrong, not quietly rewording.
- **Open the note before you cite it**, and check whether a recorded ruling has been superseded before passing it on.
- **Every repo has a README; if none exists, write one (delegate it if you can).** It is tight: the project's name and a one-line description a non-technical reader understands (6th-grade reading level); one short paragraph of what it is; how to install or consume it; a crisp Quick Start with an example or two; links out to the specific docs for anything more; authorship and license at the end.
- **The head of `AGENTS.md` lists where the docs live; keep that list current.**
<!-- agents:end docs -->

<!-- agents:begin delegation-brief@7bb732 -->
## Delegating to subagents

Design on the main thread; dispatch execution to agents for anything larger than a small change. **Read `project/agents/delegation.md` before dispatching** — it carries what to delegate, how to carve the work, the worktree workflow, the traps, and the briefing template.

- Fanning out is a decision, not a default: map each leaf's file surface first, parallelize only the disjoint set, pre-carve or reserve a contended file to one writer, and serialize the rest.
- Commit before dispatching — a worktree branches from local HEAD, so uncommitted work is invisible to the agent; pushing is backup.
- Agents never commit: the integrator wip-commits the agent's branch with hooks off, merges it `--no-ff --no-commit`, reads the diff (that is the code review), runs the full suite once, then commits and closes the leaves.
- Choose the model deliberately, require **deviations from the brief** and **"what in this brief is wrong?"** in every report, and verify what comes back — the pushback, not the typing, is usually the value.
<!-- agents:end delegation-brief -->

<!-- agents:begin jobs-brief@42b137 -->
## Jobs

`job` is the tracker for plans and tasks. **Read `project/agents/jobs.md` before filing or claiming work** — it carries the shape of the tree, criteria and blockers, the identity rules for agents, and how big a leaf should be.

- Subagents pass a unique `--as <name>` and an absolute `--db` on every call; they `claim`, `note` and `release`, never `done`.
<!-- agents:end jobs-brief -->

<!-- agents:begin harness-brief@a03f30 -->
## Harness

The harness an agent runs inside has facts of its own — the Bash sandbox, `$TMPDIR`, no TTY, worktree isolation, background processes. **`project/agents/harness.md` carries them.** Read it the first time a tool call fails with a permission error or a "too complex to verify" refusal, and before writing a brief for a subagent.
<!-- agents:end harness-brief -->

<!-- agents:begin background@882e19 -->
## Background

**Weigh decisions against `project/background.md` where it exists** — who the work is for, the people involved, the constraints that come with them, what they want, and what they call things. It is context for judging a decision rather than for writing code: read it when a choice turns on who is on the other end, and use its vocabulary in what you write.

**It holds *current* state, so it is rewritten, not appended.** Every number, date and name appears there once and links the dated `project/` document it came from; when a fact changes, edit the sentence that holds it and let the dated record keep the history.
<!-- agents:end background -->
