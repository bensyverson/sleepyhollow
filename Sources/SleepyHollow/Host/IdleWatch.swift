/// The `--wait-for idle` instrumentation, and the precise contract behind the
/// word "idle".
///
/// **A page is idle when 500 ms pass — measured on the host's clock — in which
/// all four of these hold:**
///
/// 1. no new `PerformanceResourceTiming` entry is recorded (any subresource:
///    document, script, stylesheet, image, XHR, beacon…);
/// 2. no `window.fetch` call starts or settles;
/// 3. no `XMLHttpRequest.send` starts or reaches `loadend`;
/// 4. nothing is outstanding: zero fetches and XHRs in flight, and every
///    `<img>` in the document reports `complete`.
///
/// The window starts when the settle phase does, so `--wait-for idle` always
/// costs at least 500 ms — "idle" is a *measured* quiet window, not a snapshot
/// of "nothing in flight right now".
///
/// **What it deliberately does not see**, because no WebKit API offers it to a
/// page: work inside workers and service workers (their fetches appear in
/// neither the window's resource timeline nor these hooks — see the wire
/// spike), WebSocket and EventSource traffic, and CSS-driven or media
/// downloads that are still connecting but have not yet produced an entry. A
/// fetch counts as finished when its promise settles — when the response head
/// arrives — not when the page has read the body: an unread streaming body is
/// idle by this definition.
///
/// The script must run in the page world: an isolated world has its own
/// `fetch` and `XMLHttpRequest`, so hooks installed there would never see the
/// page's calls (the same root cause as ``ConsoleCapture``'s page-world
/// requirement). It keeps its state under its own non-enumerable global so it
/// neither depends on nor disturbs ``ConsoleCapture``'s.
enum IdleWatch {
    /// One reading of the page's activity, as the sampler reports it.
    struct Sample: Friendly {
        /// A monotonic count of activity events: resource entries recorded,
        /// plus fetch/XHR starts and finishes. Only *changes* matter.
        var activity: Int

        /// How much is outstanding right now: fetches and XHRs in flight plus
        /// images that have not finished loading.
        var busy: Int

        /// What a page with no watcher reports — quiet, because a page that
        /// cannot be sampled must still be able to settle rather than hang.
        static let unknown: Sample = .init(activity: 0, busy: 0)
    }

    /// The namespaced global the watcher keeps its state under.
    static let stateGlobal: String = "__sleepyHollowIdle"

    /// How long the page must stay quiet before it counts as idle.
    static let quietWindow: Double = 0.5

    /// The document-start page-world script.
    static let script: InjectedScript = .init(
        source: source,
        injectAt: .documentStart,
        world: .page,
    )

    /// The body ``PageHost/evaluate(_:arguments:in:)`` runs to take one
    /// ``Sample``; a page without the watcher reads as ``Sample/unknown``.
    static let sampleBody: String = """
    var watch = window.\(stateGlobal);
    return watch ? watch.sample() : { activity: 0, busy: 0 };
    """

    private static let source: String = """
    (function () {
      if (window.\(stateGlobal)) { return; }
      var state = {
        activity: 0,
        busy: 0,
        sample: function () {
          var loading = 0;
          var images = document.images || [];
          for (var i = 0; i < images.length; i += 1) {
            if (!images[i].complete) { loading += 1; }
          }
          return { activity: state.activity, busy: state.busy + loading };
        }
      };
      Object.defineProperty(window, '\(stateGlobal)', {
        value: state, enumerable: false, configurable: true, writable: false
      });
      function started() { state.activity += 1; state.busy += 1; }
      function finished() { state.activity += 1; state.busy -= 1; }
      try {
        new PerformanceObserver(function (list) {
          state.activity += list.getEntries().length;
        }).observe({ type: 'resource', buffered: true });
      } catch (ignored) { /* older WebKit: the fetch and XHR hooks still count */ }
      var nativeFetch = window.fetch;
      if (typeof nativeFetch === 'function') {
        window.fetch = function () {
          started();
          var result;
          try {
            result = nativeFetch.apply(window, arguments);
          } catch (error) {
            finished();
            throw error;
          }
          return result.then(function (response) {
            finished();
            return response;
          }, function (error) {
            finished();
            throw error;
          });
        };
      }
      var nativeSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function () {
        var settled = false;
        started();
        this.addEventListener('loadend', function () {
          if (settled) { return; }
          settled = true;
          finished();
        });
        return nativeSend.apply(this, arguments);
      };
    })();
    """
}
