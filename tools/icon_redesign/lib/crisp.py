#!/usr/bin/env python3
"""crisp.py - the drawing library of the ribbon icon system v2, "Modern Crisp" (design/icons/SPEC.md).

Every v2 icon is drawn through this module, so the set shares one projection, one material, one arrowhead
and one writer. Family generators (tools/icon_redesign/families/<LETTER>.py) import it:

    import os, sys
    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
    from crisp import *

    def extrude(ic):                       # ic is an Icon for one key
        s = box(ic, Iso(16.75, 15.88), (0, 0, 0), (9.25, 9.25, 11), 'acc')
        arrow(ic, (3.25, 24), (3.25, 3.5))

    if __name__ == '__main__':
        run({'CR.extrude': extrude})       # writes design/icons/CR/extrude.svg

Stdlib only. The API is documented in SPEC.md §13; the values below ARE the spec (the build's lint
imports PALETTE / STOPS / WIDTHS from here, and checks that SPEC.md lists them).
"""
import colorsys
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
DESIGN = os.path.join(ROOT, 'design', 'icons')

# ------------------------------------------------------------------------------------------- palette
# Flat paint is INK: it goes through _map like any glyph colour (inverts on a light theme).
INK = '#D6D6D6'   # primary ink: arrows, sketch geometry, existing points, badges
SEC = '#8C8C8C'   # secondary ink: extension lines, radius, construction, preview, reference, context
ACC = '#6AA9ED'   # flat accent ink: the point being placed, dimensions, constraint markers, the target ring
ERR = '#E96C67'   # STATUS EXCEPTION ONLY (SPEC 5.4): the fault mark of a sick / failed state. Nowhere else.
PALETTE = {'INK': INK, 'SEC': SEC, 'ACC': ACC}
STATUS = {'ERR': ERR}

R = 0.6           # silhouette rounding of every solid and plane corner (planes: R + .4)
HAIR = 0.6        # lit-edge hairline width (a white 2-stop gradient: material, not ink)
HEAD_L, HEAD_W = 3.4, 2.0      # the one arrowhead: 3.4 long, 2 x 2.0 wide, softened by a 0.5 same-colour stroke
SHAFT_BACK = 3.0  # a shaft stops 3.0 before the tip (0.4 inside the head)
DOT_INK, DOT_ACC = 1.9, 2.4    # existing point / point being placed
RING_R, RING_W = 4.6, 1.0      # the coincident / target ring around an accent dot
DASH = '2.5 2'                 # construction, preview, reference (SEC 1.25, butt caps)
DASH_AXIS = '5 1.75 1.25 1.75' # 2D centre / mirror line dash-dot (SEC 1.25, butt caps)
# stroke widths allowed on flat ink; 0.5 only on an arrowhead (fill + stroke of one colour)
WIDTHS = {'ext': 1.0, 'ring': 1.0, 'arrow': 1.25, 'construct': 1.25, 'dimline': 1.25, 'centre': 1.25,
          'geom': 1.5, 'symbol': 2.0}
ALLOWED_WIDTHS = (0.5, 1.0, 1.25, 1.5, 2.0)


def _hsl(h, s, l):
    r, g, b = colorsys.hls_to_rgb(h / 360, l, s)
    return '#%02X%02X%02X' % tuple(round(c * 255) for c in (r, g, b))


# Material: matte, exactly two stops per face, key light top-left. (lightness start, end) per face kind.
# steel: hue 212, S .06 (under the .12 neutral line of _map); accent: hue 211, S .54 (moves to the accent bucket).
MATERIAL = {
    'steel': {'h': 212, 's': .06, 'top': (.93, .89), 'lit': (.63, .60), 'shade': (.37, .35)},
    'acc': {'h': 211, 's': .54, 'top': (.88, .84), 'lit': (.65, .62), 'shade': (.45, .42)},
}
# Derived kinds, same two-stop rule, fixed offsets from the three faces (so the stop list stays closed):
#   curve  cylinder / cone side, lit at the left: (lit0 + .04, shade0 + .02)
#   band   a fillet / round: (top0, curve1)
#   deep   the far wall of a bore or pocket: (shade1 - .06, lit0)
#   pane   a plane / sheet: (top0 - .08, lit1 - .07)
for _m in MATERIAL.values():
    _m['curve'] = (round(_m['lit'][0] + .04, 3), round(_m['shade'][0] + .02, 3))
    _m['band'] = (_m['top'][0], _m['curve'][1])
    _m['deep'] = (round(_m['shade'][1] - .06, 3), _m['lit'][0])
    _m['pane'] = (round(_m['top'][0] - .08, 3), round(_m['lit'][1] - .07, 3))
KINDS = ('top', 'lit', 'shade', 'curve', 'band', 'deep', 'pane')


def stop_hex(mat, l):
    m = MATERIAL[mat]
    return _hsl(m['h'], m['s'], l)


def mat_stops(mat, kind):
    a, b = MATERIAL[mat][kind]
    return stop_hex(mat, a), stop_hex(mat, b)


HIGHLIGHT = '#FFFFFF'   # the hairline's stop colour (with stop-opacity .80 -> .15)
GLASS = (.85, .70)      # stop-opacity of a glass (see-through) pane
STOPS = {HIGHLIGHT}
for _mat in MATERIAL:
    for _k in KINDS:
        STOPS.update(mat_stops(_mat, _k))


# ------------------------------------------------------------------------------------------- geometry
def f(v):
    s = ('%.2f' % v).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def pt(p):
    return '%s %s' % (f(p[0]), f(p[1]))


