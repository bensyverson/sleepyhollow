import Foundation
@testable import SleepyHollow
import Testing

/// Locks the deterministic defaults the vision doc promises and the wire shape
/// the session layer depends on.
struct LoadOptionsTests {
    @Test func `defaults are the documented deterministic ones`() {
        let options = LoadOptions()
        #expect(options.size == ViewportSize(width: 1280, height: 800))
        #expect(options.theme == .light)
        #expect(options.jar == nil)
        #expect(options.scripts.isEmpty)
        #expect(options.wait == nil)
        #expect(options.budget == nil)
        #expect(options.steps.isEmpty)
    }

    @Test func `default dialog policy declines and answers nothing`() {
        let policy = DialogPolicy()
        #expect(policy.acceptsConfirms == false)
        #expect(policy.promptResponse == nil)
    }

    @Test func `a default load budget exists for hosts to apply`() {
        #expect(LoadOptions.defaultBudget > 0)
    }

    @Test func `fully populated options survive JSON transport`() throws {
        var options = LoadOptions()
        options.size = ViewportSize(width: 390, height: 844)
        options.theme = .dark
        options.jar = JarName("login")
        options.scripts = [
            InjectedScript(source: "console.log('hi')", injectAt: .documentStart, world: .page),
        ]
        options.dialogs = DialogPolicy(acceptsConfirms: true, promptResponse: "yes")
        options.wait = .selector("#done")
        options.budget = 5.5
        options.steps = [
            .fill(selector: "#q", value: "webkit"),
            .click(selector: "#go"),
            .submit(selector: "form"),
        ]

        let data: Data = try JSONEncoder().encode(options)
        let decoded: LoadOptions = try JSONDecoder().decode(LoadOptions.self, from: data)
        #expect(decoded == options)
    }

    @Test func `every wait condition survives JSON transport`() throws {
        let conditions: [WaitCondition] = [
            .selector("#x"), .predicate("window.ready"), .message("appReady"), .idle, .load,
        ]
        for condition in conditions {
            let data: Data = try JSONEncoder().encode(condition)
            let decoded: WaitCondition = try JSONDecoder().decode(WaitCondition.self, from: data)
            #expect(decoded == condition)
        }
    }
}
