# SleepyHollow

A command-line tool that opens web pages and tells computer programs what it sees.

SleepyHollow is a headless browser built for AI agents and automated tests, not
people. It renders real pages with the WebKit engine already built into every
Mac, then lets you ask for what you need — a screenshot, the raw HTML, the
accessibility tree, a log of network requests — as one command that prints
structured text and exits with a code that means something. No browser
profile, no background process, no protocol to speak: run a verb, read the
output, move on.

## Install

```sh
brew install bensyverson/tap/sleepy
```

On macOS 15 or later with Apple silicon, that pours a prebuilt, signed binary;
anywhere else Homebrew builds it from source with Xcode 26.4 or later.

SleepyHollow is Swift and links the system `WebKit.framework` on purpose. To
build it from source, on macOS 12 or later:

```sh
git clone https://github.com/bensyverson/sleepyhollow.git
cd sleepyhollow
swift package experimental-install --product sleepy
```

That builds a release binary and copies it to `~/.swiftpm/bin/sleepy`. Add
that directory to your `PATH` once (`export PATH="$HOME/.swiftpm/bin:$PATH"`
in `~/.zshrc`). The installer refuses to overwrite, so upgrading (or removing)
goes through `swift package experimental-uninstall sleepy` first.

To build without installing, run `swift build -c release` instead — the
binary lands at `.build/release/sleepy`, and you can put it on your `PATH` or
call it by that full path.

To use the library from another Swift package instead, add it as a
dependency in `Package.swift`:

```swift
.package(url: "https://github.com/bensyverson/sleepyhollow.git", branch: "main")
```

(Pin to a version once 1.0 is tagged.)

## Quick start

Load a page and check that it's alive:

```sh
$ sleepy load https://example.com/
{
  "consoleErrorCount" : 0,
  "dialogs" : [],
  "finalURL" : "https://example.com/",
  "httpStatus" : 200
}
```

Read the page the way assistive technology would — roles, names, and states,
with layout stripped away:

```sh
$ sleepy ax https://example.com/
document "Example Domain"
  heading "Example Domain" (level=1)
  paragraph
    text "This domain is for use in documentation examples without needing permission. Avoid use in operations."
  paragraph
    link "Learn more"
```

Take a screenshot:

```sh
sleepy shot https://example.com/ --out shot.png
```

For a sharp Retina image add `--scale 2` (or 3): layout and breakpoints stay
at `--size`, only the pixels get denser, and it works on a `--selector` crop
too. `sleepy resize` changes an open session's viewport without reloading.

Assert the page reads and fits — each exits 1 when it finds something, so it
drops straight into a script:

```sh
sleepy contrast https://example.com/ --min wcag-aa
sleepy overflow https://example.com/ --size 390x800
```

If a call fails and you don't know why — a load that never finishes under a
sandbox, a session that won't open — ask the tool itself:

```sh
sleepy doctor
```

Every loading verb (`load`, `shot`, `pdf`, `archive`, `dom`, `query`, `style`,
`find`, `ax`, `contrast`, `overflow`, `console`, `wire`, `eval`) takes the same shape — a URL, then
flags for viewport size, theme, waiting, and one-shot actions like
`--click`/`--fill`/`--submit`. Run `sleepy` with no arguments for a primer, or
`sleepy <verb> --help` for that verb's flags and examples. Exit codes are a
public contract (0 success, 1 clean negative, 2 usage error, 3 timeout, 4 load
failure, 5 environment error) — see `Sources/SleepyHollow/Core/ExitStatus.swift`
for the full table.

`eval` runs your script in the page's own world by default, so page globals
and upgraded custom elements are visible. `--world isolated` runs it in
Sleepy's world instead: it shares the DOM (nodes, attributes, shadow roots)
but none of the page's JavaScript, so page classes and globals read as
`undefined`. `sleepy eval --help` has the details.

Need a page to outlive one invocation? `sleepy open <url> --name <n>` starts a
named session; every verb then takes `--session <n>` to act on that same live
page, `sleepy sessions list` shows what's open, and `sleepy close <n>` ends
it. Without `--session`, every invocation loads a fresh, ephemeral page unless
you attach a `--jar` for cookies that should outlive it.

## Embedding the library

`PageHost` is the same headless browser the CLI drives, usable directly from
Swift. Defaults worth knowing if you're coming from a raw `WKWebView`: a host
never follows the Mac's Dark Mode setting (see `ColorTheme`); it lives in an
off-screen window, so pages animate and focus works as in a browser (pass
`hosting: .windowless` to opt out); and a pinned `--scale`/`ShotScale` refuses
to upsample, so it fails loudly on a non-Retina host instead of quietly
rendering soft.

```swift
import SleepyHollow

let host = PageHost(options: LoadOptions(size: ViewportSize(width: 1280, height: 800)))
let facts = try await host.load(url)

// Ask the page a question and get a typed answer. Return a sentence rather
// than a bool, so a failing test says what was actually there.
let verdict = try await host.evaluate(
    "const h = document.querySelector('h1'); return h ? 'h1 reads ' + h.textContent : 'no h1';",
    as: String.self,
    in: .page,
)

// After a click or a submit, wait inside the page for what should follow.
try await host.waitUntil("document.querySelector('.result') !== null")

// Check another breakpoint without reloading, then capture at 2x.
host.resize(to: ViewportSize(width: 390, height: 844))
let shot = try await ShotOperation(scale: try ShotScale(factor: 2)).execute(on: host)
```

A script that throws surfaces as `EvaluationError` carrying the page's own
message; `host.navigationCount` and `waitForNavigation(after:)` tell a real
navigation from a same-document change; and
`LoadOptions(pageScripts: .disabled)` (the CLI's `--no-js`) loads a page with
its JavaScript off.

Hosts that need one identity — sign in once, then render many pages — are
built as members of a `HostGroup`, which owns the cookie store and the jar
for all of them. It does not share an HTTP cache: see
[project/2026-08-29-host-group-cache.md](project/2026-08-29-host-group-cache.md)
for what WebKit does and does not share.

Build the API reference with `swift package generate-documentation` (see
CLAUDE.md for the full DocC workflow).

## More

- **PixelPeeper** is a sibling command-line tool (same author, separate
  binary) for image-space work on PNGs from anywhere, not only SleepyHollow's
  own renders — cropping, resizing, contact sheets, and `peep compare` as the
  baseline-comparison path for a visual regression. The rule that decides
  which tool owns a feature: anything that needs the page or page
  coordinates is SleepyHollow's; anything that works on an arbitrary PNG is
  PixelPeeper's.
- [project/2026-08-20-vision.md](project/2026-08-20-vision.md) — why this
  tool exists and the philosophy behind it
- [project/recipes.md](project/recipes.md) — goal-to-verb routing (same
  content as `sleepy recipes` / `sleepy help recipes`)
- [project/](project/) — dated findings and design decisions as the project
  developed
- API reference: build the DocC archive with
  `swift package generate-documentation`, or browse it live with
  `swift package preview-documentation`

## Author & license

Built by [Ben Syverson](https://github.com/bensyverson). Released under the
[MIT License](LICENSE).
