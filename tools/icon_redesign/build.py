#!/usr/bin/env python3
"""Build docs/icon_redesign.html: the ribbon icon system v2 "Modern Crisp" (design/icons/SPEC.md) in the
faithful Carbon Pro Neutral app mock, in every ribbon / overflow menu / flyout, and in an old | new atlas.
Lints every v2 SVG and FAILS (exit 1) on a rule break. Stdlib only.

    python3 tools/icon_redesign/build.py ICONS_JSON [OUT_HTML] [--lint-only]

ICONS_JSON  the CURRENT icons, from tools/ribbon_icon_mockup/dump.dart:
            {"maps": {MAP: {key: svg}}, "singles": {name: svg}}
OUT_HTML    default docs/icon_redesign.html

Sources of truth
  tools/icon_redesign/lib/crisp.py     the v2 palette (flat inks), the material stops, stroke widths
  design/icons/SPEC.md §11             the scope (every in-scope key, family, concept)
  design/icons/SUPERSEDED.txt          old-style (v1) files, by content hash: ignored while unchanged
Reused, not rewritten:
  tools/palette_proposals/build.py     Carbon Pro Neutral tokens (derive_pro), map_icon (= shipping _map), contrast
  tools/palette_proposals/template.html  the app mock CSS + JS (rail, browser, tab bar, scenes, dialog)
  tools/ribbon_icon_mockup/build.py    RIBBONS / FLYOUTS / CONS / INTENDED and the band + menu JS
"""
import hashlib
import importlib.util
import json
import math
import os
import re
import sys
import xml.etree.ElementTree as ET

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..'))
DESIGN = os.path.join(ROOT, 'design', 'icons')
SPEC = os.path.join(DESIGN, 'SPEC.md')
SUPERSEDED = os.path.join(DESIGN, 'SUPERSEDED.txt')
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
CR = load('crisp', os.path.join(HERE, 'lib', 'crisp.py'))

# ----------------------------------------------------------------- SPEC v2 §5 palette (from lib/crisp.py)
FLAT = {h.upper(): k for k, h in CR.PALETTE.items()}            # INK SEC ACC: flat ink, through _map
STATUS = {h.upper(): k for k, h in CR.STATUS.items()}           # ERR: the status exception only
CONSTRAINT = {h.upper(): k for k, h in CR.CONSTRAINT.items()}   # CON: the constraint red, CN constraints only
STOPS = {h.upper() for h in CR.STOPS}                            # material stops (+ the hairline white)
HIGHLIGHT = CR.HIGHLIGHT.upper()
PANE = {h.upper() for m in CR.MATERIAL for h in CR.mat_stops(m, 'pane')}
# SPEC v2 §5.4: red is allowed in exactly these keys (a sick / failed state), as flat ERR ink; green and
# amber in none.
STATUS_RED = {'AS.showsick'}
# SPEC v2 §5.5: the constraint red (flat CON ink) is allowed in exactly the geometric-constraint icons, and they
# may use no other red. Dimensions (CN.dim, CN.autodim) are not constraints: they stay ACC.
CONSTRAINT_RED = {'CN.coincident', 'CN.collinear', 'CN.concentric', 'CN.lock', 'CN.parallel', 'CN.perp',
                  'CN.horiz', 'CN.vert', 'CN.tangent', 'CN.symmetric', 'CN.equal', 'CN.smooth',
                  'CN.showcons', 'CN.conset'}
MIN_CONTRAST = 3.0
MIN_EXTENT = 19.0
WIDTHS = set(CR.ALLOWED_WIDTHS)
ALLOWED_EL = {'svg', 'defs', 'linearGradient', 'stop', 'path', 'rect', 'circle', 'ellipse', 'line', 'polyline',
              'polygon', 'g'}
ALLOWED_ATTR = {'xmlns', 'viewBox', 'd', 'x', 'y', 'width', 'height', 'rx', 'ry', 'cx', 'cy', 'r', 'x1', 'y1', 'x2',
                'y2', 'points', 'fill', 'stroke', 'stroke-width', 'stroke-linecap', 'stroke-linejoin',
                'stroke-dasharray', 'stroke-dashoffset', 'fill-rule', 'transform', 'data-lit', 'id',
                'gradientUnits', 'offset', 'stop-color', 'stop-opacity'}
