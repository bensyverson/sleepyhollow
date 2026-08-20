/// The documented exit-code scheme, uniform across every verb.
///
/// Agents branch on these numbers, so they are a public contract:
/// | Code | Meaning |
/// | ---- | ------- |
/// | 0 | Success / assertion true |
/// | 1 | Clean negative (`--exists` absent, `find` without a match) |
/// | 2 | Usage error |
/// | 3 | Timeout — budget exhausted, last state attached |
/// | 4 | Load or navigation failure |
/// | 5 | Environment error (no such session, dead helper, bad jar) |
public enum ExitStatus: Int32, Friendly {
    /// Success, or the asserted condition holds.
    case success = 0
    /// The asserted condition cleanly does not hold.
    case negative = 1
    /// The invocation itself was malformed.
    case usage = 2
    /// The budget ran out before the condition was met.
    case timeout = 3
    /// The page failed to load or navigate.
    case loadFailure = 4
    /// The tool's environment is wrong: missing session, dead helper, bad jar.
    case environment = 5
}
