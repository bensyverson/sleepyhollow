import Foundation

/// `sleepy style`: computed CSS values for the **first** element a selector
/// matches.
///
/// First-match, not all-matches: `style` answers "did the reset apply?" for
/// the one thing under test, the same singular framing `getComputedStyle`
/// itself takes (one element in, one declaration block out). An assertion
/// across every match is already `query`'s job — `--exists`/`--count` plus
/// reading each element's own facts — so `style` does not duplicate it. A
/// selector matching nothing is the operation's one clean-negative case:
/// ``StyleResult/matched`` is `false`, which the CLI maps to exit 1, the
/// same contract `find` uses for "the page doesn't have this."
public struct StyleOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = StyleResult

    /// The wire identifier.
    public static let kind: String = "style"

    /// The CSS selector; computed style is read from its first match.
    public var selector: String

    /// The computed properties to read, kebab-case
    /// (`getPropertyValue`'s own spelling, e.g. `"background-color"`).
    public var properties: [String]

    /// Creates the operation.
    public init(selector: String, properties: [String]) {
        self.selector = selector
        self.properties = properties
    }

    /// Reads the requested properties' computed values from the first match.
    @MainActor
    public func execute(on host: PageHost) async throws -> StyleResult {
        let text: String
        do {
            text = try await host.evaluate(
                Self.script,
                arguments: ["selector": selector, "properties": properties],
            )
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
                message: "The style result did not transport as UTF-8 JSON text.",
                nextMove: "Retry; this indicates a WebKit transport fault, not a page fault.",
            )
        }
        return try JSONDecoder().decode(StyleResult.self, from: data)
    }

    /// Reads computed values for `properties` from `selector`'s first match,
    /// page-side.
    private static let script: String = """
    const el = document.querySelector(selector);
    if (!el) {
      return { matched: false, values: {} };
    }
    const style = getComputedStyle(el);
    const values = {};
    for (const prop of properties) {
      values[prop] = style.getPropertyValue(prop);
    }
    return { matched: true, values };
    """
}