def add(a, b, k=1.0):
    return (a[0] + b[0] * k, a[1] + b[1] * k)


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def unit(a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    d = math.hypot(dx, dy) or 1.0
    return (dx / d, dy / d)


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def poly(points, close=True):
    """'M..L..L..Z' through screen points."""
    d = 'M' + 'L'.join(pt(p) for p in points)
    return d + ('Z' if close else '')


class Iso:
    """The 2:1 dimetric projection. World x runs right-down (+1, +.5), y left-down (-1, +.5), z up (0, -1),
    all scaled by k. (ox, oy) is the screen position of the world origin. The viewer looks along -(1, 1, 1):
    the +z face is the top, +y the lit (left) face, +x the shade (right) face."""

    def __init__(self, ox, oy, k=1.0):
        self.ox, self.oy, self.k = ox, oy, k

    def p(self, x, y=0.0, z=0.0):
        k = self.k
        return (self.ox + (x - y) * k, self.oy + (x + y) * k / 2 - z * k)


VIEW = (1.0, 1.0, 1.0)


class Solid:
    """Faces of a polyhedral solid with a filleted silhouette (the B-crisp rule).

    P: name -> screen point; sil: silhouette vertex names in order; radii: name -> rounding.
    A silhouette corner is replaced by a quadratic fillet; an internal face edge that runs into a rounded
    corner ends at the fillet's midpoint (de Casteljau t = .5), so the faces meet on the curve, no notch."""

    def __init__(self, P, sil, radii):
        self.P = P
        self.sil = sil
        self.R = {}
        n = len(sil)
        for i, v in enumerate(sil):
            r = radii.get(v, 0)
            if r <= 0:
                continue
            V = P[v]
            pa, pb = sil[i - 1], sil[(i + 1) % n]
            la, lb = math.dist(V, P[pa]), math.dist(V, P[pb])
            rr = min(r, la * .45, lb * .45)
            p1 = add(V, unit(V, P[pa]), rr)
            p2 = add(V, unit(V, P[pb]), rr)
            mid = (.25 * p1[0] + .5 * V[0] + .25 * p2[0], .25 * p1[1] + .5 * V[1] + .25 * p2[1])
            self.R[v] = {pa: p1, pb: p2, 'mid': mid, 'V': V}

    def end(self, v):
        """Where an internal edge ending at silhouette vertex v really ends (the fillet midpoint)."""
        return self.R[v]['mid'] if v in self.R else self.P[v]

    def path(self, face):
        out = []
        n = len(face)
        for i, v in enumerate(face):
            u, w = face[i - 1], face[(i + 1) % n]
            if v not in self.R:
                out.append(('L', self.P[v]))
                continue
            c = self.R[v]
            V = c['V']
            if u in c and w in c:
                out += [('L', c[u]), ('Q', V, c[w])]
            elif u in c:
                out += [('L', c[u]), ('Q', lerp(c[u], V, .5), c['mid'])]
            elif w in c:
                out += [('L', c['mid']), ('Q', lerp(V, c[w], .5), c[w])]
            else:
                out.append(('L', c['mid']))
        s = ''
        for j, seg in enumerate(out):
            if seg[0] == 'L':
                s += ('M' if j == 0 else 'L') + pt(seg[1])
            else:
                s += 'Q' + pt(seg[1]) + ' ' + pt(seg[2])
        return s + 'Z'

    def outline(self):
        return self.path(self.sil)


def _hull(named):
    """Convex hull (names) of {name: (x, y)}, clockwise on screen (y down), collinear points dropped."""
    pts = sorted(named.items(), key=lambda kv: (round(kv[1][0], 6), round(kv[1][1], 6)))
    uniq = []
    for k, p in pts:
        if not uniq or math.dist(uniq[-1][1], p) > 1e-6:
            uniq.append((k, p))
    if len(uniq) < 3:
        return [k for k, _ in uniq]

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lo, hi = [], []
    for k, p in uniq:
        while len(lo) >= 2 and cross(lo[-2][1], lo[-1][1], p) <= 1e-9:
            lo.pop()
        lo.append((k, p))
    for k, p in reversed(uniq):
        while len(hi) >= 2 and cross(hi[-2][1], hi[-1][1], p) <= 1e-9:
            hi.pop()
        hi.append((k, p))
    return [k for k, _ in lo[:-1] + hi[:-1]]


def _normal(W, face):
    n = [0.0, 0.0, 0.0]
    for i, a in enumerate(face):
        b = face[(i + 1) % len(face)]
        A, B = W[a], W[b]
        n[0] += (A[1] - B[1]) * (A[2] + B[2])
        n[1] += (A[2] - B[2]) * (A[0] + B[0])
        n[2] += (A[0] - B[0]) * (A[1] + B[1])
    d = math.sqrt(sum(c * c for c in n)) or 1.0
    return [c / d for c in n]


# ------------------------------------------------------------------------------------------- the icon
class Icon:
    """One SVG. ref is 'MAP.key' (or 'single.name'); gradient ids are 'g-MAP-key[-sm]-<part>', unique app-wide."""

    def __init__(self, ref, sm=False):
        m, k = ref.split('.', 1)
        self.ref, self.sm = ref, sm
        self.pfx = 'g-%s-%s%s' % (m, k, '-sm' if sm else '')
        self.defs = {}      # xml -> id (identical gradients are shared)
        self.names = set()
        self.body = []

    # ---- paint
    def grad(self, name, stops, x1=0, y1=0, x2=1, y2=1, user=False):
        """A 2-stop linear gradient. stops: [(colour, opacity or None), (colour, opacity or None)]."""
        assert len(stops) == 2, 'two stops per gradient (SPEC 4)'
        units = ' gradientUnits="userSpaceOnUse"' if user else ''
        st = ''.join('<stop offset="%s" stop-color="%s"%s/>' % (
            o, c, '' if op is None else ' stop-opacity="%s"' % f(op)) for o, (c, op) in zip(('0', '1'), stops))
        body = '%s x1="%s" y1="%s" x2="%s" y2="%s">%s' % (units, f(x1), f(y1), f(x2), f(y2), st)
        if body in self.defs:
            return 'url(#%s)' % self.defs[body]
        gid, n = '%s-%s' % (self.pfx, name), 2
        while gid in self.names:
            gid, n = '%s-%s%d' % (self.pfx, name, n), n + 1
        self.names.add(gid)
        self.defs[body] = gid
        return 'url(#%s)' % gid

    def mat(self, mat, kind, x1=None, y1=None, x2=None, y2=None, user=False, opacity=None):
        """Material paint for a face. Default directions: top (0,0)->(1,1); lit/shade (0,0)->(.4,1) in the
        face's bounding box. curve/band/deep/pane need user-space coordinates from the caller."""
        a, b = mat_stops(mat, kind)
        if x1 is None:
            x1, y1, x2, y2 = (0, 0, 1, 1) if kind in ('top', 'pane') else (0, 0, .4, 1)
        op = opacity or (None, None)
        return self.grad(mat[0] + kind[0] + ('g' if opacity else ''), [(a, op[0]), (b, op[1])],
                         x1, y1, x2, y2, user)

    def fill(self, d, paint):
        self.body.append('<path d="%s" fill="%s"/>' % (d, paint))

    def hairline(self, d, x1, x2, op=(.8, .15)):
        """The lit-edge highlight: 0.6 u, white .80 -> .15 left to right (material, never ink).
        An 18 px master (sm=True) never draws it (SPEC 2.4): every call is a no-op there, so a family draws
        its .sm with the same code and no hair= flags."""
        if self.sm:
            return
        g = self.grad('hl', [(HIGHLIGHT, op[0]), (HIGHLIGHT, op[1])], x1, 0, x2, 0, user=True)
        self.body.append('<path d="%s" stroke="%s" stroke-width="%s"/>' % (d, g, f(HAIR)))

    def stroke(self, d, col=INK, w=1.5, dash=None):
        assert w in ALLOWED_WIDTHS, w
        extra = ' stroke-dasharray="%s" stroke-linecap="butt"' % dash if dash else ''
        self.body.append('<path d="%s" stroke="%s" stroke-width="%s"%s/>' % (d, col, f(w), extra))

    def shape(self, d, col=INK):
        """A filled flat-ink shape (badge, symbol)."""
        self.body.append('<path d="%s" fill="%s"/>' % (d, col))

    def circle(self, c, r, fill=None, stroke=None, w=None):
        a = ' fill="%s"' % fill if fill else ''
        if stroke:
            a += ' stroke="%s" stroke-width="%s"' % (stroke, f(w))
        self.body.append('<circle cx="%s" cy="%s" r="%s"%s/>' % (f(c[0]), f(c[1]), f(r), a))

    def ellipse(self, c, rx, ry, paint):
        self.body.append('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" fill="%s"/>' % (f(c[0]), f(c[1]), f(rx), f(ry), paint))

    def add(self, raw):
        self.body.append(raw)

    # ---- output
    def svg(self):
        lit = ' data-lit="2"' if self.defs else ''
        head = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 28 28" fill="none" stroke-linecap="round" '
                'stroke-linejoin="round"%s>' % lit)
        defs = ''
        if self.defs:
            defs = '<defs>%s</defs>\n' % '\n'.join('<linearGradient id="%s"%s</linearGradient>' % (gid, body)
                                                  for body, gid in self.defs.items())
        return head + '\n' + defs + '\n'.join(self.body) + '\n</svg>\n'

    def path_out(self, root=DESIGN):
        m, k = self.ref.split('.', 1)
        return os.path.join(root, m, k + ('.sm' if self.sm else '') + '.svg')

    def write(self, root=DESIGN):
        p = self.path_out(root)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w', encoding='utf-8') as fh:
            fh.write(self.svg())
        return p


