import CoreGraphics
import Foundation
import SleepyHollow
import Testing
import TestSupport

@Suite("ShotOperation")
struct CaptureShotOperationTests {
    @Test
    @MainActor
    func `a viewport shot has the host's viewport pixel size`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let output = try await host.execute(ShotOperation())
            let dimensions = try #require(pixelDimensions(ofPNG: output.png))
            #expect(dimensions.width == LoadOptions().size.width)
            #expect(dimensions.height == LoadOptions().size.height)
        }
    }

    @Test
    @MainActor
    func `a full-page shot is taller than the viewport`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let output = try await host.execute(ShotOperation(fullPage: true))
            let dimensions = try #require(pixelDimensions(ofPNG: output.png))
            #expect(dimensions.height > LoadOptions().size.height)
            // The fixture's body is 3000px tall — the capture should reach it.
            #expect(dimensions.height >= 2900)
        }
    }

    @Test
    @MainActor
    func `a full-page shot restores the host's original viewport afterward`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            _ = try await host.execute(ShotOperation(fullPage: true))
            #expect(host.webView.frame.height == CGFloat(LoadOptions().size.height))
        }
    }

    @Test
    @MainActor
    func `an element shot is sized to the element's rect and differs from the viewport shot`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let viewport = try await host.execute(ShotOperation())
            let element = try await host.execute(ShotOperation(element: "#target"))
            let viewportSize = try #require(pixelDimensions(ofPNG: viewport.png))
            let elementSize = try #require(pixelDimensions(ofPNG: element.png))
            // Fixture #target is 200x150 — below the fold in the viewport shot.
            #expect(abs(elementSize.width - 200) <= 2)
            #expect(abs(elementSize.height - 150) <= 2)
            #expect(elementSize != viewportSize)
        }
    }

    @Test
    @MainActor
    func `element capture reaches a target below the fold`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            // #target sits at top:2400px in a 3000px document — well outside
            // the default 800pt-tall viewport.
            let output = try await host.execute(ShotOperation(element: "#target"))
            #expect(!output.png.isEmpty)
        }
    }

    /// Originally asserted a shot-private ElementNotFoundError; the integrator
    /// replaced that seam with Core's clean-negative kind so every verb shares
    /// one exit-1 mechanism.
    @Test
    @MainActor
    func `an unmatched selector is a clean negative`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            do {
                _ = try await host.execute(ShotOperation(element: "#does-not-exist"))
                Issue.record("expected a clean-negative SleepyError")
            } catch let error as SleepyError {
                #expect(error.kind == .negative)
                #expect(error.exitStatus == ExitStatus.negative)
                #expect(error.message.contains("#does-not-exist"))
            }
        }
    }

    @Test
    @MainActor
    func `an unmatched selector restores the host's original viewport`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            _ = try? await host.execute(ShotOperation(element: "#does-not-exist"))
            #expect(host.webView.frame.height == CGFloat(LoadOptions().size.height))
        }
    }

    @Test func `the operation is Friendly and round-trips through its envelope`() throws {
        #expect(ShotOperation.kind == "shot")
        let envelope = try OperationEnvelope(ShotOperation(element: "#target", fullPage: true))
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(OperationEnvelope.self, from: data)
        #expect(decoded.kind == ShotOperation.kind)
        var registry = OperationRegistry()
        registry.register(ShotOperation.self)
        let operation = try registry.decode(decoded)
        #expect(operation is ShotOperation)
    }
}
