import Foundation

/// The render axes one `shot` invocation sweeps: viewport sizes, densities
/// and themes, crossed.
///
/// "How does this look at 480 and at 1280, in light and in dark?" is one
/// question, and answering it with four invocations means four `--out` paths
/// an agent has to invent and then remember. Repeating `--size`, `--scale` and
/// `--theme` makes it one invocation: the cross product renders in a fixed
/// order, each file is named for **only the axes that actually vary**, and
/// ``ShotVariantIndex`` prints the mapping so nothing has to parse a name.
///
/// Size and theme shape a *load* — they are ``LoadOptions`` facts, so each
/// distinct pair is its own page host — while ``ShotScale`` is raster-only and
/// re-renders from the same loaded page. ``loads`` groups the variants that
/// way, so a 2-size × 2-scale sweep pays for two loads, not four.
public struct ShotPlan: Friendly {
    /// One render in the sweep.
    public struct Variant: Friendly {
        /// The viewport this render lays out at.
        public let size: ViewportSize
        /// Device pixels per CSS px in its raster.
        public let scale: ShotScale
        /// The appearance it renders under.
        public let theme: ColorTheme
        /// What this render adds to the base file name — empty when nothing
        /// varies, and otherwise the varying axes in the order size, scale,
        /// theme (`-480@2x-dark`).
        public let suffix: String
        /// The varying axes in human form, for a contact sheet's gutter.
        /// A lone variant labels itself with its size, so a one-cell sheet
        /// still says what it shows.
        public let label: String

        /// Creates a variant.
        public init(size: ViewportSize, scale: ShotScale, theme: ColorTheme, suffix: String, label: String) {
            self.size = size
            self.scale = scale
            self.theme = theme
            self.suffix = suffix
            self.label = label
        }

        /// This render's file, from the `--out` path the caller gave.
        ///
        /// The suffix lands on the stem, so `header.png` becomes
        /// `header-480@2x-dark.png` and an extensionless path keeps none.
        public func file(base: String) -> String {
            ShotPlan.suffixed(base, with: suffix)
        }

        /// Whether this variant shares a page load with `other`: same
        /// viewport, same theme, differing only in raster density.
        public func sharesLoad(with other: Variant) -> Bool {
            size == other.size && theme == other.theme
        }
    }

    /// The viewports to render at; empty means the single default.
    public let sizes: [ViewportSize]
    /// The densities to render at; empty means ``ShotScale/one``.
    public let scales: [ShotScale]
    /// The appearances to render under; empty means ``ColorTheme/light``.
    public let themes: [ColorTheme]

    /// Creates a plan from the axes a caller repeated. An empty axis is the
    /// deterministic default for that axis, so a plain `shot` is a plan of
    /// exactly one variant.
    public init(sizes: [ViewportSize] = [], scales: [ShotScale] = [], themes: [ColorTheme] = []) {
        self.sizes = sizes.isEmpty ? [ViewportSize.default] : sizes
        self.scales = scales.isEmpty ? [ShotScale.one] : scales
        self.themes = themes.isEmpty ? [.light] : themes
    }

    /// Every render, size outermost, then theme, then scale.
    ///
    /// The *suffix* names the axes in the order size, scale, theme; the
    /// enumeration puts scale innermost instead, because scale is the one axis
    /// that does not need its own page load — so the variants that share a
    /// load are adjacent and ``loads`` can group them by a single pass.
    public var variants: [Variant] {
        let widthsCollide: Bool = Set(sizes.map(\.width)).count < sizes.count
        return sizes.flatMap { size in
            themes.flatMap { theme in
                scales.map { scale in
                    Variant(
                        size: size,
                        scale: scale,
                        theme: theme,
                        suffix: suffix(size: size, scale: scale, theme: theme, widthsCollide: widthsCollide),
                        label: label(size: size, scale: scale, theme: theme),
                    )
                }
            }
        }
    }

    /// The variants grouped into the page loads that produce them: one group
    /// per distinct viewport-and-theme pair, in sweep order.
    public var loads: [[Variant]] {
        variants.reduce(into: [[Variant]]()) { groups, variant in
            if let last = groups.last?.first, last.sharesLoad(with: variant) {
                groups[groups.count - 1].append(variant)
            } else {
                groups.append([variant])
            }
        }
    }

    /// Whether this plan renders more than one image — the point at which
    /// file names need suffixes and stdout needs an index.
    public var isSweep: Bool {
        sizes.count > 1 || scales.count > 1 || themes.count > 1
    }

    /// Puts `suffix` on the stem of `base`, keeping any extension — the one
    /// naming rule both a sweep's variant suffixes and `--tile`'s strip
    /// numbers go through.
    ///
    /// Deliberately string surgery rather than `URL(fileURLWithPath:)`: a
    /// `URL` resolves a relative path against the process's working directory,
    /// so `--out shot.png` would come back as an absolute path in the index
    /// and the caller would not recognise its own argument.
    public static func suffixed(_ base: String, with suffix: String) -> String {
        guard !suffix.isEmpty else { return base }
        let path = base as NSString
        let stem: String = path.deletingPathExtension + suffix
        return path.pathExtension.isEmpty ? stem : stem + "." + path.pathExtension
    }

    /// The file-name suffix for one variant: only the axes with more than one
    /// value, in the order size, scale, theme.
    ///
    /// - Parameter widthsCollide: whether two sizes share a width, in which
    ///   case the size part must carry the height too or two renders would
    ///   claim one file.
    private func suffix(size: ViewportSize, scale: ShotScale, theme: ColorTheme, widthsCollide: Bool) -> String {
        var parts = ""
        if sizes.count > 1 {
            parts += widthsCollide ? "-\(size.width)x\(size.height)" : "-\(size.width)"
        }
        if scales.count > 1 { parts += "@\(scale.factor)x" }
        if themes.count > 1 { parts += "-\(theme.rawValue)" }
        return parts
    }

    /// The human label for one variant: the varying axes, or the size alone
    /// when nothing varies.
    private func label(size: ViewportSize, scale: ShotScale, theme: ColorTheme) -> String {
        var parts: [String] = []
        if sizes.count > 1 || !isSweep { parts.append("\(size.width)×\(size.height)") }
        if scales.count > 1 { parts.append("\(scale.factor)×") }
        if themes.count > 1 { parts.append(theme.rawValue) }
        return parts.joined(separator: " ")
    }
}
