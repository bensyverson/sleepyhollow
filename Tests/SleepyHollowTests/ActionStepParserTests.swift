@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// `ActionStepParser` is the order-of-truth for `--click`/`--fill`/`--submit`:
/// ArgumentParser collects each flag into its own array and loses the
/// interleave order, so these steps come from scanning the raw argument
/// vector directly.
struct ActionStepParserTests {
    @Test func `an empty vector produces no steps`() throws {
        #expect(try ActionStepParser.parse([]).isEmpty)
    }

    @Test func `unrelated arguments are ignored`() throws {
        #expect(try ActionStepParser.parse(["load", "http://example.com", "--wait-for", "idle"]).isEmpty)
    }

    @Test func `interleaved flags preserve appearance order`() throws {
        let steps = try ActionStepParser.parse([
            "shot", "http://example.com",
            "--fill", "#q=webkit",
            "--click", "#go",
            "--wait-for", "idle",
            "--submit", "#form",
        ])
        #expect(steps == [
            .fill(selector: "#q", value: "webkit"),
            .click(selector: "#go"),
            .submit(selector: "#form"),
        ])
    }

    @Test func `the same flag repeated preserves its own order`() throws {
        let steps = try ActionStepParser.parse(["--click", "#a", "--click", "#b"])
        #expect(steps == [.click(selector: "#a"), .click(selector: "#b")])
    }

    @Test func `the inline --flag=value form is recognized`() throws {
        let steps = try ActionStepParser.parse(["--click=#go", "--fill=#q=webkit"])
        #expect(steps == [.click(selector: "#go"), .fill(selector: "#q", value: "webkit")])
    }

    @Test func `a flag with no following value is a usage error`() {
        #expect(throws: SleepyError.self) {
            try ActionStepParser.parse(["--click"])
        }
    }

    @Test func `a --fill value missing = is a usage error`() {
        do {
            _ = try ActionStepParser.parse(["--fill", "novalue"])
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.nextMove?.contains("=") == true)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    @Test func `a fill value may contain = in its replacement value`() throws {
        let steps = try ActionStepParser.parse(["--fill", "#q=a=b"])
        #expect(steps == [.fill(selector: "#q", value: "a=b")])
    }
}
