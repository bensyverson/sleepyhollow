import Foundation

/// What a hit test at a point actually found: the element a real click would
/// have landed on, named well enough to recognise.
///
/// A coordinate click is the one act primitive whose target the caller did
/// not name, so the outcome has to. The identity is deliberately the cheap,
/// stable part — tag, `id`, classes — plus the fact that decides whether a
/// selector could ever have reached it: how many open shadow boundaries the
/// hit test crossed.
public struct HitElement: Friendly {
    /// The lowercased tag name of the element under the point.
    public var tagName: String

    /// The element's `id`, when it has one. Scoped to its shadow root when
    /// ``shadowDepth`` is above zero, so it is not necessarily unique in the
    /// document — and not necessarily addressable from outside at all.
    public var id: String?

    /// The element's classes, in attribute order.
    public var classes: [String]

    /// How many open shadow roots the hit test descended through: `0` for an
    /// element in the light DOM, `1` for one rendered by a component, more
    /// for nested components.
    public var shadowDepth: Int

    /// The document-space point the hit test was run at.
    public var point: DocumentPoint

    /// Whether the element lives inside a shadow root — which is to say,
    /// whether `--selector` could have reached it at all.
    public var insideShadowRoot: Bool {
        shadowDepth > 0
    }

    /// Creates a hit-test result.
    public init(tagName: String, id: String? = nil, classes: [String] = [], shadowDepth: Int, point: DocumentPoint) {
        self.tagName = tagName
        self.id = id
        self.classes = classes
        self.shadowDepth = shadowDepth
        self.point = point
    }
}
