import Foundation

/// `sleepy dom`: the page's serialized DOM, its native form (HTML) or a
/// typed tree (`--format json`).
///
/// Reads `document.documentElement`, not `document`: the doctype is
/// serialized separately and prefixed onto ``DOMResult/html`` (the
/// vision doc's "doctype included"), while ``DOMResult/tree`` roots at the
/// `<html>` element the way an agent selects into the page.
public struct DOMOperation: ExecutablePageOperation {
    /// This operation's typed result.
    public typealias Output = DOMResult

    /// The wire identifier.
    public static let kind: String = "dom"

    /// Creates the operation. `dom` takes no arguments — its input is the
    /// page a source and load options already resolved.
    public init() {}

    /// Serializes the page's DOM in both forms.
    @MainActor
    public func execute(on host: PageHost) async throws -> DOMResult {
        let text: String
        do {
            text = try await host.evaluate(Self.script)
        } catch {
            throw SleepyError(
                kind: .environment,
                message: "Could not read the DOM: \(error.localizedDescription)",
                nextMove: "Check that the page finished loading.",
            )
        }
        guard let data = text.data(using: .utf8) else {
            throw SleepyError(
                kind: .environment,
                message: "The page's DOM did not transport as UTF-8 JSON text.",
                nextMove: "Retry; this indicates a WebKit transport fault, not a page fault.",
            )
        }
        return try JSONDecoder().decode(DOMResult.self, from: data)
    }

    /// Builds ``DOMResult`` page-side: the doctype plus outer HTML, and a
    /// recursive walk of element and (non-whitespace-only) text nodes.
    private static let script: String = """
    function serializeDoctype() {
      const dt = document.doctype;
      if (!dt) { return ''; }
      let s = '<!DOCTYPE ' + dt.name;
      if (dt.publicId) {
        s += ' PUBLIC "' + dt.publicId + '"';
        if (dt.systemId) { s += ' "' + dt.systemId + '"'; }
      } else if (dt.systemId) {
        s += ' SYSTEM "' + dt.systemId + '"';
      }
      return s + '>';
    }

    function buildTree(node) {
      if (node.nodeType === Node.TEXT_NODE) {
        if (node.nodeValue.trim() === '') { return null; }
        return { kind: 'text', attributes: {}, text: node.nodeValue, children: [] };
      }
      if (node.nodeType !== Node.ELEMENT_NODE) { return null; }
      const attributes = {};
      for (const attr of Array.from(node.attributes)) {
        attributes[attr.name] = attr.value;
      }
      const children = [];
      for (const child of Array.from(node.childNodes)) {
        const built = buildTree(child);
        if (built) { children.push(built); }
      }
      return { kind: 'element', tag: node.tagName.toLowerCase(), attributes, children };
    }

    const doctype = serializeDoctype();
    const html = (doctype ? doctype + '\\n' : '') + document.documentElement.outerHTML;
    const tree = buildTree(document.documentElement);
    return { html, tree };
    """
}
