#!/usr/bin/env python3
"""Family D of SPEC v2 "Modern Crisp": work features (WF), the plane / axis / point methods (PL, AX, PN),
the 3D feature patterns (PT) and the view styles (VW). Drawn through tools/icon_redesign/lib/crisp.py.

    python3 tools/icon_redesign/families/D.py            # writes design/icons/<MAP>/<key>.svg
    python3 tools/icon_redesign/families/D.py --out DIR  # writes DIR/<MAP>/<key>.svg instead

One rule runs through all 30 PL / AX / PN methods (SPEC 5.3, as WF.plane / WF.axis draw it):
  * the RESULT (the new plane, axis or point) is accent material: pane, rod, disc;
  * every REFERENCE it is built from is steel when it is an object (a body, a pane, an axis rod, a point on
    material: a steel bead) and plain ink when it lies on the ground (an INK line or curve, an INK dot).
So a steel bead on an accent pane is "the plane goes through this point", a steel rod through an accent
pane is "normal to this axis", an accent rod between steel panes is "where they intersect".

Local primitives (candidates for the library): sphere(), torus(), vase() (a body of revolution from a
profile), clip_ink() (ink on the ground, kept 1 u clear of the solids it runs behind), bead().
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
sys.path.insert(0, HERE)
from crisp import (INK, SEC, Iso, Solid, R, add, arc_arrow, arrow, bore, box, cylinder, dot, face,  # noqa: E402
                   iso_plane, lerp, line, mat_dot, plane, poly, pt, rod, run, solid, unit, work_point,
                   _arc, _E)
from ref import waxis, wplane  # noqa: E402


# ------------------------------------------------------------------------------------------- local primitives
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
    ry rc/2) and rt the tube radius. Drawn as three matte faces: the belly (curve), the crown (top) and the
    hole (deep, its far inner wall). parts lets a caller paint the belly and the crown separately (a plane
    through the equator goes between them)."""
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


def _catmull(pts, n=10):
    out = []
    P = [pts[0]] + list(pts) + [pts[-1]]
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        for j in range(n):
            t = j / n
            t2, t3 = t * t, t * t * t
            out.append(tuple(.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                                   + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3) for k in range(2)))
    out.append(P[-2])
    return out


def vase(ic, cx, top, prof, mat='steel', hair=True):
    """A vertical body of revolution: prof = [(radius, depth below the lip), ...] from the lip down to the
    foot (screen units; every circle is a 2:1 ellipse). Side in curve material, the opening at the lip in
    the deep ramp, the hairline on the front-left lip. Returns the lip and foot centres and radii."""
    side = _catmull(prof)
    r0, d1 = prof[0][0], prof[-1]
    right = [(cx + r, top + d) for r, d in side]
    left = [(cx - r, top + d) for r, d in reversed(side)]
    rb, yb = d1[0], top + d1[1]
    d = 'M' + 'L'.join(pt(p) for p in right)
    d += _arc(rb, rb / 2, 0, 1, (cx - rb, yb))           # the front of the foot rim
    d += 'L' + 'L'.join(pt(p) for p in left[1:])
    d += _arc(r0, r0 / 2, 0, 1, (cx + r0, top)) + 'Z'    # the back of the lip
    rmax = max(r for r, _ in prof)
    face(ic, d, mat, 'curve', x1=cx - rmax, y1=0, x2=cx + rmax, y2=0, user=True)
    ic.ellipse((cx, top), r0, r0 / 2, ic.mat(mat, 'deep', 0, top - r0 / 2, 0, top + r0 / 2, user=True))
    if hair:
        a, b = _E((cx, top), r0, r0 / 2, 176), _E((cx, top), r0, r0 / 2, 100)
        ic.hairline('M%s' % pt(a) + _arc(r0, r0 / 2, 0, 0, b), a[0], b[0], (.75, .2))
    return {'lip': (cx, top), 'r0': r0, 'foot': (cx, yb), 'rb': rb}


def bead(ic, p, r=2.1, mat='steel'):
    """A reference point that sits ON material (a pane, a rod): a steel disc. The accent disc (mat_dot) is
    kept for the point a tool creates."""
    mat_dot(ic, p, r, mat)


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


