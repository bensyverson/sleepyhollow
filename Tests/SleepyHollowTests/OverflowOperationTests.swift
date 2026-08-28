import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `OverflowOperation`: the wide table that scrolls inside its own container
/// is not a violation, the paragraph a 200-character token spills out of is,
/// and `body { overflow-x: hidden }` does not hide either from the check.
@Suite("OverflowOperation")
struct OverflowOperationTests {
    @MainActor
    private func report(_ fixture: String, size: ViewportSize? = nil, base: URL) async throws -> OverflowReport {
        let options: LoadOptions = size.map { LoadOptions(size: $0) } ?? LoadOptions()
        let host = PageHost(options: options)
        _ = try await host.load(URL(string: fixture, relativeTo: base)!)
        return try await host.execute(OverflowOperation())
    }

    @Test
    @MainActor
    func `a scrolling container's wide table is listed, not flagged`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: OverflowReport = try await report("overflow-scroll.html", base: base)
            #expect(report.violations.isEmpty)
            #expect(report.passes)
            let scroller: OverflowReport.ScrollContainer = try #require(report.scrollContainers.first)
            #expect(scroller.path.contains("scroller"))
            #expect(scroller.scrollWidth > scroller.clientWidth)
            #expect(scroller.scrollBy > 1000)
            #expect(!report.scrollContainers.contains { $0.path.contains("wide-table") })
        }
    }

    @Test
    @MainActor
    func `an unbreakable string spills its paragraph and is a violation`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: OverflowReport = try await report("overflow-spill.html", base: base)
            #expect(!report.passes)
            let violation: OverflowReport.Violation = try #require(report.violations.first)
            #expect(violation.path.contains("token"))
            #expect(violation.right > report.viewportWidth)
            #expect(violation.overflowBy > 0)
            #expect(violation.cause == .content)
        }
    }

    @Test
    @MainActor
    func `overflow-x hidden does not hide the spill`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: OverflowReport = try await report("overflow-spill.html", base: base)
            // The naive check — documentWidth > viewportWidth — is exactly
            // what `overflow-x: hidden` silences; the violation is still found.
            #expect(report.documentWidth <= report.viewportWidth)
            #expect(!report.violations.isEmpty)
        }
    }

    @Test
    @MainActor
    func `only the innermost spilling element is named`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: OverflowReport = try await report("overflow-spill.html", base: base)
            #expect(report.violations.count == 1)
            #expect(!report.violations.contains { $0.path == "body" })
        }
    }

    @Test
    @MainActor
    func `a page that fits has nothing to report`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: OverflowReport = try await report("static.html", base: base)
            #expect(report.violations.isEmpty)
            #expect(report.scrollContainers.isEmpty)
            #expect(report.viewportWidth == 1280)
        }
    }

    @Test
    @MainActor
    func `a narrower viewport is what the report is measured against`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let narrow: OverflowReport = try await report(
                "overflow-scroll.html",
                size: ViewportSize(width: 390, height: 800),
                base: base,
            )
            #expect(narrow.viewportWidth == 390)
            #expect(narrow.violations.isEmpty)
            #expect(!narrow.scrollContainers.isEmpty)
        }
    }
}
