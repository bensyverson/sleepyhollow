import Foundation
@testable import SleepyHollow
import Testing
import TestSupport
import WebKit

/// The measurement behind ``HostGroup``'s documentation: what a shared
/// `WKWebsiteDataStore` actually shares, and what a load costs with and
/// without one.
///
/// Off unless `SLEEPY_MEASURE` is set, because it is not a test — it asserts
/// almost nothing and it deliberately loads megabytes. Run it through
/// `scripts/measure-host-group.sh`, which sets that variable and names the two
/// knobs (`SLEEPY_MEASURE_LOADS`, `SLEEPY_MEASURE_SCRIPT_BYTES`).
///
/// One arrangement below builds a deprecated `WKProcessPool` on purpose, to
/// show the deprecation notice ("no longer has any effect") is literally
/// true; that test is itself marked deprecated so the evidence compiles clean.
@Suite(
    "HostGroup measurement",
    .enabled(if: ProcessInfo.processInfo.environment["SLEEPY_MEASURE"] != nil),
)
struct HostGroupMeasurementTests {
    /// How many loads each arrangement performs.
    private var loads: Int {
        ProcessInfo.processInfo.environment["SLEEPY_MEASURE_LOADS"].flatMap { Int($0) } ?? 6
    }

    /// How large the page's one script is, in bytes.
    private var scriptBytes: Int {
        ProcessInfo.processInfo.environment["SLEEPY_MEASURE_SCRIPT_BYTES"].flatMap { Int($0) } ?? 3_400_000
    }

    // MARK: - What a data store shares

    /// Prints one line per store-and-process arrangement: how many times the
    /// server was asked for a script two page loads both reference.
    ///
    /// This is the table in `project/2026-08-29-host-group-cache.md`. It uses
    /// raw `WKWebView`s rather than ``PageHost``s so that each arrangement is
    /// exactly one variable away from its neighbour.
    /// Deprecated on purpose: one arrangement builds a `WKProcessPool`, which
    /// is deprecated ("no longer has any effect") from this package's floor
    /// on — that inertness is what the arrangement measures.
    @available(*, deprecated)
    @Test
    @MainActor
    func `how many fetches each store arrangement costs`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let fixture = CachedScriptFixture(scriptBytes: 64 * 1024)
            await fixture.install(on: server)
            let page = URL(string: CachedScriptFixture.pagePath, relativeTo: base)!

