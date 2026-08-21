import Foundation

/// The `--wait-for <selector>` instrumentation: a document-start isolated-world
/// script that posts the moment the selector first matches.
///
/// **Push, with a host-side backstop.** The observer exists so a match is
/// reported the instant the DOM changes, rather than on the next poll. It
/// cannot be the only mechanism: a selector can start matching with no
/// mutation record behind it at all — `#agree:checked` flips when page script
/// assigns the IDL property, which never touches the content attribute — so
/// ``WaitEngine`` also re-checks on its own clock. The observer buys latency;
/// the backstop buys the guarantee.
///
/// The script runs in the isolated world (the DOM is shared; page globals are
/// not) and posts on ``WaitEngine/messageName``. It checks once at
/// installation and again at `DOMContentLoaded` and `load`, so content that
/// was already present before observation started still settles the wait.
enum SelectorWatch {
    /// The document-start isolated-world script for `selector`.
    static func script(selector: String, messageName: String) -> InjectedScript {
        InjectedScript(
            source: source(selector: selector, messageName: messageName),
            injectAt: .documentStart,
            world: .isolated,
        )
    }

    /// The body ``PageHost/evaluate(_:arguments:in:)`` runs to check the
    /// selector host-side, with `sleepySelector` in scope.
    ///
    /// Returns a ``WaitEngine/Probe``: `truthy` when at least one element
    /// matches, `failure` when the selector itself is not valid CSS — which is
    /// a usage error the moment it is seen, not something a longer budget
    /// fixes.
    static let checkBody: String = """
    try {
      return { truthy: document.querySelector(sleepySelector) !== null };
    } catch (error) {
      return { truthy: false, failure: String(error) };
    }
    """

    private static func source(selector: String, messageName: String) -> String {
        """
        (function () {
          var selector = \(literal(selector));
          var seen = false;
          function post() {
            try {
              window.webkit.messageHandlers.\(messageName).postMessage('matched');
            } catch (ignored) { /* the host polls too; a lost post is not a lost wait */ }
          }
          function check() {
            if (seen) { return; }
            var found = null;
            try {
              found = document.querySelector(selector);
            } catch (error) {
              // An invalid selector never matches; the host reports it.
              seen = true;
              observer.disconnect();
              return;
            }
            if (found) {
              seen = true;
              observer.disconnect();
              post();
            }
          }
          var observer = new MutationObserver(check);
          observer.observe(document, {
            childList: true, subtree: true, attributes: true, characterData: true
          });
          document.addEventListener('DOMContentLoaded', check);
          window.addEventListener('load', check);
          check();
        })();
        """
    }

    /// `text` as a JavaScript string literal.
    ///
    /// JSON's string escaping is a subset of JavaScript's, with one gap: the
    /// line separators U+2028/U+2029 are legal raw inside JSON strings, so
    /// they are escaped by hand.
    private static func literal(_ text: String) -> String {
        var escaped = ""
        for character in text.unicodeScalars {
            switch character {
            case "\"": escaped += "\\\""
            case "\\": escaped += "\\\\"
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            case "\u{2028}", "\u{2029}":
                escaped += String(format: "\\u%04X", character.value)
            default:
                escaped.unicodeScalars.append(character)
            }
        }
        return "\"\(escaped)\""
    }
}
