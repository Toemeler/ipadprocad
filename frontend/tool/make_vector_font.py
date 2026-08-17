#!/usr/bin/env python3
"""Turns a TrueType font into the compact outline table lib/vector_font.dart
reads (M220).

A sketch text has to BE geometry — closed contours the DXF carries and the
kernel can extrude — so the app needs glyph OUTLINES, not a rasteriser.
dart:ui has no API for them (a TextPainter paints pixels and hands back
nothing but a size), so the outlines are extracted here, once, and shipped as
data.

What is emitted is the `glyf` outline of every requested codepoint, in 1/1000
em units, as a sequence of move/line/quadratic commands — exactly what
TrueType stores, with the implied on-curve midpoints made explicit so the
Dart decoder needs no special cases. Composite glyphs (a-umlaut = a +
dieresis) are flattened into their components' contours.

Usage:
    python3 tool/make_vector_font.py > lib/vector_font_data.dart

The fonts are read from the paths in FONTS below; both are DejaVu, whose
licence (Bitstream Vera + public-domain DejaVu changes) allows exactly this:
modify, embed and redistribute, as long as the result is not called Bitstream
or Vera and the notice travels with it. Hence the CAD names, and hence the
notice reproduced in the generated file.
"""

import struct
import sys

FONTS = [
    ('CAD Sans', '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'),
    ('CAD Mono', '/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'),
    ('CAD Serif', '/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf'),
]

# ASCII + Latin-1 (the German app's umlauts and sharp s live here) + the few
# symbols a drawing note actually uses.
CODEPOINTS = (
    list(range(0x20, 0x7F))
    + list(range(0xA0, 0x100))
    + [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x20AC,
       0x2205, 0x2300, 0x00D8]
)

EM = 1000  # everything is emitted in 1/1000 em


def tables(buf):
    n = struct.unpack('>H', buf[4:6])[0]
    out = {}
    for i in range(n):
        o = 12 + 16 * i
        tag = buf[o:o + 4].decode('latin-1')
        off, ln = struct.unpack('>II', buf[o + 8:o + 16])
        out[tag] = (off, ln)
    return out


def read_cmap(buf, off):
    """Unicode -> glyph id, from a format 4 or format 12 subtable."""
    n = struct.unpack('>H', buf[off + 2:off + 4])[0]
    best = None
    for i in range(n):
        p = off + 4 + 8 * i
        pid, eid, sub = struct.unpack('>HHI', buf[p:p + 8])
        if (pid, eid) in ((3, 10), (3, 1), (0, 3), (0, 4), (0, 6)):
            fmt = struct.unpack('>H', buf[off + sub:off + sub + 2])[0]
            if fmt in (4, 12):
                # prefer the wider table
                rank = 2 if fmt == 12 else 1
                if best is None or rank > best[0]:
                    best = (rank, off + sub, fmt)
    if best is None:
        raise SystemExit('no usable cmap subtable')
    _, p, fmt = best
    m = {}
    if fmt == 4:
        segx2 = struct.unpack('>H', buf[p + 6:p + 8])[0]
        seg = segx2 // 2
        ends = struct.unpack('>%dH' % seg, buf[p + 14:p + 14 + segx2])
        q = p + 16 + segx2
        starts = struct.unpack('>%dH' % seg, buf[q:q + segx2])
        q += segx2
        deltas = struct.unpack('>%dh' % seg, buf[q:q + segx2])
        q += segx2
        ro_at = q
        ranges = struct.unpack('>%dH' % seg, buf[q:q + segx2])
        for i in range(seg):
            for c in range(starts[i], min(ends[i], 0xFFFF) + 1):
                if ranges[i] == 0:
                    g = (c + deltas[i]) & 0xFFFF
                else:
                    a = ro_at + 2 * i + ranges[i] + 2 * (c - starts[i])
                    g = struct.unpack('>H', buf[a:a + 2])[0]
                    if g:
                        g = (g + deltas[i]) & 0xFFFF
                if g:
                    m[c] = g
    else:
        ngroups = struct.unpack('>I', buf[p + 12:p + 16])[0]
        for i in range(ngroups):
            a = p + 16 + 12 * i
            s, e, gs = struct.unpack('>III', buf[a:a + 12])
            for c in range(s, e + 1):
                m[c] = gs + (c - s)
    return m


