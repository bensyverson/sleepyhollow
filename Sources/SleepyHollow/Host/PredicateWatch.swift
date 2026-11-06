import Foundation

/// The page-side predicate watch: JavaScript that re-evaluates an expression
/// on the page's own clock and posts once, the first time it is truthy.
///
/// Two consumers arm it. `--wait-for js:<expression>` installs it as a
/// document-start script before the load (``script(expression:messageName:)``);
/// ``PageHost/waitUntil(_:in:budget:)`` starts it in a page that is already
/// loaded, through one evaluation (``armingBody(expression:messageName:watch:lifetime:)``).
/// Both run the same loop.
///
/// **The page checks; the host only bounds it.** A host-side poll runs on the
/// main actor, so an embedding whose main actor is saturated reports a timeout
/// on a page that was ready in 200 ms — measured, not theoretical
/// (`project/2026-08-29-woodcase-harness-feedback.md`, finding 1). Re-checking
/// inside the page costs the host nothing and turns the answer into one
/// message hop. ``WaitEngine`` keeps a slow host-side backstop for what the
/// document-start script cannot answer: an expression that is not valid
/// JavaScript never parses there at all. The arming body needs none — it
/// fails to parse as a whole, so the evaluation that would start the watch
/// throws the syntax error instead.
///
/// The load-time script runs in the **page world** — a wait predicate is a
/// statement about the page's own globals, and an isolated world reads every
/// one of them as `undefined`, a silently wrong answer rather than a slow one.
/// `setTimeout` is the clock deliberately: it runs on any host, while
/// `requestAnimationFrame` never fires in a windowless view. On a hidden page
/// (a ``PageHost/Hosting/windowless`` host) WebKit aligns this nested chain to
/// one second from about its tenth tick; on a live host — the default — it
/// keeps a 16–20 ms cadence (job issue `PFrL42`, `LiveHostingTests`).
enum PredicateWatch {
    /// How often the page re-evaluates the expression, in milliseconds — a
    /// frame's worth, which is as often as anything it renders can change.
    static let checkIntervalMilliseconds: Int = 16

    /// The document-start page-world script for `expression`.
    ///
    /// Posts a ``WaitEngine/Probe`` as JSON text on `messageName`: once with
    /// `truthy` when the expression first holds, and at most once more, before
    /// that, carrying the first `failure` it threw — which is what an
    /// exhausted budget has to show, and what the host's own check may never
    /// be scheduled to find.
    static func script(expression: String, messageName: String) -> InjectedScript {
        InjectedScript(
            source: "(\(loop(expression: expression, messageName: messageName, watch: nil, lifetime: nil)))();",
            injectAt: .documentStart,
            world: .page,
        )
    }

    /// An async function body that starts the watch in a loaded page and
    /// returns the first check's ``WaitEngine/Probe``.
    ///
    /// Every push carries `watch`, so concurrent waits on one handler name
    /// each hear only their own. The page stops checking once `lifetime`
    /// seconds have passed on its own clock — housekeeping, not a deadline:
    /// the host owns the deadline, and this only keeps a wait the host gave
    /// up on from re-checking for the rest of the page's life.
    static func armingBody(
        expression: String,
        messageName: String,
        watch: String,
        lifetime: TimeInterval,
    ) -> String {
        "return (\(loop(expression: expression, messageName: messageName, watch: watch, lifetime: lifetime)))();"
    }

    /// The loop both forms share, as a JavaScript function expression that
    /// runs the first check synchronously and returns its probe.
    private static func loop(
        expression: String,
        messageName: String,
        watch: String?,
        lifetime: TimeInterval?,
    ) -> String {
        let watchLiteral: String = watch.map { "\"\($0)\"" } ?? "null"
        let stopLiteral: String = lifetime.map { "Date.now() + \(Int(($0 * 1000).rounded(.up)))" } ?? "null"
        return """
        function () {
          var watch = \(watchLiteral);
          var stopAt = \(stopLiteral);
          var posted = false;
          var firstFailure = null;
          function post(payload) {
            if (watch !== null) { payload.watch = watch; }
            try {
              window.webkit.messageHandlers.\(messageName).postMessage(JSON.stringify(payload));
            } catch (ignored) { /* nothing is listening; the host still owns the deadline */ }
          }
          function check() {
            if (posted) { return; }
            if (stopAt !== null && Date.now() > stopAt) { return; }
            var truthy = false;
            try {
              truthy = !!(\(expression));
            } catch (error) {
              // A predicate that throws is "not true yet", not a failure — but
              // the reason is what the timeout message needs.
              if (firstFailure === null) {
                firstFailure = String(error);
                post({ truthy: false, failure: firstFailure });
              }
            }
            if (truthy) {
              posted = true;
              post({ truthy: true });
              return;
            }
            setTimeout(check, \(checkIntervalMilliseconds));
          }
          check();
          return firstFailure === null ? { truthy: posted } : { truthy: posted, failure: firstFailure };
        }
        """
    }
}
