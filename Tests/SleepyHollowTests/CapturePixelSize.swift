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
