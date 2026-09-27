import Foundation
@testable import SleepyHollow
import Testing

/// `WKHTTPCookieStore`'s reads and writes are completion handlers with no
/// timeout of their own, answered by WebKit's networking process: one that
/// stops answering used to suspend a cookie read, a jar import or a jar save
/// for good. Every bridge call now answers within its caller's budget or
/// times out.
///
/// A real cookie store cannot be made to stall on demand, so these stand in a
/// store that never answers. Nothing is compared with the elapsed time.
@Suite("Cookie store deadlines")
struct CookieStoreDeadlineTests {
    /// A cookie store that takes every call and answers none of them.
    @MainActor
    final class NeverAnsweringStore: CookieStoreCalls {
        /// How many calls reached the store — proof the call was issued, not
        /// refused before it started.
        var calls: Int = 0

        func readAll(_: @escaping @MainActor ([HTTPCookie]) -> Void) {
            calls += 1
        }

        func write(_: HTTPCookie, _: @escaping @MainActor () -> Void) {
            calls += 1
        }
    }

    static let record = CookieRecord(name: "session", value: "abc", domain: "example.com")

    /// A host whose calls get half a second.
    @MainActor
    static func host() -> PageHost {
        var options = LoadOptions()
        options.callBudget = 0.5
        return PageHost(options: options)
    }

    @Test
    @MainActor
    func `a cookie read the store never answers times out at the host's call budget and abandons the host`() async throws {
        let host: PageHost = Self.host()
        let store = NeverAnsweringStore()
        do {
            _ = try await CookieStoreBridge.allCookies(in: store, through: host)
            Issue.record("expected a timeout")
        } catch let error as SleepyError {
            #expect(error.kind == .timeout)
            #expect(error.message.contains("cookie"), "the timeout must name the call: \(error.message)")
            #expect(error.message.contains("0.5s"), "the timeout must name its budget: \(error.message)")
        }
        #expect(store.calls == 1)
        #expect(host.abandonedCall?.reason == .deadline(0.5))
    }

    @Test
    @MainActor
    func `a cookie write the store never answers times out at the host's call budget and abandons the host`() async throws {
        let host: PageHost = Self.host()
        let store = NeverAnsweringStore()
        let cookie: HTTPCookie = try #require(Self.record.httpCookie)
        do {
            try await CookieStoreBridge.set(cookie, in: store, through: host)
            Issue.record("expected a timeout")
        } catch let error as SleepyError {
            #expect(error.kind == .timeout)
            #expect(error.message.contains("cookie"), "the timeout must name the call: \(error.message)")
        }
        #expect(store.calls == 1)
        #expect(host.abandonedCall?.reason == .deadline(0.5))
    }

    @Test
    @MainActor
    func `a jar import the store never answers times out rather than blocking the first load`() async throws {
        let host: PageHost = Self.host()
        let store = NeverAnsweringStore()
        await #expect(throws: SleepyError.self) {
            try await CookieStoreBridge.load([Self.record], into: store, through: host)
        }
        #expect(store.calls == 1, "the first unanswered write ends the import")
    }

    @Test
    @MainActor
    func `a group's cookie read the store never answers times out at the group's call budget`() async throws {
        let group = HostGroup()
        group.callBudget = 0.5
        let store = NeverAnsweringStore()
        do {
            _ = try await CookieStoreBridge.allCookies(in: store, through: group)
            Issue.record("expected a timeout")
        } catch let error as SleepyError {
            #expect(error.kind == .timeout)
            #expect(error.message.contains("0.5s"), "the timeout must name its budget: \(error.message)")
        }
    }

    @Test
    @MainActor
    func `a group's call budget defaults to the library's`() {
        #expect(HostGroup().callBudget == LoadOptions.defaultCallBudget)
    }
}
