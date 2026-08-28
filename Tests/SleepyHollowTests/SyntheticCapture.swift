import CoreGraphics
import Foundation
import SleepyHollow

/// A ``ShotCapture`` built in memory rather than by WebKit — what the pure
/// readout stages (fit, tile) are tested against, so their geometry is
/// checked without paying for a browser.
///
/// The image is horizontal bands `bandHeight` CSS px tall whose red channel
/// is the band index times 17, so ``redChannel(of:x:y:)`` at any pixel says
/// which slice of the document it came from.
func syntheticCapture(
    rect: CGRect,
    scale: Int = 1,
    bandHeight: CGFloat = 100,
) -> ShotCapture {
    let width = Int(rect.width) * scale
    let height = Int(rect.height) * scale
    let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    )!
    let bandPixels = bandHeight * CGFloat(scale)
    var index = 0
    var top: CGFloat = 0
    while top < CGFloat(height) {
        let value = CGFloat((index * 17) % 256) / 255
        context.setFillColor(red: value, green: 40 / 255, blue: 90 / 255, alpha: 1)
        // CGContext's origin is bottom-left; band `index` counts from the top.
        context.fill(CGRect(x: 0, y: CGFloat(height) - top - bandPixels, width: CGFloat(width), height: bandPixels))
        top += bandPixels
        index += 1
    }
    return ShotCapture(image: context.makeImage()!, rect: rect, scale: scale)
}

/// The red channel of one pixel, addressed from the image's top-left — the
/// band identity ``syntheticCapture(rect:scale:bandHeight:)`` encodes.
func redChannel(of image: CGImage, x: Int, y: Int) -> UInt8? {
    guard let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
    ) else { return nil }
    // Place image pixel (x, y) — counted from the top — at the context's only pixel.
    context.draw(
        image,
        in: CGRect(
            x: CGFloat(-x),
            y: CGFloat(-(image.height - y - 1)),
            width: CGFloat(image.width),
            height: CGFloat(image.height),
        ),
    )
    guard let data = context.data else { return nil }
    return data.load(as: UInt8.self)
}
