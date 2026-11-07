# ``SleepyHollow``

A headless WebKit browser for agents and tests: load a page, then ask for its pixels, DOM, computed style, accessibility tree or wire log.

## Overview

``PageHost`` is the browser. It renders real pages with the system's
`WebKit.framework`, and the `sleepy` command-line tool is a thin consumer of
this same library, so anything a verb does an embedder can do in Swift.

```swift
let host = PageHost(options: LoadOptions(size: ViewportSize(width: 1280, height: 800)))
let facts = try await host.load(url)
```

**Ask the page a question.** ``PageHost/evaluate(_:as:arguments:in:budget:)``
runs an async JavaScript body and decodes what it returns. Return a
diagnostic sentence rather than a bool, so a failing test says what the page
did; a body that throws arrives as ``EvaluationError`` carrying the page's own
message. Scripts run in the isolated world unless you pass
``InjectedScript/World/page``, where the page's own globals and upgraded
custom elements live.

**Wait inside the page.** After a click, a submit or an evaluation, use
``PageHost/waitUntil(_:in:budget:)`` for what should follow. To tell a real
navigation from a same-document change, read ``PageHost/navigationCount``
before the action and pass it to ``PageHost/waitForNavigation(after:budget:)``.

**Check another breakpoint.** ``PageHost/resize(to:)`` changes the viewport of
a loaded page without reloading it, so a second width costs a resize rather
than a second host and a second navigation.

**Capture sharp pixels.** ``ShotOperation`` takes a ``ShotScale`` of 2 or 3
for Retina density on a whole page or one element; layout and breakpoints stay
at the viewport's size, and a host that cannot render that densely refuses
rather than upsampling.

**Load with JavaScript off.** ``LoadOptions/PageScripts/disabled`` (the CLI's
`--no-js`) renders `<noscript>` content and answers every operation or refuses
with a message that names the way forward.

**Pages animate.** A host lives in an off-screen window by default
(``PageHost/Hosting/live``), so `requestAnimationFrame`, CSS transitions and
Web Animations run as on a display, and a capture of something still moving
can differ from run to run. Wait for the settled state with
``LoadOptions/wait`` instead of sleeping. ``PageHost/Hosting/windowless`` is
the opt-out, and it freezes animation time.

**Act as a user would.** ``ClickOperation``, ``PageHost/press(_:focusing:)``
and the hover step send real input through that window: the page sees
`isTrusted` true and WebKit runs the default action, even with scripts off.
A windowless host has no window to send it through, and refuses rather than
dispatch script events in its place.

Pages that need one identity — sign in once, then render many — are built as
members of a ``HostGroup``.

## Topics

### The browser

- ``PageHost``
- ``LoadOptions``
- ``HostGroup``

### Asking the page

- ``PageHost/evaluate(_:arguments:in:budget:)``
- ``PageHost/evaluate(_:as:arguments:in:budget:)``
- ``PageHost/waitUntil(_:in:budget:)``
- ``EvaluationError``

### Navigations and viewport

- ``PageHost/navigationCount``
- ``PageHost/waitForNavigation(after:budget:)``
- ``PageHost/resize(to:)``

### Capturing

- ``ShotOperation``
- ``ShotScale``
