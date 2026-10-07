#!/usr/bin/env python3
"""Family C of SPEC v2 "Modern Crisp": part Create / Modify / Direct (SPEC §11, family C).

    python3 tools/icon_redesign/families/C.py            # writes design/icons/<MAP>/<key>.svg
    python3 tools/icon_redesign/families/C.py --out DIR  # writes DIR/<MAP>/<key>.svg instead

Keys: CR sweep loft coil emboss derive decal; MO chamfer shell draft thread combine thicken split direct
deleteface; DE deMove deSize deScale deRotate deDelete. (CR.extrude, CR.revolve, MO.fillet and MO.hole are
references, drawn by ref.py.)

Local primitives (candidates for lib/crisp.py), all drawn through Solid / face / ic.mat:
  tube()          a round bar swept along a horizontal 3D path (exact parallel-projection silhouette), with
                  its visible end cap: the profile
  helix_band()    a helical ribbon on a cylinder (coil, thread): front half-turns in curve material, back
                  half-turns (the inside) in the shade face
  loft_sq_round() a solid blending a square base into a round top
  glass_box()     a see-through box (glass pane ramp per face)
  glass_cyl()     a see-through cylinder
  clip()          convex polygon clipping (Sutherland-Hodgman), for faces seen through an opening
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'lib'))
from crisp import (ACC, GLASS, INK, R, SEC, Iso, Solid, _hull, add, arc_arrow, arc_arrow_dimetric,  # noqa: E402
                   arrow, badge, bore, box, component, construct, cylinder, face, lerp, line, plane, poly,
                   prism, pt, rod, run, solid, sub, unit, work_axis)


# ------------------------------------------------------------------------------------------- local helpers
def E(c, rx, ry, th, dy=0.0):
    a = math.radians(th)
    return (c[0] + rx * math.cos(a), c[1] + dy + ry * math.sin(a))


def ell(c, rx, ry, a0, a1, n=None, dy=0.0):
    n = n or max(6, int(abs(a1 - a0) / 6))
    return [E(c, rx, ry, a0 + (a1 - a0) * i / n, dy) for i in range(n + 1)]


def _area(p):
    return sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p))) / 2


def clip(subject, clipper):
    """Sutherland-Hodgman: subject polygon clipped by a CONVEX clipper polygon (screen points)."""
    s = 1 if _area(clipper) > 0 else -1
    out = list(subject)
    n = len(clipper)
    for i in range(n):
        a, b = clipper[i], clipper[(i + 1) % n]
        inside = lambda p: s * ((b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])) >= -1e-9

        def cut(p, q):
            d1 = (b[0] - a[0]) * (p[1] - a[1]) - (b[1] - a[1]) * (p[0] - a[0])
            d2 = (b[0] - a[0]) * (q[1] - a[1]) - (b[1] - a[1]) * (q[0] - a[0])
            t = d1 / (d1 - d2)
            return lerp(p, q, t)
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


def smooth(pts):
    """A closed path through many sampled points (they are dense, so straight segments)."""
    return poly(pts)


def rounded(pts, r=R, sharp=()):
    """A closed screen polygon with every corner (except indices in sharp) filleted by r (the solid rule)."""
    P = {str(i): p for i, p in enumerate(pts)}
    S = Solid(P, list(P), {str(i): (0 if i in sharp else r) for i in range(len(pts))})
    return S.outline()


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
        p1, p2 = sec_pt(C, n, phi), sec_pt(C, n, phi + math.pi)
        side_a.append((p1, phi))
        side_b.append((p2, phi + math.pi))
    # orient: side_a is the upper-left one
    mid = len(secs) // 2
    if side_a[mid][0][1] > side_b[mid][0][1]:
        side_a, side_b = side_b, side_a

    def end_arc(k, lead):
        C, T, n = secs[k]
        f0, f1 = side_a[k][1], side_b[k][1]
        ts = sub(iso.p(*[C[i] + T[i] for i in range(3)]), iso.p(*C))
        best = None
        for sgn in (1, -1):
            arcp = [sec_pt(C, n, f0 + sgn * math.pi * j / 16) for j in range(17)]
            m = arcp[8]
            score = (m[0] - iso.p(*C)[0]) * ts[0] + (m[1] - iso.p(*C)[1]) * ts[1]
            if best is None or (score > best[0]) == lead:
                best = (score, arcp)
        return best[1]
    lead_arc = end_arc(len(secs) - 1, True)     # from side_a to side_b round the near end
    tail_arc = end_arc(0, False)                # from side_a to side_b round the far end
    outline = [p for p, _ in side_a] + lead_arc[1:-1] + [p for p, _ in reversed(side_b)] + list(reversed(tail_arc))[1:-1]
    # gradient across the mean direction
    A, Bp = iso.p(*path[0]), iso.p(*path[-1])
    u = unit(A, Bp)
    nrm = (u[1], -u[0])
    if nrm[1] > 0 or (abs(nrm[1]) < 1e-9 and nrm[0] < 0):
        nrm = (-nrm[0], -nrm[1])               # toward the upper side
    allp = [p for p, _ in side_a + side_b]
    proj = [(p[0] * nrm[0] + p[1] * nrm[1]) for p in allp]
    c0 = lerp(A, Bp, .5)
    base = c0[0] * nrm[0] + c0[1] * nrm[1]
    hi, lo = max(proj) - base, min(proj) - base
    g1, g2 = add(c0, nrm, hi), add(c0, nrm, lo)
    face(ic, smooth(outline), mat, 'curve', x1=g1[0], y1=g1[1], x2=g2[0], y2=g2[1], user=True)
    C, T, n = secs[-1]
    cap = [sec_pt(C, n, 2 * math.pi * j / 48) for j in range(48)]
    if sum(T[i] for i in range(3)) > 0:
        face(ic, smooth(cap), mat, cap_kind)
        if hair:
            # the profile's upper-left rim
            arcp = sorted(range(48), key=lambda j: cap[j][0] + cap[j][1])[:1][0]
            seg = [cap[(arcp + j) % 48] for j in range(-7, 8)]
            seg.sort(key=lambda p: p[0])
            ic.hairline(poly(seg, False), seg[0][0], seg[-1][0], (.75, .2))
    return cap, (A, Bp)


def helix_band(ic, c, rx, th0, th1, pitch, t, mat='acc', ry=None, front=True, back=True, inner='shade'):
    """A helical ribbon of height t on the cylinder (c = centre at th0, screen; 90 = front). It climbs pitch
    per turn. Pieces are split at the rims of the half-turns: back pieces (the inside) in the inner kind,
    front pieces in the cylinder's curve ramp. Returns the centre-line function y(th)."""
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
                ys = [yc(a), yc(b)]
                face(ic, piece(a, b), mat, inner)
    if front:
        for a, b in pieces:
            if is_front(a, b):
                face(ic, piece(a, b), mat, 'curve', x1=c[0] - rx, y1=0, x2=c[0] + rx, y2=0, user=True)
    return yc


