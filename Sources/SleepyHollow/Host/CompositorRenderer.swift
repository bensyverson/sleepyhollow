import AppKit
import Metal
import QuartzCore

/// Draws a live web view's Core Animation layer tree with `CARenderer` into
/// an off-screen Metal texture: the compositor path of
/// ``ShotRenderer/compositor``.
///
/// WebKit composites in the UI process on macOS, so the layers under
/// `WKWebView.layer` are real `CALayer`s with real 4×4 transforms and
/// `IOSurface` contents. `CARenderer` honors what they carry — CSS
/// `perspective` as `sublayerTransform.m34`, `preserve-3d` as a
/// `CATransformLayer`, `backface-visibility: hidden` as `isDoubleSided =
/// false` — which `takeSnapshot`'s software paint reduces to 2D
/// (`project/2026-11-06-compositor-capture.md`).
///
/// Three facts shape the code, all measured in that spike:
///
/// - **`CARenderer.layer =` detaches the layer from its superlayer.** So the
///   web view's backing layer is moved into a wrapper for the render and put
///   back at its old index afterwards — ``withLayer(_:in:_:)``, which restores
///   it even when the render throws.
/// - **The scale goes on the wrapper, and the image is flipped on readback.**
///   Core Animation draws with a bottom-left origin; flipping with a negative
///   y-scale would also flip every face's winding and invert backface
///   culling.
/// - **A Metal texture stops at 16,384 px a side** (``maximumTextureSide``),
///   so a tall render — a 2× capture of a page past 8,192 CSS px — is drawn
///   in horizontal strips (``strips(height:width:)``) and stitched into one
///   image, each strip a translated render of the same tree.
///
/// The renderer is not thread-safe and does not need to be: Core Animation's
/// layer tree is main-thread state, so everything here runs on the main
/// actor and blocks it only for the GPU's own few milliseconds per strip.
@MainActor
enum CompositorRenderer {
    /// The largest texture side, in pixels, that every Mac GPU family
    /// supports.
    nonisolated static let maximumTextureSide: Int = ShotRenderer.maximumWidth

    /// The most memory one strip's texture may take, in bytes.
    ///
    /// A render target this size is allocated for every strip and freed
    /// after it; capping it keeps a 2× full-page capture's peak at the
    /// output image plus one strip, rather than a second full copy.
    nonisolated static let stripByteBudget = 32 << 20

    /// The color space the renderer composites in and the image is tagged
    /// with: sRGB, the space every ``OffscreenWindow`` paints its tiles in.
    static let colorSpace: CGColorSpace = .init(name: CGColorSpace.sRGB)!

    /// The Metal device and queue, created once per process; `nil` on a Mac
    /// with no Metal device, where shots fall back to `takeSnapshot`.
    static let gpu: GPU? = GPU()

    /// One Metal device and the command queue every render runs on.
    final class GPU {
        /// The system default device.
        let device: any MTLDevice
        /// The queue `CARenderer` encodes into, and the fence is committed
        /// on.
        let queue: any MTLCommandQueue

