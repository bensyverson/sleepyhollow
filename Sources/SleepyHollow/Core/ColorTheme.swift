/// The appearance a page renders under.
///
/// Named themes replace ambient system state: two invocations, two facts, no
/// settings mutation. The default everywhere is ``light`` — deterministic
/// rather than host-matching.
public enum ColorTheme: String, Friendly {
    /// Light appearance.
    case light
    /// Dark appearance.
    case dark
}
