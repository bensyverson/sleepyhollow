import Foundation
import SleepyHollow

/// The MIME types the fixture server knows how to emit.
///
/// The raw value is the full `Content-Type` header value.
public enum FixtureContentType: String, Friendly {
    /// `text/html`, the fixture pages themselves.
    case html = "text/html; charset=utf-8"
    /// `text/css`, fixture stylesheets.
    case css = "text/css; charset=utf-8"
    /// `text/javascript`, fixture scripts.
    case javascript = "text/javascript; charset=utf-8"
    /// `image/png`, fixture images.
    case png = "image/png"
    /// `text/plain`, small text assets and dynamic-route replies.
    case plainText = "text/plain; charset=utf-8"
    /// `application/octet-stream`, the fallback for unknown extensions.
    case octetStream = "application/octet-stream"

    /// The content type for a file extension, falling back to ``octetStream``.
    public static func forFileExtension(_ fileExtension: String) -> FixtureContentType {
        switch fileExtension.lowercased() {
        case "html", "htm": .html
        case "css": .css
        case "js", "mjs": .javascript
        case "png": .png
        case "txt": .plainText
        default: .octetStream
        }
    }
}
