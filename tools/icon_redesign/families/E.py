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
from crisp import (ACC, ERR, INK, SEC, Iso, R, Solid, _arc, add, arc_arrow_dimetric, arrow, badge,  # noqa: E402
                   box, component, cylinder, face, line, lerp, mat_stops, poly, pt, put_head, rod, run, sub, unit)


# ------------------------------------------------------------------------------------------- local primitives
def glass_box(ic, iso, o, size, mat='acc'):
    """A see-through box (a phantom / new-in-place body): every face takes the PANE ramp with glass opacity
    (SPEC §4: the only material allowed to be glass). Faces are separated by placing each face at a different
    point of one ramp: top at the light end, lit face mid, shade face at the dark end. Rounded silhouette,
    hairline on the lit top edges. Candidate for the library (glass solids)."""
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
        return ic.mat(mat, 'pane', 0, y0, 0, y1, user=True, opacity=(.85, .70))
    # the shade face sits past the end of the ramp (all dark stop), the top before its start (light stop)
    ic.fill(S.path(['F', 'R', 'Rb', 'Fb']), g(top_y - 2 * span, top_y - span * .2))
    ic.fill(S.path(['L', 'F', 'Fb', 'Lb']), g(P['L'][1] - span * .55, bot_y + span * .35))
    ic.fill(S.path(['B', 'R', 'F', 'L']), g(top_y + span * .55, top_y + span * 1.6))
    pts = [S.end('L'), P['F'], S.end('R')]
    ic.hairline(poly(pts, False), pts[0][0], pts[-1][0])
    return S


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


def eye(ic, c, w=12.0, hgt=7.0, col=INK, slash=False, pupil=2.0):
    """The show / hide eye (SPEC §6.6): INK 1.5 lens and pupil; slash=True adds the INK 1.5 slash."""
    x0, x1 = c[0] - w / 2, c[0] + w / 2
    k = hgt / 2 / .75          # quadratic control so the lens is hgt tall
    d = 'M%sQ%s %sQ%s %sZ' % (pt((x0, c[1])), pt((c[0], c[1] - k)), pt((x1, c[1])),
                               pt((c[0], c[1] + k)), pt((x0, c[1])))
    ic.stroke(d, col, 1.5)
    ic.circle(c, pupil, fill=col)
    if slash:
        ic.stroke('M%sL%s' % (pt((c[0] - w * .4, c[1] + hgt * .72)), pt((c[0] + w * .4, c[1] - hgt * .72))), col, 1.5)


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
    # Free Move: a steel component with four INK arrows on the ground along the dimetric x and y axes,
    # radiating from under it (each starts clear of the silhouette)
    half, h = 6.5, 7.15
    top = (14, 5.5)
    component(ic, top, half=half, mat='steel', h=h)
    G = (14, top[1] + h + half / 2)
    for k, (t0, t1) in (('+x', (5.1, 13.6)), ('+y', (5.1, 13.6)), ('-x', (8.3, 13.6)), ('-y', (8.3, 13.6))):
        u = _ground_dirs()[k]
        arrow(ic, add(G, u, t0), add(G, u, t1))


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


def _two_parts(ic, sm=False):
    # the shared context of Show / Show Sick / Hide All: two steel components apart on the ground, the
    # relationship marker in the gap between their feet
    component(ic, (7.0, 2.75), half=5.0, mat='steel', hair=not sm)
    component(ic, (21.0, 2.75), half=5.0, mat='steel', hair=not sm)
    return (14, 13.75)


def _eye(ic, sm, slash=False):
    # at 18 px the pupil shrinks so the lens keeps a clear gap round it (SPEC §2.4)
    eye(ic, (14, 21.25), w=16, hgt=7.0, pupil=1.4 if sm else 2.0, slash=slash)


def _marker(ic, m, col, sm):
    # the relationship marker: the target ring and its dot; at 18 px a bolder ring alone
    if sm:
        ic.circle(m, 2.5, stroke=col, w=1.5)
    else:
        ic.circle(m, 2.4, stroke=col, w=1.0)
        ic.circle(m, 1.2, fill=col)


def show(ic, sm=False):
    _marker(ic, _two_parts(ic, sm), ACC, sm)
    _eye(ic, sm)


def showsick(ic, sm=False):
    m = _two_parts(ic, sm)
    # the broken relationship: the ring split in two, the halves knocked apart (ERR, the one status mark)
    r = 2.5 if sm else 2.3
    for a0, a1, dx, dy in ((110, 250, -.5, .45), (290, 430, .5, -.45)):
        p0 = (m[0] + dx + r * math.cos(math.radians(a0)), m[1] + dy + r * math.sin(math.radians(a0)))
        p1 = (m[0] + dx + r * math.cos(math.radians(a1)), m[1] + dy + r * math.sin(math.radians(a1)))
        ic.stroke('M%s' % pt(p0) + _arc(r, r, 0, 1, p1), ERR, 1.5)
    _eye(ic, sm)


def hideall(ic, sm=False):
    _marker(ic, _two_parts(ic, sm), SEC, sm)
    _eye(ic, sm, slash=True)


# ------------------------------------------------------------------------------------------- singles
def assembly_menu(ic, sm=False):
    # an assembly document: three stacked component cubes, the top one accent
    s, g = 6.5, 1.4
    iso = Iso(10.0, 15.2)
    box(ic, iso, (0, 0, 0), (s, s, s), 'steel', hair=not sm)
    box(ic, iso, (s + g, 0, 0), (s, s, s), 'steel', hair=not sm)
    box(ic, iso, ((s + g) / 2, 0, s + g), (s, s, s), 'acc', hair=not sm)


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
