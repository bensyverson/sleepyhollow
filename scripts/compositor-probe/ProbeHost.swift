import AppKit
import WebKit

/// How the probe hosts a page: today's windowless view, or a parked window,
/// optionally live (the occlusion SPI) and optionally claiming to be key.
struct HostKind: CustomStringConvertible {
    enum Window { case none, hidden, live }
    var window: Window
    var key: Bool = false
    var firstResponder: Bool = false

    var description: String {
        switch window {
        case .none: return "windowless"
        case .hidden, .live:
            var name = window == .live ? "live" : "hidden"
            if key { name += "+key" }
            if firstResponder { name += "+firstResponder" }
            return name
        }
    }

    static let windowless = HostKind(window: .none)
    static let hidden = HostKind(window: .hidden)
    static let live = HostKind(window: .live)
}

/// A window that says it is key and main without ever being made so — the
/// candidate fix for inactive-looking native controls. AppKit never sends it
/// a become-key notification.
final class KeyClaimingWindow: NSWindow {
    override var isKeyWindow: Bool {
        true
    }

    override var isMainWindow: Bool {
        true
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }
}

/// Builds a PageHost hosted as `kind`, the way `OffscreenWindow` does it
/// (parked, borderless, `.prohibited` activation) but with the probe's own
/// window class.
@MainActor
func makeHost(_ kind: HostKind, size: ViewportSize, wait: WaitCondition? = nil) -> (PageHost, NSWindow?) {
    let options = LoadOptions(size: size, fileAccessRoot: nil, wait: wait, budget: 60, callBudget: 60)
    let host = PageHost(options: options)
    guard kind.window != .none else { return (host, nil) }
    _ = NSApplication.shared.setActivationPolicy(.prohibited)
    let frame = CGRect(origin: OffscreenWindow.parkedOrigin, size: host.webView.frame.size)
    let window: NSWindow = kind.key
        ? KeyClaimingWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        : NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    // PROBE_WINDOW_SRGB=1: pin the window's color space, which WebKit paints
    // its tiles in, instead of inheriting the main display's (Display P3).
    if ProcessInfo.processInfo.environment["PROBE_WINDOW_SRGB"] == "1" {
        window.colorSpace = NSColorSpace.sRGB
    }
    window.hasShadow = false
    window.ignoresMouseEvents = true
    window.contentView = host.webView
    window.orderBack(nil)
    window.setFrameOrigin(OffscreenWindow.parkedOrigin)
    if kind.window == .live {
        let selector = NSSelectorFromString("_setWindowOcclusionDetectionEnabled:")
        typealias Setter = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        unsafeBitCast(host.webView.method(for: selector), to: Setter.self)(host.webView, selector, ObjCBool(false))
    }
    if kind.firstResponder {
        window.makeFirstResponder(host.webView)
    }
    return (host, window)
}

/// The probe's fixture directory, as a file URL.
func fixture(_ name: String, query: String? = nil) -> URL {
    let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["PROBE_FIXTURES"] ?? "scripts/compositor-probe/fixtures")
    var components = URLComponents(url: dir.appendingPathComponent(name).standardizedFileURL, resolvingAgainstBaseURL: false)!
    components.query = query
    return components.url!
}

/// takeSnapshot through the shipping shot pipeline (`ShotOperation.render`),
/// at `scale` device pixels per CSS px.
@MainActor
func snapshotCapture(_ host: PageHost, scale: Int) async throws -> (CGImage, Double) {
    let start = CACurrentMediaTime()
    let capture = try await ShotOperation(region: .viewport, scale: ShotScale(factor: scale)).render(on: host)
    return (capture.image, (CACurrentMediaTime() - start) * 1000)
}