FAMILIES = {'A': 'Sketch Create', 'B': 'Sketch Constrain, Modify, Insert, 2D pattern, sketch singles',
            'C': 'Part Create, Modify, Direct', 'D': 'Work features, PL / AX / PN, 3D pattern, view, measure',
            'E': 'Assembly'}
GENERATORS = {f: 'tools/icon_redesign/families/%s.py' % f for f in FAMILIES}
GENERATORS['ref'] = 'tools/icon_redesign/families/ref.py'


# ----------------------------------------------------------------- _map: shipping and v2 (SPEC §12)
def _bucket(p, hue):
    return p['rawAccent'] if 175 <= hue < 265 else p['ok'] if 75 <= hue < 175 else p['projRef'] if 18 <= hue < 75 else p['err']


def _cap(th, sat, p):
    """The lightest L (this hue / saturation) that still gives 3.2:1 on T.bg."""
    bg = PB.opaque(p, 'bg')
    lo, hi = 0.0, 1.0
    for _ in range(24):
        mid = (lo + hi) / 2
        lo, hi = (mid, hi) if PB.contrast(PB.hsl_to(th, sat, mid), bg) >= 3.2 else (lo, mid)
    return lo


def map_flat(src, p, mode='v2'):
    """A flat fill / stroke colour (ink). 'ship' = icon_theme.dart today; 'v2' = SPEC §12 (a) hue-less greys
    + (b) the luminance-capped light band for chromatic ink."""
    if mode == 'ship':
        return PB.map_icon(src, p)
    hue, s, l = PB.hsl_from(src)
    light = not p['_dark']
    if s < 0.12:
        ink_h, ink_s, _ = PB.hsl_from(PB.opaque(p, 'ink'))
        ll = 1 - l if light else l
        return PB.hsl_to(ink_h, 0.0 if ink_s < 0.05 else 0.04, PB.clamp(ll, 0.12, 0.92))
    th, ts, _ = PB.hsl_from(_bucket(p, hue))
    sat = PB.clamp(ts * 0.85 + s * 0.15, 0.25, 0.95)
    if not light:
        return PB.hsl_to(th, sat, PB.clamp(l, 0.32, 0.82))
    return PB.hsl_to(th, sat, 0.22 + l * (_cap(th, sat, p) - 0.22))


def map_stop(src, p):
    """A gradient stop-color inside a data-lit="2" SVG (material): SPEC §12 (c)."""
    hue, s, l = PB.hsl_from(src)
    l2 = l if p['_dark'] else 0.10 + 0.70 * l
    if s < 0.12:
        return PB.hsl_to(hue, s, PB.clamp(l2, 0.12, 0.92))
    th, ts, _ = PB.hsl_from(_bucket(p, hue))
    return PB.hsl_to(th, min(s, ts), PB.clamp(l2, 0.22, 0.86))


_HEX = re.compile(r'(stop-color=")?#([0-9a-fA-F]{6})\b')


def map_svg(src, p, mode='v2'):
    lit = mode == 'v2' and 'data-lit="2"' in src
    return _HEX.sub(lambda m: (m.group(1) or '') + '#' + (
        map_stop(m.group(2), p) if (m.group(1) and lit) else map_flat(m.group(2), p, mode)), src)


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


def sha(src):
    return hashlib.sha256(src.encode('utf-8')).hexdigest()


def superseded():
    """{relpath: sha256} of the old-style (v1) files. A listed file is ignored while its content still has
    that hash; a generator that overwrites it with a v2 drawing changes the hash, and the file is linted."""
    out = {}
    if os.path.exists(SUPERSEDED):
        for line in open(SUPERSEDED, encoding='utf-8'):
            m = re.match(r'^([0-9a-f]{64})\s+(\S+)\s*$', line)
            if m:
                out[m.group(2)] = m.group(1)
    return out


# ------------------------------------------------------------ geometry (bounds and ink-over-material lint)
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




