#!/usr/bin/env python3
"""Build docs/icon_redesign.html: the ribbon icon redesign (design/icons/SPEC.md) in the faithful
Carbon Pro Neutral app mock, in every ribbon / overflow menu / flyout, and in an old | new atlas.
Lints every new SVG and FAILS (exit 1) on a rule break. Stdlib only.

    python3 tools/icon_redesign/build.py ICONS_JSON [OUT_HTML] [--lint-only]

ICONS_JSON  the CURRENT icons, from tools/ribbon_icon_mockup/dump.dart:
            {"maps": {MAP: {key: svg}}, "singles": {name: svg}}
OUT_HTML    default docs/icon_redesign.html

Reused, not rewritten:
  tools/palette_proposals/build.py     Carbon Pro Neutral tokens (derive_pro), map_icon (= icon_theme.dart _map), contrast
  tools/palette_proposals/template.html  the app mock CSS + JS (rail, browser, tab bar, scenes, dialog)
  tools/ribbon_icon_mockup/build.py    RIBBONS / FLYOUTS / CONS / INTENDED and the band + menu JS

The scope (every in-scope key, its family and concept) is parsed from SPEC.md §11; the palette is
PALETTE below and must agree with SPEC.md §5 (checked).
"""
import importlib.util
import json
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
DESIGN = os.path.join(ROOT, 'design', 'icons')
SPEC = os.path.join(DESIGN, 'SPEC.md')
ARB = os.path.join(ROOT, 'frontend', 'lib', 'l10n', 'app_en.arb')
DEFAULT_OUT = os.path.join(ROOT, 'docs', 'icon_redesign.html')
PRO_ID = 'pro-neutral'


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


PB = load('palette_build', os.path.join(ROOT, 'tools', 'palette_proposals', 'build.py'))
RB = load('ribbon_build', os.path.join(ROOT, 'tools', 'ribbon_icon_mockup', 'build.py'))

