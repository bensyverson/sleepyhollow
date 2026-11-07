import AppKit
import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// Which renderer a shot uses, and that it always says so.
///
/// The compositor draws a `<video>` blank — a remote-hosted layer it cannot
/// see into — and raises nothing, so a shot whose area holds one falls back
/// to `takeSnapshot`, and a host with no live window has no composited layer
/// tree to render at all. Either way the result names the renderer and why,
/// and a fallback still reports the CSS 3D it draws flat.
@Suite("ShotOperation renderer choice")
struct CaptureShotRendererTests {
    /// `compositor-video.html` with a real, playing movie beside it, loaded
    /// from a temporary directory the caller removes.
    @MainActor
    private func loadPlayingVideo(on host: PageHost) async throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sleepy-video-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let page = directory.appendingPathComponent("compositor-video.html")
        try FileManager.default.copyItem(
            at: TestSupport.fixturesDirectory.appendingPathComponent("compositor-video.html"),
            to: page,
        )
        try await MovieFixture.writeMagenta(to: directory.appendingPathComponent("magenta.mp4"))
        var components = try #require(URLComponents(url: page, resolvingAgainstBaseURL: false))
        components.query = "video=magenta.mp4"
        _ = try await host.load(#require(components.url))
        return directory
    }

    /// The movie's magenta as WebKit draws it: H.264's color conversion
    /// moves `MovieFixture.color` to about (232, 49, 247).
    private static let magenta: PixelGrid.RGB = (240, 40, 250)

    private static let videoHostOptions = LoadOptions(
        size: ViewportSize(width: 800, height: 300),
        wait: .selector("body[data-ready]"),
    )

    @Test
    @MainActor
    func `a live host renders through the compositor and says so`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 1000, height: 260)))
            _ = try await host.load(#require(URL(string: "compositor-t3d.html", relativeTo: base)))
            let output = try await host.execute(ShotOperation())
            #expect(output.renderer == .compositor)
            // The compositor draws CSS 3D faithfully, so nothing is flagged.
            #expect(output.flattened3D.isEmpty)
        }
    }

    @Test
    @MainActor
    func `video in the shot area falls back to takeSnapshot, which draws it`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, _ in
            let host = PageHost(options: Self.videoHostOptions)
            let directory = try await loadPlayingVideo(on: host)
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = try await host.execute(ShotOperation())
            #expect(output.renderer == .snapshot(.video))
            let first = try #require(output.images.first)
            let image = try #require(decodedImage(ofPNG: first.png))
            let video = PixelGrid(image).shape(of: Self.magenta, in: CGRect(x: 20, y: 20, width: 240, height: 140), tolerance: 40)
            #expect(video.count > 240 * 140 / 2, "the video's frame is missing from the fallback")
            // The fallback draws 3D flat, and says which.
            #expect(output.flattened3D.map(\.path) == ["div#tilted"])
        }
    }

    /// The reason for the fallback, kept as a test: if WebKit starts
    /// drawing video into the compositor's tree, this goes red and the
    /// fallback can go.
    @Test
    @MainActor
    func `the compositor draws a playing video blank`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, _ in
            let host = PageHost(options: Self.videoHostOptions)
            let directory = try await loadPlayingVideo(on: host)
            defer { try? FileManager.default.removeItem(at: directory) }
            let image = try await host.compositorImage(of: CGRect(x: 20, y: 20, width: 240, height: 140), scale: 1)
            #expect(PixelGrid(image).shape(of: Self.magenta, tolerance: 40).count == 0)
        }
    }

    @Test
    @MainActor
    func `a rect that leaves the video out stays on the compositor`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 800, height: 300)))
            _ = try await host.load(#require(URL(string: "compositor-video.html", relativeTo: base)))
            let away = try await host.execute(ShotOperation(region: .element("#tilted")))
            #expect(away.renderer == .compositor)
            #expect(away.flattened3D.isEmpty)
            let touching = try await host.execute(ShotOperation(region: .rect(CGRect(x: 250, y: 0, width: 300, height: 300))))
            #expect(touching.renderer == .snapshot(.video))
        }
    }

    @Test
    @MainActor
    func `a hidden or unrendered video does not force the fallback`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 800, height: 300)))
            _ = try await host.load(#require(URL(string: "compositor-video.html", relativeTo: base)))
            _ = try await host.evaluate("document.getElementById('video').style.visibility = 'hidden'; return 1;")
            #expect(try await host.execute(ShotOperation()).renderer == .compositor)
            _ = try await host.evaluate("document.getElementById('video').style.display = 'none'; return 1;")
            #expect(try await host.execute(ShotOperation()).renderer == .compositor)
        }
    }

    @Test
    @MainActor
    func `a windowless host falls back and names why`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 1000, height: 260)), hosting: .windowless)
            _ = try await host.load(#require(URL(string: "compositor-t3d.html", relativeTo: base)))
            let output = try await host.execute(ShotOperation())
            #expect(output.renderer == .snapshot(.windowless))
            #expect(!output.flattened3D.isEmpty)
        }
    }

    @Test
    @MainActor
    func `the render stage and every readout stage carry the renderer`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let host = PageHost(options: LoadOptions(size: ViewportSize(width: 400, height: 300)))
            _ = try await host.load(#require(URL(string: "capture-tall.html", relativeTo: base)))
            let capture = try await ShotOperation(region: .fullPage).render(on: host)
            #expect(capture.renderer == .compositor)
            let strips = try ShotTile(height: 600).applied(to: capture)
            #expect(strips.allSatisfy { $0.renderer == .compositor })
            #expect(try ShotFit(maxSize: 200).applied(to: capture).renderer == .compositor)
        }
    }

    @Test(arguments: [
        (ShotRenderer.compositor, #"{"name":"compositor"}"#),
        (ShotRenderer.snapshot(.video), #"{"fallback":"video","name":"snapshot"}"#),
        (ShotRenderer.snapshot(.windowless), #"{"fallback":"windowless","name":"snapshot"}"#),
    ])
    func `the renderer's wire shape is a name and, for a fallback, why`(renderer: ShotRenderer, json: String) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try String(data: encoder.encode(renderer), encoding: .utf8) == json)
        #expect(try JSONDecoder().decode(ShotRenderer.self, from: Data(json.utf8)) == renderer)
    }
}
