extension SleepyHelpers {
    /// `sleepy.flattened3D(options)`: the elements inside an area whose flat
    /// render differs from their true CSS 3D render — what ``ShotOperation``
    /// reports as ``FlattenedElement``s.
    ///
    /// `takeSnapshot` keeps each layer's transform as a 2D affine one, so the
    /// question per element is whether that loses anything visible. It does
    /// when (a reason each, spelled as ``FlattenedElement/Reason``):
    ///
    /// - **`perspectiveFunction`** — the element's own matrix projects its
    ///   plane: `m14`, `m24` nonzero or `m44 ≠ 1`, which is where a
    ///   `perspective()` function lands once anything turns or lifts the
    ///   plane. A bare `perspective(400px)` only sets `m34`, which touches no
    ///   point of a flat element, so it is not listed.
    /// - **`perspectiveAncestor`** — the matrix moves the plane in z (`m13`,
    ///   `m23` or `m43` nonzero, or it projects) and the parent's
    ///   `perspective` is not `none`, the walk continuing up through
    ///   `preserve-3d` parents only. Measured 2026-11-06: a parent that is
    ///   flat (even an unpositioned one) cuts a grandparent's perspective off
    ///   in WebKit's own geometry, so it is not followed further.
    /// - **`preserve3D`** — a used `preserve-3d` with a child whose transform
    ///   leaves the plane. "Used": WebKit's computed value stays
    ///   `preserve-3d` under `overflow`, `opacity < 1`, `filter`, `isolation`
    ///   and `clip-path` but its geometry is flat (measured 2026-11-06);
    ///   `mix-blend-mode` and masks flatten per the spec.
    /// - **`hiddenBackface`** — `backface-visibility: hidden` on an element
    ///   with a 3D matrix that, composed with its `preserve-3d` ancestors,
    ///   faces away (the inverse's `m33 < 0`). A hidden back face that faces
    ///   the viewer paints either way, so it is not listed.
    ///
    /// A bare 3D rotation with no perspective above it and no `preserve-3d`
    /// is never listed: its orthographic projection is what the flat paint
    /// draws (measured 2026-11-06: `rotateY(60deg)` painted at exactly its
    /// `getBoundingClientRect()` box).
    ///
    /// One pass over the document: computed `transform` and
    /// `transform-style` decide whether an element is a candidate at all, and
    /// only candidates pay for a rect, an ancestor walk or a matrix. Only
    /// elements whose box meets `options.area` (viewport coordinates, the
    /// space the snapshot crops in) count, and the answer is pruned to the
    /// outermost flagged element so a card is named once, not per face.
    /// Shadow roots and frames are not walked.
    static let transforms: String = #"""
    const SLEEPY_MATRIX_EPSILON = 1e-6;

    function sleepyFlattened3D(options) {
      const area = options && options.area ? options.area : null;
      let elements = [];
      try {
        elements = document.querySelectorAll('*');
      } catch (error) {
        return [];
      }
      const found = [];
      for (let i = 0; i < elements.length; i++) {
        const element = elements[i];
        const style = sleepyStyle(element);
        if (!style) { continue; }
        const matrix = sleepyMatrix3D(style.transform);
        const preserves = sleepyPreserves3D(style);
        if (!matrix && !preserves) { continue; }
        const reasons = sleepyFlatteningReasons(element, style, matrix, preserves);
        if (!reasons.length) { continue; }
        if (!sleepyMeetsArea(element, area)) { continue; }
        found.push({ element: element, reasons: reasons });
      }
      const flagged = new Set(found.map(function (entry) { return entry.element; }));
      const report = [];
      for (let i = 0; i < found.length; i++) {
        const entry = found[i];
        if (sleepyHasFlaggedAncestor(entry.element, flagged)) { continue; }
        report.push({ path: sleepyPath(entry.element), reasons: entry.reasons, rect: sleepyRectOf(entry.element) });
      }
      return report;
    }

    function sleepyFlatteningReasons(element, style, matrix, preserves) {
      const reasons = [];
      const paints = style.visibility === 'visible';
      if (matrix && paints && sleepyProjects(matrix)) {
        reasons.push('perspectiveFunction');
      }
      if (matrix && paints && sleepyLeavesPlane(matrix) && sleepyPerspectiveAbove(element)) {
        reasons.push('perspectiveAncestor');
      }
      if (preserves && sleepyHasChildLeavingPlane(element)) {
        reasons.push('preserve3D');
      }
      if (matrix && paints && style.backfaceVisibility === 'hidden' && sleepyFacesAway(element, style)) {
        reasons.push('hiddenBackface');
      }
      return reasons;
    }

