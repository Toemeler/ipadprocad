"""ASM/ACIS B-rep (decoded SAB records) -> STEP AP214 solids, exact.

Analytic geometry maps one to one (plane, cylinder, cone, sphere, torus,
line, circle, ellipse). Procedural ACIS geometry -- rolling-ball blends,
intersection and offset curves -- has no STEP equivalent; ACIS stores a
B-spline approximation of each inside the record (within the fit tolerance
it also stores, typically 1e-3 of a model unit), and that is what is written.
It is the same thing Inventor's own STEP export writes for those entities.

Orientation. ACIS and STEP agree on loop direction relative to the face
normal, so loops are copied as they are. What differs is which way a
SURFACE's own normal points: ACIS lets a cone (cos < 0), torus (minor < 0),
sphere (radius < 0) or spline (reversed flag) face inwards, STEP never does.
An ADVANCED_FACE's same_sense absorbs that difference.
"""
import datetime
import math

from asm_sab import Ptr, Ident, Logical, Enum, OPEN, CLOSE


class ConvertError(ValueError):
    pass


# ---------------------------------------------------------------- vectors
def _add(a, b): return (a[0] + b[0], a[1] + b[1], a[2] + b[2])
def _sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def _mul(a, s): return (a[0] * s, a[1] * s, a[2] * s)
def _dot(a, b): return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]
def _cross(a, b): return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])
def _len(a): return math.sqrt(_dot(a, a))


def _unit(a):
    n = _len(a)
    if n < 1e-300:
        raise ConvertError('zero-length direction')
    return _mul(a, 1.0 / n)


def _perp(a):
    """Any unit vector perpendicular to a."""
    t = (1.0, 0.0, 0.0) if abs(a[0]) < 0.9 else (0.0, 1.0, 0.0)
    return _unit(_cross(a, t))


# ---------------------------------------------------------------- field cursor
class Cursor:
    """Sequential reader over a record's fields."""

    def __init__(self, fields, i=0):
        self.f, self.i = fields, i

    def peek(self):
        return self.f[self.i] if self.i < len(self.f) else None

    def next(self):
        v = self.f[self.i]
        self.i += 1
        return v

    def real(self):
        v = self.next()
        if isinstance(v, (int, float)) and not isinstance(v, (Ptr, Enum)):
            return float(v)
        raise ConvertError(f'expected a number, got {v!r}')

    def int(self):
        v = self.next()
        if isinstance(v, int) and not isinstance(v, Ptr):
            return int(v)
        raise ConvertError(f'expected an int, got {v!r}')

    def vec(self):
        v = self.peek()
        if isinstance(v, tuple) and len(v) == 3:
            self.i += 1
            return v
        return (self.real(), self.real(), self.real())

    def logical(self):
        v = self.next()
        if isinstance(v, Logical):
            return bool(v)
        raise ConvertError(f'expected a logical, got {v!r}')

    def interval(self):
        out = []
        for _ in range(2):
            out.append(self.real() if self.logical() else None)
        return out


def _depth_scan(fields):
    """(depth, index, value) for every field, depth counted in { } blocks."""
    d = 0
    for i, v in enumerate(fields):
        if v is OPEN:
            d += 1
        elif v is CLOSE:
            d -= 1
        else:
            yield d, i, v


# ---------------------------------------------------------------- bs3 data
class BSpline:
    """A B-spline curve (dim=1 param) or surface (dim=2), ACIS knot layout:
    end multiplicities are `degree`, not `degree + 1`."""

    def __init__(self):
        self.rational = False
        self.deg = []          # [p] or [pu, pv]
        self.knots = []        # per param: [(value, mult), ...]
        self.closure = []
        self.ctrl = []         # curve: [pt]; surface: [[pt for v] for u]
        self.weights = None


def _read_knots(c, n):
    return [(c.real(), c.int()) for _ in range(n)]


def _ncp(knots, deg):
    return sum(m for _, m in knots) - deg + 1


