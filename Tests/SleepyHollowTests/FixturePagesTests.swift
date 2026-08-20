import Foundation
import Testing
import TestSupport

/// Verifies the shared fixture pages: every page the implementation plan lists
/// exists in the bundled fixtures directory and is served over localhost HTTP.
struct FixturePagesTests {
    @Test func `the shared page list covers the plan's fixtures`() {
        let files = Set(FixturePage.allCases.map(\.fileName))
        let expected: Set = [
            "static.html",
            "form.html",
            "dialogs.html",
            "theme.html",
            "slow.html",
            "fetch.html",
            "cookie.html",
        ]
        #expect(files == expected)
    }

    @Test func `all shared fixture pages exist on disk`() {
        for page in FixturePage.allCases {
            let url = TestSupport.fixturesDirectory.appendingPathComponent(page.fileName)
            #expect(
                FileManager.default.fileExists(atPath: url.path),
                "\(page.fileName) is missing from the fixtures directory",
            )
        }
    }

    @Test func `all shared fixture pages are served as html`() async throws {
        try await FixtureServer.withRunning { server, _ in
            let session = URLSession(configuration: URLSessionConfiguration.ephemeral)
            for page in FixturePage.allCases {
                let url = try await server.url(for: page)
                let (data, response) = try await session.data(from: url)
                let http = try #require(response as? HTTPURLResponse)
                #expect(http.statusCode == 200, "\(page.fileName) did not serve")
                let contentType = try #require(http.value(forHTTPHeaderField: "Content-Type"))
                #expect(contentType.hasPrefix("text/html"))
                #expect(!data.isEmpty)
            }
        }
    }

    @Test func `fixture pages reference no external resources`() throws {
        for page in FixturePage.allCases {
            let url = TestSupport.fixturesDirectory.appendingPathComponent(page.fileName)
            let html = try String(contentsOf: url, encoding: String.Encoding.utf8)
            #expect(!html.contains("http://"), "\(page.fileName) references an absolute URL")
            #expect(!html.contains("https://"), "\(page.fileName) references an absolute URL")
        }
    }
}
