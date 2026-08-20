import Foundation
import SleepyHollow

/// The shared fixture pages every verb family's TDD leans on.
///
/// Each case is one file under `Tests/TestSupport/Fixtures/`; families add
/// their own fixtures later in their own files. The raw value is the file
/// name inside the fixtures directory.
public enum FixturePage: String, CaseIterable, Friendly {
    /// Static text with a heading and an identifiable paragraph.
    case staticText = "static.html"
    /// Labelled inputs, a submit button, and a disabled button named "Publish".
    case form = "form.html"
    /// Buttons raising `alert`/`confirm`/`prompt`; `?auto` raises all three on load.
    case dialogs = "dialogs.html"
    /// `prefers-color-scheme`-aware styles reporting the resolved mode in the DOM.
    case theme = "theme.html"
    /// References a stylesheet and an image through the server's delay route.
    case slowResource = "slow.html"
    /// Fires a GET and a urlencoded POST sequentially on load, logging statuses.
    case fetch = "fetch.html"
    /// Renders `document.cookie`; served via the cookie-setting route.
    case cookie = "cookie.html"

    /// The page's file name inside the fixtures directory.
    public var fileName: String {
        rawValue
    }

    /// The request path that serves this page.
    ///
    /// The cookie page routes through ``FixtureServer``'s `/cookie` route so
    /// loading it also sets the fixture cookie.
    public var path: String {
        switch self {
        case .cookie: "/cookie"
        default: "/" + rawValue
        }
    }
}
