/// The encodings a verb can emit.
///
/// Each verb defaults to its tersest faithful form — HTML for `dom`, an
/// indented outline for `ax`, JSON where the data is inherently structured —
/// and a stable JSON shape is always one `--format json` away. Output never
/// depends on the environment: the same invocation emits the same bytes in a
/// pipe and in a terminal.
public enum OutputFormat: String, Friendly {
    /// The stable machine shape, available from every verb.
    case json
    /// The page's native markup (default for `dom`).
    case html
    /// Terse lines for humans and token-frugal agents.
    case text
    /// The indented accessibility outline (default for `ax`).
    case outline
}
