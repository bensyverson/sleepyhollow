import Foundation
import SleepyHollow
import Testing

@Suite("ShotVariantIndex")
struct ShotVariantIndexTests {
    @Test func `an entry describes the render a file holds`() {
        let plan = ShotPlan(sizes: [
            ViewportSize(width: 390, height: 800),
            ViewportSize(width: 1280, height: 800),
        ])
        let index = ShotVariantIndex(
            base: "/tmp/s.png",
            renders: [(plan.variants[0], .compositor), (plan.variants[1], .snapshot(.video))],
        )
        #expect(index.variants.count == 2)
        #expect(index.variants[0].file == "/tmp/s-390.png")
        #expect(index.variants[0].width == 390)
        #expect(index.variants[0].height == 800)
        #expect(index.variants[0].scale == 1)
        #expect(index.variants[0].theme == .light)
        #expect(index.variants[1].file == "/tmp/s-1280.png")
        #expect(index.variants[1].width == 1280)
        #expect(index.variants[0].renderer == .compositor)
        #expect(index.variants[1].renderer == .snapshot(.video))
    }

    @Test func `the index round-trips as the JSON an agent reads`() throws {
        let plan = try ShotPlan(scales: [ShotScale.one, ShotScale(factor: 2)], themes: [.dark])
        let index = ShotVariantIndex(base: "shot.png", renders: plan.variants.map { ($0, .compositor) })
        let data = try JSONEncoder().encode(index)
        let decoded = try JSONDecoder().decode(ShotVariantIndex.self, from: data)
        #expect(decoded == index)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("shot@2x.png"))
        #expect(text.contains("dark"))
        #expect(text.contains("compositor"))
    }
}
