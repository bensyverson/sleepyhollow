import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("Wire fetch log")
struct WireFetchLogTests {
    /// The Starlight acceptance shape: one edit ⇒ exactly one POST, urlencoded,
    /// status 200, body carrying the value.
    @Test
    @MainActor
    func `exactly one POST, urlencoded, 200, body carrying the value`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions().recordingWire())
            _ = try await host.load(URL(string: "fetch.html", relativeTo: base)!)
            let log: WireLog = try await host.execute(WireOperation())

            let posts: [FetchExchange] = log.fetches.filter { $0.method == "POST" }
            #expect(posts.count == 1)
            let post: FetchExchange = try #require(posts.first)
            #expect(post.url.hasSuffix("/submit"))
            #expect(post.requestHeaders["content-type"] == "application/x-www-form-urlencoded")
            #expect(post.requestBody == "field=starlight")
            #expect(post.status == 200)
            #expect(post.responseBody?.contains("starlight") == true)
            #expect(post.truncated == nil)
            #expect(post.error == nil)
        }
    }

    @Test
    @MainActor
    func `exchanges are ordered by start, GET before POST`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions().recordingWire())
            _ = try await host.load(URL(string: "fetch.html", relativeTo: base)!)
            let log: WireLog = try await host.execute(WireOperation())
            #expect(log.fetches.map(\.method) == ["GET", "POST"])
            #expect(log.fetches.map(\.id) == log.fetches.map(\.id).sorted())
        }
    }

    @Test
    @MainActor
    func `a Headers instance and a Request object both survive`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions().recordingWire())
            _ = try await host.load(URL(string: "observe-fetch-styles.html", relativeTo: base)!)
            let log: WireLog = try await host.execute(WireOperation())

            let viaHeaders: FetchExchange = try #require(
                log.fetches.first { $0.requestHeaders["x-sleepy"] == "via-headers" },
            )
            #expect(viaHeaders.method == "POST")
            #expect(viaHeaders.requestBody == "hello-from-headers")
            #expect(viaHeaders.status == 200)

            let viaRequest: FetchExchange = try #require(
                log.fetches.first { $0.requestHeaders["x-sleepy"] == "via-request" },
            )
            #expect(viaRequest.method == "POST")
            #expect(viaRequest.requestBody == "hello-from-request")
            #expect(viaRequest.status == 200)
            // `new Request(…)` adds this for a string body: report what is real.
            #expect(viaRequest.requestHeaders["content-type"]?.hasPrefix("text/plain") == true)
        }
    }

    @Test
    @MainActor
    func `the recorder never breaks the page`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions().recordingWire())
            _ = try await host.load(URL(string: "observe-fetch-styles.html", relativeTo: base)!)
            _ = try await host.execute(WireOperation())
            let pageLog: String = try await host.evaluate(
                "return document.getElementById('log').textContent;",
            )
            #expect(pageLog.contains("headers:received: hello-from-headers;"))
            #expect(pageLog.contains("request:received: hello-from-request;"))
            // A GET with a body: `new Request(input, init)` throws, so the
            // recorder hands the call to the native fetch untouched and the page
            // sees the platform's own rejection.
            #expect(pageLog.contains("illegal:rejected;"))
        }
    }

    @Test
    @MainActor
    func `a body past the cap is flagged, and the page still gets all of it`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let payload = String(repeating: "abcdefgh", count: 1024) // 8 KiB
            await server.register(path: "/observe-large") { _ in
                FixtureResponse(status: 200, contentType: .plainText, body: Data(payload.utf8))
            }
            let host = PageHost(options: LoadOptions().recordingWire(byteCap: 1024))
            _ = try await host.load(URL(string: "observe-large-fetch.html", relativeTo: base)!)
            let log: WireLog = try await host.execute(WireOperation())

            let large: FetchExchange = try #require(log.fetches.first { $0.url.hasSuffix("/observe-large") })
            #expect(large.status == 200)
            #expect(large.truncated == .size)
            #expect((large.responseBody?.count ?? 0) <= 1024)
            #expect(large.responseBody?.hasPrefix("abcdefgh") == true)
            #expect((large.responseBodyBytes ?? 0) >= 1024)

            let pageLog: String = try await host.evaluate(
                "return document.getElementById('log').textContent;",
            )
            #expect(pageLog == "\"large:8192;\"")
        }
    }

    @Test
    @MainActor
    func `an opaque response is reported honestly, not as a failure`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            try await FixtureServer.withRunningOnMainActor { _, otherBase in
                var components = URLComponents(
                    url: URL(string: "observe-opaque.html", relativeTo: base)!,
                    resolvingAgainstBaseURL: true,
                )!
                let target: String = otherBase.appendingPathComponent("fetch-target.txt").absoluteString
                components.queryItems = [URLQueryItem(name: "target", value: target)]
                let host = PageHost(options: LoadOptions().recordingWire())
                _ = try await host.load(components.url!)
                let log: WireLog = try await host.execute(WireOperation())

                let opaque: FetchExchange = try #require(log.fetches.first { $0.url == target })
                #expect(opaque.responseType == "opaque")
                #expect(opaque.status == 0)
                #expect(opaque.responseHeaders.isEmpty)
                #expect(opaque.responseBody == nil)
                #expect(opaque.error == nil)
            }
        }
    }

    @Test
    @MainActor
    func `without the recorder, the verb teaches how to install it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "fetch.html", relativeTo: base)!)
            await #expect(throws: SleepyError.self) {
                _ = try await host.execute(WireOperation())
            }
        }
    }
}
