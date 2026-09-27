import Foundation

extension HostGroup: DeadlineKeeper {
    /// Starts a call into the shared cookie store and waits for its answer —
    /// or for `budget` seconds, or for the caller's cancellation, whichever
    /// comes first.
    ///
    /// The same race as ``PageHost/answer(_:within:start:)``, without the
    /// record: a group is not pooled, so nothing checks it for abandoned
    /// calls, and the member whose load was waiting reports the timeout.
    ///
    /// - Parameter call: what is being called, as the timeout names it.
    /// - Parameter budget: seconds to wait for the answer.
    /// - Parameter start: issues the call, handing WebKit's answer to the
    ///   closure it is given. Called once, synchronously.
    /// - Returns: WebKit's answer.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when the
    ///   budget runs out first, `CancellationError` when the caller is
    ///   cancelled first, and whatever the call itself fails with.
    func answer<Value>(
        _ call: String,
        within budget: TimeInterval,
        start: (_ answered: @escaping @MainActor (Result<Value, any Error>) -> Void) -> Void,
    ) async throws -> Value {
        try await PageCall<Value>.answer(call, within: budget, start: start) { _ in }
    }
}