def _simplify(run):
    out = [run[0]]
    for i in range(1, len(run) - 1):
        a, b, c = out[-1], run[i], run[i + 1]
        if abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) > .02:
            out.append(b)
    out.append(run[-1])
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


def ell_poly(c, rx, ry, n=48):
    return [_E(c, rx, ry, 360 * i / n) for i in range(n)]


def sheet(cx, cy, w, h, lean=3.5):
    """The stylised plane of WF.plane (horizontal top and bottom edges, slanted sides), centred at (cx, cy):
    width w along the edges, height h, the top edge shifted right by lean."""
    return [(cx - w / 2 - lean / 2, cy + h / 2), (cx - w / 2 + lean / 2, cy - h / 2),
            (cx + w / 2 + lean / 2, cy - h / 2), (cx + w / 2 - lean / 2, cy + h / 2)]


def vert_pane(iso, o, u, h, z0=0.0):
    """Screen points of a vertical pane: world base corner o, horizontal world vector u, height h."""
    a = (o[0], o[1], z0)
    b = (o[0] + u[0], o[1] + u[1], z0)
    return [iso.p(*a), iso.p(*b), iso.p(b[0], b[1], z0 + h), iso.p(a[0], a[1], z0 + h)]


# ------------------------------------------------------------------------------------------- WF
def wpoint(ic):
    iso = Iso(14, 13)
    s = box(ic, iso, (0, 0, 0), (11, 11, 9), 'steel')
    mat_dot(ic, s.P['F'])


def ucs(ic, panes=True, w=1.25):
    o = (14, 15)
    X, Y, Z = (1, .5), (-1, .5), (0, -1)
    k = 1.0
    P = lambda a, b: (o[0] + (a[0] + b[0]) * k, o[1] + (a[1] + b[1]) * k)
    s0, s1 = 2.6, 6.2
    sc = lambda u, v, a, b: (o[0] + u[0] * a + v[0] * b, o[1] + u[1] * a + v[1] * b)
    for u, v in ((X, Z), (Y, Z), (X, Y)) if panes else ():
        plane(ic, [sc(u, v, s0, s0), sc(u, v, s1, s0), sc(u, v, s1, s1), sc(u, v, s0, s1)], 'acc',
              r=.6, hair=False)
    for d, L in ((Z, 12), (X, 10.5), (Y, 10.5)):
        arrow(ic, (o[0] + d[0] * 3.4, o[1] + d[1] * 3.4), (o[0] + d[0] * L, o[1] + d[1] * L), w=w)
    mat_dot(ic, o)


# ------------------------------------------------------------------------------------------- PL
def pl_offset(ic):
    iso = Iso(15.5, 14.5)
    a = 9
    box(ic, iso, (0, 0, 0), (a, a, 3), 'steel')
    iso_plane(ic, iso, (0, 0, 10), (a, 0, 0), (0, a, 0), 'acc')
    x = iso.p(0, a, 0)[0] - 2.75
    arrow(ic, (x, iso.p(0, a, 3)[1]), (x, iso.p(0, a, 10)[1] + .25))


def pl_parallelpt(ic):
    iso = Iso(14, 14.5)
    a = 10
    box(ic, iso, (0, 0, 0), (a, a, 3), 'steel')
    iso_plane(ic, iso, (0, 0, 9.5), (a, 0, 0), (0, a, 0), 'acc')
    bead(ic, iso.p(a * .62, a * .62, 9.5))


def pl_midplane2(ic):
    iso = Iso(11, 12)
    box(ic, iso, (0, 0, 0), (4, 9, 8), 'steel')
    iso_plane(ic, iso, (7.5, -1.75, -1.25), (0, 12.5, 0), (0, 0, 10.75), 'acc', glass=True)
    box(ic, iso, (11, 0, 0), (4, 9, 8), 'steel')