# ------------------------------------------------------------------------------------------- solids
def solid(ic, iso, W, faces, mat='steel', r=R, kinds=None, hair=True, sil_r=None):
    """A CONVEX polyhedron. W: name -> world (x, y, z); faces: name -> [vertex names] (any winding).
    Hidden faces are dropped (normal . (1,1,1) <= 0); each visible face takes the material kind of its
    normal's dominant axis (z top, y lit, x shade) unless kinds={face: kind} overrides it. The silhouette
    is the convex hull, every corner rounded by r (sil_r={vertex: r} overrides). Paint order: the silhouette
    in the shade stop (no seams), side faces, top faces, then the hairline on the edges between the top face
    and the visible side faces. Returns the Solid (screen points in .P, plus .faces / .kinds / .W)."""
    P = {k: iso.p(*v) for k, v in W.items()}
    cen = [sum(v[i] for v in W.values()) / len(W) for i in range(3)]
    vis, kind_of = {}, {}
    for name, fc in faces.items():
        n = _normal(W, fc)
        fcen = [sum(W[v][i] for v in fc) / len(fc) for i in range(3)]
        if sum(n[i] * (fcen[i] - cen[i]) for i in range(3)) < 0:
            n = [-c for c in n]
        if sum(n[i] * VIEW[i] for i in range(3)) <= 1e-6:
            continue
        vis[name] = fc
        kind_of[name] = (kinds or {}).get(name) or ('top' if n[2] >= max(n[0], n[1]) else 'lit' if n[1] >= n[0] else 'shade')
    used = {v for fc in vis.values() for v in fc}
    sil = _hull({v: P[v] for v in used})
    radii = {v: (sil_r or {}).get(v, r) for v in sil}
    S = Solid(P, sil, radii)
    S.faces, S.kinds, S.W = vis, kind_of, W
    ic.fill(S.outline(), ic.mat(mat, 'shade'))
    order = sorted(vis, key=lambda k: {'shade': 0, 'lit': 1, 'top': 2}.get(kind_of[k], 1))
    for name in order:
        ic.fill(S.path(vis[name]), ic.mat(mat, kind_of[name]))
    if hair:
        _hair_top(ic, S)
    return S


def _hair_top(ic, S):
    edges = []
    for tn, tf in S.faces.items():
        if S.kinds[tn] != 'top':
            continue
        for i, a in enumerate(tf):
            b = tf[(i + 1) % len(tf)]
            for on, of in S.faces.items():
                if on != tn and S.kinds[on] in ('lit', 'shade') and a in of and b in of:
                    edges.append((a, b))
    if not edges:
        return
    # chain the edges into one polyline, left to right
    chain = list(min(edges, key=lambda e: min(S.P[e[0]][0], S.P[e[1]][0])))
    if S.P[chain[0]][0] > S.P[chain[1]][0]:
        chain.reverse()
    rest = [e for e in edges if set(e) != set(chain[:2])]
    grew = True
    while rest and grew:
        grew = False
        for e in rest:
            if chain[-1] in e:
                chain.append(e[1] if e[0] == chain[-1] else e[0])
                rest.remove(e)
                grew = True
                break
    pts = [S.end(v) if v in S.sil else S.P[v] for v in chain]
    ic.hairline(poly(pts, False), pts[0][0], pts[-1][0])


def prism(ic, iso, base, z0, heights, mat='steel', **kw):
    """A vertical prism over a CONVEX base polygon base=[(x, y), ...] (world, any winding) from z0 up to
    z0 + heights[i] at each base vertex (one number = a flat top; the top corners must be coplanar).
    A height of 0 makes a wedge.
    Faces are named 'top' and 'side<i>' (between base[i] and base[i+1]); vertices 'b<i>' and 't<i>'."""
    n = len(base)
    hs = heights if isinstance(heights, (list, tuple)) else [heights] * n
    W = {}
    for i, (x, y) in enumerate(base):
        W['b%d' % i] = (x, y, z0)
        W['t%d' % i] = (x, y, z0 + hs[i]) if hs[i] > 1e-9 else None
    top_of = {i: ('t%d' % i if W['t%d' % i] else 'b%d' % i) for i in range(n)}
    tname = top_of.get
    W = {k: v for k, v in W.items() if v is not None}
    faces = {'top': [tname(i) for i in range(n)], 'bottom': ['b%d' % i for i in range(n)]}
    for i in range(n):
        j = (i + 1) % n
        fc = []
        for v in ('b%d' % i, 'b%d' % j, tname(j), tname(i)):
            if v not in fc:
                fc.append(v)
        if len(fc) >= 3:
            faces['side%d' % i] = fc
    return solid(ic, iso, W, faces, mat, **kw)


def box(ic, iso, o, size, mat='steel', **kw):
    """An axis-aligned box from world corner o=(x, y, z) with size=(a, b, h). Vertex names: top B (back),
    R (right), F (front), L (left); bottom Bb Rb Fb Lb. Face names top / left (lit) / right (shade)."""
    x, y, z = o
    a, b, h = size
    W = {'B': (x, y, z + h), 'R': (x + a, y, z + h), 'F': (x + a, y + b, z + h), 'L': (x, y + b, z + h),
         'Bb': (x, y, z), 'Rb': (x + a, y, z), 'Fb': (x + a, y + b, z), 'Lb': (x, y + b, z)}
    faces = {'top': ['B', 'R', 'F', 'L'], 'left': ['L', 'F', 'Fb', 'Lb'], 'right': ['F', 'R', 'Rb', 'Fb'],
             'bottom': ['Bb', 'Rb', 'Fb', 'Lb'], 'back': ['B', 'R', 'Rb', 'Bb'], 'backl': ['B', 'L', 'Lb', 'Bb']}
    return solid(ic, iso, W, faces, mat, **kw)


def wedge(ic, iso, o, size, mat='steel', low='x', **kw):
    """A box whose top slopes down to zero height on one side: low='x' (the right, shade side), 'y' (the
    left, lit side), '-x' or '-y' (the back sides). The sloped face is shaded by its normal."""
    x, y, z = o
    a, b, h = size
    base = [(x, y), (x + a, y), (x + a, y + b), (x, y + b)]
    hs = {'x': [h, 0, 0, h], 'y': [h, h, 0, 0], '-x': [0, h, h, 0], '-y': [0, 0, h, h]}[low]
    return prism(ic, iso, base, z, hs, mat, **kw)


def component(ic, top, half=9.25, mat='acc', h=None, **kw):
    """The assembly component cube: a box whose top (back) vertex sits at screen point top, half-width half
    (so it is 2*half wide), height 1.1*half unless given. Returns the Solid."""
    h = h if h is not None else round(half * 1.1, 2)
    iso = Iso(top[0], top[1] + h)
    return box(ic, iso, (0, 0, 0), (half, half, h), mat, **kw)


def _E(c, rx, ry, th, dy=0.0):
    a = math.radians(th)
    return (c[0] + rx * math.cos(a), c[1] + dy + ry * math.sin(a))


