import Foundation

extension PageHost {
    /// Starts a call into the page and waits for its answer — or for
    /// `budget` seconds, or for the caller's cancellation, whichever comes
    /// first.
    ///
    /// Every WebKit call the host makes that ends in a completion handler
    /// goes through here, because a completion handler has no deadline of
    /// its own: a page that never settles an evaluated promise, or a content
    /// process that stops answering, never calls it, and an `await` on it is
    /// suspended for good — no thread, no stack, nothing in a `sample`.
    ///
    /// The call is *abandoned*, not awaited: when the deadline or the
    /// cancellation wins, the caller is resumed at once and WebKit's answer,
    /// if it ever comes, is dropped (``PageCall``). The host records the
    /// abandonment in ``abandonedCall``, because the call may still be
    /// running in the page.
    ///
    /// - Parameter call: what is being called, as the timeout and
    ///   ``AbandonedCall/call`` name it.
    /// - Parameter budget: seconds to wait for the answer.
    /// - Parameter start: issues the call, handing WebKit's answer to the
    ///   closure it is given. Called once, synchronously.
    /// - Returns: the page's answer.
    /// - Throws: ``SleepyError`` of kind ``SleepyError/Kind/timeout`` when the
    ///   budget runs out first, `CancellationError` when the caller is
    ///   cancelled first, and whatever the call itself fails with.
    func answer<Value>(
        _ call: String,
        within budget: TimeInterval,
        start: (_ answered: @escaping @MainActor (Result<Value, any Error>) -> Void) -> Void,
    ) async throws -> Value {
        try Task.checkCancellation()
        let pending = PageCall<Value>()
        let delivery: PageCall<Value>.Delivery = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending.arm(continuation)
                pending.deadline = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(max(0, budget) * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    if pending.finish(.failure(Self.unanswered(call, within: budget))) {
                        self?.abandon(call, because: .deadline(budget))
                    }
                }
                start { result in pending.finish(result) }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                if pending.finish(.failure(CancellationError())) {
                    self?.abandon(call, because: .cancelled)
                }
            }
        }
        return delivery.value
    }

    /// Records the first call this host gave up on; later ones add nothing a
    /// pool needs to know.
    private func abandon(_ call: String, because reason: AbandonedCall.Reason) {
        guard abandonedCall == nil else { return }
        abandonedCall = AbandonedCall(call: call, reason: reason)
    }

    /// The timeout for a call the page did not answer in time.
    private static func unanswered(_ call: String, within budget: TimeInterval) -> SleepyError {
        SleepyError(
            kind: .timeout,
            message: "The page did not answer \(call) within \(budget)s.",
            nextMove: "The page holds a promise it never settles, its content process has stalled, or the "
                + "machine is too loaded to run it. This host is now marked abandoned, so use a fresh one; "
                + "raise the call budget only if the page is merely slow.",
        )
    }

    /// How a timeout names an evaluated body: its first non-empty line,
    /// short enough to read.
    static func describing(evaluation body: String) -> String {
        let line: Substring = body.split(whereSeparator: \.isNewline).first { !$0.allSatisfy(\.isWhitespace) } ?? ""
        let trimmed: String = line.trimmingCharacters(in: .whitespaces)
        let excerpt: String = trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
        return "evaluate `\(excerpt)`"
    }
}
