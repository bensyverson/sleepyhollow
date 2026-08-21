extension AXScript {
    /// Role computation: an explicit, valid, non-abstract `role` attribute
    /// wins; otherwise HTML-AAM's implicit mapping applies.
    ///
    /// The tables here are the spec knowledge this file exists to hold. Two
    /// of them are subtle enough to be worth naming: `AX_REQUIRED_OWNED` is
    /// what makes `role="presentation"` on a `table` strip its `tbody`, `tr`
    /// and `td` too (presentational inheritance through required owned
    /// elements — the trap the spike hit), and `AX_NAME_FROM_CONTENT` is
    /// deliberately *without* `listitem` and `paragraph`, which ARIA excludes.
    static let roles: String = #"""
    const AX_ABSTRACT_ROLES = new Set([
      'command', 'composite', 'input', 'landmark', 'range', 'roletype', 'section',
      'sectionhead', 'select', 'structure', 'widget', 'window',
    ]);

    const AX_VALID_ROLES = new Set([
      'alert', 'alertdialog', 'application', 'article', 'banner', 'blockquote', 'button',
      'caption', 'cell', 'checkbox', 'code', 'columnheader', 'combobox', 'complementary',
      'contentinfo', 'definition', 'deletion', 'dialog', 'directory', 'document', 'emphasis',
      'feed', 'figure', 'form', 'generic', 'grid', 'gridcell', 'group', 'heading', 'image',
      'img', 'insertion', 'link', 'list', 'listbox', 'listitem', 'log', 'main', 'marquee',
      'math', 'menu', 'menubar', 'menuitem', 'menuitemcheckbox', 'menuitemradio', 'meter',
      'navigation', 'none', 'note', 'option', 'paragraph', 'presentation', 'progressbar',
      'radio', 'radiogroup', 'region', 'row', 'rowgroup', 'rowheader', 'scrollbar', 'search',
      'searchbox', 'separator', 'slider', 'spinbutton', 'status', 'strong', 'subscript',
      'superscript', 'switch', 'tab', 'table', 'tablist', 'tabpanel', 'term', 'textbox',
      'time', 'timer', 'toolbar', 'tooltip', 'tree', 'treegrid', 'treeitem',
    ]);

    /// ARIA "Name From: contents". `listitem` and `paragraph` are absent on
    /// purpose: ARIA names them from the author only, and `paragraph`
    /// prohibits naming outright.
    const AX_NAME_FROM_CONTENT = new Set([
      'button', 'cell', 'checkbox', 'columnheader', 'gridcell', 'heading', 'link', 'menuitem',
      'menuitemcheckbox', 'menuitemradio', 'option', 'radio', 'row', 'rowheader', 'switch',
      'tab', 'tooltip', 'treeitem',
    ]);

    /// Roles that prohibit an accessible name.
    const AX_NAME_PROHIBITED = new Set([
      'caption', 'code', 'deletion', 'emphasis', 'generic', 'insertion', 'none', 'paragraph',
      'presentation', 'strong', 'subscript', 'superscript', 'text',
    ]);

    /// Required owned elements, for presentational inheritance: when a node
    /// carrying one of these roles is presentational, the descendants that
    /// fill its required roles are presentational too, recursively.
    const AX_REQUIRED_OWNED = {
      table: ['rowgroup', 'row', 'columnheader', 'rowheader', 'cell', 'caption'],
      grid: ['rowgroup', 'row', 'columnheader', 'rowheader', 'gridcell', 'cell', 'caption'],
      treegrid: ['rowgroup', 'row', 'columnheader', 'rowheader', 'gridcell', 'cell', 'caption'],
      rowgroup: ['row', 'columnheader', 'rowheader', 'cell', 'gridcell'],
      row: ['columnheader', 'rowheader', 'cell', 'gridcell'],
      list: ['listitem'],
      listbox: ['option', 'group'],
      menu: ['menuitem', 'menuitemcheckbox', 'menuitemradio', 'group'],
      menubar: ['menuitem', 'menuitemcheckbox', 'menuitemradio', 'group'],
      tablist: ['tab'],
      tree: ['treeitem', 'group'],
      radiogroup: ['radio'],
    };

    const AX_INPUT_ROLES = {
      button: 'button',
      checkbox: 'checkbox',
      email: 'textbox',
      image: 'button',
      number: 'spinbutton',
      radio: 'radio',
      range: 'slider',
      reset: 'button',
      search: 'searchbox',
      submit: 'button',
      tel: 'textbox',
      text: 'textbox',
      url: 'textbox',
      // Not an ARIA mapping — the spec gives password no role — but every
      // browser exposes it as a text field and an agent asking "is the
      // password box there?" deserves an answer.
      password: 'textbox',
      file: 'button',
    };

    /// True when `role="presentation"` must be ignored: the element is
    /// focusable or carries a global ARIA attribute, either of which keeps it
    /// in the tree with its implicit role.
    function axPresentationBlocked(element) {
      if (element.hasAttribute('aria-label') || element.hasAttribute('aria-labelledby')) { return true; }
      if (element.hasAttribute('tabindex')) { return true; }
      return axMatches(element, 'a[href], area[href], button, input, select, textarea, summary, iframe, [contenteditable="true"]');
    }

    function axExplicitRole(element) {
      const raw = axAttribute(element, 'role');
      if (!raw) { return null; }
      for (const token of raw.split(/\s+/)) {
        const role = token.toLowerCase();
        if (role === 'none') { return 'presentation'; }
        if (role === 'img') { return 'image'; }
        if (AX_VALID_ROLES.has(role) && !AX_ABSTRACT_ROLES.has(role)) { return role; }
      }
      return null;
    }

    /// An author name, decided without computing one — the naming rules for
    /// `section` and `footer` need this and would otherwise recurse.
    function axHasAuthorName(element) {
      if (axCollapse(axAttribute(element, 'aria-label'))) { return true; }
      const ids = (axAttribute(element, 'aria-labelledby') || '').split(/\s+/).filter(Boolean);
      for (const id of ids) {
        if (axElementById(element, id)) { return true; }
      }
      return Boolean(axCollapse(axAttribute(element, 'title')));
    }

    function axIsScoped(element) {
      const parent = element.parentElement;
      if (!parent) { return false; }
      try {
        return parent.closest('article, aside, main, nav, section') !== null;
      } catch (error) {
        return false;
      }
    }

    function axHeaderCellRole(element) {
      const scope = (axAttribute(element, 'scope') || '').toLowerCase();
      if (scope === 'row' || scope === 'rowgroup') { return 'rowheader'; }
      if (scope === 'col' || scope === 'colgroup') { return 'columnheader'; }
      const row = element.parentElement;
      if (row && row.localName === 'tr' && row.querySelector(':scope > td')) { return 'rowheader'; }
      return 'columnheader';
    }

    function axImplicitRole(element) {
      const tag = element.localName;
      switch (tag) {
        case 'a': case 'area': return element.hasAttribute('href') ? 'link' : 'generic';
        case 'article': return 'article';
        case 'aside': return 'complementary';
        case 'blockquote': return 'blockquote';
        case 'button': return 'button';
        case 'caption': return 'caption';
        case 'code': return 'code';
        case 'datalist': return 'listbox';
        case 'dd': return 'definition';
        case 'del': case 's': return 'deletion';
        case 'details': return 'group';
        case 'dfn': return 'term';
        case 'dialog': return 'dialog';
        case 'dl': return 'list';
        case 'dt': return 'term';
        case 'em': return 'emphasis';
        case 'fieldset': return 'group';
        case 'figure': return 'figure';
        case 'footer': return axIsScoped(element) ? 'generic' : 'contentinfo';
        case 'form': return 'form';
        case 'h1': case 'h2': case 'h3': case 'h4': case 'h5': case 'h6': return 'heading';
        case 'header': return axIsScoped(element) ? 'generic' : 'banner';
        case 'hgroup': return 'group';
        case 'hr': return 'separator';
        case 'html': return 'document';
        case 'img': {
          const alt = axAttribute(element, 'alt');
          if (alt !== null && axCollapse(alt) === '' && !axHasAuthorName(element)) { return 'presentation'; }
          return 'image';
        }
        case 'input': {
          const type = (axAttribute(element, 'type') || 'text').toLowerCase();
          const role = AX_INPUT_ROLES[type];
          if (!role) { return 'generic'; }
          if ((role === 'textbox' || role === 'searchbox') && element.hasAttribute('list')) { return 'combobox'; }
          return role;
        }
        case 'ins': return 'insertion';
        case 'li': {
          const parent = element.parentElement;
          const parentTag = parent ? parent.localName : '';
          return (parentTag === 'ul' || parentTag === 'ol' || parentTag === 'menu') ? 'listitem' : 'generic';
        }
        case 'main': return 'main';
        case 'math': return 'math';
        case 'menu': case 'ol': case 'ul': return 'list';
        case 'meter': return 'meter';
        case 'nav': return 'navigation';
        case 'optgroup': return 'group';
        case 'option': return 'option';
        case 'output': return 'status';
        case 'p': return 'paragraph';
        case 'progress': return 'progressbar';
        case 'search': return 'search';
        case 'section': return axHasAuthorName(element) ? 'region' : 'generic';
        case 'select': {
          const multiple = element.hasAttribute('multiple');
          const size = Number(axAttribute(element, 'size') || '0');
          return (multiple || size > 1) ? 'listbox' : 'combobox';
        }
        case 'strong': return 'strong';
        case 'sub': return 'subscript';
        case 'summary': return 'button';
        case 'sup': return 'superscript';
        case 'svg': return 'image';
        case 'table': return 'table';
        case 'tbody': case 'tfoot': case 'thead': return 'rowgroup';
        case 'td': return 'cell';
        case 'textarea': return 'textbox';
        case 'th': return axHeaderCellRole(element);
        case 'time': return 'time';
        case 'tr': return 'row';
        default: return 'generic';
      }
    }

    function axRoleOf(element) {
      const explicit = axExplicitRole(element);
      if (explicit) {
        if (explicit === 'presentation' && axPresentationBlocked(element)) { return axImplicitRole(element); }
        return explicit;
      }
      return axImplicitRole(element);
    }
    """#
}
