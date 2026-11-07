import Foundation

/// The page-side halves of the real-input actions: resolving what a focus,
/// hover or press acts on, and checking afterwards that it took.
///
/// The events themselves never come from here — ``TrustedInput`` sends them
/// through the host's window, so the page sees `isTrusted` and the browser
/// runs each one's default action. These bodies only find the element, put
/// it where the pointer can reach it, and read back what the page now
/// believes, so a hover that did not land or a focus the element refused is
/// a refusal rather than a quiet no-op.
extension ActionScript {
    /// The isolated-world global a hover leaves its target under, for the
    /// check that follows the pointer move.
    static let hoverTargetKey: String = "__sleepyHoverTarget"

    /// The isolated-world global a press leaves the focused element under,
    /// for reading its value once the keys have landed.
    static let pressTargetKey: String = "__sleepyPressTarget"

    /// A focus: the element's own `focus()` with `focusVisible: true`, so
    /// `:focus-visible` matches as it does after keyboard navigation —
    /// whatever the last pointer did. An element that does not end up
    /// focused (a plain `<div>`) is refused rather than reported focused.
    static let focusBody: String = composedContainsHelper + "\n" + """
    const found = sleepyLocate(selector);
    if (found.error) return found;
    const element = found.element;
    const tag = sleepyTag(element);
    if (sleepyDisabled(element)) return { error: 'disabled', tagName: tag };
    if (typeof element.focus === 'function') element.focus({ focusVisible: true });
    const active = document.activeElement;
    const inside = active && active !== document.body && sleepyComposedContains(element, active);
    if (active !== element && !inside) return { error: 'not-focusable', tagName: tag };
    return { tagName: tag };
    """

    /// A hover's first half: scroll the element into view and answer the
    /// viewport point at its center, refusing one with no box or one another
    /// element covers there — the pointer would land on that instead.
    static let hoverLocateBody: String = hitTestHelpers + "\n" + composedContainsHelper + "\n" + """
    const found = sleepyLocate(selector);
    if (found.error) return found;
    const element = found.element;
    const tag = sleepyTag(element);
    if (typeof element.scrollIntoView === 'function') {
      element.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    }
    const rect = element.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return { error: 'not-visible', tagName: tag };
    const x = rect.left + rect.width / 2;
    const y = rect.top + rect.height / 2;
    const hit = sleepyHitTest(x, y);
    const top = hit ? hit.element : document.elementFromPoint(x, y);
    if (!top || !sleepyComposedContains(element, top)) {
      return { error: 'covered', tagName: tag, detail: top ? sleepyTag(top) : null };
    }
    window[hoverKey] = element;
    return { tagName: tag, x, y };
    """

    /// A hover's second half: whether the element the pointer was moved to
    /// now matches `:hover`.
    static let hoverCheckBody: String = """
    const element = window[hoverKey];
    if (!element || !element.isConnected) return { error: 'no-match' };
    const tag = sleepyTag(element);
    if (element.matches(':hover')) return { tagName: tag };
    const hovered = Array.from(document.querySelectorAll(':hover')).pop();
    return { error: 'not-hovered', tagName: tag, detail: hovered ? sleepyTag(hovered) : null };
    """

    /// A press's first half: remember the element that has focus — where the
    /// keys will go — and name it.
    static let pressTargetBody: String = """
    const element = document.activeElement || document.body;
    window[pressKey] = element;
    return { tagName: element ? sleepyTag(element) : 'body' };
    """

    /// A press's second half: what the focused element holds now, when it
    /// holds a value and is still in the page.
    static let pressValueBody: String = """
    const element = window[pressKey];
    if (!element || !element.isConnected) return {};
    const tag = sleepyTag(element);
    if ((tag === 'input' || tag === 'textarea' || tag === 'select') && typeof element.value === 'string') {
      return { tagName: tag, value: element.value };
    }
    if (element.isContentEditable) return { tagName: tag, value: element.textContent };
    return { tagName: tag };
    """

    /// Page-side helper the input bodies add to ``helpers``: containment that
    /// crosses shadow boundaries, since a hit test descends into open shadow
    /// roots and `Node.contains` stops at them.
    static let composedContainsHelper: String = """
    function sleepyComposedContains(outer, inner) {
      let node = inner;
      while (node) {
        if (node === outer) return true;
        node = node.parentNode || (node instanceof ShadowRoot ? node.host : null);
      }
      return false;
    }
    """
}
