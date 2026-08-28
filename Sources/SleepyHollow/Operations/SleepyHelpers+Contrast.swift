extension SleepyHelpers {
    /// `sleepy.contrast(options)`: WCAG 2 ratios for every rendered text node.
    ///
    /// The walk is over *text nodes*, not elements, because the colour that
    /// matters is the one on the node's own parent — a `<p>` with a `<span>`
    /// in a different colour is two verdicts, not one. `display: none` and
    /// `opacity: 0` prune a whole subtree; `visibility` is decided per node,
    /// since a hidden ancestor can carry a visible descendant; and text with
    /// no rendered area is counted as skipped rather than measured against a
    /// box that isn't there.
    ///
    /// Large text is WCAG's rule in CSS pixels: ≥24px, or ≥18.66px bold
    /// (18pt, and 14pt bold). The ratio is rounded to two places *before*
    /// comparison, the way conformance tools quote it, so 3.00 meets a 3.0
    /// bar.
    ///
    /// `options`: `min` (normal-size ratio, default 4.5), `largeMin` (default
    /// 3), `minimum` (the name echoed into the report), `selector` (scope).
    static let contrast: String = #"""
    const SLEEPY_LARGE_PX = 24;
    const SLEEPY_LARGE_BOLD_PX = 18.66;
    const SLEEPY_BOLD_WEIGHT = 700;
    const SLEEPY_EXCERPT_LIMIT = 80;
    const SLEEPY_TEXTLESS = new Set([
      'script', 'style', 'noscript', 'template', 'title', 'head',
      'defs', 'clippath', 'mask', 'symbol', 'metadata', 'desc',
    ]);

    function sleepyContrast(options) {
      const settings = options || {};
      const normalMin = Number.isFinite(settings.min) ? settings.min : 4.5;
      const largeMin = Number.isFinite(settings.largeMin) ? settings.largeMin : 3;
      const roots = sleepyContrastRoots(settings.selector);
      const report = {
        minimum: typeof settings.minimum === 'string' ? settings.minimum : 'wcag-aa',
        checked: 0,
        skipped: 0,
        scopeMatches: roots.length,
        failures: [],
        unmeasured: [],
      };
      for (let i = 0; i < roots.length; i++) {
        sleepyVisitText(roots[i], report, normalMin, largeMin);
      }
      return report;
    }

    function sleepyContrastRoots(selector) {
      if (typeof selector !== 'string' || selector === '') {
        const root = document.body || document.documentElement;
        return root ? [root] : [];
      }
      try {
        return Array.prototype.slice.call(document.querySelectorAll(selector));
      } catch (error) {
        return [];
      }
    }

    function sleepyVisitText(root, report, normalMin, largeMin) {
      if (!root || root.nodeType !== SLEEPY_ELEMENT_NODE) { return; }
      if (SLEEPY_TEXTLESS.has(root.localName)) { return; }
      const style = sleepyStyle(root);
      const opacity = style ? parseFloat(style.opacity) : 1;
      if (style && (style.display === 'none' || (Number.isFinite(opacity) && opacity <= 0))) {
        report.skipped += sleepyCountText(root);
        return;
      }
      const hidden = !!style && (style.visibility === 'hidden' || style.visibility === 'collapse');
      const children = root.childNodes;
      for (let i = 0; i < children.length; i++) {
        const node = children[i];
        if (node.nodeType === SLEEPY_TEXT_NODE) {
          if (!sleepyHasInk(node)) { continue; }
          if (hidden || !style) { report.skipped += 1; continue; }
          sleepyMeasureText(node, root, style, report, normalMin, largeMin);
        } else if (node.nodeType === SLEEPY_ELEMENT_NODE) {
          sleepyVisitText(node, report, normalMin, largeMin);
        }
      }
    }

    function sleepyMeasureText(node, element, style, report, normalMin, largeMin) {
      const box = sleepyTextRect(node, element);
      if (!box) { report.skipped += 1; return; }
      const fontSize = parseFloat(style.fontSize);
      const large = sleepyIsLargeText(style, fontSize);
      const required = large ? largeMin : normalMin;
      const background = sleepyIsSvg(element)
        ? sleepySvgTextBackground(element)
        : sleepyEffectiveBackground(element);
      const finding = {
        path: sleepyPath(element),
        text: sleepyExcerpt(node.nodeValue),
        foreground: '',
        background: null,
        ratio: null,
        required: required,
        isLargeText: large,
        fontSize: Number.isFinite(fontSize) ? fontSize : 0,
        reason: null,
      };
      if (!background || background.kind !== 'color') {
        const bare = sleepyForeground(element, style, null);
        finding.foreground = bare ? sleepyHex(bare) : '';
        finding.reason = background && background.reason ? background.reason : 'unknown';
        report.unmeasured.push(finding);
        return;
      }
      const foreground = sleepyForeground(element, style, background.rgba);
      if (!foreground) { report.skipped += 1; return; }
      report.checked += 1;
      const ratio = sleepyRound(sleepyContrastRatio(foreground, background.rgba), 2);
      if (ratio >= required) { return; }
      finding.foreground = sleepyHex(foreground);
      finding.background = sleepyHex(background.rgba);
      finding.ratio = ratio;
      report.failures.push(finding);
    }

    /// The text colour as painted: SVG's `fill`, everything else's `color`,
    /// faded by opacity and composited over the background when translucent.
    function sleepyForeground(element, style, background) {
      const svg = sleepyIsSvg(element);
      let colour = sleepyParseColor(svg ? style.fill : style.color);
      if (!colour) { return null; }
      if (svg) { colour = sleepyFade(colour, parseFloat(style.fillOpacity)); }
      colour = sleepyFade(colour, parseFloat(style.opacity));
      if (colour[3] >= 1 || !background) { return colour; }
      return sleepyOver(colour, background);
    }

    function sleepyIsLargeText(style, fontSize) {
      if (!Number.isFinite(fontSize)) { return false; }
      if (fontSize >= SLEEPY_LARGE_PX) { return true; }
      return fontSize >= SLEEPY_LARGE_BOLD_PX && sleepyWeight(style.fontWeight) >= SLEEPY_BOLD_WEIGHT;
    }

    function sleepyWeight(value) {
      const numeric = parseFloat(value);
      if (Number.isFinite(numeric)) { return numeric; }
      return value === 'bold' || value === 'bolder' ? SLEEPY_BOLD_WEIGHT : 400;
    }

    /// The rendered box of one text node. A `Range` answers for HTML; SVG
    /// text falls back to its element, whose box is the glyph run.
    function sleepyTextRect(node, element) {
      try {
        const range = (node.ownerDocument || document).createRange();
        range.selectNodeContents(node);
        const box = range.getBoundingClientRect();
        if (box && box.width > 0 && box.height > 0) { return box; }
      } catch (error) {
        // fall through to the element's own box
      }
      try {
        const box = element.getBoundingClientRect();
        if (box && box.width > 0 && box.height > 0) { return box; }
      } catch (error) {
        return null;
      }
      return null;
    }

    function sleepyHasInk(node) {
      const value = node.nodeValue;
      return typeof value === 'string' && value.trim() !== '';
    }

    function sleepyCountText(root) {
      let count = 0;
      const children = root.childNodes;
      for (let i = 0; i < children.length; i++) {
        const node = children[i];
        if (node.nodeType === SLEEPY_TEXT_NODE) {
          if (sleepyHasInk(node)) { count += 1; }
        } else if (node.nodeType === SLEEPY_ELEMENT_NODE && !SLEEPY_TEXTLESS.has(node.localName)) {
          count += sleepyCountText(node);
        }
      }
      return count;
    }

    function sleepyExcerpt(text) {
      const collapsed = String(text === null || text === undefined ? '' : text)
        .replace(/\s+/g, ' ')
        .trim();
      if (collapsed.length <= SLEEPY_EXCERPT_LIMIT) { return collapsed; }
      return collapsed.slice(0, SLEEPY_EXCERPT_LIMIT - 1) + '…';
    }
    """#
}