class Font:
    def __init__(self, path):
        self.buf = open(path, 'rb').read()
        self.t = tables(self.buf)
        ho = self.t['head'][0]
        self.upem = struct.unpack('>H', self.buf[ho + 18:ho + 20])[0]
        self.long_loca = struct.unpack('>h', self.buf[ho + 50:ho + 52])[0] == 1
        mo = self.t['maxp'][0]
        self.nglyphs = struct.unpack('>H', self.buf[mo + 4:mo + 6])[0]
        hh = self.t['hhea'][0]
        self.n_hmetrics = struct.unpack('>H', self.buf[hh + 34:hh + 36])[0]
        oo = self.t['OS/2'][0]
        self.asc, self.desc, self.gap = struct.unpack(
            '>hhh', self.buf[oo + 68:oo + 74])
        self.cmap = read_cmap(self.buf, self.t['cmap'][0])
        self.loca = self._loca()

    def _loca(self):
        off, _ = self.t['loca']
        n = self.nglyphs + 1
        if self.long_loca:
            return struct.unpack('>%dI' % n, self.buf[off:off + 4 * n])
        return [2 * v for v in
                struct.unpack('>%dH' % n, self.buf[off:off + 2 * n])]

    def advance(self, gid):
        off = self.t['hmtx'][0]
        i = min(gid, self.n_hmetrics - 1)
        return struct.unpack('>H', self.buf[off + 4 * i:off + 4 * i + 2])[0]

    def contours(self, gid, depth=0):
        """[[(x, y, on_curve), ...], ...] in font units."""
        if gid >= self.nglyphs or depth > 4:
            return []
        go = self.t['glyf'][0]
        start, end = self.loca[gid], self.loca[gid + 1]
        if end <= start:
            return []  # blank glyph (space)
        p = go + start
        ncont = struct.unpack('>h', self.buf[p:p + 2])[0]
        p += 10
        if ncont < 0:
            return self._composite(p, depth)
        ends = struct.unpack('>%dH' % ncont, self.buf[p:p + 2 * ncont])
        p += 2 * ncont
        ilen = struct.unpack('>H', self.buf[p:p + 2])[0]
        p += 2 + ilen
        npts = ends[-1] + 1
        flags = []
        while len(flags) < npts:
            fl = self.buf[p]
            p += 1
            flags.append(fl)
            if fl & 8:
                rep = self.buf[p]
                p += 1
                flags.extend([fl] * rep)
        flags = flags[:npts]
        xs, v = [], 0
        for fl in flags:
            if fl & 2:
                d = self.buf[p]
                p += 1
                v += d if fl & 16 else -d
            elif not fl & 16:
                v += struct.unpack('>h', self.buf[p:p + 2])[0]
                p += 2
            xs.append(v)
        ys, v = [], 0
        for fl in flags:
            if fl & 4:
                d = self.buf[p]
                p += 1
                v += d if fl & 32 else -d
            elif not fl & 32:
                v += struct.unpack('>h', self.buf[p:p + 2])[0]
                p += 2
            ys.append(v)
        out, s = [], 0
        for e in ends:
            out.append([(xs[i], ys[i], bool(flags[i] & 1))
                        for i in range(s, e + 1)])
            s = e + 1
        return [c for c in out if len(c) >= 2]

    def _composite(self, p, depth):
        out = []
        while True:
            flags, gi = struct.unpack('>HH', self.buf[p:p + 4])
            p += 4
            if flags & 1:  # ARG_1_AND_2_ARE_WORDS
                a1, a2 = struct.unpack('>hh', self.buf[p:p + 4])
                p += 4
            else:
                a1, a2 = struct.unpack('>bb', self.buf[p:p + 2])
                p += 2
            sx = sy = 1.0
            s01 = s10 = 0.0
            if flags & 8:  # WE_HAVE_A_SCALE
                sx = sy = f2dot14(self.buf, p)
                p += 2
            elif flags & 0x40:  # X_AND_Y_SCALE
                sx, sy = f2dot14(self.buf, p), f2dot14(self.buf, p + 2)
                p += 4
            elif flags & 0x80:  # TWO_BY_TWO
                sx, s01 = f2dot14(self.buf, p), f2dot14(self.buf, p + 2)
                s10, sy = f2dot14(self.buf, p + 4), f2dot14(self.buf, p + 6)
                p += 8
            dx, dy = (a1, a2) if flags & 2 else (0, 0)  # ARGS_ARE_XY_VALUES
            for c in self.contours(gi, depth + 1):
                out.append([(round(x * sx + y * s10 + dx),
                             round(x * s01 + y * sy + dy), on)
                            for (x, y, on) in c])
            if not flags & 0x20:  # MORE_COMPONENTS
                break
        return out


def f2dot14(buf, p):
    return struct.unpack('>h', buf[p:p + 2])[0] / 16384.0


