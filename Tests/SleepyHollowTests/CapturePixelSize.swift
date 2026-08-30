import CoreGraphics
import Foundation
import ImageIO

/// Decodes a PNG's pixel dimensions without a full drawing pass — what the
/// capture family's tests assert capture geometry against.
func pixelDimensions(ofPNG data: Data) -> (width: Int, height: Int)? {
    guard
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let width = properties[kCGImagePropertyPixelWidth] as? Int,
        let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
        return nil
    }
    return (width, height)
}

/// The PNG's horizontal resolution in dots per inch — the `pHYs` metadata
/// `--scale` writes so a document viewer places the image at its CSS size
/// rather than its pixel size.
///
/// A PNG with no `pHYs` chunk carries no resolution at all, and every reader
/// treats that as 72 dpi; a point-for-pixel capture writes exactly that file,
/// so the absent chunk is reported as 72 rather than as nothing.
func dotsPerInch(ofPNG data: Data) -> Double? {
    guard
        let source = CGImageSourceCreateWithData(data as CFData, nil),
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else {
        return nil
    }
    return properties[kCGImagePropertyDPIWidth] as? Double ?? 72
}

/// Decodes a PNG to pixels a colour assertion can address.
func decodedImage(ofPNG data: Data) -> CGImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(source, 0, nil)
}

/// One pixel's colour, addressed from the image's top-left.
func pixelColor(of image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8)? {
    guard let samples = redrawnSamples(of: image, width: image.width, height: image.height) else { return nil }
    let offset = (y * image.width + x) * 4
    guard offset + 2 < samples.count else { return nil }
    return (samples[offset], samples[offset + 1], samples[offset + 2])
}

/// One pixel's colour *and* alpha, addressed from the image's top-left.
///
/// The samples are premultiplied, so a fully transparent pixel reads as
/// `(0, 0, 0, 0)` whatever the page painted there — which is exactly the
/// claim a transparent backdrop makes.
func pixelRGBA(of image: CGImage, x: Int, y: Int) -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8)? {
    guard let samples = redrawnSamples(of: image, width: image.width, height: image.height) else { return nil }
    let offset = (y * image.width + x) * 4
    guard offset + 3 < samples.count else { return nil }
    return (samples[offset], samples[offset + 1], samples[offset + 2], samples[offset + 3])
}

/// The mean absolute per-channel difference between two images, each redrawn
/// into the same `width × height` RGBA buffer — 0 for identical pixels, and a
/// handful for two renderings that differ only in antialiasing.
func meanChannelDifference(_ first: CGImage, _ second: CGImage, width: Int, height: Int) -> Double? {
    guard
        let left = redrawnSamples(of: first, width: width, height: height),
        let right = redrawnSamples(of: second, width: width, height: height),
        left.count == right.count, !left.isEmpty
    else {
        return nil
    }
    var total = 0
    for index in left.indices where index % 4 != 3 {
        total += abs(Int(left[index]) - Int(right[index]))
    }
    return Double(total) / Double(left.count / 4 * 3)
}

/// `image` redrawn into a `width × height` premultiplied-RGBA buffer, so two
/// images of different pixel sizes can be compared sample by sample.
private func redrawnSamples(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
    guard width > 0, height > 0 else { return nil }
    var samples = [UInt8](repeating: 0, count: width * height * 4)
    let drawn: Bool = samples.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(
            data: buffer.baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        ) else {
            return false
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return true
    }
    return drawn ? samples : nil
}
