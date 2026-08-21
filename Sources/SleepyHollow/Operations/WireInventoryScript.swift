/// The expression that reads the wire log's inventory layer out of the page's
/// performance timeline.
///
/// It runs in ``InjectedScript/World/isolated``: the timeline is a DOM API, so
/// an isolated world sees exactly the same entries, but not a page's
/// monkey-patched `performance.getEntriesByType`. The inventory is a witness
/// statement — it should not be forgeable from the page.
///
/// Absent fields are omitted rather than zeroed, because in this timeline a
/// `0` is ambiguous: cross-origin it means "withheld", same-origin it means
/// "this phase did not happen". The gates are measured in
/// `project/2026-08-20-wire-spike.md`.
enum WireInventoryScript {
    /// The phase timestamps worth reporting, in the order they occur.
    static let timingFields: [String] = [
        "fetchStart",
        "domainLookupStart",
        "domainLookupEnd",
        "connectStart",
        "connectEnd",
        "secureConnectionStart",
        "requestStart",
        "responseStart",
        "responseEnd",
    ]

    /// The body ``PageHost/evaluate(_:arguments:in:)`` runs: an array of
    /// entries decodable as ``ResourceEntry``, main frame first.
    static let expression: String = """
    const timingFields = [\(timingFields.map { "'\($0)'" }.joined(separator: ", "))];
    function round(value) {
      return typeof value === 'number' ? Math.round(value * 1000) / 1000 : 0;
    }
    function isForeign(url) {
      try { return new URL(url, location.href).origin !== location.origin; } catch (ignored) { return false; }
    }
    function timingOf(entry) {
      const timing = {};
      let any = false;
      for (const field of timingFields) {
        const value = entry[field];
        if (typeof value === 'number' && value > 0) { timing[field] = round(value); any = true; }
      }
      return any ? timing : undefined;
    }
    function describe(entry, initiatorType) {
      const foreign = isForeign(entry.name);
      const described = {
        url: entry.name,
        initiatorType: initiatorType,
        startTime: round(entry.startTime),
        duration: round(entry.duration),
        isCrossOrigin: foreign
      };
      if (typeof entry.nextHopProtocol === 'string' && entry.nextHopProtocol !== '') {
        described.nextHopProtocol = entry.nextHopProtocol;
      }
      // Sizes are same-origin-only in WebKit — cross-origin entries report 0
      // whatever Timing-Allow-Origin says, so they are reported as absent.
      if (!foreign) {
        for (const field of ['transferSize', 'encodedBodySize', 'decodedBodySize']) {
          if (typeof entry[field] === 'number') { described[field] = entry[field]; }
        }
      }
      const timing = timingOf(entry);
      if (timing) { described.timing = timing; }
      return described;
    }
    const entries = [];
    let navigation = null;
    try { navigation = performance.getEntriesByType('navigation')[0] || null; } catch (ignored) {}
    if (navigation) {
      entries.push(describe(navigation, 'navigation'));
    } else {
      entries.push({
        url: location.href, initiatorType: 'navigation', startTime: 0, duration: 0, isCrossOrigin: false
      });
    }
    let resources = [];
    try { resources = performance.getEntriesByType('resource'); } catch (ignored) {}
    for (const entry of resources) {
      entries.push(describe(entry, String(entry.initiatorType || 'other')));
    }
    return entries;
    """
}
