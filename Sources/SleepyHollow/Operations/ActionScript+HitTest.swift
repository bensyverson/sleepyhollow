import Foundation

/// The coordinate click: a real hit test at a point, descending through open
/// shadow roots, then the same synthesized event sequence a selector click
/// dispatches.
///
/// **`--at` is document CSS px**, origin at the unscrolled page's top-left —
/// the space ``ShotRegion/rect(_:)`` crops in, so a number read off one
/// command pastes straight into the next. The point is scrolled into view
/// first and the hit test then runs at the viewport-relative position, which
/// is the only position `elementFromPoint` understands; a point past the end
/// of the document is a clean negative rather than a click on whatever
/// happened to be at the clamped scroll offset.
///
/// **The descent is what reaches a component.** `document.elementFromPoint`
/// stops at the shadow *host*, because that is the outermost node in the
/// document's own tree at that point; `shadowRoot.elementFromPoint` at the
/// same coordinates continues into the root the host renders. Repeating that
/// while the found element has an open `shadowRoot` lands on the deepest
/// element actually under the pointer — the button a `--selector` click on
/// the host cannot reach, since a click dispatched at the host travels up to
/// the document and never down into what it renders.
///
/// A closed shadow root exposes no `shadowRoot` to anyone, this tool
/// included, so the descent stops at its host. That is the truth, not a
/// limitation to paper over.
extension ActionScript {
    /// The most shadow boundaries the descent will cross. A component tree
    /// this deep is pathological; the cap only guarantees termination if a
    /// page hands back a cyclic answer.
    private static let shadowDescentLimit: Int = 32

    /// A coordinate click: scroll the document point into view, hit-test it
    /// through open shadow roots, then click what was found at exactly that
    /// point rather than at the element's centre.
    static let pointClickBody: String = hitTestHelpers + "\n" + """
    const placed = sleepyViewportPoint(point);
    if (placed.error) return placed;
    const found = sleepyHitTest(placed.x, placed.y);
    if (!found) return { error: 'no-hit' };
    const element = found.element;
    if (sleepyDisabled(element)) return { error: 'disabled', tagName: sleepyTag(element) };
    if (typeof element.focus === 'function') element.focus();
    const navigating = sleepyDispatchClick(element, placed.x, placed.y);
    return {
      tagName: sleepyTag(element),
      navigating,
      hit: {
        tagName: sleepyTag(element),
        id: element.id ? element.id : null,
        classes: element.classList ? Array.from(element.classList) : [],
        shadowDepth: found.depth,
        point: { x: point.x, y: point.y },
      },
    };
    """

    /// Page-side helpers the coordinate click adds to ``helpers``: the
    /// document-to-viewport move, and the shadow-piercing hit test.
    static let hitTestHelpers: String = """
    function sleepyViewportPoint(wanted) {
      const width = window.innerWidth;
      const height = window.innerHeight;
      const inside = (x, y) => x >= 0 && y >= 0 && x < width && y < height;
      if (!inside(wanted.x - window.scrollX, wanted.y - window.scrollY)) {
        window.scrollTo(Math.max(0, wanted.x - width / 2), Math.max(0, wanted.y - height / 2));
      }
      const x = wanted.x - window.scrollX;
      const y = wanted.y - window.scrollY;
      if (!inside(x, y)) return { error: 'off-page' };
      return { x, y };
    }

    function sleepyHitTest(x, y) {
      let element = document.elementFromPoint(x, y);
      if (!element) return null;
      let depth = 0;
      while (depth < \(shadowDescentLimit) && element.shadowRoot
        && typeof element.shadowRoot.elementFromPoint === 'function') {
        const inner = element.shadowRoot.elementFromPoint(x, y);
        if (!inner || inner === element) break;
        element = inner;
        depth += 1;
      }
      const tag = sleepyTag(element);
      if (depth === 0 && (tag === 'html' || tag === 'body')) return null;
      return { element, depth };
    }
    """
}