def ink_over_material(drawn):
    """SPEC v2 §6: flat ink never crosses a material face (ink inverts with the theme, material does not, so
    one of the two themes always loses the contrast). drawn: [(tag, polys, kind, sw)] in paint order;
    kind 'ink' (flat stroke / fill), 'mat' (gradient fill) or 'hair'."""
    errs = []
    faces = [(polys, tag) for tag, polys, kind, sw in drawn if kind == 'mat']
    if not faces:
        return errs
    for tag, polys, kind, sw in drawn:
        if kind != 'ink':
            continue
        margin = sw / 2 + 0.35
        pts = _samples(polys)
        for fpolys, ftag in faces:
            hit = [p for p in pts if _inside(p, fpolys) and _dist(p, fpolys) > margin]
            if hit:
                errs.append('flat ink <%s> crosses a material face near (%.1f, %.1f): ink lives on the ground, '
                            'marks on a solid are material (SPEC §6)' % (tag, hit[0][0], hit[0][1]))
                break
    return errs


def hue_family(h6):
    hue, s, l = PB.hsl_from(h6)
    if s < 0.12 or l > 0.96 or l < 0.04:
        return 'neutral'
    return 'accent' if 175 <= hue < 265 else 'green' if 75 <= hue < 175 else 'amber' if 18 <= hue < 75 else 'red'


