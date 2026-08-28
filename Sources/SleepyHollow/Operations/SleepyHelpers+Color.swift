extension SleepyHelpers {
    /// Colour arithmetic: parsing what `getComputedStyle` hands back,
    /// alpha-compositing one layer over another, and WCAG 2's relative
    /// luminance and contrast ratio.
    ///
    /// A colour is a plain `[r, g, b, a]` array — 0–255 channels, 0–1 alpha —
    /// because that is the one shape every function here consumes and the one
    /// the report serializes. Parsing accepts `rgb()`/`rgba()` in either the
    /// comma or the slash syntax, `transparent`, `none` (SVG's absent paint),
    /// and hex, which is more than a computed style ever returns and cheap
    /// insurance against the one that does.
    static let colors: String = #"""
    const SLEEPY_OPAQUE_WHITE = [255, 255, 255, 1];

    function sleepyParseColor(text) {
      if (typeof text !== 'string') { return null; }
      const value = text.trim().toLowerCase();
      if (value === '' || value === 'none' || value === 'transparent') { return [0, 0, 0, 0]; }
      if (value.charAt(0) === '#') { return sleepyParseHex(value); }
      const open = value.indexOf('(');
      if (open < 0) { return null; }
      const head = value.slice(0, open);
      if (head !== 'rgb' && head !== 'rgba') { return null; }
      const tokens = value.slice(open + 1).replace(')', '').split(/[\s,\/]+/).filter(function (part) {
        return part !== '';
      });
      if (tokens.length < 3) { return null; }
      const channels = [
        parseFloat(tokens[0]),
        parseFloat(tokens[1]),
        parseFloat(tokens[2]),
      ];
      if (channels.some(function (n) { return !Number.isFinite(n); })) { return null; }
      channels.push(tokens.length > 3 ? sleepyAlpha(tokens[3]) : 1);
      return channels;
    }

    /// An alpha token, which CSS may write as a number or a percentage.
    function sleepyAlpha(token) {
      const value = parseFloat(token);
      if (!Number.isFinite(value)) { return 1; }
      return token.indexOf('%') >= 0 ? value / 100 : value;
    }

    function sleepyParseHex(value) {
      let hex = value.slice(1);
      if (hex.length === 3 || hex.length === 4) {
        hex = hex.split('').map(function (digit) { return digit + digit; }).join('');
      }
      if (hex.length !== 6 && hex.length !== 8) { return null; }
      const bytes = [];
      for (let i = 0; i < hex.length; i += 2) {
        const byte = parseInt(hex.slice(i, i + 2), 16);
        if (!Number.isFinite(byte)) { return null; }
        bytes.push(byte);
      }
      return [bytes[0], bytes[1], bytes[2], bytes.length > 3 ? bytes[3] / 255 : 1];
    }

    /// `top` composited over `bottom`, source-over.
    function sleepyOver(top, bottom) {
      const alpha = top[3] + bottom[3] * (1 - top[3]);
      if (alpha <= 0) { return [0, 0, 0, 0]; }
      const mix = function (index) {
        return (top[index] * top[3] + bottom[index] * bottom[3] * (1 - top[3])) / alpha;
      };
      return [mix(0), mix(1), mix(2), alpha];
    }

    /// `colour` with its alpha multiplied by `factor` — how fill-opacity and
    /// opacity fold into a paint.
    function sleepyFade(colour, factor) {
      if (!Number.isFinite(factor)) { return colour; }
      return [colour[0], colour[1], colour[2], colour[3] * factor];
    }

    /// WCAG 2's linearised channel value.
    function sleepyChannel(value) {
      const c = value / 255;
      return c <= 0.03928 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4);
    }

    function sleepyLuminance(colour) {
      return 0.2126 * sleepyChannel(colour[0])
        + 0.7152 * sleepyChannel(colour[1])
        + 0.0722 * sleepyChannel(colour[2]);
    }

    function sleepyContrastRatio(a, b) {
      const first = sleepyLuminance(a);
      const second = sleepyLuminance(b);
      const lighter = Math.max(first, second);
      const darker = Math.min(first, second);
      return (lighter + 0.05) / (darker + 0.05);
    }

    function sleepyHex(colour) {
      const byte = function (value) {
        const n = Math.max(0, Math.min(255, Math.round(value)));
        return (n < 16 ? '0' : '') + n.toString(16);
      };
      return '#' + byte(colour[0]) + byte(colour[1]) + byte(colour[2]);
    }

    function sleepyRound(value, places) {
      const factor = Math.pow(10, places);
      return Math.round(value * factor) / factor;
    }
    """#
}
