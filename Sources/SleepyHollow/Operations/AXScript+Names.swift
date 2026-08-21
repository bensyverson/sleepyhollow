extension AXScript {
    /// Accessible Name and Description Computation 1.2, §4.3.2, in the order
    /// the spec states it: `aria-labelledby`, then `aria-label`, then the host
    /// language's own label mechanisms, then — for the roles that allow it —
    /// the element's own content, then `title` and `placeholder`.
    ///
    /// Two flags carry the parts of the algorithm that depend on *how* a node
    /// was reached. `referenced` means the node is the target of an
    /// `aria-labelledby`, which lets a hidden node contribute and lets any
    /// role be named from content. `fromContent` means the node was reached
    /// while gathering someone else's name, which additionally enables step 2E
    /// (an embedded control contributes its value, not its name).
    static let names: String = #"""
    function axNameFlags(overrides) {
      return Object.assign(
        { referenced: false, fromContent: false, inLabelledBy: false, traversing: false },
        overrides || {},
      );
    }

    function axNameFor(element, flags, visited) {
      if (visited.has(element)) { return ''; }
      visited.add(element);

      // Step 1: a hidden node contributes nothing unless it was referenced by
      // name directly.
      if (!flags.referenced && axIsHidden(element)) { return ''; }

      const role = axRoleOf(element);
      // A role that prohibits naming still contributes its *content* when it
      // was reached as a label — the prohibition binds the author's
      // attributes on the node being named, not the text of the label.
      const authorNaming = !AX_NAME_PROHIBITED.has(role) || flags.referenced || flags.fromContent;

      // Step 2B: aria-labelledby, entered only once per computation.
      if (authorNaming && !flags.inLabelledBy) {
        const labelled = axLabelledByText(element, visited);
        if (labelled) { return labelled; }
      }

      // Step 2C: aria-label.
      if (authorNaming) {
        const label = axCollapse(axAttribute(element, 'aria-label'));
        if (label) { return label; }
      }

      // Step 2D: the host language's label mechanisms.
      if (role !== 'presentation') {
        const native = axNativeLabel(element, flags, visited);
        if (native) { return native; }
      }

      // Step 2E: an embedded control contributes its value while another
      // element is being named.
      if (flags.traversing) {
        const embedded = axEmbeddedControlText(element, role);
        if (embedded) { return embedded; }
      }

      // Step 2F: name from content, for the roles that allow it and for any
      // node reached as, or inside, a label.
      if (AX_NAME_FROM_CONTENT.has(role) || flags.referenced || flags.fromContent) {
        const content = axContentText(element, flags, visited);
        if (content) { return content; }
      }

      // Step 2I: the tooltip and placeholder fallbacks.
      const title = axCollapse(axAttribute(element, 'title'));
      if (title) { return title; }
      const placeholder = axCollapse(axAttribute(element, 'placeholder'));
      if (placeholder) { return placeholder; }
      return '';
    }

    function axLabelledByText(element, visited) {
      const ids = (axAttribute(element, 'aria-labelledby') || '').split(/\s+/).filter(Boolean);
      if (!ids.length) { return ''; }
      const parts = [];
      for (const id of ids) {
        const target = axElementById(element, id);
        if (!target) { continue; }
        // Each reference is its own traversal: the same element may be named
        // twice by two different references, and a self-reference resolves to
        // the element's own content rather than looping.
        const scoped = new Set(visited);
        scoped.delete(target);
        parts.push(axNameFor(
          target,
          axNameFlags({ referenced: true, inLabelledBy: true, traversing: true }),
          scoped,
        ));
      }
      return axCollapse(parts.join(' '));
    }

    function axNativeLabel(element, flags, visited) {
      const tag = element.localName;
      if (tag === 'input') {
        const type = (axAttribute(element, 'type') || 'text').toLowerCase();
        if (type === 'button' || type === 'submit' || type === 'reset') {
          const value = axCollapse(element.value);
          if (value) { return value; }
          if (type === 'submit') { return 'Submit'; }
          if (type === 'reset') { return 'Reset'; }
        }
        if (type === 'image') {
          const alt = axCollapse(axAttribute(element, 'alt'));
          if (alt) { return alt; }
          const title = axCollapse(axAttribute(element, 'title'));
          return title ? title : 'Submit Query';
        }
      }
      if (tag === 'input' || tag === 'select' || tag === 'textarea' || tag === 'button' ||
          tag === 'meter' || tag === 'progress') {
        return axLabelElementsText(element, visited);
      }
      if (tag === 'img' || tag === 'area') { return axCollapse(axAttribute(element, 'alt')); }
      if (tag === 'fieldset') { return axChildCaptionText(element, 'legend', visited); }
      if (tag === 'figure') { return axChildCaptionText(element, 'figcaption', visited); }
      if (tag === 'table') { return axChildCaptionText(element, 'caption', visited); }
      if (tag === 'svg') {
        const title = element.querySelector(':scope > title');
        return title ? axCollapse(title.textContent) : '';
      }
      return '';
    }

    /// `label[for]` and wrapping `<label>`, which `element.labels` gives us
    /// already resolved and in tree order.
    function axLabelElementsText(element, visited) {
      const labels = element.labels ? Array.from(element.labels) : [];
      if (!labels.length) { return ''; }
      const parts = [];
      for (const label of labels) {
        const scoped = new Set(visited);
        scoped.delete(label);
        parts.push(axContentText(label, axNameFlags({ fromContent: true, traversing: true }), scoped));
      }
      return axCollapse(parts.join(' '));
    }

    function axChildCaptionText(element, childTag, visited) {
      const caption = element.querySelector(':scope > ' + childTag);
      if (!caption) { return ''; }
      const scoped = new Set(visited);
      scoped.delete(caption);
      return axContentText(caption, axNameFlags({ fromContent: true, traversing: true }), scoped);
    }

    /// Step 2E: the *value* of a control embedded in a label, never its name.
    function axEmbeddedControlText(element, role) {
      if (role === 'textbox' || role === 'searchbox') { return axCollapse(element.value); }
      if (role === 'combobox' || role === 'listbox') { return axSelectedOptionText(element); }
      if (role === 'slider' || role === 'spinbutton' || role === 'progressbar' ||
          role === 'scrollbar' || role === 'meter') {
        return axRangeValueText(element);
      }
      return '';
    }

    /// The name from an element's own content, in document order, with
    /// generated content at either end and a space around anything that is
    /// not laid out inline.
    function axContentText(element, flags, visited) {
      let text = axPseudoText(element, '::before');
      let children = [];
      try {
        children = Array.from(element.childNodes);
      } catch (error) {
        children = [];
      }
      for (const child of children) {
        if (child.nodeType === AX_TEXT_NODE) {
          text += child.data;
          continue;
        }
        if (child.nodeType !== AX_ELEMENT_NODE) { continue; }
        if (axIsHidden(child)) { continue; }
        const part = axNameFor(
          child,
          axNameFlags({ fromContent: true, traversing: true, inLabelledBy: flags.inLabelledBy }),
          visited,
        );
        text += axIsBlockish(child) ? ' ' + part + ' ' : part;
      }
      text += axPseudoText(element, '::after');
      return axCollapse(text);
    }

    /// The accessible name of a node the walk is emitting: a fresh traversal,
    /// with no inherited flags.
    function axAccessibleName(element) {
      return axNameFor(element, axNameFlags({}), new Set());
    }

    /// True when the name the walk just computed came from the element's own
    /// content — the case where repeating that content as text nodes would
    /// only say the same thing twice.
    function axNamedFromContent(element, role, name) {
      if (!name) { return false; }
      if (!AX_NAME_FROM_CONTENT.has(role)) { return false; }
      if (axCollapse(axAttribute(element, 'aria-label'))) { return false; }
      if (axAttribute(element, 'aria-labelledby')) { return false; }
      return true;
    }
    """#
}
