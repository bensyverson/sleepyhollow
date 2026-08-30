import Foundation

/// A page whose only subresource is a large, explicitly cacheable script —
/// and a count of how many times the server was actually asked for it.
///
/// The whole point of ``SleepyHollow/HostGroup`` is that two hosts sharing one
/// `WKWebsiteDataStore` share its HTTP cache, and the only honest way to see a
/// cache is from the *server* side: a hit that never reaches the wire. So the
/// script route counts its requests, and the page route is served `no-store`
/// so the second load is a real navigation rather than a cached document that
/// might never re-request anything.
///
/// The script is generated rather than committed: the figure that matters is
/// its size, and a few megabytes of filler does not belong in the repository.
///
/// ```swift
/// let fixture = CachedScriptFixture()
/// await fixture.install(on: server)
/// // … two loads of CachedScriptFixture.pagePath …
/// #expect(await fixture.scriptRequestCount == 1)
/// ```
public actor CachedScriptFixture {
    /// The path serving the page: `no-store` HTML referencing ``scriptPath``.
    public static let pagePath: String = "/cached-script.html"

    /// The path serving the large script, `Cache-Control: max-age=3600`.
    public static let scriptPath: String = "/cached-script.js"

    /// How many times the server has been asked for the script.
    public private(set) var scriptRequestCount: Int = 0

    /// How many times the server has been asked for the page.
    public private(set) var pageRequestCount: Int = 0

    private let script: Data

    /// Creates the fixture with a script of roughly `scriptBytes` bytes.
    ///
    /// - Parameter scriptBytes: how large to make the script body. The default
    ///   is small enough to keep a test quick; the measurement script asks for
    ///   megabytes, which is the regime the Woodcase report measured.
    public init(scriptBytes: Int = 64 * 1024) {
        var body = "window.cachedScriptLoaded = true;\n"
        let filler = "window.cachedScriptFiller = (window.cachedScriptFiller || 0) + 1;\n"
        while body.utf8.count < scriptBytes {
            body += filler
        }
        script = Data(body.utf8)
    }

    /// How many bytes the script route serves.
    public var scriptByteCount: Int {
        script.count
    }

    /// Registers both routes on `server`.
    public func install(on server: FixtureServer) async {
        let script: Data = script
        await server.register(path: Self.pagePath) { [weak self] _ in
            await self?.notePageRequest()
            return FixtureResponse(
                status: 200,
                contentType: .html,
                headers: ["Cache-Control": "no-store"],
                body: Data(Self.pageHTML.utf8),
            )
        }
        await server.register(path: Self.scriptPath) { [weak self] _ in
            await self?.noteScriptRequest()
            return FixtureResponse(
                status: 200,
                contentType: .javascript,
                headers: [
                    "Cache-Control": "max-age=3600",
                    "Date": Self.httpDate,
                    "Last-Modified": Self.httpDate,
                    "ETag": "\"cached-script\"",
                ],
                body: script,
            )
        }
    }

    /// Forgets the counts, so one server can measure several rounds.
    public func resetCounts() {
        scriptRequestCount = 0
        pageRequestCount = 0
    }

    private func noteScriptRequest() {
        scriptRequestCount += 1
    }

    private func notePageRequest() {
        pageRequestCount += 1
    }

    /// A fixed HTTP date, so the script's freshness is computable.
    private static let httpDate: String = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: Date())
    }()

    /// The page: a title, one paragraph, and the script it exists to fetch.
    private static let pageHTML: String = """
    <!doctype html>
    <html lang="en">
    <head><meta charset="utf-8"><title>Cached script</title>
    <script src="\(scriptPath)"></script></head>
    <body><p id="ready">ready</p></body>
    </html>
    """
}