def encode(font, gid, scale):
    """One glyph as 'M x y L x y Q cx cy x y ... Z' in 1/1000 em."""
    cmds = []
    for c in font.contours(gid):
        pts = [(round(x * scale), round(y * scale), on) for (x, y, on) in c]
        # start on an on-curve point; if there is none, the implied midpoint
        # between the first two off-curve points opens the contour
        si = next((i for i, p in enumerate(pts) if p[2]), None)
        if si is None:
            x0 = (pts[0][0] + pts[-1][0]) // 2
            y0 = (pts[0][1] + pts[-1][1]) // 2
            pts = [(x0, y0, True)] + pts
            si = 0
        pts = pts[si:] + pts[:si]
        cmds.append('M %d %d' % (pts[0][0], pts[0][1]))
        i, n = 1, len(pts)
        cur = (pts[0][0], pts[0][1])
        while i <= n:
            px, py, on = pts[i % n]
            if on:
                cmds.append('L %d %d' % (px, py))
                cur = (px, py)
                i += 1
                continue
            nx, ny, non = pts[(i + 1) % n]
            if not non:  # implied on-curve midpoint between two controls
                nx, ny = (px + nx) // 2, (py + ny) // 2
                cmds.append('Q %d %d %d %d' % (px, py, nx, ny))
                cur = (nx, ny)
                i += 1
            else:
                cmds.append('Q %d %d %d %d' % (px, py, nx, ny))
                cur = (nx, ny)
                i += 2
        cmds.append('Z')
    return ' '.join(cmds)


def main():
    out = []
    out.append('''// GENERATED by tool/make_vector_font.py — do not edit by hand.
//
// M220 — the outline data behind lib/vector_font.dart: every glyph as
// move/line/quadratic commands in 1/1000 em units, y up, origin on the
// baseline at the left side bearing.
//
// Derived from the DejaVu fonts and renamed as their licence requires:
//
//   Copyright (c) 2003 by Bitstream, Inc. All Rights Reserved.
//   Bitstream Vera is a trademark of Bitstream, Inc.
//   DejaVu changes are in public domain.
//
//   Permission is hereby granted, free of charge, to any person obtaining a
//   copy of the fonts accompanying this license ("Fonts") and associated
//   documentation files (the "Font Software"), to reproduce and distribute
//   the Font Software, including without limitation the rights to use, copy,
//   merge, publish, distribute, and/or sell copies of the Font Software, and
//   to permit persons to whom the Font Software is furnished to do so,
//   subject to the following conditions: the above copyright and trademark
//   notices and this permission notice shall be included in all copies of one
//   or more of the Font Software typefaces; the Font Software may be
//   modified, altered, or added to, and in particular the designs of glyphs
//   or characters in the Fonts may be modified and additional glyphs or
//   characters may be added to the Fonts, only if the fonts are renamed to
//   names not containing either the words "Bitstream" or the word "Vera".
//
//   THE FONT SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND.
//
// Each entry is "<codepoint> <advance> <path>"; see VectorFont.parse.
''')
    for name, path in FONTS:
        f = Font(path)
        scale = EM / f.upem
        cap = 0
        hgid = f.cmap.get(ord('H'))
        if hgid:
            for c in f.contours(hgid):
                for (_, y, _) in c:
                    cap = max(cap, round(y * scale))
        xh = 0
        xgid = f.cmap.get(ord('x'))
        if xgid:
            for c in f.contours(xgid):
                for (_, y, _) in c:
                    xh = max(xh, round(y * scale))
        lines = []
        for cp in CODEPOINTS:
            gid = f.cmap.get(cp)
            if not gid:
                continue
            adv = round(f.advance(gid) * scale)
            lines.append('%d %d %s' % (cp, adv, encode(f, gid, scale)))
        ident = '_' + name.lower().replace(' ', '')
        out.append("const %s = '''%s''';\n" % (
            ident + 'Head',
            '%d %d %d %d %d' % (round(f.asc * scale), round(f.desc * scale),
                                round(f.gap * scale), cap, xh)))
        out.append("const %s = r'''\n%s\n''';\n" % (ident, '\n'.join(lines)))
    out.append('''/// name -> "<ascent> <descent> <lineGap> <capHeight> <xHeight>"
const Map<String, String> kVectorFontHeads = {
%s};

/// name -> the glyph table, one "<codepoint> <advance> <path>" per line.
const Map<String, String> kVectorFontGlyphs = {
%s};
''' % (
        ''.join("  '%s': _%sHead,\n" % (n, n.lower().replace(' ', ''))
                for n, _ in FONTS),
        ''.join("  '%s': _%s,\n" % (n, n.lower().replace(' ', ''))
                for n, _ in FONTS)))
    sys.stdout.write('\n'.join(out))


if __name__ == '__main__':
    main()
