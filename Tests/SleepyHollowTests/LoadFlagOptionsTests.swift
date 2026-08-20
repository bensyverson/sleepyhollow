import ArgumentParser
import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// `LoadFlagOptions` resolves every loading flag to Core's `LoadOptions`,
/// teaching the grammar for the ones with a parseable-but-malformed shape
/// (`--size`, `--budget`, `--inject`).
struct LoadFlagOptionsTests {
    private static let noSteps: [ActionStep] = []

    @Test func `no flags resolve to the deterministic defaults`() throws {
        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [], waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.size == ViewportSize.default)
        #expect(options.theme == .light)
        #expect(options.jar == nil)
        #expect(options.scripts.isEmpty)
        #expect(options.wait == nil)
        #expect(options.budget == nil)
        #expect(options.dialogs.acceptsConfirms == false)
        #expect(options.dialogs.promptResponse == nil)
        #expect(options.steps.isEmpty)
    }

    @Test func `--size parses WxH`() throws {
        let options = try LoadFlagOptions.resolve(
            size: "390x844", theme: nil, jar: nil, injectPaths: [], waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.size == ViewportSize(width: 390, height: 844))
    }

    @Test func `a malformed --size teaches the WxH shape`() {
        do {
            _ = try LoadFlagOptions.resolve(
                size: "not-a-size", theme: nil, jar: nil, injectPaths: [], waitFor: nil,
                budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
            )
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.nextMove?.contains("1280x800") == true)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    @Test func `--jar carries the given name`() throws {
        let jar = try #require(JarName("login"))
        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: jar, injectPaths: [], waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.jar == jar)
    }

    @Test func `--inject reads the script file at resolve time`() throws {
        let directory = FileManager.default.temporaryDirectory
        let file = directory.appendingPathComponent(UUID().uuidString + ".js")
        try "window.marked = true;".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [file.path], waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.scripts.count == 1)
        #expect(options.scripts[0].source == "window.marked = true;")
        #expect(options.scripts[0].injectAt == .documentStart)
        #expect(options.scripts[0].world == .isolated)
    }

    @Test func `--inject with a missing file teaches checking the path`() {
        do {
            _ = try LoadFlagOptions.resolve(
                size: nil, theme: nil, jar: nil, injectPaths: ["/no/such/file.js"], waitFor: nil,
                budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
            )
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    @Test func `bare selector wait-for resolves to a selector condition`() throws {
        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [], waitFor: "#done",
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.wait == .selector("#done"))
    }

    @Test func `a js: prefix resolves to a predicate condition`() throws {
        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [], waitFor: "js:window.ready === true",
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.wait == .predicate("window.ready === true"))
    }

    @Test func `the idle keyword resolves to the idle condition`() throws {
        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [], waitFor: "idle",
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.wait == .idle)
    }

    @Test func `the load keyword resolves to the load condition`() throws {
        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [], waitFor: "load",
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.wait == .load)
    }

    @Test func `--budget converts milliseconds to seconds`() throws {
        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [], waitFor: nil,
            budgetMilliseconds: 5000, confirm: nil, promptText: nil, steps: Self.noSteps,
        )
        #expect(options.budget == 5.0)
    }

    @Test func `a non-positive --budget teaches a positive value`() {
        do {
            _ = try LoadFlagOptions.resolve(
                size: nil, theme: nil, jar: nil, injectPaths: [], waitFor: nil,
                budgetMilliseconds: 0, confirm: nil, promptText: nil, steps: Self.noSteps,
            )
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    @Test func `--confirm accept with --prompt-text builds an accepting dialog policy`() throws {
        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [], waitFor: nil,
            budgetMilliseconds: nil, confirm: .accept, promptText: "yes", steps: Self.noSteps,
        )
        #expect(options.dialogs.acceptsConfirms == true)
        #expect(options.dialogs.promptResponse == "yes")
    }

    @Test func `steps pass through untouched`() throws {
        let steps: [ActionStep] = [.click(selector: "#go")]
        let options = try LoadFlagOptions.resolve(
            size: nil, theme: nil, jar: nil, injectPaths: [], waitFor: nil,
            budgetMilliseconds: nil, confirm: nil, promptText: nil, steps: steps,
        )
        #expect(options.steps == steps)
    }

    @Test func `parses --wait-for and --prompt-text via ArgumentParser`() throws {
        let options = try LoadFlagOptions.parse(["--wait-for", "idle", "--prompt-text", "yes"])
        #expect(options.waitFor == "idle")
        #expect(options.promptText == "yes")
    }
}
