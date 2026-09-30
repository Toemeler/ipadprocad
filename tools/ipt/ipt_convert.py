"""Inventor .ipt -> Prototype .ptp with the FULL feature tree.

Pipeline:
  1. container, final B-rep (exact), DC segment (sketches, parameters,
     feature timeline, extrusion profiles);
  2. sketches -> app sketches (ptp_sketch), every constraint verified on
     the Inventor geometry (check_sketch);
  3. features -> app features. Extrusion direction and operation are read
     from the faces each feature left in Inventor's result (their tags);
     fillet edges are found by replaying the tree in the app's own kernel
     and picking, at each fillet, the edges whose blend at that radius is
     one of the faces Inventor tagged for that fillet;
  4. Inventor's exact result bodies ride along as the features' cached
     result, so the app shows exactly what Inventor built until something
     is edited (see the app's result cache).
"""
import hashlib
import json
import math
import os

import numpy as np

import acis_to_step as A
import asm_sab
import check_geometry as CG
import check_sketch
import ptp_format
import ptp_sketch
from ipt_container import IptFile
from ipt_dc import DC
from ipt_features import timeline
from ipt_model import InventorPart
from ipt_profiles import profiles

HERE = os.path.dirname(os.path.abspath(__file__))
CONVERTER = 'ipt2ptp/2'


class ConversionError(Exception):
    pass


# ------------------------------------------------------------------ B-rep
def face_tags(sab):
    """{face record: (kind, feature id)} from Inventor's face attributes."""
    out = {}
    for r in sab.records:
        if r.type != 'face':
            continue
        a = r.ptrs()[0]
        while a >= 0:
            ar = sab.records[a]
            vals = [v for v in ar.fields if isinstance(v, (int, str)) and not isinstance(v, asm_sab.Ptr)]
            names = [v for v in vals if isinstance(v, str)]
            ints = [v for v in vals if isinstance(v, int)]
            if names:
                nm = names[0]
                # [-1, name, 1, 44, count, id, ...]
                if nm in ('INV_NMX_BLEND_TAG', 'INV_NMX_SWEEPGENERATED_TAG', 'INV_NMX_MATCHED_ATTRIB') and len(ints) >= 5:
                    out.setdefault(r.index, []).append((nm, ints[4]))
                elif nm == 'INV_NMX_FEATURE_DEPENDENCY_ATTRIB' and len(ints) >= 5:
                    for fid in ints[4:4 + ints[3]]:
                        out.setdefault(r.index, []).append((nm, fid))
            nxt = ar.ptrs()
            a = nxt[2] if len(nxt) > 2 else -1
    return out


class BrepInfo:
    def __init__(self, sab):
        self.sab = sab
        self.T = A.Topo(sab)
        self.tags = face_tags(sab)
        self.body_of_face = {}
        self.faces = []
        for bi, b in enumerate(self.T.bodies()):
            for sh in self.T.shells(b):
                for f in self.T.faces(sh):
                    self.body_of_face[f] = bi
                    self.faces.append(f)
        self._sd = {}

    def all_tag_ids(self):
        return {fid for lst in self.tags.values() for _, fid in lst}

    def faces_of(self, fid, kinds=None):
        return [f for f, lst in self.tags.items()
                if any(i == fid and (kinds is None or k in kinds) for k, i in lst)]

    def surface(self, f):
        return A.surface_of(self.sab.records[self.T.face_info(f)['surface']])

    def surfdist(self, f):
        if f not in self._sd:
            self._sd[f] = CG.SurfDist(self.surface(f))
        return self._sd[f]

    def face_points(self, f):
        pts = []
        for lp in self.T.loops(f):
            for c in self.T.coedges(lp):
                ei = self.T.edge_info(self.T.coedge_info(c)['edge'])
                pts.append(np.array(self.T.vertex_point(ei['v0'])) * 10)
                pts.append(np.array(self.T.vertex_point(ei['v1'])) * 10)
        return np.array(pts)

    def outward_normal_at(self, f, p_mm):
        """Outward normal of face f near point p (planes only need no p)."""
        g = self.surface(f)
        fi = self.T.face_info(f)
        s = -1.0 if (fi['reversed'] ^ g.reversed) else 1.0
        if g.kind == 'plane':
            return np.array(g.normal) * s
        if g.kind == 'cylinder':
            q = p_mm / 10 - np.array(g.origin)
            ax = np.array(g.axis)
            rad = q - ax * (q @ ax)
            return rad / np.linalg.norm(rad) * s
        return None