def pl_midtorus(ic):
    c = (14, 14.5)
    torus(ic, c, 6.2, 3.1, parts=('belly',))
    plane(ic, sheet(14, c[1] + .75, 21.5, 9, 4.5), 'acc', glass=True)
    torus(ic, c, 6.2, 3.1, parts=('crown',))


def pl_angleedge(ic):
    # hinge = the back-right top edge; the pane opens up and back about it like a lid. The INK arc arrow
    # swings from the top face (flat) up to the pane, in the open wedge beside it, off the material.
    iso = Iso(9.5, 18.25)
    a, b, h = 8.5, 7, 6
    box(ic, iso, (0, 0, 0), (a, b, h), 'steel')
    th = math.radians(70)
    L = 8.5
    v = (0, -math.cos(th) * L, math.sin(th) * L)
    W = [(-.25, 0, h), (a, 0, h), (a, v[1], h + v[2]), (-.25, v[1], h + v[2])]
    plane(ic, [iso.p(*w) for w in W], 'acc')
    hp = iso.p(a, 0, h)
    ext = iso.p(a, -6, h)
    pv = iso.p(a, v[1], h + v[2])
    a0 = math.degrees(math.atan2(ext[1] - hp[1], ext[0] - hp[0]))
    a1 = math.degrees(math.atan2(pv[1] - hp[1], pv[0] - hp[0]))
    rr = 8.25
    arc_arrow(ic, hp, rr, rr, a0 + 28, a1 + 10, INK)


def pl_threepts(ic):
    P = sheet(14, 14, 18, 14, 7)
    plane(ic, P)
    for p in ((8.6, 18.2), (19.6, 18.2), (16.2, 9.6)):
        bead(ic, p)


def pl_twoedges(ic):
    # the plane through the top back edge and the bottom front edge: the half behind it (steel), the glass
    # pane, the half in front of it (steel). The cut shows as the diagonal on the shade face, and the pane
    # leaves the block along both edges.
    iso = Iso(14, 13.25)
    a, b, h = 10, 8.5, 8
    wedge_back = {'B': (0, 0, h), 'R': (a, 0, h), 'Bb': (0, 0, 0), 'Rb': (a, 0, 0), 'Lb': (0, b, 0), 'Fb': (a, b, 0)}
    solid(ic, iso, wedge_back, {'s': ['B', 'R', 'Fb', 'Lb'], 'r': ['R', 'Rb', 'Fb'], 'l': ['B', 'Bb', 'Lb'],
                                'k': ['B', 'R', 'Rb', 'Bb'], 'd': ['Bb', 'Rb', 'Fb', 'Lb']}, 'steel', hair=False)
    n = math.hypot(b, h)
    e = 2.75
    dy, dz = b / n * e, -h / n * e
    W = [(-1.25, -dy, h - dz), (a + 1.25, -dy, h - dz), (a + 1.25, b + dy, dz), (-1.25, b + dy, dz)]
    plane(ic, [iso.p(*w) for w in W], 'acc', glass=True)
    wedge_front = {'B': (0, 0, h), 'R': (a, 0, h), 'L': (0, b, h), 'F': (a, b, h), 'Lb': (0, b, 0), 'Fb': (a, b, 0)}
    solid(ic, iso, wedge_front, {'top': ['B', 'R', 'F', 'L'], 'lit': ['L', 'F', 'Fb', 'Lb'], 'r': ['R', 'F', 'Fb'],
                                 'l': ['B', 'L', 'Lb'], 's': ['B', 'R', 'Fb', 'Lb']}, 'steel')


def _cyl_tangent(iso_c, rx, h, th, ext=(6.5, 6.5), over=1.75):
    """Screen points of a vertical pane tangent to a cylinder (top centre iso_c, rim rx, height h) along
    the side line at angle th: its horizontal edges follow the rim tangent there."""
    c = iso_c
    p = _E(c, rx, rx / 2, th)
    t = unit((0, 0), (-rx * math.sin(math.radians(th)), rx / 2 * math.cos(math.radians(th))))
    if t[0] < 0:
        t = (-t[0], -t[1])
    top, bot = (p[0], p[1] - over), (p[0], p[1] + h + over)
    return [add(top, t, -ext[0]), add(top, t, ext[1]), add(bot, t, ext[1]), add(bot, t, -ext[0])], p


