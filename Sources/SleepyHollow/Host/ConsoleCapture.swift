/// The baseline console instrumentation every load carries: a document-start
/// script that records the page's console output — every level, plus uncaught
/// errors and unhandled rejections — counts the errors among it, and streams
/// each entry.
///
/// **It runs in the page world, and it has to.** A content world has its own
/// `console` global, so an isolated-world override of `console.error` never
/// sees the page's calls — demonstrated, and the same root cause as the wire
/// spike's finding that a `fetch` recorder must be page-world. The script
/// therefore lives on the page, namespaced under a single non-enumerable
/// `window.__sleepyHollow`, and always delegates to the page's original
/// `console` methods so the page behaves exactly as it would unobserved.
///
/// The log is *pulled*, not pushed: script-message delivery is not ordered
/// against `didFinish`, and on a one-shot load nothing is subscribed while the
/// page is talking, so the script keeps its own buffer and the host reads it
/// with one round-trip once the load settles (``ConsoleOperation``). Entries
/// are posted as well, so a live subscriber gets a stream
/// (``PageHost/consoleMessageName``) without the host changing.
///
/// The buffer is capped at ``entryCap`` entries; a page that logs in a loop
/// drops its *oldest* entries and the count of dropped ones is reported rather
/// than hidden.
enum ConsoleCapture {
    /// The namespaced global the script keeps its state under.
    static let stateGlobal: String = "__sleepyHollow"

    /// How many entries the page-side buffer holds before dropping the oldest.
    static let entryCap: Int = 1000

    /// The document-start page-world script.
    static func script(messageName: String) -> InjectedScript {
        InjectedScript(source: source(messageName: messageName), injectAt: .documentStart, world: .page)
    }

    /// The body ``PageHost/evaluate(_:arguments:in:)`` runs to read the count.
    static let countExpression: String = """
    return (window.\(stateGlobal) && window.\(stateGlobal).errorCount) || 0;
    """

    /// The body ``PageHost/evaluate(_:arguments:in:)`` runs to read the whole
    /// log: `{ messages, droppedMessages }`, decodable as ``ConsoleLog``.
    static let logExpression: String = """
    const state = window.\(stateGlobal);
    if (!state) { return { messages: [], droppedMessages: 0 }; }
    return { messages: state.entries, droppedMessages: state.dropped };
    """

    private static func source(messageName: String) -> String {
        """
        (function () {
          if (window.\(stateGlobal)) { return; }
          var state = { errorCount: 0, entries: [], dropped: 0 };
          Object.defineProperty(window, '\(stateGlobal)', {
            value: state, enumerable: false, configurable: true, writable: false
          });
          function timestamp() {
            try { return Math.round(performance.now()); } catch (ignored) { return 0; }
          }
          function text(value) {
            try {
              if (typeof value === 'string') { return value; }
              if (value instanceof Error) { return String(value); }
              if (value === null || value === undefined || typeof value !== 'object') {
                return String(value);
              }
              var json = JSON.stringify(value);
              return json === undefined ? String(value) : json;
            } catch (ignored) { return String(value); }
          }
          function record(entry) {
            if (entry.origin !== 'console' || entry.level === 'error') { state.errorCount += 1; }
            state.entries.push(entry);
            while (state.entries.length > \(entryCap)) {
              state.entries.shift();
              state.dropped += 1;
            }
            try {
              window.webkit.messageHandlers.\(messageName).postMessage(JSON.stringify(entry));
            } catch (ignored) { /* the host may not be listening; the log still stands */ }
          }
          ['debug', 'log', 'info', 'warn', 'error'].forEach(function (level) {
            var original = console[level];
            if (typeof original !== 'function') { return; }
            console[level] = function () {
              try {
                record({
                  kind: 'console.' + level,
                  level: level,
                  origin: 'console',
                  text: Array.prototype.map.call(arguments, text).join(' '),
                  timeMilliseconds: timestamp()
                });
              } catch (ignored) { /* instrumentation must never break the page */ }
              return original.apply(console, arguments);
            };
          });
          window.addEventListener('error', function (event) {
            var entry = {
              kind: 'uncaught',
              level: 'error',
              origin: 'uncaught',
              text: String((event && event.message) || 'error'),
              timeMilliseconds: timestamp()
            };
            if (event && event.filename) { entry.sourceURL = String(event.filename); }
            if (event && typeof event.lineno === 'number') { entry.line = event.lineno; }
            record(entry);
          });
          window.addEventListener('unhandledrejection', function (event) {
            record({
              kind: 'unhandledrejection',
              level: 'error',
              origin: 'unhandledRejection',
              text: text(event && event.reason),
              timeMilliseconds: timestamp()
            });
          });
        })();
        """
    }
}