def _arc(rx, ry, large, sweep, p):
    return 'A%s %s 0 %d %d %s' % (f(rx), f(ry), large, sweep, pt(p))


def cylinder(ic, c, rx, h, mat='steel', ry=None, cut=None, hair=True, top=True):
    """A vertical cylinder; c is the CENTRE OF THE TOP face, ry defaults to rx/2 (the dimetric circle).
    cut=(t1, t2) removes the wedge between those angles (degrees, screen y down: 0 right, 90 front, 180 left;
    0 <= t1 < t2 <= 180), which is the Revolve body. Side pieces are curved material lit from the left (the
    front-right sliver of a cut body takes the plain shade face); cut faces are lit when they face left,
    shade when they face right. Returns a dict of handy points: C, Cb (axis top/bottom), E(th, dy)."""
    ry = rx / 2 if ry is None else ry
    cx, cy = c
    E = lambda th, dy=0.0: _E(c, rx, ry, th, dy)
    C, Cb = (cx, cy), (cx, cy + h)

    def side(a0, a1):
        return ('M%s' % pt(E(a0)) + _arc(rx, ry, 0, 1, E(a1)) + 'L%s' % pt(E(a1, h))
                + _arc(rx, ry, 0, 0, E(a0, h)) + 'Z')
    if not cut:
        ic.fill(side(0, 180), ic.mat(mat, 'curve', cx - rx, 0, cx + rx, 0, user=True))
        if top:
            ic.ellipse(C, rx, ry, ic.mat(mat, 'top'))
            if hair:
                a = E(178)
                ic.hairline('M%s' % pt(a) + _arc(rx, ry, 0, 0, E(96)), a[0], E(96)[0], (.75, .2))
        return {'C': C, 'Cb': Cb, 'E': E, 'rx': rx, 'ry': ry, 'h': h}
    t1, t2 = cut
    pieces = [(a, b) for a, b in ((0, t1), (t2, 180)) if b - a > .5]
    for a, b in pieces:
        if b <= 90:
            ic.fill(side(a, b), ic.mat(mat, 'shade', 0, 0, 0, 1))
    for t, sgn in ((t2, 1), (t1, -1)):
        # the cut face through angle t; its normal points toward the gap
        nx = sgn * math.sin(math.radians(t))
        face = 'M%sL%sL%sL%sZ' % (pt(C), pt(E(t)), pt(E(t, h)), pt(Cb))
        ic.fill(face, ic.mat(mat, 'shade' if nx > 0 else 'lit'))
    for a, b in pieces:
        if b > 90:
            ic.fill(side(a, b), ic.mat(mat, 'curve', cx - rx, 0, E(a)[0], 0, user=True))
    if top:
        large = 1 if (360 - (t2 - t1)) > 180 else 0
        ic.fill('M%sL%s' % (pt(C), pt(E(t2))) + _arc(rx, ry, large, 1, E(t1 + 360)) + 'Z', ic.mat(mat, 'top'))
        if hair and t2 < 176:
            a = E(178)
            ic.hairline('M%s' % pt(a) + _arc(rx, ry, 0, 0, E(t2 + 2)), a[0], E(t2)[0], (.75, .2))
    return {'C': C, 'Cb': Cb, 'E': E, 'rx': rx, 'ry': ry, 'h': h}


def bore(ic, c, rx, ry=None, mat='acc'):
    """A bored (cut-away) face: the ellipse of a hole in a top face, its inner wall dark under the back rim
    and lighter toward the front lip (the 'deep' kind)."""
    ry = rx / 2 if ry is None else ry
    ic.ellipse(c, rx, ry, ic.mat(mat, 'deep', 0, c[1] - ry, 0, c[1] + ry, user=True))


def pocket(ic, d, y0, y1, mat='acc'):
    """Any cut-away / recessed face given as a path d: the 'deep' ramp from y0 (back, dark) to y1 (lit)."""
    ic.fill(d, ic.mat(mat, 'deep', 0, y0, 0, y1, user=True))


def face(ic, d, mat, kind, **kw):
    """Fill an arbitrary face path with a material kind (custom solids: fillet bands, cones, revolved parts)."""
    ic.fill(d, ic.mat(mat, kind, **kw))


def plane(ic, pts, mat='acc', glass=False, r=None, hair=True):
    """A plane / sheet: 4 screen points (any parallelogram), corners rounded R + .4, the 'pane' ramp across
    its bounding box. glass=True makes it see-through (stop-opacity .85 -> .70) for a plane that passes in
    front of or through a solid. The hairline runs along its far (upper) edge."""
    r = R + .4 if r is None else r
    P = {str(i): p for i, p in enumerate(pts)}
    S = Solid(P, list(P), {k: r for k in P})
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    w = max(xs) - min(xs)
    g = ic.mat(mat, 'pane', min(xs) + .15 * w, min(ys), max(xs) - .15 * w, max(ys), user=True,
               opacity=GLASS if glass else None)
    ic.fill(S.outline(), g)
    if hair:
        n = len(pts)
        i = min(range(n), key=lambda i: (pts[i][1] + pts[(i + 1) % n][1]))
        a, b = pts[i], pts[(i + 1) % n]
        if a[0] > b[0]:
            a, b = b, a
        a2, b2 = add(a, unit(a, b), r), add(b, unit(b, a), r)
        ic.hairline('M%sL%s' % (pt(a2), pt(b2)), a2[0], b2[0], (.85, .2))
    return S


def iso_plane(ic, iso, o, u, v, mat='acc', **kw):
    """A plane on the dimetric lattice: corner o (world) spanned by world vectors u and v."""
    w = lambda *q: iso.p(*q)
    a = o
    b = tuple(a[i] + u[i] for i in range(3))
    c = tuple(b[i] + v[i] for i in range(3))
    d = tuple(a[i] + v[i] for i in range(3))
    return plane(ic, [w(*a), w(*b), w(*c), w(*d)], mat, **kw)


# ------------------------------------------------------------------------------------------- ink
def head(tip, direction, size=1.0):
    """The one arrowhead: a slim triangle HEAD_L long, 2*HEAD_W wide, pointing along direction."""
    ux, uy = direction
    d = math.hypot(ux, uy) or 1.0
    ux, uy = ux / d, uy / d
    L, Wd = HEAD_L * size, HEAD_W * size
    base = (tip[0] - ux * L, tip[1] - uy * L)
    a = (base[0] - uy * Wd, base[1] + ux * Wd)
    b = (base[0] + uy * Wd, base[1] - ux * Wd)
    return 'M%sL%sL%sZ' % (pt(tip), pt(a), pt(b))


def put_head(ic, tip, direction, col=INK):
    ic.add('<path d="%s" fill="%s" stroke="%s" stroke-width=".5"/>' % (head(tip, direction), col, col))


def arrow(ic, a, b, col=INK, w=1.25, both=False):
    """A straight arrow a -> b (both=True: heads at both ends). The shaft stops SHAFT_BACK before a tip."""
    u = unit(a, b)
    s = add(a, u, SHAFT_BACK) if both else a
    e = add(b, u, -SHAFT_BACK)
    ic.stroke('M%sL%s' % (pt(s), pt(e)), col, w)
    put_head(ic, b, u, col)
    if both:
        put_head(ic, a, (-u[0], -u[1]), col)


