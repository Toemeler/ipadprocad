"""Sketch profiles of an Inventor part.

Every extrusion's profile is kept, as an exact planar sheet body, in an ASM
SAB inside the PmDCSegment -- one body per profile, in feature order. This
turns each into a plane frame and loops of 2D vertices with DXF bulges.
"""
import math

import acis_to_step as A
import asm_sab


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


class Profile:
    def __init__(self, tag, origin, u, v, n, loops, segments):
        self.tag = tag              # the SAB body id Inventor gave it
        self.origin, self.u, self.v, self.n = origin, u, v, n   # mm
        self.loops = loops          # [[(x, y, bulge), ...]], outer first
        self.segments = segments    # [[('line'|'arc', p0, p1, centre|None, radius)]] per loop

    def to2d(self, p):
        d = A._sub(p, self.origin)
        return (_dot(d, self.u), _dot(d, self.v))

    def to3d(self, x, y, w=0.0):
        return tuple(self.origin[i] + self.u[i] * x + self.v[i] * y + self.n[i] * w for i in range(3))


def _signed_area(loop):
    a = 0.0
    for i, (x0, y0, b) in enumerate(loop):
        x1, y1, _ = loop[(i + 1) % len(loop)]
        a += x0 * y1 - x1 * y0
        if b:
            # circular segment area of the bulged edge
            c = math.hypot(x1 - x0, y1 - y0)
            th = 4 * math.atan(b)
            r = c / (2 * math.sin(th / 2)) if abs(math.sin(th / 2)) > 1e-12 else 0
            a += r * r * (th - math.sin(th))
    return a / 2


def profiles(dc_data, unit_mm=10.0, frames=None):
    """All profiles in the DC segment, in body order.

    frames: optional {index: (origin, u, v, n)} to express a profile in a
    given sketch frame instead of the plane's own ACIS frame."""
    start = asm_sab.find(dc_data)
    if start < 0:
        return []
    sab = asm_sab.parse(dc_data, start)
    T = A.Topo(sab)
    out = []
    for bi, b in enumerate(T.bodies()):
        faces = [f for sh in T.shells(b) for f in T.faces(sh)]
        if len(faces) != 1:
            continue
        fc = faces[0]
        g = A.surface_of(sab.records[T.face_info(fc)['surface']])
        if g.kind != 'plane':
            continue
        n = g.normal
        if frames and bi in frames:
            origin, u, v, n = frames[bi]
        else:
            origin = A._mul(g.origin, unit_mm)
            u = g.udir
            v = A._cross(n, u)
        prof = Profile(sab.records[b].id, origin, u, v, n, [], [])
        loops = []
        for lp in T.loops(fc):
            verts, segs = [], []
            for c in T.coedges(lp):
                ci = T.coedge_info(c)
                ei = T.edge_info(ci['edge'])
                p0 = A._mul(T.vertex_point(ei['v0']), unit_mm)
                p1 = A._mul(T.vertex_point(ei['v1']), unit_mm)
                cg = A.curve_of(sab.records[ei['curve']])
                bulge, centre, radius = 0.0, None, 0.0
                if cg.kind == 'circle':
                    sweep = ei['t1'] - ei['t0']            # along the edge, in curve param
                    s = 1.0 if _dot(cg.normal, n) > 0 else -1.0
                    sweep *= s
                    if ci['reversed']:
                        p0, p1, sweep = p1, p0, -sweep
                    bulge = math.tan(sweep / 4)
                    centre, radius = A._mul(cg.origin, unit_mm), cg.radius * unit_mm
                elif cg.kind != 'line':
                    raise A.ConvertError(f'profile edge of type {cg.kind} is not supported yet')
                elif ci['reversed']:
                    p0, p1 = p1, p0
                x, y = prof.to2d(p0)
                verts.append((x, y, bulge))
                segs.append(('arc' if centre else 'line', prof.to2d(p0), prof.to2d(p1),
                             prof.to2d(centre) if centre else None, radius))
            loops.append((abs(_signed_area(verts)), verts, segs))
        loops.sort(key=lambda t: -t[0])
        prof.loops = [l[1] for l in loops]
        prof.segments = [l[2] for l in loops]
        out.append(prof)
    return out