def read_bs3_curve(fields, i):
    c = Cursor(fields, i)
    kind = c.next()
    b = BSpline()
    b.rational = kind == 'nurbs'
    p = c.int()
    b.deg = [p]
    b.closure = [int(c.next())]
    nk = c.int()
    b.knots = [_read_knots(c, nk)]
    n = _ncp(b.knots[0], p)
    pts, ws = [], []
    for _ in range(n):
        pts.append(c.vec())
        if b.rational:
            ws.append(c.real())
    b.ctrl = pts
    b.weights = ws if b.rational else None
    return b


def read_bs3_surface(fields, i, u_major=True):
    c = Cursor(fields, i)
    kind = c.next()
    b = BSpline()
    b.rational = kind == 'nurbs'
    pu, pv = c.int(), c.int()
    b.deg = [pu, pv]
    b.closure = [int(c.next()), int(c.next())]
    c.next(), c.next()                       # singularity in u, v
    nku, nkv = c.int(), c.int()
    ku = _read_knots(c, nku)
    kv = _read_knots(c, nkv)
    b.knots = [ku, kv]
    nu, nv = _ncp(ku, pu), _ncp(kv, pv)
    flat, ws = [], []
    for _ in range(nu * nv):
        flat.append(c.vec())
        if b.rational:
            ws.append(c.real())
    # u_major: the u index varies slowest in the file (flat[i * nv + j]).
    idx = (lambda i2, j: i2 * nv + j) if u_major else (lambda i2, j: j * nu + i2)
    grid = [[flat[idx(i2, j)] for j in range(nv)] for i2 in range(nu)]
    wgrid = [[ws[idx(i2, j)] for j in range(nv)] for i2 in range(nu)] if ws else None
    b.ctrl, b.weights = grid, wgrid
    return b


def _is_bs3_surface_at(fields, i):
    return (isinstance(fields[i], Ident) and fields[i] in ('nubs', 'nurbs')
            and i + 3 < len(fields)
            and isinstance(fields[i + 1], int) and not isinstance(fields[i + 1], (Ptr, Enum))
            and isinstance(fields[i + 2], int) and not isinstance(fields[i + 2], (Ptr, Enum))
            and isinstance(fields[i + 3], Enum))


def _is_bs3_curve_at(fields, i):
    return (isinstance(fields[i], Ident) and fields[i] in ('nubs', 'nurbs')
            and i + 2 < len(fields)
            and isinstance(fields[i + 1], int) and not isinstance(fields[i + 1], (Ptr, Enum))
            and isinstance(fields[i + 2], Enum))


# Surface control-point order in ASM bs3 data: the u index varies FASTEST.
# Established with check_geometry.py: this layout puts every face vertex on
# its blend surface within 0.001 mm, the other misses by up to 1.4 mm.
SURFACE_LAYOUT = {'u_major': False}


# ---------------------------------------------------------------- geometry
class Geom:
    kind = None
    reversed = False     # ACIS normal opposite to the STEP normal


