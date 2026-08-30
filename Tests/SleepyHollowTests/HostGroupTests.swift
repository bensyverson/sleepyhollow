import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// A group is one browser: its members share a cookie store and the one jar
/// — and a host outside a group is unchanged. What they do *not* share is an
/// HTTP cache; that is measured here too, because it is the surprise.
@Suite("Host groups")
struct HostGroupTests {
    private let login: JarName = .init("group-login")!

    /// Runs `body` against a fixture server and a throwaway jar root.
    @MainActor
    private func withJarRoot(
        _ body: @MainActor (FixtureServer, URL, JarStore) async throws -> Void,
    ) async throws {
        let root: URL = try SessionTestRoot.make()
        defer { SessionTestRoot.remove(root) }
        try await FixtureServer.withRunningOnMainActor { server, base in
            try await body(server, base, JarStore(root: root))
        }
    }

    /// An element's text, unwrapped from the JSON string ``PageHost/evaluate``
    /// transports it as.
    @MainActor
    private func text(of selector: String, in host: PageHost) async throws -> String {
        let json: String = try await host.evaluate(
            "return (document.querySelector(selector) || {}).textContent || '';",
            arguments: ["selector": selector],
        )
        return (try? JSONDecoder().decode(String.self, from: Data(json.utf8))) ?? json
    }

    // MARK: - The cache, as WebKit actually shares it

    /// One web view reuses its own cached subresource, which is what makes the
    /// next test's failure to share meaningful: the cache exists, it is just
    /// not the data store's.
    @Test
    @MainActor
    func `one host loading the page twice asks for the script once`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let fixture = CachedScriptFixture()
            await fixture.install(on: server)
            let page = URL(string: CachedScriptFixture.pagePath, relativeTo: base)!

            let host = PageHost()
            _ = try await host.load(page)
            _ = try await host.load(page)