def _ell_samples(c, rx, ry, a0, a1, n=None):
    n = n or max(8, int(abs(a1 - a0) * 2))
    return [(a0 + (a1 - a0) * i / n, _E(c, rx, ry, a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def _back_at(samples, dist):
    """Walk back along samples [(theta, p)] from the end until the path length reaches dist."""
    acc = 0.0
    for i in range(len(samples) - 1, 0, -1):
        seg = math.dist(samples[i][1], samples[i - 1][1])
        if acc + seg >= dist:
            t = (dist - acc) / seg
            th = samples[i][0] + (samples[i - 1][0] - samples[i][0]) * t
            return th
        acc += seg
    return samples[0][0]


def _ell_path(c, rx, ry, a0, a1):
    p0, p1 = _E(c, rx, ry, a0), _E(c, rx, ry, a1)
    large = 1 if abs(a1 - a0) > 180 else 0
    sweep = 1 if a1 > a0 else 0
    return 'M%s' % pt(p0) + _arc(rx, ry, large, sweep, p1)


def arc_arrow(ic, c, rx, ry, a0, a1, col=INK, w=1.25):
    """An arrow along an elliptical (or circular, rx == ry) arc about c from angle a0 to a1 (degrees, screen
    y down; a1 > a0 runs clockwise on screen). The head sits on the path: its axis is the chord of the last
    HEAD_L of the arc, so the head is tangent to the curve and its base lies on it. For a 2D rotation."""
    S = _ell_samples(c, rx, ry, a0, a1)
    stop = _back_at(S, SHAFT_BACK)
    hb = _back_at(S, HEAD_L)
    ic.stroke(_ell_path(c, rx, ry, a0, stop), col, w)
    tip = _E(c, rx, ry, a1)
    put_head(ic, tip, sub(tip, _E(c, rx, ry, hb)), col)


def arc_arrow_dimetric(ic, c, rx, a0, a1, col=INK, w=1.25, body=None, clear=1.0, ratio=.5):
    """THE rotation arrow for 3D (revolve, rotate, free rotate, angle constraints): an elliptical arc on the
    dimetric lattice (ry = rx * ratio, ratio .5 for a horizontal circle), CONCENTRIC with the rim of the
    body it turns, at a radius 2-3 u larger, from a0 to a1 (degrees; 90 is the front). It follows the body's
    perspective, sweeps round the FRONT and ends with the shared head tangent to the ellipse.

    Height and side (the visible arc never crosses material, SPEC §6.3):
      * at RIM height (c = centre of the top face) the arc runs round the BACK, above the top face, and
        comes forward at a side: the standard (Revolve, Rotate, angle constraints). The head ends beside
        the body or in the mouth of an open (cut-away) side, never over a face;
      * at BASE height (c = centre of the bottom) it runs round the FRONT, under the body.
    Occlusion: body=(cx, half_width) hides the part of the arc that passes behind the body (back half and
    within half_width + clear of cx): use it for a base-height arc that starts behind the body.
    The arc is 1.25 u INK (or ACC when it is itself the dimension, e.g. an angle), round caps, one head.
    """
    ry = rx * ratio
    S = _ell_samples(c, rx, ry, a0, a1, n=int(abs(a1 - a0) * 4) + 8)
    stop = _back_at(S, SHAFT_BACK)
    hb = _back_at(S, HEAD_L)

    def hidden(th):
        if body is None:
            return False
        p = _E(c, rx, ry, th)
        return math.sin(math.radians(th)) < 0 and abs(p[0] - body[0]) < body[1] + clear
    # visible runs of the shaft (a0 -> stop)
    step = 1 if stop > a0 else -1
    runs, cur = [], None
    th = a0
    n = int(abs(stop - a0) * 4) + 1
    for i in range(n + 1):
        th = a0 + (stop - a0) * i / n
        if not hidden(th):
            cur = [th, th] if cur is None else [cur[0], th]
        elif cur is not None:
            runs.append(cur)
            cur = None
    if cur is not None:
        runs.append(cur)
    d = ''.join(_ell_path(c, rx, ry, s, e) for s, e in runs if abs(e - s) > .5)
    if d:
        ic.stroke(d, col, w)
    tip = _E(c, rx, ry, a1)
    put_head(ic, tip, sub(tip, _E(c, rx, ry, hb)), col)
    return {'tip': tip, 'runs': runs}


def arc_arrow_iso(ic, iso, c, u, v, r, a0, a1, col=INK, w=1.25):
    """The rotation arrow in ANY world plane (an angle about a horizontal hinge, PL.angleedge): the arc of
    radius r about world point c in the plane of world unit vectors u, v, from angle a0 to a1 (degrees,
    from u toward v), projected through iso. Same weight and the same head as arc_arrow_dimetric, head
    tangent to the projected curve."""
    def P(th):
        a = math.radians(th)
        return iso.p(*[c[i] + r * (math.cos(a) * u[i] + math.sin(a) * v[i]) for i in range(3)])
    n = int(abs(a1 - a0) * 2) + 8
    S = [(a0 + (a1 - a0) * i / n, P(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]
    stop = _back_at(S, SHAFT_BACK)
    hb = _back_at(S, HEAD_L)
    m = int(abs(stop - a0) * 2) + 4
    ic.stroke(poly([P(a0 + (stop - a0) * i / m) for i in range(m + 1)], False), col, w)
    tip = P(a1)
    put_head(ic, tip, sub(tip, P(hb)), col)
    return tip


def dim(ic, p, q, off, col=ACC, ext=SEC, gap=4.0, over=2.0, inset=.7, dirn=None):
    """A dimension of segment p-q: extension lines (SEC 1.0) from gap beyond the points to off + over, and
    the dimension line (col 1.25, heads at both ends, tips inset .7 inside the extension lines) at off.
    off is signed: the normal is p->q turned 90 degrees counter-clockwise on screen (up for p left of q).
    dirn: the extension direction for a dimension on a solid, along a world axis (e.g. (0, -1) = z up);
    the dimension line then stays parallel to p-q."""
    u = unit(p, q)
    n = (u[1], -u[0]) if dirn is None else unit((0, 0), dirn)
    s = 1 if off >= 0 else -1
    n = (n[0] * s, n[1] * s)
    off = abs(off)
    ic.stroke('M%sL%sM%sL%s' % (pt(add(p, n, gap)), pt(add(p, n, off + over)),
                               pt(add(q, n, gap)), pt(add(q, n, off + over))), ext, 1.0)
    a, b = add(add(p, n, off), u, inset), add(add(q, n, off), u, -inset)
    arrow(ic, a, b, col, 1.25, both=True)


def dot(ic, p, kind='ink'):
    """A flat sketch point: 'ink' (existing, r 1.9) or 'acc' (the point being placed, r 2.4)."""
    ic.circle(p, DOT_INK if kind == 'ink' else DOT_ACC, fill=INK if kind == 'ink' else ACC)


def ring(ic, p, r=RING_R):
    """The coincident / target ring (ACC 1.0) around an accent dot."""
    ic.circle(p, r, stroke=ACC, w=RING_W)


def line(ic, pts, col=INK, w=1.5, close=False):
    """Sketch geometry (INK 1.5) or any flat polyline."""
    ic.stroke(poly(pts, close), col, w)


def construct(ic, d, col=SEC):
    """Dashed construction / preview / reference geometry: SEC 1.25, dash 2.5 2, butt caps. d: a path."""
    ic.stroke(d, col, 1.25, DASH)


def work_axis(ic, a, b, col=SEC, w=1.25):
    """A 2D centre / mirror line (drafting): SEC 1.25 dash-dot, butt caps, on the ground only. The 3D WORK
    AXIS (a work feature) is material: use rod() (SPEC 5.3)."""
    ic.stroke('M%sL%s' % (pt(a), pt(b)), col, w, DASH_AXIS)


def work_point(ic, p, r=RING_R):
    """A work point on the ground: the accent dot (r 2.4) in the accent ring."""
    ring(ic, p, r)
    dot(ic, p, 'acc')


def rod(ic, a, b, r=1.1, mat='acc', caps=(True, True), socket=False):
    """A WORK AXIS: a slim material rod (2 x r wide) from a to b, lit on its left side, round ends (caps
    False = a flat end, where it leaves a solid). Material, so it may stand on or pass through a solid.
    socket=True draws the dark collar where it leaves a top face at a."""
    u = unit(a, b)
    n = (-u[1], u[0])
    if n[0] > 0 or (abs(n[0]) < 1e-9 and n[1] > 0):
        n = (-n[0], -n[1])                      # n points to the lit (left / upper) side
    if socket:
        ic.ellipse(a, r + .55, (r + .55) / 2, ic.mat('steel', 'deep', 0, a[1] - (r + .55) / 2, 0, a[1] + (r + .55) / 2, user=True))
    a1, a2, b1, b2 = add(a, n, r), add(a, n, -r), add(b, n, r), add(b, n, -r)
    d = 'M%sL%s' % (pt(a1), pt(b1))
    d += _arc(r, r, 0, 1 if _side(u, n) else 0, b2) if caps[1] else 'L%s' % pt(b2)
    d += 'L%s' % pt(a2)
    d += _arc(r, r, 0, 1 if _side(u, n) else 0, a1) if caps[0] else 'L%s' % pt(a1)
    ic.fill(d + 'Z', ic.mat(mat, 'curve', a1[0], a1[1], a2[0], a2[1], user=True))


def _side(u, n):
    return (u[0] * n[1] - u[1] * n[0]) < 0


def mat_dot(ic, p, r=2.4, mat='acc'):
    """A point ON a solid (ink may not cross material): a flush accent-material disc, lit to shade."""
    ic.circle(p, r, fill=ic.mat(mat, 'curve', p[0] - r, 0, p[0] + r, 0, user=True))


def badge(ic, kind='+', c=(22.5, 22.5), arm=3.5, col=INK):
    """A bare + or - modifier (INK 2.0), centred at c in the bottom-right 9 x 9 badge corner; the host
    drawing keeps 1 u clear of it. Never green or red (SPEC 5.4)."""
    d = 'M%sL%s' % (pt((c[0] - arm, c[1])), pt((c[0] + arm, c[1])))
    if kind == '+':
        d += 'M%sL%s' % (pt((c[0], c[1] - arm)), pt((c[0], c[1] + arm)))
    ic.stroke(d, col, 2.0)


# ------------------------------------------------------------------------------------------- shared motifs
# One drawing per idea, so the same idea reads the same in every family (SPEC 6.6, 13). Promoted from the
# family generators: eye / gear (B, E), glass_box / glass_cyl (C, E), bead / sphere / torus / clip_ink (D),
# tube / helix_band / thread_band / clip_poly / round_pts (C), edge_band (A, D).

EYE_H, EYE_PUPIL = .42, .13    # lens height and pupil radius as fractions of the lens width
EYE_BADGE = ((20.25, 21.5), 12.0)   # the eye as a modifier (show constraints, show format): bottom right
EYE_HERO = ((14, 21.25), 16.0)      # the eye as the subject (assembly show / hide)


def eye(ic, c, w=12.0, col=INK, slash=False, sm=False):
    """The show / hide eye (SPEC 6.6): an almond lens of two quadratic arcs, w wide and EYE_H * w tall,
    INK 1.5; a filled pupil r EYE_PUPIL * w (r 1.5 minimum; .8 of that at 18 px so the lens keeps a clear
    ring round it); slash=True adds the INK 1.5 hide slash, lower left to upper right, past the lens."""
    x, y = c
    hw, hh = w / 2, EYE_H * w / 2
    ic.stroke('M%sQ%s %sQ%s %sZ' % (pt((x - hw, y)), pt((x, y - 2 * hh)), pt((x + hw, y)),
                                     pt((x, y + 2 * hh)), pt((x - hw, y))), col, 1.5)
    r = max(1.5, EYE_PUPIL * w) * (.8 if sm else 1.0)
    ic.circle(c, r, fill=col)
    if slash:
        ic.stroke('M%sL%s' % (pt((x - .4 * w, y + .3 * w)), pt((x + .4 * w, y - .3 * w))), col, 1.5)


def gear(ic, c, r_tip, r_root, n, col=INK, w=1.5, phase=-math.pi / 2):
    """A spur-gear outline (settings, IN.gear): n trapezoid teeth between r_root and r_tip."""
    step = 2 * math.pi / n
    pts = []
    for i in range(n):
        a = phase + i * step
        tip, root = step * .2, step * .26          # half-widths of the tip land and the root land
        pts += [(a - step / 2 + root, r_root), (a - tip, r_tip), (a + tip, r_tip), (a + step / 2 - root, r_root)]
    P = [(c[0] + r * math.cos(t), c[1] + r * math.sin(t)) for t, r in pts]
    ic.stroke(poly(P), col, w)


def bead(ic, p, r=2.1, mat='steel'):
    """A REFERENCE point that sits on material (a pane, a rod, a face): a flush steel disc, r 2.1. The point a
    tool creates on material is the accent mat_dot (r 2.4); a point on the ground is ink (dot)."""
    mat_dot(ic, p, r, mat)


def sphere(ic, c, r, mat='steel', hair=True):
    """A sphere: one disc of curve material, lit from the upper left (diagonal ramp), the hairline on the
    upper-left rim. Matte, two stops, no specular blob, no shadow."""
    k = r * .72
    ic.circle(c, r, fill=ic.mat(mat, 'curve', c[0] - k, c[1] - k, c[0] + k, c[1] + k, user=True))
    if hair:
        rr = r - .75
        a, b = _E(c, rr, rr, 196), _E(c, rr, rr, 252)
        ic.hairline('M%s' % pt(a) + _arc(rr, rr, 0, 1, b), a[0], b[0], (.75, .15))


def torus(ic, c, rc, rt, mat='steel', hair=True, parts=('belly', 'crown')):
    """A horizontal torus on the dimetric lattice, c the centre of its centre-line circle (screen rx rc,
    ry rc/2) and rt the tube radius: the belly (curve), the crown (top) and the hole (deep, its far inner
    wall). parts lets a caller paint the belly and the crown separately (a plane through the equator goes
    between them). Returns {'outer': (c, rx, ry), 'hole': (c, rx, ry)}."""
    out = {'outer': (c, rc + rt, rc / 2 + rt)}
    if 'belly' in parts:
        ic.ellipse(c, rc + rt, rc / 2 + rt, ic.mat(mat, 'curve', c[0] - rc - rt, 0, c[0] + rc + rt, 0, user=True))
    if 'crown' in parts:
        cc = (c[0], c[1] - rt * .42)
        crx, cry = rc + rt * .62, rc / 2 + rt * .42
        ic.ellipse(cc, crx, cry, ic.mat(mat, 'top'))
        hc = (c[0], c[1] - rt * .5)
        hrx, hry = rc - rt * .78, max(rc / 2 - rt * .55, 1.35)
        ic.ellipse(hc, hrx, hry, ic.mat(mat, 'deep', 0, hc[1] - hry, 0, hc[1] + hry, user=True))
        if hair:
            a, b = _E(cc, crx - .3, cry - .3, 172), _E(cc, crx - .3, cry - .3, 108)
            ic.hairline('M%s' % pt(a) + _arc(crx - .3, cry - .3, 0, 0, b), a[0], b[0], (.75, .2))
        out['hole'] = (hc, hrx, hry)
    return out


def glass_box(ic, iso, o, size, mat='acc'):
    """A see-through box (a phantom, a new-in-place body, a scale target): every face takes the PANE ramp
    with glass opacity (SPEC 4). The faces are told apart by where each sits on one vertical ramp: the top at
    the light end, the lit face mid, the shade face at the dark end. Rounded silhouette, hairline on the lit
    top edges. Returns the Solid."""
    x, y, z = o
    a, b, h = size
    W = {'B': (x, y, z + h), 'R': (x + a, y, z + h), 'F': (x + a, y + b, z + h), 'L': (x, y + b, z + h),
         'Rb': (x + a, y, z), 'Fb': (x + a, y + b, z), 'Lb': (x, y + b, z)}
    P = {k: iso.p(*v) for k, v in W.items()}
    sil = ['B', 'R', 'Rb', 'Fb', 'Lb', 'L']
    S = Solid(P, sil, {k: R for k in sil})
    top_y, bot_y = P['B'][1], P['Fb'][1]
    span = bot_y - top_y

    def g(y0, y1):
        return ic.mat(mat, 'pane', 0, y0, 0, y1, user=True, opacity=GLASS)
    ic.fill(S.path(['F', 'R', 'Rb', 'Fb']), g(top_y - 2 * span, top_y - span * .2))
    ic.fill(S.path(['L', 'F', 'Fb', 'Lb']), g(P['L'][1] - span * .55, bot_y + span * .35))
    ic.fill(S.path(['B', 'R', 'F', 'L']), g(top_y + span * .55, top_y + span * 1.6))
    pts = [S.end('L'), P['F'], S.end('R')]
    ic.hairline(poly(pts, False), pts[0][0], pts[-1][0])
    return S


def glass_cyl(ic, c, rx, h, mat='steel'):
    """A see-through vertical cylinder (c = top centre): side and top in the glass pane ramp."""
    ry = rx / 2
    E = lambda th, dy=0.0: _E(c, rx, ry, th, dy)
    side = ('M%s' % pt(E(0)) + 'A%s %s 0 0 1 %s' % (rx, ry, pt(E(180))) + 'L%s' % pt(E(180, h))
            + 'A%s %s 0 0 0 %s' % (rx, ry, pt(E(0, h))) + 'Z')
    face(ic, side, mat, 'pane', x1=c[0] - rx, y1=0, x2=c[0] + rx, y2=0, user=True, opacity=GLASS)
    ic.ellipse(c, rx, ry, ic.mat(mat, 'pane', c[0] - rx, c[1] - ry, c[0] + rx, c[1] + ry, user=True,
                                 opacity=GLASS))
    a = E(178)
    ic.hairline('M%sA%s %s 0 0 0 %s' % (pt(a), rx, ry, pt(E(96))), a[0], E(96)[0], (.75, .2))


def edge_band(ic, S, a, b, into_top, into_side, mat='acc', k=1.75):
    """A SELECTED EDGE of a box (SPEC 6.1: a mark on a solid is material): an accent band straddling the
    edge between the top-face vertices a and b of Solid S, k wide on the top face (into_top: the screen unit
    vector from the edge into the top face) and k down the side face (into_side). A silhouette vertex keeps
    its rounding: the band follows the fillet there. Band ramp from the lit top strip to the side strip."""
    A, B = S.P[a], S.P[b]
    ta, tb = add(A, into_top, k), add(B, into_top, k)
    sa, sb = add(A, into_side, k), add(B, into_side, k)
    d = 'M%sL%s' % (pt(ta), pt(tb))
    d += ('Q%s %s' % (pt(B), pt(sb))) if b in S.R else 'L%sL%s' % (pt(B), pt(sb))
    d += 'L%s' % pt(sa)
    d += ('Q%s %sZ' % (pt(A), pt(ta))) if a in S.R else 'L%sZ' % pt(A)
    m = lerp(A, B, .5)
    g1, g2 = add(m, into_top, k * .9), add(m, into_side, k * .9)
    face(ic, d, mat, 'band', x1=g1[0], y1=g1[1], x2=g2[0], y2=g2[1], user=True)


def _area(p):
    return sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p))) / 2


def clip_poly(subject, clipper):
    """Sutherland-Hodgman: subject polygon clipped by a CONVEX clipper polygon (screen points). For the faces
    seen through an opening (shell, delete face)."""
    s = 1 if _area(clipper) > 0 else -1
    out = list(subject)
    n = len(clipper)
    for i in range(n):
        a, b = clipper[i], clipper[(i + 1) % n]
        inside = lambda p: s * ((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])) >= -1e-9

        def cut(p, q):
            d1 = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
            d2 = (b[0] - a[0]) * (q[1] - a[1]) - (b[1] - a[1]) * (q[0] - a[0])
            return lerp(p, q, d1 / (d1 - d2))
        inp, out = out, []
        for j in range(len(inp)):
            p, q = inp[j - 1], inp[j]
            if inside(q):
                if not inside(p):
                    out.append(cut(p, q))
                out.append(q)
            elif inside(p):
                out.append(cut(p, q))
        if not out:
            return []
    return out


def round_pts(pts, r=R, which=None, n=4):
    """A polygon with the corners in which (indices; all when None) filleted by r, as dense points (for
    clipping faces to a rounded silhouette)."""
    out = []
    m = len(pts)
    for i, V in enumerate(pts):
        if which is not None and i not in which:
            out.append(V)
            continue
        a, b = pts[i - 1], pts[(i + 1) % m]
        rr = min(r, math.dist(V, a) * .45, math.dist(V, b) * .45)
        p1, p2 = add(V, unit(V, a), rr), add(V, unit(V, b), rr)
        for k in range(n + 1):
            t = k / n
            out.append(((1 - t) ** 2 * p1[0] + 2 * t * (1 - t) * V[0] + t * t * p2[0],
                        (1 - t) ** 2 * p1[1] + 2 * t * (1 - t) * V[1] + t * t * p2[1]))
    return out


def _pip(p, P):
    x, y = p
    ins = False
    for i in range(len(P)):
        (x1, y1), (x2, y2) = P[i - 1], P[i]
        if (y1 > y) != (y2 > y) and x < (x2 - x1) * (y - y1) / (y2 - y1) + x1:
            ins = not ins
    return ins


def _dseg(p, a, b):
    ax, ay = b[0] - a[0], b[1] - a[1]
    L = ax * ax + ay * ay or 1e-9
    t = max(0, min(1, ((p[0] - a[0]) * ax + (p[1] - a[1]) * ay) / L))
    return math.hypot(p[0] - a[0] - t * ax, p[1] - a[1] - t * ay)


def _clear(p, polys, margin):
    for P in polys:
        if _pip(p, P) or min(_dseg(p, P[i - 1], P[i]) for i in range(len(P))) < margin:
            return False
    return True


def _simplify(run_):
    out = [run_[0]]
    for i in range(1, len(run_) - 1):
        a, b, c = out[-1], run_[i], run_[i + 1]
        if abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) > .02:
            out.append(b)
    out.append(run_[-1])
    return out


