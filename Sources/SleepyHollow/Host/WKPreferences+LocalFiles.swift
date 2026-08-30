import Foundation
import WebKit

/// The one place in this package that spells the private
/// `allowFileAccessFromFileURLs` key.
extension WKPreferences {
    /// The private KVC key that lets a `file:` document's own scripts read
    /// `file:` URLs. A `file:` document has an opaque origin, so `fetch()` and
    /// `XMLHttpRequest` against a local file are refused by default and there
    /// is no public API to allow them.
    private static let allowFileAccessKey = "allowFileAccessFromFileURLs"

    /// Lets a `file:` page's own scripts read local files.
    ///
    /// **This is the grant that matters, and it is not the one the feedback
    /// predicted.** Measured 2026-08-29 against `file-fetch.html`:
    /// `WKWebView.loadFileURL(_:allowingReadAccessTo:)` alone leaves `fetch()`
    /// and `XMLHttpRequest` failing with "Load failed", with or without a read
    /// access root; this preference alone makes both succeed, with or without
    /// `loadFileURL`. The read-access root still earns its place — it is what
    /// bounds *subresource* loading to a directory subtree, and `loadFileURL`
    /// refuses a page that is not under it — but it grants a script nothing.
    ///
    /// WebKit does **not** bound this to that root: with a root of the
    /// fixtures directory, a page still read `file:///etc/hosts` (measured the
    /// same day). ``LoadOptions/fileAccessRoot`` therefore says *whether* a
    /// page may read local files, not *which* ones, and that is what its DocC
    /// promises.
    ///
    /// Like ``WKWebView/applyBackdrop(_:)``, this is one internal function
    /// spelling one private key, under the ruling in
    /// `project/2026-08-29-woodcase-harness-plan.md`.
    ///
    /// - Returns: `true` when the preference took — the canary in
    ///   `PageHostFileAccessTests` asserts a page actually reads its sibling,
    ///   which is the same claim measured end to end.
    @discardableResult
    func allowLocalFileReads() -> Bool {
        guard responds(to: NSSelectorFromString("setAllowFileAccessFromFileURLs:"))
            || responds(to: NSSelectorFromString("_setAllowFileAccessFromFileURLs:"))
        else {
            return false
        }
        setValue(true, forKey: Self.allowFileAccessKey)
        return true
    }
}
