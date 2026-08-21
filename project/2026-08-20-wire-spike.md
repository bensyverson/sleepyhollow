# Wire spike — inventory field availability & fetch-recorder limits

*2026-08-20 · Claude (spike agent, leaf qDOiz) · status: findings, feeds the observe family (zffuW)*

Settles the two open wire questions from the vision doc: which
`PerformanceResourceTiming` fields the inventory layer can rely on across the
WebKits that macOS 12 can carry, and the fetch recorder's response-body
limits, demonstrated against a live prototype.

**Method.** Version-gated claims come from MDN browser-compat-data, WebKit
release notes and WebKit source (cited inline). Behavioural claims were
demonstrated with a throwaway prototype — a headless `WKWebView` host with a
document-start page-world recorder, driven against two local Python origins
(`127.0.0.1:8801` / `:8802`) serving status, CORS/TAO, opaque, chunked,
endless and 50 MB endpoints. The prototype ran on macOS 26.5.2 / Xcode 26.6
(WebKit ≈ Safari 26.x), so local results are evidence for the *current* end
of the range; the *old* end rests on the cited sources. Prototype code lived
in the session scratchpad and was deliberately not kept; everything needed to
re-derive it is in this doc.

## Question 1 — what the inventory layer can show

**"WebKit on macOS 12" is a range, not a point.** WKWebView uses the system
`WebKit.framework`, which updates with Safari. macOS 12 shipped with Safari
15.0; its last Safari update was **17.6** (July 2024 — Safari 18 requires
macOS Sonoma). So the honest minimum is Safari 15.0 WebKit, and the common
case for a patched Monterey machine is 16.4–17.6.
Sources: [Safari 17 on Monterey (AppleInsider)](https://appleinsider.com/articles/23/09/26/safari-17-with-enhanced-private-browsing-out-now-for-macos-ventura-macos-monterey),
[Apple Community browser/OS matrix](https://discussions.apple.com/docs/DOC-250003586),
[Safari version history (Wikipedia)](https://en.wikipedia.org/wiki/Safari_version_history).

### Field-by-field availability

Safari columns from MDN browser-compat-data
(`api/PerformanceResourceTiming.json`,
[raw JSON](https://raw.githubusercontent.com/mdn/browser-compat-data/main/api/PerformanceResourceTiming.json),
fetched 2026-08-20). "Current WebKit" column verified locally by the
prototype's inventory probe (`field in PerformanceResourceTiming.prototype`
plus live entry values), macOS 26.5.2.

| Field | Safari arrival | Stock macOS 12 (Safari 15.0) | Updated macOS 12 (≤ 17.6) | Current WebKit (26.x, local probe) | Cross-origin gating |
|---|---|---|---|---|---|
| interface, `initiatorType` | 11 | yes | yes | yes | — |
| `nextHopProtocol` | 11 | yes | yes | yes | `""` without TAO (demonstrated) |
| `fetchStart` … `responseEnd`, `workerStart`, redirect/DNS/connect/`secureConnectionStart`, `requestStart`, `responseStart` | 11 | yes | yes | yes | detail timestamps `0` without TAO (demonstrated); `startTime`/`duration`/`responseEnd` always present |
| `transferSize`, `encodedBodySize`, `decodedBodySize` | 16.4 | **no** | yes | yes | **same-origin only — TAO does not help** (see below) |
| `serverTiming` | 16.4 | **no** | yes | yes | same restriction as sizes |
| `responseStatus` | **never shipped** (BCD `version_added: false`) | no | no | **no** (probe: `false`) | n/a |
| `deliveryType`, `firstInterimResponseStart` | 26.4 | no | no | yes | — |
| `contentType`, `renderBlockingStatus` | not shipped | no | no | no (probe: `false`) | n/a |

Corroboration for the 16.4 sizes:
[WebKit Features in Safari 16.4](https://webkit.org/blog/13966/webkit-features-in-safari-16-4/)
lists "transfer size metrics for first parties in `ServerTiming` and
`PerformanceResourceTiming`" — note *first parties*.

**Sizes ignore Timing-Allow-Origin — demonstrated.** A cross-origin fetch
with `Timing-Allow-Origin: *` exposed `nextHopProtocol`, `requestStart`,
`responseStart` (TAO works for timing) but still reported
`transferSize`/`encodedBodySize`/`decodedBodySize` as `0`. This is
deliberate: WebKit restricts the size fields to strictly same-origin
requests, "intentionally stricter than a TAO check"
([WebKit commit 20108e3](https://github.com/WebKit/WebKit/commit/20108e3e4a2dbb9c82b4f0068ae546f09e90f381),
bug 245501, citing [w3c/server-timing#89](https://github.com/w3c/server-timing/issues/89)).

### Headline for `sleepy wire`'s inventory

- **HTTP status for subresources is unavailable on every WebKit we can
  reach** — `responseStatus` has never shipped in Safari, including current.
  Status comes from exactly two places: `WKNavigationDelegate`'s
  `decidePolicyFor navigationResponse` (main-frame and the few delegate-visible
  responses) and the fetch log. The vision doc's "status where the platform
  provides it" resolves to: main frame yes, subresources no, fetch calls via
  the recorder.
- **Sizes are same-origin-only and require Safari ≥ 16.4** (so: present on
  any Monterey machine patched since March 2023, absent on stock 15.0).
  Cross-origin entries report `0` regardless of TAO — the inventory should
  emit `null` rather than a misleading `0` when the entry is cross-origin.
- **Timing detail needs TAO cross-origin**; `startTime`/`duration` are
  always real. `initiatorType` and URL are always available — the inventory
  of *what was requested* is complete even where the *how it went* is not.
- The Safari-26.4 additions (`deliveryType`, `firstInterimResponseStart`)
  and the never-shipped fields are not worth modelling; treat every field
  beyond the Safari 11 set as optional in the wire JSON.

Reproduce the probe: run the prototype below; its last scenario returns
`{present, sameOriginFetch, imgSubresource, corsNoTao, corsTao, opaqueNoCors, workerFetchVisible, xhr}`.

## Question 2 — fetch-recorder limits, demonstrated

Prototype: SwiftPM executable (`swift build`, sandbox off — see gotchas),
`WKWebView` + `WKUserScript(..., injectionTime: .atDocumentStart,
forMainFrameOnly: true, in: .page)` + `userContentController.add(handler,
contentWorld: .page, name: "wire")`, against
`python3 server.py 8801` / `python3 server.py 8802` (endpoints: `/page`,
`/json`, `/echo` POST, `/status?code=`, `/cors`, `/cors-tao`, `/plain`,
`/large?mb=`, `/chunked-big?mb=`, `/stream?seconds=&chunks=`, `/endless`).
Figures below are from the third run (`run3.log`); all reproduced across runs.

### What survives — the fragility the recorder exists to fix

Normalizing through `new Request(input, init)` captured **method, headers and
request body** identically for all three call styles:

- `fetch(url, {method, headers: {…}, body})` → captured.
- `fetch(url, {headers: new Headers({…})})` → captured
  (`x-spike: via-headers`, body `hello-from-headers`).
- `fetch(new Request(url, {…}))` → captured (`x-spike: via-request`, body
  `hello-from-request`; note `Request` adds `content-type:
  text/plain;charset=UTF-8` for string bodies — report what's real).

If `new Request(input, init)` throws (e.g. GET with body), delegate to native
fetch untouched so the page gets the native error.

### The demonstrated limits

1. **Response-clone timing is a one-microtask race.** The recorder's
   `.then` is attached before the promise is returned, so it runs before the
   page's continuation — but only until its first `await`. Cloning after
   `await` produced `TypeError: Body is disturbed or locked` on every
   page-consumed response (first prototype run); cloning **synchronously at
   the top of the fulfillment handler** fixed all of them. This is a hard
   requirement on the recorder's shape.
2. **Opaque (`no-cors` cross-origin) responses are honestly empty**:
   `type: "opaque"`, `status: 0`, zero headers, and `clone().text()` resolves
   to `""` (no error). Report the type and skip the body; a `status: 0` in
   the log is an opaque response, not a network failure.
3. **Streaming: `clone()` does not stall the page, but the report waits for
   the stream.** With a 3 s chunked response read incrementally by the page,
   the page saw its first chunk at ~0 ms and the recorder's body message
   arrived only at stream end (`readMs: 3029`). Response-head and body must
   therefore be **separate messages**.
4. **Naive `clone().text()` on a never-ending stream never resolves** — the
   body report simply never arrives (demonstrated over the remaining ~18 s of
   the run) and the clone buffers without bound. A capped streaming read of
   the clone (`body.getReader()`, byte cap, cancel on cap) returned
   `truncated: "size"` immediately at the cap; on the endless stream it
   returned `truncated: "time"` with the ticks received so far.
5. **Page-world timers are throttled in a headless web view.** The capped
   reader's 1.5 s `setTimeout` deadline fired at ~3.1 s in both runs — and
   fired exactly when the host next evaluated JS. While no
   `callAsyncJavaScript` was pending, timers *and* stream-read resolutions
   stalled. Consequences: the **byte cap is the reliable guard; the time
   budget belongs to the Swift host**, and trailing body reports may land on
   the next host interaction. (Flag for the pagehost/wait leaves: headless
   throttling affects any page that waits on its own timers.)

   > **Corrected 2026-08-20 by the wait engine (leaf oCDLF): plain page
   > timers are *not* throttled in the shipped host, and a host pump makes no
   > difference.** Measured against a real `PageHost` with no host-side
   > evaluation at all after `didFinish`: `setTimeout(…, 400)` fired at
   > 400 ms and `setTimeout(…, 1500)` at 1501 ms; pumping every 250 ms or
   > 50 ms gave 401/1501 ms. Network completions also arrive unpumped. What
   > *never* fires headless is `requestAnimationFrame` — there is no window to
   > render into — so the stalled 1.5 s deadline above was most likely the
   > capped reader's stream-read resolution, not timer alignment. The
   > conclusions above still stand for the recorder (the byte cap is the
   > reliable guard; the host owns the budget), but no leaf should design
   > around "page timers are throttled" as a general fact. Details and the
   > reproducing probes: `project/2026-08-20-wait-engine.md`.
6. **Large bodies cost memory, not time.** A 50 MB `Content-Length` response
   was fully read by the clone in 62 ms on localhost — the danger is holding
   50 MB strings per request, not stalling. A `Content-Length` pre-check can
   skip the read early, but **chunked responses carry no `Content-Length`**
   (demonstrated: 8 MB chunked body, no header), so the streaming cap is the
   real guard. Cap granularity is one network read (~1 MiB observed against
   a 256 KiB cap) — slice the captured text to the cap before reporting.
7. **Abort doesn't wedge the recorder**: page `AbortController.abort()`
   mid-stream produced a body message `error: "AbortError: Fetch is
   aborted"`.
8. **No pre-injection gap exists.** The fixture's first inline `<head>`
   script fires `fetch('/early')` as the earliest possible page-script
   request; the document-start recorder saw it (it is recorder message id 1).
   Document-start user scripts run before any page content script — there is
   no page-script fetch the recorder can miss.
9. **Workers are blind in *both* layers** (expected, confirmed): a fetch
   inside a `Worker` never reached the recorder *and* never appeared in the
   window's `performance.getEntriesByType('resource')` — workers own a
   separate performance timeline. Only the worker script's own load is
   visible to the window.
10. **XHR is invisible to the fetch recorder but fully visible to the
    inventory** (`initiatorType: "xmlhttprequest"`, sizes included when
    same-origin). State this platform truth in the wire verb's docs: the
    fetch log covers `window.fetch` in the main frame's page world; XHR,
    workers, service workers, beacons, EventSource/WebSocket and
    subresources appear in the inventory only (and worker-internal fetches
    in neither).

## Recommended recorder shape (for the observe family, zffuW)

Installation: `WKUserScript` at `.atDocumentStart` in `.page` world (must be
page world — an isolated world cannot see or wrap the page's `fetch`);
`WKScriptMessageHandler` added `in: .page` under a namespaced name. Guard
against double-install with a window sentinel.

Per exchange, **three correlated messages** (plus `error`), because the body
can arrive late, truncated, or never:

- `request` — id, url, method, mode, headers, request body (all read off a
  synchronous `req.clone()` taken *before* handing `req` to native fetch).
- `response` — id, status, statusText, type, redirected, headers, elapsed ms.
  Posted as soon as the promise fulfills.
- `body` — id, text (sliced to cap), byte count, `truncated: false | "size"
  | "time"`, or `error`. Opaque responses: skip with a marker.

Core skeleton (the exact logic the prototype validated):

```js
window.fetch = function (input, init) {
  let req; try { req = new Request(input, init); } catch (e) { req = null; }
  if (!req) return nativeFetch.call(window, input, init); // native error, untouched
  const id = nextId(), reqBody = req.clone().text().catch(() => null);
  const result = nativeFetch.call(window, req);
  result.then(async (resp) => {
    let clone = null;                      // clone SYNCHRONOUSLY —
    try { clone = resp.clone(); } catch (e) {} // before any await (limit 1)
    post({ kind: 'request', id, /* …req facts… */ requestBody: await reqBody });
    post({ kind: 'response', id, status: resp.status, type: resp.type, /* … */ });
    if (!clone || resp.type === 'opaque') return post({ kind: 'body', id, skipped: resp.type });
    post(await cappedRead(id, clone));     // reader loop: byte cap + cancel; see limits 4–6
  }, (err) => post({ kind: 'error', id, error: String(err) }));
  return result;                            // page gets the original promise
};
```

Defaults that the demonstrations support: **byte cap 256 KiB** (configurable
per invocation), **no page-side time cap** (throttled timers make it lie —
limit 5); the Swift host owns the wire verb's overall budget and reports
bodies still pending at budget end as `truncated: "budget"`. The host
assembles the three messages by id into one wire-log entry; the Starlight
acceptance shape ("one edit ⇒ exactly one POST, urlencoded, status 200, body
contains the value") needs `request` + `response` + `body` and is fully
covered.

### Reproducing

The prototype was throwaway (session scratchpad, not kept). To re-derive:
SwiftPM executable (macOS 12+, tools 5.9) embedding the recorder above;
scenario driver via `webView.callAsyncJavaScript(_:arguments:in:contentWorld:
.page)`; two `http.server`-based Python origins as described. Two traps the
rebuild will hit, both solved above: drive the process with
`RunLoop.main.run()` — `dispatchMain()` does not service the CFRunLoop
sources WebKit's IPC needs, and the navigation never finishes; and don't
trust page-world `setTimeout` for deadlines (limit 5).
