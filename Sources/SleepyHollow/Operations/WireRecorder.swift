/// The document-start page-world script that records `window.fetch`, and the
/// expressions the host reads it back with.
///
/// **Page world, document start, both required.** A content world has its own
/// `fetch`, so an isolated-world wrapper never sees the page's calls; and a
/// wrapper installed after parsing begins misses the first inline script's
/// request. The consequence is honest and unavoidable: page code can see the
/// recorder (`sleepy wire` is a witness, not a wiretap).
///
/// The shape below is the one the wire spike validated, and every constraint
/// in it was measured:
///
/// - The call is normalized through `new Request(input, init)` so a `Headers`
///   instance or a `Request` object survives; when that constructor throws
///   (a GET with a body), the call goes to the native `fetch` untouched so the
///   page gets the platform's own error.
/// - The response is cloned **synchronously at the top of the fulfillment
///   handler**. Cloning after any `await` fails with "Body is disturbed or
///   locked" on every response the page reads.
/// - Body reads are capped in *bytes* and cancel at the cap: a chunked
///   response carries no `Content-Length`, and an endless one never resolves.
/// - There is no page-side deadline. A headless web view throttles page timers
///   whenever the host is not evaluating JavaScript, so a page-side timeout
///   lies; the host owns the budget (``WireOperation``).
/// - Each exchange posts three correlated messages — `request`, `response`,
///   `body` — because the body arrives late, truncated, or never. The recorder
///   also assembles them by id into its own buffer, which is what the host
///   reads: on a one-shot load nothing is subscribed while the page is
///   talking, so a pushed-only log would be lost.
///
/// Nothing here may throw into page code. Every step is wrapped, and a failure
/// inside the recorder degrades to a missing field, never a broken page.
public enum WireRecorder {
    /// The script-message name the recorder posts on, in
    /// ``InjectedScript/World/page``.
    ///
    /// Each message is JSON text with a `kind` of `request`, `response`,
    /// `body` or `error`, and an `id` correlating the messages of one exchange.
    public static let messageName: String = "sleepyHollowWire"

    /// How many response-body bytes the recorder reads per exchange before it
    /// cancels the read and reports ``FetchExchange/Truncation/size``.
    ///
    /// 256 KiB: large enough for any API response worth asserting on, small
    /// enough that a 50 MB download costs neither memory nor time. The cap is
    /// per invocation — ``LoadOptions/recordingWire(byteCap:)``.
    public static let defaultByteCap: Int = 262_144

    /// The namespaced global the recorder keeps its state under.
    static let stateGlobal: String = "__sleepyHollowWire"

    /// The recorder, ready to install before a load.
    public static func script(
        messageName: String = WireRecorder.messageName,
        byteCap: Int = WireRecorder.defaultByteCap,
    ) -> InjectedScript {
        InjectedScript(
            source: source(messageName: messageName, byteCap: byteCap),
            injectAt: .documentStart,
            world: .page,
        )
    }

    /// The body the host evaluates to ask whether the page is still fetching:
    /// `{ inflight, pendingBodies, lastActivityAt, now }`, or `null` when no
    /// recorder is installed.
    static let activityExpression: String = """
    const state = window.\(stateGlobal);
    if (!state) { return null; }
    let now = 0;
    try { now = Math.round(performance.now()); } catch (ignored) {}
    return {
      inflight: state.inflight,
      pendingBodies: state.pendingBodies,
      lastActivityAt: state.lastActivityAt,
      now: now
    };
    """

    /// The body the host evaluates to read the assembled exchanges, or `null`
    /// when no recorder is installed.
    static let exchangesExpression: String = """
    const state = window.\(stateGlobal);
    if (!state) { return null; }
    return state.exchanges;
    """

