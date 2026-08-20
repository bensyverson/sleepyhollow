/// The shared validation rule for names that become directories under
/// `~/.sleepyhollow` — a security boundary (path traversal), not a style
/// preference.
///
/// Implemented as a plain character walk because Swift `Regex` requires
/// macOS 13 and the package floor is 12.
enum StateNameRule {
    /// The longest name accepted, chosen to stay well inside filesystem limits.
    static let maximumLength = 64

    /// Whether `raw` is safe to use as an on-disk state name: ASCII
    /// alphanumeric first character, then alphanumerics plus `.`, `_`, `-`,
    /// at most ``maximumLength`` characters.
    static func isValid(_ raw: String) -> Bool {
        guard !raw.isEmpty, raw.count <= maximumLength else { return false }
        for (index, scalar) in raw.unicodeScalars.enumerated() {
            let isAlphanumeric = (scalar >= "a" && scalar <= "z")
                || (scalar >= "A" && scalar <= "Z")
                || (scalar >= "0" && scalar <= "9")
            let isExtra = scalar == "." || scalar == "_" || scalar == "-"
            if index == 0 {
                guard isAlphanumeric else { return false }
            } else {
                guard isAlphanumeric || isExtra else { return false }
            }
        }
        return true
    }
}
