/// A computed ARIA role, as a string the wire keeps verbatim.
///
/// The role vocabulary is open — WAI-ARIA grows, and pages use roles this
/// build has never heard of — so the type wraps a string rather than closing
/// over an enum. The roles the tool itself reasons about have constants, so
/// no comparison is spelled with a bare literal.
public struct AXRole: Friendly, RawRepresentable, ExpressibleByStringLiteral, CustomStringConvertible {
    /// The role token, exactly as the accessibility computation reported it.
    public let rawValue: String

    /// Creates a role from its token.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates a role from a literal, so `let role: AXRole = "button"` reads.
    public init(stringLiteral value: String) {
        rawValue = value
    }

    /// The role token.
    public var description: String {
        rawValue
    }

    /// Decodes from a bare JSON string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    /// Encodes as a bare JSON string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The roles the tool names in code: the outline's structural cases and the
/// widgets the fixtures assert on.
public extension AXRole {
    /// A page or frame's document node — the root of every tree.
    static let document: AXRole = "document"
    /// A run of text with no semantics of its own.
    static let text: AXRole = "text"
    /// An element with no role of its own; the outline collapses unnamed ones.
    static let generic: AXRole = "generic"
    /// An element removed from the tree by `role="presentation"`/`"none"`.
    static let presentation: AXRole = "presentation"

    /// A button.
    static let button: AXRole = "button"
    /// A hyperlink.
    static let link: AXRole = "link"
    /// A heading; its depth rides along as ``AXState/Name/level``.
    static let heading: AXRole = "heading"
    /// A paragraph of text.
    static let paragraph: AXRole = "paragraph"
    /// An image.
    static let image: AXRole = "image"
    /// A figure.
    static let figure: AXRole = "figure"

    /// A single-line or multi-line text input.
    static let textbox: AXRole = "textbox"
    /// A search input.
    static let searchbox: AXRole = "searchbox"
    /// A checkbox, which may be `mixed`.
    static let checkbox: AXRole = "checkbox"
    /// A radio button.
    static let radio: AXRole = "radio"
    /// An on/off switch.
    static let `switch`: AXRole = "switch"
    /// A select or other value picker.
    static let combobox: AXRole = "combobox"
    /// A list of options.
    static let listbox: AXRole = "listbox"
    /// One option of a listbox or combobox.
    static let option: AXRole = "option"
    /// A slider.
    static let slider: AXRole = "slider"
    /// A progress bar.
    static let progressbar: AXRole = "progressbar"

    /// A form.
    static let form: AXRole = "form"
    /// A generic grouping, such as a fieldset.
    static let group: AXRole = "group"
    /// A list.
    static let list: AXRole = "list"
    /// One item of a list.
    static let listitem: AXRole = "listitem"
    /// A data table.
    static let table: AXRole = "table"
    /// A table's `thead`/`tbody`/`tfoot`.
    static let rowgroup: AXRole = "rowgroup"
    /// A table row.
    static let row: AXRole = "row"
    /// A table cell.
    static let cell: AXRole = "cell"
    /// A column header cell.
    static let columnheader: AXRole = "columnheader"
    /// A row header cell.
    static let rowheader: AXRole = "rowheader"
    /// A table's caption.
    static let caption: AXRole = "caption"

    /// The page's banner landmark.
    static let banner: AXRole = "banner"
    /// The page's navigation landmark.
    static let navigation: AXRole = "navigation"
    /// The page's main landmark.
    static let main: AXRole = "main"
    /// The page's footer landmark.
    static let contentinfo: AXRole = "contentinfo"
    /// A named region landmark.
    static let region: AXRole = "region"
    /// A search landmark.
    static let search: AXRole = "search"
}