def pl_tansurfedge(ic):
    c, rx, h = (15.5, 8.5), 7.5, 11
    cylinder(ic, c, rx, h, 'steel')
    P, p = _cyl_tangent(c, rx, h, 135, (6.75, 6.75))
    plane(ic, P, 'acc', glass=True)
    w = .7
    face(ic, poly([(p[0] - w, p[1]), (p[0] + w, p[1] + .1), (p[0] + w, p[1] + h + .1), (p[0] - w, p[1] + h)]),
         'acc', 'shade')


def pl_tansurfpt(ic):
    c, r = (11.5, 13.0), 8.5
    sphere(ic, c, r)
    p = add(c, (r * .64, r * .5))
    t = (-1, .5)
    tn = unit((0, 0), t)
    top, bot = (p[0], p[1] - 7.25), (p[0], p[1] + 7.25)
    P = [add(top, tn, 6), add(top, tn, -6.5), add(bot, tn, -6.5), add(bot, tn, 6)]
    plane(ic, P, 'acc', glass=True)
    bead(ic, p)


def pl_tanparallel(ic):
    c, rx, h = (13.5, 9.5), 6.5, 10
    Pr, _ = _cyl_tangent(c, rx, h, -45 + 180 + 180, (5, 5))       # dummy to get the tangent direction
    t = unit(Pr[0], Pr[1])
    q = _E(c, rx, rx / 2, -45)
    q = add(q, (1, -.5), 2.2)
    top, bot = (q[0], q[1] - 1.5), (q[0], q[1] + h + 1.5)
    ref = [add(top, t, -5.5), add(top, t, 5.5), add(bot, t, 5.5), add(bot, t, -5.5)]
    plane(ic, ref, 'steel')
    cylinder(ic, c, rx, h, 'steel')
    P, p = _cyl_tangent(c, rx, h, 135, (6, 6))
    plane(ic, P, 'acc', glass=True)


def pl_normalaxis(ic):
    S = sheet(14, 15.5, 17, 9, 6)
    cy = 15.5
    rod(ic, (14, cy), (14, 26), r=1.0, mat='steel', caps=(False, True))
    plane(ic, S, 'acc')
    rod(ic, (14, cy), (14, 2), r=1.0, mat='steel', caps=(False, True), socket=True)


def pl_normalcurve(ic):
    iso = Iso(12.5, 16.5)
    P = vert_pane(iso, (-5.5, 0), (11, 0), 10, -.5)
    curve = [iso.p(1.6 * math.sin(y * .22), y, 0) for y in [i * .5 for i in range(-27, 21)]]
    ic.stroke(clip_ink(curve, [P], 1.25), INK, 1.5)
    plane(ic, P, 'acc')


# ------------------------------------------------------------------------------------------- AX
def ax_onedge(ic):
    iso = Iso(15, 12.5)
    a, b, h = 10, 10, 8
    box(ic, iso, (0, 0, 0), (a, b, h), 'steel')
    rod(ic, iso.p(-2.75, b, h), iso.p(a + 2.75, b, h), r=1.0)


def ax_axparallel(ic):
    line(ic, [(3.5, 17.5), (17, 24.25)])
    a, b = (8.5, 4.25), (24.5, 12.25)
    rod(ic, a, b, r=1.05)
    bead(ic, lerp(a, b, .45))


def ax_twopts(ic):
    a, b = (4.5, 23), (23.5, 5)
    rod(ic, a, b, r=1.05)
    bead(ic, lerp(a, b, .27))
    bead(ic, lerp(a, b, .73))


