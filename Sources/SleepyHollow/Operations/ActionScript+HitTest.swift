import Foundation

/// The coordinate click's page-side half: a hit test at a point, descending
/// through open shadow roots, that names what a real click there will reach
/// — the click itself comes from the host's window (``TrustedInput``), and
/// WebKit hit-tests it again, the way it does a user's.
///
/// **`--at` is document CSS px**, origin at the unscrolled page's top-left —
/// the space ``ShotRegion/rect(_:)`` crops in, so a number read off one
/// command pastes straight into the next. The point is scrolled into view
/// first and the hit test then runs at the viewport-relative position, which
/// is the only position `elementFromPoint` understands; a point past the end
/// of the document is a clean negative rather than a click on whatever
/// happened to be at the clamped scroll offset.
///
/// **The descent is what names a component.** `document.elementFromPoint`
/// stops at the shadow *host*, because that is the outermost node in the
/// document's own tree at that point; `shadowRoot.elementFromPoint` at the
/// same coordinates continues into the root the host renders. Repeating that
/// while the found element has an open `shadowRoot` lands on the deepest
/// element actually under the pointer — the one the click reaches, and the
/// one ``HitElement`` reports, rather than the host a selector stops at.
///
/// **Fractions reach the hit test, not every event.** The point goes to
/// `elementFromPoint` and to the window's mouse events unrounded, and the
/// pointer events carry it unrounded, but WebKit gives a `MouseEvent` —
/// `mousedown`, `mouseup`, `click` — whole-pixel `clientX`/`clientY`, the
/// integer part. Measured the same for the synthesized click this replaced
/// and for the real one (2026-11-06); `ClickFractionalPointTests` pins both
/// halves.
///
/// A closed shadow root exposes no `shadowRoot` to anyone, this tool
/// included, so the descent stops at its host. That is the truth, not a
/// limitation to paper over.
extension ActionScript {
    /// The most shadow boundaries the descent will cross. A component tree
    /// this deep is pathological; the cap only guarantees termination if a
    /// page hands back a cyclic answer.
    private static let shadowDescentLimit: Int = 32

    /// A coordinate click's first half: scroll the document point into view,
    /// hit-test it through open shadow roots, and answer the viewport point
    /// and what is there — refusing the page background and a disabled
    /// control, which a click there cannot act on.
    static let pointClickBody: String = hitTestHelpers + "\n" + """
    const placed = sleepyViewportPoint(point);
    if (placed.error) return placed;
    const found = sleepyHitTest(placed.x, placed.y);
    if (!found) return { error: 'no-hit' };
    const element = found.element;
    if (sleepyDisabled(element)) return { error: 'disabled', tagName: sleepyTag(element) };
    return {
      tagName: sleepyTag(element),
      x: placed.x,
      y: placed.y,
      hit: {
        tagName: sleepyTag(element),
        id: element.id ? element.id : null,
        classes: element.classList ? Array.from(element.classList) : [],
        shadowDepth: found.depth,
        point: { x: point.x, y: point.y },
      },
    };
    """

    /// Page-side helpers the coordinate click, the selector click and the
    /// hover add to ``helpers``: the document-to-viewport move, the
    /// shadow-piercing hit test, and the check that an element is what a
    /// pointer at its center would reach.
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

    function sleepyComposedContains(outer, inner) {
      let node = inner;
      while (node) {
        if (node === outer) return true;
        node = node.parentNode || (node instanceof ShadowRoot ? node.host : null);
      }
      return false;
    }

    function sleepyPointerTarget(element, block) {
      const tag = sleepyTag(element);
      if (typeof element.scrollIntoView === 'function') {
        element.scrollIntoView({ block, inline: block });
      }
      const rect = element.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) return { error: 'not-visible', tagName: tag };
      const x = rect.left + rect.width / 2;
      const y = rect.top + rect.height / 2;
      const hit = sleepyHitTest(x, y);
      const top = hit ? hit.element : document.elementFromPoint(x, y);
      if (!top || !sleepyComposedContains(element, top)) {
        return { error: 'covered', tagName: tag, detail: top ? sleepyTag(top) : null };
      }
      return { tagName: tag, x, y };
    }
    """

    /// A selector click's first half: the element's center, scrolled into
    /// view, refusing a disabled control, one with no box, and one another
    /// element covers there — a real click would land on that instead.
    static let clickLocateBody: String = hitTestHelpers + "\n" + """
    const found = sleepyLocate(selector);
    if (found.error) return found;
    const element = found.element;
    if (sleepyDisabled(element)) return { error: 'disabled', tagName: sleepyTag(element) };
    return sleepyPointerTarget(element, 'center');
    """
}
