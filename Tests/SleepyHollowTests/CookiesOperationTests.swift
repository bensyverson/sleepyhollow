import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `sleepy cookies` against a live page: reading the store, filtering by name,
/// and writing a cookie the page then sees.
@Suite("CookiesOperation")
struct CookiesOperationTests {
    @MainActor
    private func loadedHost(_ path: String, base: URL) async throws -> PageHost {
        let host = PageHost()
        _ = try await host.load(URL(string: path, relativeTo: base)!)
        return host
    }

    @Test func `the operation's wire kind is stable`() {
        #expect(CookiesOperation.kind == "cookies")
    }

    @Test
    @MainActor
    func `get reports the cookies the page was served`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host: PageHost = try await loadedHost("cookie", base: base)
            let cookies: [CookieRecord] = try await host.execute(CookiesOperation())
            #expect(cookies.contains { $0.name == "sleepy" && $0.value == "hollow" })
        }
    }

    @Test
    @MainActor
    func `get filters by name and stays quiet when nothing matches`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host: PageHost = try await loadedHost("cookie", base: base)
            let matched: [CookieRecord] = try await host.execute(CookiesOperation(name: "sleepy"))
            #expect(matched.count == 1)
            let missing: [CookieRecord] = try await host.execute(CookiesOperation(name: "absent"))
            #expect(missing.isEmpty)
        }
    }

    @Test
    @MainActor
    func `set puts a cookie in the live store and reports it back`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host: PageHost = try await loadedHost("static.html", base: base)
            let record = CookieRecord(name: "sid", value: "abc123", domain: "127.0.0.1", path: "/")
            let written: [CookieRecord] = try await host.execute(CookiesOperation(set: record))
            #expect(written.map(\.name) == ["sid"])
            let all: [CookieRecord] = try await host.execute(CookiesOperation())
            #expect(all.contains { $0.name == "sid" && $0.value == "abc123" })
        }
    }

    @Test
    @MainActor
    func `a cookie set through the operation goes out on the next request`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host: PageHost = try await loadedHost("static.html", base: base)
            let record = CookieRecord(name: "sid", value: "abc123", domain: "127.0.0.1", path: "/")
            _ = try await host.execute(CookiesOperation(set: record))
            _ = try await host.load(URL(string: "echo-cookie", relativeTo: base)!)
            let json: String = try await host.evaluate("return document.querySelector('#sent').textContent;")
            #expect(json.contains("sid=abc123"))
        }
    }

    @Test
    @MainActor
    func `setting a nameless cookie is a usage error`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host: PageHost = try await loadedHost("static.html", base: base)
            let record = CookieRecord(name: "", value: "x", domain: "127.0.0.1", path: "/")
            let error: SleepyError? = await #expect(throws: SleepyError.self) {
                _ = try await host.execute(CookiesOperation(set: record))
            }
            #expect(error?.kind == .usage)
        }
    }
}
