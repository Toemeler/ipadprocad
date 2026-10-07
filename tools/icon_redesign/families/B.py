#!/usr/bin/env python3
"""Family B of SPEC v2 "Modern Crisp": sketch Constrain / Modify / Insert / 2D pattern / sketch singles.

    python3 tools/icon_redesign/families/B.py            # writes design/icons/<MAP>/<key>.svg (+ .sm.svg)
    python3 tools/icon_redesign/families/B.py --out DIR  # elsewhere

Sketch tools are line art (SPEC 6.5): INK 1.5 geometry, INK r 1.9 existing points, ACC on ONE element.
The constraint set is one glyph language built on the coincident reference: the geometry the relation acts
on in INK, and the relation itself as a single ACC 1.5 marker drawn at its locus.
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
from crisp import (ACC, DASH, DASH_AXIS, INK, SEC, Iso, add, arc_arrow, arrow, badge, construct,  # noqa: E402
                   dim, dot, f, iso_plane, lerp, line, plane, poly, pt, ring, run, sub, unit, work_axis)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ref import coincident, dimension  # noqa: E402,F401  (the two CN references, for the sheet only)


# ------------------------------------------------------------------------------------------- local helpers
def seg(ic, a, b, col=INK, w=1.5, dash=None):
    ic.stroke('M%sL%s' % (pt(a), pt(b)), col, w, dash)


def along(a, b, t):
    return lerp(a, b, t)


def perp(u):
    return (-u[1], u[0])


def rrect(x0, y0, x1, y1, r):
    """A rounded rectangle path (clockwise)."""
    return ('M%s H%s A%s %s 0 0 1 %s V%s A%s %s 0 0 1 %s H%s A%s %s 0 0 1 %s V%s A%s %s 0 0 1 %s Z' % (
        pt((x0 + r, y0)), f(x1 - r), f(r), f(r), pt((x1, y0 + r)), f(y1 - r), f(r), f(r), pt((x1 - r, y1)),
        f(x0 + r), f(r), f(r), pt((x0, y1 - r)), f(y0 + r), f(r), f(r), pt((x0 + r, y0)))).replace('M', 'M', 1)


def eye(ic, c, w=5.5, h=3.1, col=INK, slash=False):
    """The show / hide eye (SPEC 6.6): INK 1.5 lens, filled pupil."""
    x, y = c
    ic.stroke('M%sQ%s %sQ%s %sZ' % (pt((x - w, y)), pt((x, y - 2 * h)), pt((x + w, y)),
                                     pt((x, y + 2 * h)), pt((x - w, y))), col, 1.5)
    ic.circle(c, 1.6, fill=col)
    if slash:
        seg(ic, (x - w + 1, y + h + 1), (x + w - 1, y - h - 1), col)


def gear(ic, c, r_tip, r_root, n, col=INK, w=1.5, phase=-math.pi / 2):
    step = 2 * math.pi / n
    pts = []
    for i in range(n):
        a = phase + i * step
        tip, root = step * .2, step * .26          # half-widths of the tip land and the root land
        pts += [(a - step / 2 + root, r_root), (a - tip, r_tip), (a + tip, r_tip), (a + step / 2 - root, r_root)]
    P = [(c[0] + r * math.cos(t), c[1] + r * math.sin(t)) for t, r in pts]
    ic.stroke(poly(P), col, w)


def chevron(ic, tip, dirn, size=3.2, col=ACC, w=1.5):
    """An open chevron (a 'less than' sign) pointing along dirn, apex at tip."""
    u = unit((0, 0), dirn)
    n = perp(u)
    back = add(tip, u, -size * .8)
    ic.stroke('M%sL%sL%s' % (pt(add(back, n, size)), pt(tip), pt(add(back, n, -size))), col, w)


def padlock(ic, x0, y0, x1, y1, col=ACC):
    """The fix marker: rx 1 body and a round shackle, ACC 1.5 (SPEC CN.lock), keyhole dot."""
    ic.stroke(rrect(x0, y0, x1, y1, 1.0), col, 1.5)
    cx = (x0 + x1) / 2
    r = (x1 - x0) / 2 - 2.0
    leg = y0 - 2.4
    ic.stroke('M%sV%sA%s %s 0 0 1 %sV%s' % (pt((cx - r, y0)), f(leg), f(r), f(r), pt((cx + r, leg)), f(y0)), col, 1.5)
    ic.circle((cx, (y0 + y1) / 2), 1.15, fill=col)


def fx(ic, x, base, cap=11.0, col=INK):
    """Monoline italic 'fx' (SPEC 7: letters are paths), x = left of the f stem foot, base = baseline."""
    sl = .21                                        # italic slant (dx per unit of height)
    top = base - cap
    P = lambda dx, y: (x + dx + (base - y) * sl, y)
    # f: stem from below the baseline-ish foot up into a hook to the right
    foot = P(0, base)
    st = P(0, top + 2.6)
    ic.stroke('M%sL%sQ%s %s' % (pt(foot), pt(st), pt(P(0, top)), pt(P(3.3, top + .2))), col, 1.5)
    ic.stroke('M%sL%s' % (pt(P(-2.0, top + 4.3)), pt(P(3.2, top + 4.3))), col, 1.5)
    # x: two diagonals on the x-height
    xh = top + 4.3
    ic.stroke('M%sL%sM%sL%s' % (pt(P(5.0, xh)), pt(P(10.0, base)), pt(P(10.0, xh)), pt(P(5.0, base))), col, 1.5)


# ------------------------------------------------------------------------------------------- constraints
def parallel(ic):
    d = (8.0, -18.0)
    for x in (4.5, 15.5):
        seg(ic, (x, 23), add((x, 23), d))
    u = unit((0, 0), d)
    for dx in (-1.75, 1.75):
        c = (14 + dx, 14)
        seg(ic, add(c, u, -3.4), add(c, u, 3.4), ACC)


def perpendicular(ic):
    seg(ic, (3.5, 21.5), (24.5, 21.5))
    seg(ic, (12, 21.5), (12, 4))
    line(ic, [(12, 15.5), (18, 15.5), (18, 21.5)], ACC)


def horizontal(ic):
    a, b = (4.5, 18.5), (23.5, 18.5)
    seg(ic, a, b)
    dot(ic, a)
    dot(ic, b)
    seg(ic, (9.5, 11), (18.5, 11), ACC)


def vertical(ic):
    a, b = (18.5, 4.5), (18.5, 23.5)
    seg(ic, a, b)
    dot(ic, a)
    dot(ic, b)
    seg(ic, (11, 9.5), (11, 18.5), ACC)


def tangent(ic):
    c, r = (11.5, 16.5), 7.5
    ic.circle(c, r, stroke=INK, w=1.5)
    k = math.sqrt(.5)
    t = (c[0] + r * k, c[1] - r * k)
    seg(ic, add(t, (-k, -k), 10.5), add(t, (k, k), 9.0))
    dot(ic, t, 'acc')


def smooth(ic, sm=False):
    p0 = (3, 19.5)
    a = (9.5, 19.5)
    c1, c2, e = (16.5, 19.5), (21.5, 14.5), (22.5, 3.5)
    ic.stroke('M%sL%sC%s %s %s' % (pt(p0), pt(a), pt(c1), pt(c2), pt(e)), INK, 1.5)
    dot(ic, a)

    def B(t):
        m = 1 - t
        return (m ** 3 * a[0] + 3 * m * m * t * c1[0] + 3 * m * t * t * c2[0] + t ** 3 * e[0],
                m ** 3 * a[1] + 3 * m * m * t * c1[1] + 3 * m * t * t * c2[1] + t ** 3 * e[1])

    def D(t, h=1e-4):
        p, q = B(t - h), B(t + h)
        return ((q[0] - p[0]) / (2 * h), (q[1] - p[1]) / (2 * h))

    def K(t, h=1e-3):
        d1 = D(t)
        p, q = D(t - h), D(t + h)
        d2 = ((q[0] - p[0]) / (2 * h), (q[1] - p[1]) / (2 * h))
        return (d1[0] * d2[1] - d1[1] * d2[0]) / (math.hypot(*d1) ** 3)

    tips, spines = [], ''
    nc = 3 if sm else 5
    for i in range(nc):
        t = .12 + i * .5 / (nc - 1)
        p = B(t)
        u = unit((0, 0), D(t))
        n = (u[1], -u[0])
        ln = 2.0 + abs(K(t)) * 30
        q = add(p, n, -ln)
        tips.append(q)
        spines += 'M%sL%s' % (pt(add(p, n, -.75)), pt(q))
    ic.stroke(spines, ACC, 1.25 if sm else 1.0)
    if sm:
        ic.stroke('M%sQ%s %s' % (pt(tips[0]), pt(tips[1]), pt(tips[2])), ACC, 1.25)
    else:
        ic.stroke('M%s' % pt(tips[0]) + ''.join('Q%s %s' % (pt(tips[i]), pt(lerp(tips[i], tips[i + 1], .5)))
                                               for i in range(1, len(tips) - 1)) + 'L%s' % pt(tips[-1]), ACC, 1.25)


def symmetric(ic):
    work_axis(ic, (14, 3), (14, 25))
    dot(ic, (4.5, 14))
    dot(ic, (23.5, 14))
    chevron(ic, (11, 14), (1, 0), 3.0)
    chevron(ic, (17, 14), (-1, 0), 3.0)


def equal(ic):
    for a, b in (((3.5, 23), (11.5, 5)), ((16.5, 5), (24.5, 23))):
        seg(ic, a, b)
        u = unit(a, b)
        n = perp(u)
        m = lerp(a, b, .5)
        for s in (-1.3, 1.3):
            c = add(m, u, s)
            seg(ic, add(c, n, -2.6), add(c, n, 2.6), ACC)


def collinear(ic, sm=False):
    A, B = (3, 23.5), (25, 4.5)
    seg(ic, A, lerp(A, B, .3))
    seg(ic, lerp(A, B, .7), B)
    ic.stroke('M%sL%s' % (pt(lerp(A, B, .345)), pt(lerp(A, B, .655))), ACC, 1.5, '2.6 1.9' if sm else '2.2 1.55')


def concentric(ic):
    c = (14, 14)
    ic.circle(c, 11, stroke=INK, w=1.5)
    ic.circle(c, 7.4, stroke=INK, w=1.5)
    dot(ic, c, 'acc')


def lock(ic):
    a, b = (4, 24), (11.5, 16.5)
    seg(ic, a, b)
    dot(ic, a)
    dot(ic, b)
    padlock(ic, 14, 12.5, 24, 20.5)


def autodim(ic):
    A, B, C, D, E, F = (11, 18.5), (24, 18.5), (24, 13.5), (16, 13.5), (16, 4.5), (11, 4.5)
    line(ic, [A, B, C, D, E, F], close=True)
    dim(ic, A, F, 6, gap=2, over=1.5)
    dim(ic, A, B, -5, gap=2, over=1.5)


def conset(ic, sm=False):
    g = (19.5, 19.5)
    ic.stroke('M19.5 11.5V5A1.5 1.5 0 0 0 18 3.5H5A1.5 1.5 0 0 0 3.5 5V20A1.5 1.5 0 0 0 5 21.5H11.5', INK, 1.5)
    line(ic, [(7, 6.5), (7, 13), (13.5, 13)])
    line(ic, [(7, 9.75), (10.25, 9.75), (10.25, 13)])
    if not sm:
        seg(ic, (6.5, 18.5), (8.75, 15.5))
        seg(ic, (9.75, 18.5), (12, 15.5))
    gear(ic, g, 6.4, 4.6, 6 if sm else 8, ACC)
    ic.circle(g, 1.8, stroke=ACC, w=1.5)


def showcons(ic):
    seg(ic, (8.5, 3.5), (8.5, 15.5))
    seg(ic, (3.5, 15.5), (16, 15.5))
    line(ic, [(8.5, 10.5), (13.5, 10.5), (13.5, 15.5)], ACC)
    for x in (18.25, 21.75):
        seg(ic, (x - 1.75, 10), (x + 1.75, 4), ACC)
    eye(ic, (20, 21.75))


# ------------------------------------------------------------------------------------------- modify
def trim(ic):
    q0, qc, q1 = (9, 3.5), (18, 14), (9, 24.5)
    ic.stroke('M%sQ%s %s' % (pt(q0), pt(qc), pt(q1)), INK, 1.5)
    cut = (13.5, 14)
    seg(ic, (3.5, 14), cut)
    construct(ic, 'M%sL%s' % (pt((17, 14)), pt((25.5, 14))))
    dot(ic, cut, 'acc')


def extend(ic):
    seg(ic, (23, 3.5), (23, 24.5))
    a = (4, 21)
    u = unit((0, 0), (1, -.62))
    m = add(a, u, 9)
    end = add(a, u, (23 - .75 - a[0]) / u[0])
    seg(ic, a, m)
    dot(ic, a)
    seg(ic, m, end, ACC)


def split(ic):
    A, B = (3, 21), (25, 7)
    c = lerp(A, B, .5)
    u = unit(A, B)
    g = 2.4 + 2 + 1.9
    seg(ic, A, add(c, u, -g))
    seg(ic, add(c, u, g), B)
    dot(ic, add(c, u, -g))
    dot(ic, add(c, u, g))
    dot(ic, c, 'acc')


def moffset(ic):
    ic.stroke('M10.5 24.5V18A4.5 4.5 0 0 1 15 13.5H24.5', SEC, 1.5)
    ic.stroke('M4 24.5V18A11 11 0 0 1 15 7H24.5', INK, 1.5)
    dot(ic, (24.5, 7), 'acc')
    k = math.sqrt(.5)
    c = (15, 18)
    arrow(ic, add(c, (-k, -k), 5.6), add(c, (-k, -k), 10.2), SEC)


def move(ic):
    line(ic, [(4, 14), (13.5, 14), (13.5, 23.5), (4, 23.5)], close=True)
    dot(ic, (4, 23.5), 'acc')
    c = (18.25, 9.25)
    for d in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        arrow(ic, add(c, d, 0), add(c, d, 6.75))


def copy(ic):
    line(ic, [(3.5, 14.5), (13, 14.5), (13, 24), (3.5, 24)], SEC, close=True)
    line(ic, [(15, 4), (24.5, 4), (24.5, 13.5), (15, 13.5)], INK, close=True)
    dot(ic, (15, 13.5), 'acc')
    arrow(ic, (4.5, 11.5), (11, 5))


def mrotate(ic):
    pv = (7, 20.5)
    th = math.radians(-38)
    u = (math.cos(th), math.sin(th))
    n = perp(u)
    L, W = 12.5, 2.6
    p = [add(pv, n, -W * .0), add(add(pv, u, L), n, 0)]
    corners = [add(pv, n, W), add(add(pv, u, L), n, W), add(add(pv, u, L), n, -W), add(pv, n, -W)]
    line(ic, corners, close=True)
    arc_arrow(ic, pv, 17, 17, -4, -78, )
    dot(ic, pv, 'acc')


def mscale(ic):
    line(ic, [(4.5, 23.5), (4.5, 4.5), (23.5, 4.5), (23.5, 23.5)], close=True)
    line(ic, [(4.5, 23.5), (4.5, 15), (13, 15), (13, 23.5)], SEC, close=True)
    arrow(ic, (15, 13), (21, 7))
    dot(ic, (4.5, 23.5), 'acc')


def stretch(ic):
    line(ic, [(3.5, 11), (21, 11), (21, 21.5), (3.5, 21.5)], close=True)
    construct(ic, poly([(16.5, 7.5), (25.5, 7.5), (25.5, 25.5), (16.5, 25.5)]))
    arrow(ic, (8, 4.25), (21, 4.25))
    dot(ic, (21, 11), 'acc')


# ------------------------------------------------------------------------------------------- insert
def image(ic):
    ic.stroke(rrect(3, 5, 25, 23, 1.5), INK, 1.5)
    line(ic, [(6, 20), (11, 13), (14.5, 17), (17.5, 14), (22, 20)], ACC)
    ic.circle((19, 9.5), 1.9, fill=INK)


def points(ic, sm=False):
    line(ic, [(4, 24), (4, 4), (24, 4)])
    g = (11, 20) if sm else (10, 16, 22)
    for j, y in enumerate(g):
        for i, x in enumerate(g):
            dot(ic, (x, y), 'acc' if (i, j) == (0, 0) else 'ink')


def acad(ic, sm=False):
    ic.stroke('M8 12V5A1.5 1.5 0 0 1 9.5 3.5H19L24.5 9V23A1.5 1.5 0 0 1 23 24.5H9.5A1.5 1.5 0 0 1 8 23V20',
              INK, 1.5)
    ic.stroke('M19 3.5V9H24.5', INK, 1.5)
    if not sm:
        line(ic, [(12.5, 13), (20.5, 13), (20.5, 20.5), (12.5, 20.5)], close=True)
    dot(ic, (16.5, 16) if sm else (12.5, 13), 'acc')
    arrow(ic, (2, 16), (10, 16))


def constr(ic):
    a, b = (5, 23), (23, 5)
    u = unit(a, b)
    construct(ic, 'M%sL%s' % (pt(add(a, u, 3)), pt(add(b, u, -3.6))))
    dot(ic, a)
    dot(ic, b, 'acc')


def params(ic):
    fx(ic, 3.0, 19.5, 11.5)
    ic.stroke(rrect(15, 8.5, 25.5, 19.5, 1.5), SEC, 1.25)
    seg(ic, (18.25, 11.25), (18.25, 16.75), ACC)


def gear_icon(ic, sm=False):
    gear(ic, (14, 14), 11.2, 8.4 if sm else 8.6, 8 if sm else 12, INK)
    ic.circle((14, 14), 3.6, stroke=ACC, w=1.5)


def driven(ic):
    for x in (7, 21):
        construct(ic, 'M%sL%s' % (pt((x, 5)), pt((x, 23))))
    arrow(ic, (7.7, 14), (20.3, 14), ACC, both=True)
    ic.stroke('M5 7.5Q1.5 14 5 20.5', INK, 1.25)
    ic.stroke('M23 7.5Q26.5 14 23 20.5', INK, 1.25)


def centerline(ic):
    a, b = (4, 14), (24, 14)
    work_axis(ic, (6.6, 14), (21.2, 14))
    dot(ic, a)
    dot(ic, b, 'acc')


def center(ic):
    c = (14, 14)
    ic.stroke('M%sL%sM%sL%s' % (pt((3.5, 14)), pt((24.5, 14)), pt((14, 3.5)), pt((14, 24.5))), INK, 1.5)
    ring(ic, c, 5.5)


def showfmt(ic, sm=False):
    seg(ic, (3.5, 5), (24.5, 5))
    if sm:
        seg(ic, (3.5, 12), (24.5, 12), INK, 1.5, '3.5 2.5')
    else:
        seg(ic, (3.5, 10.5), (24.5, 10.5), INK, 1.5, DASH)
        seg(ic, (3.5, 16), (24.5, 16), INK, 1.5, DASH_AXIS)
    eye(ic, (20, 22))


# ------------------------------------------------------------------------------------------- 2D patterns
def patrect(ic):
    s = 6.5
    for j, y in enumerate((4, 13)):
        for i, x in enumerate((9, 18.5)):
            col = INK
            line(ic, [(x, y), (x + s, y), (x + s, y + s), (x, y + s)], col, close=True)
    dot(ic, (9, 19.5), 'acc')
    arrow(ic, (4.5, 24.5), (25, 24.5), SEC)
    arrow(ic, (4.5, 24.5), (4.5, 3.5), SEC)


def patcirc(ic, sm=False):
    c, R0, ri = (14, 14), 10, 2.2
    if sm:
        ic.circle(c, R0, stroke=SEC, w=1.25)
        dot(ic, c)
        for i in range(6):
            a = math.radians(-90 + i * 60)
            dot(ic, (c[0] + R0 * math.cos(a), c[1] + R0 * math.sin(a)), 'acc' if i == 0 else 'ink')
        return
    dot(ic, c)
    gap = math.degrees((ri + 1.6) / R0)
    d = ''
    for i in range(6):
        a0, a1 = -90 + i * 60 + gap, -90 + (i + 1) * 60 - gap
        p0 = (c[0] + R0 * math.cos(math.radians(a0)), c[1] + R0 * math.sin(math.radians(a0)))
        p1 = (c[0] + R0 * math.cos(math.radians(a1)), c[1] + R0 * math.sin(math.radians(a1)))
        d += 'M%sA%s %s 0 0 1 %s' % (pt(p0), f(R0), f(R0), pt(p1))
    ic.stroke(d, SEC, 1.25)
    for i in range(6):
        a = math.radians(-90 + i * 60)
        p = (c[0] + R0 * math.cos(a), c[1] + R0 * math.sin(a))
        if i == 0:
            dot(ic, p, 'acc')
        else:
            ic.circle(p, ri, stroke=INK, w=1.5)


def patmir(ic):
    work_axis(ic, (14, 3), (14, 25))
    line(ic, [(11, 5.5), (11, 22.5), (3.5, 22.5)], close=True)
    line(ic, [(17, 5.5), (17, 22.5), (24.5, 22.5)], close=True)
    dot(ic, (24.5, 22.5), 'acc')


# ------------------------------------------------------------------------------------------- singles
def layer_big(ic):
    iso = Iso(12, 10)
    iso_plane(ic, iso, (0, 0, 0), (9, 0, 0), (0, 9, 0), 'steel')
    iso = Iso(12, 4)
    iso_plane(ic, iso, (0, 0, 0), (9, 0, 0), (0, 9, 0), 'acc')
    badge(ic, '+')


def finish(ic):
    ic.stroke('M15 21.5H5A1.5 1.5 0 0 1 3.5 20V5.5A1.5 1.5 0 0 1 5 4H13.5A5 5 0 0 1 18.5 9V10', SEC, 1.5)
    ic.stroke('M%sL%sL%s' % (pt((9.5, 15.5)), pt((14.5, 20.5)), pt((24.5, 7))), ACC, 2.0)


def new_sketch(ic):
    plane(ic, [(2, 18), (8, 4), (24.5, 4), (18.5, 18)], 'steel')
    c = (13.25, 11)
    rx, ry, w = 5.2, 3.1, 1.7
    d = ('M%sa%s %s 0 1 0 %s 0a%s %s 0 1 0 %s 0Z' % (pt((c[0] - rx, c[1])), f(rx), f(ry), f(2 * rx), f(rx), f(ry), f(-2 * rx))
         + 'M%sa%s %s 0 1 0 %s 0a%s %s 0 1 0 %s 0Z' % (pt((c[0] - rx + w, c[1])), f(rx - w), f(ry - w), f(2 * (rx - w)),
                                                        f(rx - w), f(ry - w), f(-2 * (rx - w))))
    g = ic.mat('acc', 'curve', c[0] - rx, 0, c[0] + rx, 0, user=True)
    ic.add('<path d="%s" fill="%s" fill-rule="evenodd"/>' % (d, g))
    badge(ic, '+')


DRAW = {
    'CN.parallel': parallel, 'CN.perp': perpendicular, 'CN.horiz': horizontal, 'CN.vert': vertical,
    'CN.tangent': tangent, 'CN.smooth': smooth, 'CN.symmetric': symmetric, 'CN.equal': equal,
    'CN.collinear': collinear, 'CN.concentric': concentric, 'CN.lock': lock,
    'CN.autodim': autodim, 'CN.conset': conset, 'CN.showcons': showcons,
    'MD.move': move, 'MD.copy': copy, 'MD.mrotate': mrotate, 'MD.trim': trim, 'MD.extend': extend,
    'MD.split': split, 'MD.mscale': mscale, 'MD.stretch': stretch, 'MD.moffset': moffset,
    'IN.image': image, 'IN.points': points, 'IN.acad': acad, 'IN.constr': constr, 'IN.params': params,
    'IN.gear': gear_icon, 'IN.driven': driven, 'IN.sphere': centerline, 'IN.center': center,
    'IN.showfmt': showfmt,
    'IC.patrect': patrect, 'IC.patcirc': patcirc, 'IC.patmir': patmir,
    'single.layerBigIcon': layer_big, 'single.finishIcon': finish, 'single.newSketchIcon': new_sketch,
}
SMALL = {
    'CN.smooth': lambda ic: smooth(ic, sm=True), 'CN.collinear': lambda ic: collinear(ic, sm=True),
    'CN.conset': lambda ic: conset(ic, sm=True), 'IN.gear': lambda ic: gear_icon(ic, sm=True),
    'IN.points': lambda ic: points(ic, sm=True), 'IN.acad': lambda ic: acad(ic, sm=True),
    'IN.showfmt': lambda ic: showfmt(ic, sm=True), 'IC.patcirc': lambda ic: patcirc(ic, sm=True),
}

if __name__ == '__main__':
    run(DRAW, SMALL)
