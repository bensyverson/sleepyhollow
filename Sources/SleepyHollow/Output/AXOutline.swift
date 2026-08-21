/// Renders an ``AXNode`` tree as the indented outline `sleepy ax` emits by
/// default — the cheapest faithful read of a page's semantics.
///
/// One node per line, two spaces of indent per level, the role first, then the
/// accessible name in quotes when there is one, then the states in
/// parentheses:
///
/// ```text
/// document "Publish an article"
///   form
///     textbox "Article title" (required, value="Sleepy Hollow ships")
///     checkbox "Notify subscribers" (checked)
///     button "Publish" (disabled)
/// ```
///
/// **What is collapsed.** A node whose role is ``AXRole/generic`` and which
/// carries no name, no value and no states says nothing an agent can act on —
/// it is a `div` — so its line is omitted and its children rise to its depth.
/// Nothing else is ever dropped: a named or stateful generic node keeps its
/// line, and `--format json` collapses nothing at all.
///
/// **What is quoted.** Names and values are whitespace-collapsed and quoted,
/// with `"` and `\` escaped, so one node is always exactly one line and a
/// grep for `button "Publish"` cannot be defeated by the page's formatting.
public enum AXOutline {
    /// The two spaces one level of depth adds.
    private static let indent: String = "  "

    /// Renders `root` and its descendants, one node per line, with a trailing
    /// newline. A tree that collapses to nothing renders as the empty string.
    public static func render(_ root: AXNode) -> String {
        var lines: [String] = []
        append(root, depth: 0, to: &lines)
        guard !lines.isEmpty else { return "" }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func append(_ node: AXNode, depth: Int, to lines: inout [String]) {
        guard !isCollapsed(node) else {
            for child in node.children {
                append(child, depth: depth, to: &lines)
            }
            return
        }
        lines.append(line(for: node, depth: depth))
        for child in node.children {
            append(child, depth: depth + 1, to: &lines)
        }
    }

    /// A `div` by another name: nothing to say, so it says nothing.
    private static func isCollapsed(_ node: AXNode) -> Bool {
        node.role == .generic
            && normalized(node.name).isEmpty
            && normalized(node.value).isEmpty
            && node.states.isEmpty
    }

    private static func line(for node: AXNode, depth: Int) -> String {
        var line = String(repeating: indent, count: depth) + node.role.rawValue
        let name: String = normalized(node.name)
        if !name.isEmpty {
            line += " \(quoted(name))"
        }
        let annotations: [String] = annotations(of: node)
        if !annotations.isEmpty {
            line += " (\(annotations.joined(separator: ", ")))"
        }
        return line
    }

    /// The parenthesized part: states sorted by name, then the value — last,
    /// because a long value should never bury the flags in front of it.
    private static func annotations(of node: AXNode) -> [String] {
        var annotations: [String] = node.states
            .sorted { $0.name < $1.name }
            .map(token(for:))
        let value: String = normalized(node.value)
        if !value.isEmpty {
            annotations.append("value=\(quoted(value))")
        }
        return annotations
    }

    private static func token(for state: AXState) -> String {
        switch state.value {
        case let .flag(flag):
            flag ? state.name.rawValue : "not \(state.name.rawValue)"
        case let .token(token):
            "\(state.name.rawValue)=\(quoted(token))"
        case let .number(number):
            "\(state.name.rawValue)=\(number)"
        }
    }

    private static func normalized(_ text: String?) -> String {
        guard let text else { return "" }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func quoted(_ text: String) -> String {
        let escaped: String = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
