import Darwin
import Foundation
import SleepyHollow
import Testing
import TestSupport
import WebKit

/// A snapshot, a print or an archive must reach the page at the priority an
/// evaluate does, however long the host has sat idle.
///
/// A host's web view has no window, so WebKit throttles its content process
/// once it goes idle: about a second after the last call that held a
/// foreground activity, the process drops to the background band (measured
/// 2026-09-26: priority 31 while called, 4 once idle). `evaluateJavaScript`
/// takes that activity, and so lifts the page back; `takeSnapshot`, printing
/// and `createWebArchiveData` take none. On a loaded machine a background-band
/// process gets no CPU, so a session idle for two seconds could not answer
/// its next shot, pdf or archive before the call budget (job leaf 116NLb).
///
/// Each test waits for the idle page to be throttled, stops the content
/// process so the call cannot finish, and then watches the process's task
/// priority while the call is pending. That is deterministic on a quiet Mac:
/// no load has to be imitated and nothing races a threshold — an unheld call
/// leaves the priority where the throttle put it for as long as it waits.
@Suite("PageHost foreground hold", .serialized)
struct PageHostSchedulingTests {
    /// The calls that take no foreground activity of their own.
    enum Call: String, CaseIterable, CustomTestStringConvertible {
        case snapshot
        case archive
        case pdf

        var testDescription: String {
            rawValue
        }

        /// Makes the call, discarding its answer.
        @MainActor
        func make(on host: PageHost) async throws {
            switch self {
            case .snapshot:
                _ = try await host.snapshot(WKSnapshotConfiguration())
            case .archive:
                _ = try await host.execute(ArchiveOperation())
            case .pdf:
                _ = try await host.execute(PDFOperation())
            }
        }
    }

    /// How long a priority is waited for before the wait gives up. An upper
    /// bound only — a green run ends as soon as the priority moves.
    private static let ceiling: TimeInterval = 10

    /// The host's load and call budgets in these tests.
    private static let callBudget: TimeInterval = 20

    @Test(arguments: Call.allCases)
    @MainActor
    func `a call on an idle page lifts it to the priority an evaluate runs at`(call: Call) async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            // Budgets well short of the defaults: an unheld call on a loaded
            // machine is not answered at all, and the red should say so
            // without costing a minute per case.
            var options = LoadOptions()
            options.budget = Self.callBudget
            options.callBudget = Self.callBudget
            let host = PageHost(options: options)
            _ = try await host.load(#require(URL(string: FixturePage.staticText.fileName, relativeTo: base)))
            _ = try await host.evaluate("return 1;")
            let pid: pid_t = try #require(Self.contentProcessIdentifier(of: host.webView))
            let called: Int32 = try #require(Self.basePriority(of: pid))

            let throttled: Bool = await Self.waitUntil { (Self.basePriority(of: pid) ?? called) < called }
            try #require(
                throttled,
                "WebKit no longer throttles an idle page (priority stayed \(called)); the hold may be retired",
            )

            // Stopped, the page cannot answer, so the call stays pending for
            // as long as the priority is watched.
            kill(pid, SIGSTOP)
            let pending = Task { @MainActor in try await call.make(on: host) }
            let lifted: Bool = await Self.waitUntil { (Self.basePriority(of: pid) ?? 0) >= called }
            let during: Int32? = Self.basePriority(of: pid)
            kill(pid, SIGCONT)

            #expect(lifted, "a pending \(call) left the page at priority \(during.map(String.init) ?? "?"), not \(called)")
            try await pending.value
        }
    }

    /// Polls `condition` until it holds or ``ceiling`` passes.
    @MainActor
    private static func waitUntil(_ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(ceiling)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    /// The content process behind `webView`, through the SPI WebKit's own
    /// tests use. Test-only: nothing in `Sources/` needs the pid.
    @MainActor
    private static func contentProcessIdentifier(of webView: WKWebView) -> pid_t? {
        (webView.value(forKey: "_webProcessIdentifier") as? NSNumber)?.int32Value
    }

    /// The task's base scheduling priority — what `ps -M` shows per thread.
    private static func basePriority(of pid: pid_t) -> Int32? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return info.pti_priority
    }
}
