"""Residuals of converted sketch constraints on their own geometry, with the
equations of frontend/lib/solver.dart. Every constraint written from an
Inventor sketch must be satisfied by the sketch as Inventor left it."""
import math

from ptp_sketch import CT, LINE, ARC, CIRCLE, PROJ_CENTER

T = {v: k for k, v in CT.items()}


def point(geos, r):
    if r['e'] == PROJ_CENTER:
        return (0.0, 0.0)
    g = geos[r['e']]
    d = g['data']
    if g['type'] == LINE:
        return (d[0], d[1]) if r['p'] == 0 else (d[2], d[3])
    if g['type'] == CIRCLE:
        return (d[0], d[1])
    if r['p'] == 0:
        return (d[0], d[1])
    a = d[3] if r['p'] == 1 else d[4]
    return (d[0] + math.cos(a) * d[2], d[1] + math.sin(a) * d[2])


def line(geos, i):
    d = geos[i]['data']
    return (d[0], d[1]), (d[2], d[3])


def residuals(geos, c):
    t = T[c['t']]
    P = [point(geos, r) for r in c['p']]
    E = c['e']
    if t == 'coincident':
        if len(P) >= 2:
            return [P[0][0] - P[1][0], P[0][1] - P[1][1]]
        g = geos[E[0]]
        if g['type'] in (ARC, CIRCLE):
            d = g['data']
            return [math.hypot(P[0][0] - d[0], P[0][1] - d[1]) - d[2]]
        a, b = line(geos, E[0])
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy)
        return [((P[0][0] - a[0]) * -dy + (P[0][1] - a[1]) * dx) / L]
    if t == 'fix':
        return [0.0]
    if t in ('horizontal', 'vertical'):
        a, b = line(geos, E[0])
        return [b[1] - a[1] if t == 'horizontal' else b[0] - a[0]]
    if t in ('parallel', 'perpendicular', 'collinear'):
        (a1, b1), (a2, b2) = line(geos, E[0]), line(geos, E[1])
        d1 = (b1[0] - a1[0], b1[1] - a1[1])
        d2 = (b2[0] - a2[0], b2[1] - a2[1])
        s = math.hypot(*d1) * math.hypot(*d2)
        if t == 'parallel':
            return [(d1[0] * d2[1] - d1[1] * d2[0]) / s]
        if t == 'perpendicular':
            return [(d1[0] * d2[0] + d1[1] * d2[1]) / s]
        n = (-d1[1] / math.hypot(*d1), d1[0] / math.hypot(*d1))
        return [(a2[0] - a1[0]) * n[0] + (a2[1] - a1[1]) * n[1],
                (b2[0] - a1[0]) * n[0] + (b2[1] - a1[1]) * n[1]]
    if t == 'midpoint':
        a, b = line(geos, E[0])
        return [(a[0] + b[0]) / 2 - P[0][0], (a[1] + b[1]) / 2 - P[0][1]]
    if t == 'equal':
        g1, g2 = geos[E[0]], geos[E[1]]
        if g1['type'] == LINE:
            (a, b), (c2, d2) = line(geos, E[0]), line(geos, E[1])
            return [math.dist(a, b) - math.dist(c2, d2)]
        return [g1['data'][2] - g2['data'][2]]
    if t == 'tangent':
        a, b = line(geos, E[0])
        d = geos[E[1]]['data']
        dx, dy = b[0] - a[0], b[1] - a[1]
        L = math.hypot(dx, dy)
        dist = abs(((d[0] - a[0]) * -dy + (d[1] - a[1]) * dx) / L)
        return [dist - d[2]]
    if t == 'dimension':
        k, v = c['k'], c['v']
        if k == 'dist':
            return [math.dist(P[0], P[1]) - v]
        if k == 'pline':
            la, lb = P[1], P[2]
            dl = (lb[0] - la[0], lb[1] - la[1])
            L = math.hypot(*dl)
            return [abs(((P[0][0] - la[0]) * dl[1] - (P[0][1] - la[1]) * dl[0]) / L) - v]
        if k == 'ang':
            (a1, b1), (a2, b2) = line(geos, E[0]), line(geos, E[1])
            d1 = (b1[0] - a1[0], b1[1] - a1[1])
            d2 = (b2[0] - a2[0], b2[1] - a2[1])
            ang = abs(math.degrees(math.atan2(d1[0] * d2[1] - d1[1] * d2[0], d1[0] * d2[0] + d1[1] * d2[1])))
            return [ang - v]      # the app measures the directed angle, no supplement
        if k == 'ang4':
            da = (P[1][0] - P[0][0], P[1][1] - P[0][1])
            db = (P[3][0] - P[2][0], P[3][1] - P[2][1])
            ang = abs(math.degrees(math.atan2(da[0] * db[1] - da[1] * db[0], da[0] * db[0] + da[1] * db[1])))
            return [ang - v]
        if k == 'gap':
            return [abs(geos[E[1]]['data'][2] - geos[E[0]]['data'][2]) - v]
        if k == 'rad':
            return [geos[E[0]]['data'][2] - v]
    raise ValueError(t)


def check(a, tol=1e-6):
    worst, bad = 0.0, []
    for c in a.cons:
        r = max(abs(x) for x in residuals(a.geos, c))
        worst = max(worst, r)
        if r > tol:
            bad.append((T[c['t']], c, r))
    return worst, bad
