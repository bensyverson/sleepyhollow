import Foundation
import Testing
import TestSupport

/// Exercises the in-process HTTP fixture server: static files, content types,
/// dynamic routes, the delay prefix, the cookie route, and lifecycle.
struct FixtureServerTests {
    /// An ephemeral session so cookie storage and caches never bleed between tests.
    private func makeSession() -> URLSession {
        URLSession(configuration: URLSessionConfiguration.ephemeral)
    }

    @Test func `serves a fixture page's exact bytes`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let expected = try Data(
                contentsOf: TestSupport.fixturesDirectory.appendingPathComponent("static.html"),
            )
            let (data, response) = try await makeSession().data(
                from: baseURL.appendingPathComponent("static.html"),
            )
            let http = try #require(response as? HTTPURLResponse)
            #expect(http.statusCode == 200)
            #expect(data == expected)
        }
    }

    @Test func `reports correct content types`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let expectations: [(file: String, contentType: String)] = [
                ("static.html", "text/html"),
                ("slow.css", "text/css"),
                ("script.js", "text/javascript"),
                ("pixel.png", "image/png"),
            ]
            let session = makeSession()
            for expectation in expectations {
                let (_, response) = try await session.data(
                    from: baseURL.appendingPathComponent(expectation.file),
                )
                let http = try #require(response as? HTTPURLResponse)
                let contentType = try #require(http.value(forHTTPHeaderField: "Content-Type"))
                #expect(
                    contentType.hasPrefix(expectation.contentType),
                    "\(expectation.file) served as \(contentType)",
                )
            }
        }
    }

    @Test func `two concurrent servers use distinct ports`() async throws {
        try await FixtureServer.withRunning { _, firstBase in
            try await FixtureServer.withRunning { _, secondBase in
                #expect(firstBase.port != secondBase.port)
                let session = makeSession()
                let (_, first) = try await session.data(
                    from: firstBase.appendingPathComponent("static.html"),
                )
                let (_, second) = try await session.data(
                    from: secondBase.appendingPathComponent("static.html"),
                )
                #expect((first as? HTTPURLResponse)?.statusCode == 200)
                #expect((second as? HTTPURLResponse)?.statusCode == 200)
            }
        }
    }

    @Test func `stop refuses further requests`() async throws {
        let server = FixtureServer()
        let baseURL = try await server.start()
        let session = makeSession()
        let (_, live) = try await session.data(from: baseURL.appendingPathComponent("static.html"))
        #expect((live as? HTTPURLResponse)?.statusCode == 200)

        await server.stop()
        await #expect(throws: (any Error).self) {
            _ = try await session.data(from: baseURL.appendingPathComponent("static.html"))
        }
    }

    @Test func `delay route delays the response`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let expected = try Data(
                contentsOf: TestSupport.fixturesDirectory.appendingPathComponent("static.html"),
            )
            let started = Date()
            let (data, response) = try await makeSession().data(
                from: baseURL.appendingPathComponent("delay/300/static.html"),
            )
            let elapsed = Date().timeIntervalSince(started)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(data == expected)
            #expect(elapsed >= 0.3, "response arrived after \(elapsed)s, expected >= 0.3s")
        }
    }

    @Test func `cookie route sets a cookie`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let (_, response) = try await makeSession().data(
                from: baseURL.appendingPathComponent("cookie"),
            )
            let http = try #require(response as? HTTPURLResponse)
            #expect(http.statusCode == 200)
            let setCookie = try #require(http.value(forHTTPHeaderField: "Set-Cookie"))
            #expect(setCookie.contains("sleepy=hollow"))
        }
    }

    @Test func `dynamic routes serve registered closures`() async throws {
        try await FixtureServer.withRunning { server, baseURL in
            await server.register(method: "POST", path: "/echo") { request in
                FixtureResponse(
                    status: 200,
                    contentType: FixtureContentType.plainText,
                    body: request.body,
                )
            }
            var request = URLRequest(url: baseURL.appendingPathComponent("echo"))
            request.httpMethod = "POST"
            request.httpBody = Data("hello fixture".utf8)
            let (data, response) = try await makeSession().data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(String(decoding: data, as: UTF8.self) == "hello fixture")
        }
    }

    @Test func `built-in submit route echoes urlencoded posts`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            var request = URLRequest(url: baseURL.appendingPathComponent("submit"))
            request.httpMethod = "POST"
            request.setValue(
                "application/x-www-form-urlencoded",
                forHTTPHeaderField: "Content-Type",
            )
            request.httpBody = Data("field=starlight".utf8)
            let (data, response) = try await makeSession().data(for: request)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            #expect(String(decoding: data, as: UTF8.self).contains("field=starlight"))
        }
    }

    @Test func `unknown path returns 404`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            let (_, response) = try await makeSession().data(
                from: baseURL.appendingPathComponent("no-such-page.html"),
            )
            #expect((response as? HTTPURLResponse)?.statusCode == 404)
        }
    }

    @Test func `path traversal is refused`() async throws {
        try await FixtureServer.withRunning { _, baseURL in
            var components = try #require(
                URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
            )
            components.percentEncodedPath = "/%2E%2E/Package.swift"
            let url = try #require(components.url)
            let (_, response) = try await makeSession().data(from: url)
            #expect((response as? HTTPURLResponse)?.statusCode == 404)
        }
    }
}