# ------------------------------------------------------------------ profiles
def match_profile(sk, profs):
    o, x, y, n = [np.array(v, float) for v in sk.frame]
    pts = [o + p['xy'][0] * x + p['xy'][1] * y for p in sk.points.values()]
    best = None
    for pi, pr in enumerate(profs):
        if abs(abs(float(np.dot(pr.n, n))) - 1) > 1e-6:
            continue
        vs = [np.array(pr.to3d(a, b)) for a, b, _ in pr.loops[0]]
        d = max(min(np.linalg.norm(v - q) for q in pts) for v in vs)
        if best is None or d < best[0]:
            best = (d, pi)
    if best is None or best[0] > 1e-6:
        raise ConversionError(f'{sk.name}: no extrusion profile matches the sketch')
    return best[1]


def _loop_area_centroid(loop):
    a = cx = cy = 0.0
    for i, (x0, y0, _) in enumerate(loop):
        x1, y1, _ = loop[(i + 1) % len(loop)]
        c = x0 * y1 - x1 * y0
        a += c
        cx += (x0 + x1) * c
        cy += (y0 + y1) * c
    a /= 2
    return a, (cx / (6 * a), cy / (6 * a)) if a else (loop[0][0], loop[0][1])


def _inside(loop, px, py):
    """Point in polygon (bulges ignored -- used on a point well inside)."""
    c = False
    n = len(loop)
    for i in range(n):
        x0, y0, _ = loop[i]
        x1, y1, _ = loop[(i + 1) % n]
        if (y0 > py) != (y1 > py) and px < x0 + (py - y0) * (x1 - x0) / (y1 - y0):
            c = not c
    return c


def profile_anchor(pr):
    """An interior point of the profile's region (3D) and its area (mm^2)."""
    outer = pr.loops[0]
    area = sum(abs(ptp_sketch_area(l)) * (1 if i == 0 else -1) for i, l in enumerate(pr.loops))
    _, (cx, cy) = _loop_area_centroid(outer)
    if _inside(outer, cx, cy) and not any(_inside(h, cx, cy) for h in pr.loops[1:]):
        return pr.to3d(cx, cy), area
    xs = [p[0] for p in outer]
    ys = [p[1] for p in outer]
    best = None
    for gx in np.linspace(min(xs), max(xs), 61)[1:-1]:
        for gy in np.linspace(min(ys), max(ys), 61)[1:-1]:
            if not _inside(outer, gx, gy) or any(_inside(h, gx, gy) for h in pr.loops[1:]):
                continue
            d = min(_seg_dist(outer, gx, gy), *[_seg_dist(h, gx, gy) for h in pr.loops[1:]] or [1e9])
            if best is None or d > best[0]:
                best = (d, gx, gy)
    return pr.to3d(best[1], best[2]), area


def _seg_dist(loop, px, py):
    d = 1e18
    for i in range(len(loop)):
        x0, y0, _ = loop[i]
        x1, y1, _ = loop[(i + 1) % len(loop)]
        vx, vy = x1 - x0, y1 - y0
        L2 = vx * vx + vy * vy
        t = 0 if L2 == 0 else max(0, min(1, ((px - x0) * vx + (py - y0) * vy) / L2))
        d = min(d, math.hypot(px - x0 - t * vx, py - y0 - t * vy))
    return d