def glass_box(ic, iso, o, size, mat='acc'):
    """A see-through box: its three visible faces in the glass pane ramp, each ramp turned so neighbouring
    faces meet light against dark (no outline). Returns the screen points."""
    x, y, z = o
    a, b, h = size
    W = {'B': (x, y, z + h), 'R': (x + a, y, z + h), 'F': (x + a, y + b, z + h), 'L': (x, y + b, z + h),
         'Bb': (x, y, z), 'Rb': (x + a, y, z), 'Fb': (x + a, y + b, z), 'Lb': (x, y + b, z)}
    P = {k: iso.p(*v) for k, v in W.items()}
    sil = ['B', 'R', 'Rb', 'Fb', 'Lb', 'L']
    S = Solid(P, sil, {k: R for k in sil})

    def bb(names):
        xs = [P[n][0] for n in names]
        ys = [P[n][1] for n in names]
        return min(xs), min(ys), max(xs), max(ys)
    x0, y0, x1, y1 = bb(['L', 'F', 'Fb', 'Lb'])
    face(ic, S.path(['L', 'F', 'Fb', 'Lb']), mat, 'pane', x1=x0, y1=y0, x2=x0 + (x1 - x0) * .4, y2=y1,
         user=True, opacity=GLASS)
    x0, y0, x1, y1 = bb(['F', 'R', 'Rb', 'Fb'])
    face(ic, S.path(['F', 'R', 'Rb', 'Fb']), mat, 'pane', x1=x0 + (x1 - x0) * .4, y1=y1, x2=x0, y2=y0 - 6,
         user=True, opacity=GLASS)
    x0, y0, x1, y1 = bb(['B', 'R', 'F', 'L'])
    face(ic, S.path(['B', 'R', 'F', 'L']), mat, 'pane', x1=x0, y1=y0, x2=x1, y2=y1 + 3, user=True,
         opacity=GLASS)
    a0 = S.end('L')
    ic.hairline(poly([a0, P['F'], S.end('R')], False), a0[0], S.end('R')[0])
    return S


