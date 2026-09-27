import Foundation

public extension PageHost {
    /// A call into the page that the host stopped waiting for before the page
    /// answered — the fact that makes a host unsafe to reuse.
    ///
    /// WebKit cannot take back a call it has started: an evaluation whose
    /// promise the page never settles, or a snapshot queued behind a stalled
    /// content process, stays outstanding after its caller has been told
    /// ``SleepyError/Kind/timeout``. The page may still be running it, or
    /// holding the process that would run the next one. A pool that hands
    /// such a host to the next caller hands over that stall too, so a pool
    /// checks ``PageHost/abandonedCall`` and discards the host instead.
    struct AbandonedCall: Friendly {
        /// Why the host stopped waiting.
        public enum Reason: Friendly {
            /// The call's deadline passed, in seconds, before the page answered.
            case deadline(TimeInterval)
            /// The caller's task was cancelled while the call was in flight.
            case cancelled
        }

        /// What was called, as a timeout names it — `evaluate` with the
        /// body's first line, `snapshot`, the console count a load ends with.
        public let call: String

        /// Why the host stopped waiting for it.
        public let reason: Reason

        /// Records an abandoned call.
        ///
        /// - Parameter call: what was called.
        /// - Parameter reason: why the host stopped waiting.
        public init(call: String, reason: Reason) {
            self.call = call
            self.reason = reason
        }
    }
}
