"""Decoder for the Inventor PmDCSegment: parameters, sketches (entities,
constraints, dimensions, placement) and the feature list.

Everything here was established on Inventor 2026 files; the layouts are
recognised structurally (reference arrays, marker words), because RSe
objects carry no class tag.

Conventions: object indices are 0-based; a reference word is
0x80000000 | (index + 1). Lengths come out in mm, angles in rad.
"""
import math
import re
import struct

from rse_segment import Segment

ARR = 0x30000002          # "array of references" marker
CM = 10.0                 # Inventor internal length unit is cm


def u32(b, o):
    return struct.unpack_from('<I', b, o)[0] if o + 4 <= len(b) else None


def f64(b, o):
    return struct.unpack_from('<d', b, o)[0] if o + 8 <= len(b) else None


def ref(b, o):
    v = u32(b, o)
    if v is None or not v & 0x80000000:
        return None
    return (v & 0x7fffffff) - 1


class DC:
    def __init__(self, data, meta):
        self.seg = Segment(data, meta)
        self.n = self.seg.n
        self._names = None

    def obj(self, i):
        return self.seg.obj(i)

    # ------------------------------------------------------------ names
    def name_table(self):
        """{name: owner object} from the parameter/name index (object 2)."""
        if self._names is not None:
            return self._names
        b = self.seg.data
        out = {}

        def entry_at(p):
            ln = u32(b, p)
            if ln is None or not 1 <= ln <= 64:
                return None
            try:
                t = b[p + 4:p + 4 + 2 * ln].decode('utf-16le')
            except UnicodeDecodeError:
                return None
            if not t.isprintable():
                return None
            r = u32(b, p + 4 + 2 * ln)
            if r is None or not r & 0x80000000:
                return None
            return t, (r & 0x7fffffff) - 1, p + 8 + 2 * ln

        s2, e2 = self.seg.starts[2], self.seg.starts[3]
        p = s2
        while p < e2:
            e = entry_at(p)
            if e:
                q = p
                while True:
                    e = entry_at(q)
                    if not e:
                        break
                    out.setdefault(e[0], e[1])
                    q = e[2]
                if q > p + 16:
                    p = q
                    continue
            p += 1
        self._names = out
        return out

    def named_objects(self):
        """{name: object that carries the name string} for browser nodes."""
        out = {}
        for i in range(self.n):
            for o, t in self.seg.strings(i, 2):
                if o in (24, 28, 36, 40):
                    out.setdefault(t, i)
        return out

    # ------------------------------------------------------------ parameters
    def parameters(self):
        """{name: dict(obj, value)} -- value in internal units (cm / rad)."""
        out = {}
        for name, owner in self.name_table().items():
            i = owner
            b = self.obj(i)
            ln = u32(b, 20)
            if ln is None or ln > 40:
                continue
            try:
                nm = b[24:24 + 2 * ln].decode('utf-16le')
            except UnicodeDecodeError:
                continue
            if nm != name:
                continue
            vo = 24 + 2 * ln + 12
            out[name] = dict(obj=i, value=f64(b, vo), nominal=f64(b, vo + 8))
        return out

    # ------------------------------------------------------------ sketches
    def sketch_mains(self):
        """[(name, main object)] -- the object a sketch's entities point to."""
        out = []
        for name, i in self.named_objects().items():
            refs = [r for _, r in self.seg.refs(i)]
            if len(refs) >= 2:
                # name node -> [sketch main, ...]; entities point back at it
                main = refs[0]
                ents = [e for e in range(main + 1, min(self.n, main + 400))
                        if ref(self.obj(e), 24) == main]
                if ents:
                    out.append((name, main))
        return out

    def sketch(self, main):
        ents = [e for e in range(main + 1, self.n) if ref(self.obj(e), 24) == main]
        points, curves = {}, {}
        for e in ents:
            b = self.obj(e)
            if u32(b, 28) != ARR:
                points[e] = dict(xy=(f64(b, 28) * CM, f64(b, 36) * CM), flags=u32(b, 20))
        for e in ents:
            b = self.obj(e)
            flags = u32(b, 20)
            if u32(b, 28) != ARR:
                continue
            n = u32(b, 32)
            refs = [ref(b, 44 + 4 * k) for k in range(n)]
            p = 44 + 4 * n + 8
            c = dict(flags=flags, refs=refs)
            cref = ref(b, p)
            rad = f64(b, p + 4)
            if cref in points and rad is not None and 1e-9 < rad < 1e4:   # arc: centre, radius
                c.update(kind='arc', centre=cref, radius=rad * CM)
            else:
                c.update(kind='line', origin=(f64(b, p) * CM, f64(b, p + 8) * CM),
                         dir=(f64(b, p + 16), f64(b, p + 24)))
            curves[e] = c
        cons = self._constraints_of(main, set(points) | set(curves))
        return dict(main=main, points=points, curves=curves, constraints=cons)

    def _constraints_of(self, main, ents):
        """Objects whose u32@16 names one constraint system and whose
        participants are this sketch's entities."""
        sysref = {}
        for i in range(main + 1, min(self.n, main + 800)):
            b = self.obj(i)
            s = ref(b, 16)
            if s is None or u32(b, 20) != 0x30000006:
                continue
            parts = [r for _, r in self.seg.refs(i) if r != 2 and r != s]
            if parts and any(p in ents for p in parts):
                sysref.setdefault(s, []).append(i)
        out = []
        for s, objs in sysref.items():
            for i in objs:
                b = self.obj(i)
                parts = [(o, r) for o, r in self.seg.refs(i) if r != 2 and r != s]
                out.append(dict(obj=i, system=s, size=len(b), parts=parts, raw=b))
        return out

    # ------------------------------------------------------------ placement
    def frame(self, main):
        """The sketch's 2D->3D frame: (origin, xaxis, yaxis, normal), world mm.

        A placed sketch stores an origin, one in-plane axis `a` and, in its
        own reference list, the normal. Bytes 28/29 of the placement object
        say what `a` is: byte 28 = 1 -> the x axis, 0 -> the y axis; byte 29
        = 1 -> reversed. The other axis completes a right-handed frame.
        A sketch on an origin plane stores no placement; Inventor's axes for
        those are fixed (XY: X,Y  XZ: -X,Z  YZ: Y,Z -- verified for XZ)."""
        o, a, n = self.placement(main)
        if n is None:
            return None
        if o is None:
            nx = tuple(round(c) for c in n)
            base = {(0, 0, 1): ((1, 0, 0), (0, 1, 0)), (0, 1, 0): ((-1, 0, 0), (0, 0, 1)),
                    (1, 0, 0): ((0, 1, 0), (0, 0, 1))}.get(nx)
            if base is None:
                return None
            return (0.0, 0.0, 0.0), base[0], base[1], n
        is_x, rev = self._placement_flags(main)
        if rev:
            a = tuple(-c for c in a)

        def cross(p, q):
            return (p[1] * q[2] - p[2] * q[1], p[2] * q[0] - p[0] * q[2], p[0] * q[1] - p[1] * q[0])
        if is_x:
            return o, a, cross(n, a), n
        return o, cross(a, n), a, n

    def _placement_flags(self, main):
        for i in range(main, min(self.n, main + 12)):
            b = self.obj(i)
            if len(b) == 90 and ref(b, 20) == main - 1:
                return bool(b[28]), bool(b[29])
        return True, False

    def placement(self, main):
        """(origin, xaxis, normal) in world mm for a sketch, when stored."""
        normal = None
        for r in [r for _, r in self.seg.refs(main)]:
            b = self.obj(r)
            if len(b) == 83 and r not in (2,):
                v = (f64(b, 36), f64(b, 44), f64(b, 52))
                if all(x is not None for x in v) and abs(math.hypot(*v) - 1) < 1e-9:
                    normal = v
        for i in range(main, min(self.n, main + 12)):
            b = self.obj(i)
            if len(b) == 90 and ref(b, 20) == main - 1:
                rs = [r for _, r in self.seg.refs(i)]
                ax, org = self.obj(rs[2]), self.obj(rs[3])
                xa = (f64(ax, 36), f64(ax, 44), f64(ax, 52))
                o = (f64(org, 36) * CM, f64(org, 44) * CM, f64(org, 52) * CM)
                return o, xa, normal
        return None, None, normal
