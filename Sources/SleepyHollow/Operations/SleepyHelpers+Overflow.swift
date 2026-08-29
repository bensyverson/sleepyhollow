extension SleepyHelpers {
    /// `sleepy.overflow(options)`: what reaches past the viewport's right
    /// edge, and what scrolls on purpose instead.
    ///
    /// Two signals, because a spill shows up two ways. A **box** spill is an
    /// element whose own border box ends past the viewport — a fixed-width
    /// block, an oversized image. A **content** spill is an element whose box
    /// fits but whose `scrollWidth` does not — the unbreakable string in a
    /// paragraph, which never widens the paragraph at all and so is invisible
    /// to a rect-only check.
    ///
    /// Both are then pruned so the report names a cause rather than a chain:
    /// a box spill inside another box spill is the outer one's doing, and a
    /// content spill wrapping a smaller offender is `body` reporting its
    /// child. An `overflow-x: auto | scroll` ancestor ends the walk — its
    /// descendants are wide by design — and is listed under
    /// `scrollContainers` with how far it scrolls.
    ///
    /// The comparison is scroll-independent by construction, not by
    /// correction: `sleepyRectOf` already folds `window.scrollX` into every
    /// rect, so an element's document-space right edge (`rect.x + width`, or
    /// `rect.x + scrollWidth` for a content spill) does not move as the page
    /// scrolls — `box.left` shrinks by exactly what `scrollX` grows.
    /// `viewportWidth` (`root.clientWidth`) is the viewport's own size, never
    /// its scroll offset. Comparing the two is therefore always the question
    /// "does this exceed one viewport width from the document's origin?",
    /// regardless of where the page happens to be scrolled when the check
    /// runs — verified 2026-08-28 by scrolling `capture-wide.html` to an
    /// arbitrary offset and to its own maximum scroll (exactly its spill
    /// amount) and finding the report byte-identical each time. Do not
    /// "fix" this by adding `scrollX` to `viewportWidth`: at the page's own
    /// maximum scroll, `scrollX + viewportWidth` equals `documentWidth`
    /// exactly, which would cancel the very violation this check exists to
    /// find.
    static let overflow: String = #"""
    const SLEEPY_OVERFLOW_TOLERANCE = 1;

    function sleepyOverflow(options) {
      const root = document.documentElement;
      const viewportWidth = root ? root.clientWidth : 0;
      const body = document.body;
      const report = {
        viewportWidth: viewportWidth,
        // The document scroller's own width: the number the naive
        // `scrollWidth > clientWidth` check reads, and the one that goes
        // quiet under `overflow-x: hidden`. Reported, never trusted.
        documentWidth: root ? root.scrollWidth : 0,
        violations: [],
        scrollContainers: [],
      };
      const candidates = [];
      const start = body || root;
      if (start) {
        sleepyVisitBoxes(start, viewportWidth, candidates, report.scrollContainers);
      }
      const kept = sleepyPruneCandidates(candidates);
      for (let i = 0; i < kept.length; i++) {
        const candidate = kept[i];
        report.violations.push({
          path: sleepyPath(candidate.element),
          cause: candidate.cause,
          right: sleepyRound(candidate.right, 2),
          overflowBy: sleepyRound(candidate.right - viewportWidth, 2),
          rect: candidate.rect,
        });
      }
      return report;
    }

    function sleepyVisitBoxes(element, viewportWidth, candidates, scrollers) {
      const style = sleepyStyle(element);
      if (style && style.display === 'none') { return; }
      const rect = sleepyRectOf(element);
      const boxRight = rect ? rect.x + rect.width : 0;
      const boxSpills = !!rect && boxRight > viewportWidth + SLEEPY_OVERFLOW_TOLERANCE;
      if (style && sleepyScrollsHorizontally(style)) {
        if (boxSpills) {
          candidates.push({ element: element, cause: 'box', right: boxRight, rect: rect });
        }
        const scrollWidth = element.scrollWidth;
        const clientWidth = element.clientWidth;
        if (scrollWidth > clientWidth + SLEEPY_OVERFLOW_TOLERANCE) {
          scrollers.push({
            path: sleepyPath(element),
            scrollWidth: scrollWidth,
            clientWidth: clientWidth,
            scrollBy: scrollWidth - clientWidth,
          });
        }
        return;
      }
      if (rect) {
        const contentRight = rect.x + Math.max(rect.width, element.scrollWidth);
        if (boxSpills) {
          candidates.push({ element: element, cause: 'box', right: boxRight, rect: rect });
        } else if (
          element.scrollWidth > element.clientWidth + SLEEPY_OVERFLOW_TOLERANCE
          && contentRight > viewportWidth + SLEEPY_OVERFLOW_TOLERANCE
        ) {
          candidates.push({ element: element, cause: 'content', right: contentRight, rect: rect });
        }
      }
      const children = element.children;
      for (let i = 0; i < children.length; i++) {
        sleepyVisitBoxes(children[i], viewportWidth, candidates, scrollers);
      }
    }

    function sleepyScrollsHorizontally(style) {
      return style.overflowX === 'auto' || style.overflowX === 'scroll';
    }

    /// Box spills report their outermost element; content spills report their
    /// innermost, since every ancestor inherits the same overrun.
    function sleepyPruneCandidates(candidates) {
      const boxes = candidates.filter(function (candidate) { return candidate.cause === 'box'; });
      return candidates.filter(function (candidate) {
        if (candidate.cause === 'box') {
          return !boxes.some(function (other) {
            return other !== candidate && other.element.contains(candidate.element);
          });
        }
        return !candidates.some(function (other) {
          return other !== candidate && candidate.element.contains(other.element);
        });
      });
    }
    """#
}
