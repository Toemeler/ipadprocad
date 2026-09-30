"""Inventor sketch (ipt_model.Sketch) -> the app's sketch files.

The app keeps a sketch as a DXF (lines, arcs, circles; a sketch POINT is a
circle tagged in .splines.json) plus JSON sidecars; constraints address
entities by their index in the DXF and points as (entity, point) with the
grip numbering of constraints.dart: line 0/1 = ends, arc 0 = centre,
1 = start, 2 = end, circle 0 = centre.

Inventor keeps points as objects that lines and arcs share. Here each
Inventor point becomes one or more entity points tied by coincident
constraints; a point that is nobody's end or centre becomes a sketch point.
"""
import json
import math

import numpy as np

# constraints.dart CType indices (the sidecar stores the enum index)
CT = dict(coincident=0, collinear=1, concentric=2, fix=3, parallel=4, perpendicular=5,
          horizontal=6, vertical=7, tangent=8, smooth=9, symmetric=10, equal=11,
          dimension=12, midpoint=13, pattern=14)
LINE, CIRCLE, ARC = 1, 2, 3
POINT_TAG = 5                 # Geo.pointTag
POINT_R = 0.35                # kSketchPointRadius
STYLE_CONSTRUCTION = 2
PROJ_CENTER = -1              # kProjCenter
LAYER = 'Layer 1'

# app frames of the origin planes (part_model.dart planeFrame)
APP_PLANES = {
    'xy': ((1, 0, 0), (0, 1, 0), (0, 0, 1)),
    'xz': ((1, 0, 0), (0, 0, -1), (0, 1, 0)),
    'yz': ((0, 0, -1), (0, 1, 0), (1, 0, 0)),
}


class AppSketch:
    def __init__(self, name):
        self.name = name
        self.geos = []          # dict(type, data, style, tag)
        self.cons = []          # constraint json dicts
        self.plane = 'face'
        self.frame = None       # (u, v, n, origin) world mm, for plane == 'face'


def _place(sk):
    """Choose the app plane for an Inventor sketch and the 2D map into it."""
    o, x, y, n = [np.array(v, float) for v in sk.frame]
    for key, (u, v, nn) in APP_PLANES.items():
        if np.allclose(n, nn, atol=1e-9) and abs(float(np.dot(o, n))) < 1e-9:
            u, v = np.array(u, float), np.array(v, float)
            return key, None, (lambda p, u=u, v=v: (float(np.dot(o + p[0] * x + p[1] * y, u)),
                                                     float(np.dot(o + p[0] * x + p[1] * y, v))))
    # a face/work-plane sketch: keep Inventor's own frame, so coordinates carry over
    return 'face', (x, y, n, o), (lambda p: (float(p[0]), float(p[1])))


