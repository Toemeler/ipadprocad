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

Shared motifs come from the library (sphere, torus, bead, clip_ink); local: vase() (a body of revolution
from a profile), sheet(), vert_pane(), _quad().
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
sys.path.insert(0, HERE)
from crisp import (ACC, INK, SEC, Iso, Solid, R, add, arc_arrow, arc_arrow_iso, arrow, bead, bore, box,  # noqa: E402
                   clip_ink, cylinder, dot, face, iso_plane, lerp, line, mat_dot, plane, poly, pt, rod, run,
                   solid, sphere, sub, torus, unit, work_point, _arc, _E)
from ref import waxis, wplane  # noqa: E402


# ------------------------------------------------------------------------------------------- local primitives
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
    # the plane at an angle to a face, about an edge: a steel block, the accent pane hinged on its top back
    # edge and swung up out of the top face's plane. The shared rotation arrow turns in the pane's own
    # plane of rotation (y-z, about the hinge), just beyond the block's right end, on the ground: from the
    # face's plane up to the pane
    iso = Iso(8.25, 18.0)
    a, b, h = 8.0, 7.0, 5.0
    box(ic, iso, (0, 0, 0), (a, b, h), 'steel')
    th = math.radians(64)
    L = 8.25
    v = (0, -math.cos(th) * L, math.sin(th) * L)
    W = [(-.25, 0, h), (a, 0, h), (a, v[1], h + v[2]), (-.25, v[1], h + v[2])]
    plane(ic, [iso.p(*w) for w in W], 'acc')
    arc_arrow_iso(ic, iso, (a + 1.75, 0, h), (0, -1, 0), (0, 0, 1), 7.5, -28, 57)


def pl_threepts(ic):
    P = sheet(14, 14, 18, 14, 7)
    plane(ic, P)
    for p in ((8.6, 18.2), (19.6, 18.2), (16.2, 9.6)):
        bead(ic, p)


def pl_twoedges(ic):
    # the plane through two opposite edges of a block (the top back-left edge and the bottom front-right
    # edge): it runs inside the solid, so only the two accent flaps beyond those edges show, one up and
    # back, one down and forward, each leaving the block exactly along its edge
    iso = Iso(13.5, 13.25)
    a, b, h = 9.5, 9.0, 7.5
    n = math.hypot(a, h)
    e = 3.75
    dx, dz = a / n * e, h / n * e
    W = [(-dx, 0, h + dz), (-dx, b, h + dz), (a + dx, b, -dz), (a + dx, 0, -dz)]
    plane(ic, [iso.p(*w) for w in W], 'acc')
    box(ic, iso, (0, 0, 0), (a, b, h), 'steel')


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
    # an INK curve on the ground running through an accent pane that stands normal to it; where it pierces
    # the pane, a steel bead (a reference point on material)
    iso = Iso(13.5, 16.75)
    P = vert_pane(iso, (-6.5, 0), (13, 0), 12.5, -1.25)
    curve = [iso.p(2.0 * math.sin(y * .2), y, 0) for y in [i * .5 for i in range(-25, 22)]]
    ic.stroke(clip_ink(curve, [P], 1.25), INK, 1.5)
    plane(ic, P, 'acc')
    bead(ic, iso.p(0, 0, 0))


# ------------------------------------------------------------------------------------------- AX
def ax_onedge(ic):
    iso = Iso(15, 12.5)
    a, b, h = 10, 10, 8
    box(ic, iso, (0, 0, 0), (a, b, h), 'steel')
    rod(ic, iso.p(-2.75, b, h), iso.p(a + 2.75, b, h), r=1.0)


def ax_axparallel(ic):
    # an accent axis through a steel bead (the point), parallel to an INK line on the ground below it
    d = unit((0, 0), (2, -1))
    a = (3.75, 14.5)
    b = add(a, d, 23.5)
    line(ic, [(3.75, 24.25), add((3.75, 24.25), d, 23.5)])
    rod(ic, a, b, r=1.2)
    bead(ic, lerp(a, b, .42), 2.4)


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
    # a grounded (fixed) point: an accent push pin stuck into a steel ground pane. The pin's point is the
    # work point; its socket in the pane says it is held there
    plane(ic, sheet(14, 21, 19.5, 8.5, 5), 'steel')
    tip = (12.5, 21.25)
    head = (17.25, 8.0)
    rod(ic, tip, head, r=.9, mat='acc', caps=(False, True), socket=True)
    sphere(ic, head, 4.6, 'acc')


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


def pn_int3planes(ic):
    # three planes x=0, y=0 (standing) and z=0 (lying) meeting in one point: the vertical pair crossing,
    # standing on the horizontal one; drawn as glass quadrants back to front
    iso = Iso(14, 16.25)
    s, hz = 6.75, 10
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
        _quad(ic, [iso.p(*w) for w in W], 'steel', False, (1, 2, 3))
    mat_dot(ic, iso.p(0, 0, 0), 2.6)


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
    t = torus(ic, (14, 14.75), 7.4, 3.4)
    hc, hrx, hry = t['hole']
    mat_dot(ic, (hc[0], hc[1] + .3), 2.3)


def pn_centersphere(ic):
    sphere(ic, (14, 14), 10.5)
    mat_dot(ic, (14, 14))


