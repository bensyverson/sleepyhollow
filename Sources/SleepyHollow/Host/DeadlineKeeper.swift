import Foundation

/// An owner that bounds each WebKit completion-handler call it makes with a
/// deadline: a ``PageHost`` for its page, a ``HostGroup`` for the cookie
/// store its members share.
///
/// It exists so ``CookieStoreBridge`` can serve both owners and still keep
/// each one's budget — and, for a host, its ``PageHost/abandonedCall``.
@MainActor
protocol DeadlineKeeper: AnyObject {
    /// Seconds a call gets when it names no budget of its own.
    var callBudget: TimeInterval { get }

    /// Starts `call` and waits for its answer, for at most `budget` seconds.
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
    ) async throws -> Value
}