        /// The system default device and a queue on it, or `nil` without
        /// one.
        init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
                return nil
            }
            self.device = device
            self.queue = queue
        }
    }

    /// Why a render could not run.
    enum Failure: Error, Equatable {
        /// The process has no Metal device.
        case noGPU
        /// The layer to render is not in a layer tree it can be returned to.
        case detachedLayer
        /// The output is wider than one texture.
        case tooWide(pixels: Int)
        /// Metal refused a texture of this size.
        case textureUnavailable(width: Int, height: Int)
    }

    /// Renders the part of `layer` that `rect` names, at `scale` pixels per
    /// point.
    ///
    /// - Parameters:
    ///   - layer: the web view's backing layer, in its window's layer tree.
    ///   - rect: the area to draw, in the layer's own coordinates measured
    ///     from its **top-left** (the view's flipped space, which is where a
    ///     shot's rect is resolved).
    ///   - scale: output pixels per point.
    /// - Returns: the pixels, sRGB, premultiplied, top row first.
    /// - Throws: ``Failure`` when there is no GPU, the layer has no parent to
    ///   return to, the output is wider than ``maximumTextureSide``, or Metal
    ///   refuses a strip's texture.
    static func render(_ layer: CALayer, rect: CGRect, scale: CGFloat) throws -> CGImage {
        guard let gpu else { throw Failure.noGPU }
        let width = max(1, Int((rect.width * scale).rounded()))
        let height = max(1, Int((rect.height * scale).rounded()))
        guard width <= maximumTextureSide else { throw Failure.tooWide(pixels: width) }
        let readback = CompositorReadback(width: width, height: height)
        // The layer's top edge in its own (bottom-left origin) coordinates.
        let top = layer.bounds.height
        for rows in strips(height: height, width: width) {
            let texture = try target(width: width, height: rows.count, on: gpu)
            let wrapper = CALayer()
            wrapper.anchorPoint = .zero
            wrapper.bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(rows.count))
            // Output row `rows.upperBound` (top-down from the rect's top)
            // lands on the wrapper's bottom edge; scaling first keeps the
            // offset in whole output pixels.
            let offsetX = rect.minX * scale
            let offsetY = (top - rect.minY) * scale - CGFloat(rows.upperBound)
            wrapper.sublayerTransform = CATransform3DConcat(
                CATransform3DMakeScale(scale, scale, 1),
                CATransform3DMakeTranslation(-offsetX, -offsetY, 0),
            )
            try withLayer(layer, in: wrapper) { wrapper in
                draw(wrapper, into: texture, on: gpu)
            }
            readback.copy(texture, intoRows: rows)
        }
        return try readback.image(in: colorSpace)
    }

    /// Moves `layer` into `wrapper` for the length of `body`, then puts it
    /// back in its old superlayer at its old index — on success and on
    /// throw alike.
    ///
    /// - Throws: ``Failure/detachedLayer`` when `layer` has no superlayer to
    ///   return to, and whatever `body` throws.
    static func withLayer<Value>(
        _ layer: CALayer,
        in wrapper: CALayer,
        _ body: (CALayer) throws -> Value,
    ) throws -> Value {
        guard let parent = layer.superlayer else { throw Failure.detachedLayer }
        let index = UInt32(parent.sublayers?.firstIndex(of: layer) ?? 0)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wrapper.addSublayer(layer)
        CATransaction.commit()
        defer {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            parent.insertSublayer(layer, at: index)
            CATransaction.commit()
            CATransaction.flush()
        }
        return try body(wrapper)
    }

    /// The output rows each strip draws, top to bottom: contiguous, covering
    /// `0 ..< height`, each no taller than ``maximumTextureSide`` and no
    /// larger than ``stripByteBudget`` at `width` pixels of four bytes.
    nonisolated static func strips(height: Int, width: Int) -> [Range<Int>] {
        let byBudget = stripByteBudget / max(1, width * 4)
        let tallest = max(1, min(maximumTextureSide, byBudget))
        return stride(from: 0, to: height, by: tallest).map { $0 ..< min(height, $0 + tallest) }
    }

    /// A render target `width × height`, readable by the CPU.
    private static func target(width: Int, height: Int, on gpu: GPU) throws -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false,
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        // Unified memory reads a shared texture directly; a discrete GPU
        // needs a managed one, synchronized after the render.
        descriptor.storageMode = gpu.device.hasUnifiedMemory ? .shared : .managed
        guard let texture = gpu.device.makeTexture(descriptor: descriptor) else {
            throw Failure.textureUnavailable(width: width, height: height)
        }
        return texture
    }

    /// One `CARenderer` frame of `wrapper` into `texture`, waited on.
    private static func draw(_ wrapper: CALayer, into texture: any MTLTexture, on gpu: GPU) {
        let renderer = CARenderer(mtlTexture: texture, options: [
            kCARendererColorSpace as String: colorSpace,
            kCARendererMetalCommandQueue as String: gpu.queue,
        ])
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderer.layer = wrapper
        renderer.bounds = wrapper.bounds
        CATransaction.commit()
        // Without a flush the first render came back blank.
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(renderer.bounds)
        renderer.render()
        renderer.endFrame()
        // Same queue, so this completes after the renderer's own work.
        if let fence = gpu.queue.makeCommandBuffer() {
            if texture.storageMode == .managed, let blit = fence.makeBlitCommandEncoder() {
                blit.synchronize(resource: texture)
                blit.endEncoding()
            }
            fence.commit()
            fence.waitUntilCompleted()
        }
        renderer.layer = nil
    }
}
