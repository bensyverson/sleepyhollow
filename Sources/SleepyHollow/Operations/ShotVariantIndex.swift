import Foundation

/// What a `shot` sweep prints on stdout: which file holds which render.
///
/// A set of files named `header-480@2x-dark.png` is only self-describing if
/// you already know the naming rule — and the rule deliberately omits the
/// axes that did not vary, so the name alone can never say what the other
/// axes were. This index says it outright, so an agent picks the render it
/// wants by its parameters and never parses a file name.
///
/// The sibling of ``ShotIndex``, which does the same job for `--tile`: one
/// says *which rows*, this one says *which render*.
public struct ShotVariantIndex: Friendly {
    /// One render: the file it was written to, and the axes that produced it.
    public struct Entry: Friendly {
        /// The path the render was written to.
        public let file: String
        /// Viewport width in CSS px.
        public let width: Int
        /// Viewport height in CSS px.
        public let height: Int
        /// Device pixels per CSS px in the file.
        public let scale: Int
        /// The appearance it rendered under.
        public let theme: ColorTheme

        /// Which renderer drew it (``ShotRenderer``): each combination is
        /// its own render, so one can fall back while another does not.
        public let renderer: ShotRenderer

        /// Creates an entry.
        public init(file: String, width: Int, height: Int, scale: Int, theme: ColorTheme, renderer: ShotRenderer) {
            self.file = file
            self.width = width
            self.height = height
            self.scale = scale
            self.theme = theme
            self.renderer = renderer
        }

        /// Describes `variant`, drawn by `renderer`, as the file `base`
        /// names it.
        public init(variant: ShotPlan.Variant, base: String, renderer: ShotRenderer) {
            self.init(
                file: variant.file(base: base),
                width: variant.size.width,
                height: variant.size.height,
                scale: variant.scale.factor,
                theme: variant.theme,
                renderer: renderer,
            )
        }
    }

    /// The renders, in sweep order.
    public let variants: [Entry]

    /// Creates an index.
    public init(variants: [Entry]) {
        self.variants = variants
    }

    /// Describes every render of a sweep, in order, written off `base`.
    ///
    /// Built after rendering rather than from the plan alone, because which
    /// renderer drew a combination is only known once it has been drawn.
    public init(base: String, renders: [(variant: ShotPlan.Variant, renderer: ShotRenderer)]) {
        self.init(variants: renders.map { Entry(variant: $0.variant, base: base, renderer: $0.renderer) })
    }
}
