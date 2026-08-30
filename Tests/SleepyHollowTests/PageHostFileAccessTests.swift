import Foundation
import SleepyHollow
import Testing
import TestSupport

/// ``LoadOptions/fileAccessRoot``: the read-access grant that lets a `file:`
/// page's own scripts read files beside it.
///
/// `file-fetch.html` is the probe — it `fetch()`es its sibling
/// `file-fetch-target.txt` and writes either `ok:<contents>` or
/// `blocked:<reason>` into `#result`, appending `#done` either way so the wait
/// is a happens-before rather than a timer.
///
/// The fixtures directory is used as a real on-disk root: `FixtureServer`
/// serves over HTTP, and nothing about a `file:` load goes through it.
@Suite("PageHost file access root")
struct PageHostFileAccessTests {
    private static var fixtures: URL {
        TestSupport.fixturesDirectory
    }

    private static var page: URL {
        fixtures.appendingPathComponent("file-fetch.html")
    }

    /// The probe's verdict. `evaluate` hands back the value's JSON, so a
    /// string arrives quoted; decoding is what turns it back into one.
    @MainActor
    private func fetchResult(under root: URL?) async throws -> String {
        let host = PageHost(options: LoadOptions(fileAccessRoot: root, wait: .selector("#done")))
        _ = try await host.load(Self.page)
        let json: String = try await host.evaluate("return document.getElementById('result').textContent;")
        return try JSONDecoder().decode(String.self, from: Data(json.utf8))
    }

    @Test
    @MainActor
    func `a file page under a read-access root can fetch a sibling file`() async throws {
        let text: String = try await fetchResult(under: Self.fixtures)
        #expect(text == "ok:sibling-file-contents")
    }

    @Test
    @MainActor
    func `the same fetch is refused without a read-access root`() async throws {
        let text: String = try await fetchResult(under: nil)
        #expect(text.hasPrefix("blocked:"), "expected the sibling fetch to fail, got '\(text)'")
    }

    @Test
    @MainActor
    func `a non-file URL ignores the root`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(fileAccessRoot: Self.fixtures))
            let facts = try await host.load(#require(URL(string: "static.html", relativeTo: base)))
            #expect(facts.httpStatus == 200)
        }
    }

    @Test
    @MainActor
    func `a root that is not a file URL is a usage error`() async throws {
        let host = PageHost(options: LoadOptions(fileAccessRoot: URL(string: "https://example.com/")))
        await #expect(throws: SleepyError.self) {
            _ = try await host.load(Self.page)
        }
    }
}
