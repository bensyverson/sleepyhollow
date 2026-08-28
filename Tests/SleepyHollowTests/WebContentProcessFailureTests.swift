import Foundation
import SleepyHollow
import Testing

@Suite("Web content process failures")
struct WebContentProcessFailureTests {
    @Test
    func `a process that never launched names the sandbox, the page and the next move`() throws {
        let url: URL = try #require(URL(string: "https://example.com/page"))
        let error: SleepyError = WebContentProcessFailure.neverLaunched.error(url: url)
        #expect(error.kind == .loadFailure)
        #expect(error.exitStatus == ExitStatus.loadFailure)
        #expect(error.message.hasPrefix("WebKit could not start under this sandbox"))
        #expect(error.message.contains("https://example.com/page"))
        let nextMove: String = try #require(error.nextMove)
        #expect(nextMove.contains("sandbox"))
        #expect(nextMove.contains("dangerouslyDisableSandbox"))
        #expect(nextMove.contains("/sandbox"))
    }

    @Test
    func `a process that never launched reads the same without a URL`() {
        let error: SleepyError = WebContentProcessFailure.neverLaunched.error(url: nil)
        #expect(error.message.hasPrefix("WebKit could not start under this sandbox"))
        #expect(error.kind == .loadFailure)
    }

    @Test
    func `a process that died mid-load blames the page, not the sandbox`() throws {
        let url: URL = try #require(URL(string: "https://example.com/page"))
        let error: SleepyError = WebContentProcessFailure.crashedMidLoad.error(url: url)
        #expect(error.kind == .loadFailure)
        #expect(!error.message.contains("sandbox"))
        #expect(error.message.contains("https://example.com/page"))
        #expect(error.nextMove != nil)
    }
}
