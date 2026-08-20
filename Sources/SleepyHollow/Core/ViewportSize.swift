/// A fixed viewport size in points.
///
/// Fixed window size is part of determinism-by-construction: the same
/// invocation renders the same page.
public struct ViewportSize: Friendly {
    /// The deterministic default: 1280×800.
    public static let `default` = ViewportSize(width: 1280, height: 800)

    /// Width in points.
    public var width: Int

    /// Height in points.
    public var height: Int

    /// Creates a size.
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }
}
