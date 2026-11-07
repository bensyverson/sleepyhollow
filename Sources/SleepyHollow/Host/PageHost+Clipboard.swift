import Foundation

public extension PageHost {
    /// Whose clipboard pages use: this process's own pasteboard by default,
    /// so a page that copies never overwrites the clipboard of whoever runs
    /// the process, and a page that pastes never reads it.
    ///
    /// **Creating a ``PageHost`` redirects this process's general
    /// pasteboard** (and pins the app accent color, see `AccentPin`). The
    /// redirect is process-wide: anything else in the process that asks
    /// `NSPasteboard.general` gets the private pasteboard too. An embedder
    /// with its own UI sets ``ClipboardIsolation/shared`` — before creating
    /// its first host or at any later time, because the change takes effect
    /// immediately and restores AppKit's own behavior:
    ///
    /// ```swift
    /// PageHost.clipboardIsolation = .shared
    /// ```
    ///
    /// Private pasteboard behavior rests on replacing public AppKit class
    /// methods; `sleepy doctor` reports whether it took (`pasteboard`).
    static var clipboardIsolation: ClipboardIsolation = .isolated {
        didSet { PasteboardIsolation.apply(clipboardIsolation) }
    }
}