def ax_intersect(ic):
    # two standing steel panes crossing (planes x=0 and y=0, as PN.int3planes stands them); the accent axis
    # is their common line, drawn last (it lies in both). Back wings, front wings, the axis.
    iso = Iso(14, 14.5)
    f, k, z0, z1 = 10.0, 5.5, -4.5, 5.0
    vp = lambda o, u: vert_pane(iso, o, u, z1 - z0, z0)
    plane(ic, vp((-k, 0), (k, 0)), 'steel', r=.8)
    plane(ic, vp((0, -k), (0, k)), 'steel', r=.8)
    plane(ic, vp((0, 0), (f, 0)), 'steel', r=.8)
    plane(ic, vp((0, 0), (0, f)), 'steel', r=.8)
    rod(ic, iso.p(0, 0, z1 + 4.0), iso.p(0, 0, z0 - 3.5), r=1.05)


def ax_normalplane(ic):
    iso = Iso(14, 14.25)
    a = 11
    box(ic, iso, (0, 0, 0), (a, a, 4), 'steel')
    c = iso.p(a / 2, a / 2, 4)
    rod(ic, c, (c[0], 2.0), r=1.0, caps=(False, True), socket=True)


def ax_centeredge(ic):
    iso = Iso(14, 12.5)
    a = 11
    s = box(ic, iso, (0, 0, 0), (a, a, 5), 'steel')
    c = iso.p(a / 2, a / 2, 5)
    rx = 4.6
    bore(ic, c, rx, mat='steel')
    rod(ic, (c[0], c[1] + rx / 2 - .2), (c[0], 2.0), r=1.0, caps=(False, True))
    fb = s.P['Fb']
    rod(ic, (fb[0], fb[1] - .3), (fb[0], 26.0), r=1.0, caps=(False, True))


def ax_revolved(ic):
    v = vase(ic, 14, 7.5, [(4.6, 0), (3.6, 2.6), (6.6, 8.2), (7.6, 11.5), (5.0, 15.0), (5.4, 16.2)])
    cx, top = v['lip']
    rod(ic, (cx, top + .2), (cx, 1.75), r=1.0, caps=(False, True))
    fy = v['foot'][1] + v['rb'] / 2
    rod(ic, (cx, fy - .3), (cx, 26.25), r=1.0, caps=(False, True))


# ------------------------------------------------------------------------------------------- PN
def pn_grounded(ic):
    c = (14, 8.5)
    work_point(ic, c)
    line(ic, [(14, 14.75), (14, 18.75)])
    for y, w in ((18.75, 8), (22, 5.5), (25.25, 3)):
        line(ic, [(14 - w, y), (14 + w, y)])


def pn_vertex(ic):
    iso = Iso(14, 15.5)
    a, h = 10.5, 12.5
    W = {'b0': (0, 0, 0), 'b1': (a, 0, 0), 'b2': (a, a, 0), 'b3': (0, a, 0), 'ap': (a / 2, a / 2, h)}
    faces = {'s0': ['b0', 'b1', 'ap'], 's1': ['b1', 'b2', 'ap'], 's2': ['b2', 'b3', 'ap'], 's3': ['b3', 'b0', 'ap'],
             'bot': ['b0', 'b1', 'b2', 'b3']}
    s = solid(ic, iso, W, faces, 'steel')
    mat_dot(ic, s.P['ap'])


def _quad(ic, pts, mat, glass, rounded):
    """A pane quadrant: rounded (1.0) only at the corners named in rounded (its outer corners)."""
    P = {str(i): p for i, p in enumerate(pts)}
    S = Solid(P, list(P), {str(i): R + .4 for i in rounded})
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    ic.fill(S.outline(), ic.mat(mat, 'pane', min(xs), min(ys), max(xs), max(ys), user=True,
                                opacity=(.85, .70) if glass else None))


def _quad(ic, pts, mat, glass, rounded):
    """A pane quadrant: rounded (1.0) only at the corners named in rounded (its outer corners)."""
    P = {str(i): p for i, p in enumerate(pts)}
    S = Solid(P, list(P), {str(i): R + .4 for i in rounded})
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    ic.fill(S.outline(), ic.mat(mat, 'pane', min(xs), min(ys), max(xs), max(ys), user=True,
                                opacity=(.85, .70) if glass else None))


