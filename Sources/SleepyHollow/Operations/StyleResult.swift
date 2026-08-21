/// What ``StyleOperation`` returns: whether the selector matched, and the
/// requested properties' computed values when it did.
public struct StyleResult: Friendly {
    /// Whether the selector matched an element. `false` means an empty
    /// ``values`` — there is nothing to compute style for.
    public var matched: Bool

    /// Each requested property's computed value, keyed by the property name
    /// exactly as given (kebab-case, e.g. `"background-color"`). A property
    /// `getComputedStyle` does not recognize reports its own empty string —
    /// the same honest answer the platform gives, not a synthesized error.
    public var values: [String: String]

    /// Creates a style result.
    public init(matched: Bool, values: [String: String]) {
        self.matched = matched
        self.values = values
    }
}
