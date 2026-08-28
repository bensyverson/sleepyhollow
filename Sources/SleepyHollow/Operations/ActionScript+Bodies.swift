extension ActionScript {
    /// Page-side helpers every action body shares: element lookup, the
    /// disabled test, and the submit watcher that tells a click whether the
    /// page really started navigating.
    ///
    /// The watcher listens for `submit` in the *capture* phase at the
    /// document, so it sees the event before any page handler and can read
    /// `defaultPrevented` afterwards — the honest answer to "did that click
    /// actually submit, or did the page cancel it?".
    static let helpers: String = """
    function sleepyTag(element) {
      return element.tagName.toLowerCase();
    }

    function sleepyLocate(chosen) {
      let element;
      try {
        element = document.querySelector(chosen);
      } catch (failure) {
        return { error: 'invalid-selector', detail: String(failure) };
      }
      if (!element) return { error: 'no-match' };
      return { element };
    }

    function sleepyDisabled(element) {
      if (element.disabled) return true;
      return !!(element.closest && element.closest('fieldset[disabled]'));
    }

    function sleepyWatchSubmits() {
      let last = null;
      const probe = (event) => { last = event; };
      document.addEventListener('submit', probe, true);
      return () => {
        document.removeEventListener('submit', probe, true);
        return last !== null && !last.defaultPrevented;
      };
    }

    function sleepyFollowsLink(element) {
      const anchor = element.closest ? element.closest('a[href]') : null;
      if (!anchor) return false;
      const href = (anchor.getAttribute('href') || '').trim();
      if (href === '' || href.startsWith('#')) return false;
      return !href.toLowerCase().startsWith('javascript:');
    }

    function sleepyDispatchClick(element, x, y) {
      const stopWatching = sleepyWatchSubmits();
      let allowed = true;
      for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {
        const pressing = type === 'pointerdown' || type === 'mousedown';
        const init = {
          bubbles: true,
          cancelable: true,
          composed: true,
          view: window,
          button: 0,
          buttons: pressing ? 1 : 0,
          detail: type === 'click' ? 1 : 0,
          clientX: x,
          clientY: y,
        };
        const pointer = type.startsWith('pointer') && typeof PointerEvent === 'function';
        const event = pointer
          ? new PointerEvent(type, Object.assign({ pointerId: 1, pointerType: 'mouse', isPrimary: true }, init))
          : new MouseEvent(type, init);
        const proceeded = element.dispatchEvent(event);
        if (type === 'click') allowed = proceeded;
      }
      const submitted = stopWatching();
      return submitted || (allowed && sleepyFollowsLink(element));
    }

    function sleepyNativeSetter(element, property) {
      const prototype = Object.getPrototypeOf(element);
      const descriptor = Object.getOwnPropertyDescriptor(prototype, property);
      return descriptor && descriptor.set ? descriptor.set.bind(element) : null;
    }
    """

    /// A click: the pointer, mouse and click sequence a page listens for,
    /// dispatched at the element's centre.
    static let clickBody: String = """
    const found = sleepyLocate(selector);
    if (found.error) return found;
    const element = found.element;
    if (sleepyDisabled(element)) return { error: 'disabled', tagName: sleepyTag(element) };
    if (typeof element.scrollIntoView === 'function') {
      element.scrollIntoView({ block: 'center', inline: 'center' });
    }
    if (typeof element.focus === 'function') element.focus();
    const rect = element.getBoundingClientRect();
    const navigating = sleepyDispatchClick(element, rect.left + rect.width / 2, rect.top + rect.height / 2);
    return { tagName: sleepyTag(element), navigating };
    """

    /// A fill: the value set through the native setter, then `input` and
    /// `change`, so a page that tracks its own fields sees a real edit.
    static let fillBody: String = """
    const found = sleepyLocate(selector);
    if (found.error) return found;
    const element = found.element;
    const tag = sleepyTag(element);
    if (sleepyDisabled(element)) return { error: 'disabled', tagName: tag };
    if (element.readOnly) return { error: 'read-only', tagName: tag };
    if (typeof element.focus === 'function') element.focus();

    const kind = (element.type || '').toLowerCase();
    let settled;
    if (tag === 'input' && (kind === 'checkbox' || kind === 'radio')) {
      const on = ['true', '1', 'on', 'yes', 'checked'].indexOf(String(value).toLowerCase()) !== -1;
      const setter = sleepyNativeSetter(element, 'checked');
      if (setter) { setter(on); } else { element.checked = on; }
      settled = on ? 'true' : 'false';
    } else if (tag === 'select') {
      const options = Array.from(element.options);
      const match = options.find((option) => option.value === value)
        || options.find((option) => (option.label || option.text || '').trim() === value);
      if (!match) return { error: 'no-option', tagName: tag };
      element.value = match.value;
      settled = element.value;
    } else if (tag === 'input' || tag === 'textarea') {
      const setter = sleepyNativeSetter(element, 'value');
      if (setter) { setter(String(value)); } else { element.value = String(value); }
      settled = element.value;
    } else if (element.isContentEditable) {
      element.textContent = String(value);
      settled = element.textContent;
    } else {
      return { error: 'not-fillable', tagName: tag };
    }

    const typed = tag === 'input' || tag === 'textarea';
    const input = typed && typeof InputEvent === 'function'
      ? new InputEvent('input', { bubbles: true, composed: true, data: String(value), inputType: 'insertText' })
      : new Event('input', { bubbles: true, composed: true });
    element.dispatchEvent(input);
    element.dispatchEvent(new Event('change', { bubbles: true }));
    return { tagName: tag, value: settled };
    """

    /// A submit: the form the selector names or belongs to, submitted through
    /// a real `submit` event the page can cancel.
    static let submitBody: String = """
    const found = sleepyLocate(selector);
    if (found.error) return found;
    const element = found.element;
    const tag = sleepyTag(element);
    const form = tag === 'form' ? element : (element.form || (element.closest ? element.closest('form') : null));
    if (!form) return { error: 'no-form', tagName: tag };
    if (!form.noValidate && typeof form.checkValidity === 'function' && !form.checkValidity()) {
      const invalid = Array.from(form.elements).find((field) => field.willValidate && !field.checkValidity());
      return {
        error: 'invalid-form',
        tagName: 'form',
        detail: invalid ? (invalid.id || invalid.name || sleepyTag(invalid)) : null,
      };
    }
    const stopWatching = sleepyWatchSubmits();
    if (typeof form.requestSubmit === 'function') {
      form.requestSubmit();
    } else if (form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))) {
      form.submit();
    }
    return { tagName: 'form', value: form.id, navigating: stopWatching() };
    """
}