def pn_int3planes(ic):
    # three planes x=0, y=0 (standing) and z=0 (lying) meeting in one point: the vertical pair crossing,
    # standing on the horizontal one; drawn as glass quadrants back to front
    iso = Iso(14, 16)
    s, hz = 6.5, 9
    Q = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            Q.append(((sx * s / 2, sy * s / 2, -.01), [(0, 0, 0), (sx * s, 0, 0), (sx * s, sy * s, 0), (0, sy * s, 0)]))
    for sx in (-1, 1):
        Q.append(((sx * s / 2, 0, hz / 2), [(0, 0, 0), (sx * s, 0, 0), (sx * s, 0, hz), (0, 0, hz)]))
    for sy in (-1, 1):
        Q.append(((0, sy * s / 2, hz / 2), [(0, 0, 0), (0, sy * s, 0), (0, sy * s, hz), (0, 0, hz)]))
    Q.sort(key=lambda q: q[0][0] + q[0][1] + .3 * q[0][2])
    for _, W in Q:
        _quad(ic, [iso.p(*w) for w in W], 'steel', True, (1, 2, 3))
    mat_dot(ic, iso.p(0, 0, 0))


def pn_int2lines(ic):
    c = (14, 14)
    for far in ((3, 8.5), (25, 19.5), (9.5, 25.5), (18.5, 2.5)):
        line(ic, [far, add(c, unit(c, far), 6.0)])
    work_point(ic, c)


def pn_intplaneline(ic):
    S = sheet(14, 16, 18, 9.5, 6)
    c = (14, 16)
    d = unit((0, 0), (.42, -1))
    a, b = add(c, d, 14.25), add(c, d, -11.25)
    ic.stroke(clip_ink([a, b], [S], 1.25), INK, 1.5)
    plane(ic, S, 'steel', glass=False)
    mat_dot(ic, c)


def pn_centerloop(ic):
    iso = Iso(14, 12)
    a = 11.5
    box(ic, iso, (0, 0, 0), (a, a, 6), 'steel')
    c = iso.p(a / 2, a / 2, 6)
    bore(ic, c, 5.0, mat='steel')
    mat_dot(ic, (c[0], c[1] + .2))


def pn_centertorus(ic):
    t = torus(ic, (14, 15), 6.6, 3.0)
    hc, hrx, hry = t['hole']
    mat_dot(ic, (hc[0], hc[1] + .3), 2.3)


def pn_centersphere(ic):
    sphere(ic, (14, 14), 10.5)
    mat_dot(ic, (14, 14))


# ------------------------------------------------------------------------------------------- PT
def _cube(ic, iso, o, a, mat, k=1.05):
    return box(ic, iso, (o[0], o[1], 0), (a, a, a * k), mat)


def pt_rect(ic, a=4.6, sp=7.0, arrows=True, oy=11):
    # 2 x 2 grid, the first instance (accent) at the back; the two pattern directions as INK arrows running
    # from it over the two back rows, clear of the cubes
    iso = Iso(14, oy)
    cells = sorted(((i, j) for i in range(2) for j in range(2)), key=lambda q: q[0] + q[1])
    for i, j in cells:
        _cube(ic, iso, (i * sp, j * sp), a, 'acc' if (i, j) == (0, 0) else 'steel')
    top = iso.p(0, 0, a * 1.05)
    for d in ((1, .5), (-1, .5)) if arrows else ():
        st = add(top, (d[0] * 2.2, -3.0))
        arrow(ic, st, add(st, d, 10.6))




def pt_circ(ic, n=6, a=3.6, rr=6.4):
    # instances on a ring round a vertical steel axis; the ring is set with instances at its left and right
    # extremes, so its 2:1 ellipse reads as a ring, not as rows; the first instance (front) is the accent
    iso = Iso(14, 12.75)
    items = [(0.0, 'rod', None)]
    for k in range(n):
        th = math.radians(-45 + 360 * k / n)
        x, y = rr * math.cos(th), rr * math.sin(th)
        items.append((x + y, k, (x - a / 2, y - a / 2)))
    for depth, k, o in sorted(items, key=lambda q: q[0]):
        if k == 'rod':
            rod(ic, iso.p(0, 0, 9.5), iso.p(0, 0, -3.25), r=1.0, mat='steel')
        else:
            _cube(ic, iso, o, a, 'acc' if k == 2 else 'steel', .8)


