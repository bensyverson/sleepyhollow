import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("Wire inventory")
struct WireInventoryTests {
    @Test
    @MainActor
    func `the main frame leads the inventory, with the status only it can have`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let url = URL(string: "observe-inventory.html", relativeTo: base)!
            let host = PageHost(options: LoadOptions().recordingWire())
            _ = try await host.load(url)
            let log: WireLog = try await host.execute(WireOperation())
            let first: ResourceEntry = try #require(log.inventory.first)
            #expect(first.initiatorType == "navigation")
            #expect(first.url == url.absoluteString)
            #expect(first.httpStatus == 200)
        }
    }

    @Test
    @MainActor
    func `subresources are listed with the fields WebKit provides`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions().recordingWire())
            _ = try await host.load(URL(string: "observe-inventory.html", relativeTo: base)!)
            let log: WireLog = try await host.execute(WireOperation())
            let types: Set<String> = Set(log.inventory.map(\.initiatorType))
            #expect(types.isSuperset(of: ["navigation", "link", "script", "img", "xmlhttprequest"]))

            let script: ResourceEntry = try #require(log.inventory.first { $0.url.hasSuffix("/script.js") })
            #expect(script.duration >= 0)
            #expect(script.isCrossOrigin == false)
            // Same-origin sizes need Safari >= 16.4; every WebKit this project
            // targets on a patched machine reports them.
            #expect(script.decodedBodySize != nil)
            #expect(script.encodedBodySize != nil)
            #expect(script.transferSize != nil)
            // Same-origin timing detail is not gated.
            #expect(script.timing?.responseEnd != nil)
        }
    }

    @Test
    @MainActor
    func `a subresource never carries an HTTP status — the platform has none`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions().recordingWire())
            _ = try await host.load(URL(string: "observe-inventory.html", relativeTo: base)!)
            let log: WireLog = try await host.execute(WireOperation())
            let subresources: [ResourceEntry] = log.inventory.filter { $0.initiatorType != "navigation" }
            #expect(!subresources.isEmpty)
            #expect(subresources.allSatisfy { $0.httpStatus == nil })
        }
    }

    @Test
    @MainActor
    func `cross-origin sizes are absent, not a misleading zero`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            try await FixtureServer.withRunningOnMainActor { _, otherBase in
                var components = URLComponents(
                    url: URL(string: "observe-inventory.html", relativeTo: base)!,
                    resolvingAgainstBaseURL: true,
                )!
                components.queryItems = [URLQueryItem(name: "crossOrigin", value: otherBase.absoluteString)]
                let host = PageHost(options: LoadOptions().recordingWire())
                _ = try await host.load(components.url!)
                let log: WireLog = try await host.execute(WireOperation())

                let foreign: ResourceEntry = try #require(
                    log.inventory.first { $0.url.hasPrefix(otherBase.absoluteString) },
                )
                #expect(foreign.isCrossOrigin)
                #expect(foreign.transferSize == nil)
                #expect(foreign.encodedBodySize == nil)
                #expect(foreign.decodedBodySize == nil)
                #expect(foreign.httpStatus == nil)
                // What was requested is still complete: URL, type and duration.
                #expect(foreign.initiatorType == "img")
                #expect(foreign.duration >= 0)
            }
        }
    }
}
