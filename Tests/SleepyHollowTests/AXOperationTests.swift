import Foundation
import SleepyHollow
import Testing
import TestSupport

/// The operation itself against the shared form fixture: the flagship query,
/// the round trip through JSON, and the terseness the outline exists for.
@Suite("AX operation")
struct AXOperationTests {
    @Test func `the operation's wire kind is stable`() {
        #expect(AXOperation.kind == "ax")
    }

    @Test
    @MainActor
    func `the flagship line appears verbatim in the form fixture's outline`() async throws {
        let tree = try await AXFixtureTree.tree(of: "form.html")
        let outline: String = AXOutline.render(tree)
        #expect(outline.contains("button \"Publish\" (disabled)\n"))
        #expect(outline.contains("button \"Save\"\n"))
    }

    @Test
    @MainActor
    func `labelled form controls take their label text as name`() async throws {
        let tree = try await AXFixtureTree.tree(of: "form.html")
        #expect(tree.first(role: .textbox, named: "Title") != nil)
        #expect(tree.first(role: .textbox, named: "Body") != nil)
        #expect(tree.first(role: .form) != nil)
    }

    @Test
    @MainActor
    func `the JSON encoding round-trips to the same tree the outline renders`() async throws {
        let tree = try await AXFixtureTree.tree(of: "form.html")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data = try encoder.encode(tree)
        let decoded = try JSONDecoder().decode(AXNode.self, from: data)
        #expect(decoded == tree)
        #expect(AXOutline.render(decoded) == AXOutline.render(tree))
    }

    @Test
    @MainActor
    func `the outline is materially terser than the JSON tree`() async throws {
        let tree = try await AXFixtureTree.tree(of: "form.html")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json: Data = try encoder.encode(tree)
        let outline = Data(AXOutline.render(tree).utf8)
        #expect(outline.count * 3 < json.count)
    }

    @Test
    @MainActor
    func `the computation leaves no globals behind in the page's world`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "form.html", relativeTo: base)!)
            let globals = "return Object.getOwnPropertyNames(window).sort();"
            let before: String = try await host.evaluate(globals, in: .page)
            _ = try await host.execute(AXOperation())
            let after: String = try await host.evaluate(globals, in: .page)
            #expect(before == after)
        }
    }
}
