# Recipes

Goal-to-verb routing for an agent that knows what it wants to do but not
which verb does it. `sleepy --help` lists every verb by name; this indexes
them by goal instead. Same text as `sleepy recipes` / `sleepy help recipes`
— a living reference, like `gotchas.md`: update it in place as verbs change,
no dates on entries.

Prove the page makes no external requests → `wire`

```sh
sleepy wire http://localhost:3000/app --format text
```

Check a semantic or structural fact — roles, names, states; whether an
element exists or how many match; whether text is on the rendered page →
`ax`, `query`, `find`

```sh
sleepy ax http://localhost:3000/ | grep 'button "Save"'
sleepy query http://localhost:3000/ --selector '.error' --exists
sleepy find http://localhost:3000/ --text 'Welcome back'
```

Check that every label is legible against what it sits on → `contrast`

```sh
sleepy contrast http://localhost:3000/report --min wcag-aa
```

Check that nothing spills the viewport sideways → `overflow`

```sh
sleepy overflow http://localhost:3000/report --size 390x800
```

Drive an interaction and see the result → `open`, then
`click`/`fill`/`submit`, then `shot --session`

```sh
sleepy open http://localhost:3000/login --name login
sleepy click --session login --selector '#sign-in'
sleepy shot --session login --out after.png
```

Click something a component renders inside an open shadow root, which no
selector can address → `query` for the host's box, then `click --at`

```sh
sleepy query --session app --selector 'my-widget'
sleepy click --session app --at 620,180
```

Check another breakpoint without reopening → `resize`

```sh
sleepy resize --session app 390x844
sleepy shot --session app --out narrow.png
```

Compare a screenshot against a baseline → `peep compare` (PixelPeeper, a
sibling tool: it works on any PNG in pixel space; Sleepy owns the page and
its CSS-px coordinates)

```sh
sleepy shot http://localhost:3000/ --out after.png
peep compare before.png after.png
```

Wait until the page is actually ready before reading it → `--wait-for`, on
any loading verb. The page pushes and the host holds the budget, so no verb
needs a sleep: `js:<expr>` is re-evaluated **inside the page** until it is
truthy, and `message:<name>` settles when the page itself posts to
`window.webkit.messageHandlers.<name>`.

```sh
sleepy shot http://localhost:3000/app --wait-for '#chart' --out chart.png
sleepy load http://localhost:3000/app --wait-for 'js:window.ready === true'
sleepy load http://localhost:3000/app --wait-for message:appReady
```

Capture a page that uses webfonts, without catching it mid-fallback → just
`shot`; the load event already waits for a `@font-face` the page's own
stylesheet asks for

```sh
sleepy shot http://localhost:3000/report --out report.png
```

Do **not** add a sleep, and do not reach for `--wait-for
"js:document.fonts.status === 'loaded'"`: a shot flushes the page's rendering
before it rasterizes, and both `document.fonts.status` and
`document.fonts.check(…)` already read ready on a page that has not requested
the font, so for a font the page asks for *after* load they settle on the
fallback. Wait for what the page does instead — a selector, or a predicate
naming the page's own state (measured:
[2026-08-29-paint-after-fonts-ready.md](2026-08-29-paint-after-fonts-ready.md)).

Read console errors → `load`, `console`

```sh
sleepy load http://localhost:3000/app
sleepy console http://localhost:3000/app --format text
```

Get a value out of the page → `eval`

```sh
sleepy eval http://localhost:3000/ --js 'return document.title;'
```

Something failed and you don't know why → `doctor`

```sh
sleepy doctor
```

**Sandbox note.** WebKit cannot start under a restrictive sandbox — a load
that "never finishes" and times out is usually this, not a slow page. In
Claude Code, run the `sleepy` call with the Bash sandbox disabled.

Every `sleepy` invocation above is real — check a verb's own `--help` before
trusting an example that looks stale. `peep`'s own flags aren't Sleepy's to
promise; only its subcommand name is given (see
[2026-08-28-agent-feedback-synthesis.md](2026-08-28-agent-feedback-synthesis.md),
"Sleepy vs PixelPeeper").
