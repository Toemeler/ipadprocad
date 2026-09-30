"""The feature timeline of an Inventor part (PmDCSegment).

Structure, as found:
  * browser name nodes ("Extrusion1", "Rundung3", ...) point at the feature
    object; the feature object points at its definition object and, for a
    sketch-based feature, at the sketch's main object;
  * a body's feature list (the object after the body list, e.g. object 7)
    holds one reference per feature in TIMELINE order; the value of that
    reference (index + 1) is the id Inventor writes into the B-rep face tags
    of the faces the feature made (INV_NMX_BLEND_TAG, ...SWEEPGENERATED...);
  * an extrusion's definition -> extent object -> (distance dim, taper dim);
    the distance dimension stores its leader end points in 3D, which give the
    direction; a through-all extent stores no dimension.
"""
import math
import struct

from ipt_dc import DC, f64, ref


class Feature:
    def __init__(self, name, node, obj):
        self.name, self.node, self.obj = name, node, obj
        self.kind = None             # 'extrude' | 'fillet'
        self.tag = None              # B-rep tag id of this feature
        self.sketch = None           # sketch main object
        self.params = []             # parameter names, in definition order
        self.distance = None         # mm
        self.taper = 0.0             # deg
        self.extent = 'distance'     # 'distance' | 'throughAll'
        self.leader = None           # (p0, p1) world mm of the distance dimension
        self.radius = None           # mm, fillets
        self.edge_count = None       # edges Inventor stored for a fillet

    def __repr__(self):
        return f'<{self.kind} {self.name} tag={self.tag} params={self.params}>'


def _refs(dc, i):
    return [r for _, r in dc.seg.refs(i)]


def timeline(dc, sketch_mains, params, brep_tags=()):
    named = dc.named_objects()
    node_of = {}
    for name, node in named.items():
        rs = _refs(dc, node)
        # a feature node points at a feature object that points back at it
        for r in rs[:3]:
            if node in _refs(dc, r)[:3] and len(dc.obj(r)) < 1000:
                node_of[name] = (node, r)
                break
    feats = {}
    sk_set = {m for _, m in sketch_mains}
    sk_names = {n for n, _ in sketch_mains}
    param_objs = {v['obj']: k for k, v in params.items()}
    for name, (node, obj) in node_of.items():
        if obj in sk_set or name in sk_names:
            continue                      # a sketch's own browser node
        rs = _refs(dc, obj)
        f = Feature(name, node, obj)
        sk = [r for r in rs if r in sk_set]
        defn = rs[2] if len(rs) > 2 else None
        if sk:
            f.kind, f.sketch = 'extrude', sk[0]
            _extrude_details(dc, f, defn, param_objs)
        elif rs.count(3) >= 1 and defn is not None:
            f.kind = 'fillet'
            f.edge_count = rs.count(3)
            _fillet_details(dc, f, defn, param_objs)
        else:
            continue
        feats[obj] = f
    # timeline order: the browser chain -- node -> chain object -> next node
    by_node = {f.node: f for f in feats.values()}
    succ, has_pred = {}, set()
    for f in feats.values():
        for c in _refs(dc, f.node)[:1]:
            for n2 in _refs(dc, c):
                if n2 in by_node and n2 != f.node:
                    succ[f.node] = n2
                    has_pred.add(n2)
    heads = [n for n in by_node if n not in has_pred]
    order = []
    for h in sorted(heads):
        n = h
        while n is not None and by_node[n] not in order:
            order.append(by_node[n])
            n = succ.get(n)
    # tags: a body's feature list holds one reference per feature, in
    # timeline order, and ends with the body's browser node; the reference
    # value (index + 1) is the id the B-rep face tags carry
    best, best_hits = None, -1
    for name, node in named.items():
        for i in range(0, min(dc.n, 64)):
            rs = _refs(dc, i)
            if not rs or rs[-1] != node:
                continue
            lst = [r for r in rs if r not in (0, 1, 2)][1:-1]
            if len(lst) != len(order):
                continue
            hits = sum(1 for t in lst if t + 1 in brep_tags)
            if hits > best_hits:
                best, best_hits = lst, hits
    if best is not None:
        for f, t in zip(order, best):
            f.tag = t + 1
    return order


def _feature_for_tag_object(dc, tag, feats):
    """The feature whose own sub-objects include object (tag - 1)."""
    obj = tag - 1
    rs = set(_refs(dc, obj)) if 0 <= obj < dc.n else set()
    for f in feats.values():
        if f.obj in rs or f.node in rs:
            return f
    return None


def _walk_params(dc, start, param_objs, depth=3, hubs=(0, 1, 2, 3)):
    seen, frontier, found = {start}, [start], []
    for _ in range(depth):
        nxt = []
        for x in frontier:
            for r in _refs(dc, x):
                if r in hubs or r in seen:
                    continue
                seen.add(r)
                if r in param_objs:
                    found.append(param_objs[r])
                nxt.append(r)
        frontier = nxt
    return found


def _extrude_details(dc, f, defn, param_objs):
    rs = _refs(dc, defn)
    extent = rs[-1]
    ers = [r for r in _refs(dc, extent) if r != 2]
    dist_obj, taper_obj = (ers + [None, None])[:2]
    for o in (dist_obj, taper_obj):
        if o is None:
            continue
        for r in _refs(dc, o):
            if r in param_objs:
                f.params.append(param_objs[r])
    b = dc.obj(dist_obj) if dist_obj is not None else b''
    if len(b) >= 56 and struct.unpack_from('<I', b, 0)[0] == 2:
        p0 = tuple(f64(b, 8 + 8 * k) * 10 for k in range(3))
        p1 = tuple(f64(b, 32 + 8 * k) * 10 for k in range(3))
        f.leader = (p0, p1)
    else:
        f.extent = 'throughAll'


def _fillet_details(dc, f, defn, param_objs):
    f.params = _walk_params(dc, defn, param_objs, depth=3, hubs=(0, 1, 2, 3, f.obj))
