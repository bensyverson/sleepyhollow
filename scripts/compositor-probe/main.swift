import AppKit
import QuartzCore
import WebKit

// The compositor-capture probe (job leaf B3dXgQ). Built and run by
// scripts/compositor-probe.sh, compiled together with Sources/SleepyHollow so
// it drives the real PageHost, ShotOperation and wait engine. Findings:
// project/2026-11-06-compositor-capture.md.

let out = ProcessInfo.processInfo.environment["PROBE_OUT"] ?? ".build/compositor-probe/out"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
let arguments = Array(CommandLine.arguments.dropFirst())
let mode = arguments.first ?? "help"

func say(_ line: String) {
    print(line)
    fflush(stdout)
}

@MainActor
func run() async throws {
    say("[probe] \(mode) — \(loadAverage()), footprint \(String(format: "%.0f", footprintMB())) MB at start")
    switch mode {
    case "tree": try await tree()
    case "t3d": try await t3d()
    case "flat": try await flat()
    case "media": try await media()
    case "fullpage": try await fullPage()
    case "readiness": try await readiness()
    case "bench": try await bench(Int(arguments.dropFirst().first ?? "20") ?? 20)
    case "anim": try await animation()
    case "idle": try await idle()
    case "controls": try await controls()
    case "spi": try await spi()
    case "css3d": try await css3d()
    case "timers": try await timers(Int(arguments.dropFirst().first ?? "10") ?? 10)
    default:
        say("modes: tree t3d css3d flat media fullpage readiness bench [N] anim idle timers [seconds] controls spi")
    }
}

// MARK: - 1. Does it work: the UI-process layer tree

