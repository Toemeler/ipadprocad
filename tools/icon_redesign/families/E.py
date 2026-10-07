#!/usr/bin/env python3
"""Family E (SPEC v2 §11): the assembly icons, drawn through tools/icon_redesign/lib/crisp.py.

    python3 tools/icon_redesign/families/E.py            # writes design/icons/AS/*.svg and single/*.svg
    python3 tools/icon_redesign/families/E.py --out DIR  # writes DIR/<MAP>/<key>.svg instead

The component-cube language: a COMPONENT is the cube (component()), an ASSEMBLY is several cubes, a PART is
a machined L-block. AS.place and AS.constrain are references (ref.py); this file draws the rest of the tab.
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
from crisp import (ACC, ERR, EYE_HERO, INK, SEC, Iso, R, Solid, _arc, add, arc_arrow_dimetric, arrow,  # noqa: E402
                   badge, box, component, cylinder, eye, face, glass_box, ink_clear, line, lerp, mat_stops, poly, pt,
                   put_head, rod, run, sub, unit)


# ------------------------------------------------------------------------------------------- local primitives
def l_block(ic, iso, a, b, H, h, t, mat='steel', top_mat=None):
    """A machined L-block (a PART): profile in the x-z plane (tall back leg 0..t at height H, low front
    step t..a at height h), extruded along y by b. Non-convex, so it is built on Solid with its own
    silhouette (the step's inner corner E stays sharp). top_mat paints the two top faces. Candidate for
    the library (the part / L-solid)."""
    W = {'A': (0, 0, H), 'B': (t, 0, H), 'C': (t, b, H), 'D': (0, b, H),
         'E': (t, 0, h), 'G': (t, b, h), 'I': (a, 0, h), 'J': (a, b, h),
         'K': (a, 0, 0), 'M': (a, b, 0), 'N': (0, b, 0)}
    P = {k: iso.p(*v) for k, v in W.items()}
    sil = ['A', 'B', 'E', 'I', 'K', 'M', 'N', 'D']
    S = Solid(P, sil, {k: R for k in sil if k != 'E'})
    tm = top_mat or mat
    face(ic, S.outline(), mat, 'shade')
    face(ic, S.path(['D', 'C', 'G', 'J', 'M', 'N']), mat, 'lit')
    face(ic, S.path(['C', 'B', 'E', 'G']), mat, 'shade')
    face(ic, S.path(['J', 'I', 'K', 'M']), mat, 'shade')
    face(ic, S.path(['A', 'B', 'C', 'D']), tm, 'top')
    face(ic, S.path(['G', 'E', 'I', 'J']), tm, 'top')
    for chain in ((S.end('D'), P['C'], P['B'] if 'B' not in S.R else S.end('B')),
                  (P['G'], P['J'], S.end('I'))):
        ic.hairline(poly(chain, False), chain[0][0], chain[-1][0])
    return S


# ------------------------------------------------------------------------------------------- component
def create(ic):
    # Create In-Place: a new accent component, still a glass phantom, made in place against an existing
    # steel one (seen through it); INK + badge
    component(ic, (18.0, 1.5), half=7.0, mat='steel')
    glass_box(ic, Iso(11.25, 5.25 + 8.25), (0, 0, 0), (7.5, 7.5, 8.25))
    badge(ic, '+')


def copy(ic):
    # Copy Components: the steel original behind, its accent duplicate offset in front, INK copy arrow
    component(ic, (10.0, 1.5), half=7.0, mat='steel')
    component(ic, (17.5, 9.0), half=7.5, mat='acc')
    arrow(ic, (1.75, 19.75), (8.5, 23.125))


# ------------------------------------------------------------------------------------------- position
def _ground_dirs():
    s = 1 / math.hypot(1, .5)
    return {'+x': (s, .5 * s), '+y': (-s, .5 * s), '-x': (-s, -.5 * s), '-y': (s, -.5 * s)}


def freemove(ic):
    # Free Move: a steel component with four INK arrows on the ground along the dimetric x and y axes. Each
    # arrow starts where it clears the cube's silhouette by 1.25 u (the back two come out from behind it)
    # and all four have the same visible length, so the back ones are arrows too, not bare heads
    half, h = 5.5, 6.25
    top = (14, 7.0)
    S = component(ic, top, half=half, mat='steel', h=h)
    sil = [S.P[v] for v in S.sil]
    G = (14, top[1] + h + half / 2)
    for k in ('+x', '+y', '-x', '-y'):
        u = _ground_dirs()[k]
        t = 0.0
        while not ink_clear(add(G, u, t), [sil], 1.25):
            t += .1
        arrow(ic, add(G, u, t), add(G, u, t + 6.75))


def freerotate(ic):
    # Free Rotate: a steel component, the dimetric rotation arrow concentric with its top face, round the
    # back above it and forward at the right (SPEC §6.4)
    half = 8.0
    top = (14, 6.3)
    component(ic, top, half=half, mat='steel')
    c = (14, top[1] + half / 2)
    arc_arrow_dimetric(ic, c, half + 2.75, 160, 382)


# ------------------------------------------------------------------------------------------- relationships
def joint(ic, sm=False):
    # Joint (revolute): a hinge. Two parts, the steel leaf (back-left) and the accent leaf (back-right, the
    # component being jointed), open at 90 degrees behind a knuckle stack that alternates steel / accent /
    # steel, so the two parts visibly interleave on one pin. The pin (the joint origin, an accent rod)
    # stands out of the top knuckle with its socket.
    iso = Iso(14, 23.25)
    H, Lf, t = 12.5, 10.0, 1.5
    box(ic, iso, (-Lf, -t / 2, 0), (Lf, t, H), 'steel', hair=not sm)       # steel leaf along -x
    box(ic, iso, (-t / 2, -Lf, 0), (t, Lf, H), 'acc', hair=not sm)         # accent leaf along -y
    rx, g = 2.6, .6
    mats = ('steel',) if sm else ('steel', 'acc', 'steel')      # 18 px: one knuckle, no sub-1.25 gaps
    seg = (H - (len(mats) - 1) * g) / len(mats)
    for i, m in enumerate(mats):
        z1 = (i + 1) * seg + i * g
        top = iso.p(0, 0, z1)
        cylinder(ic, top, rx, seg, m, hair=not sm and i == len(mats) - 1)
    top = iso.p(0, 0, H)
    rod(ic, top, (top[0], top[1] - 4.5), r=1.0, caps=(False, True), socket=True)


def _two_parts(ic):
    # the shared context of Show / Show Sick / Hide All: two steel components apart on the ground, the
    # relationship marker in the gap between their feet
    component(ic, (7.0, 2.75), half=5.0, mat='steel')
    component(ic, (21.0, 2.75), half=5.0, mat='steel')
    return (14, 13.75)


def _marker(ic, m, col, sm):
    # the relationship marker: the target ring and its dot (18 px: bolder, bigger)
    if sm:
        ic.circle(m, 4.1, stroke=col, w=1.5)
        ic.circle(m, 1.9, fill=col)
    else:
        ic.circle(m, 2.4, stroke=col, w=1.0)
        ic.circle(m, 1.2, fill=col)


SM_MARK, SM_EYE = (14, 8.0), ((14, 20.0), 21.0)


def _context(ic, sm):
    """28: two steel parts with the marker between their feet. 18: the parts are dropped (at 0.64 they
    clog), the marker sits alone above a larger eye: marker + eye is the whole idea."""
    return SM_MARK if sm else _two_parts(ic)


def _eye(ic, sm, slash=False):
    c, w = SM_EYE if sm else EYE_HERO
    eye(ic, c, w, slash=slash, sm=sm)


def show(ic, sm=False):
    _marker(ic, _context(ic, sm), ACC, sm)
    _eye(ic, sm)


def showsick(ic, sm=False):
    m = _context(ic, sm)
    # the broken relationship: the ring split in two, the halves knocked apart (ERR, the one status mark)
    r = 4.1 if sm else 2.3
    for a0, a1, dx, dy in ((110, 250, -.6, .5), (290, 430, .6, -.5)):
        p0 = (m[0] + dx + r * math.cos(math.radians(a0)), m[1] + dy + r * math.sin(math.radians(a0)))
        p1 = (m[0] + dx + r * math.cos(math.radians(a1)), m[1] + dy + r * math.sin(math.radians(a1)))
        ic.stroke('M%s' % pt(p0) + _arc(r, r, 0, 1, p1), ERR, 1.5)
    _eye(ic, sm)


def hideall(ic, sm=False):
    _marker(ic, _context(ic, sm), SEC, sm)
    _eye(ic, sm, slash=True)


# ------------------------------------------------------------------------------------------- singles
def assembly_menu(ic, sm=False):
    # an assembly document: three stacked component cubes, the top one accent
    # the cubes keep the component proportion (height 1.1 x side, as component() draws it)
    s, g = 6.5, 1.4
    h = round(s * 1.1, 2)
    iso = Iso(10.0, 15.9)
    box(ic, iso, (0, 0, 0), (s, s, h), 'steel')
    box(ic, iso, (s + g, 0, 0), (s, s, h), 'steel')
    box(ic, iso, ((s + g) / 2, 0, h + g), (s, s, h), 'acc')


def part_menu(ic):
    # a part document: one machined steel L-block, its top faces accent
    iso = Iso(12.5, 12.75)
    l_block(ic, iso, 14, 10, 11, 5, 6, 'steel', top_mat='acc')


def return_icon(ic):
    # leave in-place edit: an INK U-turn arrow rising out of the accent component and turning back left
    component(ic, (16.75, 10.0), half=8.0, mat='acc', h=8.0)
    c, r = (12.0, 6.5), 4.75
    start = (c[0] + r, 8.5)
    d = 'M%sL%s' % (pt(start), pt((c[0] + r, c[1])))
    d += _arc(r, r, 0, 0, (c[0] - r, c[1]))
    tip = (c[0] - r, 16.5)
    d += 'L%s' % pt((tip[0], tip[1] - 3.0))
    ic.stroke(d, INK, 1.25)
    put_head(ic, tip, (0, 1), INK)


DRAW = {
    'AS.create': create, 'AS.freemove': freemove, 'AS.freerotate': freerotate, 'AS.joint': joint,
    'AS.show': show, 'AS.showsick': showsick, 'AS.hideall': hideall, 'AS.copy': copy,
    'single.assemblyMenuIcon': assembly_menu, 'single.part3dMenuIcon': part_menu,
    'single.returnIcon': return_icon,
}
SMALL = {
    'AS.joint': lambda ic: joint(ic, sm=True),
    'AS.show': lambda ic: show(ic, sm=True),
    'AS.showsick': lambda ic: showsick(ic, sm=True),
    'AS.hideall': lambda ic: hideall(ic, sm=True),
    'single.assemblyMenuIcon': lambda ic: assembly_menu(ic, sm=True),
}

if __name__ == '__main__':
    run(DRAW, SMALL)
