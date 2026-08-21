import ArgumentParser
import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// The routing decisions every page verb inherits: which page source a verb's
/// arguments name, and which flags a `--session` invocation may not carry.
struct PageExecutionRoutingTests {
    // MARK: - Loading options against a session

    /// A parsed option group. ArgumentParser traps when an `@Option` it never
    /// filled is read, so a routing test must go through the parser rather
    /// than construct `LoadFlagOptions()` by hand.
    private static func flags(_ arguments: [String]) throws -> LoadFlagOptions {
        try LoadFlagOptions.parse(arguments)
    }

    @Test func `a bare session invocation carries no loading options`() throws {
        let flags: LoadFlagOptions = try Self.flags([])
        try PageExecution.requireSessionCompatible(flags)
        #expect(PageExecution.loadShapingFlags(flags).isEmpty)
    }

    @Test func `an act verb declares no loading flags at all`() throws {
        try PageExecution.requireSessionCompatible(nil)
        #expect(PageExecution.loadShapingFlags(nil).isEmpty)
    }

    @Test func `--wait-for is a load-shaping flag a session refuses`() throws {
        let flags: LoadFlagOptions = try Self.flags(["--wait-for", "#ready"])
        #expect(PageExecution.loadShapingFlags(flags) == ["--wait-for"])
        #expect(throws: SleepyError.self) {
            try PageExecution.requireSessionCompatible(flags)
        }
    }

    @Test func `every load-shaping flag is named, in a stable order`() throws {
        let flags: LoadFlagOptions = try Self.flags([
            "--size", "800x600",
            "--theme", "dark",
            "--jar", "login",
            "--inject", "a.js",
            "--inject-world", "page",
            "--wait-for", "idle",
            "--confirm", "accept",
            "--prompt-text", "hi",
            "--click", "#go",
            "--fill", "#q=x",
            "--submit", "form",
        ])
        #expect(PageExecution.loadShapingFlags(flags) == [
            "--size", "--theme", "--jar", "--inject", "--inject-world", "--wait-for",
            "--confirm", "--prompt-text", "--click", "--fill", "--submit",
        ])
    }

    @Test func `the refusal teaches where the option belongs`() throws {
        let flags: LoadFlagOptions = try Self.flags(["--theme", "dark"])
        do {
            try PageExecution.requireSessionCompatible(flags)
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.message.contains("--theme"))
            #expect(error.nextMove?.contains("sleepy open") == true)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    @Test func `--budget is not load-shaping: it bounds the session client instead`() throws {
        let flags: LoadFlagOptions = try Self.flags(["--budget", "5000"])
        #expect(PageExecution.loadShapingFlags(flags).isEmpty)
        try PageExecution.requireSessionCompatible(flags)
        let name: SessionName = try #require(SessionName("login"))
        #expect(try PageExecution.client(for: name, flags: flags).connectTimeout == 5)
    }

    // MARK: - The load verb's target

    /// A URL literal the tests compare against, spelled once.
    private static let page = URL(string: "http://example.com/")!
    /// The URL a navigation moves to.
    private static let next = URL(string: "http://example.com/next")!

    @Test func `a bare URL is an ephemeral load`() throws {
        let target = try PageSourceOptions.resolveLoadTarget(url: Self.page.absoluteString, session: nil)
        #expect(target == .ephemeral(Self.page))
    }

    @Test func `a bare session reads the session's current facts`() throws {
        let name: SessionName = try #require(SessionName("login"))
        let target = try PageSourceOptions.resolveLoadTarget(url: nil, session: "login")
        #expect(target == .session(name, navigatingTo: nil))
    }

    @Test func `a URL and a session together navigate the session`() throws {
        let name: SessionName = try #require(SessionName("login"))
        let target = try PageSourceOptions.resolveLoadTarget(url: Self.next.absoluteString, session: "login")
        #expect(target == .session(name, navigatingTo: Self.next))
    }

    @Test func `neither a URL nor a session is still a usage error`() {
        #expect(throws: SleepyError.self) {
            _ = try PageSourceOptions.resolveLoadTarget(url: nil, session: nil)
        }
    }

    @Test func `a scheme-less URL is refused when navigating a session`() {
        #expect(throws: SleepyError.self) {
            _ = try PageSourceOptions.resolveLoadTarget(url: "example.com", session: "login")
        }
    }

    @Test func `the page source a load target names`() throws {
        let name: SessionName = try #require(SessionName("login"))
        #expect(PageSourceOptions.LoadTarget.session(name, navigatingTo: nil).pageSource == .session(name))
        #expect(PageSourceOptions.LoadTarget.ephemeral(Self.page).pageSource == .url(Self.page))
    }
}
