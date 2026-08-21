import Foundation

/// `sleepy query`: every element matching a CSS selector, as ``ElementFact``s.
///
/// Always computes the full fact set — text, attributes, geometry,
/// visibility — for every match; `--exists`/`--count` (the CLI's assertion
/// flags) are answered by counting the result client-side rather than by a
/// separate operation mode, so there is exactly one code path to trust.
/// A selector matching nothing is not an error: it returns an empty array,
/// the same honest "zero facts" answer as any other query with no matches.
public struct QueryOperation: ExecutablePageOperation {
    /// This operation's typed result: one fact per matched element, in
    /// document order.
    public typealias Output = [ElementFact]

    /// The wire identifier.
    public static let kind: String = "query"

    /// The CSS selector to match, as `querySelectorAll` would take it.
    public var selector: String

    /// Creates the operation.
    public init(selector: String) {
        self.selector = selector
    }

    /// Matches `selector` and reports facts for every element found.
    @MainActor
    public func execute(on host: PageHost) async throws -> [ElementFact] {
        let text: String
        do {
            text = try await host.evaluate(Self.script, arguments: ["selector": selector])
        } catch {
            throw SleepyError(
                kind: .usage,
                message: "'\(selector)' could not be evaluated as a CSS selector: \(error.localizedDescription)",
                nextMove: "Check the selector syntax.",
            )
        }
        guard let data = text.data(using: .utf8) else {
            throw SleepyError(
                kind: .environment,
                message: "The query result did not transport as UTF-8 JSON text.",
                nextMove: "Retry; this indicates a WebKit transport fault, not a page fault.",
            )
        }
        return try JSONDecoder().decode([ElementFact].self, from: data)
    }

    /// Builds one fact object per match, page-side.
    private static let script: String = """
    const nodes = Array.from(document.querySelectorAll(selector));
    function factFor(el) {
      const rect = el.getBoundingClientRect();
      const style = getComputedStyle(el);
      const attributes = {};
      for (const attr of Array.from(el.attributes)) {
        attributes[attr.name] = attr.value;
      }
      const opacity = parseFloat(style.opacity);
      const visible = style.display !== 'none'
        && style.visibility !== 'hidden'
        && style.visibility !== 'collapse'
        && !(Number.isFinite(opacity) && opacity <= 0)
        && (rect.width > 0 || rect.height > 0);
      return {
        tagName: el.tagName.toLowerCase(),
        text: (el.innerText || '').trim(),
        attributes,
        geometry: { x: rect.x, y: rect.y, width: rect.width, height: rect.height },
        visible,
      };
    }
    return nodes.map(factFor);
    """
}
