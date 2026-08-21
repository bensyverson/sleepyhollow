import Foundation
import SleepyHollow
import Testing

/// The outline renderer in isolation: one node per line, two-space indent,
/// quoted names, sorted parenthesized states, and the collapsing rule.
@Suite("AX outline rendering")
struct AXOutlineTests {
    @Test func `a named disabled button renders the flagship line`() {
        let tree = AXNode(
            role: .document,
            name: "Form fixture",
            children: [AXNode(role: .button, name: "Publish", states: [AXState.disabled])],
        )
        #expect(AXOutline.render(tree) == """
        document "Form fixture"
          button "Publish" (disabled)

        """)
    }

    @Test func `depth becomes two spaces of indent per level`() {
        let tree = AXNode(
            role: .main,
            children: [AXNode(role: .list, name: "Things", children: [AXNode(role: .listitem)])],
        )
        #expect(AXOutline.render(tree) == """
        main
          list "Things"
            listitem

        """)
    }

    @Test func `states render sorted by name, with the value last`() {
        let node = AXNode(
            role: .textbox,
            name: "Title",
            value: "Sleepy Hollow ships",
            states: [
                AXState.required,
                AXState(name: .readonly, value: .flag(true)),
                AXState(name: .checked, value: .token("mixed")),
            ],
        )
        #expect(AXOutline.render(node) == "textbox \"Title\" (checked=\"mixed\", readonly, required, value=\"Sleepy Hollow ships\")\n")
    }

    @Test func `a false flag renders as a negation, a number bare, and sorting stays by state name`() {
        let node = AXNode(
            role: .heading,
            name: "Title",
            states: [AXState(name: .level, value: .number(2)), AXState(name: .expanded, value: .flag(false))],
        )
        #expect(AXOutline.render(node) == "heading \"Title\" (not expanded, level=2)\n")
    }

    @Test func `an unnamed generic node collapses and raises its children`() {
        let tree = AXNode(
            role: .main,
            children: [
                AXNode(role: .generic, children: [
                    AXNode(role: .generic, children: [AXNode(role: .button, name: "Deep")]),
                ]),
            ],
        )
        #expect(AXOutline.render(tree) == """
        main
          button "Deep"

        """)
    }

    @Test func `a generic node with a name or a state keeps its line`() {
        let named = AXNode(role: .generic, name: "Labelled wrapper", children: [AXNode(role: .button, name: "Inner")])
        #expect(AXOutline.render(named) == """
        generic "Labelled wrapper"
          button "Inner"

        """)
        let stateful = AXNode(role: .generic, states: [AXState.disabled])
        #expect(AXOutline.render(stateful) == "generic (disabled)\n")
    }

    @Test func `a name with quotes, newlines or runs of space is normalized`() {
        let node = AXNode(role: .button, name: "  Say \"hi\"\n  now  ")
        #expect(AXOutline.render(node) == "button \"Say \\\"hi\\\" now\"\n")
    }

    @Test func `an empty name is omitted rather than rendered as empty quotes`() {
        #expect(AXOutline.render(AXNode(role: .button, name: "")) == "button\n")
    }

    @Test func `the outline is materially terser than the JSON encoding`() throws {
        let tree = AXNode(role: .document, name: "Page", children: (1 ... 12).map { index in
            AXNode(role: .button, name: "Button \(index)", states: [AXState.disabled])
        })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json: Data = try encoder.encode(tree)
        let outline = Data(AXOutline.render(tree).utf8)
        #expect(outline.count * 3 < json.count)
    }
}
