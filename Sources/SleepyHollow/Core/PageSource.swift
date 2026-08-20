import Foundation

/// The page a verb operates on: a URL to load ephemerally, or a live named
/// session.
///
/// Every page verb takes exactly one page source (the uniform grammar in the
/// vision doc). A ``url(_:)`` source means a fresh load that vanishes when the
/// invocation exits; a ``session(_:)`` source targets the page a helper
/// process already holds.
public enum PageSource: Friendly {
    /// Load this URL in an ephemeral page owned by the invocation.
    case url(URL)
    /// Operate on the live page owned by the named session.
    case session(SessionName)
}