def glass_cyl(ic, c, rx, h, mat='steel'):
    """A see-through vertical cylinder (c = top centre): side and top in the glass pane ramp."""
    ry = rx / 2
    side = 'M%s' % pt(E(c, rx, ry, 0)) + 'A%s %s 0 0 1 %s' % (rx, ry, pt(E(c, rx, ry, 180))) + \
           'L%s' % pt(E(c, rx, ry, 180, h)) + 'A%s %s 0 0 0 %s' % (rx, ry, pt(E(c, rx, ry, 0, h))) + 'Z'
    face(ic, side, mat, 'pane', x1=c[0] - rx, y1=0, x2=c[0] + rx, y2=0, user=True, opacity=GLASS)
    ic.ellipse(c, rx, ry, ic.mat(mat, 'pane', c[0] - rx, c[1] - ry, c[0] + rx, c[1] + ry, user=True,
                                 opacity=GLASS))
    a = E(c, rx, ry, 178)
    ic.hairline('M%sA%s %s 0 0 0 %s' % (pt(a), rx, ry, pt(E(c, rx, ry, 96))), a[0], E(c, rx, ry, 96)[0], (.75, .2))


def accent_face(ic, S, name, kind=None):
    """Repaint one face of a steel Solid in the accent material (the face the tool acts on)."""
    face(ic, S.path(S.faces[name]), 'acc', kind or S.kinds[name])


def top_hair(ic, S):
    """Re-lay the hairline on a box's lit top edges after a face was repainted."""
    a0, b0 = S.end('L'), S.end('R')
    ic.hairline(poly([a0, S.P['F'], b0], False), a0[0], b0[0])


# ------------------------------------------------------------------------------------------- CR: create
def sweep(ic, r=2.6, A=3.4, split=.6, L=26.0):
    # a round bar swept along an S path: the profile (its cap) at the leading end, the rest of the path an
    # SEC line on the ground ahead of it. The path runs from the back (upper right) toward the viewer
    # (lower left); it is fitted into the keyline automatically.
    d = (0.45, 1.0)
    dn = math.hypot(*d)
    d = (d[0] / dn, d[1] / dn)
    nv = (d[1], -d[0])

    def P(t):
        w = A * math.sin(math.pi * 1.7 * t - .35)
        return (d[0] * L * t + nv[0] * w, d[1] * L * t + nv[1] * w, 0.0)
    ts = [i / 90 for i in range(91)]
    z = Iso(0, 0)
    pts = [z.p(*P(t)) for t in ts]
    body_pts = [z.p(*P(t * split)) for t in ts]
    m = r * 1.25
    x0 = min(min(p[0] for p in body_pts) - m, min(p[0] for p in pts))
    x1 = max(max(p[0] for p in body_pts) + m, max(p[0] for p in pts))
    y0 = min(min(p[1] for p in body_pts) - m, min(p[1] for p in pts))
    y1 = max(max(p[1] for p in body_pts) + m, max(p[1] for p in pts))
    iso = Iso(14 - (x0 + x1) / 2, 14 - (y0 + y1) / 2)
    body = [P(t * split) for t in ts]
    cap, ends = tube(ic, iso, body, r, 'acc', cap_kind='top')
    ahead = [iso.p(*P(split + (1 - split) * t)) for t in ts]

    def near(p):
        return min(math.dist(p, q) for q in cap) < 1.0 + .75 or _pip(p, cap)
    k = 0
    while k < len(ahead) - 1 and near(ahead[k]):
        k += 1
    line(ic, ahead[k:], SEC, 1.5)