    /// The sixteen numbers of a computed `matrix3d(…)`, column-major, or null
    /// for `none` and for a 2D `matrix(…)` — which flattening cannot change.
    function sleepyMatrix3D(transform) {
      if (typeof transform !== 'string' || transform.indexOf('matrix3d(') !== 0) { return null; }
      const values = transform.slice(9, -1).split(',').map(Number);
      return values.length === 16 && values.every(isFinite) ? values : null;
    }

    function sleepyNonzero(value) {
      return Math.abs(value) > SLEEPY_MATRIX_EPSILON;
    }

    /// Whether a z = 0 point's w depends on where it is: m14, m24, m44.
    function sleepyProjects(m) {
      return sleepyNonzero(m[3]) || sleepyNonzero(m[7]) || sleepyNonzero(m[15] - 1);
    }

    /// Whether a z = 0 point leaves the plane: m13, m23, m43 — or projects.
    function sleepyLeavesPlane(m) {
      return sleepyNonzero(m[2]) || sleepyNonzero(m[6]) || sleepyNonzero(m[14]) || sleepyProjects(m);
    }

    /// `preserve-3d` as WebKit uses it, not as it computes it.
    function sleepyPreserves3D(style) {
      if (style.transformStyle !== 'preserve-3d') { return false; }
      if (style.overflowX !== 'visible' || style.overflowY !== 'visible') { return false; }
      if (parseFloat(style.opacity) < 1) { return false; }
      if (style.filter && style.filter !== 'none') { return false; }
      if (style.isolation === 'isolate') { return false; }
      if (style.clipPath && style.clipPath !== 'none') { return false; }
      if (style.mixBlendMode && style.mixBlendMode !== 'normal') { return false; }
      const mask = style.maskImage || style.webkitMaskImage;
      if (mask && mask !== 'none') { return false; }
      return true;
    }

    function sleepyPerspectiveAbove(element) {
      let parent = element.parentElement;
      while (parent) {
        const style = sleepyStyle(parent);
        if (!style) { return false; }
        if (style.perspective && style.perspective !== 'none') { return true; }
        if (!sleepyPreserves3D(style)) { return false; }
        parent = parent.parentElement;
      }
      return false;
    }

    function sleepyHasChildLeavingPlane(element) {
      const children = element.children;
      for (let i = 0; i < children.length; i++) {
        const style = sleepyStyle(children[i]);
        const matrix = style ? sleepyMatrix3D(style.transform) : null;
        if (matrix && sleepyLeavesPlane(matrix)) { return true; }
      }
      return false;
    }

    /// The element's matrix composed with its `preserve-3d` ancestors',
    /// checked the way WebKit decides a back face is showing.
    function sleepyFacesAway(element, style) {
      try {
        let composed = new DOMMatrix(style.transform);
        let parent = element.parentElement;
        while (parent) {
          const parentStyle = sleepyStyle(parent);
          if (!parentStyle || !sleepyPreserves3D(parentStyle)) { break; }
          if (parentStyle.transform && parentStyle.transform !== 'none') {
            composed = new DOMMatrix(parentStyle.transform).multiply(composed);
          }
          parent = parent.parentElement;
        }
        const m33 = composed.inverse().m33;
        return isFinite(m33) && m33 < 0;
      } catch (error) {
        return false;
      }
    }

    /// Whether the element's box, in viewport coordinates, overlaps `area`.
    function sleepyMeetsArea(element, area) {
      let box = null;
      try {
        box = element.getBoundingClientRect();
      } catch (error) {
        return false;
      }
      if (!box || box.width <= 0 || box.height <= 0) { return false; }
      if (!area) { return true; }
      return box.left < area.x + area.width && box.right > area.x
        && box.top < area.y + area.height && box.bottom > area.y;
    }

    function sleepyHasFlaggedAncestor(element, flagged) {
      let node = element.parentElement;
      while (node) {
        if (flagged.has(node)) { return true; }
        node = node.parentElement;
      }
      return false;
    }
    """#
}