def pt_sketch(ic, a=4.4):
    # instances stand behind INK sketch points: each cube's front corner points at its dot on the ground
    iso = Iso(14.75, 8.75)
    spots = [(-7, 2.0), (3.25, -4.0), (3.5, 5.25)]
    order = sorted(range(3), key=lambda i: spots[i][0] + spots[i][1])
    for i in order:
        x, y = spots[i]
        s = _cube(ic, iso, (x, y), a, 'acc' if i == 0 else 'steel')
        fb = s.P['Fb']
        dot(ic, (fb[0], fb[1] + 3.1), 'ink')


def _reflect(W, n):
    k = math.sqrt(sum(c * c for c in n))
    n = [c / k for c in n]
    return {name: tuple(w[i] - 2 * sum(w[j] * n[j] for j in range(3)) * n[i] for i in range(3)) for name, w in W.items()}


def pt_mirror(ic):
    # a mirror plane through the z axis, nearly facing the viewer; the original (accent ramp) in front of it,
    # its reflection (steel) behind, seen through the steel glass pane
    iso = Iso(13.25, 14)
    n = (-.42, 1, 0)
    base = [(-2.6, 2.0), (4.0, 4.75), (2.2, 9.0), (-4.4, 6.25)]
    W, faces = {}, {}
    hs = [9, 9, 3.5, 3.5]
    for i, (x, y) in enumerate(base):
        W['b%d' % i], W['t%d' % i] = (x, y, -4.5), (x, y, -4.5 + hs[i])
    faces = {'top': ['t0', 't1', 't2', 't3'], 'bot': ['b0', 'b1', 'b2', 'b3']}
    for i in range(4):
        j = (i + 1) % 4
        faces['s%d' % i] = ['b%d' % i, 'b%d' % j, 't%d' % j, 't%d' % i]
    solid(ic, iso, _reflect(W, n), faces, 'steel')
    d = unit((0, 0), (1, .42))
    o = (-d[0] * 6.75, -d[1] * 6.75, -6)
    iso_plane(ic, iso, o, (d[0] * 13.5, d[1] * 13.5, 0), (0, 0, 12.5), 'steel', glass=True)
    solid(ic, iso, W, faces, 'acc')


# ------------------------------------------------------------------------------------------- VW
def vw_shaded(ic):
    box(ic, Iso(14, 14.5), (0, 0, 0), (10, 10, 11), 'steel')


def vw_rendered(ic):
    sphere(ic, (14, 14), 10.5, 'acc')


def vw_section(ic):
    # a cutaway: the front-right quarter of the steel block is removed; the two cut faces are the accent
    iso = Iso(14, 13.5)
    a, b, h = 11, 11, 10
    m, n = 5, 5.5                  # the notch: x > m and y > n are gone
    P = {k: iso.p(*w) for k, w in {
        'B': (0, 0, h), 'R': (a, 0, h), 'Rn': (a, n, h), 'C': (m, n, h), 'Fm': (m, b, h), 'L': (0, b, h),
        'Rb': (a, 0, 0), 'Rnb': (a, n, 0), 'Cb': (m, n, 0), 'Fmb': (m, b, 0), 'Lb': (0, b, 0)}.items()}
    sil = ['B', 'R', 'Rn', 'Rnb', 'Cb', 'Fmb', 'Lb', 'L']
    S = Solid(P, sil, {k: R for k in sil})
    face(ic, S.outline(), 'steel', 'shade')
    face(ic, S.path(['L', 'Fm', 'Fmb', 'Lb']), 'steel', 'lit')
    face(ic, S.path(['R', 'Rn', 'Rnb', 'Rb']), 'steel', 'shade')
    face(ic, S.path(['C', 'Rn', 'Rnb', 'Cb']), 'acc', 'lit')
    face(ic, S.path(['C', 'Fm', 'Fmb', 'Cb']), 'acc', 'shade')
    face(ic, S.path(['B', 'R', 'Rn', 'C', 'Fm', 'L']), 'steel', 'top')
    hl = [S.end('L'), P['Fm'], P['C'], P['Rn'], S.end('R')]
    ic.hairline(poly([S.end('L'), P['Fm']], False), hl[0][0], hl[1][0])
    ic.hairline(poly([P['Rn'], S.end('R')], False), P['Rn'][0], S.end('R')[0])


