import Foundation

/// Bounds how many WebKit instances the test suite keeps live at once.
///
/// Swift Testing runs every suite concurrently, and each WebKit test is
/// expensive out of proportion to its code: an in-process test owns a
/// `WKWebView` (and its web-content subprocess), a golden test spawns a whole
/// `sleepy` binary that owns another. Unbounded, a full run has dozens of
/// WebKit instances contending for CPU and the main actor, and wall-clock
/// budgets that hold comfortably in isolation blow out in the tail — the
/// suite's one historical source of flakes.
///
/// ``FixtureServer/withRunning(fixturesDirectory:_:)`` acquires the shared
/// gate around every test body, so every current and future WebKit test is
/// bounded without opting in. The width trades tail latency against wall
/// time; it was measured, not guessed — see `project/gotchas.md`'s retired
/// golden-contention entry for the history.
///
/// Waiters are woken first-in-first-out and ignore task cancellation (a
/// cancelled test still passes through briefly and releases; the body's own
/// cancellation checks apply). Do not nest acquisitions.
public actor WebKitGate {
    /// The gate every WebKit test flows through.
    public static let shared = WebKitGate(width: 8)

    /// How many holders may be live at once.
    public let width: Int

    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Creates a gate admitting `width` concurrent holders.
    public init(width: Int) {
        self.width = max(1, width)
    }

    /// Waits for a slot; every `acquire` must be paired with one ``release()``.
    public func acquire() async {
        if active < width {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Returns the slot, waking the longest-waiting acquirer if any.
    ///
    /// The slot is handed over directly — `active` stays constant — so a
    /// release-acquire race can never overshoot the width.
    public func release() {
        if waiters.isEmpty {
            active -= 1
        } else {
            waiters.removeFirst().resume()
        }
    }
}
