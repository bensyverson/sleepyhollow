extension AXScript {
    /// Shared helpers: safe DOM access, visibility pruning, whitespace
    /// normalization, and generated (`::before`/`::after`) content.
    ///
    /// Visibility is decided per element and *not* re-derived for descendants:
    /// `getComputedStyle` inside a `display: none` subtree still reports each
    /// element's own `display`, so only the walk's refusal to descend makes
    /// hiding inherit. Everything here is defensive — a page can make any DOM
    /// accessor throw, and a read verb that throws is a read verb that lies.
    static let support: String = #"""
    const AX_TEXT_NODE = 3;
    const AX_ELEMENT_NODE = 1;

    /// Elements the platform renders itself, whose computed style is not a
    /// trustworthy visibility signal.
    const AX_STYLE_EXEMPT = new Set(['option', 'optgroup']);

    function axView(node) {
      const document = node.ownerDocument || node;
      return document ? document.defaultView : null;
    }

    function axStyle(element, pseudo) {
      const view = axView(element);
      if (!view) { return null; }
      try {
        return view.getComputedStyle(element, pseudo || null);
      } catch (error) {
        return null;
      }
    }

    function axMatches(element, selector) {
      try {
        return element.matches(selector);
      } catch (error) {
        return false;
      }
    }

    function axAttribute(element, name) {
      try {
        const value = element.getAttribute(name);
        return value === null ? null : value;
      } catch (error) {
        return null;
      }
    }

    /// AccName and the tree both exclude hidden nodes; `aria-hidden` and the
    /// two CSS mechanisms are the whole of it. `hidden` and `display: none`
    /// coincide, but the attribute is checked first because it is cheaper.
    function axIsHidden(element) {
      if (axAttribute(element, 'aria-hidden') === 'true') { return true; }
      if (element.hasAttribute && element.hasAttribute('hidden')) { return true; }
      if (AX_STYLE_EXEMPT.has(element.localName)) { return false; }
      const style = axStyle(element);
      if (!style) { return false; }
      if (style.display === 'none') { return true; }
      if (style.visibility === 'hidden' || style.visibility === 'collapse') { return true; }
      return false;
    }

    /// True when the element's box does not sit in the text flow, so the name
    /// it contributes needs a space around it.
    function axIsBlockish(element) {
      const style = axStyle(element);
      if (!style) { return false; }
      const display = style.display;
      return display !== 'inline' && display !== 'contents' && display !== 'inline-block';
    }

    function axCollapse(text) {
      return String(text === null || text === undefined ? '' : text).replace(/\s+/g, ' ').trim();
    }

    /// The literal part of generated content. `attr()`, counters, images and
    /// the like are not text an assistive technology would announce, and this
    /// deliberately contributes nothing for them.
    function axPseudoText(element, pseudo) {
      const style = axStyle(element, pseudo);
      if (!style) { return ''; }
      const content = style.content;
      if (!content || content === 'none' || content === 'normal') { return ''; }
      const match = /^"([\s\S]*)"$/.exec(content.trim());
      return match ? match[1] : '';
    }

    function axElementById(element, id) {
      const document = element.ownerDocument;
      if (!document) { return null; }
      try {
        return document.getElementById(id);
      } catch (error) {
        return null;
      }
    }

    /// Elements whose text belongs to *another* element's accessible name —
    /// `label`, `legend`, `figcaption`, `caption`. Marked in one pass before
    /// the walk, because a `label[for]` is reached before the control it
    /// names and the walk cannot look ahead.
    const AX_CONSUMED = new Set();

    function axMarkConsumedLabels(root) {
      let controls = [];
      try {
        controls = Array.from(root.querySelectorAll('input, select, textarea, button, meter, progress'));
      } catch (error) {
        controls = [];
      }
      for (const control of controls) {
        const labels = control.labels ? Array.from(control.labels) : [];
        for (const label of labels) { AX_CONSUMED.add(label); }
      }
      let captioned = [];
      try {
        captioned = Array.from(root.querySelectorAll('fieldset, figure, table'));
      } catch (error) {
        captioned = [];
      }
      for (const element of captioned) {
        // An author name wins over the caption, so the caption's text is then
        // still the page's own text and stays in the tree.
        if (element.hasAttribute('aria-label') || element.hasAttribute('aria-labelledby')) { continue; }
        const caption = element.querySelector(':scope > legend, :scope > figcaption, :scope > caption');
        if (caption) { AX_CONSUMED.add(caption); }
      }
    }

    function axIsConsumedText(node) {
      let element = node.parentElement;
      while (element) {
        if (AX_CONSUMED.has(element)) { return true; }
        element = element.parentElement;
      }
      return false;
    }
    """#
}
