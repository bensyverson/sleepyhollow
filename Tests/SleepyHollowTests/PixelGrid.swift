import CoreGraphics
import Foundation

/// An sRGB RGBA8 copy of a capture, for finding shapes by color and comparing
/// two renders — the measuring tools of the compositor spike
/// (`scripts/compositor-probe/Pixels.swift`), as test apparatus.
struct PixelGrid {
    /// An sRGB color, 0–255 per channel.
    typealias RGB = (red: Int, green: Int, blue: Int)

    let width: Int
    let height: Int
    private var bytes: [UInt8]

    /// Redraws `image` into an sRGB buffer of its own pixel size.
    init(_ image: CGImage) {
        width = image.width
        height = image.height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            )!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// The color at `(x, y)`, from the top-left.
    func rgb(_ x: Int, _ y: Int) -> RGB {
        let index = (y * width + x) * 4
        return (Int(bytes[index]), Int(bytes[index + 1]), Int(bytes[index + 2]))
    }

    /// Whether `(x, y)` is within `tolerance` of `color` on every channel.
    func matches(_ x: Int, _ y: Int, _ color: RGB, tolerance: Int = 24) -> Bool {
        let pixel = rgb(x, y)
        return abs(pixel.red - color.red) <= tolerance
            && abs(pixel.green - color.green) <= tolerance
            && abs(pixel.blue - color.blue) <= tolerance
    }

    /// Where one color lies: its bounding box, pixel count, and the extent of
    /// its outermost columns and rows — enough to tell a trapezoid from a
    /// rectangle.
    struct Shape {
        var count = 0
        var minX = Int.max
        var maxX = Int.min
        var minY = Int.max
        var maxY = Int.min
        /// Pixels of the color in the column 3 px inside the left edge.
        var leftColumn = 0
        /// Pixels of the color in the column 3 px inside the right edge.
        var rightColumn = 0
        /// Pixels of the color in the row 3 px inside the top edge.
        var topRow = 0
        /// Pixels of the color in the row 3 px inside the bottom edge.
        var bottomRow = 0
    }

    /// The shape `color` makes, within `region` (pixels) or the whole image.
    func shape(of color: RGB, in region: CGRect? = nil, tolerance: Int = 24) -> Shape {
        var shape = Shape()
        let area = region ?? CGRect(x: 0, y: 0, width: width, height: height)
        let columns = max(0, Int(area.minX)) ..< min(width, Int(area.maxX))
        let rows = max(0, Int(area.minY)) ..< min(height, Int(area.maxY))
        for y in rows {
            for x in columns where matches(x, y, color, tolerance: tolerance) {
                shape.count += 1
                shape.minX = min(shape.minX, x)
                shape.maxX = max(shape.maxX, x)
                shape.minY = min(shape.minY, y)
                shape.maxY = max(shape.maxY, y)
            }
        }
        guard shape.count > 0 else { return shape }
        // Past the anti-aliased edge.
        let inset = 3
        shape.leftColumn = rows.count { matches(shape.minX + inset, $0, color, tolerance: tolerance) }
        shape.rightColumn = rows.count { matches(shape.maxX - inset, $0, color, tolerance: tolerance) }
        shape.topRow = columns.count { matches($0, shape.minY + inset, color, tolerance: tolerance) }
        shape.bottomRow = columns.count { matches($0, shape.maxY - inset, color, tolerance: tolerance) }
        return shape
    }

    /// How two same-size images differ, per pixel, by the largest channel
    /// difference.
    struct Difference {
        var pixels = 0
        /// Pixels whose largest channel difference exceeds 8.
        var over8 = 0
        /// Pixels whose largest channel difference exceeds 32.
        var over32 = 0
        var maximum = 0

        /// The share of pixels off by more than 8, as a fraction.
        var shareOver8: Double {
            Double(over8) / Double(max(pixels, 1))
        }
    }

    /// The difference against `other`, or `nil` when the sizes differ.
    func difference(from other: PixelGrid) -> Difference? {
        guard width == other.width, height == other.height else { return nil }
        var difference = Difference(pixels: width * height)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let delta = max(
                abs(Int(bytes[index]) - Int(other.bytes[index])),
                abs(Int(bytes[index + 1]) - Int(other.bytes[index + 1])),
                abs(Int(bytes[index + 2]) - Int(other.bytes[index + 2])),
            )
            difference.maximum = max(difference.maximum, delta)
            if delta > 8 { difference.over8 += 1 }
            if delta > 32 { difference.over32 += 1 }
        }
        return difference
    }
}
