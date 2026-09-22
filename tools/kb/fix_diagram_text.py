#!/usr/bin/env python3
"""Fit diagram text inside its canvas.

THE BUG THIS FIXES. Many diagrams carry an explanatory line or two along the
bottom, and several of those lines are longer than the 480-unit canvas they
were drawn in. SVG does not wrap text: the sentence simply stops at the edge,
mid-word, with nothing to show that anything is missing. It is invisible while
writing the markup and obvious the instant the diagram is rendered.

TWO REPAIRS, IN ORDER.

  1. Footnote lines along the bottom are WRAPPED and the canvas grows
     downward. Widening would also stop the clipping, but it strands the
     drawing in the left two-thirds of a wider frame and changes the
     proportions of every diagram; growing downward leaves the drawing exactly
     where it was.

  2. Whatever still overflows is a right-hand label that cannot be wrapped
     sensibly, so the canvas is WIDENED to fit it. These are usually a few
     units over, so nothing is left stranded.

The canvas size is written once, at the end, from a single pair of variables -
the earlier version of this script updated the viewBox in two places and the
second overwrote the first, which produced files whose width attribute and
viewBox disagreed and which therefore still clipped.

    python3 tools/kb/fix_diagram_text.py          # report only
    python3 tools/kb/fix_diagram_text.py --fix    # rewrite the files
"""

from __future__ import annotations

import math
import re
import sys
from pathlib import Path

KB = Path(__file__).resolve().parents[2] / "knowledge"

TEXT_RE = re.compile(r"<text\b([^>]*)>([^<]*)</text>")
Y_RE = re.compile(r'y="[\d.]+"')
VIEWBOX_RE = re.compile(r'viewBox="0 0 ([\d.]+) ([\d.]+)"')
MARGIN = 10          # keep this much clear of the right edge
BOTTOM_BAND = 70     # a line lower than (height - this) counts as a footnote


def attr(name: str, s: str, default=None):
    m = re.search(rf'{name}="([^"]*)"', s)
    return m.group(1) if m else default


def char_factor(attrs: str) -> float:
    """Approximate width per character, as a fraction of the font size.

    No font metrics are available here, but for one sans-serif face at these
    sizes a flat factor is accurate to a few per cent — enough to decide
    whether a line overflows.
    """
    if "monospace" in (attr("font-family", attrs) or ""):
        return 0.60
    return 0.575 if attr("font-weight", attrs) in ("600", "700", "bold") else 0.55


def width_of(text: str, size: float, factor: float) -> float:
    return len(text) * size * factor


def right_extent(attrs: str, content: str, root_size: float) -> tuple[float, float]:
    x = float(attr("x", attrs) or 0)
    y = float(attr("y", attrs) or 0)
    size = float(attr("font-size", attrs) or root_size)
    anchor = attr("text-anchor", attrs) or "start"
    w = width_of(content, size, char_factor(attrs))
    right = x + w if anchor == "start" else (x + w / 2 if anchor == "middle" else x)
    return right, y


def wrap(text: str, limit: float, size: float, factor: float) -> list[str]:
    lines, cur = [], ""
    for word in text.split():
        trial = f"{cur} {word}".strip()
        if width_of(trial, size, factor) <= limit or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = word
    if cur:
        lines.append(cur)
    return lines


def set_canvas(svg: str, w: int, h: int) -> str:
    """Write the canvas size into the three places that must agree."""
    svg = VIEWBOX_RE.sub(f'viewBox="0 0 {w} {h}"', svg, count=1)
    svg = re.sub(r'(<svg\b[^>]*?\bwidth=")[\d.]+(")', rf"\g<1>{w}\g<2>", svg, count=1)
    svg = re.sub(r'(<svg\b[^>]*?\bheight=")[\d.]+(")', rf"\g<1>{h}\g<2>", svg, count=1)
    svg = re.sub(r'(<rect x="0" y="0" width=")[\d.]+(")', rf"\g<1>{w}\g<2>", svg, count=1)
    svg = re.sub(r'(<rect x="0" y="0" width="[\d.]+" height=")[\d.]+(")',
                 rf"\g<1>{h}\g<2>", svg, count=1)
    return svg


def process(path: Path, apply_fix: bool) -> tuple[int, bool, bool]:
    svg = path.read_text(encoding="utf-8")
    vb = VIEWBOX_RE.search(svg)
    if not vb:
        return 0, False, False
    W, H = int(float(vb.group(1))), int(float(vb.group(2)))
    root_size = float(attr("font-size", svg[:svg.find(">")]) or 12)

    # --- pass 1: wrap the footnotes -------------------------------------
    wrapped, max_y, out, pos = 0, 0.0, [], 0
    for m in TEXT_RE.finditer(svg):
        attrs, content = m.group(1), m.group(2)
        if not content.strip():
            continue
        right, y = right_extent(attrs, content, root_size)
        max_y = max(max_y, y)
        if right <= W - MARGIN or y < H - BOTTOM_BAND:
            continue

        x = float(attr("x", attrs) or 0)
        size = float(attr("font-size", attrs) or root_size)
        anchor = attr("text-anchor", attrs) or "start"
        limit = (W - x - MARGIN) if anchor == "start" else (W - 2 * MARGIN)
        lines = wrap(content, limit, size, char_factor(attrs))
        if len(lines) < 2:
            continue

        step = round(size * 1.3)
        pieces = []
        for i, line in enumerate(lines):
            shifted = Y_RE.sub(f'y="{y + i * step:.0f}"', attrs)
            pieces.append(f"<text{shifted}>{line}</text>")
        out.append(svg[pos:m.start()])
        out.append("".join(pieces))
        pos = m.end()
        wrapped += 1
        max_y = max(max_y, y + (len(lines) - 1) * step)

    out.append(svg[pos:])
    svg = "".join(out)

    newH = H
    if wrapped and max_y + 12 > H:
        newH = int(math.ceil((max_y + 14) / 5.0) * 5)

    # --- pass 2: widen for anything wrapping cannot help ------------------
    over = max((right_extent(m.group(1), m.group(2), root_size)[0]
                for m in TEXT_RE.finditer(svg) if m.group(2).strip()), default=0.0)
    newW = W
    if over + MARGIN > W:
        newW = int(math.ceil((over + MARGIN) / 10.0) * 10)

    if newW == W and newH == H and not wrapped:
        return 0, False, False

    svg = set_canvas(svg, newW, newH)
    if apply_fix:
        path.write_text(svg, encoding="utf-8")
    return wrapped, newH > H, newW > W


def main() -> int:
    apply_fix = "--fix" in sys.argv
    files = sorted(KB.rglob("*.svg"))
    lines = taller = wider = touched = 0
    for p in files:
        w, t, wd = process(p, apply_fix)
        if w or t or wd:
            touched += 1
        lines += w
        taller += 1 if t else 0
        wider += 1 if wd else 0
    verb = "wrapped" if apply_fix else "would wrap"
    print(f"{verb} {lines} lines across {touched} of {len(files)} diagrams — "
          f"{taller} grew taller, {wider} grew wider")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
