#!/usr/bin/env python3
"""The 14 reference icons of SPEC v2 "Modern Crisp", drawn through tools/icon_redesign/lib/crisp.py.

    python3 tools/icon_redesign/families/ref.py            # writes design/icons/<MAP>/<key>.svg
    python3 tools/icon_redesign/families/ref.py --out DIR  # writes DIR/<MAP>/<key>.svg instead

The first ten start from the B-crisp study (tools/icon_redesign/study/steel-modern/draw.py); Revolve has the
v2 rotation arrow (arc_arrow_dimetric); WF.axis, AS.place, AS.constrain and MS.measure are new in v2.
These are the bar: every family generator draws through the same calls.
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
from crisp import (CON, INK, SEC, Iso, Solid, add, arc_arrow_dimetric, arrow, bore, box, component,  # noqa: E402
                   cylinder, dim, dot, face, lerp, line, plane, poly, pt, R, ring, rod, run, unit)


# ------------------------------------------------------------------------------------------- sketch (2D)
def line34(ic):
    line(ic, [(6, 22), (22, 6)])
    dot(ic, (6, 22), 'ink')
    dot(ic, (22, 6), 'acc')


def circle34(ic):
    ic.circle((14, 14), 10.5, stroke=INK, w=1.5)
    line(ic, [(14, 14), (21.42, 6.58)], SEC, 1.25)
    dot(ic, (14, 14), 'acc')


def rect34(ic):
    line(ic, [(5, 21), (23, 21), (23, 7), (5, 7)], close=True)
    dot(ic, (5, 21), 'ink')
    dot(ic, (23, 7), 'acc')


def coincident(ic):
    c = (13, 15.5)
    for far in ((2.5, 21.5), (23.5, 3.5)):
        line(ic, [far, add(c, unit(c, far), 6.0)])
    ring(ic, c, col=CON)                            # the constraint marker is constraint red (SPEC 5.5)
    ic.circle(c, 2.3, fill=CON)


def dimension(ic):
    p, q = (4.5, 21.5), (23.5, 21.5)
    dim(ic, p, q, 11, gap=4, over=5)
    line(ic, [p, q])
    dot(ic, p, 'ink')
    dot(ic, q, 'ink')


# ------------------------------------------------------------------------------------------- part (3D)
def extrude(ic):
    box(ic, Iso(16.75, 15.88), (0, 0, 0), (9.25, 9.25, 11), 'acc')
    arrow(ic, (3.25, 24), (3.25, 3.5))


def revolve(ic):
    # three-quarter body of revolution, the front-right wedge removed. The rotation arrow is concentric with
    # the top rim (same centre, ry = rx / 2, 2.75 u larger), runs round the BACK above the top face (on the
    # ground, so no ink over material), and ends in the mouth of the missing quarter, head tangent.
    cx, cy, rx, h = 13.5, 8.75, 9.25, 10.5
    cylinder(ic, (cx, cy), rx, h, 'acc', cut=(22, 108))
    arc_arrow_dimetric(ic, (cx, cy), rx + 2.75, 198, 396)


def fillet(ic):
    k = .32
    P = {'L': (3, 11.5), 'B': (14, 6), 'R': (25, 11.5), 'F': (14, 17),
         'Lb': (3, 19.75), 'Fb': (14, 25.25), 'Rb': (25, 19.75)}
    P["F'"] = add(P['F'], (-11 * k, -5.5 * k))
    P["R'"] = add(P['R'], (-11 * k, -5.5 * k))
    P["F''"] = add(P['F'], (0, 11 * k))
    P["R''"] = add(P['R'], (0, 11 * k))
    S = Solid(P, ['L', 'B', "R'", "R''", 'Rb', 'Fb', 'Lb'], {'L': R, 'B': R, 'Rb': R, 'Fb': R, 'Lb': R})
    face(ic, S.outline(), 'steel', 'shade')
    lf = S.path(['L', "F'", "F''", 'Fb', 'Lb'])          # the lit face; its corner follows the round
    lf = lf.replace('L%sL%s' % (pt(P["F'"]), pt(P["F''"])), 'L%sQ%s %s' % (pt(P["F'"]), pt(P['F']), pt(P["F''"])))
    face(ic, lf, 'steel', 'lit')
    face(ic, S.path(["F''", "R''", 'Rb', 'Fb']), 'steel', 'shade')
    face(ic, S.path(['L', 'B', "R'", "F'"]), 'steel', 'top')
    band = 'M%sL%sQ%s %sL%sQ%s %sZ' % (pt(P["F'"]), pt(P["R'"]), pt(P['R']), pt(P["R''"]),
                                        pt(P["F''"]), pt(P['F']), pt(P["F'"]))
    m = lerp(P["F'"], P["R'"], .5)
    face(ic, band, 'acc', 'band', x1=m[0] - 1.2, y1=m[1] - 1.2, x2=m[0] + 2.4, y2=m[1] + 5.6, user=True)
    a0 = S.R['L']['mid']
    ic.hairline('M%sL%s' % (pt(a0), pt(P["F'"])), a0[0], P["F'"][0])


def hole(ic):
    box(ic, Iso(14, 12.25), (0, 0, 0), (11.5, 11.5, 5.25), 'steel')
    bore(ic, (14, 12.75), 6.2, 3.1)


# ------------------------------------------------------------------------------------------- work features
def wplane(ic):
    plane(ic, [(2.5, 21.5), (9.5, 6.5), (25.5, 6.5), (18.5, 21.5)])


def waxis(ic):
    # a steel shaft (the reference) and the work axis through its centre: an accent rod standing out of the
    # top face and leaving again under the bottom rim. Material on material, so it may cross the solid.
    cx, cy, rx, h = 14, 11, 9, 7
    cylinder(ic, (cx, cy), rx, h, 'steel')
    rod(ic, (cx, cy), (cx, 2.0), r=.95, caps=(False, True), socket=True)
    rod(ic, (cx, cy + h + rx / 2), (cx, 26.0), r=.95, caps=(False, True))


# ------------------------------------------------------------------------------------------- assembly
def place(ic):
    component(ic, (14, 8.25), half=8.5, mat='acc')
    arrow(ic, (14, 1.5), (14, 7.0))


def constrain(ic):
    # mate: the accent part is pressed down onto the steel base, the two mating faces close the gap
    iso = Iso(14, 12.6)
    box(ic, iso, (0, 0, 0), (12, 12, 3.5), 'steel')
    box(ic, iso, (2.75, 2.75, 6), (6.5, 6.5, 6), 'acc')
    for x in (4.5, 23.5):
        arrow(ic, (x, 6.5), (x, 12.5))


# ------------------------------------------------------------------------------------------- measure
def measure(ic, marks=8, sm=False):
    # a steel rule lying on the lattice, its graduations cut in as shade-material marks, and the measured
    # length as the accent dimension above it (extension lines vertical, along world z)
    iso = Iso(6.25, 13.5)
    a, b, h = 19, 4, 2
    box(ic, iso, (0, 0, 0), (a, b, h), 'steel', hair=not sm)
    for i in range(1, marks):
        x = i * a / marks
        ln = (2.6 if sm else 2.2) if i % 2 == 0 or sm else 1.3
        w = .6 if sm else .35
        q = [iso.p(x - w, b - ln, h), iso.p(x + w, b - ln, h), iso.p(x + w, b, h), iso.p(x - w, b, h)]
        face(ic, poly(q), 'steel', 'shade')
    p0, p1 = iso.p(0, 0, h), iso.p(a, 0, h)
    dim(ic, p0, p1, 7.5, gap=1.75, over=1.5, dirn=(0, -1))


REFS = {
    'IC.line34': line34, 'IC.circle34': circle34, 'IC.rect34': rect34,
    'CN.coincident': coincident, 'CN.dim': dimension,
    'CR.extrude': extrude, 'CR.revolve': revolve, 'MO.fillet': fillet, 'MO.hole': hole,
    'WF.plane': wplane, 'WF.axis': waxis,
    'AS.place': place, 'AS.constrain': constrain, 'MS.measure': measure,
}

# 18 px masters (SPEC §2.4): the rule's graduations are under 2 u, so it gets four bold marks, no hairline
SMALL = {'MS.measure': lambda ic: measure(ic, marks=4, sm=True)}

if __name__ == '__main__':
    run(REFS, SMALL)
