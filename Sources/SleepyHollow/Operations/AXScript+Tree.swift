extension AXScript {
    /// The walk that assembles the tree, and the entry point the operation
    /// evaluates.
    ///
    /// Three rules shape it. Hidden subtrees are never entered, so hiding
    /// inherits. A presentational node is replaced by its children, and if it
    /// owns required elements — a `table`'s rows and cells, a `list`'s items —
    /// those become presentational too, recursively. Text that has already
    /// been spoken as some element's accessible name is not repeated as a
    /// text node.
    static let tree: String = #"""
    /// Text-level semantics that say nothing once they are empty. They go
    /// empty routinely: an `<a>Read <strong>more</strong></a>` spends its
    /// text on the link's name, and what is left of the `strong` is a husk
    /// this walk created. Widgets, images and table structure are never
    /// dropped — an empty cell or an unlabelled button is a finding.
    const AX_DROP_WHEN_EMPTY = new Set([
      'generic', 'strong', 'emphasis', 'code', 'deletion', 'insertion', 'subscript',
      'superscript', 'paragraph', 'time', 'term', 'definition', 'caption', 'blockquote',
      'math', 'note',
    ]);

    function axTextNode(text) {
      return { role: 'text', name: text, states: [], children: [] };
    }

    function axNodesForElement(element, owner, suppressText) {
      if (axIsHidden(element)) { return []; }

      const tag = element.localName;
      if (tag === 'iframe' || tag === 'frame') { return axFrameNodes(element); }

      const implicit = axImplicitRole(element);
      let role = axRoleOf(element);

      // Presentational inheritance: a presentational owner makes the
      // descendants that fill its required roles presentational too.
      if (owner && (AX_REQUIRED_OWNED[owner] || []).indexOf(implicit) !== -1 &&
          !axPresentationBlocked(element)) {
        role = 'presentation';
      }

      if (role === 'presentation') {
        return axChildNodes(element, implicit, suppressText);
      }

      // A caption whose text is already the accessible name of its table,
      // fieldset or figure has nothing left to contribute.
      if (AX_CONSUMED.has(element) &&
          (tag === 'caption' || tag === 'legend' || tag === 'figcaption')) {
        return axChildNodes(element, null, suppressText);
      }

      const name = axAccessibleName(element);
      const node = { role: role };
      if (name) { node.name = name; }
      const value = axValueFor(element, role);
      if (value) { node.value = value; }
      node.states = axStatesFor(element, role);
      // A collapsed select is read by its value, not by its hundreds of
      // options: only the chosen one is worth a line. A listbox — multiple,
      // or sized open — lists them all, because there the set is the point.
      node.children = (role === 'combobox' && tag === 'select')
        ? axSelectedOptionNodes(element)
        : axChildNodes(element, null, suppressText || axNamedFromContent(element, role, name));

      if (!node.name && !node.value && node.states.length === 0 &&
          node.children.length === 0 && AX_DROP_WHEN_EMPTY.has(role)) {
        return [];
      }
      return [node];
    }

    function axSelectedOptionNodes(element) {
      let options = [];
      try {
        options = Array.from(element.selectedOptions || []);
      } catch (error) {
        options = [];
      }
      const nodes = [];
      for (const option of options) {
        const built = axNodesForElement(option, null, false);
        for (const node of built) { nodes.push(node); }
      }
      return nodes;
    }

    function axChildNodes(element, owner, suppressText) {
      const nodes = [];
      let children = [];
      try {
        children = Array.from(element.childNodes);
      } catch (error) {
        children = [];
      }
      for (const child of children) {
        if (child.nodeType === AX_TEXT_NODE) {
          if (suppressText) { continue; }
          const text = axCollapse(child.data);
          if (!text) { continue; }
          if (axIsConsumedText(child)) { continue; }
          nodes.push(axTextNode(text));
          continue;
        }
        if (child.nodeType !== AX_ELEMENT_NODE) { continue; }
        const built = axNodesForElement(child, owner, suppressText);
        for (const node of built) { nodes.push(node); }
      }
      return nodes;
    }

    /// A same-origin frame is another document, and reads as one. A
    /// cross-origin frame is opaque to any script in this page, so it comes
    /// back as an empty document node rather than a silent omission.
    function axFrameNodes(element) {
      let inner = null;
      try {
        inner = element.contentDocument;
      } catch (error) {
        inner = null;
      }
      const name = axAccessibleName(element);
      const node = { role: 'document', states: [], children: [] };
      if (name) {
        node.name = name;
      } else if (inner) {
        const title = axCollapse(inner.title);
        if (title) { node.name = title; }
      }
      if (inner && inner.body) {
        axMarkConsumedLabels(inner);
        node.children = axChildNodes(inner.body, null, false);
      }
      return [node];
    }

    function axSnapshot() {
      axMarkConsumedLabels(document);
      const root = { role: 'document', states: [], children: [] };
      const title = axCollapse(document.title);
      if (title) { root.name = title; }
      if (document.body) {
        root.children = axChildNodes(document.body, null, false);
      }
      return root;
    }

    return axSnapshot();
    """#
}
