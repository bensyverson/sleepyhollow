// Measures whether anything in the UI process can pin the accent and highlight
// colors WebKit draws active native controls in (job leaf AuYtct; findings in
// project/2026-11-06-compositor-capture.md question 7, "Measured" note).
//
//   xcrun swiftc -swift-version 5 scripts/accent-lever-probe.swift -o .build/accent-lever-probe
//   .build/accent-lever-probe none
//   .build/accent-lever-probe runtime-orange      # argument domain, set before the view exists
//   .build/accent-lever-probe late-orange         # argument domain, set after the page loaded
//   .build/accent-lever-probe none -AppleAccentColor 1 -AppleHighlightColor "1 0.87451 0.701961 Orange"
//   defaults write accent-lever-probe AppleAccentColor -int 1   # application domain; then `none`;
//   defaults delete accent-lever-probe                          # and clean up after
//   .build/accent-lever-probe spi-orange          # NSApp _setAccentColor: systemOrange, before the view exists
//   .build/accent-lever-probe spi-blue            # ... systemBlue
//   .build/accent-lever-probe spi-default         # ... sRGB 0/122/255
//   .build/accent-lever-probe spi-accentblue      # ... AppKit's catalog +controlAccentBlueColor (what ships)
//   PROBE_DARK=1 .build/accent-lever-probe <mode> # the dark appearance on the view
//
// Each run hosts a focused, selected text input and a checked checkbox in a
// key-claiming, sRGB, off-screen window and prints NSColor.controlAccentColor
// as this process sees it, next to counts of green, orange and blue pixels in
// the snapshot. A lever works if the page's pixel counts move with it. Needs
// the Claude Code sandbox off: WebKit cannot start inside it.
import AppKit
import WebKit

final class KeyWindow: NSWindow {
    override var isKeyWindow: Bool {
        true
    }

    override var isMainWindow: Bool {
        true
    }
}

let html = """
<!doctype html><meta charset=utf-8><meta name=color-scheme content="light dark">
<style>body{margin:0;padding:20px;font:14px system-ui}</style>
<input id=t type=text value="SELECTED SELECTED" style="width:200px">
<input id=c type=checkbox checked style="width:40px;height:40px">
<script>const t=document.getElementById('t');t.focus();t.select();</script>
"""

@MainActor
final class Probe: NSObject, WKNavigationDelegate {
    var done: CheckedContinuation<Void, Never>?
    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        done?.resume(); done = nil
    }
}

/// Puts the accent and highlight into this process's argument domain, the
/// highest-priority defaults domain.
func pin(_ accent: Int, _ highlight: String) {
    let name = UserDefaults.argumentDomain
    var domain = UserDefaults.standard.volatileDomain(forName: name)
    domain["AppleAccentColor"] = accent
    domain["AppleHighlightColor"] = highlight
    UserDefaults.standard.removeVolatileDomain(forName: name)
    UserDefaults.standard.setVolatileDomain(domain, forName: name)
}

/// `[NSApp _setAccentColor:]`: the app-wide accent override WebKit forwards to
/// its web content process (WebPageProxy::creationParameters reads
/// `[NSApp _effectiveAccentColor]`; WebPage::setAccentColor calls
/// `_setAccentColor:` in the content process).
@MainActor
func setAppAccent(_ color: NSColor) {
    let app = NSApplication.shared
    let selector = NSSelectorFromString("_setAccentColor:")
    guard app.responds(to: selector) else { print("  NSApp does not respond to _setAccentColor:"); return }
    _ = app.perform(selector, with: color)
}

/// An `NSColor` class method by name (the private named accent colors).
@MainActor
func colorFromClassMethod(_ name: String) -> NSColor {
    let selector = NSSelectorFromString(name)
    guard NSColor.responds(to: selector), let color = NSColor.perform(selector)?.takeUnretainedValue() as? NSColor else {
        print("  NSColor has no +\(name)")
        return .systemPink
    }
    print("  +\(name) = \(color)")
    return color
}

/// `[NSApp _effectiveAccentColor]`, as this process sees it.
@MainActor
func effectiveAccent() -> String {
    let selector = NSSelectorFromString("_effectiveAccentColor")
    guard NSApplication.shared.responds(to: selector) else { return "no such selector" }
    let value = NSApplication.shared.perform(selector)?.takeUnretainedValue()
    return value.map { String(describing: $0) } ?? "nil"
}

let orangeHighlight = "1.000000 0.874510 0.701961 Orange"

@MainActor
func run() async {
    let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "none"
    if mode == "runtime-orange" { pin(1, orangeHighlight) }
    print("[\(mode)] NSApp._effectiveAccentColor before: \(effectiveAccent())")
    if mode == "spi-orange" { setAppAccent(.systemOrange) }
    if mode == "spi-blue" { setAppAccent(.systemBlue) }
    if mode == "spi-accentblue" { setAppAccent(colorFromClassMethod("controlAccentBlueColor")) }
    if mode == "spi-default" { setAppAccent(NSColor(srgbRed: 0, green: 122 / 255, blue: 1, alpha: 1)) }
    _ = NSApplication.shared.setActivationPolicy(.prohibited)
    let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 100))
    let probe = Probe()
    view.navigationDelegate = probe
    // PROBE_DARK=1: the dark theme, as `--theme dark` sets it.
    if ProcessInfo.processInfo.environment["PROBE_DARK"] == "1" { view.appearance = NSAppearance(named: .darkAqua) }
    let window = KeyWindow(
        contentRect: CGRect(x: -20000, y: -20000, width: 400, height: 100),
        styleMask: .borderless, backing: .buffered, defer: false,
    )
    window.colorSpace = .sRGB
    window.contentView = view
    window.orderBack(nil)
    await withCheckedContinuation { c in probe.done = c; view.loadHTMLString(html, baseURL: nil) }
    if mode == "late-orange" {
        pin(1, orangeHighlight)
        try? await Task.sleep(nanoseconds: 500_000_000)
        _ = try? await view.evaluateJavaScript("t.blur();t.focus();t.select();1")
    }
    try? await Task.sleep(nanoseconds: 500_000_000)
    let image: NSImage = await withCheckedContinuation { c in
        view.takeSnapshot(with: WKSnapshotConfiguration()) { img, _ in c.resume(returning: img!) }
    }
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!.converting(to: .sRGB, renderingIntent: .default)!
    var green = 0, orange = 0, blue = 0
    var channelSum = 0
    for y in 0 ..< rep.pixelsHigh {
        for x in 0 ..< rep.pixelsWide {
            let c = rep.colorAt(x: x, y: y)!
            let r = c.redComponent * 255, g = c.greenComponent * 255, b = c.blueComponent * 255
            channelSum += Int(r.rounded()) + Int(g.rounded()) * 3 + Int(b.rounded()) * 7
            if g > r + 20, g > b + 5 { green += 1 } else if r > g + 20, g > b + 20 { orange += 1 } else if b > r + 40, b > g + 20 { blue += 1 }
        }
    }
    let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.black
    print(String(
        format: "[%@] this process's controlAccentColor %.0f,%.0f,%.0f — page pixels green %d, orange %d, blue %d, weighted channel sum %d",
        CommandLine.arguments.dropFirst().joined(separator: " "),
        accent.redComponent * 255, accent.greenComponent * 255, accent.blueComponent * 255,
        green, orange, blue, channelSum,
    ))
    exit(0)
}

Task { @MainActor in await run() }
RunLoop.main.run()
