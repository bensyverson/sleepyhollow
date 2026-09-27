# An idle page is throttled, and shot/pdf/archive never lift it (2026-09-26)

Findings for job leaf 116NLb. `sleepy open <url> --name x; sleepy eval --session x …; sleep 2; sleepy shot --session x` timed out at the call budget; with 0–1 s of idle it answered, and an eval just before the shot avoided it. The same stall failed `SessionIntegrationGoldenTests` (shot, pdf and archive `--session`) and kept the pre-commit hook red.

**Cause: WebKit throttles the content process of a windowless web view about a second after the last call that held a foreground activity, and `takeSnapshot`, printing and `createWebArchiveData` take no such activity.** On a loaded machine the throttled process is not scheduled at all, so those calls wait out the budget. `evaluateJavaScript` takes a foreground activity, which is why eval answers after any idle and why an eval right before a shot rescued it.

It is a *load* bug, not a timing bug: on a quiet machine the throttled process still gets a core and the shot answers in ~0.1 s. The brief's "every time" held only because the machine was at load 100–250 for the whole day.

## Evidence

All on macOS 27.0 (26A428), WebKit 22625.1.29.11.27, 8 cores, debug `sleepy` from this worktree.

1. **The stall needs load.** `idle 2 s → shot` timed out (exit 3 at the 15–20 s budget) in four of four runs at load average 73–200, and answered in 0.11–0.15 s in five of five runs at load 12–15, minutes apart. `idle 0 → shot` answered in 0.14 s at load 73.
2. **The helper is idle, waiting on WebKit.** A `sample` of the helper during the stall: the main thread parked in `CFRunLoopRun`, nothing else busy. lldb breakpoint hit counts (`-[WKWebView takeSnapshotWithConfiguration:…]` and `WebPageProxy::takeSnapshot` hit, `WebPageProxy::callAfterNextPresentationUpdate` not) show the request reached WebKit and was sent to the content process.
3. **WebKit logs the throttle.** `log show --predicate 'processID == <helper> AND subsystem == "com.apple.WebKit"'`: the eval is `Starting foreground activity / 'WebPageProxy::runJavaScriptInFrameInScriptWorld'`; ~1 s after it ends, `Releasing process assertion 'WebProcess Foreground Assertion'`, leaving `process assertion type 1 (foregroundActivities=0, backgroundActivities=…)`. The snapshot logs no activity at all. RunningBoard reports the process `running-active-NotVisible` throughout — throttled, not suspended.
4. **The priority drops.** `ps -M -p <web content pid>` every 0.5 s after an eval (`scripts/idle-throttle-probe.sh`): threads at 31/37/47 for ~1.0–1.2 s, then every thread at 4 (some runs then settle at 20), which is where it stays — 57 s watched.
5. **Deterministic in a test, without load.** `PageHostSchedulingTests` waits for the idle page's task priority (`proc_pidinfo(PROC_PIDTASKINFO).pti_priority`) to drop, `SIGSTOP`s the content process so the call stays pending, and watches the priority while it is. Unheld, all three calls left it at 4 ("a pending snapshot left the page at priority 4, not 31", same for archive and pdf) — and after `SIGCONT`, at load ~175, none answered within its 20 s budget.

## What does not work

- `WKPreferences.inactiveSchedulingPolicy = .none` (public, macOS 14+; the default here reads `.suspend`). Set on the configuration, it leaves the drop to 4 exactly as before — measured with the same test. It decides whether an idle view is *suspended*, not whether it is throttled.
- Hosting the view in the off-screen window with occlusion detection off would make WebKit call it visible and keep it foreground, but it also makes the page visible — rAF runs, `visibilityState` flips, `--wait-for idle` over a rAF chain never settles. That is the timing change `PageHost.ensureOffscreenWindow(ordering:rendering:)` refuses to make by default, and it needs the private selector.

## The fix

`PageHost.holdingForeground(_:)` (internal) makes a call under a *hold*: before it, an async JavaScript call in a content world of its own (`sleepy-foreground-hold`) that awaits a promise; after it, however it ends, a second call that settles the promise. WebKit keeps the first call's foreground activity for as long as it is outstanding, so the content process is at foreground priority while the snapshot, print or archive is in flight. `PageHost.snapshot(_:budget:)`, `ArchiveOperation` and `PDFOperation` use it. Cookie calls do not: they are answered by the networking process, and measured after the same idle at load ~45 they answered in 0.07–0.39 s.

After the fix, at load 180–200: shot/pdf/archive `--session` after 3 s idle answered in 0.14/1.20/0.08 s, the original repro after 2 s and 10 s idle in 0.11–0.12 s, and `SessionIntegrationGoldenTests` passed three runs in a row (6.7–9.3 s each).

The hold rests on WebKit behaviour, not a documented contract — that a pending JavaScript call keeps a foreground activity. `PageHostSchedulingTests` is the canary: if WebKit stops throttling an idle page its `#require` fails and says the hold may be retired; if a pending JavaScript call stops lifting the page, its expectation fails.

## Reproduce

```
swift build
scripts/idle-throttle-probe.sh 3 shot     # priorities after the eval, then the shot's exit and time
swift test --filter PageHostSchedulingTests
```

Quote the load average with any figure: the probe prints it.