def clip_ink(pts, polys, margin=1.25, step=.08):
    """Ink on the ground that runs behind solids or panes (SPEC 6.1): the polyline pts, cut where it comes
    within margin of any polygon in polys (screen points). Returns a path of the visible runs."""
    samples = []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        n = max(1, int(math.dist(a, b) / step))
        samples += [lerp(a, b, j / n) for j in range(n)]
    samples.append(pts[-1])
    runs, cur = [], []
    for p in samples:
        if _clear(p, polys, margin):
            cur.append(p)
        elif cur:
            runs.append(cur)
            cur = []
    if cur:
        runs.append(cur)
    return ''.join(poly(_simplify(r), False) for r in runs if len(r) > 2 and math.dist(r[0], r[-1]) > .6)


def ink_clear(p, polys, margin=1.25):
    """True when a ground-ink point p is at least margin outside every polygon in polys."""
    return _clear(p, polys, margin)


def tube(ic, iso, path, r, mat='acc', cap_kind='lit', hair=True):
    """A round bar of radius r swept along a horizontal 3D path (list of world points, dense). The silhouette
    is exact for the parallel projection along (1, 1, 1): on each cross-section circle (normal = the path
    tangent) the two points whose surface normal is perpendicular to the view. The body takes the curve
    ramp across its mean direction (lit at the upper left); the far end is rounded off by its own section,
    and the near end shows its cap (the profile) when it faces the viewer. Returns (cap polygon, ends)."""
    secs = []
    for i, C in enumerate(path):
        a, b = path[max(i - 1, 0)], path[min(i + 1, len(path) - 1)]
        T = [b[k] - a[k] for k in range(3)]
        d = math.sqrt(sum(t * t for t in T))
        T = [t / d for t in T]
        n = [T[1], -T[0], 0.0]
        dn = math.hypot(n[0], n[1])
        n = [n[0] / dn, n[1] / dn, 0.0]
        secs.append((C, T, n))

    def sec_pt(C, n, phi):
        return iso.p(C[0] + r * math.cos(phi) * n[0], C[1] + r * math.cos(phi) * n[1], C[2] + r * math.sin(phi))

    side_a, side_b = [], []
    for C, T, n in secs:
        phi = math.atan(-(n[0] + n[1]))
        side_a.append((sec_pt(C, n, phi), phi))
        side_b.append((sec_pt(C, n, phi + math.pi), phi + math.pi))
    mid = len(secs) // 2
    if side_a[mid][0][1] > side_b[mid][0][1]:
        side_a, side_b = side_b, side_a

    def end_arc(k, lead):
        C, T, n = secs[k]
        f0 = side_a[k][1]
        ts = sub(iso.p(*[C[i] + T[i] for i in range(3)]), iso.p(*C))
        best = None
        for sgn in (1, -1):
            arcp = [sec_pt(C, n, f0 + sgn * math.pi * j / 16) for j in range(17)]
            m = arcp[8]
            score = (m[0] - iso.p(*C)[0]) * ts[0] + (m[1] - iso.p(*C)[1]) * ts[1]
            if best is None or (score > best[0]) == lead:
                best = (score, arcp)
        return best[1]
    lead_arc = end_arc(len(secs) - 1, True)
    tail_arc = end_arc(0, False)
    outline = [p for p, _ in side_a] + lead_arc[1:-1] + [p for p, _ in reversed(side_b)] + list(reversed(tail_arc))[1:-1]
    A, Bp = iso.p(*path[0]), iso.p(*path[-1])
    u = unit(A, Bp)
    nrm = (u[1], -u[0])
    if nrm[1] > 0 or (abs(nrm[1]) < 1e-9 and nrm[0] < 0):
        nrm = (-nrm[0], -nrm[1])
    allp = [p for p, _ in side_a + side_b]
    proj = [(p[0] * nrm[0] + p[1] * nrm[1]) for p in allp]
    c0 = lerp(A, Bp, .5)
    base = c0[0] * nrm[0] + c0[1] * nrm[1]
    hi, lo = max(proj) - base, min(proj) - base
    g1, g2 = add(c0, nrm, hi), add(c0, nrm, lo)
    face(ic, poly(outline), mat, 'curve', x1=g1[0], y1=g1[1], x2=g2[0], y2=g2[1], user=True)
    C, T, n = secs[-1]
    cap = [sec_pt(C, n, 2 * math.pi * j / 48) for j in range(48)]
    if sum(T[i] for i in range(3)) > 0:
        face(ic, poly(cap), mat, cap_kind)
        if hair:
            arcp = sorted(range(48), key=lambda j: cap[j][0] + cap[j][1])[:1][0]
            seg = [cap[(arcp + j) % 48] for j in range(-7, 8)]
            seg.sort(key=lambda p: p[0])
            ic.hairline(poly(seg, False), seg[0][0], seg[-1][0], (.75, .2))
    return cap, (A, Bp)