def surface_of(rec):
    t = rec.type
    c = Cursor(rec.fields, 3)
    g = Geom()
    if t == 'plane-surface':
        g.kind = 'plane'
        g.origin, g.normal, g.udir = c.vec(), _unit(c.vec()), c.vec()
        if _len(g.udir) < 1e-12:
            g.udir = _perp(g.normal)
        g.udir = _unit(g.udir)
    elif t == 'cone-surface':
        g.origin, g.axis, g.major = c.vec(), _unit(c.vec()), c.vec()
        g.ratio = c.real()
        c.interval()
        s, co = c.real(), c.real()
        c.real()                              # u-parameter scale
        if abs(g.ratio - 1.0) > 1e-9:
            raise ConvertError('elliptical cone/cylinder is not supported yet')
        g.radius = _len(g.major)
        g.reversed = co < 0
        if abs(s) < 1e-12:
            g.kind = 'cylinder'
        else:
            g.kind = 'cone'
            g.tan = s / co                    # radius growth per unit along +axis
    elif t == 'torus-surface':
        g.kind = 'torus'
        g.origin, g.axis = c.vec(), _unit(c.vec())
        g.major, g.minor = c.real(), c.real()
        g.udir = c.vec()
        if _len(g.udir) < 1e-12:
            g.udir = _perp(g.axis)
        g.udir = _unit(g.udir)
        g.reversed = g.minor < 0
        if g.major < 0:
            raise ConvertError('self-intersecting (lemon/apple) torus is not supported yet')
    elif t == 'sphere-surface':
        g.kind = 'sphere'
        g.origin, r = c.vec(), c.real()
        g.udir, g.pole = c.vec(), c.vec()
        g.radius = abs(r)
        g.reversed = r < 0
        g.pole = _unit(g.pole) if _len(g.pole) > 1e-12 else (0.0, 0.0, 1.0)
        g.udir = _unit(g.udir) if _len(g.udir) > 1e-12 else _perp(g.pole)
    elif t == 'spline-surface':
        g.kind = 'bspline_surface'
        g.reversed = c.logical()
        hit = None
        for d, i, v in _depth_scan(rec.fields):
            if d == 1 and _is_bs3_surface_at(rec.fields, i):
                hit = i
        if hit is None:
            raise ConvertError(f'spline surface ${rec.index} carries no B-spline approximation')
        g.fields, g.bs_at = rec.fields, hit
        g.bs = read_bs3_surface(rec.fields, hit, SURFACE_LAYOUT['u_major'])
    else:
        raise ConvertError(f'unsupported surface type {t}')
    return g


def curve_of(rec):
    t = rec.type
    c = Cursor(rec.fields, 3)
    g = Geom()
    if t == 'straight-curve':
        g.kind = 'line'
        g.origin, g.dir = c.vec(), _unit(c.vec())
    elif t == 'ellipse-curve':
        g.origin, g.normal, g.major = c.vec(), _unit(c.vec()), c.vec()
        g.ratio = c.real()
        g.kind = 'circle' if abs(g.ratio - 1.0) < 1e-12 else 'ellipse'
        g.radius = _len(g.major)
    elif t == 'intcurve-curve':
        g.kind = 'bspline_curve'
        g.reversed = c.logical()
        hit = None
        for d, i, v in _depth_scan(rec.fields):
            if d == 1 and _is_bs3_curve_at(rec.fields, i):
                hit = i
                break
        if hit is None:
            raise ConvertError(f'intcurve ${rec.index} carries no B-spline approximation')
        g.bs = read_bs3_curve(rec.fields, hit)
    else:
        raise ConvertError(f'unsupported curve type {t}')
    return g


# ---------------------------------------------------------------- topology
class Topo:
    """Walks bodies -> lumps -> shells -> faces -> loops -> coedges."""

    def __init__(self, sab):
        self.sab = sab
        self.R = sab.records

    def p(self, i):
        return self.R[i].ptrs()

    def chain(self, start, nxt):
        seen = set()
        while start >= 0 and start not in seen:
            seen.add(start)
            yield start
            start = self.p(start)[nxt]

    def bodies(self):
        return [r.index for r in self.R if r.type == 'body']

    def body_transform(self, b):
        t = self.p(b)[4] if len(self.p(b)) > 4 else -1
        if t < 0:
            return None
        c = Cursor(self.R[t].fields, 3)
        m = [c.real() for _ in range(9)]
        tr = c.vec()
        scale = c.real()
        return m, tr, scale

    def shells(self, b):
        for lump in self.chain(self.p(b)[2], 2):
            yield from self.chain(self.p(lump)[3], 2)

    def faces(self, shell):
        return list(self.chain(self.p(shell)[4], 2))

    def face_info(self, f):
        r = self.R[f]
        pp = r.ptrs()
        logicals = [bool(v) for v in r.fields if isinstance(v, Logical)]
        return dict(loop=pp[3], surface=pp[6], reversed=logicals[0] if logicals else False,
                    double_sided=logicals[1] if len(logicals) > 1 else False)

    def loops(self, f):
        return list(self.chain(self.p(f)[3], 2))

    def coedges(self, loop):
        out, c0 = [], self.p(loop)[3]
        c = c0
        while c >= 0:
            out.append(c)
            c = self.p(c)[2]
            if c == c0 or len(out) > 100000:
                break
        return out

    def coedge_info(self, c):
        r = self.R[c]
        pp = r.ptrs()
        lg = [bool(v) for v in r.fields if isinstance(v, Logical)]
        return dict(edge=pp[5], partner=pp[4], reversed=lg[0])

    def edge_info(self, e):
        r = self.R[e]
        cur = Cursor(r.fields, 3)
        v0 = int(cur.next()); t0 = cur.real()
        v1 = int(cur.next()); t1 = cur.real()
        cur.next()                              # coedge
        curve = int(cur.next())
        rev = cur.logical()
        return dict(v0=v0, v1=v1, t0=t0, t1=t1, curve=curve, reversed=rev)

    def vertex_point(self, v):
        pt = self.p(v)[3]
        return Cursor(self.R[pt].fields, 3).vec()


