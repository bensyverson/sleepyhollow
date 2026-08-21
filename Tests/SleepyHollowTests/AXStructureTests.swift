import Foundation
import SleepyHollow
import Testing

/// The shape of the tree: landmarks, pruning, and the presentation-role rules.
@Suite("AX tree structure")
struct AXStructureTests {
    @Test
    @MainActor
    func `landmarks and headings carry their roles and levels`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-structure.html")
        #expect(tree.role == .document)
        #expect(tree.name == "AX structure fixture")
        #expect(tree.first(role: .banner) != nil)
        #expect(tree.first(role: .navigation, named: "Primary") != nil)
        #expect(tree.first(role: .main) != nil)
        #expect(tree.first(role: .contentinfo) != nil)
        #expect(tree.first(role: .region, named: "Named region") != nil)

        let heading: AXNode = try #require(tree.first(role: .heading, named: "Structure"))
        #expect(heading.states.contains(AXState(name: .level, value: .number(1))))
    }

    @Test
    @MainActor
    func `an unnamed section is generic, not a region`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-structure.html")
        let regions: [AXNode] = tree.flattened.filter { $0.role == .region }
        #expect(regions.count == 1)
        #expect(tree.flattened.contains { $0.role == .generic })
    }

    @Test
    @MainActor
    func `aria-hidden, display none and visibility hidden subtrees are absent`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-structure.html")
        let names: [String] = tree.names
        #expect(!names.contains("Hidden by aria"))
        #expect(!names.contains("Hidden by display"))
        #expect(!names.contains("Hidden by visibility"))
        #expect(names.contains("Screen reader note"))
    }

    @Test
    @MainActor
    func `role=presentation strips the whole table skeleton it owns`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-structure.html")
        #expect(tree.names.contains("Inside layout table"))

        let tables: [AXNode] = tree.flattened.filter { $0.role == .table }
        #expect(tables.count == 1)
        #expect(tables.first?.name == "Data table")

        let cells: [String] = tree.flattened.filter { $0.role == .cell }.compactMap(\.name)
        #expect(cells == ["Body cell"])
    }

    @Test
    @MainActor
    func `a real table keeps rows, row groups and header cells`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-structure.html")
        let table: AXNode = try #require(tree.first(role: .table, named: "Data table"))
        #expect(table.first(role: .rowgroup) != nil)
        #expect(table.flattened.count(where: { $0.role == .row }) == 2)
        #expect(table.first(role: .columnheader, named: "Header cell") != nil)
    }

    @Test
    @MainActor
    func `role=none drops only the wrapper it is on`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-structure.html")
        #expect(tree.first(role: .button, named: "Kept through none") != nil)
        #expect(!tree.flattened.contains { $0.role == .presentation })
    }

    @Test
    @MainActor
    func `unnamed wrappers collapse in the outline but survive in the tree`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-structure.html")
        #expect(tree.first(role: .button, named: "Deeply wrapped") != nil)

        let outline: String = AXOutline.render(tree)
        let line: String = try #require(outline.split(separator: "\n").first { $0.contains("Deeply wrapped") }.map(String.init))
        let mainLine: String = try #require(outline.split(separator: "\n").first { $0.hasSuffix("main") }.map(String.init))
        #expect(indent(of: line) == indent(of: mainLine) + 2)
    }

    @Test
    @MainActor
    func `the list of links keeps its list and item structure`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-structure.html")
        let list: AXNode = try #require(tree.first(role: .list))
        #expect(list.flattened.count(where: { $0.role == .listitem }) == 2)
        #expect(list.first(role: .link, named: "Alpha") != nil)
    }

    private func indent(of line: String) -> Int {
        line.prefix { $0 == " " }.count
    }
}
