# A shared `WKWebsiteDataStore` shares cookies, not a cache

**2026-08-29 — findings, while building `HostGroup` (leaf pKB1B).**

The Woodcase harness reported 142 ms per load on a page carrying 3.4 MB of
scripts, every load re-fetching all of it, and asked for several `PageHost`s
that share one browser
(`project/2026-08-29-woodcase-harness-feedback.md`, finding 9). The plan's
ruling followed from a premise:

> **A `HostGroup` is one browser, and the jar belongs to the browser.** WebKit
> keeps cookies and the HTTP cache in the same `WKWebsiteDataStore`, so sharing
> a cache means sharing cookies.
> — `project/2026-08-29-woodcase-harness-plan.md`

**Half of that premise is wrong, and it is the half the performance goal rests
on.** Sharing a *non-persistent* `WKWebsiteDataStore` does share its cookies.
It does not share an HTTP cache, because an ephemeral session has no network
cache to share: the cache that serves a repeated subresource lives in the web
view's own content process, and two `WKWebView`s do not share one.

The jar half of the ruling stands, and `HostGroup` implements it. The cache
half does not, and no arrangement reachable from public API on a macOS 12 floor
delivers it.

## What was measured

`scripts/measure-host-group.sh` (its header names the two knobs). Each
arrangement loads the same page twice; the page's one `<script>` is served with
`Cache-Control: max-age=3600`, a `Date`, a `Last-Modified` and an `ETag`, and
the fixture server counts how many times it is actually asked for it. Two
requests means no cache was used.

| Arrangement | Script fetches for 2 loads |
| --- | --- |
| two views, one ephemeral store | **2** |
| two views, one ephemeral store + one shared `WKProcessPool` | **2** |
| one view, two loads, ephemeral store | **1** |
| two views, one ephemeral store, the first released before the second exists | **2** |
| two views, the persistent default store | **1** |

Reproduce: `scripts/measure-host-group.sh` (macOS 15.x, Xcode 26 SDK,
2026-08-29, load average 30).

Three things follow.

1. **The cache is real and it is per web view.** One view reloading the page
   fetches the script once. So the failures above are failures to *share*, not
   an absent cache or a mis-served fixture.
2. **`WKProcessPool` does nothing.** It is deprecated at exactly this package's
   floor — `API_DEPRECATED("Creating and using multiple instances of
   WKProcessPool no longer has any effect.", macos(10.10, 12.0))` in
   `WKProcessPool.h` — and the measurement agrees. `HostGroup` therefore holds
   no process pool; a property that holds no decision is a bug.
3. **Only a persistent store shares a cache.** The default store is the one
   arrangement that serves the second load from cache. That is the whole
   mechanism: WebKit creates its `NetworkCache` for a session that has a cache
   directory, and an ephemeral session has none.

## What grouping costs and saves, in milliseconds

`scripts/measure-host-group.sh 6 3400000`, six loads of a page with a 3.4 MB
script, run four times on the same machine (load average 17–30, so treat the
absolute numbers as an upper bound):

| Arm order | Fresh hosts | One group |
| --- | --- | --- |
| fresh first | 285.0 ms | 205.1 ms |
| group first | 204.0 ms | 259.8 ms |
| fresh first | 346.3 ms | 201.9 ms |
| group first | 202.3 ms | 296.9 ms |

**Whichever arm runs second wins**, at about 202 ms, regardless of which one it
is; the first arm pays 204–346 ms. That is warm-up, not grouping. All six
script fetches happen in both arms, every time. So on this seam a group buys
**no measurable per-load time** — which is exactly what the table above
predicts.

The order effect is why the script takes `SLEEPY_MEASURE_ORDER=group`: a
one-order measurement here would have reported a 30% win that does not exist.

## What `HostGroup` is therefore for

What it does deliver, and what the tests assert:

- **One cookie store across members.** A cookie set during one member's load is
  sent by the next member's request. Log in once, render many pages.
- **One jar, imported once and exported after any member's load.** Per-host
  import inside a shared store would resurrect a cookie an earlier member's
  page had deleted. A member whose `LoadOptions.jar` disagrees with the
  group's is a usage error.
- **The seam a shared cache would arrive through**, if the floor or the ruling
  on persistence ever moves.

## What would deliver the performance goal

Two options, both needing a decision that is not this leaf's to make.

1. **An isolated persistent store per group.**
   `WKWebsiteDataStore(forIdentifier:)` is macOS 14, so on a 12 floor it is
   `@available`-gated and the win is 14-only; it also writes under
   `~/Library/WebKit`, which breaks today's promise that nothing on disk is
   touched unless `LoadOptions.jar` names a jar. The current leaf's brief
   explicitly ruled a persistent store out.
2. **One web view, re-used.** The measured "one view, two loads" row is the
   whole win, and `PageHost.resize(to:)` already moves the viewport without a
   reload. A `shot --sweep` that re-rendered one host across sizes would pay
   for subresources once. Theme is the open question: `prefers-color-scheme`
   comes from the view's `NSAppearance`, and whether a page re-evaluates its
   media queries on an appearance change mid-life is unmeasured.

Both are filed in `project/backlog.md`.
