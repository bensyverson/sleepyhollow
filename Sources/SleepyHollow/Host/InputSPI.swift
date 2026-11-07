import Foundation

/// The `WKWebView` SPI real input rests on, named once so ``TrustedInput``
/// calls it and `sleepy doctor` checks it from the same list.
///
/// Approved for shipping use on 2026-11-06 (leaf `XerXuw`), on condition that
/// ``Doctor/checkInput(selectors:)`` reports when a macOS lacks any of them.
enum InputSPI {
    /// Moves the pointer in a window that is not frontmost; the only route to
    /// `:hover` in the off-screen host.
    static let simulateMouseMove: String = "_simulateMouseMove:"

    /// Calls back once every queued key event has reached the page.
    static let afterPendingKeyEvents: String = "_doAfterProcessingAllPendingKeyEvents:"

    /// Calls back once every queued mouse event has reached the page.
    static let afterPendingMouseEvents: String = "_doAfterProcessingAllPendingMouseEvents:"

    /// Every selector above.
    static let all: [String] = [simulateMouseMove, afterPendingKeyEvents, afterPendingMouseEvents]
}
