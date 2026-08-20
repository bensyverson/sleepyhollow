import ArgumentParser
import Foundation
@testable import SleepyCLIKit
import SleepyHollow
import Testing

/// Every page verb takes exactly one page source: a URL or a named session.
/// Both or neither is a usage error that teaches the grammar; an invalid
/// URL or session name teaches its own rule.
struct PageSourceOptionsTests {
    @Test func `a URL alone resolves to a url page source`() throws {
        let source = try PageSourceOptions.resolve(url: "http://localhost:8080/fixture.html", session: nil)
        #expect(try source == .url(#require(URL(string: "http://localhost:8080/fixture.html"))))
    }

    @Test func `a session alone resolves to a session page source`() throws {
        let source = try PageSourceOptions.resolve(url: nil, session: "login-flow")
        #expect(try source == .session(#require(SessionName("login-flow"))))
    }

    @Test func `giving both a URL and a session is a usage error`() {
        #expect(throws: SleepyError.self) {
            try PageSourceOptions.resolve(url: "http://example.com", session: "login-flow")
        }
    }

    @Test func `giving neither a URL nor a session is a usage error`() {
        #expect(throws: SleepyError.self) {
            try PageSourceOptions.resolve(url: nil, session: nil)
        }
    }

    @Test func `both-given error teaches dropping one or the other`() {
        do {
            _ = try PageSourceOptions.resolve(url: "http://example.com", session: "login-flow")
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.nextMove?.contains("--session") == true)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    @Test func `a URL with no scheme teaches adding one`() {
        do {
            _ = try PageSourceOptions.resolve(url: "example.com", session: nil)
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.nextMove?.contains("http://") == true)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    @Test func `a malformed URL teaches adding a scheme`() {
        #expect(throws: SleepyError.self) {
            try PageSourceOptions.resolve(url: "not a url at all", session: nil)
        }
    }

    @Test func `an invalid session name teaches the naming rule`() {
        do {
            _ = try PageSourceOptions.resolve(url: nil, session: "-bad-start")
            Issue.record("expected a usage error")
        } catch let error as SleepyError {
            #expect(error.kind == .usage)
            #expect(error.nextMove?.contains("letter or digit") == true)
        } catch {
            Issue.record("expected a SleepyError, got \(error)")
        }
    }

    @Test func `parses a positional URL via ArgumentParser`() throws {
        let options = try PageSourceOptions.parse(["http://localhost/fixture.html"])
        #expect(options.url == "http://localhost/fixture.html")
        #expect(options.session == nil)
    }

    @Test func `parses --session via ArgumentParser`() throws {
        let options = try PageSourceOptions.parse(["--session", "login-flow"])
        #expect(options.url == nil)
        #expect(options.session == "login-flow")
    }
}
