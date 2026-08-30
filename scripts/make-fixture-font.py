#!/usr/bin/env python3
"""Generates Tests/TestSupport/Fixtures/block-font.ttf.

The webfont fixture needs a face whose glyphs are unmistakably *not* the
fallback: every letter is one solid rectangle, so a paragraph set in it is a
row of black bars where the fallback serif would draw letterforms. That makes
"did the repaint with the webfont land?" a difference of tens of channel
levels rather than a judgement about antialiasing.

The font is generated rather than checked out of the system so nothing
licensed is vendored, and so the fixture is reproducible:

    python3 scripts/make-fixture-font.py

Requires fontTools (``python3 -m pip install fonttools``); written against
4.62.1. Re-run it only if the fixture's shape must change — the .ttf is
committed, and the tests do not invoke this script.
"""

from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

UNITS_PER_EM = 1000
ASCENT = 800
DESCENT = -200
ADVANCE = 700
FAMILY = "Sleepy Block"

# Every letter and digit maps to the one bar glyph; that is the whole point.
COVERED = (
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ" "abcdefghijklmnopqrstuvwxyz" "0123456789"
)


def bar_glyph():
    """One filled rectangle, inset from the advance so bars stay separable."""
    pen = TTGlyphPen(None)
    pen.moveTo((60, 0))
    pen.lineTo((60, 700))
    pen.lineTo((640, 700))
    pen.lineTo((640, 0))
    pen.closePath()
    return pen.glyph()


def build(destination: Path) -> None:
    builder = FontBuilder(UNITS_PER_EM, isTTF=True)
    builder.setupGlyphOrder([".notdef", "bar"])
    builder.setupCharacterMap({ord(character): "bar" for character in COVERED})
    builder.setupGlyf({".notdef": TTGlyphPen(None).glyph(), "bar": bar_glyph()})
    builder.setupHorizontalMetrics({".notdef": (ADVANCE, 0), "bar": (ADVANCE, 60)})
    builder.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    builder.setupNameTable(
        {
            "familyName": FAMILY,
            "styleName": "Regular",
            "uniqueFontIdentifier": f"{FAMILY} Regular; SleepyHollow fixture",
            "fullName": f"{FAMILY} Regular",
            "psName": "SleepyBlock-Regular",
            "version": "Version 1.000",
        }
    )
    builder.setupOS2(
        sTypoAscender=ASCENT,
        sTypoDescender=DESCENT,
        sTypoLineGap=0,
        usWinAscent=ASCENT,
        usWinDescent=-DESCENT,
    )
    builder.setupPost()
    destination.parent.mkdir(parents=True, exist_ok=True)
    builder.save(str(destination))
    print(f"wrote {destination} ({destination.stat().st_size} bytes)")


if __name__ == "__main__":
    root = Path(__file__).resolve().parent.parent
    build(root / "Tests" / "TestSupport" / "Fixtures" / "block-font.ttf")