def _pip(p, polyg):
    c = False
    n = len(polyg)
    for i in range(n):
        a, b = polyg[i], polyg[(i + 1) % n]
        if (a[1] > p[1]) != (b[1] > p[1]) and p[0] < a[0] + (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]):
            c = not c
    return c


def loft_sq_round(ic, iso, s, rho, h, hp=0.0, mat='acc'):
    """A loft: a square section of side s (world, centred on the iso origin; a straight prism up to hp)
    blended into a round section of radius rho at height h. The square's corners run up as ridges that
    end on the rim. Returns (Solid, rim centre, rim rx)."""
    hs = s / 2
    P = {'Lb': iso.p(-hs, hs, 0), 'Fb': iso.p(hs, hs, 0), 'Rb': iso.p(hs, -hs, 0),
         'L2': iso.p(-hs, hs, hp), 'F2': iso.p(hs, hs, hp), 'R2': iso.p(hs, -hs, hp), 'B2': iso.p(-hs, -hs, hp)}
    c = iso.p(0, 0, h)
    rx = rho * math.sqrt(2)
    ry = rx / 2
    for a in range(0, 360, 3):
        P['e%d' % a] = E(c, rx, ry, a)
    cand = {k: v for k, v in P.items() if k != 'B2' and (hp > 0 or k not in ('L2', 'F2', 'R2'))}
    hull = _hull(cand)
    rad = {k: R for k in hull if not k.startswith('e')}
    S = Solid(P, hull, rad)
    face(ic, S.outline(), mat, 'shade')
    ang = lambda k: int(k[1:])
    a_l = min(ang(k) for k in hull if k.startswith('e') and 90 < ang(k) < 270)
    rs = [ang(k) for k in hull if k.startswith('e') and (ang(k) < 90 or ang(k) > 270)]
    a_r = min((a if a < 90 else a - 360) for a in rs)
    lo = ['Lb', 'Fb'] if hp <= 0 else ['Lb', 'Fb', 'F2']
    left = lo + ['e%d' % a for a in range(90, a_l + 1, 3)] + ([] if hp <= 0 else ['L2'])
    ro = ['Fb', 'Rb'] if hp <= 0 else ['Fb', 'Rb', 'R2']
    right = ro + ['e%d' % (a % 360) for a in range(a_r, 91, 3)] + ([] if hp <= 0 else ['F2'])
    face(ic, S.path(right), mat, 'shade')
    face(ic, S.path(left), mat, 'lit')
    ic.ellipse(c, rx, ry, ic.mat(mat, 'top'))
    a = E(c, rx, ry, 178)
    ic.hairline('M%sA%s %s 0 0 0 %s' % (pt(a), rx, ry, pt(E(c, rx, ry, 96))), a[0], E(c, rx, ry, 96)[0], (.75, .2))
    return S, c, rx


def loft(ic):
    loft_sq_round(ic, Iso(14, 20.25), 10.5, 3.9, 12.0, hp=3.5)


