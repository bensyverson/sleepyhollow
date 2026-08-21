/// The baseline console instrumentation every load carries: a document-start
/// script that counts the page's errors and streams them.
///
/// **It runs in the page world, and it has to.** A content world has its own
/// `console` global, so an isolated-world override of `console.error` never
/// sees the page's calls — demonstrated, and the same root cause as the wire
/// spike's finding that a `fetch` recorder must be page-world. The script
/// therefore lives on the page, namespaced under a single non-enumerable
/// `window.__sleepyHollow`, and always delegates to the page's original
/// `console.error` so the page behaves exactly as it would unobserved.
///
/// The count is *pulled*, not pushed: script-message delivery is not ordered
/// against `didFinish`, so the script keeps its own counter and the host reads
/// it with one round-trip once the load settles. The messages are posted as
/// well, so the console verb gets a live stream (``PageHost/consoleMessageName``)
/// without the host changing.
enum ConsoleCapture {
    /// The namespaced global the script keeps its state under.
    static let stateGlobal: String = "__sleepyHollow"

    /// The document-start page-world script.
    static func script(messageName: String) -> InjectedScript {
        InjectedScript(source: source(messageName: messageName), injectAt: .documentStart, world: .page)
    }

    /// The body ``PageHost/evaluate(_:arguments:in:)`` runs to read the count.
    static let countExpression: String = """
    return (window.\(stateGlobal) && window.\(stateGlobal).errorCount) || 0;
    """

    private static func source(messageName: String) -> String {
        """
        (function () {
          if (window.\(stateGlobal)) { return; }
          var state = { errorCount: 0 };
          Object.defineProperty(window, '\(stateGlobal)', {
            value: state, enumerable: false, configurable: true, writable: false
          });
          function report(kind, text) {
            state.errorCount += 1;
            try {
              window.webkit.messageHandlers.\(messageName).postMessage(
                JSON.stringify({ kind: kind, text: text })
              );
            } catch (ignored) { /* the host may not be listening; the count still stands */ }
          }
          var original = console.error;
          console.error = function () {
            report('console.error', Array.prototype.map.call(arguments, String).join(' '));
            return original.apply(console, arguments);
          };
          window.addEventListener('error', function (event) {
            report('uncaught', String((event && event.message) || 'error'));
          });
          window.addEventListener('unhandledrejection', function (event) {
            report('unhandledrejection', String(event && event.reason));
          });
        })();
        """
    }
}
