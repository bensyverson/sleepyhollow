extension SleepyHelpers {
    /// Element-level helpers: computed style, the document-coordinate rect,
    /// a selector-ish path an agent can paste back, and the effective
    /// background walk.
    ///
    /// The background walk is the piece that earns the library. An element
    /// holding text almost never has a background of its own, so the answer
    /// lives up the ancestor chain, compositing each translucent layer over
    /// the next until one is opaque; the canvas beneath everything is white,
    /// which is what a `WKWebView` paints when nothing else does. At the first
    /// `background-image` — a gradient counts — the walk stops and says so,
    /// because a gradient has no single colour and a made-up one would be a
    /// contrast ratio that looks like an answer.
    ///
    /// SVG has no background at all: text sits on whatever shape is painted
    /// under it. `sleepySvgTextBackground` finds that shape by hit-testing the
    /// text's own corners and centre against every shape's fill geometry, from
    /// the top of the paint order down, then composites its fill over whatever
    /// the ordinary walk found beneath the `<svg>`.
    static let elements: String = #"""
    const SLEEPY_ELEMENT_NODE = 1;
    const SLEEPY_TEXT_NODE = 3;
    const SLEEPY_SVG_NAMESPACE = 'http://www.w3.org/2000/svg';
    const SLEEPY_SVG_SHAPES = 'path,rect,circle,ellipse,polygon,polyline';
    const SLEEPY_PATH_DEPTH = 6;

    function sleepyStyle(element) {
      try {
        const document = element.ownerDocument;
        const view = document ? document.defaultView : null;
        return view ? view.getComputedStyle(element) : null;
      } catch (error) {
        return null;
      }
    }

    function sleepyIsSvg(element) {
      return !!element && element.namespaceURI === SLEEPY_SVG_NAMESPACE;
    }

    /// An element's border box in document coordinates.
    function sleepyRectOf(element) {
      try {
        const box = element.getBoundingClientRect();
        return {
          x: box.left + window.scrollX,
          y: box.top + window.scrollY,
          width: box.width,
          height: box.height,
        };
      } catch (error) {
        return null;
      }
    }

    function sleepyRect(selector) {
      let element = null;
      try {
        element = document.querySelector(selector);
      } catch (error) {
        return null;
      }
      return element ? sleepyRectOf(element) : null;
    }

    /// A short, pasteable path: an id ends the walk, classes and
    /// `:nth-of-type` disambiguate the rest.
    function sleepyPath(element) {
      if (!element || element.nodeType !== SLEEPY_ELEMENT_NODE) { return ''; }
      const parts = [];
      let node = element;
      while (node && node.nodeType === SLEEPY_ELEMENT_NODE && parts.length < SLEEPY_PATH_DEPTH) {
        const name = node.localName;
        if (node.id) {
          parts.unshift(name + '#' + sleepyEscape(node.id));
          break;
        }
        parts.unshift(name + sleepyClassPart(node) + sleepyIndexPart(node));
        node = node.parentElement;
        if (node && node.localName === 'html') { break; }
      }
      return parts.join(' > ');
    }

    function sleepyEscape(text) {
      try {
        return window.CSS && window.CSS.escape ? window.CSS.escape(text) : text;
      } catch (error) {
        return text;
      }
    }

    function sleepyClassPart(element) {
      const attribute = element.getAttribute ? element.getAttribute('class') : null;
      if (typeof attribute !== 'string') { return ''; }
      const classes = attribute.trim().split(/\s+/).filter(Boolean).slice(0, 2);
      return classes.length ? '.' + classes.join('.') : '';
    }

    function sleepyIndexPart(element) {
      const parent = element.parentElement;
      if (!parent) { return ''; }
      const siblings = Array.prototype.filter.call(parent.children, function (child) {
        return child.localName === element.localName;
      });
      if (siblings.length < 2) { return ''; }
      return ':nth-of-type(' + (siblings.indexOf(element) + 1) + ')';
    }

    /// The composited colour behind `element`, or an honest gap.
    function sleepyEffectiveBackground(element) {
      const layers = [];
      let node = element;
      while (node && node.nodeType === SLEEPY_ELEMENT_NODE) {
        const style = sleepyStyle(node);
        if (style) {
          const image = style.backgroundImage;
          if (image && image !== 'none') { return { kind: 'unknown', reason: 'image' }; }
          const colour = sleepyParseColor(style.backgroundColor);
          if (colour && colour[3] > 0) {
            layers.push(colour);
            if (colour[3] >= 1) { break; }
          }
        }
        node = node.parentElement;
      }
      let result = SLEEPY_OPAQUE_WHITE;
      for (let i = layers.length - 1; i >= 0; i--) {
        result = sleepyOver(layers[i], result);
      }
      return { kind: 'color', rgba: result };
    }

    /// The background an SVG `<text>` sits on: the topmost shape whose fill
    /// covers it, over whatever the ordinary walk finds beneath the `<svg>`.
    function sleepySvgTextBackground(element) {
      const beneath = sleepyEffectiveBackground(element);
      const fill = sleepyShapeFillUnder(element);
      if (!fill) { return beneath; }
      if (beneath.kind !== 'color') {
        return fill[3] >= 1 ? { kind: 'color', rgba: fill } : beneath;
      }
      return { kind: 'color', rgba: sleepyOver(fill, beneath.rgba) };
    }

    function sleepyShapeFillUnder(element) {
      const root = element.ownerSVGElement;
      if (!root) { return null; }
      let box = null;
      try {
        box = element.getBoundingClientRect();
      } catch (error) {
        return null;
      }
      if (!box || (box.width <= 0 && box.height <= 0)) { return null; }
      const points = [
        [box.left + box.width / 2, box.top + box.height / 2],
        [box.left + 1, box.top + 1],
        [box.right - 1, box.top + 1],
        [box.left + 1, box.bottom - 1],
        [box.right - 1, box.bottom - 1],
      ];
      const shapes = Array.prototype.slice.call(root.querySelectorAll(SLEEPY_SVG_SHAPES));
      for (let i = shapes.length - 1; i >= 0; i--) {
        const shape = shapes[i];
        if (shape === element || shape.contains(element)) { continue; }
        if (typeof shape.isPointInFill !== 'function') { continue; }
        const style = sleepyStyle(shape);
        if (!style || style.display === 'none' || style.visibility === 'hidden') { continue; }
        const colour = sleepyParseColor(style.fill);
        if (!colour) { continue; }
        const paint = sleepyFade(sleepyFade(colour, parseFloat(style.fillOpacity)), parseFloat(style.opacity));
        if (paint[3] <= 0) { continue; }
        if (sleepyShapeCovers(shape, points)) { return paint; }
      }
      return null;
    }

    function sleepyShapeCovers(shape, points) {
      let inverse = null;
      try {
        const matrix = shape.getScreenCTM();
        if (!matrix) { return false; }
        inverse = matrix.inverse();
      } catch (error) {
        return false;
      }
      for (let i = 0; i < points.length; i++) {
        try {
          const local = new DOMPoint(points[i][0], points[i][1]).matrixTransform(inverse);
          if (!shape.isPointInFill(local)) { return false; }
        } catch (error) {
          return false;
        }
      }
      return true;
    }
    """#
}