def coil(ic, sm=False):
    # a three-turn helical spring (a band of curve material) round its SEC axis, shown above and below
    rx = 7.25
    pitch, t = (3.8, 1.9) if not sm else (4.3, 2.4)
    ry = rx / 2
    cy = 14 + 1.5 * pitch                     # centres the coil: its mid-height is 14
    c = (14, cy)
    yc = helix_band(ic, c, rx, 0, 1080, pitch, t, inner='shade')
    top = yc(990) - t / 2           # the back of the top turn
    bot = yc(90) + t / 2            # the front of the bottom turn
    if top - 1.25 - 1.5 > 1.0:
        ic.stroke('M%sL%s' % (pt((c[0], 1.5)), pt((c[0], top - 1.25))), SEC, 1.25)
    if 26.5 - bot - 1.25 > 1.0:
        ic.stroke('M%sL%s' % (pt((c[0], bot + 1.25)), pt((c[0], 26.5))), SEC, 1.25)


def emboss(ic):
    # a steel slab with a raised accent "T" on its top face
    iso = Iso(14, 14.5)
    S = box(ic, iso, (0, 0, 0), (11.5, 11.5, 4.5), 'steel')
    z = 4.5
    th, hz = 3.0, 3.0
    box(ic, iso, (1.25, 1.25, z), (9, th, hz), 'acc', hair=False)
    box(ic, iso, (5.75 - th / 2, 1.25 + th, z), (th, 9 - th, hz), 'acc', hair=False, sil_r={'B': 0, 'R': 0})


def derive(ic):
    # the source part (steel) and the derived part (accent), linked by an INK arrow on the ground
    component(ic, (9, 2.25), half=5.75, mat='steel')
    component(ic, (19.25, 12.5), half=6.25, mat='acc')
    arc_arrow(ic, (13, 15.75), 5.25, 5.25, 180, 95)


def decal(ic):
    # a steel block with an accent picture (mountains and sun cut out) applied to its lit face
    iso = Iso(10.75, 13.6)
    a, b, h = 14, 7.5, 10.0
    box(ic, iso, (0, 0, 0), (a, b, h), 'steel')
    q = lambda x, z: iso.p(x, b, z)
    x0, x1, z0, z1 = 1.6, 12.4, 1.5, 8.5
    plane(ic, [q(x0, z1), q(x1, z1), q(x1, z0), q(x0, z0)], 'acc', hair=False, r=.8)
    mnt = [q(2.6, z0 + 1.0), q(5.9, 6.4), q(7.6, 4.4), q(8.9, 5.6), q(11.4, z0 + 1.0)]
    face(ic, poly(mnt), 'steel', 'top')
    ic.circle(q(10.0, 7.0), .95, fill=ic.mat('steel', 'top'))


# ------------------------------------------------------------------------------------------- MO: modify
def chamfer(ic):
    k = .36
    P = {'L': (3, 11.5), 'B': (14, 6), 'R': (25, 11.5), 'F': (14, 17),
         'Lb': (3, 19.75), 'Fb': (14, 25.25), 'Rb': (25, 19.75)}
    P["F'"] = add(P['F'], (-11 * k, -5.5 * k))
    P["R'"] = add(P['R'], (-11 * k, -5.5 * k))
    P["F''"] = add(P['F'], (0, 11 * k))
    P["R''"] = add(P['R'], (0, 11 * k))
    S = Solid(P, ['L', 'B', "R'", "R''", 'Rb', 'Fb', 'Lb'], {'L': R, 'B': R, "R'": R, "R''": R, 'Rb': R, 'Fb': R, 'Lb': R})
    face(ic, S.outline(), 'steel', 'shade')
    face(ic, S.path(['L', "F'", "F''", 'Fb', 'Lb']), 'steel', 'lit')
    face(ic, S.path(["F''", "R''", 'Rb', 'Fb']), 'steel', 'shade')
    face(ic, S.path(['L', 'B', "R'", "F'"]), 'steel', 'top')
    face(ic, S.path(["F'", "R'", "R''", "F''"]), 'acc', 'lit')
    a0 = S.R['L']['mid']
    ic.hairline('M%sL%s' % (pt(a0), pt(P["F'"])), a0[0], P["F'"][0])


