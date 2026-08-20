import ArgumentParser
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// `--format` resolves to the verb's own default when unset, and any choice
/// outside the verb's supported subset is a teaching usage error.
struct FormatOptionTests {
    @Test func `an unset format resolves to the verb's default`() throws {
        let resolved = try FormatOption.resolve(nil, default: .html, supporting: [.html, .json], verb: "dom")
        #expect(resolved == .html)
    }

    @Test func `an explicit supported format is honored`() throws {
        let resolved = try FormatOption.resolve(.json, default: .html, supporting: [.html, .json], verb: "dom")
        #expect(resolved == .json)
    }

    @Test func `an unsupported format is a usage error listing the verb's formats`() {
        do {
            _ = try FormatOption.resolve(.outline, default: .html, supporting: [.html, .json], verb: "dom")
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.message.contains("dom"))
            #expect(error.nextMove?.contains("html") == true)
            #expect(error.nextMove?.contains("json") == true)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    @Test func `parses --format via ArgumentParser`() throws {
        let options = try FormatOption.parse(["--format", "json"])
        #expect(options.format == .json)
    }
}
