import Foundation

/// Whose clipboard a page's copy and paste use.
///
/// Set it through ``PageHost/clipboardIsolation``.
public enum ClipboardIsolation: String, Friendly, CaseIterable {
    /// Pages copy into, and paste from, a pasteboard private to this
    /// process; the user's clipboard is never written or read. The default.
    case isolated

    /// Pages use the system's general pasteboard, as in any browser. For an
    /// embedder with its own UI, where the user expects copy to reach the
    /// clipboard.
    case shared
}
