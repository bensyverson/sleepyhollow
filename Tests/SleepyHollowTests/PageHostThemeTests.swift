import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("PageHost theme")
struct PageHostThemeTests {
    @MainActor
    private func resolvedMode(theme: ColorTheme, base: URL) async throws -> String {
        var options = LoadOptions()
        options.theme = theme
        let host = PageHost(options: options)
        _ = try await host.load(URL(string: "theme.html", relativeTo: base)!)
        return try await host.evaluate("return document.getElementById('mode').textContent;")
    }

    @Test
    @MainActor
    func `light and dark resolve prefers-color-scheme differently`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let light: String = try await resolvedMode(theme: .light, base: base)
            let dark: String = try await resolvedMode(theme: .dark, base: base)
            #expect(light == "\"light\"")
            #expect(dark == "\"dark\"")
            #expect(light != dark)
        }
    }

    @Test
    @MainActor
    func `light is the default`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "theme.html", relativeTo: base)!)
            let mode: String = try await host.evaluate("return document.getElementById('mode').textContent;")
            #expect(mode == "\"light\"")
        }
    }
}