def shell(ic):
    # a steel block hollowed out: open top, thin walls; the cavity (the result) in accent
    iso = Iso(14, 12.5)
    a, h, t = 11.5, 8.5, 1.5
    S = box(ic, iso, (0, 0, 0), (a, a, h), 'steel')
    d = h - 1.6
    W = lambda x, y, z: iso.p(x, y, z)
    op = [W(t, t, h), W(a - t, t, h), W(a - t, a - t, h), W(t, a - t, h)]
    zf = h - d
    floor = [W(t, t, zf), W(a - t, t, zf), W(a - t, a - t, zf), W(t, a - t, zf)]
    wall_y = [W(t, t, h), W(a - t, t, h), W(a - t, t, zf), W(t, t, zf)]      # back wall, faces +y: lit
    wall_x = [W(t, t, h), W(t, a - t, h), W(t, a - t, zf), W(t, t, zf)]      # back-left wall, faces +x
    face(ic, rounded(op, .45), 'acc', 'shade')
    face(ic, poly(clip(floor, op)), 'acc', 'top')
    face(ic, poly(clip(wall_y, op)), 'acc', 'lit')
    face(ic, poly(clip(wall_x, op)), 'acc', 'shade')


def draft(ic):
    # a steel block whose sides taper (wider at the foot); the drafted face accent; INK pull direction
    iso = Iso(12.25, 16.5)
    s, dd, h = 9.75, 1.9, 10.5
    W = {'b0': (0, 0, 0), 'b1': (s, 0, 0), 'b2': (s, s, 0), 'b3': (0, s, 0),
         't0': (dd, dd, h), 't1': (s - dd, dd, h), 't2': (s - dd, s - dd, h), 't3': (dd, s - dd, h)}
    faces = {'top': ['t0', 't1', 't2', 't3'], 'bot': ['b0', 'b1', 'b2', 'b3'],
             'sy': ['b3', 'b2', 't2', 't3'], 'sx': ['b1', 'b2', 't2', 't1'],
             'sb': ['b0', 'b1', 't1', 't0'], 'sl': ['b0', 'b3', 't3', 't0']}
    S = solid(ic, iso, W, faces, 'steel', hair=False)
    accent_face(ic, S, 'sy', 'lit')
    a0, b0 = S.end('t3') if 't3' in S.sil else S.P['t3'], S.end('t1') if 't1' in S.sil else S.P['t1']
    ic.hairline(poly([a0, S.P['t2'], b0], False), a0[0], b0[0])
    arrow(ic, (24.75, 23.5), (24.75, 4))


def thread_band(ic, c, rx, pitch, t, tooth=.85):
    """One front half-turn of a thread crest: a helical band on the cylinder side (curve ramp) whose ends
    stand out of the silhouette as the thread's teeth."""
    ry = rx / 2
    yc = lambda th: c[1] + ry * math.sin(math.radians(th)) - pitch * th / 360.0
    xc = lambda th: c[0] + rx * math.cos(math.radians(th))
    ths = [180 - 180 * i / 36 for i in range(37)]          # left -> right
    up = [(xc(h), yc(h) - t / 2) for h in ths]
    dn = [(xc(h), yc(h) + t / 2) for h in reversed(ths)]
    tl = (c[0] - rx - tooth, yc(180))
    tr = (c[0] + rx + tooth, yc(0))
    face(ic, poly([tl] + up + [tr] + dn), 'acc', 'curve', x1=c[0] - rx, y1=0, x2=c[0] + rx, y2=0, user=True)


def thread(ic, sm=False):
    # a steel shaft (bolt) whose lower part carries the accent thread: helical crests with teeth at the
    # silhouette
    c, rx, h = (14, 4.75), 6.75, 17.5
    cylinder(ic, c, rx, h, 'steel', hair=not sm)
    pitch, t = (3.6, 1.9) if not sm else (4.6, 2.5)
    n = 4 if not sm else 3
    y0 = c[1] + h - 1.0 - t / 2
    for k in range(n):
        thread_band(ic, (c[0], y0 - k * pitch), rx, pitch, t)


