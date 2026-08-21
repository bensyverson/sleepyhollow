import Foundation
import SleepyHollow
import Testing

/// States: disabled (native and ARIA), tri-state checked, expanded, pressed,
/// selected, required, readonly, current, level, and values.
@Suite("AX states")
struct AXStateTests {
    @Test
    @MainActor
    func `disabled comes from the native property, an ancestor fieldset, and aria-disabled`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-states.html")
        for name in ["Inherited disabled", "Native disabled", "Aria disabled"] {
            let node: AXNode = try #require(tree.first(role: .button, named: name))
            #expect(node.states.contains(AXState.disabled), "\(name) should be disabled")
        }
    }

    @Test
    @MainActor
    func `checked is tri-state and reports both true and false`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-states.html")
        let checked: AXNode = try #require(tree.first(role: .checkbox, named: "Native checked"))
        #expect(checked.states.contains(AXState(name: .checked, value: .flag(true))))

        let unchecked: AXNode = try #require(tree.first(role: .checkbox, named: "Native unchecked"))
        #expect(unchecked.states.contains(AXState(name: .checked, value: .flag(false))))

        let mixed: AXNode = try #require(tree.first(role: .checkbox, named: "Mixed checkbox"))
        #expect(mixed.states.contains(AXState(name: .checked, value: .token("mixed"))))

        let switched: AXNode = try #require(tree.first(role: .switch, named: "Switch"))
        #expect(switched.states.contains(AXState(name: .checked, value: .flag(true))))
    }

    @Test
    @MainActor
    func `expanded, pressed and current carry their ARIA values`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-states.html")
        let collapsed: AXNode = try #require(tree.first(role: .button, named: "Expandable"))
        #expect(collapsed.states.contains(AXState(name: .expanded, value: .flag(false))))

        let pressed: AXNode = try #require(tree.first(role: .button, named: "Pressed"))
        #expect(pressed.states.contains(AXState(name: .pressed, value: .flag(true))))

        let current: AXNode = try #require(tree.first(role: .link, named: "Current page"))
        #expect(current.states.contains(AXState(name: .current, value: .token("page"))))
    }

    @Test
    @MainActor
    func `required and readonly come from the native properties`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-states.html")
        let required: AXNode = try #require(tree.first(role: .textbox, named: "Required field"))
        #expect(required.states.contains(AXState.required))

        let readonly: AXNode = try #require(tree.first(role: .textbox, named: "Read only field"))
        #expect(readonly.states.contains(AXState.readonly))
        #expect(readonly.value == "Read only value")
    }

    @Test
    @MainActor
    func `values come from text fields, progress bars, sliders and selects`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-states.html")
        #expect(tree.first(role: .textbox, named: "Filled field")?.value == "Typed text")
        #expect(tree.first(role: .progressbar, named: "Progress")?.value == "42")
        #expect(tree.first(role: .slider, named: "Slider")?.value == "7")

        let chooser: AXNode = try #require(tree.first(role: .combobox, named: "Chooser"))
        #expect(chooser.value == "Alpha")
    }

    @Test
    @MainActor
    func `a collapsed select lists only its chosen option, a listbox lists them all`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-states.html")

        let chooser: AXNode = try #require(tree.first(role: .combobox, named: "Chooser"))
        #expect(chooser.children.map(\.name) == ["Alpha"])
        #expect(chooser.first(role: .option, named: "Alpha")?.states
            .contains(AXState(name: .selected, value: .flag(true))) == true)

        let picker: AXNode = try #require(tree.first(role: .listbox, named: "Picker"))
        #expect(picker.children.map(\.name) == ["Ex", "Why"])
        #expect(picker.first(role: .option, named: "Why")?.states
            .contains(AXState(name: .selected, value: .flag(false))) == true)
    }

    @Test
    @MainActor
    func `heading level is a state`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-states.html")
        let heading: AXNode = try #require(tree.first(role: .heading, named: "A third-level heading"))
        #expect(heading.states.contains(AXState(name: .level, value: .number(3))))
    }

    @Test
    @MainActor
    func `states arrive sorted by name`() async throws {
        let tree = try await AXFixtureTree.tree(of: "ax-states.html")
        for node in tree.flattened {
            #expect(node.states.map(\.name.rawValue) == node.states.map(\.name.rawValue).sorted())
        }
    }
}
