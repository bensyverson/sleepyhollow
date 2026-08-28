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

SleepyHollow is Swift and needs macOS 12 or later — it links the system
`WebKit.framework` on purpose. There's no Homebrew formula yet, so build it
from source:

```sh
git clone https://github.com/bensyverson/sleepyhollow.git
cd sleepyhollow
swift build -c release
```

The binary lands at `.build/release/sleepy`; put it on your `PATH` or call it
by that full path.

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

Every loading verb (`load`, `shot`, `pdf`, `archive`, `dom`, `query`, `style`,
`find`, `ax`, `console`, `wire`, `eval`) takes the same shape — a URL, then
flags for viewport size, theme, waiting, and one-shot actions like
`--click`/`--fill`/`--submit`. Run `sleepy` with no arguments for a primer, or
`sleepy <verb> --help` for that verb's flags and examples. Exit codes are a
public contract (0 success, 1 clean negative, 2 usage error, 3 timeout, 4 load
failure, 5 environment error) — see `Sources/SleepyHollow/Core/ExitStatus.swift`
for the full table.

Need a page to outlive one invocation? `sleepy open <url> --name <n>` starts a
named session; every verb then takes `--session <n>` to act on that same live
page, `sleepy sessions list` shows what's open, and `sleepy close <n>` ends
it. Without `--session`, every invocation loads a fresh, ephemeral page unless
you attach a `--jar` for cookies that should outlive it.

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