def helix_band(ic, c, rx, th0, th1, pitch, t, mat='acc', ry=None, front=True, back=True, inner='shade'):
    """A helical ribbon of height t on a vertical cylinder (c = centre at th0, screen; 90 = front), climbing
    pitch per turn: the coil, the thread. Back half-turns (the inside) in the inner kind, front half-turns in
    the cylinder's curve ramp. Returns the centre-line function y(th)."""
    ry = rx / 2 if ry is None else ry
    yc = lambda th: c[1] + ry * math.sin(math.radians(th)) - pitch * (th - th0) / 360.0
    xc = lambda th: c[0] + rx * math.cos(math.radians(th))
    cuts = [th0] + [k * 180 for k in range(int(th0 // 180) + 1, int(th1 // 180) + 1) if th0 < k * 180 < th1] + [th1]
    pieces = list(zip(cuts[:-1], cuts[1:]))

    def piece(a, b):
        n = max(8, int((b - a) / 5))
        ths = [a + (b - a) * i / n for i in range(n + 1)]
        up = [(xc(h), yc(h) - t / 2) for h in ths]
        dn = [(xc(h), yc(h) + t / 2) for h in reversed(ths)]
        return poly(up + dn)
    is_front = lambda a, b: math.sin(math.radians((a + b) / 2)) > 0
    if back:
        for a, b in pieces:
            if not is_front(a, b):
                face(ic, piece(a, b), mat, inner)
    if front:
        for a, b in pieces:
            if is_front(a, b):
                face(ic, piece(a, b), mat, 'curve', x1=c[0] - rx, y1=0, x2=c[0] + rx, y2=0, user=True)
    return yc


# ------------------------------------------------------------------------------------------- runner
def run(drawers, small=None, root=DESIGN, argv=None):
    """Draw every icon of a family generator. drawers: {'MAP.key': fn(ic)}; small: {'MAP.key': fn(ic)} for
    the 18 px masters (.sm.svg). --out DIR writes elsewhere (e.g. a scratch dir), --only KEY,KEY limits."""
    argv = sys.argv[1:] if argv is None else argv
    only = None
    if '--out' in argv:
        root = argv[argv.index('--out') + 1]
    if '--only' in argv:
        only = set(argv[argv.index('--only') + 1].split(','))
    written = []
    for table, sm in ((drawers, False), (small or {}, True)):
        for ref, fn in table.items():
            if only and ref not in only:
                continue
            ic = Icon(ref, sm)
            fn(ic)
            written.append(ic.write(root))
    print('wrote %d SVG(s) under %s' % (len(written), root))
    return written
