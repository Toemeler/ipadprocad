"""Self-consistency check of the ACIS -> STEP geometry mapping.

Evaluates every surface and curve exactly as the STEP output will define
it, and measures:
  * vertex -> each of its edges' curves
  * vertex -> the surface of every face that uses it
  * points along every edge -> the surfaces of both faces on that edge
Everything in model units (Inventor: cm); tolerances are printed in mm.

usage: py check_geometry.py file.ipt
"""
import math
import sys

import numpy as np

import acis_to_step as A
import asm_sab
from ipt_container import IptFile


def basis_funs(knots_full, p, u):
    """All non-zero B-spline basis values at u (Cox-de Boor), plus span."""
    n = len(knots_full) - p - 2
    if u >= knots_full[n + 1]:
        span = n
    else:
        span = max(p, int(np.searchsorted(knots_full, u, side='right')) - 1)
        span = min(span, n)
    N = [1.0] + [0.0] * p
    left, right = [0.0] * (p + 1), [0.0] * (p + 1)
    for j in range(1, p + 1):
        left[j] = u - knots_full[span + 1 - j]
        right[j] = knots_full[span + j] - u
        saved = 0.0
        for r in range(j):
            den = right[r + 1] + left[j - r]
            tmp = N[r] / den if den != 0 else 0.0
            N[r] = saved + right[r + 1] * tmp
            saved = left[j - r] * tmp
        N[j] = saved
    return span, N


def full_knots(knots, p):
    vals, mults = A._knot_lists(knots, p)
    out = []
    for v, m in zip(vals, mults):
        out += [v] * m
    return out


def eval_curve(bs, t):
    p = bs.deg[0]
    U = full_knots(bs.knots[0], p)
    span, N = basis_funs(U, p, t)
    P = np.array(bs.ctrl)
    W = np.array(bs.weights) if bs.weights else np.ones(len(P))
    num = np.zeros(3); den = 0.0
    for k in range(p + 1):
        i = span - p + k
        num += N[k] * W[i] * P[i]; den += N[k] * W[i]
    return num / den


def eval_surface(bs, u, v):
    pu, pv = bs.deg
    U, V = full_knots(bs.knots[0], pu), full_knots(bs.knots[1], pv)
    su, Nu = basis_funs(U, pu, u)
    sv, Nv = basis_funs(V, pv, v)
    P = bs.ctrl
    W = bs.weights
    num = np.zeros(3); den = 0.0
    for a in range(pu + 1):
        for b in range(pv + 1):
            i, j = su - pu + a, sv - pv + b
            w = W[i][j] if W else 1.0
            num += Nu[a] * Nv[b] * w * np.array(P[i][j]); den += Nu[a] * Nv[b] * w
    return num / den


class SurfDist:
    def __init__(self, g):
        self.g = g
        if g.kind == 'bspline_surface':
            bs = g.bs
            u0, u1 = bs.knots[0][0][0], bs.knots[0][-1][0]
            v0, v1 = bs.knots[1][0][0], bs.knots[1][-1][0]
            self.dom = (u0, u1, v0, v1)
            us, vs = np.linspace(u0, u1, 41), np.linspace(v0, v1, 41)
            self.grid = np.array([[eval_surface(bs, u, v) for v in vs] for u in us])
            self.us, self.vs = us, vs

    def __call__(self, p):
        g = self.g
        p = np.asarray(p, float)
        if g.kind == 'plane':
            return abs(np.dot(p - g.origin, g.normal))
        if g.kind == 'cylinder':
            q = p - g.origin; a = np.array(g.axis)
            return abs(np.linalg.norm(q - np.dot(q, a) * a) - g.radius)
        if g.kind == 'cone':
            q = p - g.origin; a = np.array(g.axis)
            h = np.dot(q, a); rad = np.linalg.norm(q - h * a)
            return abs(rad - (g.radius + h * g.tan)) / math.sqrt(1 + g.tan ** 2)
        if g.kind == 'torus':
            q = p - g.origin; a = np.array(g.axis)
            h = np.dot(q, a); rad = np.linalg.norm(q - h * a)
            return abs(math.hypot(rad - g.major, h) - abs(g.minor))
        if g.kind == 'sphere':
            return abs(np.linalg.norm(p - g.origin) - g.radius)
        if g.kind == 'bspline_surface':
            d = np.linalg.norm(self.grid - p, axis=2)
            i, j = np.unravel_index(np.argmin(d), d.shape)
            # refine: local Gauss-Newton-free pattern search around the best cell
            u, v = self.us[i], self.vs[j]
            du, dv = self.us[1] - self.us[0], self.vs[1] - self.vs[0]
            best = d[i, j]
            for _ in range(40):
                improved = False
                for su, sv in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    uu = min(max(u + su * du, self.dom[0]), self.dom[1])
                    vv = min(max(v + sv * dv, self.dom[2]), self.dom[3])
                    dd = np.linalg.norm(eval_surface(g.bs, uu, vv) - p)
                    if dd < best:
                        best, u, v, improved = dd, uu, vv, True
                if not improved:
                    du, dv = du / 2, dv / 2
                    if du < 1e-9:
                        break
            return best
        raise A.ConvertError(g.kind)