# ------------------------------------------------------------------- lint
def lint_svg(name, ref, src, pals, ids_seen):
    """-> (errors, metrics). metrics: silhouette contrast on the rail per theme under the v2 _map."""
    errs = []
    E = lambda msg: errs.append('%s: %s' % (name, msg))
    if re.search(r'<\s*(text|tspan)\b', src) or 'font-' in src:
        E('<text>/font attributes are banned; letters are paths')
    if re.search(r'<\s*(filter|mask|clipPath|radialGradient|image|pattern|use|style)\b', src) or re.search(r'(?<![\w-])(filter|mask|clip-path|style|class|opacity|fill-opacity|stroke-opacity)=', src):
        E('filters, masks, clip paths, radial gradients, <use>, style/class and opacity attributes are banned')
    if '<!--' in src:
        E('comments are banned')
    for h in re.findall(r'#[0-9A-Fa-f]+\b', src):
        if len(h) != 7:
            E('colour %s is not 6-digit #RRGGBB' % h)
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
    if root.get('fill') != 'none' or root.get('stroke-linecap') != 'round' or root.get('stroke-linejoin') != 'round':
        E('root must set fill="none" stroke-linecap="round" stroke-linejoin="round"')
    sm = name.endswith('.sm.svg')
    m, k = ref.split('.', 1)
    pfx = 'g-%s-%s%s-' % (m, k, '-sm' if sm else '')

    # ---- gradients
    grads = {}
    for el in root.iter():
        if tag(el) == 'linearGradient':
            gid = el.get('id') or ''
            stops = [s for s in el if tag(s) == 'stop']
            grads[gid] = stops
            if not gid.startswith(pfx):
                E('gradient id %r must start with %r (unique app-wide, SPEC §12)' % (gid, pfx))
            if gid in ids_seen and ids_seen[gid] != name:
                E('gradient id %s collides with %s' % (gid, ids_seen[gid]))
            ids_seen.setdefault(gid, name)
            if len(stops) != 2:
                E('gradient %s has %d stops: exactly 2 per face (SPEC §4)' % (gid, len(stops)))
            cols = [(s.get('stop-color') or '').upper() for s in stops]
            for s, c in zip(stops, cols):
                if c not in STOPS:
                    fam = hue_family(c[1:]) if re.fullmatch(r'#[0-9A-F]{6}', c) else '?'
                    E('stop-color %s is not a v2 material stop%s' % (c, ' (%s is banned in tool icons)' % fam if fam in ('amber', 'green', 'red') else ''))
                op = s.get('stop-opacity')
                if op is not None:
                    o = num(op)
                    if c == HIGHLIGHT:
                        continue
                    if c in PANE and o in CR.GLASS:
                        continue
                    E('stop-opacity %s on %s: only on the hairline white or a glass pane (%s)' % (op, c, '/'.join(map(str, CR.GLASS))))
            if (HIGHLIGHT in cols) and any(c != HIGHLIGHT for c in cols):
                E('gradient %s mixes the hairline white with a material stop' % gid)
        elif el.get('id') is not None and tag(el) != 'linearGradient':
            E('id on <%s>: ids are for gradients only' % tag(el))
    used = set(re.findall(r'url\(#([^)]+)\)', src))
    for u in used:
        if u not in grads:
            E('url(#%s) has no target' % u)
    for g in grads:
        if g not in used:
            E('gradient %s is never used' % g)
    lit = root.get('data-lit')
    if grads and lit != '2':
        E('uses gradients but the root lacks data-lit="2" (SPEC §12: without it _map inverts the material)')
    if lit is not None and (lit != '2' or not grads):
        E('data-lit=%r: only data-lit="2", and only on an SVG with gradients' % lit)

    # ---- elements, paint, strokes
    flats = set()
    mins = {}
    drawn = []

    def walk(el, inh, mtx):
        t = tag(el)
        if t not in ALLOWED_EL:
            E('element <%s> is banned' % t)
        for a in el.attrib:
            if a not in ALLOWED_ATTR:
                E('attribute %s on <%s> is banned' % (a, t))
        if t in ('defs', 'linearGradient', 'stop'):
            return
        tr = el.get('transform')
        if tr and not re.fullmatch(r'\s*((matrix|translate)\([^)]*\)\s*)+', tr):
            E('transform %r: only matrix()/translate()' % tr)
        cur = dict(inh)
        if tr:
            n_ = _mat(tr)
            m_ = mtx
            mtx = [m_[0] * n_[0] + m_[2] * n_[1], m_[1] * n_[0] + m_[3] * n_[1], m_[0] * n_[2] + m_[2] * n_[3],
                   m_[1] * n_[2] + m_[3] * n_[3], m_[0] * n_[4] + m_[2] * n_[5] + m_[4], m_[1] * n_[4] + m_[3] * n_[5] + m_[5]]
        for a in ('fill', 'stroke', 'stroke-width', 'stroke-dasharray', 'stroke-linecap'):
            if el.get(a) is not None:
                cur[a] = el.get(a)
        if t in ('svg', 'g'):
            for ch in el:
                walk(ch, cur, mtx)
            return
        stroke, fill = cur.get('stroke', 'none'), cur.get('fill', 'none')
        sw = num(cur.get('stroke-width', '1'))
        for a, v in (('fill', fill), ('stroke', stroke)):
            if v == 'none' or v.startswith('url(#'):
                continue
            if not re.fullmatch(r'#[0-9A-Fa-f]{6}', v):
                E('%s=%r: only none, url(#gradient) or a v2 ink #RRGGBB' % (a, v))
                continue
            V = v.upper()
            if V in FLAT:
                flats.add(V)
            elif V in CONSTRAINT:
                if re.sub(r'\.sm$', '', ref) not in CONSTRAINT_RED:
                    E('%s %s (constraint red) is allowed only in the constraint set %s (SPEC §5.5)'
                      % (a, v, ', '.join(sorted(CONSTRAINT_RED))))
                flats.add(V)
            elif V in STATUS:
                if re.sub(r'\.sm$', '', ref) in CONSTRAINT_RED:
                    E('%s %s (status red) in a constraint icon: the constraint red is CON %s (SPEC §5.5)' % (a, v, CR.CON))
                elif re.sub(r'\.sm$', '', ref) not in STATUS_RED:
                    E('%s %s (red) is the status exception: allowed only in %s (SPEC §5.4)' % (a, v, ', '.join(sorted(STATUS_RED))))
                flats.add(V)
            else:
                fam = hue_family(V[1:])
                if fam in ('amber', 'green', 'red'):
                    E('%s %s: %s is banned in tool icons (SPEC §5.4)' % (a, v, fam))
                elif V in STOPS:
                    E('%s %s is a material stop used as flat paint: material is gradients only (SPEC §4)' % (a, v))
                else:
                    E('%s %s is not a v2 ink (INK %s, SEC %s, ACC %s; CON %s in the constraint set)' % (a, v, CR.INK, CR.SEC, CR.ACC, CR.CON))
        if stroke.startswith('url(#'):
            gid = stroke[5:-1]
            cols = [(s.get('stop-color') or '').upper() for s in grads.get(gid, [])]
            if cols and set(cols) != {HIGHLIGHT}:
                E('<%s> gradient stroke %s: the only gradient stroke is the hairline (white stops)' % (t, gid))
            if sw != CR.HAIR:
                E('<%s> hairline width %s: must be %s' % (t, cur.get('stroke-width'), CR.HAIR))
            if sm:
                E('<%s> a .sm.svg drops the hairline (SPEC §2.4)' % t)
        elif stroke != 'none':
            if sw not in WIDTHS:
                E('<%s> stroke-width %s: ink strokes are %s' % (t, cur.get('stroke-width', '1 (default)'), ' / '.join(map(str, sorted(WIDTHS - {0.5})))))
            elif sw == 0.5 and fill.upper() != stroke.upper():
                E('<%s> stroke-width .5 is only the arrowhead softening (fill and stroke of one colour)' % t)
            if cur.get('stroke-dasharray') and cur.get('stroke-linecap') != 'butt':
                E('<%s> dashed stroke needs stroke-linecap="butt"' % t)
        if fill.startswith('url(#'):
            cols = [(s.get('stop-color') or '').upper() for s in grads.get(fill[5:-1], [])]
            if HIGHLIGHT in cols:
                E('<%s> the hairline white may only stroke, never fill' % t)
        try:
            polys = shape_polys(el, t, mtx)
        except (ValueError, IndexError, ZeroDivisionError) as ex:
            E('<%s> geometry could not be parsed (%s)' % (t, ex))
            return
        if fill.startswith('url(#'):
            drawn.append((t, polys, 'mat', 0.0))
        elif stroke.startswith('url(#'):
            drawn.append((t, polys, 'hair', sw or CR.HAIR))
        if fill not in ('none',) and not fill.startswith('url(#'):
            drawn.append((t, polys, 'ink', 0.0))
        if stroke not in ('none',) and not stroke.startswith('url(#'):
            drawn.append((t, polys, 'ink', sw or 1.0))

    walk(root, {'fill': root.get('fill', 'black')}, [1, 0, 0, 1, 0, 0])
    if re.sub(r'\.sm$', '', ref) in CONSTRAINT_RED and CR.CON.upper() not in flats:
        E('a constraint icon draws its relation marker in CON %s, the constraint red (SPEC §5.5)' % CR.CON)
    for e in ink_over_material(drawn):
        E(e)

    # ---- extent and bounds (SPEC §2)
    xs, ys = [], []
    for _, polys, kind, sw in drawn:
        hw = sw / 2
        for pts, _ in polys:
            for x, y in pts:
                xs += [x - hw, x + hw]
                ys += [y - hw, y + hw]
    if xs:
        w, h = max(xs) - min(xs), max(ys) - min(ys)
        if max(w, h) < MIN_EXTENT:
            E('glyph extent %.1f x %.1f u: too small, it must fill the cell (major extent >= %gu, SPEC §2)' % (w, h, MIN_EXTENT))
        if min(xs) < 0.75 or min(ys) < 0.75 or max(xs) > 27.25 or max(ys) > 27.25:
            E('glyph reaches %.2f..%.2f x %.2f..%.2f: nothing may cross 0.75 / 27.25 (SPEC §2)' % (min(xs), max(xs), min(ys), max(ys)))
    else:
        E('draws nothing')

    # ---- silhouette contrast after the v2 _map, on the rail, both themes (SPEC §5.3)
    opaque = set(flats)
    for gid, stops in grads.items():
        for s in stops:
            c = (s.get('stop-color') or '').upper()
            if c == HIGHLIGHT or c not in STOPS:
                continue
            if (num(s.get('stop-opacity')) or 1.0) >= 0.9:
                opaque.add(('stop', c))
    for pid, p in pals.items():
        mode = 'dark' if p['_dark'] else 'light'
        bg = PB.opaque(p, 'bg')
        best = 0.0
        for c in opaque:
            mapped = map_stop(c[1][1:], p) if isinstance(c, tuple) else map_flat(c[1:], p)
            best = max(best, PB.contrast(mapped, bg))
        mins[mode] = round(best, 2)
        if best < MIN_CONTRAST:
            E('silhouette contrast %.2f < %.1f on the %s rail after the v2 _map' % (best, MIN_CONTRAST, mode))
    mat = sorted({'acc' if hue_family(c[1][1:]) == 'accent' else 'steel' for c in opaque if isinstance(c, tuple)})
    return errs, {'dark': mins.get('dark', 0), 'light': mins.get('light', 0),
                  'ink': sorted(FLAT.get(c, STATUS.get(c, CONSTRAINT.get(c, c))) for c in flats), 'mat': mat}


