/// One node of the serialized DOM tree ``DOMOperation`` returns for
/// `--format json`.
///
/// Two kinds share one type rather than an enum with associated values,
/// because the wire shape — `kind`, `tag`, `attributes`, `text`, `children` —
/// is exactly what the vision doc promises ("a tree of typed nodes: tag,
/// attributes, children, text"), and a flat struct keeps that shape visible
/// in the JSON an agent reads, instead of hiding it behind Codable's
/// enum-with-payload encoding.
///
/// Built by walking `document.documentElement` in JavaScript
/// (``DOMOperation``): comment nodes are omitted (no product need), and
/// text nodes that are pure formatting whitespace between tags are omitted
/// too — the same significant-whitespace judgment call HTML pretty-printers
/// make, so the tree reads as content, not indentation noise. Any text node
/// with non-whitespace content is kept **verbatim**, not trimmed.
public struct DOMNode: Friendly {
    /// Which shape this node is: an element with a tag and attributes, or a
    /// text run.
    public enum Kind: String, Friendly {
        /// An element node — see ``tag`` and ``attributes``.
        case element
        /// A text node — see ``text``.
        case text
    }

    /// Which shape this node is.
    public var kind: Kind

    /// The lowercased tag name. `nil` for ``Kind/text`` nodes.
    public var tag: String?

    /// The element's attributes, name to value. Empty for ``Kind/text`` nodes.
    public var attributes: [String: String]

    /// The verbatim text content. `nil` for ``Kind/element`` nodes.
    public var text: String?

    /// Child nodes, in document order. Always empty for ``Kind/text`` nodes.
    public var children: [DOMNode]

    /// Creates a DOM tree node.
    public init(
        kind: Kind,
        tag: String? = nil,
        attributes: [String: String] = [:],
        text: String? = nil,
        children: [DOMNode] = [],
    ) {
        self.kind = kind
        self.tag = tag
        self.attributes = attributes
        self.text = text
        self.children = children
    }
}
