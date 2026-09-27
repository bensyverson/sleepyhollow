import Foundation

/// One call into the page, and the continuation its caller waits on — resumed
/// exactly once, by whichever of WebKit's answer, the deadline or the
/// caller's cancellation arrives first.
///
/// The three racers arrive in no fixed order and the losers still arrive: a
/// page that answers after its deadline calls its completion handler all the
/// same, and a `CheckedContinuation` resumed twice is a crash. So every
/// racer goes through ``finish(_:)``, and only the first one's result is
/// delivered. A finish that lands before the continuation is armed is kept
/// and delivered on arming, so no order of events leaves the caller waiting.
///
/// Main-actor isolated because every racer already is, or hops there: WebKit
/// calls its completion handlers on the main thread, the deadline is a
/// main-actor task, and the cancellation handler hops. One isolation domain
/// means no lock.
@MainActor
final class PageCall<Value> {
    /// The answer as it crosses the continuation.
    ///
    /// A continuation carries only `Sendable` values, and what WebKit answers
    /// need not be one — `NSImage` is not below macOS 14. Every racer and the
    /// caller are on the main actor, so the value never actually crosses an
    /// isolation boundary; a main-actor class says exactly that to the
    /// checker, without an unchecked conformance.
    @MainActor
    final class Delivery: Sendable {
        /// The page's answer.
        let value: Value

        /// Wraps an answer.
        init(_ value: Value) {
            self.value = value
        }
    }

    /// Where the call stands.
    private enum State {
        /// Neither armed nor finished.
        case idle
        /// Armed, waiting for the first racer.
        case armed(CheckedContinuation<Delivery, any Error>)
        /// Finished before it was armed.
        case early(Result<Delivery, any Error>)
        /// Resumed; every later finish is dropped.
        case done
    }

    private var state: State = .idle

    /// The deadline's timer, cancelled as soon as any racer wins.
    var deadline: Task<Void, Never>?

    /// Creates a call that has neither started nor finished.
    init() {}

    /// Hands the call the continuation its caller waits on, delivering at
    /// once a result that arrived first.
    func arm(_ continuation: CheckedContinuation<Delivery, any Error>) {
        switch state {
        case .idle:
            state = .armed(continuation)
        case let .early(result):
            state = .done
            continuation.resume(with: result)
        case .armed, .done:
            // A second arm is a programming error, and resuming either
            // continuation here could only resume one of them twice.
            assertionFailure("PageCall armed twice")
        }
    }

    /// Ends the call with `result` unless something ended it already.
    ///
    /// - Returns: `true` when this finish is the one that ended the call —
    ///   which is how the deadline and the cancellation handler know that
    ///   *they* abandoned it, rather than arriving after an answer.
    @discardableResult
    func finish(_ result: Result<Value, any Error>) -> Bool {
        let delivered: Result<Delivery, any Error> = result.map { Delivery($0) }
        switch state {
        case .idle:
            state = .early(delivered)
        case let .armed(continuation):
            state = .done
            continuation.resume(with: delivered)
        case .early, .done:
            return false
        }
        deadline?.cancel()
        deadline = nil
        return true
    }
}
