import Foundation

/// The `--wait-for js:<expression>` instrumentation: a document-start
/// page-world script that re-evaluates the expression on the page's own clock
/// and posts once, the first time it is truthy.
///
/// **The page checks; the host only bounds it.** A host-side poll runs on the
/// main actor, so an embedding whose main actor is saturated reports a timeout
/// on a page that was ready in 200 ms — measured, not theoretical
/// (`project/2026-08-29-woodcase-harness-feedback.md`, finding 1). Re-checking
/// inside the page costs the host nothing and turns the answer into one
/// message hop. ``WaitEngine`` keeps a slow host-side backstop for what this
/// script cannot answer: an expression that is not valid JavaScript never
/// parses here at all.
///
/// The script runs in the **page world** — a wait predicate is a statement
/// about the page's own globals, and an isolated world reads every one of them
/// as `undefined`, a silently wrong answer rather than a slow one. `setTimeout`
/// is the clock deliberately: page timers keep wall time in this WebKit, while
/// `requestAnimationFrame` never fires in a windowless view.
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
            source: source(expression: expression, messageName: messageName),
            injectAt: .documentStart,
            world: .page,
        )
    }

    private static func source(expression: String, messageName: String) -> String {
        """
        (function () {
          var posted = false;
          var reportedFailure = false;
          function post(payload) {
            try {
              window.webkit.messageHandlers.\(messageName).postMessage(payload);
            } catch (ignored) { /* nothing is listening; the host still has its backstop */ }
          }
          function check() {
            if (posted) { return; }
            var truthy = false;
            try {
              truthy = !!(\(expression));
            } catch (error) {
              // A predicate that throws is "not true yet", not a failure — but
              // the reason is what the timeout message needs.
              if (!reportedFailure) {
                reportedFailure = true;
                post(JSON.stringify({ truthy: false, failure: String(error) }));
              }
            }
            if (truthy) {
              posted = true;
              post(JSON.stringify({ truthy: true }));
              return;
            }
            setTimeout(check, \(checkIntervalMilliseconds));
          }
          check();
        })();
        """
    }
}