            print("arrangement                                 script fetches for 2 loads")
            try await report("two views, one ephemeral store", fixture) {
                let store: WKWebsiteDataStore = .nonPersistent()
                let first: WKWebView = Self.view(store: store)
                let second: WKWebView = Self.view(store: store)
                await Self.load(first, page)
                await Self.load(second, page)
            }
            try await report("two views, one ephemeral store + one process pool", fixture) {
                let store: WKWebsiteDataStore = .nonPersistent()
                let pool = WKProcessPool()
                let first: WKWebView = Self.view(store: store, pool: pool)
                let second: WKWebView = Self.view(store: store, pool: pool)
                await Self.load(first, page)
                await Self.load(second, page)
            }
            try await report("one view, two loads, ephemeral store", fixture) {
                let view: WKWebView = Self.view(store: .nonPersistent())
                await Self.load(view, page)
                await Self.load(view, page)
            }
            try await report("two views, one ephemeral store, first released", fixture) {
                let store: WKWebsiteDataStore = .nonPersistent()
                do {
                    let first: WKWebView = Self.view(store: store)
                    await Self.load(first, page)
                }
                let second: WKWebView = Self.view(store: store)
                await Self.load(second, page)
            }
            let since = Date()
            try await report("two views, the persistent default store", fixture) {
                let store: WKWebsiteDataStore = .default()
                let first: WKWebView = Self.view(store: store)
                let second: WKWebView = Self.view(store: store)
                await Self.load(first, page)
                await Self.load(second, page)
            }
            // The persistent arrangement is the only one that writes to disk;
            // take back exactly what it wrote.
            await WKWebsiteDataStore.default().removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: since,
            )
        }
    }

    // MARK: - What a load costs

    /// Prints per-load milliseconds for N fresh hosts and for N members of one
    /// group, plus what the server was asked for in each case.
    @Test
    @MainActor
    func `per-load milliseconds, fresh hosts against one group`() async throws {
        try await FixtureServer.withRunningOnMainActor { server, base in
            let fixture = CachedScriptFixture(scriptBytes: scriptBytes)
            await fixture.install(on: server)
            let page = URL(string: CachedScriptFixture.pagePath, relativeTo: base)!
            let bytes: Int = await fixture.scriptByteCount
            print("loads=\(loads) script=\(bytes) bytes")

            // One throwaway load before either arm: without it whichever arm
            // runs second wins by a factor of two on framework and
            // network-process warm-up alone. Set SLEEPY_MEASURE_ORDER=group
            // to swap the arms and confirm the remaining order effect.
            _ = try await PageHost().load(page)
            await fixture.resetCounts()

            var fresh: [PageHost] = []
            var members: [PageHost] = []
            let group = HostGroup()
            let freshArm: () async throws -> Void = {
                let host = PageHost()
                fresh.append(host)
                _ = try await host.load(page)
            }
            let groupArm: () async throws -> Void = {
                let host: PageHost = try PageHost.member(of: group)
                members.append(host)
                _ = try await host.load(page)
            }

            var freshMilliseconds = 0.0
            var groupedMilliseconds = 0.0
            var freshFetches = 0
            var groupedFetches = 0
            if ProcessInfo.processInfo.environment["SLEEPY_MEASURE_ORDER"] == "group" {
                groupedMilliseconds = try await Self.milliseconds(over: loads, groupArm)
                groupedFetches = await fixture.scriptRequestCount
                await fixture.resetCounts()
                freshMilliseconds = try await Self.milliseconds(over: loads, freshArm)
                freshFetches = await fixture.scriptRequestCount
            } else {
                freshMilliseconds = try await Self.milliseconds(over: loads, freshArm)
                freshFetches = await fixture.scriptRequestCount
                await fixture.resetCounts()
                groupedMilliseconds = try await Self.milliseconds(over: loads, groupArm)
                groupedFetches = await fixture.scriptRequestCount
            }

            print(String(format: "fresh hosts   %.1f ms per load, %d script fetches", freshMilliseconds, freshFetches))
            print(String(
                format: "one group     %.1f ms per load, %d script fetches",
                groupedMilliseconds,
                groupedFetches,
            ))
        }
    }

    // MARK: - Apparatus

    /// Runs `arrangement`, prints its script-fetch count against `label`, and
    /// resets the counter for the next one.
    @MainActor
    private func report(
        _ label: String,
        _ fixture: CachedScriptFixture,
        _ arrangement: () async throws -> Void,
    ) async throws {
        try await arrangement()
        let fetches: Int = await fixture.scriptRequestCount
        await fixture.resetCounts()
        print(label.padding(toLength: 44, withPad: " ", startingAt: 0) + "\(fetches)")
    }

    /// The mean milliseconds one iteration of `body` took, over `count` of them.
    @MainActor
    private static func milliseconds(over count: Int, _ body: () async throws -> Void) async rethrows -> Double {
        let started: DispatchTime = .now()
        for _ in 0 ..< count {
            try await body()
        }
        let elapsed: UInt64 = DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds
        return Double(elapsed) / 1_000_000 / Double(max(1, count))
    }

    /// A bare web view on `store`, with no ``PageHost`` machinery in the way.
    /// Deprecated for the same reason as its one caller: the `pool` it takes.
    @available(*, deprecated)
    @MainActor
    private static func view(store: WKWebsiteDataStore, pool: WKProcessPool? = nil) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        if let pool { configuration.processPool = pool }
        return WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
    }

    /// Navigates `view` and returns when the navigation ends, either way.
    @MainActor
    private static func load(_ view: WKWebView, _ url: URL) async {
        let delegate = MeasurementNavigationDelegate()
        view.navigationDelegate = delegate
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            delegate.finish = { continuation.resume() }
            view.load(URLRequest(url: url))
        }
        view.navigationDelegate = nil
    }
}
