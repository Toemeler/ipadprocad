"""Capture actual build123d calls as a native, editable construction graph.

No reverse engineering of a finished STEP, invented sketches, or opaque result
features. Unrecorded solid operations fail instead of silently importing a B-Rep.
Geometry and workplanes are retained until serialization so placements compose
before conversion to the app's Y-up frame.
"""
import contextlib
import functools
import inspect
import math

import build123d as bd
from build123d.objects_part import BasePartObject


class HistoryError(ValueError):
    pass


def app_vector(point):
    x, y, z = bd.Vector(point)
    return [x, z, -y]


def profile(faces, location=bd.Location(), plane=None):
    faces = [f.moved(location) for f in faces]
    if not faces:
        raise HistoryError('An editable feature requires a sketch profile')
    plane = (plane.moved(location) if plane else bd.Plane(faces[0]))
    for f in faces:
        if f.geom_type != bd.GeomType.PLANE:
            raise HistoryError('A native sketch must be planar')
        if abs(plane.to_local_coords(f.center()).Z) > 1e-5:
            raise HistoryError('One sketch cannot contain faces on different planes')
    return {'frame': frame(plane), 'curves': curves([e for f in faces for e in f.edges()], plane)}


def frame(plane):
    return [*app_vector(plane.x_dir), *app_vector(plane.y_dir),
            *app_vector(plane.z_dir), *app_vector(plane.origin)]


def curves(edges, plane):
    result = []
    def point(p):
        q = plane.to_local_coords(p)
        if abs(q.Z) > 1e-5:
            raise HistoryError('Nonplanar curve cannot become an editable native sketch')
        return [q.X, q.Y]
    for edge in edges:
        kind = edge.geom_type
        if kind == bd.GeomType.LINE:
            result.append({'type': 1, 'data': [*point(edge.position_at(0)), *point(edge.position_at(1))]})
        elif kind == bd.GeomType.CIRCLE:
            c = point(edge.arc_center)
            if edge.is_closed:
                result.append({'type': 2, 'data': [*c, edge.radius]})
            else:
                a, m, b = [point(edge.position_at(t)) for t in [0, .5, 1]]
                angles = [math.atan2(p[1]-c[1], p[0]-c[0]) for p in [a, m, b]]
                sweep = (angles[2]-angles[0]) % math.tau
                reverse = (angles[1]-angles[0]) % math.tau > sweep
                result.append({'type': 3, 'data': [*c, edge.radius, angles[0], angles[2], int(reverse)]})
        elif kind == bd.GeomType.BEZIER:
            from OCP.BRepAdaptor import BRepAdaptor_Curve
            arc = BRepAdaptor_Curve(edge.wrapped).Bezier()
            if arc.IsRational() or arc.Degree()>3:
                raise HistoryError('Native sketch requires a non-rational cubic Bezier')
            arc.Increase(3)
            controls=[point(bd.Vector(arc.Pole(j))) for j in range(1,5)]
            result.append({'type':4,'spline':6,'data':[0,4,*[v for p in controls for v in p]]})
        elif kind == bd.GeomType.BSPLINE:
            # The native sketch already supports editable cubic Bezier chains.
            # Preserve their control points, not a sampled polygon.
            from OCP.BRepAdaptor import BRepAdaptor_Curve
            from OCP.GeomConvert import GeomConvert_BSplineCurveToBezierCurve
            adaptor = BRepAdaptor_Curve(edge.wrapped)
            spline = adaptor.BSpline()
            if spline.IsRational() or spline.Degree() > 3:
                raise HistoryError('Native sketches support non-rational cubic splines; use arcs or cubic splines for this profile')
            converter = GeomConvert_BSplineCurveToBezierCurve(spline, adaptor.FirstParameter(), adaptor.LastParameter())
            controls = []
            for i in range(1, converter.NbArcs()+1):
                arc = converter.Arc(i)
                arc.Increase(3)
                poles = [point(bd.Vector(arc.Pole(j))) for j in range(1,5)]
                controls.extend(poles if not controls else poles[1:])
            result.append({'type':4, 'spline':6, 'data':[0,len(controls),*[v for p in controls for v in p]]})
        else:
            raise HistoryError(f'Native editable sketch curve {kind.name} is not supported; use lines, arcs, circles or cubic splines')
    if not result or len(result) > 2000:
        raise HistoryError('Sketch must contain 1..2000 editable curves')
    return result


