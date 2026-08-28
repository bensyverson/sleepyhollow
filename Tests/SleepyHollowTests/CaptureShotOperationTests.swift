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
            let dimensions = try #require(pixelDimensions(ofPNG: output.images[0].png))
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
            let output = try await host.execute(ShotOperation(region: .fullPage))
            let dimensions = try #require(pixelDimensions(ofPNG: output.images[0].png))
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
            _ = try await host.execute(ShotOperation(region: .fullPage))
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
            let element = try await host.execute(ShotOperation(region: .element("#target")))
            let viewportSize = try #require(pixelDimensions(ofPNG: viewport.images[0].png))
            let elementSize = try #require(pixelDimensions(ofPNG: element.images[0].png))
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
            let output = try await host.execute(ShotOperation(region: .element("#target")))
            #expect(!output.images[0].png.isEmpty)
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
                _ = try await host.execute(ShotOperation(region: .element("#does-not-exist")))
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
            _ = try? await host.execute(ShotOperation(region: .element("#does-not-exist")))
            #expect(host.webView.frame.height == CGFloat(LoadOptions().size.height))
        }
    }

    @Test
    @MainActor
    func `a display-none element is a clean negative naming its rect`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-zero-area.html", relativeTo: base)!)
            do {
                _ = try await host.execute(ShotOperation(region: .element("#hidden")))
                Issue.record("expected a clean-negative SleepyError")
            } catch let error as SleepyError {
                #expect(error.kind == .negative)
                #expect(error.exitStatus == ExitStatus.negative)
                #expect(error.message.contains("#hidden"))
                #expect(error.message.contains("0×0"))
            }
        }
    }

    @Test
    @MainActor
    func `an empty inline element with zero width is a clean negative`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-zero-area.html", relativeTo: base)!)
            do {
                _ = try await host.execute(ShotOperation(region: .element("#empty-inline")))
                Issue.record("expected a clean-negative SleepyError")
            } catch let error as SleepyError {
                #expect(error.kind == .negative)
                #expect(error.message.contains("#empty-inline"))
                #expect(error.message.contains("0×"))
            }
        }
    }

    @Test
    @MainActor
    func `a zero-area element restores the host's original viewport`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-zero-area.html", relativeTo: base)!)
            _ = try? await host.execute(ShotOperation(region: .element("#hidden")))
            #expect(host.webView.frame.height == CGFloat(LoadOptions().size.height))
        }
    }

    @Test
    @MainActor
    func `a laid-out element on the same page still captures`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-zero-area.html", relativeTo: base)!)
            let output = try await host.execute(ShotOperation(region: .element("#visible")))
            let dimensions = try #require(pixelDimensions(ofPNG: output.images[0].png))
            #expect(abs(dimensions.width - 200) <= 2)
            #expect(abs(dimensions.height - 150) <= 2)
        }
    }

    @Test
    @MainActor
    func `a rect shot has exactly the rect's pixel size and carries the rect back`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let rect = CGRect(x: 100, y: 2400, width: 200, height: 150)
            let output = try await host.execute(ShotOperation(region: .rect(rect)))
            let image = try #require(output.images.first)
            let dimensions = try #require(pixelDimensions(ofPNG: image.png))
            #expect(dimensions.width == 200)
            #expect(dimensions.height == 150)
            #expect(image.rect == rect)
            #expect(image.scale == 1)
        }
    }

    @Test
    @MainActor
    func `a rect below the viewport still captures painted content`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let byRect = try await host.execute(ShotOperation(region: .rect(CGRect(x: 100, y: 2400, width: 200, height: 150))))
            let byElement = try await host.execute(ShotOperation(region: .element("#target")))
            #expect(byRect.images[0].png == byElement.images[0].png)
        }
    }

    @Test
    @MainActor
    func `an element shot reports the element's rect in CSS px`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost()
            _ = try await host.load(URL(string: "capture-tall.html", relativeTo: base)!)
            let output = try await host.execute(ShotOperation(region: .element("#target")))
            #expect(output.images[0].rect == CGRect(x: 100, y: 2400, width: 200, height: 150))
        }
    }

    @Test func `the operation is Friendly and round-trips through its envelope`() throws {
        #expect(ShotOperation.kind == "shot")
        let envelope = try OperationEnvelope(ShotOperation(region: .rect(CGRect(x: 0, y: 850, width: 1280, height: 1285))))
        let data = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(OperationEnvelope.self, from: data)
        #expect(decoded.kind == ShotOperation.kind)
        var registry = OperationRegistry()
        registry.register(ShotOperation.self)
        let operation = try registry.decode(decoded)
        #expect(operation is ShotOperation)
    }
}
