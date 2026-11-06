import Foundation

/// An element a shot's area contains whose flattened render differs from
/// its true CSS 3D render.
///
/// `shot` rasterizes through `WKWebView.takeSnapshot`, which repaints the
/// page in software with every layer's 4×4 transform reduced to a 2D affine
/// one: perspective foreshortening, `preserve-3d` depth sorting and
/// `backface-visibility: hidden` are lost, and the pixels stop agreeing with
/// `getBoundingClientRect()` (`project/2026-11-06-true-3d-shots.md`). A
/// shot that draws one of these elements is a plausible wrong answer, so it
/// says so: ``ShotOperation/Output/flattened3D`` and
/// ``ShotCapture/flattened3D`` list them, and the CLI prints a caveat.
///
/// Only what flattening actually changes is listed. A 2D transform, or a
/// bare 3D rotation with no perspective above it and no `preserve-3d`, is
/// an orthographic projection — exactly what the flat paint draws — so it is
/// never here.
///
/// Elements are pruned to the outermost flagged one: a `preserve-3d` card
/// is named once, not once per face. The page-side detector is
/// `window.sleepy.flattened3D` in ``SleepyHelpers``.
public struct FlattenedElement: Friendly {
    /// Why flattening changes how the element renders.
    public enum Reason: String, Friendly, CaseIterable {
        /// The element's own transform projects — it has perspective terms
        /// of its own (a `perspective()` function that reaches its plane),
        /// so its edges should converge and do not.
        case perspectiveFunction
        /// The element's transform leaves its plane, under a parent whose
        /// `perspective` is not `none` (reached directly or through
        /// `preserve-3d` ancestors), so it should be foreshortened.
        case perspectiveAncestor
        /// The element keeps a 3D rendering context (`transform-style:
        /// preserve-3d`, not forced flat by `overflow`, `opacity`, `filter`
        /// and the like) around a child whose transform leaves the plane, so
        /// depth should decide what paints in front, and DOM order does.
        case preserve3D
        /// The element has `backface-visibility: hidden` and is turned away
        /// from the viewer, so it should not paint at all, and does,
        /// mirrored.
        case hiddenBackface
    }

    /// A selector-ish path to the element, e.g. `div#card` or
    /// `main > div.scene > div.cube` — the same shape `overflow` reports.
    public let path: String

    /// Every reason this element is listed, in ``Reason`` declaration order.
    public let reasons: [Reason]

    /// The element's border box as `getBoundingClientRect()` reports it, in
    /// document coordinates. That is the *true* 3D box; the flat pixels may
    /// sit elsewhere.
    public let rect: DocumentRect

    /// Creates a finding.
    public init(path: String, reasons: [Reason], rect: DocumentRect) {
        self.path = path
        self.reasons = reasons
        self.rect = rect
    }
}