def convert(sk, dim_positions=True):
    a = AppSketch(sk.name)
    a.plane, a.frame, to2d = _place(sk)
    P = {e: to2d(p['xy']) for e, p in sk.points.items()}

    # ---- entities: curves first (Inventor order), then lone points
    occ = {e: [] for e in sk.points}        # inventor point -> [(ent, pt)]
    index = {}
    projected_ents = []
    for e, c in sorted(sk.curves.items()):
        i = len(a.geos)
        index[e] = i
        style = STYLE_CONSTRUCTION if (c['construction'] or c['projected']) else 0
        if c['kind'] == 'line':
            p0, p1 = P[c['ends'][0]], P[c['ends'][1]]
            a.geos.append(dict(type=LINE, data=[p0[0], p0[1], p1[0], p1[1]], style=style))
            occ[c['ends'][0]].append((i, 0))
            occ[c['ends'][1]].append((i, 1))
        else:
            ctr = P[c['centre']]
            s, t = P[c['ends'][0]], P[c['ends'][1]]
            a0 = math.atan2(s[1] - ctr[1], s[0] - ctr[0])
            a1 = math.atan2(t[1] - ctr[1], t[0] - ctr[0])
            sweep = (a1 - a0) % (2 * math.pi)
            if sweep > math.pi + 1e-9:          # the minor arc, running s -> t or t -> s
                a0, a1 = a1, a0
                occ[c['ends'][1]].append((i, 1))
                occ[c['ends'][0]].append((i, 2))
            else:
                occ[c['ends'][0]].append((i, 1))
                occ[c['ends'][1]].append((i, 2))
            occ[c['centre']].append((i, 0))
            a.geos.append(dict(type=ARC, data=[ctr[0], ctr[1], c['radius'], a0, a1], style=style))
        if c['projected']:
            projected_ents.append(i)
    for e, p in sorted(sk.points.items()):
        if occ[e]:
            continue
        if p['projected'] and abs(P[e][0]) < 1e-9 and abs(P[e][1]) < 1e-9:
            occ[e].append((PROJ_CENTER, 0))     # Inventor's projected centre point
            continue
        i = len(a.geos)
        a.geos.append(dict(type=CIRCLE, data=[P[e][0], P[e][1], POINT_R], style=0, tag=POINT_TAG))
        occ[e].append((i, 0))
        if p['projected']:
            projected_ents.append(i)

    def pref(e):
        ent, pt = occ[e][0]
        return {'e': ent, 'p': pt}

    def add(t, pts=(), ents=(), **kw):
        d = {'t': CT[t], 'p': list(pts), 'e': list(ents)}
        d.update(kw)
        a.cons.append(d)

    # ---- connectivity: one Inventor point shared by several entities
    for e, lst in occ.items():
        for ent, pt in lst[1:]:
            add('coincident', pts=[{'e': lst[0][0], 'p': lst[0][1]}, {'e': ent, 'p': pt}])

    # ---- projected geometry is reference geometry: pinned where it is
    for i in projected_ents:
        g = a.geos[i]
        add('fix', ents=[i], an=list(g['data'][:5 if g['type'] == ARC else (4 if g['type'] == LINE else 3)]))

    # ---- geometric constraints
    offsets = []
    for c in sk.constraints:
        t = c['type']
        if t in ('endpoint', 'centre'):
            continue                            # carried by the shared points
        if t == 'on_curve':
            add('coincident', pts=[pref(c['point'])], ents=[index[c['curve']]])
        elif t == 'midpoint':
            add('midpoint', pts=[pref(c['point'])], ents=[index[c['line']]])
        elif t in ('horizontal', 'vertical'):
            g = a.geos[index[c['line']]]['data']
            dx, dy = g[2] - g[0], g[3] - g[1]
            add('horizontal' if abs(dy) < abs(dx) else 'vertical', ents=[index[c['line']]])
        elif t in ('parallel', 'perpendicular', 'collinear'):
            add(t, ents=[index[c['lines'][0]], index[c['lines'][1]]])
        elif t == 'offset':
            offsets += c['pairs']
        else:
            raise ValueError(f'{sk.name}: constraint {t} has no mapping yet')

    # Inventor's OFFSET has no single counterpart. The offset loop is pinned
    # by: arcs concentric with their source (shared centre, above), all
    # offset arcs equal, lines tangent to the arcs they meet, and the offset
    # distance as a dimension (below, from Inventor's own dimension).
    off_arcs = sorted({index[o] for s, o in offsets if sk.curves[o]['kind'] == 'arc'})
    for i in off_arcs[1:]:
        add('equal', ents=[off_arcs[0], i])
    arcs_by_pt = {}
    for e, lst in occ.items():
        for ent, pt in lst:
            arcs_by_pt.setdefault(e, []).append((ent, pt))
    for s, o in offsets:
        if sk.curves[o]['kind'] != 'line':
            continue
        li = index[o]
        for end in sk.curves[o]['ends']:
            for ent, pt in occ[end]:
                if ent in off_arcs:
                    add('tangent', ents=[li, ent])

    # ---- dimensions
    for d in sk.dimensions:
        kw = dict(v=d['value'], nm=d['param'])
        if d['driven']:
            kw['dr'] = True
        refs = d['refs']
        if d['kind'] == 'point_point':
            p0, p1 = P[refs[0]], P[refs[1]]
            add('dimension', pts=[pref(refs[0]), pref(refs[1])], k='dist', **kw)
        elif d['kind'] == 'point_line':
            pt = next(r for r in refs if r in sk.points)
            ln = next(r for r in refs if r in sk.curves)
            e0, e1 = sk.curves[ln]['ends']
            add('dimension', pts=[pref(pt), pref(e0), pref(e1)], k='pline', **kw)
        elif d['kind'] == 'line_line':
            la, lb = refs
            add('dimension', pts=[pref(sk.curves[la]['ends'][0]), pref(sk.curves[lb]['ends'][0]),
                                  pref(sk.curves[lb]['ends'][1])], k='pline', **kw)
        elif d['kind'] == 'angle':
            # 'ang' measures between the lines as their ends happen to run,
            # which is Inventor's angle or its supplement. 'ang4' takes the
            # two directions as point pairs: order each pair so the directed
            # angle between them IS Inventor's value.
            la, lb = refs
            ea, eb = list(sk.curves[la]['ends']), list(sk.curves[lb]['ends'])

            def ang(ea, eb):
                a0, a1, b0, b1 = P[ea[0]], P[ea[1]], P[eb[0]], P[eb[1]]
                da = (a1[0] - a0[0], a1[1] - a0[1])
                db = (b1[0] - b0[0], b1[1] - b0[1])
                return abs(math.degrees(math.atan2(da[0] * db[1] - da[1] * db[0],
                                                   da[0] * db[0] + da[1] * db[1])))
            if abs(ang(ea, eb) - d['value']) > 1e-6:
                eb = eb[::-1]
            if abs(ang(ea, eb) - d['value']) > 1e-6:
                raise ValueError(f'{sk.name}: angle {d["param"]} does not match its lines')
            add('dimension', pts=[pref(ea[0]), pref(ea[1]), pref(eb[0]), pref(eb[1])], k='ang4', **kw)
        elif d['kind'] == 'arc_arc':
            add('dimension', ents=[index[refs[0]], index[refs[1]]], k='gap', **kw)
        elif d['kind'] == 'radius':
            add('dimension', ents=[index[refs[0]]], k='rad', **kw)
        else:
            raise ValueError(f'{sk.name}: dimension {d} has no mapping yet')
    return a


