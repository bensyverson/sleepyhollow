import AppKit
import Metal
import QuartzCore
import WebKit

/// Renders a live hosted `WKWebView`'s Core Animation layer tree with
/// `CARenderer` into an off-screen Metal texture — the candidate true-3D
/// capture this probe measures. Spike code: not shippable as is.
@MainActor
final class CompositorCapture {
    /// Where one capture's time went, in milliseconds.
    struct Timing {
        var commit: Double = 0
        var render: Double = 0
        var readback: Double = 0
        var total: Double {
            commit + render + readback
        }
    }

    let device: MTLDevice
    let queue: MTLCommandQueue

    /// The color space the renderer composites into and the readback is
    /// tagged with. `PROBE_RENDER_CS=p3` picks Display P3, the space WebKit's
    /// tiles turned out to be painted in; the default is sRGB.
    static let colorSpace: CGColorSpace = ProcessInfo.processInfo.environment["PROBE_RENDER_CS"] == "p3"
        ? CGColorSpace(name: CGColorSpace.displayP3)! : CGColorSpace(name: CGColorSpace.sRGB)!

    init() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            fatalError("no Metal device")
        }
        self.device = device
        self.queue = queue
    }

    /// Waits until the UI process has applied a layer-tree commit that
    /// includes every change the page made before this call — WebKit's
    /// `-_doAfterNextPresentationUpdate:` (SPI, the hook its own layout tests
    /// use before reading pixels).
    static func waitForPresentationUpdate(_ webView: WKWebView) async {
        let selector = NSSelectorFromString("_doAfterNextPresentationUpdate:")
        guard webView.responds(to: selector) else { fatalError("_doAfterNextPresentationUpdate: is gone") }
        typealias Call = @convention(c) (AnyObject, Selector, @escaping @convention(block) () -> Void) -> Void
        let call = unsafeBitCast(webView.method(for: selector), to: Call.self)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            call(webView, selector) { continuation.resume() }
        }
    }

    /// Renders the web view's whole layer tree at `scale` pixels per point.
    ///
    /// `CARenderer.layer =` takes the layer out of its superlayer, so the web
    /// view's backing layer is moved into a scaling wrapper for the render and
    /// put back afterwards.
    func capture(_ webView: WKWebView, scale: CGFloat, waitForCommit: Bool = true) async -> (CGImage, Timing) {
        var timing = Timing()
        var mark = CACurrentMediaTime()
        if waitForCommit {
            await Self.waitForPresentationUpdate(webView)
        }
        timing.commit = (CACurrentMediaTime() - mark) * 1000
        mark = CACurrentMediaTime()
        let texture = render(webView, scale: scale)
        timing.render = (CACurrentMediaTime() - mark) * 1000
        mark = CACurrentMediaTime()
        let image = Self.image(from: texture)
        timing.readback = (CACurrentMediaTime() - mark) * 1000
        return (image, timing)
    }

    /// The synchronous half: move the layer, render, wait for the GPU, put
    /// the layer back.
    private func render(_ webView: WKWebView, scale: CGFloat) -> MTLTexture {
        let size = webView.bounds.size
        let width = Int((size.width * scale).rounded())
        let height = Int((size.height * scale).rounded())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else { fatalError("texture \(width)x\(height)") }
        let renderer = CARenderer(mtlTexture: texture, options: [
            kCARendererColorSpace as String: Self.colorSpace,
            kCARendererMetalCommandQueue as String: queue,
        ])

        guard let backing = webView.layer, let parent = backing.superlayer else { fatalError("web view has no hosted layer") }
        let index = UInt32(parent.sublayers?.firstIndex(of: backing) ?? 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let wrapper = CALayer()
        wrapper.anchorPoint = .zero
        wrapper.bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        wrapper.sublayerTransform = CATransform3DMakeScale(scale, scale, 1)
        wrapper.addSublayer(backing)
        renderer.layer = wrapper
        renderer.bounds = wrapper.bounds
        CATransaction.commit()
        CATransaction.flush()

        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        // Same queue, so this completes after the renderer's own work.
        let fence = queue.makeCommandBuffer()!
        fence.commit()
        fence.waitUntilCompleted()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderer.layer = nil
        parent.insertSublayer(backing, at: index)
        CATransaction.commit()
        CATransaction.flush()
        return texture
    }

    /// Reads the texture back as a `CGImage` tagged ``colorSpace``, flipping it: CARenderer
    /// draws with Core Animation's bottom-left origin.
    static func image(from texture: MTLTexture) -> CGImage {
        let width = texture.width, height = texture.height, rowBytes = width * 4
        var raw = [UInt8](repeating: 0, count: rowBytes * height)
        texture.getBytes(&raw, bytesPerRow: rowBytes, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        var flipped = [UInt8](repeating: 0, count: raw.count)
        for row in 0 ..< height {
            let source = (height - 1 - row) * rowBytes
            flipped.replaceSubrange(row * rowBytes ..< (row + 1) * rowBytes, with: raw[source ..< source + rowBytes])
        }
        let context = CGContext(
            data: &flipped, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue,
        )!
        return context.makeImage()!
    }
}
