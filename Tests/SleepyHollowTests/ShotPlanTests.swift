import Foundation
import SleepyHollow
import Testing

@Suite("ShotPlan")
struct ShotPlanTests {
    @Test func `an empty plan is one default render with no suffix`() throws {
        let plan = ShotPlan()
        #expect(plan.variants.count == 1)
        let only = try #require(plan.variants.first)
        #expect(only.size == ViewportSize.default)
        #expect(only.scale == ShotScale.one)
        #expect(only.theme == ColorTheme.light)
        #expect(only.suffix.isEmpty)
        #expect(plan.isSweep == false)
    }

    @Test func `a single value on every axis still suffixes nothing`() throws {
        let plan = try ShotPlan(
            sizes: [ViewportSize(width: 480, height: 800)],
            scales: [ShotScale(factor: 2)],
            themes: [.dark],
        )
        #expect(plan.variants.count == 1)
        #expect(plan.variants[0].suffix.isEmpty)
        #expect(plan.variants[0].file(base: "header.png") == "header.png")
        #expect(plan.isSweep == false)
    }

    @Test func `two sizes suffix the width alone`() {
        let plan = ShotPlan(sizes: [
            ViewportSize(width: 480, height: 800),
            ViewportSize(width: 1280, height: 800),
        ])
        #expect(plan.variants.map(\.suffix) == ["-480", "-1280"])
        #expect(plan.variants.map { $0.file(base: "header.png") } == ["header-480.png", "header-1280.png"])
        #expect(plan.isSweep)
    }

    @Test func `sizes sharing a width keep their heights in the name`() {
        let plan = ShotPlan(sizes: [
            ViewportSize(width: 480, height: 800),
            ViewportSize(width: 480, height: 1600),
        ])
        #expect(plan.variants.map(\.suffix) == ["-480x800", "-480x1600"])
    }

    @Test func `a varying scale suffixes every file, one times included`() throws {
        let plan = try ShotPlan(scales: [ShotScale.one, ShotScale(factor: 2)])
        #expect(plan.variants.map(\.suffix) == ["@1x", "@2x"])
    }

    @Test func `a varying theme suffixes the theme's name`() {
        let plan = ShotPlan(themes: [.light, .dark])
        #expect(plan.variants.map(\.suffix) == ["-light", "-dark"])
    }

    @Test func `the cross product runs size outermost, then theme, then scale`() throws {
        let plan = try ShotPlan(
            sizes: [ViewportSize(width: 480, height: 800), ViewportSize(width: 1280, height: 800)],
            scales: [ShotScale.one, ShotScale(factor: 2)],
            themes: [.light, .dark],
        )
        #expect(plan.variants.count == 8)
        // The suffix names size, scale, theme; the sweep runs scale innermost
        // because scale alone needs no page load of its own.
        #expect(plan.variants.map { $0.file(base: "header.png") } == [
            "header-480@1x-light.png", "header-480@2x-light.png",
            "header-480@1x-dark.png", "header-480@2x-dark.png",
            "header-1280@1x-light.png", "header-1280@2x-light.png",
            "header-1280@1x-dark.png", "header-1280@2x-dark.png",
        ])
    }

    @Test func `variants that differ only in density share one page load`() throws {
        let plan = try ShotPlan(
            sizes: [ViewportSize(width: 480, height: 800), ViewportSize(width: 1280, height: 800)],
            scales: [ShotScale.one, ShotScale(factor: 2)],
            themes: [.light, .dark],
        )
        #expect(plan.loads.count == 4)
        #expect(plan.loads.allSatisfy { $0.count == 2 })
        #expect(plan.loads[0].map(\.scale.factor) == [1, 2])
        #expect(plan.loads[1].map(\.theme) == [.dark, .dark])
    }

    @Test func `every size and theme pair is its own load`() {
        let plan = ShotPlan(
            sizes: [ViewportSize(width: 480, height: 800), ViewportSize(width: 1280, height: 800)],
            themes: [.light, .dark],
        )
        #expect(plan.loads.count == 4)
        #expect(plan.loads.allSatisfy { $0.count == 1 })
    }

    @Test func `only the axes that vary reach the file name`() throws {
        let plan = try ShotPlan(
            sizes: [ViewportSize(width: 480, height: 800), ViewportSize(width: 1280, height: 800)],
            scales: [ShotScale(factor: 2)],
            themes: [.dark],
        )
        #expect(plan.variants.map { $0.file(base: "header.png") } == ["header-480.png", "header-1280.png"])
    }

    @Test func `a base path with no extension keeps none`() {
        let plan = ShotPlan(themes: [.light, .dark])
        #expect(plan.variants.map { $0.file(base: "/tmp/shots/header") } == [
            "/tmp/shots/header-light",
            "/tmp/shots/header-dark",
        ])
    }

    @Test func `a variant labels itself with the axes that vary`() {
        let plan = ShotPlan(
            sizes: [ViewportSize(width: 390, height: 800), ViewportSize(width: 1280, height: 800)],
            themes: [.light, .dark],
        )
        #expect(plan.variants.map(\.label) == [
            "390×800 light", "390×800 dark", "1280×800 light", "1280×800 dark",
        ])
    }

    @Test func `a lone variant labels itself with its size anyway`() {
        #expect(ShotPlan().variants[0].label == "1280×800")
    }
}