def combine(ic):
    # Boolean: the target body (accent box) joined by a tool body (steel glass cylinder) that overlaps it
    iso = Iso(10.5, 13.5)
    box(ic, iso, (0, 0, 0), (9.5, 9.5, 9.5), 'acc')
    glass_cyl(ic, (18.25, 12.25), 6.5, 8.75)


def thicken(ic):
    # a thin steel sheet and the accent thickened slab above it, INK offset arrow beside
    iso = Iso(16.0, 16.0)
    a = 10.0
    box(ic, iso, (0, 0, 0), (a, a, 1.25), 'steel')
    box(ic, iso, (0, 0, 4.0), (a, a, 4.25), 'acc')
    p_l = iso.p(0, a, 0)
    arrow(ic, (3.25, p_l[1] + 1.25), (3.25, iso.p(0, a, 8.25)[1] - 1.5))


def split(ic, sm=False):
    # a block split by a steel glass plane: the back half steel, the front half accent, moved apart
    iso = Iso(11.5, 13.25)
    b, h = 9, 8.5
    box(ic, iso, (0, 0, 0), (5.25, b, h), 'steel', hair=not sm)
    xp = 6.6
    plane(ic, [iso.p(xp, -3.5, h + 3.5), iso.p(xp, b + 2.0, h + 3.5), iso.p(xp, b + 2.0, -1.5),
               iso.p(xp, -3.5, -1.5)], 'steel', glass=True, hair=not sm)
    box(ic, iso, (8.0, 0, 0), (5.25, b, h), 'acc', hair=not sm)


def direct(ic):
    # Direct edit: a steel block, the selected face accent, and the INK 3D move gizmo beside it
    iso = Iso(11.5, 15.5)
    S = box(ic, iso, (0, 0, 0), (9, 9, 8), 'steel', hair=False)
    accent_face(ic, S, 'top')
    top_hair(ic, S)
    o = (21.5, 13.5)
    arrow(ic, o, (21.5, 3.25))
    arrow(ic, o, (21.5 + 5.0, 13.5 + 2.5))


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


def deleteface(ic):
    # a steel block with its right face deleted (a surface body now): its inside shows through the opening,
    # the missing face is an SEC dashed ghost along its old edges, INK minus badge
    iso = Iso(11, 12.75)
    a, b, h = 9, 9, 9
    W = {'B': (0, 0, h), 'R': (a, 0, h), 'F': (a, b, h), 'L': (0, b, h),
         'Bb': (0, 0, 0), 'Rb': (a, 0, 0), 'Fb': (a, b, 0), 'Lb': (0, b, 0)}
    P = {k: iso.p(*v) for k, v in W.items()}
    sil = ['B', 'R', 'Rb', 'Fb', 'Lb', 'L']
    S = Solid(P, sil, {k: R for k in sil})
    opening = round_pts([P['F'], P['R'], P['Rb'], P['Fb']], R, which=(1, 2, 3))
    # the inside, seen through the opening: one dark recess (deep ramp, dark under the top edge)
    face(ic, poly(opening), 'steel', 'deep', x1=0, y1=P['R'][1], x2=0, y2=P['Fb'][1], user=True)
    face(ic, S.path(['L', 'F', 'Fb', 'Lb']), 'steel', 'lit')
    face(ic, S.path(['B', 'R', 'F', 'L']), 'steel', 'top')
    a0, b0 = S.end('L'), S.end('R')
    ic.hairline(poly([a0, P['F'], b0], False), a0[0], b0[0])
    construct(ic, poly([P['F'], P['R'], P['Rb'], P['Fb']]))
    badge(ic, '-')


# ------------------------------------------------------------------------------------------- DE: direct edit
DE_ISO = (10.0, 13.5)
DE_SIZE = (9.5, 7.5, 7.5)       # the Direct-edit block (deMove, deDelete); the moved slab is its last 4 u


