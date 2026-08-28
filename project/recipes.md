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

Compare a screenshot against a baseline → `peep compare` (PixelPeeper, a
sibling tool: it works on any PNG in pixel space; Sleepy owns the page and
its CSS-px coordinates)

```sh
sleepy shot http://localhost:3000/ --out after.png
peep compare before.png after.png
```

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