# ----------------------------------------------------------------- SPEC §5
# token: (source hex, role, family). role: glyph (stroke or fill, must reach 3:1) | face (fill only)
PALETTE = {
    'INK': ('#E0E0E0', 'glyph', None), 'LINE': ('#ADADAD', 'glyph', None), 'DIM': ('#8F8F8F', 'glyph', None),
    'FA': ('#666666', 'face', None), 'FB': ('#545454', 'face', None), 'FC': ('#424242', 'face', None),
    'ACC': ('#6CABEF', 'glyph', 'ACC'), 'ACCHI': ('#BFDAF8', 'glyph', 'ACC'),
    'AFA': ('#8BBBEE', 'face', 'ACC'), 'AFB': ('#559CE7', 'face', 'ACC'), 'AFC': ('#207CDF', 'face', 'ACC'),
    'AMB': ('#ED8D26', 'glyph', 'AMB'), 'OK': ('#29A35C', 'glyph', 'OK'), 'ERR': ('#E96C67', 'glyph', 'ERR'),
}
BY_HEX = {h.upper(): (k, role, fam) for k, (h, role, fam) in PALETTE.items()}
MIN_CONTRAST = 3.0
MIN_EXTENT = 19.0
STROKES = (1.25, 1.5, 2.0)
ALLOWED_EL = {'svg', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon', 'g'}
ALLOWED_ATTR = {'xmlns', 'viewBox', 'd', 'x', 'y', 'width', 'height', 'rx', 'ry', 'cx', 'cy', 'r', 'x1', 'y1', 'x2',
                'y2', 'points', 'fill', 'stroke', 'stroke-width', 'stroke-linecap', 'stroke-linejoin',
                'stroke-dasharray', 'stroke-dashoffset', 'fill-opacity', 'fill-rule', 'transform'}
FAMILIES = {'A': 'Sketch Create', 'B': 'Sketch Constrain, Modify, Insert, 2D pattern, sketch singles',
            'C': 'Part Create, Modify, Direct', 'D': 'Work features, 3D pattern, view, measure', 'E': 'Assembly'}
MOTIF_EXEMPT_STROKE = {'grid-keylines'}


FACE_STOPS = [h for h, role, fam in PALETTE.values() if role == 'face' and fam == 'ACC']


def _bucket(p, hue):
    return p['rawAccent'] if 175 <= hue < 265 else p['ok'] if 75 <= hue < 175 else p['projRef'] if 18 <= hue < 75 else p['err']


def map_icon_proposed(src, p, a=True, b=True):
    """SPEC §12 Integration: icon_theme.dart _map with (a) hue-less greys and (b) a luminance-capped light band."""
    hue, s, l = PB.hsl_from(src)
    light = not p['_dark']
    if s < 0.12:
        ink_h, ink_s, _ = PB.hsl_from(PB.opaque(p, 'ink'))
        ll = 1 - l if light else l
        return PB.hsl_to(ink_h, 0.0 if (a and ink_s < 0.05) else 0.04, PB.clamp(ll, 0.12, 0.92))
    th, ts, _ = PB.hsl_from(_bucket(p, hue))
    sat = PB.clamp(ts * 0.85 + s * 0.15, 0.25, 0.95)
    if not light:
        ll = PB.clamp(l, 0.32, 0.82)
    elif not b:
        ll = PB.clamp(0.16 + l * 0.30, 0.16, 0.46)
    elif ('#' + src.upper()) in FACE_STOPS:
        ll = 0.36 + l * 0.34                     # volume, outlined by a glyph stroke: exempt from 3:1
    else:
        bg = PB.opaque(p, 'bg')
        lo, hi = 0.0, 1.0                        # cap = lightest L that still gives 3.2:1 on T.bg
        for _ in range(24):
            mid = (lo + hi) / 2
            lo, hi = (mid, hi) if PB.contrast(PB.hsl_to(th, sat, mid), bg) >= 3.2 else (lo, mid)
        ll = 0.22 + l * (lo - 0.22)
    return PB.hsl_to(th, sat, ll)


def palettes():
    v = [x for x in PB.PRO_VARIANTS if x['id'] == PRO_ID][0]
    out = {}
    for mode in ('dark', 'light'):
        pid = '%s-%s' % (PRO_ID, mode)
        out[pid] = PB.derive_pro(v, mode == 'dark', '%s %s' % (v['name'], mode.capitalize()))
    return out


def parse_scope():
    rows = []
    for line in open(SPEC, encoding='utf-8'):
        m = re.match(r'^\| ([A-E]) \| `([\w.]+)` \| (.*) \|\s*$', line)
        if m:
            concept = m.group(3).strip()
            am = re.match(r'^= `([\w.]+)`$', concept)
            rows.append({'fam': m.group(1), 'ref': m.group(2), 'concept': concept.replace('★ ', ''),
                         'ref_star': concept.startswith('★'), 'alias': am.group(1) if am else None})
    return rows


def file_of(ref):
    m, k = ref.split('.', 1)
    return os.path.join(DESIGN, m, k + '.svg')


def ref_of(path):
    rel = os.path.relpath(path, DESIGN).replace(os.sep, '/')
    d, f = rel.split('/', 1) if '/' in rel else ('', rel)
    return d + '.' + f[:-4]


def num(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None



# ------------------------------------------------------------ geometry (overlap lint)
# Flattens SVG shapes to polylines so the lint can tell when a dark-on-light glyph (INK/LINE/DIM) is drawn
# OVER an accent face. On light themes that pair maps to about #201E1E on #1C-#3A blues and vanishes (SPEC §3).
import math

DARK_ON_LIGHT = {'INK', 'LINE', 'DIM'}
ACCENT_FACES = {'AFA', 'AFB', 'AFC'}


def _mat(tr):
    m = [1, 0, 0, 1, 0, 0]
    for fn, args in re.findall(r'(matrix|translate)\(([^)]*)\)', tr or ''):
        a = [float(x) for x in re.split(r'[\s,]+', args.strip()) if x]
        n = a if fn == 'matrix' else [1, 0, 0, 1, a[0], a[1] if len(a) > 1 else 0]
        m = [m[0] * n[0] + m[2] * n[1], m[1] * n[0] + m[3] * n[1], m[0] * n[2] + m[2] * n[3],
             m[1] * n[2] + m[3] * n[3], m[0] * n[4] + m[2] * n[5] + m[4], m[1] * n[4] + m[3] * n[5] + m[5]]
    return m


def _app(m, p):
    return (m[0] * p[0] + m[2] * p[1] + m[4], m[1] * p[0] + m[3] * p[1] + m[5])


def _arc(p0, rx, ry, phi, fa, fs, p1, n=24):
    # SVG elliptical arc -> points (W3C implementation notes F.6.5)
    if rx == 0 or ry == 0:
        return [p1]
    c, s_ = math.cos(math.radians(phi)), math.sin(math.radians(phi))
    dx, dy = (p0[0] - p1[0]) / 2, (p0[1] - p1[1]) / 2
    x1, y1 = c * dx + s_ * dy, -s_ * dx + c * dy
    rx, ry = abs(rx), abs(ry)
    lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lam > 1:
        rx, ry = rx * math.sqrt(lam), ry * math.sqrt(lam)
    num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    k = math.sqrt(max(0, num / den)) * (-1 if fa == fs else 1)
    cx1, cy1 = k * rx * y1 / ry, -k * ry * x1 / rx
    cx, cy = c * cx1 - s_ * cy1 + (p0[0] + p1[0]) / 2, s_ * cx1 + c * cy1 + (p0[1] + p1[1]) / 2
    ang = lambda ux, uy, vx, vy: math.atan2(ux * vy - uy * vx, ux * vx + uy * vy)
    t1 = ang(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
    dt = ang((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
    if not fs and dt > 0:
        dt -= 2 * math.pi
    elif fs and dt < 0:
        dt += 2 * math.pi
    out = []
    for i in range(1, n + 1):
        t = t1 + dt * i / n
        ex, ey = rx * math.cos(t), ry * math.sin(t)
        out.append((c * ex - s_ * ey + cx, s_ * ex + c * ey + cy))
    return out


def _path(d):
    toks = re.findall(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?', d)
    subs, cur, pos, start, cmd, i = [], [], (0.0, 0.0), (0.0, 0.0), None, 0
    last_c = None

    def nums(k):
        nonlocal i
        v = [float(t) for t in toks[i:i + k]]
        i += k
        return v
    while i < len(toks):
        if re.match(r'[A-Za-z]', toks[i]):
            cmd = toks[i]
            i += 1
            if cmd in 'Zz':
                if cur:
                    cur.append(start)
                    subs.append((cur, True))
                cur, pos = [], start
                continue
        rel = cmd.islower()
        C_ = cmd.upper()
        ox, oy = pos if rel else (0, 0)
        if C_ == 'M':
            x, y = nums(2)
            if cur:
                subs.append((cur, False))
            pos = start = (x + ox, y + oy)
            cur = [pos]
            cmd = 'l' if rel else 'L'
        elif C_ == 'L':
            x, y = nums(2)
            pos = (x + ox, y + oy)
            cur.append(pos)
        elif C_ == 'H':
            x, = nums(1)
            pos = (x + ox, pos[1])
            cur.append(pos)
        elif C_ == 'V':
            y, = nums(1)
            pos = (pos[0], y + (pos[1] if rel else 0))
            cur.append(pos)
        elif C_ in 'QTCS':
            if C_ == 'Q':
                a = nums(4)
                c1, p1 = (a[0] + ox, a[1] + oy), (a[2] + ox, a[3] + oy)
                ctrl = [c1, c1]
            elif C_ == 'T':
                a = nums(2)
                c1 = (2 * pos[0] - last_c[0], 2 * pos[1] - last_c[1]) if last_c else pos
                p1 = (a[0] + ox, a[1] + oy)
                ctrl = [c1, c1]
            elif C_ == 'C':
                a = nums(6)
                ctrl = [(a[0] + ox, a[1] + oy), (a[2] + ox, a[3] + oy)]
                p1 = (a[4] + ox, a[5] + oy)
            else:
                a = nums(4)
                c1 = (2 * pos[0] - last_c[0], 2 * pos[1] - last_c[1]) if last_c else pos
                ctrl = [c1, (a[0] + ox, a[1] + oy)]
                p1 = (a[2] + ox, a[3] + oy)
            p0 = pos
            for k in range(1, 17):
                t = k / 16
                if C_ in 'QT':
                    q = ctrl[0]
                    pt = ((1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * q[0] + t * t * p1[0],
                          (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * q[1] + t * t * p1[1])
                else:
                    a1, a2 = ctrl
                    pt = tuple((1 - t) ** 3 * p0[j] + 3 * (1 - t) ** 2 * t * a1[j] + 3 * (1 - t) * t * t * a2[j] + t ** 3 * p1[j] for j in (0, 1))
                cur.append(pt)
            last_c = ctrl[-1] if C_ in 'CS' else ctrl[0]
            pos = p1
            continue
        elif C_ == 'A':
            a = nums(7)
            p1 = (a[5] + ox, a[6] + oy)
            cur += _arc(pos, a[0], a[1], a[2], int(a[3]), int(a[4]), p1)
            pos = p1
        last_c = None
    if cur:
        subs.append((cur, False))
    return subs


def shape_polys(el, tag, m):
    """-> list of (points, closed) in root coordinates."""
    f = lambda k, d=0.0: float(el.get(k, d))
    if tag == 'path':
        subs = _path(el.get('d', ''))
    elif tag == 'rect':
        x, y, w, h = f('x'), f('y'), f('width'), f('height')
        subs = [([(x, y), (x + w, y), (x + w, y + h), (x, y + h), (x, y)], True)]
    elif tag in ('circle', 'ellipse'):
        cx, cy = f('cx'), f('cy')
        rx = f('r') if tag == 'circle' else f('rx')
        ry = f('r') if tag == 'circle' else f('ry')
        pts = [(cx + rx * math.cos(2 * math.pi * i / 48), cy + ry * math.sin(2 * math.pi * i / 48)) for i in range(49)]
        subs = [(pts, True)]
    elif tag == 'line':
        subs = [([(f('x1'), f('y1')), (f('x2'), f('y2'))], False)]
    elif tag in ('polyline', 'polygon'):
        v = [float(x) for x in re.split(r'[\s,]+', el.get('points', '').strip()) if x]
        pts = list(zip(v[::2], v[1::2]))
        subs = [(pts + ([pts[0]] if tag == 'polygon' else []), tag == 'polygon')]
    else:
        subs = []
    return [([_app(m, p) for p in pts], cl) for pts, cl in subs]


def _inside(pt, polys):
    x, y, n = pt[0], pt[1], 0
    for pts, _ in polys:
        for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
            if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                n += 1
    return n % 2 == 1


def _dist(pt, polys):
    best = 1e9
    for pts, _ in polys:
        for a, b in zip(pts, pts[1:] + pts[:1]):
            vx, vy = b[0] - a[0], b[1] - a[1]
            L2 = vx * vx + vy * vy
            t = 0 if L2 == 0 else max(0, min(1, ((pt[0] - a[0]) * vx + (pt[1] - a[1]) * vy) / L2))
            best = min(best, math.hypot(pt[0] - a[0] - t * vx, pt[1] - a[1] - t * vy))
    return best


def _samples(polys, step=0.35):
    out = []
    for pts, _ in polys:
        for a, b in zip(pts, pts[1:]):
            n = max(1, int(math.hypot(b[0] - a[0], b[1] - a[1]) / step))
            out += [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]
    return out


def overlap_errors(drawn):
    """drawn: [(tag, polys, fill_token, stroke_token, stroke_width, tinted)] in paint order."""
    errs = []
    faces = []
    for tag, polys, ft, st, sw, tint in drawn:
        dark_stroke = st in DARK_ON_LIGHT
        dark_fill = ft in DARK_ON_LIGHT and not tint
        if (dark_stroke or dark_fill) and faces:
            margin = (sw / 2 if dark_stroke else 0) + 0.35
            pts = _samples(polys)
            for fpolys, fname in faces:
                hit = [p for p in pts if _inside(p, fpolys) and _dist(p, fpolys) > margin]
                if hit:
                    errs.append('%s <%s> drawn over accent face %s near (%.1f, %.1f): dark-on-accent vanishes on light themes (SPEC §3)'
                                % (st if dark_stroke else ft, tag, fname, hit[0][0], hit[0][1]))
                    break
        if ft in ACCENT_FACES and not tint:
            faces.append((polys, ft))
    return errs


# ------------------------------------------------------------------- lint
def lint_svg(name, src, pals, motif=False):
    """-> (errors, metrics). metrics: min glyph contrast on the rail per theme, chromatic families used."""
    errs = []
    E = lambda msg: errs.append('%s: %s' % (name, msg))
    if re.search(r'<\s*(text|tspan)\b', src) or 'font-' in src:
        E('<text>/font attributes are banned; letters are paths')
    for h in re.findall(r'#[0-9A-Fa-f]+\b', src):
        if len(h) != 7:
            E('colour %s is not 6-digit #RRGGBB' % h)
        elif h.upper() not in BY_HEX:
            E('colour %s is not in the SPEC palette' % h)
    if re.search(r'rgba?\(|hsla?\(|currentColor', src):
        E('rgb()/hsl()/currentColor are banned')
    try:
        root = ET.fromstring(src)
    except ET.ParseError as e:
        E('not well-formed XML: %s' % e)
        return errs, None
    tag = lambda el: el.tag.split('}')[-1]
    if tag(root) != 'svg':
        E('root is not <svg>')
    if root.get('viewBox') != '0 0 28 28':
        E('viewBox must be "0 0 28 28" (got %r)' % root.get('viewBox'))
    if root.get('width') or root.get('height'):
        E('root must not set width/height')
    fams, glyphs = set(), 0
    mins = {'dark': 99.0, 'light': 99.0}
    bgs = {pid: PB.opaque(p, 'bg') for pid, p in pals.items()}

    drawn = []

    def walk(el, inh, m):
        nonlocal glyphs
        t = tag(el)
        if t not in ALLOWED_EL:
            E('element <%s> is banned' % t)
        for a in el.attrib:
            if a not in ALLOWED_ATTR:
                E('attribute %s on <%s> is banned' % (a, t))
        tr = el.get('transform')
        if tr and not re.fullmatch(r'\s*((matrix|translate)\([^)]*\)\s*)+', tr):
            E('transform %r: only matrix()/translate()' % tr)
        cur = dict(inh)
        if tr:
            m = [a * 1 for a in m]
            n_ = _mat(tr)
            m = [m[0] * n_[0] + m[2] * n_[1], m[1] * n_[0] + m[3] * n_[1], m[0] * n_[2] + m[2] * n_[3],
                 m[1] * n_[2] + m[3] * n_[3], m[0] * n_[4] + m[2] * n_[5] + m[4], m[1] * n_[4] + m[3] * n_[5] + m[5]]
        for a in ('fill', 'stroke', 'stroke-width', 'fill-opacity', 'stroke-dasharray', 'stroke-linecap'):
            if el.get(a) is not None:
                cur[a] = el.get(a)
        for a in ('fill', 'stroke'):
            v = el.get(a)
            if v is not None and v != 'none' and not re.fullmatch(r'#[0-9A-Fa-f]{6}', v):
                E('%s=%r: only none or a palette #RRGGBB' % (a, v))
        fo = el.get('fill-opacity')
        if fo is not None and not (0.25 <= (num(fo) or -1) <= 0.35):
            E('fill-opacity %s outside .25-.35 (tints only)' % fo)
        if t != 'svg' and t != 'g':
            stroke, fill = cur.get('stroke', 'none'), cur.get('fill', 'none')
            sw = num(cur.get('stroke-width', '1'))
            tok = lambda v: (BY_HEX.get(v.upper()) or (None,))[0] if v != 'none' else None
            try:
                drawn.append((t, shape_polys(el, t, m), tok(fill), tok(stroke), sw or 1, bool(cur.get('fill-opacity'))))
            except (ValueError, IndexError, ZeroDivisionError) as ex:
                E('<%s> geometry could not be parsed (%s)' % (t, ex))
            if stroke != 'none':
                k = BY_HEX.get(stroke.upper())
                rounding = fill != 'none' and fill.upper() == stroke.upper() and sw is not None and sw <= 1.0
                if not motif or name.split('/')[-1][:-4] not in MOTIF_EXEMPT_STROKE:
                    if sw is None or (sw not in STROKES and not rounding):
                        E('<%s> stroke-width %s: use 1.25 / 1.5 / 2.0 (1.0 only to round a same-colour fill)' % (t, cur.get('stroke-width', '1 (default)')))
                if cur.get('stroke-dasharray') and cur.get('stroke-linecap') != 'butt':
                    E('<%s> dashed stroke needs stroke-linecap="butt"' % t)
                if k and k[1] == 'face':
                    E('<%s> face stop %s used as a stroke' % (t, k[0]))
            for paint, is_fill in ((stroke, False), (fill, True)):
                if paint == 'none':
                    continue
                k = BY_HEX.get(paint.upper())
                if not k:
                    continue
                if k[2]:
                    fams.add(k[2])
                if k[1] == 'face' or (is_fill and cur.get('fill-opacity')):
                    continue
                glyphs += 1
                for pid, p in pals.items():
                    mode = 'dark' if p['_dark'] else 'light'
                    for fn in (PB.map_icon, map_icon_proposed):
                        c = PB.contrast(fn(paint[1:], p), bgs[pid])
                        mins[mode] = min(mins[mode], c)
        for ch in el:
            walk(ch, cur, m)

    walk(root, {'fill': root.get('fill', 'black')}, [1, 0, 0, 1, 0, 0])
    for e in overlap_errors(drawn):
        E(e)
    # SPEC §2 optical size: the glyph fills its keyline (major extent >= 19u of the 24u live area)
    xs, ys = [], []
    for _, polys, ft, st, sw, _ in drawn:
        hw = (sw / 2) if st else 0
        for pts, _ in polys:
            for x, y in pts:
                xs += [x - hw, x + hw]
                ys += [y - hw, y + hw]
    if xs and not motif:
        w, h = max(xs) - min(xs), max(ys) - min(ys)
        if max(w, h) < MIN_EXTENT:
            E('glyph extent %.1f x %.1f u: too small, it must fill its keyline (major extent >= %gu, SPEC §2)' % (w, h, MIN_EXTENT))
        if min(xs) < 0.75 or min(ys) < 0.75 or max(xs) > 27.25 or max(ys) > 27.25:
            E('glyph reaches %.2f..%.2f x %.2f..%.2f: nothing may cross 0.75 / 27.25 (SPEC §2)' % (min(xs), max(xs), min(ys), max(ys)))
    if root.get('fill') not in ('none',):
        E('root must set fill="none"')
    if root.get('stroke-linecap') != 'round' or root.get('stroke-linejoin') != 'round':
        E('root must set stroke-linecap="round" stroke-linejoin="round"')
    if not glyphs:
        E('no glyph-role colour (needs INK/LINE/DIM/ACC/ACCHI/AMB/OK/ERR)')
    sec = fams - {'ACC'}
    if len(sec) > 1:
        E('two secondary families %s: max 1 accent + 1 secondary' % sorted(sec))
    for mode, c in mins.items():
        if glyphs and c < MIN_CONTRAST:
            E('mapped glyph contrast %.2f < %.1f on the %s rail' % (c, MIN_CONTRAST, mode))
    return errs, {'dark': round(mins['dark'], 2), 'light': round(mins['light'], 2), 'fams': sorted(fams)}


def lint_all(scope, pals):
    errs, warns, metrics, new = [], [], {}, {}
    scope_refs = {e['ref'] for e in scope}
    files = motifs = 0
    for dp, _, fs in os.walk(DESIGN):
        for f in sorted(fs):
            if not f.endswith('.svg'):
                continue
            path = os.path.join(dp, f)
            rel = os.path.relpath(path, DESIGN).replace(os.sep, '/')
            src = open(path, encoding='utf-8').read().strip()
            files += 1
            if rel.startswith('_motifs/'):
                motifs += 1
                e, _ = lint_svg(rel, src, pals, motif=True)
                errs += e
                continue
            sm = f.endswith('.sm.svg')
            ref = ref_of(path[:-7] + '.svg') if sm else ref_of(path)
            if ref not in scope_refs:
                errs.append('%s: not in the SPEC §11 family table (expected design/icons/<MAP>/<key>.svg)' % rel)
                continue
            e, m = lint_svg(rel, src, pals)
            errs += e
            if sm:
                new[ref + '@sm'] = src
            else:
                new[ref] = src
                metrics[ref] = m
    # aliases and duplicates
    alias = {e['ref']: e['alias'] for e in scope if e['alias']}
    for a, t in alias.items():
        if a in new and t in new and new[a] != new[t]:
            errs.append('%s: alias of %s but not byte-identical' % (a, t))
        if a in new and t not in new:
            errs.append('%s: alias drawn before its target %s' % (a, t))
    seen = {}
    for ref, s in new.items():
        if ref.endswith('@sm'):
            continue
        if s in seen and alias.get(ref) != seen[s] and alias.get(seen[s]) != ref:
            errs.append('%s: identical drawing to %s (not a declared alias)' % (ref, seen[s]))
        seen.setdefault(s, ref)
    # SPEC palette agrees with PALETTE
    spec = open(SPEC, encoding='utf-8').read()
    for k, (h, _, _) in PALETTE.items():
        if h not in spec:
            errs.append('SPEC.md §5 does not list %s %s' % (k, h))
    # palette-level contrast (all glyph roles, rail/panel/fly)
    for k, (h, role, _) in PALETTE.items():
        if role != 'glyph':
            continue
        for pid, p in pals.items():
            for surf in ('bg', 'panel', 'fly'):
                c = PB.contrast(PB.map_icon(h[1:], p), PB.opaque(p, surf))
                if c < MIN_CONTRAST:
                    (errs if surf == 'bg' else warns).append('palette %s on %s %s: %.2f' % (k, pid, surf, c))
    return errs, warns, metrics, new, files, motifs


# ------------------------------------------------------------------ splice
def between(s, a, b, include_a=False):
    i = s.find(a)
    j = s.find(b, i + len(a))
    if i < 0 or j < 0:
        sys.exit('template marker not found: %r .. %r (did the reused template change?)' % (a, b))
    return s[i if include_a else i + len(a):j]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    if not args:
        sys.exit(__doc__)
    lint_only = '--lint-only' in sys.argv
    icons = json.load(open(args[0], encoding='utf-8'))
    out = args[1] if len(args) > 1 else DEFAULT_OUT
    pals = palettes()
    scope = parse_scope()
    if len(scope) != len({e['ref'] for e in scope}):
        sys.exit('SPEC §11 lists a key twice')
    old = {}
    for m, v in icons['maps'].items():
        for k, s in v.items():
            old['%s.%s' % (m, k)] = s
    old.update(icons['singles'])
    # every scope key must exist today, unless it is one of the new ones
    new_keys = {e['ref'] for e in scope if e['ref'].startswith('DE.') or e['ref'] == 'IN.params'}
    for e in scope:
        r = e['ref']
        today = old.get(r) or (old.get(r[7:]) if r.startswith('single.') else None)
        if not today and r not in new_keys:
            sys.exit('SPEC §11 key %s does not exist in svg_icons.dart' % r)

    errs, warns, metrics, new, nfiles, nmotifs = lint_all(scope, pals)
    print('lint: %d files (%d motifs), %d error(s), %d warning(s); %d/%d keys drawn' % (
        nfiles, nmotifs, len(errs), len(warns), len([e for e in scope if e['ref'] in new]), len(scope)))
    for e in errs:
        print('  ERROR ' + e)
    for w in warns:
        print('  warn  ' + w)
    if lint_only:
        sys.exit(1 if errs else 0)

    # flyout rows -> new refs
    fly_new = {}
    for items in RB.FLYOUTS.values():
        for key, _, _ in items:
            if key in RB.INTENDED:
                fly_new[key] = RB.INTENDED[key]
            elif key.startswith('de'):
                fly_new[key] = 'DE.' + key
            elif key in icons['maps']['IC']:
                fly_new[key] = 'IC.' + key
            else:
                fly_new[key] = 'PL.' + key
    arb = json.load(open(ARB, encoding='utf-8'))
    keys = RB.collect_label_keys()
    labels = {k: arb[k] for k in keys if isinstance(arb.get(k), str)}
    rbdata = {'ribbons': RB.RIBBONS, 'flyouts': RB.FLYOUTS, 'cons': RB.CONS, 'intended': RB.INTENDED,
              'labels': labels, 'flyNew': fly_new,
              'icons': {'maps': {m: {k: 1 for k in icons['maps'][m]} for m in ('IC', 'PL')}}}
    pal_rows = []
    for k, (h, role, _) in PALETTE.items():
        row = {'name': k, 'src': h, 'role': role}
        for pid, p in pals.items():
            mode = 'dark' if p['_dark'] else 'light'
            mh = PB.map_icon(h[1:], p)
            row[mode] = mh
            row['c' + mode[0]] = round(PB.contrast(mh, PB.opaque(p, 'bg')), 2)
            if not p['_dark']:
                pr = map_icon_proposed(h[1:], p)
                row['lightP'] = pr
                row['clP'] = round(PB.contrast(pr, PB.opaque(p, 'bg')), 2)
        pal_rows.append(row)
    fields = [k for k in pals['%s-dark' % PRO_ID] if not k.startswith('_')]
    data = {
        'pals': pals, 'fields': fields, 'pid': {'dark': '%s-dark' % PRO_ID, 'light': '%s-light' % PRO_ID},
        'old': old, 'nu': new, 'scope': [{k: e[k] for k in ('fam', 'ref', 'concept', 'alias')} for e in scope],
        'scopeSet': {e['ref']: 1 for e in scope}, 'families': FAMILIES, 'metrics': metrics,
        'lint': {'errors': errs, 'warnings': warns, 'files': nfiles, 'motifs': nmotifs},
        'palette': pal_rows, 'rb': rbdata, 'faceStops': [h[1:].upper() for h in FACE_STOPS],
    }
    ptpl = open(os.path.join(ROOT, 'tools', 'palette_proposals', 'template.html'), encoding='utf-8').read()
    pal_css = between(ptpl, '<style>', '</style>')
    pal_js = between(ptpl, '// ------------------------------------------------------------ colour helpers',
                     '// ---------------------------------------------------------------- viewer UI', True)
    rb_css = between(RB.TEMPLATE, '/* ---- mockup palette (set from JS) ---- */', '/* atlas */', True)
    rb_js = between(RB.TEMPLATE, 'const esc = s =>', '// ---------------------------------------------------------------- render', True)
    tpl = open(os.path.join(HERE, 'template.html'), encoding='utf-8').read()
    blob = json.dumps(data, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
    html = (tpl.replace('/*__PALETTE_CSS__*/', pal_css).replace('/*__RIBBON_CSS__*/', rb_css)
            .replace('/*__PALETTE_JS__*/', pal_js).replace('/*__RIBBON_JS__*/', rb_js)
            .replace('/*__DATA__*/null', blob))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, 'w', encoding='utf-8') as f:
        f.write(html)
    print('wrote %s (%d bytes)' % (out, len(html)))
    if errs:
        sys.exit('lint failed: %d error(s) (the page was written so the failures can be inspected)' % len(errs))


if __name__ == '__main__':
    main()