# ---------------------------------------------------------------- STEP writer
def _real(x):
    if x == 0:
        return '0.'
    s = repr(float(x)).upper()
    if 'E' in s:
        mant, exp = s.split('E')
        if '.' not in mant:
            mant += '.'
        return f'{mant}E{int(exp):+03d}'.replace('E+', 'E+')
    if '.' not in s:
        s += '.'
    return s


def step_string(s):
    out = []
    for ch in s:
        o = ord(ch)
        if ch == "'":
            out.append("''")
        elif ch == '\\':
            out.append('\\\\')
        elif 32 <= o < 127:
            out.append(ch)
        else:
            out.append('\\X2\\%04X\\X0\\' % o)
    return "'" + ''.join(out) + "'"


class StepWriter:
    def __init__(self):
        self.lines = []
        self.n = 0
        self._cache = {}

    def add(self, text, key=None):
        if key is not None and key in self._cache:
            return self._cache[key]
        self.n += 1
        self.lines.append(f'#{self.n}={text};')
        if key is not None:
            self._cache[key] = self.n
        return self.n

    def point(self, p):
        return self.add(f"CARTESIAN_POINT('',({_real(p[0])},{_real(p[1])},{_real(p[2])}))",
                        key=('P',) + tuple(p))

    def direction(self, d):
        return self.add(f"DIRECTION('',({_real(d[0])},{_real(d[1])},{_real(d[2])}))",
                        key=('D',) + tuple(d))

    def axis2(self, o, z, x):
        # STEP wants ref_direction not parallel to axis; project it.
        x = _sub(x, _mul(z, _dot(x, z)))
        x = _unit(x) if _len(x) > 1e-12 else _perp(z)
        return self.add(f"AXIS2_PLACEMENT_3D('',#{self.point(o)},#{self.direction(z)},#{self.direction(x)})")


class Xform:
    """Model-to-file mapping: body transform (if any), then unit scale."""

    def __init__(self, scale, body_tf=None):
        self.s = scale
        self.tf = body_tf

    def p(self, v):
        if self.tf:
            m, t, sc = self.tf
            v = (m[0] * v[0] + m[3] * v[1] + m[6] * v[2] + t[0],
                 m[1] * v[0] + m[4] * v[1] + m[7] * v[2] + t[1],
                 m[2] * v[0] + m[5] * v[1] + m[8] * v[2] + t[2])
            v = _mul(v, sc) if sc != 1 else v
        return _mul(v, self.s)

    def d(self, v):
        if self.tf:
            m, _, _ = self.tf
            v = (m[0] * v[0] + m[3] * v[1] + m[6] * v[2],
                 m[1] * v[0] + m[4] * v[1] + m[7] * v[2],
                 m[2] * v[0] + m[5] * v[1] + m[8] * v[2])
        return _unit(v)

    def len(self, x):
        sc = self.tf[2] if self.tf else 1.0
        return x * self.s * sc