# ---------------------------------------------------------------- files
def _dxf_entities(geos):
    out = []
    h = 0x100
    for g in geos:
        h += 1
        d = g['data']
        head = f"  0\n{'LINE' if g['type'] == LINE else 'ARC' if g['type'] == ARC else 'CIRCLE'}\n  5\n{h:X}\n100\nAcDbEntity\n  8\n{LAYER}\n 62\n256\n370\n-1\n 48\n1.0\n  6\nBYLAYER\n"
        if g['type'] == LINE:
            out.append(head + f"100\nAcDbLine\n 10\n{d[0]!r}\n 20\n{d[1]!r}\n 30\n0.0\n 11\n{d[2]!r}\n 21\n{d[3]!r}\n 31\n0.0\n")
        elif g['type'] == CIRCLE:
            out.append(head + f"100\nAcDbCircle\n 10\n{d[0]!r}\n 20\n{d[1]!r}\n 30\n0.0\n 40\n{d[2]!r}\n")
        else:
            out.append(head + f"100\nAcDbCircle\n 10\n{d[0]!r}\n 20\n{d[1]!r}\n 30\n0.0\n 40\n{d[2]!r}\n"
                       f"100\nAcDbArc\n 50\n{math.degrees(d[3])!r}\n 51\n{math.degrees(d[4])!r}\n")
    return ''.join(out)


def dxf_text(geos, template):
    """An app-style DXF: the template's header/tables/objects, our entities."""
    i = template.index('ENTITIES')
    j = template.index('  0\nENDSEC', i)
    start = template.index('\n', i) + 1
    return template[:start] + _dxf_entities(geos) + template[j:]


def files(a, template):
    """{entry name: bytes} for the sketch, under sketches/."""
    base = f'sketches/{a.name}'
    spl = {str(i): g['tag'] for i, g in enumerate(a.geos) if g.get('tag')}
    sty = {str(i): g['style'] for i, g in enumerate(a.geos) if g.get('style')}
    enc = lambda o: json.dumps(o, separators=(',', ':')).encode()
    return {
        f'{base}.dxf': dxf_text(a.geos, template).encode(),
        f'{base}.cons.json': enc(a.cons),
        f'{base}.params.json': b'[]',
        f'{base}.texts.json': b'[]',
        f'{base}.images.json': b'[]',
        f'{base}.splines.json': enc(spl),
        f'{base}.styles.json': enc(sty),
        f'{base}.proj.json': b'{}',
        f'{base}.gears.json': b'{}',
        f'{base}.layers.json': enc({'version': 3, 'layers': [LAYER], 'hidden': [], 'locked': [], 'eos': 1}),
    }
