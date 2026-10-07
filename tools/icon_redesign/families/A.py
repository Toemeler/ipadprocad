#!/usr/bin/env python3
"""Family A of SPEC v2 "Modern Crisp": sketch Create (design/icons/SPEC.md §11, family A).

    python3 tools/icon_redesign/families/A.py            # writes design/icons/IC/<key>.svg (+ .sm.svg)
    python3 tools/icon_redesign/families/A.py --out DIR  # writes DIR/IC/<key>.svg instead

Line art (SPEC §6.5): INK 1.5 geometry, INK r 1.9 existing points, ONE ACC r 2.4 point being placed (or an
ACC 1.5 added piece with no accent dot), SEC 1.25 construction / radius. No gradient, except projgeo (a
steel block, the only rendered icon of the family). The references IC.line34 / circle34 / rect34 come from
ref.py and are reused here for the flyout aliases and as the base of their siblings.

Flyout families share one geometry and differ in one idea:
  line   line / midpoint (dot moved) / CV spline (same S, control polygon) / interpolating spline (dots on
         the curve) / freehand (a loop) / equation curve (sine on axes) / bridge (ACC blend)
  circle centre-point / tangent (incircle of three lines) / ellipse (axes)
  arc    three-point (two ends + ACC on arc) / tangent (INK line + ACC arc) / centre-point (pie radii)
  rect   2-point / 3-point (rotated, three corners) / 2-point centre (diagonal) / 3-point centre (rotated,
         midpoints); slots on ONE stadium: centre-centre / overall (tips) / centre-point; curved slot on
         ONE arc: three-point / centre-point-arc; polygon
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'lib'))
sys.path.insert(0, HERE)
from crisp import (ACC, INK, SEC, DASH, DASH_AXIS, Iso, add, box, construct, dot, edge_band, face,  # noqa: E402
                   line, lerp, poly, pt, ring, run, sub, unit)
from ref import circle34, line34, rect34  # noqa: E402


# ------------------------------------------------------------------------------------------- local helpers
def P(c, r, deg):
    """Point on a circle (degrees, screen y down: 0 right, 90 down, 270 up)."""
    a = math.radians(deg)
    return (c[0] + r * math.cos(a), c[1] + r * math.sin(a))


def arc_d(c, r, a0, a1, move=True):
    """Circular arc path from angle a0 to a1 (a1 > a0: clockwise on screen)."""
    p0, p1 = P(c, r, a0), P(c, r, a1)
    large = 1 if abs(a1 - a0) > 180 else 0
    sweep = 1 if a1 > a0 else 0
    return ('M%s' % pt(p0) if move else '') + 'A%s %s 0 %d %d %s' % (f2(r), f2(r), large, sweep, pt(p1))


def f2(v):
    return pt((v, 0)).split()[0]


def smooth(pts, tension=1.0):
    """Catmull-Rom through pts as cubic Beziers (end tangents from the neighbours)."""
    d = 'M%s' % pt(pts[0])
    n = len(pts)
    for i in range(n - 1):
        p0 = pts[i - 1] if i > 0 else pts[i]
        p1, p2 = pts[i], pts[i + 1]
        p3 = pts[i + 2] if i + 2 < n else p2
        c1 = add(p1, sub(p2, p0), tension / 6)
        c2 = add(p2, sub(p3, p1), -tension / 6)
        d += 'C%s %s %s' % (pt(c1), pt(c2), pt(p2))
    return d


def bez(p0, p1, p2, p3, t):
    s = 1 - t
    return (s ** 3 * p0[0] + 3 * s * s * t * p1[0] + 3 * s * t * t * p2[0] + t ** 3 * p3[0],
            s ** 3 * p0[1] + 3 * s * s * t * p1[1] + 3 * s * t * t * p2[1] + t ** 3 * p3[1])


def rot(p, c, deg):
    a = math.radians(deg)
    x, y = p[0] - c[0], p[1] - c[1]
    return (c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a))


def rect_pts(c, w, h, deg):
    """Corners (counter-clockwise from bottom-left, before rotation) of a w x h rectangle at c, rotated."""
    hw, hh = w / 2, h / 2
    return [rot((c[0] + x, c[1] + y), c, deg) for x, y in ((-hw, hh), (hw, hh), (hw, -hh), (-hw, -hh))]


def letter_a(ic, base_l, base_r, apex_y, col=INK):
    """Monoline geometric sans 'A' (SPEC §7): two stems to a pointed apex and a crossbar, INK 1.5."""
    (xl, yb), (xr, _) = base_l, base_r
    apex = ((xl + xr) / 2, apex_y)
    t = .62                                       # crossbar height (fraction from apex down)
    a, b = lerp(apex, base_l, t), lerp(apex, base_r, t)
    ic.stroke('M%sL%sL%sM%sL%s' % (pt(base_l), pt(apex), pt(base_r), pt(a), pt(b)), col, 1.5)


# ------------------------------------------------------------------------------------------- arcs
ARC_C, ARC_R = (14, 18.25), 10            # the three-point arc: about 200 degrees, open at the bottom


def arc34(ic):
    a0, a1 = 170, 370
    ic.stroke(arc_d(ARC_C, ARC_R, a0, a1), INK, 1.5)
    dot(ic, P(ARC_C, ARC_R, a0), 'ink')
    dot(ic, P(ARC_C, ARC_R, a1), 'ink')
    dot(ic, P(ARC_C, ARC_R, 300), 'acc')


def arctan(ic):
    # an existing INK line ends in a point; the new arc (ACC, the added piece) leaves it tangentially
    y, x0, x1 = 21.5, 3.25, 11.5
    c, r = (x1, y - 9.5), 9.5
    line(ic, [(x0, y), (x1, y)])
    ic.stroke(arc_d(c, r, 90, -48), ACC, 1.5)
    dot(ic, (x0, y), 'ink')
    dot(ic, (x1, y), 'ink')


def arccp(ic):
    # centre, start, end: the arc with its two SEC radii, the ACC centre placed first
    c, r, a0, a1 = (6.5, 21.5), 17, -84, -6
    s, e = P(c, r, a0), P(c, r, a1)
    line(ic, [s, c, e], SEC, 1.25)
    ic.stroke(arc_d(c, r, a0, a1), INK, 1.5)
    dot(ic, c, 'acc')


# ------------------------------------------------------------------------------------------- circles
def circletan(ic, sm=False):
    # the circle tangent to three lines: the incircle of a closed INK triangle (apex up, no overshoot at the
    # corners), the last tangent point picked as the ACC dot on the base
    r = 6.5
    c = (14, 14 + r / 2)
    V = [P(c, 2 * r, a) for a in (270, 30, 150)]
    line(ic, V, close=True)
    ic.circle(c, r, stroke=INK, w=1.5)
    dot(ic, P(c, r, 90), 'acc')


def ellipse(ic):
    c, rx, ry = (14, 14), 11.25, 7.25
    line(ic, [(c[0] - rx, c[1]), (c[0] + rx, c[1])], SEC, 1.25)
    line(ic, [(c[0], c[1] - ry), (c[0], c[1] + ry)], SEC, 1.25)
    ic.add('<ellipse cx="%s" cy="%s" rx="%s" ry="%s" stroke="%s" stroke-width="1.5"/>'
           % (f2(c[0]), f2(c[1]), f2(rx), f2(ry), INK))
    dot(ic, c, 'acc')


# ------------------------------------------------------------------------------------------- lines
def midline(ic):
    line(ic, [(6, 22), (22, 6)])
    dot(ic, (6, 22), 'ink')
    dot(ic, (22, 6), 'ink')
    dot(ic, (14, 14), 'acc')


S_CV = [(4.25, 22), (7.5, 4.5), (20.5, 23.5), (23.75, 6)]     # the CV spline: one cubic, four vertices


def splinecv(ic, sm=False):
    p0, p1, p2, p3 = S_CV
    construct(ic, poly(S_CV, False))
    ic.stroke('M%sC%s %s %s' % (pt(p0), pt(p1), pt(p2), pt(p3)), INK, 1.5)
    for p in ((p1, p2) if sm else (p0, p1, p2)):
        dot(ic, p, 'ink')
    dot(ic, p3, 'acc')


# the fit spline: a smooth wave THROUGH four points (round crests, handles horizontal at the inner points)
S_FIT = [(4.25, 20.5), (10.25, 10.5), (17.5, 17), (23.75, 7.5)]
S_FIT_D = ('M4.25 20.5C5.5 15 7.25 10.5 10.25 10.5C13.25 10.5 14.25 17 17.5 17C20.75 17 22.5 13 23.75 7.5')


def splinei(ic):
    ic.stroke(S_FIT_D, INK, 1.5)
    for p in S_FIT[:-1]:
        dot(ic, p, 'ink')
    dot(ic, S_FIT[-1], 'acc')


def splinefree(ic):
    # a freehand pen stroke: one confident cursive loop (a single smooth path, no wobble), the pen at the
    # end (ACC)
    ic.stroke('M3.5 21.5C8.5 21.5 14 19.25 16.5 14.25C18.25 10.75 17 6.75 14 7C11 7.25 10.75 11.5 13.25 14.75'
              'C15.75 18 20.25 18.25 23.75 11.75', INK, 1.5)
    dot(ic, (23.75, 11.75), 'acc')


def eqcurve(ic):
    # y = f(x): one period of a sine plotted in the corner of SEC x / y axes (an L, clear of the curve),
    # ACC dot on the last crest
    ox, oy = 4, 24
    line(ic, [(ox, 3.5), (ox, oy), (24.5, oy)], SEC, 1.25)
    x0, x1, yc, amp = 7.5, 24.5, 12.5, 6.5
    n = 32
    pts = [(x0 + (x1 - x0) * i / n, yc + amp * math.sin(2 * math.pi * i / n)) for i in range(n + 1)]
    ic.stroke(smooth(pts), INK, 1.5)
    dot(ic, (x0 + (x1 - x0) * .75, yc - amp), 'acc')


def bridge(ic):
    # two INK curves with a gap; the bridge is an ACC S-blend tangent to both (the added piece)
    a, b = (10.5, 9.5), (17.5, 18.5)
    ic.stroke('M%sC%s %s %s' % (pt((3, 17.5)), pt((4.25, 12)), pt((7, 9.5)), pt(a)), INK, 1.5)
    ic.stroke('M%sC%s %s %s' % (pt(b), pt((21, 18.5)), pt((23.75, 16)), pt((25, 10.5))), INK, 1.5)
    ic.stroke('M%sC%s %s %s' % (pt(a), pt((14.75, 9.5)), pt((13.25, 18.5)), pt(b)), ACC, 1.5)
    dot(ic, a, 'ink')
    dot(ic, b, 'ink')


# ------------------------------------------------------------------------------------------- rectangles
RC, RW, RH, RA = (14, 14.25), 17.5, 10.5, -22     # the rotated rectangle of the 3-point tools


def rect3p(ic):
    q = rect_pts(RC, RW, RH, RA)
    line(ic, q, close=True)
    dot(ic, q[0], 'ink')
    dot(ic, q[1], 'ink')
    dot(ic, q[2], 'acc')


def rect2pc(ic):
    line(ic, [(5, 21), (23, 21), (23, 7), (5, 7)], close=True)
    line(ic, [(14, 14), (23, 7)], SEC, 1.25)
    dot(ic, (23, 7), 'ink')
    dot(ic, (14, 14), 'acc')


def rect3pc(ic):
    q = rect_pts(RC, RW, RH, RA)
    line(ic, q, close=True)
    dot(ic, lerp(q[0], q[1], .5), 'ink')
    dot(ic, lerp(q[1], q[2], .5), 'ink')
    dot(ic, RC, 'acc')


# ------------------------------------------------------------------------------------------- slots
SL_A, SL_B, SL_R = (8, 14), (20, 14), 4.75       # one stadium for every straight slot


def stadium(ic):
    (ax, y), (bx, _), r = SL_A, SL_B, SL_R
    d = 'M%sL%sA%s %s 0 0 1 %sL%sA%s %s 0 0 1 %sZ' % (
        pt((ax, y - r)), pt((bx, y - r)), f2(r), f2(r), pt((bx, y + r)), pt((ax, y + r)), f2(r), f2(r),
        pt((ax, y - r)))
    ic.stroke(d, INK, 1.5)


def slotcc(ic):
    stadium(ic)
    ic.stroke('M%sL%s' % (pt(SL_A), pt(SL_B)), SEC, 1.25, DASH_AXIS)
    dot(ic, SL_A, 'ink')
    dot(ic, SL_B, 'acc')


def slotov(ic):
    stadium(ic)
    dot(ic, (SL_A[0] - SL_R, SL_A[1]), 'ink')
    dot(ic, (SL_B[0] + SL_R, SL_B[1]), 'acc')


def slotcp(ic):
    stadium(ic)
    m = lerp(SL_A, SL_B, .5)
    dot(ic, SL_B, 'ink')
    dot(ic, m, 'acc')


AS_C, AS_R, AS_W, AS_A = (14, 21.75), 10, 4, (216, 324)   # one curved slot: centre, radius, half-width


def arcslot(ic):
    c, r, w = AS_C, AS_R, AS_W
    a0, a1 = AS_A
    e0, e1 = P(c, r, a0), P(c, r, a1)
    d = arc_d(c, r + w, a0, a1)
    # the end caps as two quarter arcs each (a semicircle arc is ambiguous to parsers)
    d += 'A%s %s 0 0 1 %s' % (f2(w), f2(w), pt(P(e1, w, a1 + 90)))
    d += 'A%s %s 0 0 1 %s' % (f2(w), f2(w), pt(P(c, r - w, a1)))
    d += 'A%s %s 0 0 0 %s' % (f2(r - w), f2(r - w), pt(P(c, r - w, a0)))
    d += 'A%s %s 0 0 1 %s' % (f2(w), f2(w), pt(P(e0, w, a0 - 90)))
    d += 'A%s %s 0 0 1 %sZ' % (f2(w), f2(w), pt(P(c, r + w, a0)))
    ic.stroke(d, INK, 1.5)
    return e0, e1


def slot3a(ic):
    e0, e1 = arcslot(ic)
    ic.stroke(arc_d(AS_C, AS_R, *AS_A), SEC, 1.25, DASH_AXIS)
    dot(ic, e0, 'ink')
    dot(ic, e1, 'ink')
    dot(ic, P(AS_C, AS_R, 270), 'acc')


def slotcpa(ic):
    arcslot(ic)
    a0, a1 = AS_A
    line(ic, [P(AS_C, AS_R - AS_W, a0), AS_C, P(AS_C, AS_R - AS_W, a1)], SEC, 1.25)
    dot(ic, AS_C, 'acc')


def polygon(ic):
    c, r = (14, 14), 10.75
    ic.add('<circle cx="%s" cy="%s" r="%s" stroke="%s" stroke-width="1.25" stroke-dasharray="%s" '
           'stroke-linecap="butt"/>' % (f2(c[0]), f2(c[1]), f2(r), SEC, DASH))
    line(ic, [P(c, r, a) for a in range(0, 360, 60)], close=True)
    dot(ic, c, 'acc')


# ------------------------------------------------------------------------------------------- fillet / chamfer
CO, CL, CR_ = (5.75, 5.75), 17.75, 8.5     # corner, leg length, fillet radius / chamfer setback


def corner(ic, piece, ghost=True):
    x, y = CO
    t1, t2 = (x, y + CR_), (x + CR_, y)               # tangent / setback points
    line(ic, [(x, y + CL), t1])
    line(ic, [t2, (x + CL, y)])
    if ghost:
        construct(ic, 'M%sL%sL%s' % (pt(add(t1, (0, -1.75))), pt(CO), pt(add(t2, (-1.75, 0)))))
    if piece == 'fillet':
        ic.stroke('M%sA%s %s 0 0 1 %s' % (pt(t1), f2(CR_), f2(CR_), pt(t2)), ACC, 1.5)
    else:
        ic.stroke('M%sL%s' % (pt(t1), pt(t2)), ACC, 1.5)
    dot(ic, t1, 'ink')
    dot(ic, t2, 'ink')


def fillet18(ic):
    corner(ic, 'fillet')


def chamfer(ic):
    corner(ic, 'chamfer')


# ------------------------------------------------------------------------------------------- text
def text18(ic):
    # cap height 14 (SPEC 7): the letter is the subject
    y = 21.25
    line(ic, [(3.5, y), (25, y)], SEC, 1.25)
    letter_a(ic, (9.25, y - 1.75), (24.75, y - 1.75), y - 1.75 - 14)
    dot(ic, (5.25, y), 'acc')


def gtext(ic):
    # the letter (cap 13.5) standing on the crown of an INK arc, ACC dot at the arc's start
    c, r = (14, 33.5), 14.5
    a0, a1 = 226, 314
    ic.stroke(arc_d(c, r, a0, a1), INK, 1.5)
    top = c[1] - r
    letter_a(ic, (7.25, top - 1.75), (20.75, top - 1.75), top - 1.75 - 13.5)
    dot(ic, P(c, r, a0), 'acc')


# ------------------------------------------------------------------------------------------- point / project
def point18(ic):
    c = (14, 14)
    ring(ic, c)
    dot(ic, c, 'acc')
    a, b = 7.0, 11.25
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        line(ic, [(c[0] + dx * a, c[1] + dy * a), (c[0] + dx * b, c[1] + dy * b)], SEC, 1.25)


def projgeo(ic, sm=False):
    # a steel block; its long front-left top edge is the selected edge (the shared accent edge_band).
    # Straight below, on the ground, its projection: an ACC line, joined to the block by SEC dashed
    # projectors that continue the block's vertical edges (they start 1.5 u under it: no ink on material).
    a, b, h = 13, 6, 5.5
    iso = Iso(10, 6.75)
    S = box(ic, iso, (0, 0, 0), (a, b, h), 'steel')
    edge_band(ic, S, 'L', 'F', (1, -.5), (0, 1), k=2.0)
    Lb, Fb = S.P['Lb'], S.P['Fb']
    drop = 9.0
    gl, gf = add(Lb, (0, drop)), add(Fb, (0, drop))
    if not sm:
        construct(ic, 'M%sL%sM%sL%s' % (pt(add(Lb, (0, 1.5))), pt(add(gl, (0, -1.5))),
                                        pt(add(Fb, (0, 1.5))), pt(add(gf, (0, -1.5)))))
    line(ic, [gl, gf], ACC, 1.5 if not sm else 2.0)


# ------------------------------------------------------------------------------------------- table
DRAW = {
    'IC.arc34': arc34, 'IC.fillet18': fillet18, 'IC.text18': text18, 'IC.point18': point18,
    'IC.fline': line34, 'IC.fmidline': midline,
    'IC.fsplinecv': splinecv, 'IC.fsplinei': splinei, 'IC.fsplinefree': splinefree,
    'IC.feqcurve': eqcurve, 'IC.fbridge': bridge,
    'IC.fcirclecp': circle34, 'IC.fcircletan': circletan, 'IC.fellipse': ellipse,
    'IC.farc3': arc34, 'IC.farctan': arctan, 'IC.farccp': arccp,
    'IC.frect2p': rect34, 'IC.frect3p': rect3p, 'IC.frect2pc': rect2pc, 'IC.frect3pc': rect3pc,
    'IC.fslotcc': slotcc, 'IC.fslotov': slotov, 'IC.fslotcp': slotcp, 'IC.fslot3a': slot3a,
    'IC.fslotcpa': slotcpa, 'IC.fpolygon': polygon,
    'IC.ffillet': fillet18, 'IC.fchamfer': chamfer,
    'IC.ftext': text18, 'IC.fgtext': gtext,
    'IC.projgeo': projgeo,
}
SMALL = {
    'IC.fcircletan': lambda ic: circletan(ic, sm=True),
    'IC.projgeo': lambda ic: projgeo(ic, sm=True),
    # the v1 small masters of these keys are still on disk: overwrite them (secondary detail dropped)
    'IC.fillet18': lambda ic: corner(ic, 'fillet', ghost=False),
    'IC.ffillet': lambda ic: corner(ic, 'fillet', ghost=False),
    'IC.fchamfer': lambda ic: corner(ic, 'chamfer', ghost=False),
    'IC.fsplinecv': lambda ic: splinecv(ic, sm=True),
}

if __name__ == '__main__':
    run(DRAW, SMALL)