def _knot_lists(knots, deg):
    vals = [k for k, _ in knots]
    mults = [m for _, m in knots]
    mults[0] += 1
    mults[-1] += 1
    return vals, mults


def _write_bspline_curve(w, bs, X):
    p = bs.deg[0]
    vals, mults = _knot_lists(bs.knots[0], p)
    pts = ','.join(f'#{w.point(X.p(q))}' for q in bs.ctrl)
    kv = ','.join(_real(v) for v in vals)
    km = ','.join(str(m) for m in mults)
    closed = '.T.' if bs.closure[0] else '.F.'
    if not bs.rational:
        return w.add(f"B_SPLINE_CURVE_WITH_KNOTS('',{p},({pts}),.UNSPECIFIED.,{closed},.F.,({km}),({kv}),.UNSPECIFIED.)")
    ws = ','.join(_real(x) for x in bs.weights)
    return w.add(f"(BOUNDED_CURVE() B_SPLINE_CURVE({p},({pts}),.UNSPECIFIED.,{closed},.F.) "
                 f"B_SPLINE_CURVE_WITH_KNOTS(({km}),({kv}),.UNSPECIFIED.) CURVE() GEOMETRIC_REPRESENTATION_ITEM() "
                 f"RATIONAL_B_SPLINE_CURVE(({ws})) REPRESENTATION_ITEM(''))")


def _write_bspline_surface(w, bs, X):
    pu, pv = bs.deg
    vu, mu = _knot_lists(bs.knots[0], pu)
    vv, mv = _knot_lists(bs.knots[1], pv)
    rows = ','.join('(' + ','.join(f'#{w.point(X.p(q))}' for q in row) + ')' for row in bs.ctrl)
    cu = '.T.' if bs.closure[0] else '.F.'
    cv = '.T.' if bs.closure[1] else '.F.'
    kmu, kmv = ','.join(map(str, mu)), ','.join(map(str, mv))
    kvu, kvv = ','.join(map(_real, vu)), ','.join(map(_real, vv))
    if not bs.rational:
        return w.add(f"B_SPLINE_SURFACE_WITH_KNOTS('',{pu},{pv},({rows}),.UNSPECIFIED.,{cu},{cv},.F.,"
                     f"({kmu}),({kmv}),({kvu}),({kvv}),.UNSPECIFIED.)")
    ws = ','.join('(' + ','.join(_real(x) for x in row) + ')' for row in bs.weights)
    return w.add(f"(BOUNDED_SURFACE() B_SPLINE_SURFACE({pu},{pv},({rows}),.UNSPECIFIED.,{cu},{cv},.F.) "
                 f"B_SPLINE_SURFACE_WITH_KNOTS(({kmu}),({kmv}),({kvu}),({kvv}),.UNSPECIFIED.) "
                 f"GEOMETRIC_REPRESENTATION_ITEM() RATIONAL_B_SPLINE_SURFACE(({ws})) "
                 f"REPRESENTATION_ITEM('') SURFACE())")


def write_surface(w, g, X):
    if g.kind == 'plane':
        return w.add(f"PLANE('',#{w.axis2(X.p(g.origin), X.d(g.normal), X.d(g.udir))})")
    if g.kind == 'cylinder':
        return w.add(f"CYLINDRICAL_SURFACE('',#{w.axis2(X.p(g.origin), X.d(g.axis), X.d(g.major))},"
                     f"{_real(X.len(g.radius))})")
    if g.kind == 'cone':
        axis, tan = g.axis, g.tan
        if tan < 0:                           # STEP needs a positive semi-angle
            axis, tan = _mul(axis, -1), -tan
        return w.add(f"CONICAL_SURFACE('',#{w.axis2(X.p(g.origin), X.d(axis), X.d(g.major))},"
                     f"{_real(X.len(g.radius))},{_real(math.atan(tan))})")
    if g.kind == 'torus':
        return w.add(f"TOROIDAL_SURFACE('',#{w.axis2(X.p(g.origin), X.d(g.axis), X.d(g.udir))},"
                     f"{_real(X.len(g.major))},{_real(X.len(abs(g.minor)))})")
    if g.kind == 'sphere':
        return w.add(f"SPHERICAL_SURFACE('',#{w.axis2(X.p(g.origin), X.d(g.pole), X.d(g.udir))},"
                     f"{_real(X.len(g.radius))})")
    if g.kind == 'bspline_surface':
        return _write_bspline_surface(w, g.bs, X)
    raise ConvertError(g.kind)