def de_move(ic):
    # the selected face pushed out of the block: the new slab accent, the INK arrow along the push
    iso = Iso(*DE_ISO)
    a, b, h = DE_SIZE
    box(ic, iso, (0, 0, 0), (a - 4, b, h), 'steel')
    box(ic, iso, (a - 4, 0, 0), (4, b, h), 'acc')
    r = iso.p(a, 0, h)
    u = unit((0, 0), (1, .5))
    arrow(ic, add(add(r, u, 1.6), (0, -.9)), add(add(r, u, 8.2), (0, -.9)))


def de_size(ic):
    iso = Iso(14, 11)
    box(ic, iso, (0, 0, 0), (11, 11, 5), 'steel')
    c = iso.p(5.5, 5.5, 5)
    bore(ic, c, 5.6, 2.8)
    y = iso.p(11, 11, 0)[1] + 2.5
    arrow(ic, (c[0] - 5.6, y), (c[0] + 5.6, y), both=True)


def de_scale(ic):
    iso = Iso(11.5, 15.5)
    box(ic, iso, (0, 0, 0), (5, 5, 4.5), 'steel')
    glass_box(ic, iso, (0, 0, 0), (9.5, 9.5, 8.5), 'acc')
    arrow(ic, (19.25, 9.25), (25.75, 2.75))


def de_rotate(ic, sm=False):
    iso = Iso(13.5, 17.5)
    s = 10
    box(ic, iso, (-s / 2, -s / 2, 0), (s, s, 4.5), 'steel', hair=not sm)
    ang = math.radians(22)
    hs = s / 2 * .92
    base = [(hs * math.cos(ang + k * math.pi / 2) - hs * math.sin(ang + k * math.pi / 2),
             hs * math.sin(ang + k * math.pi / 2) + hs * math.cos(ang + k * math.pi / 2)) for k in range(4)]
    prism(ic, iso, base, 5.25, 3.25, 'acc', hair=not sm)
    c = iso.p(0, 0, 8.5)
    if not sm:
        rod(ic, c, (c[0], c[1] - 3.75), r=.95, mat='steel', caps=(False, True), socket=True)
    arc_arrow_dimetric(ic, c, 11.25, 200, 392)


def de_delete(ic):
    # the Direct-edit block with a slab of it deleted (the body heals): the removed piece is an SEC dashed
    # ghost where it stood, at the back where nothing of the block lies behind it; INK minus badge
    iso = Iso(DE_ISO[0] + 1.25, DE_ISO[1] + 0.25)
    a, b, h = DE_SIZE
    yb = 4.0
    box(ic, iso, (0, 0, 0), (a, b, h), 'steel')
    q = lambda x, y, z: iso.p(x, y, z)
    construct(ic, poly([q(0, 0, h), q(0, -yb, h), q(a, -yb, h), q(a, -yb, 0), q(a, 0, 0)], False))
    construct(ic, 'M%sL%s' % (pt(q(a, -yb, h)), pt(q(a, 0, h))))
    badge(ic, '-')


DRAW = {
    'CR.sweep': sweep, 'CR.loft': loft, 'CR.coil': coil, 'CR.emboss': emboss, 'CR.derive': derive,
    'CR.decal': decal,
    'MO.chamfer': chamfer, 'MO.shell': shell, 'MO.draft': draft, 'MO.thread': thread, 'MO.combine': combine,
    'MO.thicken': thicken, 'MO.split': split, 'MO.direct': direct, 'MO.deleteface': deleteface,
    'DE.deMove': de_move, 'DE.deSize': de_size, 'DE.deScale': de_scale, 'DE.deRotate': de_rotate,
    'DE.deDelete': de_delete,
}
SMALL = {
    'MO.split': lambda ic: split(ic, sm=True),
    'DE.deRotate': lambda ic: de_rotate(ic, sm=True),
    'CR.coil': lambda ic: coil(ic, sm=True),
    'MO.thread': lambda ic: thread(ic, sm=True),
}

if __name__ == '__main__':
    run(DRAW, SMALL)
