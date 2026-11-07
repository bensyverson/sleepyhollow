import Foundation

extension WaitEngine {
    /// When, relative to its deadline, a wait first saw its condition hold.
    enum Sighting: Friendly {
        /// Seen holding by the deadline: the wait settled.
        case inTime
        /// Seen holding only after the deadline: a timeout, whose message
        /// says so rather than claiming the condition never held.
        case late
        /// Not seen holding at all before the race ended.
        case never
    }

    /// Races what the page pushes against a host-side re-check, ending at
    /// `deadline` either way.
    ///
    /// **The deadline is checked where an answer is seen, not only by the
    /// timer.** Each side stamps the moment it saw the condition hold, and
    /// only a stamp at or before `deadline` settles the wait. A host whose
    /// main actor stalls across the deadline — a modal print session, an
    /// embedding's busy loop — would otherwise let a backstop check issued
    /// in time come back true long after it, and report a success the budget
    /// never covered. The stamp is taken when the host *sees* the answer, so
    /// it can only be later than the page's own moment: the error runs toward
    /// an honest timeout, never toward a late success.
    ///
    /// - Parameter accept: whether a pushed message ends the wait.
    /// - Parameter check: the backstop, run every ``backstopInterval``; `nil`
    ///   for a condition only the page can answer, which leaves the deadline
    ///   as the race's other half.
    /// - Returns: when the condition was first seen holding.
    func race(
        by deadline: DispatchTime,
        accepting accept: @escaping @Sendable (String) async -> Bool,
        checking check: (@Sendable () async -> Bool)? = nil,
    ) async -> Sighting {
        let interval: TimeInterval = backstopInterval
        var sighting = Sighting.never
        // Each child answers with the moment it saw the condition hold, or
        // `nil` when it stopped without seeing it.
        await withTaskGroup(of: DispatchTime?.self) { group in
            if let stream = pushes {
                group.addTask {
                    for await text in stream {
                        if await accept(text) { return DispatchTime.now() }
                    }
                    return nil
                }
            }
            if let check {
                group.addTask {
                    while DispatchTime.now() < deadline {
                        // Never sleep past the deadline: the backstop is the
                        // slow half of this race, and a settle phase that
                        // outlives its budget is the hang the whole engine
                        // exists to rule out.
                        try? await Task.sleep(nanoseconds: Self.nanoseconds(interval, notPast: deadline))
                        guard !Task.isCancelled, DispatchTime.now() < deadline else { return nil }
                        if await check() { return DispatchTime.now() }
                    }
                    return nil
                }
            } else {
                group.addTask {
                    try? await Task.sleep(nanoseconds: Self.nanoseconds(.infinity, notPast: deadline))
                    return nil
                }
            }
            while let result = await group.next() {
                if let seen = result {
                    sighting = Self.sighting(at: seen, by: deadline)
                    break
                }
                if DispatchTime.now() >= deadline { break }
            }
            group.cancelAll()
        }
        return sighting
    }

    /// Classifies a moment the condition was seen holding against `deadline`.
    static func sighting(at seen: DispatchTime, by deadline: DispatchTime) -> Sighting {
        seen <= deadline ? .inTime : .late
    }

    /// Whether a quiet window that began at `quietSince` closed by `deadline`
    /// — the only quiet that settles `--wait-for idle`, however late the
    /// sample confirming it came back.
    static func quietWindowClosed(quietSince: DispatchTime, by deadline: DispatchTime) -> Bool {
        quietSince + IdleWatch.quietWindow <= deadline
    }

    /// The sentence a timeout adds when the condition did come about, but was
    /// first seen after the deadline.
    static let heldLateDetail: String = "It did happen, but was first seen only after the budget ran out, "
        + "which does not count — a busy host can see an answer late."
}
