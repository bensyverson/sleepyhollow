import AppKit
import CoreGraphics

/// An sRGB RGBA8 copy of an image, for counting and comparing pixels.
struct Pixels {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(_ image: CGImage) {
        width = image.width
        height = image.height
        bytes = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(
            data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
        )!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
    }

    func matches(_ x: Int, _ y: Int, _ color: (Int, Int, Int), tolerance: Int = 24) -> Bool {
        let (r, g, b) = rgb(x, y)
        return abs(r - color.0) <= tolerance && abs(g - color.1) <= tolerance && abs(b - color.2) <= tolerance
    }

    /// The extent of `color`, plus the vertical span of its leftmost and
    /// rightmost columns and the horizontal span of its top and bottom rows —
    /// enough to tell a trapezoid from a rectangle.
    struct Shape: CustomStringConvertible {
        var count = 0
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        var leftSpan = 0, rightSpan = 0, topSpan = 0, bottomSpan = 0
        var description: String {
            count == 0 ? "absent" :
                "bbox x \(minX)–\(maxX) y \(minY)–\(maxY); column height left \(leftSpan) right \(rightSpan); row width top \(topSpan) bottom \(bottomSpan); \(count) px"
        }
    }

    func shape(of color: (Int, Int, Int), in region: CGRect? = nil, tolerance: Int = 24) -> Shape {
        var shape = Shape()
        let r = region ?? CGRect(x: 0, y: 0, width: width, height: height)
        let x0 = max(0, Int(r.minX)), x1 = min(width, Int(r.maxX)), y0 = max(0, Int(r.minY)), y1 = min(height, Int(r.maxY))
        for y in y0 ..< y1 {
            for x in x0 ..< x1 where matches(x, y, color, tolerance: tolerance) {
                shape.count += 1
                shape.minX = min(shape.minX, x); shape.maxX = max(shape.maxX, x)
                shape.minY = min(shape.minY, y); shape.maxY = max(shape.maxY, y)
            }
        }
        guard shape.count > 0 else { return shape }
        // Sample a few pixels in from each edge, past anti-aliasing.
        let inset = 3
        shape.leftSpan = (y0 ..< y1).count(where: { matches(shape.minX + inset, $0, color, tolerance: tolerance) })
        shape.rightSpan = (y0 ..< y1).count(where: { matches(shape.maxX - inset, $0, color, tolerance: tolerance) })
        shape.topSpan = (x0 ..< x1).count(where: { matches($0, shape.minY + inset, color, tolerance: tolerance) })
        shape.bottomSpan = (x0 ..< x1).count(where: { matches($0, shape.maxY - inset, color, tolerance: tolerance) })
        return shape
    }

    /// How two same-size images differ: per-channel absolute differences.
    struct Diff: CustomStringConvertible {
        var total = 0, over2 = 0, over8 = 0, over32 = 0, maxDelta = 0
        var sum = 0.0
        var description: String {
            String(format: "max Δ %d, mean Δ %.3f, pixels Δ>2 %d (%.2f%%), Δ>8 %d (%.2f%%), Δ>32 %d (%.2f%%) of %d",
                   maxDelta, sum / Double(max(total, 1) * 3), over2, 100 * Double(over2) / Double(max(total, 1)),
                   over8, 100 * Double(over8) / Double(max(total, 1)), over32, 100 * Double(over32) / Double(max(total, 1)), total)
        }
    }

    func diff(_ other: Pixels) -> Diff? {
        guard width == other.width, height == other.height else { return nil }
        var diff = Diff()
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let d = max(abs(Int(bytes[i]) - Int(other.bytes[i])), abs(Int(bytes[i + 1]) - Int(other.bytes[i + 1])), abs(Int(bytes[i + 2]) - Int(other.bytes[i + 2])))
            diff.total += 1
            diff.sum += Double(abs(Int(bytes[i]) - Int(other.bytes[i])) + abs(Int(bytes[i + 1]) - Int(other.bytes[i + 1])) + abs(Int(bytes[i + 2]) - Int(other.bytes[i + 2])))
            diff.maxDelta = max(diff.maxDelta, d)
            if d > 2 { diff.over2 += 1 }
            if d > 8 { diff.over8 += 1 }
            if d > 32 { diff.over32 += 1 }
        }
        return diff
    }

    /// A gray image of where two images differ by more than 8, for eyeballing.
    func diffImage(_ other: Pixels) -> CGImage? {
        guard width == other.width, height == other.height else { return nil }
        var out = [UInt8](repeating: 255, count: bytes.count)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            let d = max(abs(Int(bytes[i]) - Int(other.bytes[i])), abs(Int(bytes[i + 1]) - Int(other.bytes[i + 1])), abs(Int(bytes[i + 2]) - Int(other.bytes[i + 2])))
            let v: UInt8 = d > 8 ? 0 : 230
            out[i] = d > 8 ? 255 : v; out[i + 1] = v; out[i + 2] = v
        }
        let context = CGContext(data: &out, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()
    }
}

func writePNG(_ image: CGImage, to path: String) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}

/// The process's physical footprint in MB — what Activity Monitor calls Memory.
func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}

func loadAverage() -> String {
    var loads = [Double](repeating: 0, count: 3)
    getloadavg(&loads, 3)
    return String(format: "load %.2f %.2f %.2f", loads[0], loads[1], loads[2])
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
}

func percentile(_ values: [Double], _ p: Double) -> Double {
    let sorted = values.sorted()
    return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
}