def lint_all(scope, pals):
    errs, warns, metrics, new = [], [], {}, {}
    scope_refs = {e['ref'] for e in scope}
    sup = superseded()
    files = skipped = 0
    ids_seen = {}
    for dp, _, fs in sorted(os.walk(DESIGN)):
        for f in sorted(fs):
            if not f.endswith('.svg'):
                continue
            path = os.path.join(dp, f)
            rel = os.path.relpath(path, DESIGN).replace(os.sep, '/')
            src = open(path, encoding='utf-8').read().strip()
            if rel in sup and sup[rel] == sha(src):
                skipped += 1
                continue
            files += 1
            if rel.startswith('_motifs/'):
                errs.append('%s: v2 motifs are library calls (lib/crisp.py); do not add files to _motifs/' % rel)
                continue
            sm = f.endswith('.sm.svg')
            ref = ref_of(path[:-7] + '.svg') if sm else ref_of(path)
            if ref not in scope_refs:
                errs.append('%s: not in the SPEC §11 family table (expected design/icons/<MAP>/<key>.svg)' % rel)
                continue
            e, m = lint_svg(rel, ref, src, pals, ids_seen)
            errs += e
            if sm:
                new[ref + '@sm'] = src
            else:
                new[ref] = src
                metrics[ref] = m
    for ref in list(new):
        if ref.endswith('@sm') and ref[:-3] not in new:
            errs.append('%s.sm.svg: a small master without its v2 28 master' % ref[:-3])
    # aliases and duplicates
    alias = {e['ref']: e['alias'] for e in scope if e['alias']}
    for a, t in alias.items():
        if a in new and t in new and re.sub(r'id="g-[^"]*"|url\(#g-[^)]*\)', '', new[a]) != re.sub(r'id="g-[^"]*"|url\(#g-[^)]*\)', '', new[t]):
            errs.append('%s: alias of %s but not the same drawing (only the gradient ids may differ)' % (a, t))
        if a in new and t not in new:
            errs.append('%s: alias drawn before its target %s' % (a, t))
    seen = {}
    for ref, s in new.items():
        if ref.endswith('@sm'):
            continue
        key = re.sub(r'id="g-[^"]*"|url\(#g-[^)]*\)', '', s)
        if key in seen and alias.get(ref) != seen[key] and alias.get(seen[key]) != ref:
            errs.append('%s: identical drawing to %s (not a declared alias)' % (ref, seen[key]))
        seen.setdefault(key, ref)
    # the SPEC lists the palette and every material stop
    spec = open(SPEC, encoding='utf-8').read()
    for k, h in list(CR.PALETTE.items()) + list(CR.STATUS.items()) + list(CR.CONSTRAINT.items()):
        if h not in spec:
            errs.append('SPEC.md §5 does not list %s %s' % (k, h))
    for mname in CR.MATERIAL:
        for kind in CR.KINDS:
            for h in CR.mat_stops(mname, kind):
                if h not in spec:
                    errs.append('SPEC.md §4 does not list the %s %s stop %s' % (mname, kind, h))
    # palette-level contrast of every flat ink (rail must reach 3:1; panel / fly warn)
    for h, k in list(FLAT.items()) + list(STATUS.items()) + list(CONSTRAINT.items()):
        for pid, p in pals.items():
            for surf in ('bg', 'panel', 'fly'):
                c = PB.contrast(map_flat(h[1:], p), PB.opaque(p, surf))
                if c < MIN_CONTRAST:
                    (errs if surf == 'bg' else warns).append('palette %s on %s %s: %.2f' % (k, pid, surf, c))
    return errs, warns, metrics, new, files, skipped