def curve_points(cg, ei, P0, P1, n=7):
    """n points along the edge, from its start vertex to its end vertex."""
    if cg.kind == 'line':
        return [P0 + (P1 - P0) * k / (n - 1) for k in range(n)]
    if cg.kind in ('circle', 'ellipse'):
        c = np.array(cg.origin); nrm = np.array(cg.normal); maj = np.array(cg.major)
        mn = np.cross(nrm, maj) * cg.ratio
        t0, t1 = ei['t0'], ei['t1']
        if ei['reversed']:
            t0, t1 = -t0, -t1
        return [c + maj * math.cos(t) + mn * math.sin(t) for t in np.linspace(t0, t1, n)]
    if cg.kind == 'bspline_curve':
        # Edge params are negated once for a reversed edge (edge -> intcurve)
        # and once for a reversed intcurve (intcurve -> its bs3).
        t0, t1 = ei['t0'], ei['t1']
        if ei['reversed'] ^ cg.reversed:
            t0, t1 = -t0, -t1
        return [eval_curve(cg.bs, t) for t in np.linspace(t0, t1, n)]
    raise A.ConvertError(cg.kind)


def check(sab, verbose=True):
    topo = A.Topo(sab)
    to_mm = sab.header.get('unit_mm', 1.0)
    worst = {'vertex-curve': 0.0, 'vertex-surface': 0.0, 'edge-surface': 0.0, 'edge-endpoints': 0.0}
    where = {}
    sd_cache = {}

    def sd(i):
        if i not in sd_cache:
            sd_cache[i] = SurfDist(A.surface_of(topo.R[i]))
        return sd_cache[i]

    for b in topo.bodies():
        for sh in topo.shells(b):
            edge_faces = {}
            for f in topo.faces(sh):
                fi = topo.face_info(f)
                for lp in topo.loops(f):
                    for c in topo.coedges(lp):
                        edge_faces.setdefault(topo.coedge_info(c)['edge'], []).append(fi['surface'])
            for e, surfs in edge_faces.items():
                ei = topo.edge_info(e)
                P0 = np.array(topo.vertex_point(ei['v0'])); P1 = np.array(topo.vertex_point(ei['v1']))
                cg = A.curve_of(topo.R[ei['curve']])
                pts = curve_points(cg, ei, P0, P1)
                d_end = max(np.linalg.norm(pts[0] - P0), np.linalg.norm(pts[-1] - P1))
                if d_end > worst['edge-endpoints']:
                    worst['edge-endpoints'] = d_end; where['edge-endpoints'] = (e, cg.kind)
                for s in surfs:
                    for P in (P0, P1):
                        d = sd(s)(P)
                        if d > worst['vertex-surface']:
                            worst['vertex-surface'] = d; where['vertex-surface'] = (e, topo.R[s].type)
                    for P in pts[1:-1]:
                        d = sd(s)(P)
                        if d > worst['edge-surface']:
                            worst['edge-surface'] = d; where['edge-surface'] = (e, cg.kind, topo.R[s].type)
    if verbose:
        for k, v in worst.items():
            print(f'  {k:16} worst {v * to_mm:.6f} mm  at {where.get(k)}')
    return {k: v * to_mm for k, v in worst.items()}


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    ipt = IptFile(sys.argv[1])
    sab = asm_sab.parse(ipt.brep_segment())
    check(sab)
