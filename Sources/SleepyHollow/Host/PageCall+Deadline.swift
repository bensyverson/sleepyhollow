import Foundation

extension PageCall {
    /// Starts a WebKit call and waits for its answer — or for `budget`
    /// seconds, or for the caller's cancellation, whichever comes first.
    ///
    /// The race itself, without an owner: ``PageHost/answer(_:within:start:)``
    /// records what it abandons on the host, and a ``HostGroup`` keeps the
    /// same deadline on its shared cookie store.
    ///
    /// - Parameter call: what is being called, as the timeout names it.
    /// - Parameter budget: seconds to wait for the answer.
    /// - Parameter start: issues the call, handing WebKit's answer to the
    ///   closure it is given. Called once, synchronously.
    /// - Parameter abandoned: told why, when the deadline or the cancellation
    ///   ends the call before WebKit answers it.
    /// - Returns: WebKit's answer.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when the
    ///   budget runs out first, `CancellationError` when the caller is
    ///   cancelled first, and whatever the call itself fails with.
    static func answer(
        _ call: String,
        within budget: TimeInterval,
        start: (_ answered: @escaping @MainActor (Result<Value, any Error>) -> Void) -> Void,
        abandoned: @escaping @MainActor (PageHost.AbandonedCall.Reason) -> Void,
    ) async throws -> Value {
        try Task.checkCancellation()
        let pending = PageCall<Value>()
        let delivery: Delivery = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.arm(continuation)
                pending.deadline = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, budget) * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    if pending.finish(.failure(unanswered(call, within: budget))) {
                        abandoned(.deadline(budget))
                    }
                }
                start { result in pending.finish(result) }
            }
        } onCancel: {
            Task { @MainActor in
                if pending.finish(.failure(CancellationError())) {
                    abandoned(.cancelled)
                }
            }
        }
        return delivery.value
    }

    /// The timeout for a call WebKit did not answer in time.
    ///
    /// "WebKit", not "the page": a cookie call is answered by the networking
    /// process, which no page script can stall.
    private static func unanswered(_ call: String, within budget: TimeInterval) -> SleepyError {
        SleepyError(
            kind: .timeout,
            message: "WebKit did not answer \(call) within \(budget)s.",
            nextMove: "The page holds a promise it never settles, a WebKit process (content or networking) has "
                + "stalled, or the machine is too loaded to run it. A host that gave up on a call is marked "
                + "abandoned, so use a fresh one; raise the call budget only if the page is merely slow.",
        )
    }
}