# ------------------------------------------------------------------------------------------- PT
def _cube(ic, iso, o, a, mat, k=1.1):
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




def pt_circ(ic, n=6, sm=False):
    # a circular pattern of bosses on a steel flange round its centre bore (the axis): one object, so the
    # ring reads as a ring; the first instance (front) accent, its copies steel
    c, R_, h = (14, 12.25), 11.75, 3.25
    cylinder(ic, c, R_, h, 'steel')
    bore(ic, c, 2.6, mat='steel')
    rr, rb, hb = 7.75, 2.3 if not sm else 2.6, 3.25
    items = []
    for k in range(n):
        th = 90 + 360 * k / n
        p = (c[0] + rr * math.cos(math.radians(th)), c[1] + rr / 2 * math.sin(math.radians(th)))
        items.append((math.sin(math.radians(th)), k, p))
    for _, k, p in sorted(items):
        cylinder(ic, (p[0], p[1] - hb), rb, hb, 'acc' if k == 0 else 'steel')


def pt_sketch(ic, a=4.6):
    # instances placed at sketch points: cubes standing on the steel sketch pane at irregular places (not a
    # grid: that is the rectangular pattern), the first one accent
    plane(ic, sheet(14, 19.25, 19.0, 11.5, 6), 'steel')
    iso = Iso(14, 14)
    spots = [(-5.0, 2.5), (2.5, -4.5), (5.5, 4.5)]
    for i in sorted(range(3), key=lambda i: spots[i][0] + spots[i][1]):
        x, y = spots[i]
        _cube(ic, iso, (x - a / 2, y - a / 2), a, 'acc' if i == 0 else 'steel')


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
def vw_shaded(ic, e=.65):
    # Shaded (with edges): a steel cube in flat three-value shading whose edges are drawn, as material (a
    # mark on a solid is material, SPEC 6.1): a dark rim round the silhouette and dark strips on the three
    # inner edges. The display mode is the subject, so the same cube carries no accent
    iso = Iso(14, 14.5)
    a, h = 9.5, 10
    dark = {'top': 'shade', 'left': 'shade', 'right': 'shade'}
    box(ic, iso, (-e, -e, -e), (a + 2 * e, a + 2 * e, h + 2 * e), 'steel', kinds=dark, hair=False)
    S = box(ic, iso, (0, 0, 0), (a, a, h), 'steel')
    F, L, Rr, Fb = S.P['F'], S.end('L'), S.end('R'), S.P['Fb']
    k = e / 2
    for p, q in ((F, L), (F, Rr), (F, Fb)):
        u = unit(p, q)
        n = (-u[1] * k, u[0] * k)
        face(ic, poly([add(p, n), add(q, n), sub(q, n), sub(p, n)]), 'steel', 'shade')


def vw_rendered(ic):
    # Realistic (rendered): an accent sphere lit from the upper left, with the specular reflection a
    # renderer adds (a bright steel-top spot: material, never white paint) and its reflection in a glossy
    # steel floor
    c, r = (14, 12.5), 9.75
    plane(ic, sheet(14, 22.0, 18.5, 6.0, 5), 'steel', hair=False)
    sphere(ic, c, r, 'acc')
    hl = (c[0] - r * .38, c[1] - r * .4)
    ic.circle(hl, 2.1, fill=ic.mat('steel', 'top', hl[0] - 2, hl[1] - 2, hl[0] + 2, hl[1] + 2, user=True))


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
    # the render engine (the renderer, not a look): the camera aperture. An INK circle, six INK blades whose
    # edges close round the hexagonal opening, the opening itself flat ACC (the light let through)
    c, R_, ro = (14, 14), 10.75, 4.6
    V = [(c[0] + ro * math.cos(math.radians(a)), c[1] + ro * math.sin(math.radians(a))) for a in range(-90, 270, 60)]
    ic.shape(poly(V), ACC)
    d = ''
    for i in range(6):
        p, q = V[i], V[(i + 1) % 6]
        u = unit(p, q)
        # the blade edge runs on from q to the rim
        fx, fy = q[0] - c[0], q[1] - c[1]
        b = fx * u[0] + fy * u[1]
        t = -b + math.sqrt(b * b - (fx * fx + fy * fy - R_ * R_))
        d += 'M%sL%s' % (pt(p), pt(add(q, u, t - .4)))
    ic.stroke(d, INK, 1.5)
    ic.circle(c, R_, stroke=INK, w=1.5)


def vw_floor(ic, n=3):
    iso = Iso(14, 9.0)
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
    """An 18 px master (SPEC 2.4): the same drawing with the given simplifications (the library drops the
    hairline of every .sm icon by itself)."""
    def draw(ic):
        fn(ic, **kw)
    return draw


SMALL = {
    'WF.ucs': _sm(ucs, panes=False, w=1.5),                 # seven parts: drop the panes, bolder arrows
    'PT.rect': _sm(pt_rect, a=5.2, sp=7.0, arrows=False, oy=8.5),   # four solids: no arrows, bigger cubes
    'PT.circ': _sm(pt_circ, n=6, sm=True),                  # seven parts: bigger instances
    'PT.sketch': _sm(pt_sketch),                            # three solids plus ink
    'VW.floor': _sm(vw_floor, n=2),                         # grid gaps: two cells
}

if __name__ == '__main__':
    run(DRAW, SMALL)