# ------------------------------------------------------------------ splice
def between(s, a, b, include_a=False):
    i = s.find(a)
    j = s.find(b, i + len(a))
    if i < 0 or j < 0:
        sys.exit('template marker not found: %r .. %r (did the reused template change?)' % (a, b))
    return s[i if include_a else i + len(a):j]




def write_superseded():
    """--supersede: list every SVG under design/icons that is not drawn in the v2 palette (any colour outside
    the v2 inks and material stops) with its hash. Additive: existing entries are kept."""
    sup = superseded()
    v2cols = set(FLAT) | set(STATUS) | set(CONSTRAINT) | STOPS
    lines = ['%s  %s' % (h, r) for r, h in sorted(sup.items())]
    for dp, _, fs in sorted(os.walk(DESIGN)):
        for f in sorted(fs):
            if f.endswith('.svg'):
                path = os.path.join(dp, f)
                rel = os.path.relpath(path, DESIGN).replace(os.sep, '/')
                src = open(path, encoding='utf-8').read().strip()
                if rel in sup or {h.upper() for h in re.findall(r'#[0-9A-Fa-f]{6}', src)} <= v2cols:
                    continue
                lines.append('%s  %s' % (sha(src), rel))
    with open(SUPERSEDED, 'w', encoding='utf-8') as fh:
        fh.write('# Old-style (SPEC v1) SVGs, superseded by SPEC v2 "Modern Crisp". The build ignores a file listed here\n'
                 '# while its content still has this sha256. A family generator overwrites the file with its v2 drawing,\n'
                 '# the hash no longer matches, and from then on the file is linted and counted as drawn. Never edit by hand.\n')
        fh.write('\n'.join(lines) + '\n')
    print('wrote %s (%d files)' % (SUPERSEDED, len(lines)))


