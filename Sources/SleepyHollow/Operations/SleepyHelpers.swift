import Foundation

/// The `window.sleepy` helper library: page measurements this tool owns,
/// written once in JavaScript and reachable three ways.
///
/// `sleepy contrast` and `sleepy overflow` are thin callers over
/// `window.sleepy.contrast()` and `window.sleepy.overflow()`; an agent
/// composing its own check calls the same functions through `sleepy eval`,
/// which defaults to the page world for exactly this reason. One
/// implementation, so a verb and an agent's own loop can never disagree.
///
/// Like ``AXScript`` it is a Swift constant rather than a bundle resource, so
/// the library stays resource-free. Unlike it, this one is *installed* — a
/// document-end user script in ``InjectedScript/World/page``, because a
/// namespace an agent can reach from `eval` has to be a page global — and its
/// parts are assembled inside one IIFE, so the only name it adds to the page
/// is `sleepy`.
///
/// Every function is defensive: a page can make any DOM accessor throw, and a
/// check verb that throws is a check verb that lies.
public enum SleepyHelpers {
    /// The version stamped on the namespace, so a re-injected copy (a
    /// same-document navigation, a second install) leaves the first alone.
    static let version: Int = 1

    /// The whole library, in the order the parts depend on each other, wrapped
    /// in the IIFE that publishes exactly one global.
    static let source: String = [prologue, colors, elements, contrast, overflow, epilogue]
        .joined(separator: "\n\n")

    /// The user script that installs the library on every page.
    ///
    /// Document *end*: the functions measure rendered geometry, so there is
    /// nothing for them to do before the document has one, and installing late
    /// keeps the library out of the way of anything the page does at start.
    public static let script: InjectedScript = .init(
        source: source,
        injectAt: .documentEnd,
        world: .page,
    )

    /// Opens the IIFE and refuses to overwrite a namespace already installed.
    private static let prologue: String = """
    (function () {
      'use strict';
      if (window.sleepy && window.sleepy.version === \(version)) { return; }
    """

    /// Publishes the namespace and closes the IIFE.
    private static let epilogue: String = """
      window.sleepy = {
        version: \(version),
        rect: sleepyRect,
        effectiveBackground: sleepyEffectiveBackground,
        contrast: sleepyContrast,
        overflow: sleepyOverflow,
      };
    })();
    """

    /// Calls one library function in `host`'s page and decodes its answer.
    ///
    /// - Parameters:
    ///   - function: the name on the `sleepy` namespace.
    ///   - options: the single options object the function takes; must be
    ///     JSON-serializable.
    ///   - type: what the answer decodes to.
    ///   - host: the page to ask.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` when
    ///   the library is missing from the page, the page cannot run it, or the
    ///   answer is one this build cannot read.
    @MainActor
    static func call<Value: Decodable>(
        _ function: String,
        options: [String: Any],
        as type: Value.Type,
        on host: PageHost,
    ) async throws -> Value {
        let body = """
        if (!window.sleepy || typeof window.sleepy.\(function) !== 'function') {
          throw new Error('the sleepy helper library is not installed in this page');
        }
        return window.sleepy.\(function)(options);
        """
        let json: String
        do {
            json = try await host.evaluate(body, arguments: ["options": options], in: .page)
        } catch let error as SleepyError {
            throw error
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "The page could not run the '\(function)' check: \(error.localizedDescription)",
                nextMove: "Retry against a settled page — a frame that navigates mid-read cannot answer.",
            )
        }
        do {
            return try JSONDecoder().decode(type, from: Data(json.utf8))
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "The '\(function)' check answered with a result this build can't read.",
                nextMove: "This is a bug in SleepyHollow — please report the page that caused it.",
            )
        }
    }
}
