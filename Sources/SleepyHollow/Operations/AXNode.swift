/// One node of the page's computed accessibility tree: a role, an accessible
/// name, a value, the states that apply, and the nodes it owns.
///
/// This is *the page's semantics per WAI-ARIA and AccName*, computed in the
/// page by ``AXOperation``'s injected script — not a copy of WebKit's internal
/// accessibility tree, which a headless CLI cannot reach (see
/// `project/2026-08-20-ax-spike.md`). The spec is the contract pages are
/// written against, so it is the contract this tree reports.
///
/// ```swift
/// let tree = try await host.execute(AXOperation())
/// print(AXOutline.render(tree))   // button "Publish" (disabled)
/// ```
public struct AXNode: Friendly {
    /// The computed role.
    public var role: AXRole

    /// The accessible name, when the element has one.
    public var name: String?

    /// The element's value: a text field's contents, a slider's position, a
    /// select's chosen option.
    public var value: String?

    /// The states that apply, sorted by ``AXState/Name``.
    public var states: [AXState]

    /// The nodes this one owns, in document order.
    public var children: [AXNode]

    /// Creates a node.
    public init(
        role: AXRole,
        name: String? = nil,
        value: String? = nil,
        states: [AXState] = [],
        children: [AXNode] = [],
    ) {
        self.role = role
        self.name = name
        self.value = value
        self.states = states
        self.children = children
    }

    /// This node and every descendant, in document (preorder) order — the
    /// shape queries want: `tree.flattened.filter { $0.role == .button }`.
    public var flattened: [AXNode] {
        var collected: [AXNode] = [self]
        for child in children {
            collected.append(contentsOf: child.flattened)
        }
        return collected
    }
}