def vw_engine(ic):
    c, r = (16, 18.5), 7.5
    sphere(ic, c, r)
    hit = add(c, unit(c, (12, 5)), r + 1.6)
    L = (4.5, 4.5)
    line(ic, [add(L, unit(L, hit), 3.6), hit], INK, 1.25)
    arrow(ic, hit, (24.5, 3.5))
    dot(ic, L, 'acc')


def vw_floor(ic, n=3):
    iso = Iso(14, 7.5)
    S = 11
    s = box(ic, iso, (2, 2, 0), (5.5, 5.5, 7.5), 'steel')
    sil = [s.P[v] for v in s.sil]
    d = ''
    for i in range(n + 1):
        t = S * i / n
        d += clip_ink([iso.p(t, 0, 0), iso.p(t, S, 0)], [sil], 1.1)
        d += clip_ink([iso.p(0, t, 0), iso.p(S, t, 0)], [sil], 1.1)
    ic.stroke(d, SEC, 1.25)


DRAW = {
    'WF.point': wpoint, 'WF.ucs': ucs,
    'PL.plane': wplane, 'PL.offset': pl_offset, 'PL.parallelpt': pl_parallelpt, 'PL.midplane2': pl_midplane2,
    'PL.midtorus': pl_midtorus, 'PL.angleedge': pl_angleedge, 'PL.threepts': pl_threepts,
    'PL.twoedges': pl_twoedges, 'PL.tansurfedge': pl_tansurfedge, 'PL.tansurfpt': pl_tansurfpt,
    'PL.tanparallel': pl_tanparallel, 'PL.normalaxis': pl_normalaxis, 'PL.normalcurve': pl_normalcurve,
    'AX.axis': waxis, 'AX.onedge': ax_onedge, 'AX.axparallel': ax_axparallel, 'AX.twopts': ax_twopts,
    'AX.intersect': ax_intersect, 'AX.normalplane': ax_normalplane, 'AX.centeredge': ax_centeredge,
    'AX.revolved': ax_revolved,
    'PN.point': wpoint, 'PN.grounded': pn_grounded, 'PN.vertex': pn_vertex, 'PN.int3planes': pn_int3planes,
    'PN.int2lines': pn_int2lines, 'PN.intplaneline': pn_intplaneline, 'PN.centerloop': pn_centerloop,
    'PN.centertorus': pn_centertorus, 'PN.centersphere': pn_centersphere,
    'PT.rect': pt_rect, 'PT.circ': pt_circ, 'PT.sketch': pt_sketch, 'PT.mirror': pt_mirror,
    'VW.shaded': vw_shaded, 'VW.rendered': vw_rendered, 'VW.section': vw_section, 'VW.engine': vw_engine,
    'VW.floor': vw_floor,
}
def _sm(fn, **kw):
    """An 18 px master (SPEC 2.4): the same drawing without the hairline, with the given simplifications."""
    def draw(ic):
        ic.hairline = lambda *a, **k: None
        fn(ic, **kw)
    return draw


SMALL = {
    'WF.ucs': _sm(ucs, panes=False, w=1.5),                 # seven parts: drop the panes, bolder arrows
    'PT.rect': _sm(pt_rect, a=5.2, sp=7.0, arrows=False, oy=8.5),   # four solids: no arrows, bigger cubes
    'PT.circ': _sm(pt_circ, n=6, a=4.0, rr=6.1),            # seven parts: bigger instances
    'PT.sketch': _sm(pt_sketch),                            # three solids plus ink
    'VW.floor': _sm(vw_floor, n=2),                         # grid gaps: two cells
}

if __name__ == '__main__':
    run(DRAW, SMALL)
