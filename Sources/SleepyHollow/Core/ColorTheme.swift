/// The appearance a page renders under.
///
/// Named themes replace ambient system state: two invocations, two facts, no
/// settings mutation. The default everywhere is ``light`` — deterministic
/// rather than host-matching, so a consumer coming from a raw `WKWebView`
/// (which follows the Mac's own appearance) will see every baseline stop
/// tracking Dark Mode; that shift is deliberate.
///
/// `CaseIterable` so the CLI's `--theme` can name both themes when it refuses
/// a third.
public enum ColorTheme: String, CaseIterable, Friendly {
    /// Light appearance.
    case light
    /// Dark appearance.
    case dark
}
