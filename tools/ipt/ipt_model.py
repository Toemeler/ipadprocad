"""A neutral description of an Inventor part, built from the decoded
PmDCSegment: parameters, sketches (typed entities, constraints, dimensions,
3D frame) and the feature timeline.

Constraint classes are recognised by their shape (object size, participant
kinds) and confirmed against the geometry they hold; see ipt_dc.py for the
raw layouts.
"""
import math

from ipt_dc import DC, u32, ref

PROJECTED, OFFSET_GEN, CONSTRUCTION = 0x40, 0x40000, 0x80000


def _cross2(a, b):
    return a[0] * b[1] - a[1] * b[0]


def _dot2(a, b):
    return a[0] * b[0] + a[1] * b[1]


class Sketch:
    def __init__(self, name, main):
        self.name, self.main = name, main
        self.frame = None                 # (origin, x, y, n) world mm
        self.points = {}                  # id -> dict(xy, projected)
        self.curves = {}                  # id -> dict(kind, ends, on, centre, radius, origin, dir, style flags)
        self.constraints = []             # dict(type, ...)
        self.dimensions = []              # dict(kind, param, value, refs, driven)


class InventorPart:
    def __init__(self, dc_data, dc_meta):
        self.dc = DC(dc_data, dc_meta)
        self.params = self.dc.parameters()
        self.param_by_obj = {v['obj']: k for k, v in self.params.items()}
        self.sketches = []
        for name, main in self.dc.sketch_mains():
            self.sketches.append(self._sketch(name, main))

    # ------------------------------------------------------------------
    def _sketch(self, name, main):
        dc = self.dc
        raw = dc.sketch(main)
        s = Sketch(name, main)
        s.frame = dc.frame(main)
        for e, p in raw['points'].items():
            s.points[e] = dict(xy=p['xy'], projected=bool(p['flags'] & PROJECTED))
        for e, c in raw['curves'].items():
            fl = c['flags']
            d = dict(kind=c['kind'], ends=c['refs'][:2], on=c['refs'][2:],
                     projected=bool(fl & PROJECTED), construction=bool(fl & CONSTRUCTION),
                     offset=bool(fl & OFFSET_GEN))
            if c['kind'] == 'line':
                # The stored direction sits at a layout-dependent offset (some
                # lines carry extra fields before it); the end points are exact,
                # so direction and origin come from them.
                p0, p1 = raw['points'][c['refs'][0]]['xy'], raw['points'][c['refs'][1]]['xy']
                L = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
                d.update(origin=p0, dir=((p1[0] - p0[0]) / L, (p1[1] - p0[1]) / L) if L else c['dir'])
            else:
                d.update(centre=c['centre'], radius=c['radius'])
            s.curves[e] = d
        for c in raw['constraints']:
            self._constraint(s, c)
        return s

    def _kind(self, s, e):
        if e in s.points:
            return 'P'
        if e in s.curves:
            return 'L' if s.curves[e]['kind'] == 'line' else 'A'
        if e in self.param_by_obj:
            return 'D'
        return None

    def _constraint(self, s, c):
        parts = [r for _, r in c['parts']]
        kinds = [self._kind(s, r) for r in parts]
        ents = [(r, k) for r, k in zip(parts, kinds) if k]
        size = c['size']
        if any(k == 'D' for _, k in ents):                       # a dimension
            pname = next(self.param_by_obj[r] for r, k in ents if k == 'D')
            geo = [r for r, k in ents if k != 'D']
            s.dimensions.append(self._dimension(s, pname, geo, size))
            return
        uniq = []
        for r, k in ents:
            if r not in uniq:
                uniq.append(r)
        ks = [self._kind(s, r) for r in uniq]
        if size == 79:                                           # offset pairs
            s.constraints.append(dict(type='offset', pairs=[(uniq[0], uniq[1]), (uniq[2], uniq[3])]))
            return
        if ks == ['L'] and size == 68:
            d = s.curves[uniq[0]]['dir']
            s.constraints.append(dict(type='horizontal' if abs(d[1]) < abs(d[0]) else 'vertical',
                                      line=uniq[0]))
            return
        if sorted(ks) == ['L', 'L']:
            a, b = uniq
            da, db = s.curves[a]['dir'], s.curves[b]['dir']
            if abs(_cross2(da, db)) < 1e-9:
                oa, ob = s.curves[a]['origin'], s.curves[b]['origin']
                off = abs(_cross2(da, (ob[0] - oa[0], ob[1] - oa[1])))
                t = 'collinear' if off < 1e-6 else 'parallel'
            elif abs(_dot2(da, db)) < 1e-9:
                t = 'perpendicular'
            else:
                t = 'unknown-line-pair'
            s.constraints.append(dict(type=t, lines=(a, b)))
            return
        if sorted(ks) in (['L', 'P'], ['A', 'P']):
            cur = next(r for r in uniq if self._kind(s, r) in 'LA')
            pt = next(r for r in uniq if self._kind(s, r) == 'P')
            cd = s.curves[cur]
            if size == 75:
                s.constraints.append(dict(type='midpoint', point=pt, line=cur))
            elif pt in cd['ends']:
                s.constraints.append(dict(type='endpoint', point=pt, curve=cur))
            elif cd['kind'] == 'arc' and cd['centre'] == pt:
                s.constraints.append(dict(type='centre', point=pt, curve=cur))
            else:
                s.constraints.append(dict(type='on_curve', point=pt, curve=cur))
            return
        s.constraints.append(dict(type='unknown', size=size, refs=uniq))

    def _dimension(self, s, pname, geo, size):
        p = self.params[pname]
        ks = [self._kind(s, r) for r in geo]
        v = p['value']
        dim = dict(param=pname, refs=geo, raw_value=v,
                   driven=all(s.points.get(r, s.curves.get(r, {})).get('projected') for r in geo))
        if ks == ['L', 'L']:
            da, db = s.curves[geo[0]]['dir'], s.curves[geo[1]]['dir']
            if abs(_cross2(da, db)) < 1e-9:
                dim.update(kind='line_line', value=v * 10)
            else:
                dim.update(kind='angle', value=math.degrees(v))
        elif sorted(ks) == ['L', 'P']:
            dim.update(kind='point_line', value=v * 10)
        elif ks == ['P', 'P']:
            dim.update(kind='point_point', value=v * 10)
        elif ks == ['A', 'A']:
            dim.update(kind='arc_arc', value=v * 10)
        elif ks == ['A']:
            dim.update(kind='radius', value=v * 10)
        else:
            dim.update(kind='unknown', value=v)
        return dim
