/// A CSS-pixel rectangle in **document** coordinates: the page's own space,
/// with the scroll offset already added in.
///
/// This is the coordinate system `sleepy.rect(selector)` answers in and the
/// one ``OverflowReport`` measures against, deliberately *not*
/// ``ElementFact/Geometry``'s viewport-relative box: a rect an agent will
/// paste back into a region flag has to survive a scroll, and a
/// viewport-relative one does not.
public struct DocumentRect: Friendly {
    /// Left edge, from the document's left edge.
    public var x: Double

    /// Top edge, from the document's top edge.
    public var y: Double

    /// Border-box width.
    public var width: Double

    /// Border-box height.
    public var height: Double

    /// Creates a rect.
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
