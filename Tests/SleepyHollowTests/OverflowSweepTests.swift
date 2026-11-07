import Foundation
import SleepyHollow
import Testing
import TestSupport

/// `OverflowSweep`: the spill question asked at every breakpoint in one call —
/// one load per size, a report per size in the order given, and a sweep that
/// passes only when every size does.
@Suite("OverflowSweep")
struct OverflowSweepTests {
    private static let narrow = ViewportSize(width: 390, height: 800)
    private static let wide = ViewportSize(width: 1280, height: 900)

    private static var budgeted: LoadOptions {
        var options = LoadOptions()
        options.budget = TestSupport.livenessBudget
        return options
    }

    @Test func `only more than one size is a sweep`() {
        #expect(!OverflowSweep(sizes: []).isSweep)
        #expect(!OverflowSweep(sizes: [Self.narrow]).isSweep)
        #expect(OverflowSweep(sizes: [Self.narrow, Self.wide]).isSweep)
    }

    @Test
    @MainActor
    func `each size gets its own load and its own report, in the order given`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let url = URL(string: "overflow-breakpoint.html", relativeTo: base)!
            let report: OverflowSweepReport = try await OverflowSweep(sizes: [Self.narrow, Self.wide])
                .run(url, options: Self.budgeted, group: HostGroup())
            #expect(report.sizes.map(\.width) == [390, 1280])
            #expect(report.sizes.map(\.height) == [800, 900])
            let narrow: OverflowSweepReport.Entry = try #require(report.sizes.first)
            let wide: OverflowSweepReport.Entry = try #require(report.sizes.last)
            // Measured at its own viewport, not the first one's.
            #expect(narrow.report.viewportWidth == 390)
            #expect(wide.report.viewportWidth == 1280)
            #expect(narrow.report.violations.contains { $0.path.contains("hero") })
            #expect(wide.report.passes)
            #expect(!report.passes, "a page that spills at any size fails the sweep")
        }
    }

    @Test
    @MainActor
    func `a page that holds its width at every size passes, scroll containers listed per size`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let url = URL(string: "overflow-scroll.html", relativeTo: base)!
            let report: OverflowSweepReport = try await OverflowSweep(sizes: [Self.narrow, Self.wide])
                .run(url, options: Self.budgeted, group: HostGroup())
            #expect(report.passes)
            #expect(report.sizes.count == 2)
            for entry in report.sizes {
                #expect(entry.report.scrollContainers.contains { $0.path.contains("scroller") })
            }
        }
    }

    @Test func `the sweep encodes a sizes array, each entry the single-size report under its viewport`() throws {
        let single = OverflowReport(viewportWidth: 390, documentWidth: 390, violations: [], scrollContainers: [])
        let report = OverflowSweepReport(sizes: [
            OverflowSweepReport.Entry(size: Self.narrow, report: single),
        ])
        let data: Data = try JSONEncoder().encode(report)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let entries = try #require(object["sizes"] as? [[String: Any]])
        let entry = try #require(entries.first)
        #expect(entry["width"] as? Int == 390)
        #expect(entry["height"] as? Int == 800)
        let nested = try #require(entry["report"] as? [String: Any])
        #expect(nested["viewportWidth"] as? Double == 390)
        #expect(nested["violations"] as? [Any] != nil)
    }
}
