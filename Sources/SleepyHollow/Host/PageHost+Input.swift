import Foundation

/// Real keyboard input for embedders: the library face of `sleepy press`.
///
/// Both calls run ``PressOperation``, so a library caller, a one-shot
/// `--press`/`--type` step and a session's `press` verb cannot drift apart.
/// The keys arrive with `isTrusted` true and run their default actions; see
/// ``PressOperation`` for what that covers, and ``TrustedInput`` for how.
///
/// ```swift
/// try await host.type("webkit", focusing: "#q")
/// let outcome = try await host.press([KeyChord(parsing: "Enter")])
/// if outcome.startedNavigation { … }
/// ```
public extension PageHost {
    /// Presses `keys` in order on whatever has focus — or on `selector`'s
    /// first match, focused first as by keyboard.
    ///
    /// - Parameter keys: the chords to press, in order.
    /// - Parameter selector: an element to focus first; `nil` leaves focus
    ///   where it is.
    /// - Returns: what had focus, its value afterwards, and whether the keys
    ///   set the page navigating.
    /// - Throws: everything ``PressOperation/execute(on:)`` throws — a usage
    ///   error on a ``Hosting/windowless`` host among them.
    @discardableResult
    func press(_ keys: [KeyChord], focusing selector: String? = nil) async throws -> ActionOutcome {
        try await execute(PressOperation(keys: keys, selector: selector))
    }

    /// Types `text` one real keystroke per character into whatever has focus
    /// — or into `selector`'s first match, focused first.
    ///
    /// A newline is Enter and a tab is Tab, so `"hi\n"` types and submits.
    ///
    /// - Parameter text: the text to type.
    /// - Parameter selector: an element to focus first; `nil` leaves focus
    ///   where it is.
    /// - Returns: what had focus, its value afterwards, and whether typing set
    ///   the page navigating.
    /// - Throws: everything ``PressOperation/execute(on:)`` throws.
    @discardableResult
    func type(_ text: String, focusing selector: String? = nil) async throws -> ActionOutcome {
        try await execute(PressOperation(text: text, selector: selector))
    }
}
