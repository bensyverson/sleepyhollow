import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// Attaching a jar: what a load imports, what it persists, and the flagship
/// claim — a jar minted by one host authenticates a later, unrelated one.
@Suite("PageHost jars")
struct PageHostJarTests {
    private let login: JarName = .init("login-flow")!

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

    // MARK: - The flagship

    @Test
    @MainActor
    func `a jar minted by one load authenticates a later unrelated load`() async throws {
        try await withJarRoot { _, base, store in
            var minting = LoadOptions()
            minting.jar = login
            let minter = PageHost(options: minting, jars: store)
            _ = try await minter.load(URL(string: "cookie", relativeTo: base)!)

            // A second host, built from scratch, sharing only the jar's name.
            var reusing = LoadOptions()
            reusing.jar = login
            let reuser = PageHost(options: reusing, jars: store)
            _ = try await reuser.load(URL(string: "echo-cookie", relativeTo: base)!)
            let sent: String = try await text(of: "#sent", in: reuser)
            #expect(sent.contains("sleepy=hollow"))
        }
    }

    @Test
    @MainActor
    func `without a jar the same second load carries no cookie`() async throws {
        try await withJarRoot { _, base, store in
            var minting = LoadOptions()
            minting.jar = login
            _ = try await PageHost(options: minting, jars: store)
                .load(URL(string: "cookie", relativeTo: base)!)

            let bare = PageHost(options: LoadOptions(), jars: store)
            _ = try await bare.load(URL(string: "echo-cookie", relativeTo: base)!)
            try #expect(await text(of: "#sent", in: bare) == "none")
        }
    }

    // MARK: - Persistence

    @Test
    @MainActor
    func `a load with a jar writes the cookies the page set`() async throws {
        try await withJarRoot { _, base, store in
            var options = LoadOptions()
            options.jar = login
            let host = PageHost(options: options, jars: store)
            _ = try await host.load(URL(string: "cookie", relativeTo: base)!)
            let saved: [CookieRecord] = try store.cookies(in: login)
            #expect(saved.contains { $0.name == "sleepy" && $0.value == "hollow" })
        }
    }

    @Test
    @MainActor
    func `naming a jar creates it even when the page sets nothing`() async throws {
        try await withJarRoot { _, base, store in
            var options = LoadOptions()
            options.jar = JarName("fresh")!
            let host = PageHost(options: options, jars: store)
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            #expect(store.exists(JarName("fresh")!))
        }
    }

    @Test
    @MainActor
    func `a bare load writes nothing under the jar root`() async throws {
        try await withJarRoot { _, base, store in
            let host = PageHost(options: LoadOptions(), jars: store)
            _ = try await host.load(URL(string: "cookie", relativeTo: base)!)
            #expect(!FileManager.default.fileExists(atPath: store.jarsDirectory.path))
        }
    }

    @Test
    @MainActor
    func `a cookie written by script during the load reaches the jar`() async throws {
        try await withJarRoot { _, base, store in
            var options = LoadOptions()
            options.jar = login
            let host = PageHost(options: options, jars: store)
            _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            _ = try await host.evaluate("document.cookie = 'minted=by-script; Path=/'; return '';")
            try await host.saveJar()
            try #expect(store.cookies(in: login).contains { $0.name == "minted" })
        }
    }

    @Test
    @MainActor
    func `a load that fails still persists what the jar already gained`() async throws {
        try await withJarRoot { _, base, store in
            var options = LoadOptions()
            options.jar = login
            let host = PageHost(options: options, jars: store)
            _ = try await host.load(URL(string: "cookie", relativeTo: base)!)

            // The same host navigating somewhere unreachable must not lose the
            // cookie it already minted.
            await #expect(throws: SleepyError.self) {
                _ = try await host.load(URL(string: "http://127.0.0.1:9/nope")!)
            }
            try #expect(store.cookies(in: login).contains { $0.name == "sleepy" })
        }
    }

    // MARK: - Failure modes

    @Test
    @MainActor
    func `an unreadable jar is an environment error, not a silent empty load`() async throws {
        try await withJarRoot { _, base, store in
            try store.write([], to: login)
            try Data("not json".utf8).write(to: store.cookiesURL(for: login))
            var options = LoadOptions()
            options.jar = login
            let host = PageHost(options: options, jars: store)
            let error: SleepyError? = await #expect(throws: SleepyError.self) {
                _ = try await host.load(URL(string: "static.html", relativeTo: base)!)
            }
            #expect(error?.kind == .environment)
        }
    }
}