def write_curve(w, g, X):
    if g.kind == 'line':
        v = w.add(f"VECTOR('',#{w.direction(X.d(g.dir))},1.)")
        return w.add(f"LINE('',#{w.point(X.p(g.origin))},#{v})")
    if g.kind == 'circle':
        return w.add(f"CIRCLE('',#{w.axis2(X.p(g.origin), X.d(g.normal), X.d(g.major))},"
                     f"{_real(X.len(g.radius))})")
    if g.kind == 'ellipse':
        return w.add(f"ELLIPSE('',#{w.axis2(X.p(g.origin), X.d(g.normal), X.d(g.major))},"
                     f"{_real(X.len(g.radius))},{_real(X.len(g.radius * g.ratio))})")
    if g.kind == 'bspline_curve':
        return _write_bspline_curve(w, g.bs, X)
    raise ConvertError(g.kind)


def brep_to_step(sab, names=None, product='Part', author='', out_scale=None):
    """All bodies of a decoded SAB -> one STEP file (str), one solid per body.

    names: optional list of body names, in body order.
    Returns (step_text, [solid names], report dict)."""
    topo = Topo(sab)
    unit = out_scale if out_scale is not None else sab.header.get('unit_mm', 1.0)
    w = StepWriter()
    now = datetime.datetime.now().replace(microsecond=0).isoformat()

    ctx_len = w.add("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.))")
    ctx_ang = w.add("(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.))")
    ctx_sol = w.add("(NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT())")
    unc = w.add(f"UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(1.E-05),#{ctx_len},"
                f"'distance_accuracy_value','confusion accuracy')")
    ctx = w.add(f"(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT((#{unc})) "
                f"GLOBAL_UNIT_ASSIGNED_CONTEXT((#{ctx_len},#{ctx_ang},#{ctx_sol})) "
                f"REPRESENTATION_CONTEXT('Context #1','3D Context with UNIT and UNCERTAINTY'))")

    solids, solid_names, report = [], [], {'bodies': []}
    for bi, b in enumerate(topo.bodies()):
        X = Xform(unit, topo.body_transform(b))
        name = names[bi] if names and bi < len(names) else f'Solid{bi + 1}'
        vtx, edges, surf_cache = {}, {}, {}
        shells_out, stats = [], {'faces': 0, 'edges': 0, 'vertices': 0, 'closed': True}
        for sh in topo.shells(b):
            face_ids = []
            used = {}
            for f in topo.faces(sh):
                fi = topo.face_info(f)
                if fi['surface'] not in surf_cache:
                    g = surface_of(topo.R[fi['surface']])
                    surf_cache[fi['surface']] = (g, write_surface(w, g, X))
                g, sid = surf_cache[fi['surface']]
                bounds = []
                for lp in topo.loops(f):
                    oes = []
                    for c in topo.coedges(lp):
                        ci = topo.coedge_info(c)
                        e = ci['edge']
                        used[e] = used.get(e, 0) + 1
                        if e not in edges:
                            ei = topo.edge_info(e)
                            for v in (ei['v0'], ei['v1']):
                                if v not in vtx:
                                    vtx[v] = w.add(f"VERTEX_POINT('',#{w.point(X.p(topo.vertex_point(v)))})")
                            if ei['curve'] < 0:
                                raise ConvertError(f'edge ${e} has no curve')
                            cg = curve_of(topo.R[ei['curve']])
                            cid = write_curve(w, cg, X)
                            same = not (ei['reversed'] ^ cg.reversed)
                            edges[e] = w.add(f"EDGE_CURVE('',#{vtx[ei['v0']]},#{vtx[ei['v1']]},#{cid},"
                                             f"{'.T.' if same else '.F.'})")
                        oes.append(w.add(f"ORIENTED_EDGE('',*,*,#{edges[e]},"
                                         f"{'.F.' if ci['reversed'] else '.T.'})"))
                    loop = w.add(f"EDGE_LOOP('',({','.join('#%d' % o for o in oes)}))")
                    bounds.append(w.add(f"FACE_BOUND('',#{loop},.T.)"))
                same = not (fi['reversed'] ^ g.reversed)
                face_ids.append(w.add(f"ADVANCED_FACE('',({','.join('#%d' % x for x in bounds)}),#{sid},"
                                      f"{'.T.' if same else '.F.'})"))
            closed = all(n == 2 for n in used.values())
            stats['closed'] &= closed
            stats['faces'] += len(face_ids)
            kind = 'CLOSED_SHELL' if closed else 'OPEN_SHELL'
            shells_out.append((kind, w.add(f"{kind}('',({','.join('#%d' % x for x in face_ids)}))")))
        stats['edges'], stats['vertices'] = len(edges), len(vtx)
        if not shells_out:
            continue
        if all(k == 'CLOSED_SHELL' for k, _ in shells_out):
            outer = shells_out[0][1]
            if len(shells_out) == 1:
                sol = w.add(f"MANIFOLD_SOLID_BREP({step_string(name)},#{outer})")
            else:
                voids = ','.join('#%d' % s for _, s in shells_out[1:])
                sol = w.add(f"BREP_WITH_VOIDS({step_string(name)},#{outer},({voids}))")
        else:
            sol = w.add(f"SHELL_BASED_SURFACE_MODEL({step_string(name)},"
                        f"({','.join('#%d' % s for _, s in shells_out)}))")
        solids.append(sol)
        solid_names.append(name)
        stats['name'] = name
        report['bodies'].append(stats)

    origin = w.axis2((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), (1.0, 0.0, 0.0))
    rep = w.add(f"ADVANCED_BREP_SHAPE_REPRESENTATION({step_string(product)},"
                f"({','.join('#%d' % s for s in solids + [origin])}),#{ctx})")
    app = w.add("APPLICATION_CONTEXT('core data for automotive mechanical design processes')")
    w.add(f"APPLICATION_PROTOCOL_DEFINITION('international standard','automotive_design',2000,#{app})")
    pc = w.add(f"PRODUCT_CONTEXT('',#{app},'mechanical')")
    prod = w.add(f"PRODUCT({step_string(product)},{step_string(product)},'',(#{pc}))")
    pdf = w.add(f"PRODUCT_DEFINITION_FORMATION('','',#{prod})")
    pdc = w.add(f"PRODUCT_DEFINITION_CONTEXT('part definition',#{app},'design')")
    pd = w.add(f"PRODUCT_DEFINITION('design','',#{pdf},#{pdc})")
    pds = w.add(f"PRODUCT_DEFINITION_SHAPE('','',#{pd})")
    w.add(f"SHAPE_DEFINITION_REPRESENTATION(#{pds},#{rep})")
    w.add(f"PRODUCT_RELATED_PRODUCT_CATEGORY('part',$,(#{prod}))")

    head = ("ISO-10303-21;\nHEADER;\n"
            "FILE_DESCRIPTION(('Exact B-rep converted from an Autodesk Inventor part'),'2;1');\n"
            f"FILE_NAME({step_string(product + '.step')},'{now}',({step_string(author)}),(''),"
            f"'ipt2ptp','{sab.header.get('asm', '')}','');\n"
            "FILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'));\nENDSEC;\nDATA;\n")
    return head + '\n'.join(w.lines) + '\nENDSEC;\nEND-ISO-10303-21;\n', solid_names, report
