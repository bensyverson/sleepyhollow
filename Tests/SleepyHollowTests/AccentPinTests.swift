import AppKit
import Foundation
@testable import SleepyHollow
import Testing
import TestSupport

/// The accent native controls draw in is pinned to the system default blue,
/// whatever this Mac's System Settings say (leaf `AuYtct`, criterion toY).
///
/// The lever is private: `-[NSApplication _setAccentColor:]` in this process,
/// which WebKit reads back through `_effectiveAccentColor` into every new
/// page's creation parameters and re-applies in the web content process
/// (`WebPageProxy::creationParameters`, `WebPage::setAccentColor`). These tests
/// go red if any link of that chain stops working.
///
/// `.serialized`, and the pin is restored before the suite's test returns:
/// the app accent is process-wide, so a page another test creates while the
/// accent is orange would draw orange controls.
@Suite("Accent pin", .serialized)
struct AccentPinTests {
    @Test
    @MainActor
    func `a host pins the app accent before its page exists`() {
        _ = PageHost(hosting: .windowless)
        #expect(AccentPin.isPinned)
    }

    @Test
    @MainActor
    func `the page draws controls in the pinned accent, not the machine's`() async throws {
        try await FixtureServer.withRunningOnMainActor { _, base in
            let url = try #require(URL(string: "controls-checked.html", relativeTo: base))
            defer { AccentPin.apply(AccentPin.pinned) }

            AccentPin.apply(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1))
            let orangeHost = PageHost()
            _ = try await orangeHost.load(url)
            let orange = try await Self.hues(of: orangeHost)

            AccentPin.apply(AccentPin.pinned)
            let blueHost = PageHost()
            _ = try await blueHost.load(url)
            let blue = try await Self.hues(of: blueHost)

            print("[accent] pinned orange: \(orange); pinned default: \(blue)")
            // If the page ignored the pin, both would draw the machine's own
            // accent and one of these two would fail.
            #expect(orange.orange > 300 && orange.blue == 0, "orange pin: \(orange)")
            #expect(blue.blue > 300 && blue.orange == 0, "default pin: \(blue)")
        }
    }

    @Test
    @MainActor
    func `doctor reports the accent pin`() {
        _ = PageHost(hosting: .windowless)
        let check = Doctor.checkAccentPin()
        #expect(check.status == .ok, "\(check.detail)")
    }

    /// Orange and blue pixel counts in a capture of `#box`.
    private struct Hues: CustomStringConvertible {
        var orange = 0
        var blue = 0

        var description: String {
            "orange \(orange), blue \(blue)"
        }
    }

    @MainActor
    private static func hues(of host: PageHost) async throws -> Hues {
        let capture = try await ShotOperation(region: .element("#box"), scale: ShotScale(factor: 1)).render(on: host)
        let image = capture.image
        var hues = Hues()
        for y in 0 ..< image.height {
            for x in 0 ..< image.width {
                guard let pixel = pixelColor(of: image, x: x, y: y) else { continue }
                let red = Int(pixel.red), green = Int(pixel.green), blue = Int(pixel.blue)
                if red > green + 20, green > blue + 20 {
                    hues.orange += 1
                } else if blue > red + 40, blue > green + 20 {
                    hues.blue += 1
                }
            }
        }
        return hues
    }
}
