import Darwin

/// Answers whether a process id is still running — the first half of a
/// session's liveness probe.
enum ProcessProbe {
    /// Whether a process with `identifier` exists.
    ///
    /// `kill(pid, 0)` sends no signal: it succeeds when the process exists and
    /// we may signal it, and reports `EPERM` when it exists under another
    /// user — which still means *alive*, so both count. Only `ESRCH` (no such
    /// process) is death.
    static func isAlive(_ identifier: Int32) -> Bool {
        guard identifier > 0 else { return false }
        if kill(identifier, 0) == 0 { return true }
        return errno == EPERM
    }
}
