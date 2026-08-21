import AppKit

public extension ColorTheme {
    /// The `NSAppearance.Name` this theme renders under.
    ///
    /// Set on the web view itself, which is what makes `prefers-color-scheme`
    /// resolve without a window, an `NSApplication`, or any ambient system
    /// state — the named theme replaces the environment.
    var appearanceName: NSAppearance.Name {
        switch self {
        case .light: .aqua
        case .dark: .darkAqua
        }
    }
}