            let pages: Int = await fixture.pageRequestCount
            let scripts: Int = await fixture.scriptRequestCount
            #expect(pages == 2)
            #expect(scripts == 1)
        }
    }

    /// **A recorded WebKit fact, not a goal.** Sharing a *non-persistent*
    /// `WKWebsiteDataStore` shares its cookies but not an HTTP cache: an
    /// ephemeral session has no network cache, and the cache that does the
    /// work above lives in the web view's own content process. So each member
    /// still fetches the script. Measured 2026-08-29 across seven store and
    /// process arrangements — including a shared, deprecated `WKProcessPool`
    /// (no effect) and the persistent default store (which *does* share) — see
    /// `project/2026-08-29-host-group-cache.md`, reproduced by
    /// `scripts/measure-host-group.sh`.
    ///
    /// If this ever records `1`, the shared-cache half of finding 9 has become
    /// reachable without a persistent store, and ``HostGroup``'s documentation
    /// is the thing to correct.
    @Test
    @MainActor
    func `members do not share a cache, because an ephemeral store has none`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let fixture = CachedScriptFixture()
            await fixture.install(on: server)
            let page = URL(string: CachedScriptFixture.pagePath, relativeTo: base)!
            let group = HostGroup()

            let first: PageHost = try PageHost.member(of: group)
            _ = try await first.load(page)
            let second: PageHost = try PageHost.member(of: group)
            _ = try await second.load(page)

            let pages: Int = await fixture.pageRequestCount
            let scripts: Int = await fixture.scriptRequestCount
            #expect(pages == 2)
            #expect(scripts == 2)
        }
    }

    // MARK: - One cookie store, one jar

    @Test
    @MainActor
    func `a cookie one member's load set is sent by the next member`() async throws {
        try await withJarRoot { _, base, store in
            let group = HostGroup(jar: login, jars: store)
            _ = try await PageHost.member(of: group).load(URL(string: "cookie", relativeTo: base)!)

            let second: PageHost = try PageHost.member(of: group)
            _ = try await second.load(URL(string: "echo-cookie", relativeTo: base)!)
            let sent: String = try await text(of: "#sent", in: second)
            #expect(sent.contains("sleepy=hollow"))
        }
    }

    @Test
    @MainActor
    func `the group's jar holds one copy of a cookie two members both saw`() async throws {
        try await withJarRoot { _, base, store in
            let group = HostGroup(jar: login, jars: store)
            _ = try await PageHost.member(of: group).load(URL(string: "cookie", relativeTo: base)!)
            _ = try await PageHost.member(of: group).load(URL(string: "static.html", relativeTo: base)!)

            let saved: [CookieRecord] = try store.cookies(in: login)
            #expect(saved.count(where: { $0.name == "sleepy" }) == 1)
        }
    }

    @Test
    @MainActor
    func `a jar minted before the group is imported once, for every member`() async throws {
        try await withJarRoot { _, base, store in
            var minting = LoadOptions()
            minting.jar = login
            _ = try await PageHost(options: minting, jars: store)
                .load(URL(string: "cookie", relativeTo: base)!)

            let group = HostGroup(jar: login, jars: store)
            let first: PageHost = try PageHost.member(of: group)
            _ = try await first.load(URL(string: "echo-cookie", relativeTo: base)!)
            let second: PageHost = try PageHost.member(of: group)
            _ = try await second.load(URL(string: "echo-cookie", relativeTo: base)!)

            try #expect(await text(of: "#sent", in: first).contains("sleepy=hollow"))
            try #expect(await text(of: "#sent", in: second).contains("sleepy=hollow"))
        }
    }

    @Test
    @MainActor
    func `a group without a jar writes nothing under the jar root`() async throws {
        try await withJarRoot { _, base, store in
            let group = HostGroup(jars: store)
            _ = try await PageHost.member(of: group).load(URL(string: "cookie", relativeTo: base)!)
            #expect(!FileManager.default.fileExists(atPath: store.jarsDirectory.path))
        }
    }

    // MARK: - The jar disagreement

    @Test
    @MainActor
    func `a member naming a different jar is refused`() throws {
        let group = HostGroup(jar: login)
        var options = LoadOptions()
        options.jar = JarName("somewhere-else")
        let error: SleepyError? = #expect(throws: SleepyError.self) {
            _ = try PageHost.member(of: group, options: options)
        }
        #expect(error?.kind == .usage)
    }

    @Test
    @MainActor
    func `a member naming a jar the group does not have is refused`() throws {
        let group = HostGroup()
        var options = LoadOptions()
        options.jar = login
        let error: SleepyError? = #expect(throws: SleepyError.self) {
            _ = try PageHost.member(of: group, options: options)
        }
        #expect(error?.kind == .usage)
    }

    @Test
    @MainActor
    func `a member naming the group's own jar is accepted`() throws {
        let group = HostGroup(jar: login)
        var options = LoadOptions()
        options.jar = login
        let host: PageHost = try PageHost.member(of: group, options: options)
        #expect(host.group === group)
    }

    @Test
    @MainActor
    func `a member naming no jar inherits the group's`() throws {
        let group = HostGroup(jar: login)
        let host: PageHost = try PageHost.member(of: group)
        #expect(host.options.jar == nil)
        #expect(host.group?.jar == login)
    }

    // MARK: - Ungrouped hosts are unchanged

    @Test
    @MainActor
    func `a host built the ordinary way has no group`() {
        #expect(PageHost().group == nil)
    }

    @Test
    @MainActor
    func `two ungrouped hosts do not share a data store`() {
        let first = PageHost()
        let second = PageHost()
        #expect(first.webView.configuration.websiteDataStore !== second.webView.configuration.websiteDataStore)
    }

    @Test
    @MainActor
    func `members share the group's non-persistent data store`() throws {
        let group = HostGroup()
        let first: PageHost = try PageHost.member(of: group)
        let second: PageHost = try PageHost.member(of: group)
        #expect(first.webView.configuration.websiteDataStore === group.dataStore)
        #expect(second.webView.configuration.websiteDataStore === group.dataStore)
        #expect(group.dataStore.isPersistent == false)
    }
}
