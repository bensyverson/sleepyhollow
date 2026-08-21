import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `DOMOperation`: the page's markup, and the same document as a typed tree.
@Suite("DOMOperation")
struct DOMOperationTests {
    @Test
    @MainActor
    func `html contains the literal markup, doctype included`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            let result = try await host.execute(DOMOperation())
            #expect(result.html.hasPrefix("<!DOCTYPE html>"))
            #expect(result.html.contains(#"<p id="greeting">The quick brown fox jumps over the lazy dog.</p>"#))
        }
    }

    @Test
    @MainActor
    func `json tree decodes nested elements, attributes, and text`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "dom-nested.html", relativeTo: base)!)
            let result = try await host.execute(DOMOperation())
            let tree = result.tree
            #expect(tree.kind == .element)
            #expect(tree.tag == "html")

            let section = try #require(Self.firstNode(in: tree) { $0.tag == "section" })
            #expect(section.attributes["class"] == "intro")
            #expect(section.attributes["data-index"] == "1")

            let em = try #require(Self.firstNode(in: tree) { $0.tag == "em" })
            #expect(em.children.first?.kind == .text)
            #expect(em.children.first?.text == "level")

            let listItems = Self.nodes(in: tree) { $0.tag == "li" }
            let itemTexts = listItems.map { $0.children.first?.text }
            #expect(itemTexts == ["One", "Two"])
        }
    }

    @Test
    @MainActor
    func `pure-whitespace text nodes between tags are omitted`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "dom-nested.html", relativeTo: base)!)
            let result = try await host.execute(DOMOperation())
            let ul = try #require(Self.firstNode(in: result.tree) { $0.tag == "ul" })
            // Two <li> children only — the indentation whitespace between them
            // in the fixture's source is not a child node in the tree.
            #expect(ul.children.count == 2)
            #expect(ul.children.allSatisfy { $0.kind == .element })
        }
    }

    /// Depth-first search for the first node matching `predicate`.
    private static func firstNode(in node: DOMNode, where predicate: (DOMNode) -> Bool) -> DOMNode? {
        if predicate(node) { return node }
        for child in node.children {
            if let found = firstNode(in: child, where: predicate) { return found }
        }
        return nil
    }

    /// Depth-first collection of every node matching `predicate`, in
    /// document order.
    private static func nodes(in node: DOMNode, where predicate: (DOMNode) -> Bool) -> [DOMNode] {
        var found: [DOMNode] = []
        if predicate(node) { found.append(node) }
        for child in node.children {
            found.append(contentsOf: nodes(in: child, where: predicate))
        }
        return found
    }
}