@MainActor
func tree() async throws {
    let name = arguments.dropFirst().first ?? "t3d.html"
    let (host, _) = makeHost(.live, size: name == "t3d.html" ? ViewportSize(width: 1000, height: 260) : ViewportSize(width: 800, height: 500))
    _ = try await host.load(fixture(name))
    await CompositorCapture.waitForPresentationUpdate(host.webView)
    func dump(_ layer: CALayer, _ depth: Int) {
        var contents = "-"
        if let c = layer.contents { contents = CFCopyTypeIDDescription(CFGetTypeID(c as CFTypeRef)) as String }
        let t = layer.transform, s = layer.sublayerTransform
        let flags = [
            CATransform3DIsAffine(t) ? nil : "3D transform (m34 \(String(format: "%.5f", t.m34)), m13 \(String(format: "%.3f", t.m13)))",
            CATransform3DIsIdentity(s) ? nil : "sublayerTransform m34 \(String(format: "%.5f", s.m34))",
            layer.isDoubleSided ? nil : "single-sided",
            String(describing: type(of: layer)).contains("Transform") ? "CATransformLayer" : nil,
        ].compactMap(\.self)
        let name = (layer.name ?? "").replacingOccurrences(of: #"0x[0-9a-f]+"#, with: "…", options: .regularExpression)
        say("\(String(repeating: "  ", count: depth))\(type(of: layer)) “\(name)” contents=\(contents) scale=\(layer.contentsScale) \(flags.joined(separator: ", "))")
        for sub in layer.sublayers ?? [] {
            dump(sub, depth + 1)
        }
    }
    dump(host.webView.layer!, 0)
}

// MARK: - 2. Fidelity

@MainActor
func t3d() async throws {
    let (host, _) = makeHost(.live, size: ViewportSize(width: 1000, height: 260))
    _ = try await host.load(fixture("t3d.html"))
    let rects = try await host.evaluate("""
    return ["a", "b-front", "c", "d-near", "d-far"].map((id) => { const r = document.getElementById(id).getBoundingClientRect(); return id + " x " + r.left.toFixed(1) + "–" + r.right.toFixed(1) + " y " + r.top.toFixed(1) + "–" + r.bottom.toFixed(1); });
    """, in: .page)
    say("[t3d] getBoundingClientRect (CSS px): \(rects)")
    // Expected geometry is derived by hand in project/2026-11-06-compositor-capture.md;
    // WebKit's getBoundingClientRect agrees with it to 0.1 px.
    let capture = CompositorCapture()
    for scale in [1, 2] {
        let (snap, snapMS) = try await snapshotCapture(host, scale: scale)
        let (comp, timing) = await capture.capture(host.webView, scale: CGFloat(scale))
        writePNG(snap, to: "\(out)/t3d-snapshot-\(scale)x.png")
        writePNG(comp, to: "\(out)/t3d-compositor-\(scale)x.png")
        say(String(format: "[t3d] scale %d: snapshot %.1f ms, compositor %.1f ms (commit %.1f, render %.1f, readback %.1f)", scale, snapMS, timing.total, timing.commit, timing.render, timing.readback))
        for (label, image) in [("snapshot", snap), ("compositor", comp)] {
            let pixels = Pixels(image)
            let s = CGFloat(scale)
            say("[t3d] \(scale)x \(label) A blue   (perspective on parent): \(pixels.shape(of: (42, 82, 168)))")
            say("[t3d] \(scale)x \(label) B green  (front face):            \(pixels.shape(of: (21, 102, 79)))")
            say("[t3d] \(scale)x \(label) B orange (back face, must be absent): \(pixels.shape(of: (194, 70, 28)))")
            say("[t3d] \(scale)x \(label) C purple (perspective() rotateX):  \(pixels.shape(of: (140, 40, 160)))")
            // Overlap of D's two boxes in flat layout: x 836–876 (abs) y 64–144 → sample its middle.
            let red = pixels.shape(of: (220, 20, 20)), yellow = pixels.shape(of: (240, 200, 0))
            let sample = (Int(856 * s), Int(104 * s))
            let (r, g, b) = pixels.rgb(sample.0, sample.1)
            say("[t3d] \(scale)x \(label) D near red: \(red); far yellow: \(yellow); overlap sample at CSS (856,104) = rgb(\(r),\(g),\(b)) → \(pixels.matches(sample.0, sample.1, (220, 20, 20)) ? "RED wins (correct)" : pixels.matches(sample.0, sample.1, (240, 200, 0)) ? "YELLOW wins (DOM order, flat)" : "neither")")
        }
    }
}

@MainActor
func flat() async throws {
    let capture = CompositorCapture()
    for kind in [HostKind.live] {
        let (host, _) = makeHost(kind, size: ViewportSize(width: 800, height: 500))
        _ = try await host.load(fixture("flat.html"))
        for scale in [1, 2] {
            let (snap, _) = try await snapshotCapture(host, scale: scale)
            let (comp, _) = await capture.capture(host.webView, scale: CGFloat(scale))
            writePNG(snap, to: "\(out)/flat-snapshot-\(scale)x.png")
            writePNG(comp, to: "\(out)/flat-compositor-\(scale)x.png")
            let a = Pixels(snap), b = Pixels(comp)
            if let d = a.diff(b) { say("[flat] \(kind) \(scale)x snapshot vs compositor: \(d)") } else { say("[flat] sizes differ: \(a.width)x\(a.height) vs \(b.width)x\(b.height)") }
            if let img = a.diffImage(b) { writePNG(img, to: "\(out)/flat-diff-\(scale)x.png") }
        }
    }
    // Control: does hosting live change takeSnapshot itself? Windowless vs live.
    let (plain, _) = makeHost(.windowless, size: ViewportSize(width: 800, height: 500))
    _ = try await plain.load(fixture("flat.html"))
    let (live, _) = makeHost(.live, size: ViewportSize(width: 800, height: 500))
    _ = try await live.load(fixture("flat.html"))
    let (p, _) = try await snapshotCapture(plain, scale: 2)
    let (l, _) = try await snapshotCapture(live, scale: 2)
    say("[flat] control 2x: takeSnapshot windowless vs live: \(Pixels(p).diff(Pixels(l)).map { "\($0)" } ?? "size differs")")
}

// MARK: - 3. What it misses

@MainActor
func media() async throws {
    let movie = URL(fileURLWithPath: "\(out)/magenta.mp4").standardizedFileURL
    try await writeMagentaMovie(to: movie)
    let (host, _) = makeHost(.live, size: ViewportSize(width: 900, height: 420), wait: .selector("body[data-ready]"))
    _ = try await host.load(fixture("media.html", query: "video=\(movie.absoluteString)"))
    let facts = try await host.evaluate("return { webgl: document.body.dataset.webgl, videoError: document.body.dataset.videoError ?? null, videoTime: document.getElementById('video').currentTime, fontStatus: document.fonts.status };", in: .page)
    say("[media] page facts: \(facts)")
    let capture = CompositorCapture()
    let (snap, _) = try await snapshotCapture(host, scale: 2)
    let (comp, _) = await capture.capture(host.webView, scale: 2)
    writePNG(snap, to: "\(out)/media-snapshot-2x.png")
    writePNG(comp, to: "\(out)/media-compositor-2x.png")
    for (label, image) in [("snapshot", snap), ("compositor", comp)] {
        let p = Pixels(image)
        // Cell origins (CSS px): row 1 at y 20, columns at x 20, 300, 580; row 2 at y 200.
        let cell = { (x: Int, y: Int) in CGRect(x: x * 2, y: y * 2, width: 480, height: 280) }
        say("[media] \(label) video magenta: \(p.shape(of: (255, 0, 255), in: cell(20, 20)).count) px of 134400")
        say("[media] \(label) webgl teal:    \(p.shape(of: (0, 200, 200), in: cell(300, 20)).count) px of 134400")
        say("[media] \(label) canvas orange: \(p.shape(of: (255, 128, 0), in: cell(580, 20)).count) px of 134400")
        // Backdrop: the top half (y 200–270) is covered by invert(1). Sample a
        // stripe that is black underneath: x 30 (first black stripe).
        let (r, g, b) = p.rgb(30 * 2, 230 * 2), (r2, g2, b2) = p.rgb(30 * 2, 300 * 2)
        say("[media] \(label) backdrop: covered black stripe reads rgb(\(r),\(g),\(b)) (inverted = white), uncovered rgb(\(r2),\(g2),\(b2))")
        // Late font: block glyphs fill much more ink than the fallback monospace.
        let ink = p.shape(of: (0, 0, 0), in: CGRect(x: 300 * 2, y: 200 * 2, width: 480, height: 130)).count
        say("[media] \(label) late font ink: \(ink) black px")
    }
}

@MainActor
func fullPage() async throws {
    let bands: [(Int, Int, Int)] = (0 ..< 13).map { (17 * $0, 40, 90) }
    let capture = CompositorCapture()
    for resizeWindow in [false, true] {
        let (host, window) = makeHost(.live, size: ViewportSize(width: 1280, height: 800))
        _ = try await host.load(URL(fileURLWithPath: "Tests/TestSupport/Fixtures/capture-banded.html").standardizedFileURL)
        // Grow the view to the document, as ShotOperation does for --full-page.
        let full = CGSize(width: 1280, height: 12982)
        host.webView.frame = CGRect(origin: .zero, size: full)
        if resizeWindow { window?.setFrame(CGRect(origin: OffscreenWindow.parkedOrigin, size: full), display: false) }
        // One commit may not be enough for tiles to cover the new size; take two.
        await CompositorCapture.waitForPresentationUpdate(host.webView)
        let (image, timing) = await capture.capture(host.webView, scale: 1)
        writePNG(image, to: "\(out)/fullpage-\(resizeWindow ? "window" : "view")-1x.png")
        let p = Pixels(image)
        let present = bands.enumerated().map { i, color in p.matches(640, i * 1000 + 500, color, tolerance: 6) ? "✓" : "·" }.joined()
        let blank = (0 ..< 13).count(where: { i in p.rgb(640, i * 1000 + 500) == (0, 0, 0) || p.rgb(640, i * 1000 + 500) == (255, 255, 255) })
        say(String(format: "[fullpage] resize %@: %dx%d in %.0f ms, bands present at x=640 [%@], blank/background bands %d", resizeWindow ? "view+window" : "view only", p.width, p.height, timing.total, present, blank))
        // Tile coverage as WebKit built it.
        var tiles = 0
        var maxY: CGFloat = 0
        func walk(_ layer: CALayer) {
            if (layer.name ?? "").hasPrefix("tile at"), layer.contents != nil { tiles += 1; maxY = max(maxY, layer.frame.maxY) }
            layer.sublayers?.forEach(walk)
        }
        walk(host.webView.layer!)
        say("[fullpage] tiles with contents: \(tiles), lowest tile edge \(maxY) pt")
    }
    // Scrolling instead: does the compositor follow a scroll? Rect far below the fold.
    let (host, _) = makeHost(.live, size: ViewportSize(width: 1280, height: 800))
    _ = try await host.load(URL(fileURLWithPath: "Tests/TestSupport/Fixtures/capture-banded.html").standardizedFileURL)
    _ = try await host.evaluate("window.scrollTo(0, 9200); return window.scrollY;", in: .page)
    let (image, _) = await capture.capture(host.webView, scale: 1)
    let p = Pixels(image)
    say("[fullpage] after scrollTo(0, 9200): top-left pixel rgb\(p.rgb(10, 10)) (band 9 = (153,40,90)), y=700 rgb\(p.rgb(10, 700)) (band 9 = (153,40,90); band 10 starts at 800 = (170,40,90))")
}

// MARK: - 4. Readiness

@MainActor
func readiness() async throws {
    let (host, _) = makeHost(.live, size: ViewportSize(width: 400, height: 300))
    _ = try await host.load(fixture("swatch.html"))
    let capture = CompositorCapture()
    for waitForCommit in [false, true] {
        var stale = 0, fresh = 0, other = 0
        for i in 1 ... 20 {
            let value = i * 12
            _ = try await host.evaluate("document.getElementById('s').style.background = 'rgb(\(value), 0, 0)'; return 1;", in: .page)
            let (image, _) = await capture.capture(host.webView, scale: 1, waitForCommit: waitForCommit)
            let (r, _, _) = Pixels(image).rgb(200, 150)
            if abs(r - value) <= 2 { fresh += 1 } else if abs(r - (value - 12)) <= 2 { stale += 1 } else { other += 1 }
        }
        say("[readiness] wait for presentation update: \(waitForCommit) → fresh \(fresh), previous frame \(stale), other \(other) of 20")
    }
}

// MARK: - 5. Cost

@MainActor
func bench(_ count: Int) async throws {
    let (host, _) = makeHost(.live, size: ViewportSize(width: 1280, height: 800))
    _ = try await host.load(fixture("t3d.html"))
    let capture = CompositorCapture()
    // Warm both paths.
    _ = try await snapshotCapture(host, scale: 2)
    _ = await capture.capture(host.webView, scale: 2)
    for scale in [1, 2] {
        let before = footprintMB()
        var comp: [Double] = [], commit: [Double] = [], render: [Double] = [], readback: [Double] = [], snap: [Double] = []
        var peak = before
        for _ in 0 ..< count {
            let (_, t) = await capture.capture(host.webView, scale: CGFloat(scale))
            comp.append(t.total); commit.append(t.commit); render.append(t.render); readback.append(t.readback)
            peak = max(peak, footprintMB())
        }
        let mid = footprintMB()
        for _ in 0 ..< count {
            let (_, ms) = try await snapshotCapture(host, scale: scale)
            snap.append(ms)
            peak = max(peak, footprintMB())
        }
        say(String(format: "[bench] 1280x800 @%dx, n=%d: compositor median %.1f ms p90 %.1f (commit %.1f, render %.1f, readback %.1f); takeSnapshot median %.1f ms p90 %.1f; footprint %.0f → %.0f (after compositor) → %.0f MB, peak %.0f; %@",
                   scale, count, median(comp), percentile(comp, 0.9), median(commit), median(render), median(readback), median(snap), percentile(snap, 0.9), before, mid, footprintMB(), peak, loadAverage()))
    }
}

// MARK: - 6. Live-hosting side effects

@MainActor
func animation() async throws {
    for kind in [HostKind.windowless, .hidden, .live] {
        let (host, _) = makeHost(kind, size: ViewportSize(width: 600, height: 300), wait: .selector("body[data-done]"))
        let start = CACurrentMediaTime()
        _ = try await host.load(fixture("animation.html"))
        let report = try await host.evaluate("return document.getElementById('report').textContent;", in: .page)
        say(String(format: "[anim] %@ (load+wait %.0f ms): %@", kind.description, (CACurrentMediaTime() - start) * 1000, report))
    }
}

@MainActor
func idle() async throws {
    for kind in [HostKind.windowless, .live] {
        let (host, _) = makeHost(kind, size: ViewportSize(width: 600, height: 300), wait: .idle)
        let start = CACurrentMediaTime()
        do {
            _ = try await host.load(fixture("raf-forever.html"))
            let frames = try await host.evaluate("return window.frames;", in: .page)
            say(String(format: "[idle] %@: --wait-for idle settled in %.0f ms; rAF frames so far %@", kind.description, (CACurrentMediaTime() - start) * 1000, frames))
        } catch {
            say(String(format: "[idle] %@: failed after %.0f ms: %@", kind.description, (CACurrentMediaTime() - start) * 1000, "\(error)"))
        }
    }
}

/// Question 8: timer cadence by host kind (coordinator addition, from
/// project/2026-11-06-webgl-scene-feedback.md § 2).
@MainActor
func timers(_ seconds: Int) async throws {
    for kind in [HostKind.windowless, .hidden, .live, HostKind(window: .live, key: true)] {
        for loop in ["timeout", "interval", "channel"] {
            let (host, _) = makeHost(kind, size: ViewportSize(width: 400, height: 200), wait: .selector("body[data-done]"))
            _ = try await host.load(fixture("timers.html", query: "loop=\(loop)&seconds=\(seconds)"))
            let report = try await host.evaluate("return document.getElementById('report').textContent;", in: .page)
            say("[timers] \(kind) \(loop): \(report)")
        }
    }
}

@MainActor
func css3d() async throws {
    let (host, _) = makeHost(.live, size: ViewportSize(width: 1000, height: 500))
    _ = try await host.load(fixture("css3d.html"))
    let rects = try await host.evaluate("""
    return ["p1", "p2"].map((id) => { const r = document.getElementById(id).getBoundingClientRect(); return id + " x " + r.left.toFixed(1) + "–" + r.right.toFixed(1) + " y " + r.top.toFixed(1) + "–" + r.bottom.toFixed(1); });
    """, in: .page)
    say("[css3d] getBoundingClientRect (CSS px): \(rects)")
    let capture = CompositorCapture()
    let (snap, _) = try await snapshotCapture(host, scale: 1)
    let (comp, _) = await capture.capture(host.webView, scale: 1)
    writePNG(snap, to: "\(out)/css3d-snapshot-1x.png")
    writePNG(comp, to: "\(out)/css3d-compositor-1x.png")
    for (label, image) in [("snapshot", snap), ("compositor", comp)] {
        let p = Pixels(image)
        say("[css3d] \(label) blue panel (expect x 400–600, y 200–300): \(p.shape(of: (0, 150, 255)))")
        say("[css3d] \(label) green panel (expect centered near x 850, trapezoid): \(p.shape(of: (30, 180, 60)))")
    }
}

// MARK: - 7. Inactive-window controls

@MainActor
func controls() async throws {
    let kinds: [HostKind] = [
        .windowless, .hidden, .live,
        HostKind(window: .hidden, key: true), HostKind(window: .live, key: true),
        HostKind(window: .hidden, key: true, firstResponder: true), HostKind(window: .live, key: true, firstResponder: true),
        HostKind(window: .live, key: false, firstResponder: true),
    ]
    let capture = CompositorCapture()
    var baseline: Pixels?
    for kind in kinds {
        let (host, _) = makeHost(kind, size: ViewportSize(width: 520, height: 260))
        _ = try await host.load(fixture("controls.html"))
        // Re-focus after load: focus() before the window was active may not draw a ring.
        _ = try await host.evaluate("document.getElementById('focused').focus(); return 1;", in: .page)
        let facts = try await host.evaluate("return window.focusFacts();", in: .page)
        let (snap, _) = try await snapshotCapture(host, scale: 2)
        let name = kind.description.replacingOccurrences(of: "+", with: "-")
        writePNG(snap, to: "\(out)/controls-\(name)-2x.png")
        let p = Pixels(snap)
        // Saturated (accent-colored) pixels: an active checked checkbox, radio,
        // focus ring and range fill are blue; inactive ones are gray.
        var accent = 0
        for y in 0 ..< p.height {
            for x in 0 ..< p.width {
                let (r, g, b) = p.rgb(x, y)
                if b > 150, b - r > 60, b - g > 30 { accent += 1 }
            }
        }
        let delta = baseline.flatMap { p.diff($0) }.map { "vs windowless: \($0)" } ?? "(baseline)"
        if baseline == nil { baseline = p }
        say("[controls] \(kind): accent-blue px \(accent); facts \(facts); \(delta)")
        if kind.window == .live, kind.key {
            let (comp, _) = await capture.capture(host.webView, scale: 2)
            writePNG(comp, to: "\(out)/controls-\(name)-compositor-2x.png")
            say("[controls] \(kind): compositor vs snapshot: \(Pixels(comp).diff(p).map { "\($0)" } ?? "size differs")")
        }
    }
}

// MARK: - Other routes

@MainActor
func spi() async throws {
    for cls in [WKWebView.self, WKSnapshotConfiguration.self] as [AnyClass] {
        var count: UInt32 = 0
        guard let methods = class_copyMethodList(cls, &count) else { continue }
        let names = (0 ..< Int(count)).map { NSStringFromSelector(method_getName(methods[$0])) }
            .filter { $0.lowercased().contains("snapshot") || $0.contains("PresentationUpdate") || $0.contains("Active") }
            .sorted()
        say("[spi] \(cls) selectors: \(names.joined(separator: " "))")
    }
    let (host, _) = makeHost(.live, size: ViewportSize(width: 1000, height: 260))
    _ = try await host.load(fixture("t3d.html"))
    await CompositorCapture.waitForPresentationUpdate(host.webView)
    // -[WKWebView _windowSnapshotInRect:withOptions:]: a window-server image of
    // the view's own window. Signature assumed (CGRect, CGWindowImageOption) → CGImageRef.
    let selector = NSSelectorFromString("_windowSnapshotInRect:withOptions:")
    if host.webView.responds(to: selector) {
        // Measured: it returns an NSImage, not a CGImageRef.
        typealias Call = @convention(c) (AnyObject, Selector, CGRect, UInt32) -> Unmanaged<NSImage>?
        let call = unsafeBitCast(host.webView.method(for: selector), to: Call.self)
        let start = CACurrentMediaTime()
        let nsImage = call(host.webView, selector, CGRect(x: 0, y: 0, width: 1000, height: 260), 0)?.takeUnretainedValue()
        say("[spi] _windowSnapshotInRect returned \(nsImage.map { "NSImage \($0.size), reps \($0.representations)" } ?? "nil")")
        let image = nsImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        say(String(format: "[spi] _windowSnapshotInRect: %@ in %.1f ms", image.map { "\($0.width)x\($0.height)" } ?? "nil", (CACurrentMediaTime() - start) * 1000))
        if let image {
            writePNG(image, to: "\(out)/spi-window-snapshot.png")
            say("[spi] window snapshot A blue: \(Pixels(image).shape(of: (42, 82, 168)))")
        }
    }
}

MainActor.assumeIsolated {
    Task { @MainActor in
        do { try await run() } catch { say("[probe] error: \(error)"); exit(1) }
        say("[probe] done — footprint \(String(format: "%.0f", footprintMB())) MB, \(loadAverage())")
        exit(0)
    }
}

RunLoop.main.run()
