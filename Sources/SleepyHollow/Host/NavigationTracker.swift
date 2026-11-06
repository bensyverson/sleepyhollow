import Foundation

/// The host's record of main-frame navigations, and the callers waiting for
/// the next one — the state behind ``PageHost/navigationCount`` and
/// ``PageHost/waitForNavigation(after:budget:)``.
///
/// Fed by `WKNavigationDelegate`'s `didCommit`, which WebKit sends once per
/// main-frame document that becomes the page — a fresh load, a reload, and a
/// back or forward navigation restored from the back-forward cache alike —
/// and never for a same-document change (`history.pushState`,
/// `replaceState`, a fragment). Main-actor isolated like every delegate
/// callback and every caller, so no lock.
@MainActor
final class NavigationTracker {
    /// One caller waiting for a navigation past `threshold`.
    private struct Waiter {
        /// The count the caller has already seen.
        var threshold: Int
        /// Resumed once: with the navigation, `nil` at the deadline, or a
        /// cancellation.
        var continuation: CheckedContinuation<PageHost.Navigation?, any Error>
        /// The deadline's timer, cancelled when anything else ends the wait.
        var deadline: Task<Void, Never>?
    }

    /// Main-frame commits so far.
    private(set) var count: Int = 0

    /// The most recent commit, or `nil` before the first.
    private(set) var latest: PageHost.Navigation?

    /// The waits still pending, by id.
    private var waiters: [Int: Waiter] = [:]

    /// The id the next wait gets.
    private var nextWaiterID: Int = 0

    /// Creates a tracker that has seen no navigation.
    init() {}

    /// Records a main-frame commit at `url` and ends every wait it satisfies.
    func commit(url: URL?) {
        count += 1
        let navigation = PageHost.Navigation(number: count, url: url)
        latest = navigation
        for (id, waiter) in waiters where waiter.threshold < count {
            finish(id, with: .success(navigation))
        }
    }

    /// Waits for a commit past `threshold`, for at most `budget` seconds.
    ///
    /// - Returns: the most recent navigation once the count passes
    ///   `threshold` — at once when it already has — or `nil` when the
    ///   budget runs out first.
    /// - Throws: `CancellationError` when the caller is cancelled first.
    func wait(after threshold: Int, budget: TimeInterval) async throws -> PageHost.Navigation? {
        if count > threshold, let latest { return latest }
        let id: Int = nextWaiterID
        nextWaiterID += 1
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                let deadline = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: WaitEngine.nanoseconds(budget))
                    guard !Task.isCancelled else { return }
                    self?.finish(id, with: .success(nil))
                }
                waiters[id] = Waiter(threshold: threshold, continuation: continuation, deadline: deadline)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finish(id, with: .failure(CancellationError()))
            }
        }
    }

    /// Ends wait `id` with `result`, unless something ended it already.
    private func finish(_ id: Int, with result: Result<PageHost.Navigation?, any Error>) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.deadline?.cancel()
        waiter.continuation.resume(with: result)
    }
}
