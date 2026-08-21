extension AXScript {
    /// States and values.
    ///
    /// Every state is reported only where it *applies*, and the ones that are
    /// meaningful in both directions (`checked`, `expanded`, `pressed`,
    /// `selected`) are reported in both — "not checked" is an answer, while a
    /// missing state is a question. Native semantics and ARIA attributes are
    /// both consulted: `:disabled` catches an ancestor `fieldset[disabled]`
    /// that `aria-disabled` would miss, and vice versa.
    static let states: String = #"""
    const AX_CHECKABLE_ROLES = new Set([
      'checkbox', 'radio', 'switch', 'menuitemcheckbox', 'menuitemradio',
    ]);

    const AX_RANGE_ROLES = new Set([
      'slider', 'spinbutton', 'progressbar', 'scrollbar', 'meter',
    ]);

    function axState(name, value) {
      return { name: name, value: value };
    }

    function axTriState(name, raw, nativeValue) {
      if (raw === 'mixed') { return axState(name, 'mixed'); }
      if (raw === 'true' || raw === 'false') { return axState(name, raw === 'true'); }
      if (typeof nativeValue === 'boolean') { return axState(name, nativeValue); }
      return null;
    }

    function axSelectedOptionText(element) {
      try {
        if (element.localName === 'select') {
          const option = element.selectedOptions && element.selectedOptions.length
            ? element.selectedOptions[0]
            : element.options[element.selectedIndex];
          return option ? axCollapse(option.textContent) : '';
        }
      } catch (error) {
        return '';
      }
      const selected = element.querySelector('[aria-selected="true"], option:checked');
      return selected ? axCollapse(selected.textContent) : '';
    }

    function axRangeValueText(element) {
      const text = axCollapse(axAttribute(element, 'aria-valuetext'));
      if (text) { return text; }
      const now = axAttribute(element, 'aria-valuenow');
      if (now !== null && axCollapse(now)) { return axCollapse(now); }
      if (element.value !== undefined && element.value !== null && String(element.value) !== '') {
        return String(element.value);
      }
      return '';
    }

    function axHeadingLevel(element) {
      const authored = parseInt(axAttribute(element, 'aria-level'), 10);
      if (!isNaN(authored)) { return authored; }
      const match = /^h([1-6])$/.exec(element.localName);
      return match ? Number(match[1]) : 2;
    }

    function axStatesFor(element, role) {
      const states = [];

      const ariaDisabled = axAttribute(element, 'aria-disabled') === 'true';
      if (ariaDisabled || axMatches(element, ':disabled')) { states.push(axState('disabled', true)); }

      if (AX_CHECKABLE_ROLES.has(role)) {
        const indeterminate = element.indeterminate === true;
        const checked = indeterminate
          ? axState('checked', 'mixed')
          : axTriState('checked', axAttribute(element, 'aria-checked'), element.checked);
        if (checked) { states.push(checked); }
      }

      let expanded = axTriState('expanded', axAttribute(element, 'aria-expanded'), undefined);
      if (!expanded && element.localName === 'summary') {
        const details = element.parentElement;
        if (details && details.localName === 'details') {
          expanded = axState('expanded', details.open === true);
        }
      }
      if (expanded) { states.push(expanded); }

      const pressed = axTriState('pressed', axAttribute(element, 'aria-pressed'), undefined);
      if (pressed) { states.push(pressed); }

      const selected = axTriState(
        'selected',
        axAttribute(element, 'aria-selected'),
        role === 'option' ? element.selected : undefined,
      );
      if (selected) { states.push(selected); }

      if (axAttribute(element, 'aria-required') === 'true' || axMatches(element, ':required')) {
        states.push(axState('required', true));
      }

      if (axAttribute(element, 'aria-readonly') === 'true' || element.readOnly === true) {
        states.push(axState('readonly', true));
      }

      const current = axAttribute(element, 'aria-current');
      if (current && current !== 'false') {
        states.push(axState('current', current === 'true' ? true : current));
      }

      if (role === 'heading') { states.push(axState('level', axHeadingLevel(element))); }

      states.sort((left, right) => (left.name < right.name ? -1 : (left.name > right.name ? 1 : 0)));
      return states;
    }

    /// The value an agent would read off the control — a field's contents, a
    /// select's chosen option's label (not its `value` attribute, which is a
    /// wire detail), a range's position.
    function axValueFor(element, role) {
      if (role === 'textbox' || role === 'searchbox') {
        return axCollapse(element.value) || null;
      }
      if (role === 'combobox' || role === 'listbox') {
        return axSelectedOptionText(element) || null;
      }
      if (AX_RANGE_ROLES.has(role)) {
        return axRangeValueText(element) || null;
      }
      return null;
    }
    """#
}
