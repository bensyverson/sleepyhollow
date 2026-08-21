/// What ``QueryOperation`` reports about one matched element: the facts an
/// agent needs without parsing HTML — "is there exactly one identity
/// control on this page?" answered without an agent holding a DOM parser in
/// its head.
public struct ElementFact: Friendly {
    /// One element's border-box rect in CSS pixels, from
    /// `getBoundingClientRect()`.
    public struct Geometry: Friendly {
        /// Left edge, relative to the viewport.
        public var x: Double
        /// Top edge, relative to the viewport.
        public var y: Double
        /// Border-box width.
        public var width: Double
        /// Border-box height.
        public var height: Double

        /// Creates a geometry fact.
        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    /// The lowercased tag name, e.g. `"button"`.
    public var tagName: String

    /// The element's rendered text (`innerText`, trimmed): what a sighted
    /// user would read, not the raw text-node content — collapsed
    /// whitespace, hidden descendants excluded, block boundaries as line
    /// breaks.
    public var text: String

    /// Every attribute, name to value, exactly as written (boolean
    /// attributes like `disabled` carry an empty string).
    public var attributes: [String: String]

    /// The element's border-box rect.
    public var geometry: Geometry

    /// Whether the element renders at all.
    ///
    /// **Definition** (see ``QueryOperation`` for the full reasoning):
    /// computed `display` is not `none`, computed `visibility` is not
    /// `hidden`/`collapse`, computed `opacity` is greater than `0`, and the
    /// border-box rect has nonzero width or height. `visibility` is an
    /// inherited CSS property, so a hidden ancestor is caught through the
    /// element's own computed value; a `display: none` ancestor is caught
    /// because it collapses this element's own rect to zero. An ancestor's
    /// `opacity: 0` is **not** caught — `getComputedStyle` never multiplies
    /// opacity through ancestors — so a transparent element inside an
    /// opaque one still reads `visible: true`.
    public var visible: Bool

    /// Creates an element fact.
    public init(
        tagName: String,
        text: String,
        attributes: [String: String],
        geometry: Geometry,
        visible: Bool,
    ) {
        self.tagName = tagName
        self.text = text
        self.attributes = attributes
        self.geometry = geometry
        self.visible = visible
    }
}