def ptp_sketch_area(loop):
    from ipt_profiles import _signed_area
    return _signed_area(loop)


# ------------------------------------------------------------------ extrusion semantics
def extrusion_semantics(feat, sk, pr, brep, first_in_body, solids=None, last_body=None):
    """(dir, a, b, extent, output, body index) for an extrusion."""
    o, x, y, n = [np.array(v, float) for v in sk.frame]
    faces = brep.faces_of(feat.tag, {'INV_NMX_SWEEPGENERATED_TAG'})
    # which side(s) of the sketch plane the feature's faces lie on
    if feat.leader is not None:
        p0, p1 = [np.array(p) for p in feat.leader]
        s0, s1 = float((p0 - o) @ n), float((p1 - o) @ n)
        if abs(s0 + s1) < 1e-6 and abs(s0) > 1e-6:
            direction = 'symmetric'
        else:
            direction = 'default' if (s1 - s0) > 0 else 'flipped'
    else:
        side = []
        for f in faces:
            side += [float((p - o) @ n) for p in brep.face_points(f)]
        side = [s for s in side if abs(s) > 1e-6]
        if side and all(s < 0 for s in side):
            direction = 'flipped'
        elif side and all(s > 0 for s in side):
            direction = 'default'
        else:
            direction = 'symmetric'
    # operation, from a side face: does its outward normal point away from
    # the profile (material added) or into it (material removed)?
    anchor, _ = profile_anchor(pr)
    anchor = np.array(anchor)
    votes = 0
    body = None
    for f in faces:
        g = brep.surface(f)
        if g.kind != 'plane' or abs(float(np.array(g.normal) @ n)) > 1e-6:
            continue                                   # side faces only
        c = brep.face_points(f).mean(0)
        nrm = brep.outward_normal_at(f, c)
        radial = c - anchor
        radial -= n * float(radial @ n)
        if np.linalg.norm(radial) < 1e-9:
            continue
        votes += 1 if float(nrm @ radial) > 0 else -1
        body = brep.body_of_face[f]
    if body is None and faces:
        body = brep.body_of_face[faces[0]]
    if votes == 0 and solids:
        # No face of Inventor's result still carries this feature's tag (a
        # later feature re-tagged them). Ask the result itself: is the
        # extruded region material, or empty?
        o_n = float(anchor @ n)
        if direction == 'symmetric':
            mids = [0.0]
        elif feat.leader is not None:
            L = float(np.linalg.norm(np.array(feat.leader[1]) - np.array(feat.leader[0])))
            mids = [(L / 2) if direction == 'default' else -(L / 2)]
        else:
            mids = [0.5 if direction == 'default' else -0.5]
        inside = None
        for m in mids:
            p = anchor + n * m
            for bi_, ms in enumerate(solids):
                if ms.contains(p):
                    inside = bi_
        if inside is None:
            votes, body = -1, last_body
        else:
            votes, body = 1, inside
    if votes >= 0:
        output = 'new' if first_in_body(body) else 'join'
    else:
        output = 'cut'
    return direction, output, body


# ------------------------------------------------------------------ fillet edges
def gap(r, dihedral_deg):
    h = math.radians(dihedral_deg) / 2
    return r * (1 / max(math.cos(h), 1e-9) - 1)


def match_edges(K, shape, r, blend_faces, brep, tol=0.005):
    out = []
    boxes = {f: (brep.face_points(f).min(0), brep.face_points(f).max(0)) for f in blend_faces}
    for e in K.edges(shape):
        if e['nfaces'] != 2 or e['dihedral'] < 1 or e['length'] < 1e-6:
            continue
        m = np.array(e['mid'])
        g = gap(r, e['dihedral'])
        for f in blend_faces:
            lo, hi = boxes[f]
            if np.any(m < lo - 3 * r) or np.any(m > hi + 3 * r):
                continue
            if abs(brep.surfdist(f)(m / 10) * 10 - g) < tol:
                out.append(e)
                break
    return out


