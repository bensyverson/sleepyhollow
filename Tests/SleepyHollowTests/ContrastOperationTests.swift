import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// `ContrastOperation` against the two contrast fixtures: the SVG sub-label
/// the tool must catch, the same grey passing at large sizes and failing at
/// small ones, the background-image honesty gap, and what `--selector` and
/// `--min` change.
@Suite("ContrastOperation")
struct ContrastOperationTests {
    @MainActor
    private func report(
        _ fixture: String,
        minimum: ContrastMinimum = .wcagAA,
        selector: String? = nil,
        base: URL,
    ) async throws -> ContrastReport {
        let host = PageHost()
        _ = try await host.load(URL(string: fixture, relativeTo: base)!)
        return try await host.execute(ContrastOperation(minimum: minimum, selector: selector))
    }

    @Test
    @MainActor
    func `the SVG sub-label at 2point9 to 1 is a failure`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: ContrastReport = try await report("contrast.html", base: base)
            let label: ContrastReport.Finding = try #require(
                report.failures.first { $0.path.contains("sub-label") },
            )
            #expect(label.text.contains("Updated 3 minutes ago"))
            #expect(label.background == "#262626")
            #expect(label.foreground == "#6c6c6c")
            let ratio: Double = try #require(label.ratio)
            #expect(abs(ratio - 2.88) < 0.05)
            #expect(label.required == 4.5)
            #expect(label.isLargeText == false)
        }
    }

    @Test
    @MainActor
    func `SVG text on a light shape passes, proving the shape is the background`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: ContrastReport = try await report("contrast.html", base: base)
            // White-on-#262626 inside the same <svg>: if the walk fell back to
            // the page's white body background this would read 1:1 and fail.
            #expect(!report.failures.contains { $0.text.contains("Panel title") })
        }
    }

    @Test
    @MainActor
    func `the fixed fixture has no failures`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: ContrastReport = try await report("contrast-fixed.html", base: base)
            #expect(report.failures.isEmpty)
            #expect(report.passes)
            #expect(report.checked > 0)
        }
    }

    @Test
    @MainActor
    func `text over a background image is unmeasured, never a ratio`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: ContrastReport = try await report("contrast.html", base: base)
            let gradient: ContrastReport.Finding = try #require(
                report.unmeasured.first { $0.text.contains("Text over a gradient") },
            )
            #expect(gradient.ratio == nil)
            #expect(gradient.background == nil)
            #expect(gradient.reason == "image")
            #expect(!report.failures.contains { $0.text.contains("Text over a gradient") })
        }
    }

    @Test
    @MainActor
    func `an unmeasured background alone is not a failure`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: ContrastReport = try await report("contrast-fixed.html", base: base)
            #expect(!report.unmeasured.isEmpty)
            #expect(report.passes)
        }
    }

    @Test
    @MainActor
    func `the same grey passes at 24px and fails at 14px`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: ContrastReport = try await report("contrast.html", base: base)
            #expect(!report.failures.contains { $0.text.contains("Large heading") })
            let small: ContrastReport.Finding = try #require(
                report.failures.first { $0.text.contains("Small grey text") },
            )
            #expect(small.isLargeText == false)
            #expect(small.required == 4.5)
        }
    }

    @Test
    @MainActor
    func `19px bold counts as large text`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: ContrastReport = try await report("contrast.html", base: base)
            #expect(!report.failures.contains { $0.text.contains("Bold nineteen pixels") })
        }
    }

    @Test
    @MainActor
    func `hidden text is skipped rather than measured`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: ContrastReport = try await report("contrast.html", base: base)
            #expect(report.skipped >= 3)
            for hidden in ["display none", "visibility", "opacity"] {
                #expect(!report.failures.contains { $0.text.contains(hidden) })
                #expect(!report.unmeasured.contains { $0.text.contains(hidden) })
            }
        }
    }

    @Test
    @MainActor
    func `--selector scopes the walk to one subtree`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: ContrastReport = try await report("contrast.html", selector: "#panel", base: base)
            #expect(report.failures.count == 1)
            #expect(report.failures[0].path.contains("sub-label"))
        }
    }

    @Test
    @MainActor
    func `a selector matching nothing is a usage error, not an empty pass`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let thrown: SleepyError? = await #expect(throws: SleepyError.self) {
                _ = try await report("contrast.html", selector: "#nowhere", base: base)
            }
            #expect(thrown?.kind == .usage)
        }
    }

    @Test
    @MainActor
    func `wcag-aaa raises the bar on text that clears AA`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let aa: ContrastReport = try await report("contrast-fixed.html", base: base)
            #expect(aa.failures.isEmpty)
            let aaa: ContrastReport = try await report("contrast-fixed.html", minimum: .wcagAAA, base: base)
            #expect(!aaa.failures.isEmpty)
            #expect(aaa.failures.allSatisfy { $0.required == ($0.isLargeText ? 4.5 : 7.0) })
        }
    }

    @Test
    @MainActor
    func `a bare ratio applies one bar to every size`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let report: ContrastReport = try await report("contrast.html", minimum: .ratio(2.0), base: base)
            #expect(report.failures.isEmpty)
            #expect(report.minimum == .ratio(2.0))
        }
    }
}