def main():
    if '--supersede' in sys.argv:
        write_superseded()
        return
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
    new_keys = {e['ref'] for e in scope if e['ref'].startswith('DE.') or e['ref'] == 'IN.params'}
    for e in scope:
        r = e['ref']
        today = old.get(r) or (old.get(r[7:]) if r.startswith('single.') else None)
        if not today and r not in new_keys:
            sys.exit('SPEC §11 key %s does not exist in svg_icons.dart' % r)

    errs, warns, metrics, new, nfiles, nsup = lint_all(scope, pals)
    print('lint: %d v2 files, %d superseded (ignored), %d error(s), %d warning(s); %d/%d keys drawn in v2' % (
        nfiles, nsup, len(errs), len(warns), len([e for e in scope if e['ref'] in new]), len(scope)))
    for e in errs:
        print('  ERROR ' + e)
    for w in warns:
        print('  warn  ' + w)
    if lint_only:
        sys.exit(1 if errs else 0)

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
    for k, h in list(CR.PALETTE.items()) + list(CR.STATUS.items()) + list(CR.CONSTRAINT.items()):
        row = {'name': k, 'src': h, 'role': {'ERR': 'status', 'CON': 'constraint'}.get(k, 'ink')}
        for pid, p in pals.items():
            md = 'd' if p['_dark'] else 'l'
            for mode in ('ship', 'v2'):
                mh = map_flat(h[1:], p, mode)
                row[md + mode] = mh
                row['c' + md + mode] = round(PB.contrast(mh, PB.opaque(p, 'bg')), 2)
        pal_rows.append(row)
    mat_rows = []
    for mname in CR.MATERIAL:
        for kind in CR.KINDS:
            a, b = CR.mat_stops(mname, kind)
            row = {'name': '%s %s' % (mname, kind), 'src': [a, b]}
            for pid, p in pals.items():
                md = 'd' if p['_dark'] else 'l'
                row[md + 'v2'] = [map_stop(x[1:], p) for x in (a, b)]
                row[md + 'ship'] = [map_flat(x[1:], p, 'ship') for x in (a, b)]
            mat_rows.append(row)
    fields = [k for k in pals['%s-dark' % PRO_ID] if not k.startswith('_')]
    data = {
        'pals': pals, 'fields': fields, 'pid': {'dark': '%s-dark' % PRO_ID, 'light': '%s-light' % PRO_ID},
        'old': old, 'nu': new, 'scope': [{k: e[k] for k in ('fam', 'ref', 'concept', 'alias')} for e in scope],
        'scopeSet': {e['ref']: 1 for e in scope}, 'families': FAMILIES, 'generators': GENERATORS, 'metrics': metrics,
        'lint': {'errors': errs, 'warnings': warns, 'files': nfiles, 'superseded': nsup},
        'palette': pal_rows, 'material': mat_rows, 'rb': rbdata,
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