def edge_sel(e):
    return {'m': [e['mid'][0], e['mid'][1], e['mid'][2]], 'l': e['length'],
            'k': e['type'] if e['type'] in (1, 2, 3) else 4, 'r': e['radius']}


# ------------------------------------------------------------------ the part
def convert(ipt_path, out_path=None, log=print, kernel=None):
    ipt = IptFile(ipt_path)
    name = os.path.splitext(os.path.basename(ipt_path))[0]
    dc_data, dc_meta = ipt.segments()['PmDCSegment']
    sab = asm_sab.parse(ipt.brep_segment())
    brep = BrepInfo(sab)
    part = InventorPart(dc_data, dc_meta)
    dc = part.dc
    profs = profiles(dc_data)
    feats = timeline(dc, dc.sketch_mains(), part.params, brep.all_tag_ids())
    sketches = {s.main: s for s in part.sketches}

    # ---- sketches
    app_sketches = {}
    template = open(os.path.join(HERE, 'sketch_template.dxf'), encoding='utf-8').read()
    for s in part.sketches:
        a = ptp_sketch.convert(s)
        worst, bad = check_sketch.check(a)
        if bad:
            raise ConversionError(f'{s.name}: {len(bad)} constraint(s) not satisfied after conversion: {bad[:2]}')
        app_sketches[s.main] = a
        log(f'  sketch {s.name}: {len(a.geos)} entities, {len(a.cons)} constraints (worst residual {worst:.1e})')

    # ---- bodies
    body_names = _body_names(dc, len(sab.of_type('body')))
    seen_body = set()

    def first_in_body(bi):
        return bi not in seen_body

    # ---- replay in the app kernel, building the feature list as we go
    from occt_kernel import Kernel
    from point_in_solid import MeshSolid
    import tempfile
    K = kernel or Kernel()
    step_txt, _, _ = A.brep_to_step(sab, names=list(body_names), product=name)
    tmp = os.path.join(tempfile.gettempdir(), f'ipt2ptp_{os.getpid()}.step')
    open(tmp, 'w', encoding='ascii').write(step_txt)
    solids = [MeshSolid(*K.triangles(s_)) for s_ in K.import_step_solids(tmp)]
    os.remove(tmp)
    last_body = None
    bodies = {}                  # body index -> shape
    features, sketch_rows, seq = [], [], 0
    fillet_faces_used = set()
    for f in feats:
        if f.kind == 'extrude':
            sk = sketches[f.sketch]
            a = app_sketches[f.sketch]
            pi = match_profile(sk, profs)
            pr = profs[pi]
            direction, output, bi = extrusion_semantics(f, sk, pr, brep, first_in_body, solids, last_body)
            seen_body.add(bi)
            last_body = bi
            dist = part.params[f.params[0]]['value'] * 10 if f.params else 0.0
            taper = math.degrees(part.params[f.params[1]]['value']) if len(f.params) > 1 else 0.0
            extent = f.extent
            # the sketch comes first in the timeline; a sketch on a face
            # records WHICH face (the app's SketchFaceSel), measured on the
            # body the app itself builds up to here, so an edit that moves
            # the face takes the sketch along -- as in Inventor
            row = _sketch_row(a, seq)
            if a.plane == 'face' and bodies:
                ref = _face_ref(K, bodies, sk, anchor3d_for(pr))
                if ref is not None:
                    row['faceRef'] = ref
            sketch_rows.append(row)
            seq += 1
            anchor3d, area = profile_anchor(pr)
            ax, ay = _to_app2d(a, sk, anchor3d)
            h = dist if extent == 'distance' else 1000.0
            span = {'default': (h, 0.0), 'flipped': (h, -h), 'symmetric': (h, -h / 2)}[direction]
            # the profile's own frame may face the other way than the sketch's
            s_sign = 1.0 if float(np.dot(pr.n, sk.frame[3])) > 0 else -1.0
            h_, st = span
            start = st if s_sign > 0 else -(st + h_)
            tool = K.place(K.extrude(pr.loops, h_, 0.0), pr.u, pr.v, pr.n, pr.origin, start)
            if output == 'new':
                bodies[bi] = tool
            else:
                bodies[bi] = K.boolean(output, bodies[bi], tool)
            st_ = K.stats(bodies[bi])
            log(f'  {f.name}: extrude {direction} {extent} {dist:g} mm {output} -> '
                f'{body_names[bi]} (vol {st_["volume"]:.3f}, valid {st_["valid"]})')
            features.append({
                'kind': 'extrude', 'name': f.name, 'seq': seq, 'body': body_names[bi],
                'visible': True, 'output': output, 'sketch': a.name,
                'profiles': [{'x': ax, 'y': ay, 'a': area}],
                'dir': direction, 'a': dist if extent == 'distance' else 5.0, 'b': 0.0,
                'taper': taper, 'exprA': f'{dist:g} mm' if extent == 'distance' else '5 mm',
                'exprB': '0 mm', 'exprTaper': f'{taper:.2f} deg', 'imate': False, 'match': True,
                'extent': extent,
            })
            seq += 1
            f.body = bi
        else:
            r = part.params[f.params[0]]['value'] * 10
            blend = brep.faces_of(f.tag, {'INV_NMX_BLEND_TAG'})
            # the body the fillet's own faces ended up in
            bi = brep.body_of_face[blend[0]] if blend else next(iter(bodies))
            es = match_edges(K, bodies[bi], r, blend, brep)
            if f.edge_count and len(es) < f.edge_count:
                # faces a LATER feature re-tagged (FEATURE_DEPENDENCY) lost this
                # fillet's tag; offer the unclaimed ones of this radius
                extra = [fc for fc in brep.faces if fc not in fillet_faces_used
                         and any(k == 'INV_NMX_FEATURE_DEPENDENCY_ATTRIB' for k, _ in brep.tags.get(fc, []))
                         and _radius(brep, fc) is not None and abs(_radius(brep, fc) - r) < 1e-6]
                es2 = match_edges(K, bodies[bi], r, blend + extra, brep)
                if len(es2) > len(es):
                    fillet_faces_used.update(extra)
                    es = es2
            fillet_faces_used.update(blend)
            sels = [edge_sel(e) for e in es if e['length'] > 0.05]
            ids = [e['id'] for e in es if e['length'] > 0.05]
            built, dropped = bodies[bi], ids
            if ids:
                try:
                    built, dropped, scale = K.fillet_ex(bodies[bi], ids, [r] * len(ids))
                except RuntimeError as ex:
                    built, dropped = bodies[bi], ids
            bodies[bi] = built
            note = '' if not dropped else f'  ({len(dropped)} of {len(ids)} edges NOT built by the kernel)'
            log(f'  {f.name}: fillet r={r:g} mm, {len(sels)} edges (Inventor stored {f.edge_count}){note}')
            features.append({
                'kind': 'fillet', 'name': f.name, 'seq': seq, 'body': body_names[bi], 'visible': True,
                'output': 'join', 'edges': sels, 'radii': [r] * len(sels),
                'exprRadius': f'{r:g} mm', 'allFillets': False, 'allRounds': False,
            })
            seq += 1

    # ---- exact results: the whole of Inventor's result per body
    step, solid_names, report = A.brep_to_step(sab, names=list(body_names), product=name,
                                               author=ipt.metadata().get('author', ''))
    step_entry = 'inventor/result.step'
    last_of_body = {}
    for i, fe in enumerate(features):
        last_of_body[fe['body']] = i
    for bname, i in last_of_body.items():
        features[i]['cache'] = {'step': step_entry, 'index': list(body_names).index(bname), 'sig': '*'}

    meta = {
        'version': 1, 'type': 'part',
        'vis': {k: False for k in ('yz', 'xz', 'xy', 'x', 'y', 'z', 'cp')},
        'cam': _camera(sab),
        'sketches': sketch_rows,
        'features': features,
        'featureN': len(features), 'solidN': len(body_names), 'seqNext': seq,
    }
    entries = {'meta.json': ptp_format.part_json(meta), step_entry: step.encode('ascii'),
               'inventor/source.ipt': ipt.raw}
    for a in app_sketches.values():
        entries.update(ptp_sketch.files(a, template))
    thumb = ipt.thumbnail_png()
    if thumb:
        entries['preview.png'] = thumb
    info = {'converter': CONVERTER, 'source_name': os.path.basename(ipt_path),
            'source_sha256': hashlib.sha256(ipt.raw).hexdigest(),
            'metadata': ipt.metadata(), 'bodies': report['bodies'],
            'parameters': {k: v['value'] for k, v in part.params.items()}}
    # What ptp2ipt checks to know the part is still Inventor's: the same
    # feature list, and every stored result still in place -- the app drops
    # a stored result exactly when an edit changes the tree under it.
    info['features'] = [[fe['name'], fe['kind'], fe['body']] for fe in features]
    info['cached'] = [fe['name'] for fe in features if 'cache' in fe]
    entries['inventor/source.json'] = json.dumps(info, indent=2, ensure_ascii=False).encode('utf-8')
    out_path = out_path or os.path.splitext(ipt_path)[0] + '.ptp'
    with open(out_path, 'wb') as fh:
        fh.write(ptp_format.encode('part', entries))
    log(f'wrote {out_path}')
    return out_path