    private static func source(messageName: String, byteCap: Int) -> String {
        """
        (function () {
          if (window.\(stateGlobal)) { return; }
          var BYTE_CAP = \(byteCap);
          var nativeFetch = window.fetch;
          if (typeof nativeFetch !== 'function') { return; }

          var state = { nextId: 1, inflight: 0, pendingBodies: 0, lastActivityAt: 0, exchanges: [] };
          Object.defineProperty(window, '\(stateGlobal)', {
            value: state, enumerable: false, configurable: true, writable: false
          });

          function now() {
            try { return Math.round(performance.now()); } catch (ignored) { return 0; }
          }
          function touch() { state.lastActivityAt = now(); }
          function post(message) {
            try {
              window.webkit.messageHandlers.\(messageName).postMessage(JSON.stringify(message));
            } catch (ignored) { /* nobody is subscribed; the buffer still stands */ }
          }
          function headerMap(source) {
            var map = {};
            try {
              source.forEach(function (value, name) {
                map[String(name).toLowerCase()] = String(value);
              });
            } catch (ignored) {}
            return map;
          }
          function byteLength(text) {
            try { return new TextEncoder().encode(text).length; } catch (ignored) { return text.length; }
          }

          async function cappedRead(response) {
            var text = '';
            var bytes = 0;
            var truncated = null;
            try {
              var body = response.body;
              if (!body || typeof body.getReader !== 'function') {
                text = await response.text();
                return { text: text, bytes: byteLength(text), truncated: null };
              }
              var reader = body.getReader();
              var decoder = new TextDecoder('utf-8');
              while (true) {
                var chunk = await reader.read();
                if (chunk.done) { break; }
                bytes += chunk.value.byteLength;
                text += decoder.decode(chunk.value, { stream: true });
                if (bytes >= BYTE_CAP) {
                  truncated = 'size';
                  try { await reader.cancel(); } catch (ignored) {}
                  break;
                }
              }
              try { text += decoder.decode(); } catch (ignored) {}
            } catch (error) {
              return { error: String(error), bytes: bytes };
            }
            // The cap is a byte count and a read returns whole network chunks,
            // so the captured text is sliced back down to it before reporting.
            if (truncated) { text = text.slice(0, BYTE_CAP); }
            return { text: text, bytes: bytes, truncated: truncated };
          }

          async function observe(exchange, requestBody, clone, response) {
            try {
              exchange.requestBody = await requestBody;
              post({
                kind: 'request', id: exchange.id, method: exchange.method, url: exchange.url,
                mode: exchange.mode, requestHeaders: exchange.requestHeaders,
                requestBody: exchange.requestBody
              });
              post({
                kind: 'response', id: exchange.id, status: exchange.status,
                statusText: exchange.statusText, responseType: exchange.responseType,
                redirected: exchange.redirected, responseHeaders: exchange.responseHeaders,
                elapsedMilliseconds: exchange.elapsedMilliseconds
              });
              if (!clone || response.type === 'opaque' || response.type === 'opaqueredirect') {
                post({ kind: 'body', id: exchange.id, skipped: response.type });
                return;
              }
              var body = await cappedRead(clone);
              if (body.error) {
                exchange.error = body.error;
                exchange.responseBodyBytes = body.bytes;
              } else {
                exchange.responseBody = body.text;
                exchange.responseBodyBytes = body.bytes;
                if (body.truncated) { exchange.truncated = body.truncated; }
              }
              post({
                kind: 'body', id: exchange.id, text: exchange.responseBody,
                bytes: body.bytes, truncated: body.truncated || false, error: body.error
              });
            } catch (ignored) {
              /* the recorder failing is a missing field, never a broken page */
            } finally {
              state.pendingBodies -= 1;
              touch();
            }
          }

          window.fetch = function (input, init) {
            var request = null;
            try { request = new Request(input, init); } catch (ignored) { request = null; }
            // `new Request` throws on e.g. a GET with a body: hand the call to
            // the native fetch so the page sees the platform's own error.
            if (!request) { return nativeFetch.call(window, input, init); }

            var exchange = {
              id: state.nextId++,
              method: request.method,
              url: request.url,
              mode: request.mode,
              requestHeaders: headerMap(request.headers),
              responseHeaders: {},
              startedAtMilliseconds: now()
            };
            state.exchanges.push(exchange);
            state.inflight += 1;
            touch();

            // The request body comes off a clone taken before native fetch
            // ever sees the request.
            var requestBody = null;
            try {
              requestBody = request.clone().text().catch(function () { return null; });
            } catch (ignored) { requestBody = null; }

            var result;
            try {
              result = nativeFetch.call(window, request);
            } catch (error) {
              state.inflight -= 1;
              exchange.error = String(error);
              touch();
              throw error;
            }

            var watched = result.then(function (response) {
              // Clone SYNCHRONOUSLY, before any await: after one, the page's
              // own read has disturbed the body.
              var clone = null;
              try { clone = response.clone(); } catch (ignored) { clone = null; }
              state.inflight -= 1;
              state.pendingBodies += 1;
              exchange.status = response.status;
              exchange.statusText = response.statusText;
              exchange.responseType = response.type;
              exchange.redirected = response.redirected;
              exchange.responseHeaders = headerMap(response.headers);
              exchange.elapsedMilliseconds = now() - exchange.startedAtMilliseconds;
              touch();
              return observe(exchange, requestBody, clone, response);
            }, function (error) {
              state.inflight -= 1;
              exchange.error = String(error);
              touch();
              post({ kind: 'error', id: exchange.id, error: exchange.error });
            });
            if (watched && typeof watched.catch === 'function') {
              watched.catch(function () {});
            }

            // The page gets the original promise, untouched.
            return result;
          };
        })();
        """
    }
}
