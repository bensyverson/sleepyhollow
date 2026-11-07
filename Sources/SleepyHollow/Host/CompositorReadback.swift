import CoreGraphics
import Foundation
import Metal

/// The CPU side of a compositor render: one buffer the size of the output
/// image, filled strip by strip from the GPU's textures and handed over as a
/// `CGImage`.
///
/// Each strip is read straight into its own rows of the buffer and then
/// flipped in place, because `CARenderer` draws bottom row first. The spike's
/// readback built a second buffer and copied row ranges between Swift arrays,
/// and that copy — not the render — was most of the 2× cost
/// (`project/2026-11-06-compositor-capture.md` § 5).
final class CompositorReadback {
    /// Output width in pixels.
    let width: Int
    /// Output height in pixels.
    let height: Int
    /// Bytes per output row: four per pixel, BGRA.
    let rowBytes: Int
    /// The output pixels, premultiplied BGRA, top row first once every strip
    /// is in.
    private let pixels: UnsafeMutableRawPointer

    /// An empty `width × height` image's worth of memory.
    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        rowBytes = width * 4
        pixels = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: 16)
    }

    deinit {
        pixels.deallocate()
    }

    /// Reads `texture` — one strip, bottom row first — into output `rows`,
    /// top row first.
    func copy(_ texture: any MTLTexture, intoRows rows: Range<Int>) {
        let start = pixels + rows.lowerBound * rowBytes
        texture.getBytes(
            start,
            bytesPerRow: rowBytes,
            from: MTLRegionMake2D(0, 0, width, rows.count),
            mipmapLevel: 0,
        )
        Self.flipRows(start, count: rows.count, rowBytes: rowBytes)
    }

    /// The finished image, tagged `colorSpace`.
    ///
    /// The bytes are copied once into the image's own storage, so this
    /// object can be released, or reused, afterwards.
    ///
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/environment`` if
    ///   Core Graphics cannot wrap the pixels — a seam bug, never a page fact.
    func image(in colorSpace: CGColorSpace) throws -> CGImage {
        let data = Data(bytes: pixels, count: rowBytes * height) as CFData
        guard
            let provider = CGDataProvider(data: data),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: rowBytes,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent,
            )
        else {
            throw SleepyError(
                kind: .environment,
                message: "Could not read the compositor's render back as an image.",
                nextMove: "Retry; if this persists, it is a seam bug against CARenderer.",
            )
        }
        return image
    }

    /// Reverses the order of `count` rows starting at `start`, in place.
    private static func flipRows(_ start: UnsafeMutableRawPointer, count: Int, rowBytes: Int) {
        let scratch = UnsafeMutableRawPointer.allocate(byteCount: rowBytes, alignment: 16)
        defer { scratch.deallocate() }
        var top = 0
        var bottom = count - 1
        while top < bottom {
            let upper = start + top * rowBytes
            let lower = start + bottom * rowBytes
            scratch.copyMemory(from: upper, byteCount: rowBytes)
            upper.copyMemory(from: lower, byteCount: rowBytes)
            lower.copyMemory(from: scratch, byteCount: rowBytes)
            top += 1
            bottom -= 1
        }
    }
}