def _radius(brep, f):
    g = brep.surface(f)
    if g.kind == 'cylinder':
        return g.radius * 10
    if g.kind == 'torus':
        return abs(g.minor) * 10
    return None


def _body_names(dc, n):
    named = dc.named_objects()
    import re
    pat = re.compile(r'^(Solid|Volumenkörper|Volumen|Corps|Cuerpo|Corpo|Body|Körper)\s?\d+$')
    found = [k for k, v in sorted(named.items(), key=lambda kv: kv[1]) if pat.match(k)]
    out = [found[i] if i < len(found) else f'Solid{i + 1}' for i in range(n)]
    return out


def anchor3d_for(pr):
    return profile_anchor(pr)[0]


def _face_ref(K, bodies, sk, anchor):
    """The planar face the sketch lies on, as the app records it."""
    o, x, y, n = [np.array(v, float) for v in sk.frame]
    best = None
    for shape in bodies.values():
        for r in K.planar_face_recs(shape):
            if float(r['n'] @ n) < 0.999:
                continue
            if abs(float((r['c'] - o) @ n)) > 1e-6:
                continue                      # not in the sketch plane
            d = np.linalg.norm((r['c'] - np.array(anchor)) - n * float((r['c'] - np.array(anchor)) @ n))
            if best is None or d < best[0]:
                best = (d, r)
    if best is None:
        return None
    r = best[1]
    return {'c': [float(v) for v in r['c']], 'n': [float(v) for v in r['n']], 'a': float(r['area'])}


def _sketch_row(a, seq):
    row = {'name': a.name, 'plane': a.plane, 'vis': False, 'seq': seq}
    if a.plane == 'face':
        u, v, n, o = a.frame
        row['frame'] = [float(c) for c in (*u, *v, *n, *o)]
    return row


def _to_app2d(a, sk, p3):
    p3 = np.array(p3, float)
    if a.plane == 'face':
        u, v, n, o = [np.array(c, float) for c in a.frame]
        return float((p3 - o) @ u), float((p3 - o) @ v)
    u, v, _ = [np.array(c, float) for c in ptp_sketch.APP_PLANES[a.plane]]
    return float(p3 @ u), float(p3 @ v)


def _camera(sab):
    from ipt2ptp import _camera as cam
    return cam(sab)
