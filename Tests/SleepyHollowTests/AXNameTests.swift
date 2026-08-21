import Foundation
import SleepyHollow
import Testing

/// AccName 1.2 precedence against a real page: labelledby, label, the host
/// language's own mechanisms, then name from content.
@Suite("AX accessible names")
struct AXNameTests {
    @Test
    @MainActor
    func `aria-labelledby beats aria-label beats name from content`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-names.html")
        let buttons: [String] = tree.flattened.filter { $0.role == .button }.compactMap(\.name)
        #expect(buttons.contains("Delete file"))
        #expect(buttons.contains("Label attribute"))
        #expect(buttons.contains("Content text"))
        #expect(!buttons.contains("Content text Label attribute"))
    }

    @Test
    @MainActor
    func `native label mechanisms name their controls`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-names.html")
        let names: [String] = tree.names
        #expect(names.contains("Explicit label"))
        #expect(names.contains("Wrapping label"))
        #expect(names.contains("Placeholder only"))
        #expect(names.contains("Title only"))
        #expect(names.contains("Wins over placeholder"))
        #expect(!names.contains("Ignored placeholder"))
    }

    @Test
    @MainActor
    func `alt, legend, figcaption and caption name their elements`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-names.html")
        #expect(tree.first(role: .image, named: "A single pixel") != nil)
        #expect(tree.first(role: .group, named: "Legend name") != nil)
        #expect(tree.first(role: .figure, named: "Figure caption") != nil)
        #expect(tree.first(role: .table, named: "Table caption") != nil)
        #expect(tree.first(role: .link, named: "A link") != nil)
    }

    @Test
    @MainActor
    func `an empty alt makes the image presentational, so it disappears`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-names.html")
        let images: [AXNode] = tree.flattened.filter { $0.role == .image }
        #expect(images.count == 1)
        #expect(images.first?.name == "A single pixel")
    }

    @Test
    @MainActor
    func `headings take a name from content, paragraphs and list items do not`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-names.html")
        #expect(tree.first(role: .heading, named: "Heading text") != nil)

        let paragraph: AXNode = try #require(tree.flattened.first {
            $0.role == .paragraph && $0.flattened.contains { $0.name == "Paragraph text" }
        })
        #expect(paragraph.name == nil)

        let item: AXNode = try #require(tree.first(role: .listitem))
        #expect(item.name == nil)
        #expect(item.flattened.contains { $0.role == .text && $0.name == "List item text" })
    }

    @Test
    @MainActor
    func `generated content joins the name`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-names.html")
        #expect(tree.first(role: .button, named: "Go home") != nil)
    }

    @Test
    @MainActor
    func `text consumed as a label is not repeated as a text node`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-names.html")
        let texts: [String] = tree.flattened.filter { $0.role == .text }.compactMap(\.name)
        #expect(!texts.contains("Explicit label"))
        #expect(!texts.contains("Wrapping label"))
        #expect(!texts.contains("Heading text"))
    }
}