class History:
    def __init__(self):
        self.shapes = {}
        self.patches = []
        self.busy = 0

    @contextlib.contextmanager
    def quiet(self):
        self.busy += 1
        try: yield
        finally: self.busy -= 1

    def remember(self, shape, node):
        self.shapes[id(shape)] = (shape, node)
        return node

    def lookup(self, shape):
        item = self.shapes.get(id(shape))
        if item and item[0] is shape:
            return item[1]
        # Builder wrappers and topology casts can retain the same B-Rep under
        # a different Python object. Compare kernel identity, never a bbox.
        for known, node in reversed(list(self.shapes.values())):
            if shape.wrapped is not None and known.wrapped is not None and shape.wrapped.IsSame(known.wrapped):
                return node
        raise HistoryError('Unrecorded solid operation: use build123d Box/Cylinder, extrude, revolve, loft, planar sweep, booleans, fillet or chamfer. No imported-solid fallback is allowed.')

    def existing(self, name, shape):
        self.remember(shape, {'op':'input', 'name':name})

    def patch(self, obj, name, wrapper):
        original = getattr(obj, name)
        self.patches.append((obj,name,original))
        setattr(obj,name,wrapper(original))

    def context_result(self, context, before, node, mode):
        if context is None or mode == bd.Mode.PRIVATE: return
        if before is None:
            if mode not in [bd.Mode.ADD, bd.Mode.REPLACE]:
                raise HistoryError('Cut/intersect requires an existing native body')
            combined = node
        elif mode == bd.Mode.REPLACE:
            combined = node
        else:
            combined = {'op':{bd.Mode.ADD:'join',bd.Mode.SUBTRACT:'cut',bd.Mode.INTERSECT:'intersect'}[mode],
                        'left':self.lookup(before), 'right':node}
        self.remember(context.part, combined)

    def primitive(self, original):
        @functools.wraps(original)
        def call(shape, part, rotation=(0,0,0), align=None, mode=bd.Mode.ADD):
            if self.busy: return original(shape, part, rotation, align, mode)
            context = bd.BuildPart._get_context(log=False)
            before = context.part if context else None
            with self.quiet():
                original(shape, part, rotation, align, mode)
                kind = type(shape).__name__
                if kind not in ['Box','Cylinder','Sphere','Cone','Torus']:
                    raise HistoryError(f'{kind} does not yet have an editable primitive mapping. Construct it from sketches with extrude/revolve/loft/sweep instead.')
                box = part.bounding_box()
                bottom = [f for f in part.faces() if f.geom_type == bd.GeomType.PLANE and f.normal_at().Z < -.999]
                if kind in ['Box','Cylinder']:
                    if len(bottom)!=1: raise HistoryError('Primitive has no single planar base sketch')
                    plane=bd.Plane(origin=(0,0,box.min.Z),x_dir=(1,0,0),z_dir=(0,0,1))
                    base={'op':'extrude','faces':bottom,'plane':plane,
                          'amount':box.size.Z,'taper':0,'both':False}
                else:
                    c=box.center()
                    plane=bd.Plane(origin=c,x_dir=(1,0,0),z_dir=(0,-1,0))
                    axis=bd.Axis(c,(0,0,1))
                    if kind=='Sphere':
                        r=box.size.Z/2
                        if abs(part.volume-4*math.pi*r**3/3)>1e-4:
                            raise HistoryError('Partial Sphere needs an explicit native revolve profile')
                        wire=bd.Wire([bd.Edge.make_three_point_arc(c+(0,0,-r),c+(r,0,0),c+(0,0,r)),
                                      bd.Edge.make_line(c+(0,0,r),c+(0,0,-r))])
                    elif kind=='Cone':
                        rings=[e for e in part.edges() if e.geom_type==bd.GeomType.CIRCLE and e.is_closed]
                        low=next((e.radius for e in rings if abs(e.arc_center.Z-box.min.Z)<1e-6),0)
                        high=next((e.radius for e in rings if abs(e.arc_center.Z-box.max.Z)<1e-6),0)
                        z0,z1=box.min.Z,box.max.Z
                        points=[(c.X,c.Y,z0),(c.X+low,c.Y,z0),(c.X+high,c.Y,z1),(c.X,c.Y,z1)]
                        unique=[p for i,p in enumerate(points) if p!=points[i-1]]
                        wire=bd.Wire.make_polygon(unique,close=True)
                    else:
                        from OCP.BRepAdaptor import BRepAdaptor_Surface
                        torus=BRepAdaptor_Surface(next(f for f in part.faces() if f.geom_type==bd.GeomType.TORUS).wrapped).Torus()
                        r=torus.MinorRadius();major=torus.MajorRadius()
                        c=bd.Vector(torus.Location())
                        plane=bd.Plane(origin=c,x_dir=(1,0,0),z_dir=(0,-1,0));axis=bd.Axis(c,(0,0,1))
                        if abs(part.volume-2*math.pi**2*major*r*r)>1e-4:
                            raise HistoryError('Partial Torus needs an explicit native revolve profile')
                        wire=bd.Wire.make_circle(r,bd.Plane(origin=c+(major,0,0),x_dir=(1,0,0),z_dir=(0,-1,0)))
                    base={'op':'revolve','faces':[bd.Face(wire)],'plane':plane,'axis':axis,'angle':360}
                rotate = bd.Rotation(*rotation) if isinstance(rotation,tuple) else rotation
                locations = bd.LocationList._get_context().locations if context else [bd.Location()]
                nodes = [base | {'placement':loc*rotate} for loc in locations]
                node = nodes[0]
                for other in nodes[1:]: node = {'op':'join','left':node,'right':other}
            self.remember(shape,node)
            self.context_result(context,before,node,mode)
        return call

    def operation(self, name):
        def wrap(original):
            signature = inspect.signature(original)
            @functools.wraps(original)
            def call(*args,**kwargs):
                if self.busy: return original(*args,**kwargs)
                bound = signature.bind(*args,**kwargs); bound.apply_defaults(); p=bound.arguments
                context = bd.BuildPart._get_context(log=False)
                if not isinstance(context,bd.BuildPart): context=None
                before = context.part if context else None
                def faces(key):
                    obj = p.get(key)
                    if obj is None: return list(context.pending_faces) if context else []
                    values = list(obj) if isinstance(obj,(list,tuple)) else [obj]
                    return [f for value in values for f in value.faces()]
                with self.quiet():
                    if name == 'extrude':
                        fs = faces('to_extrude')
                        if p['amount'] is None or p['until'] is not None:
                            raise HistoryError('Use a numeric extrude amount for native editable extents')
                        if p['dir'] is not None:
                            if any(abs(abs(bd.Vector(p['dir']).normalized().dot(f.normal_at()))-1)>1e-6 for f in fs):
                                raise HistoryError('Oblique extrusion has no native mapping; use loft')
                        planes=(list(context.pending_face_planes) if p['to_extrude'] is None and context else [bd.Plane(f) for f in fs])
                        pieces=[]
                        for face,plane in zip(fs,planes):
                            piece={'op':'extrude','faces':[face],'plane':plane,
                                   'amount':p['amount'],'both':p['both'],'taper':p['taper']}
                            if p['dir'] is not None: piece['direction']=bd.Vector(p['dir'])
                            if p['both'] and abs(p['taper']) > 1e-9:
                                # build123d drafts away from the sketch in BOTH
                                # directions; a native symmetric feature drafts
                                # continuously from one end to the other.
                                pieces.extend([piece | {'both':False},
                                    piece | {'amount':-p['amount'],'both':False}])
                            else:
                                pieces.append(piece)
                        if not pieces: raise HistoryError('Extrude did not supply recorded face workplanes')
                        node=pieces[0]
                        for other in pieces[1:]: node={'op':'join','left':node,'right':other}
                    elif name == 'revolve':
                        node={'op':'revolve','faces':faces('profiles'),'axis':p['axis'],'angle':p['revolution_arc']}
                    elif name == 'loft':
                        node={'op':'loft','faces':faces('sections'),'ruled':p['ruled']}
                    elif name == 'sweep':
                        if p['multisection'] or p['normal'] is not None or p['binormal'] is not None:
                            raise HistoryError('Native sweep requires one profile and default transport')
                        path = p['path'] or (bd.Wire(context.pending_edges) if context else None)
                        if path is None: raise HistoryError('Sweep requires an editable path')
                        node={'op':'sweep','faces':faces('sections'),'path':path,'frenet':p['is_frenet']}
                    elif name=='offset':
                        target=p['objects'] if p['objects'] is not None else before
                        if not isinstance(target,bd.Shape) or target._dim!=3:
                            return original(*args,**kwargs)
                        openings=p['openings'] or []
                        if isinstance(openings,bd.Face): openings=[openings]
                        node={'op':'shell','left':self.lookup(target),'faces':list(openings),'amount':p['amount']}
                    else:
                        selected=list(p['objects']) if not isinstance(p['objects'],bd.Edge) else [p['objects']]
                        if not selected or not isinstance(selected[0],bd.Edge):
                            # 2D sketch finishing is included in the captured profile.
                            return original(*args,**kwargs)
                        target=before if context else selected[0].topo_parent
                        if target is None or target._dim != 3: return original(*args,**kwargs)
                        # build123d selectors include periodic seam edges. OCCT
                        # ignores those while blending; they are not two-face
                        # intersections and have no native fillet selection.
                        selected=[e for e in selected if sum(e in f.edges() for f in target.faces())>=2]
                        if not selected: raise HistoryError('Finishing selected only seam/boundary edges')
                        node={'op':name,'left':self.lookup(target),'edges':selected,
                              'size':p['radius'] if name=='fillet' else p['length']}
                        if name=='chamfer' and (p['length2'] is not None or p['angle'] is not None or p['reference'] is not None):
                            raise HistoryError('Native chamfer capture currently requires equal distances')
                    result = original(*args,**kwargs)
                self.remember(result,node)
                self.context_result(context,before,node,bd.Mode.REPLACE if name in ['fillet','chamfer','offset'] else p['mode'])
                return result
            return call
        return wrap

    def boolean(self, name, op):
        def wrap(original):
            @functools.wraps(original)
            def call(left,right):
                if self.busy or left._dim != 3: return original(left,right)
                with self.quiet():
                    a=self.lookup(left)
                    values=list(right) if isinstance(right,(list,tuple)) else [right]
                    nodes=[self.lookup(value) for value in values]
                    result=original(left,right)
                node=a
                for b in nodes: node={'op':op,'left':node,'right':b}
                self.remember(result,node)
                return result
            return call
        return wrap

    def movement(self, absolute=False):
        def wrap(original):
            @functools.wraps(original)
            def call(shape,loc):
                if self.busy or shape._dim != 3: return original(shape,loc)
                node=self.lookup(shape)
                if isinstance(loc,bd.Plane): loc=loc.location
                delta=loc*shape.location.inverse() if absolute else loc
                with self.quiet(): result=original(shape,loc)
                self.remember(result,{'op':'placement','left':node,'location':delta})
                return result
            return call
        return wrap

    def __enter__(self):
        self.patch(BasePartObject,'__init__',self.primitive)
        for name in ['extrude','revolve','loft','sweep','fillet','chamfer','offset']:
            self.patch(bd,name,self.operation(name))
        for cls in [bd.Shape,bd.Compound]:
            for name,op in [('__add__','join'),('__sub__','cut'),('__and__','intersect')]:
                self.patch(cls,name,self.boolean(name,op))
        for name in ['moved','move']:
            self.patch(bd.Shape,name,self.movement())
        for name in ['located','locate']:
            self.patch(bd.Shape,name,self.movement(True))
        return self

    def __exit__(self,*_):
        for obj,name,original in reversed(self.patches): setattr(obj,name,original)
        self.shapes.clear()

    def serialize(self, shape):
        with self.quiet():
            root=self.lookup(shape)
            nodes=[]
            def visit(node,location=bd.Location()):
                if len(nodes)>128: raise HistoryError('At most 128 native construction steps')
                op=node['op']
                if op=='placement': return visit(node['left'],location*node['location'])
                out={'op':op}
                if op=='input':
                    if location != bd.Location(): raise HistoryError('Moving an existing input body has no editable capture yet; use native move tools')
                    out['name']=node['name']
                elif op in ['join','cut','intersect']:
                    out.update(left=visit(node['left'],location),right=visit(node['right'],location))
                elif op in ['fillet','chamfer']:
                    out.update(left=visit(node['left'],location),size=node['size'],
                        edges=[app_vector(e.moved(location).center()) for e in node['edges']])
                elif op=='shell':
                    out.update(left=visit(node['left'],location),amount=node['amount'],
                        faces=[{'point':app_vector(f.moved(location).center()),
                                'normal':app_vector(f.moved(location).normal_at())} for f in node['faces']])
                elif op=='loft':
                    out.update(profiles=[profile([f],location) for f in node['faces']],ruled=node['ruled'])
                elif op=='sweep':
                    path=node['path'].moved(location)
                    edges=path.edges()
                    points=[e.position_at(t) for e in edges for t in [0,.5,1]]
                    origin=points[0]
                    u=next((q-origin for q in points if (q-origin).length>1e-6),bd.Vector(1,0,0)).normalized()
                    normal=next((u.cross(q-origin).normalized() for q in points if u.cross(q-origin).length>1e-6),None)
                    if normal is None:
                        normal=u.cross(bd.Vector(0,0,1) if abs(u.Z)<.9 else bd.Vector(0,1,0)).normalized()
                    plane=bd.Plane(origin=origin,x_dir=u,z_dir=normal)
                    out.update(profiles=[profile(node['faces'],location)],
                        path={'frame':frame(plane),'curves':curves(path.edges(),plane)},frenet=node['frenet'])
                else:
                    location=location*node.get('placement',bd.Location())
                    sketch=profile(node['faces'],location,node.get('plane'))
                    out['profiles']=[sketch]
                    if op=='extrude':
                        # Native extrusion grows along the captured plane normal.
                        # build123d follows its face's orientation (or explicit dir).
                        source_plane=node.get('plane') or bd.Plane(node['faces'][0])
                        direction=node.get('direction') or source_plane.z_dir
                        sign=1 if direction.dot(source_plane.z_dir)>0 else -1
                        amount=node['amount']*sign
                        if amount < 0:
                            # Native flipped extents translate the starting
                            # face. Reverse the workplane instead so the draft
                            # starts at the actual controlling sketch.
                            reverse=bd.Plane(origin=source_plane.origin,
                                x_dir=source_plane.x_dir,z_dir=-source_plane.z_dir)
                            out['profiles']=[profile(node['faces'],location,reverse)]
                        out.update(amount=abs(amount),both=node['both'],taper=node['taper'])
                    elif op=='revolve':
                        axis=node['axis']
                        plane=(node.get('plane') or bd.Plane(node['faces'][0]))
                        p=plane.to_local_coords(axis.position);d=axis.direction
                        if abs(p.Z)>1e-5 or abs(d.dot(plane.z_dir))>1e-5:
                            raise HistoryError('Native revolve axis must lie in its profile sketch')
                        out.update(axis=[p.X,p.Y,d.dot(plane.x_dir),d.dot(plane.y_dir)],angle=node['angle'])
                    else: raise HistoryError(f'No editable native mapping for {op}')
                out['id']=len(nodes)
                nodes.append(out)
                return out['id']
            final=visit(root)
            if len(nodes)>128: raise HistoryError('At most 128 native construction steps')
            return {'version':1,'nodes':nodes,'root':final}
