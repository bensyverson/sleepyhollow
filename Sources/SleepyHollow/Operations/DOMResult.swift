/// What ``DOMOperation`` returns: the page's markup and its tree, computed
/// together in one round-trip to the page.
///
/// Both forms are always present — the operation does not know which one the
/// CLI will print — so a session round-trip pays for one evaluation, not two.
public struct DOMResult: Friendly {
    /// The page's native markup: the serialized doctype (when present)
    /// followed by `document.documentElement.outerHTML`. This is `dom`'s
    /// default output.
    public var html: String

    /// The same document as a ``DOMNode`` tree — `dom`'s `--format json`.
    public var tree: DOMNode

    /// Creates a DOM read result.
    public init(html: String, tree: DOMNode) {
        self.html = html
        self.tree = tree
    }
}
