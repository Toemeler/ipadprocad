"""ctypes access to the app's own modelling kernel (prototype_native.dll,
the OCCT shim), so a converted feature tree can be REPLAYED with the same
operations the app will run and compared against Inventor's result.
"""
import ctypes as C
import os

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DLL = os.path.join(HERE, '..', '..', 'frontend', 'build', 'native', 'prototype_native.dll')

_P = C.c_void_p
_D = C.POINTER(C.c_double)
_I = C.POINTER(C.c_int)


class Kernel:
    def __init__(self, dll=DEFAULT_DLL):
        dll = os.path.abspath(dll)
        for sub in ('', 'deps'):
            p = os.path.join(os.path.dirname(dll), sub)
            if os.path.isdir(p):
                os.add_dll_directory(p)
        L = self.L = C.CDLL(dll)
        sig = {
            'occt_extrude_profile_arcs': (_P, [_D, _I, C.c_int, C.c_double, C.c_double]),
            'occt_transform': (_P, [_P, _D]),
            'occt_fuse': (_P, [_P, _P]),
            'occt_cut': (_P, [_P, _P]),
            'occt_common': (_P, [_P, _P]),
            'occt_fillet_edges': (_P, [_P, _I, _D, _D, C.c_int]),
            'occt_fillet_edges_ex': (_P, [_P, _I, _D, _D, C.c_int, _I, _D]),
            'occt_shape_edge_count': (C.c_int, [_P]),
            'occt_shape_edges_info': (C.c_int, [_P, _D, C.c_int]),
            'occt_shape_valid': (C.c_int, [_P]),
            'occt_shape_volume': (C.c_double, [_P]),
            'occt_shape_counts': (C.c_int, [_P, _I, _I, _I]),
            'occt_bbox': (C.c_int, [_P, _D]),
            'occt_free_shape': (None, [_P]),
            'occt_last_error': (C.c_char_p, []),
            'occt_import_step': (_P, [C.c_char_p]),
            'occt_export_step': (C.c_int, [_P, C.c_char_p]),
            'occt_unify': (_P, [_P]),
            'occt_split_solids': (C.c_int, [_P, C.POINTER(_P), C.c_int]),
            'occt_mesh_create': (_P, [_P, C.c_double, C.c_double]),
            'occt_mesh_counts': (C.c_int, [_P, _I, _I, _I, _I]),
            'occt_mesh_vertices': (C.c_int, [_P, _D]),
            'occt_mesh_triangles': (C.c_int, [_P, _I]),
            'occt_free_mesh': (None, [_P]),
            'occt_mesh_face_count': (C.c_int, [_P]),
            'occt_mesh_triangle_faces': (C.c_int, [_P, _I]),
            'occt_mesh_face_infos': (C.c_int, [_P, _D]),
        }
        for name, (res, args) in sig.items():
            fn = getattr(L, name)
            fn.restype, fn.argtypes = res, args

    def err(self):
        e = self.L.occt_last_error()
        return e.decode('utf-8', 'replace') if e else ''

    def _check(self, s, what):
        if not s:
            raise RuntimeError(f'{what} failed: {self.err()}')
        return s

    def extrude(self, loops, height, taper=0.0):
        """loops: [[(x, y, bulge), ...], ...], loop 0 outer."""
        flat = [c for lp in loops for v in lp for c in v]
        xyb = (C.c_double * len(flat))(*flat)
        cnt = (C.c_int * len(loops))(*[len(lp) for lp in loops])
        return self._check(self.L.occt_extrude_profile_arcs(xyb, cnt, len(loops), height, taper), 'extrude')

    def place(self, shape, u, v, n, origin, z0=0.0):
        m = [u[0], v[0], n[0], origin[0] + n[0] * z0,
             u[1], v[1], n[1], origin[1] + n[1] * z0,
             u[2], v[2], n[2], origin[2] + n[2] * z0]
        return self._check(self.L.occt_transform(shape, (C.c_double * 12)(*m)), 'transform')

    def boolean(self, op, a, b):
        fn = {'join': self.L.occt_fuse, 'cut': self.L.occt_cut, 'intersect': self.L.occt_common}[op]
        return self._check(fn(a, b), op)

    def edges(self, shape):
        n = self.L.occt_shape_edge_count(shape)
        buf = (C.c_double * (12 * max(n, 1)))()
        k = self.L.occt_shape_edges_info(shape, buf, n)
        out = []
        for i in range(k):
            r = buf[12 * i:12 * i + 12]
            out.append(dict(id=i + 1, type=int(r[0]), mid=tuple(r[1:4]), tan=tuple(r[4:7]),
                            length=r[7], radius=r[8], nfaces=int(r[9]), dihedral=r[10], convex=int(r[11])))
        return out

    def fillet(self, shape, edge_ids, radii):
        n = len(edge_ids)
        return self._check(self.L.occt_fillet_edges(
            shape, (C.c_int * n)(*edge_ids), (C.c_double * n)(*radii), None, n), 'fillet')

    def fillet_ex(self, shape, edge_ids, radii):
        """Blends what can be blended; returns (shape, [dropped edge ids], scale)."""
        n = len(edge_ids)
        dropped = (C.c_int * n)()
        scale = C.c_double(1.0)
        s = self._check(self.L.occt_fillet_edges_ex(
            shape, (C.c_int * n)(*edge_ids), (C.c_double * n)(*radii), None, n, dropped, C.byref(scale)),
            'fillet')
        return s, [edge_ids[i] for i in range(n) if dropped[i]], scale.value

    def stats(self, shape):
        f, e, v = C.c_int(), C.c_int(), C.c_int()
        self.L.occt_shape_counts(shape, C.byref(f), C.byref(e), C.byref(v))
        bb = (C.c_double * 6)()
        self.L.occt_bbox(shape, bb)
        return dict(valid=bool(self.L.occt_shape_valid(shape)), volume=self.L.occt_shape_volume(shape),
                    faces=f.value, edges=e.value, vertices=v.value, bbox=list(bb))

    def import_step_solids(self, path):
        s = self._check(self.L.occt_import_step(os.path.abspath(path).encode('utf-8')), 'import')
        buf = (_P * 256)()
        n = self.L.occt_split_solids(s, buf, 256)
        return [buf[i] for i in range(n)]

    def triangles(self, shape, deflection=0.02):
        """(vertices Nx3, triangles Mx3) of a fine tessellation."""
        import numpy as np
        m = self._check(self.L.occt_mesh_create(shape, deflection, 0.1), 'mesh')
        nv, nt, ne, nep = C.c_int(), C.c_int(), C.c_int(), C.c_int()
        self.L.occt_mesh_counts(m, C.byref(nv), C.byref(nt), C.byref(ne), C.byref(nep))
        V = (C.c_double * (3 * nv.value))()
        T = (C.c_int * (3 * nt.value))()
        self.L.occt_mesh_vertices(m, V)
        self.L.occt_mesh_triangles(m, T)
        self.L.occt_free_mesh(m)
        return np.array(V).reshape(-1, 3), np.array(T).reshape(-1, 3)

    def planar_face_recs(self, shape, deflection=0.02):
        """The app's FaceRec list (part_model.dart planarFaceRecs): per planar
        face, the area-weighted centroid of its triangles, its normal from the
        kernel's face record, and its area."""
        import numpy as np
        m = self._check(self.L.occt_mesh_create(shape, deflection, 0.1), 'mesh')
        nv, nt, ne, nep = C.c_int(), C.c_int(), C.c_int(), C.c_int()
        self.L.occt_mesh_counts(m, C.byref(nv), C.byref(nt), C.byref(ne), C.byref(nep))
        nf = self.L.occt_mesh_face_count(m)
        V = (C.c_double * (3 * nv.value))()
        T = (C.c_int * (3 * nt.value))()
        TF = (C.c_int * max(nt.value, 1))()
        FI = (C.c_double * (15 * max(nf, 1)))()
        self.L.occt_mesh_vertices(m, V)
        self.L.occt_mesh_triangles(m, T)
        self.L.occt_mesh_triangle_faces(m, TF)
        self.L.occt_mesh_face_infos(m, FI)
        self.L.occt_free_mesh(m)
        V = np.array(V).reshape(-1, 3)
        T = np.array(T).reshape(-1, 3)
        acc = {}
        for t, f in zip(T, TF):
            if f < 0 or f >= nf or round(FI[15 * f]) != 0:
                continue
            a, b, c = V[t[0]], V[t[1]], V[t[2]]
            ar = np.linalg.norm(np.cross(b - a, c - a)) / 2
            if ar <= 0:
                continue
            s_, w = acc.get(f, (np.zeros(3), 0.0))
            acc[f] = (s_ + (a + b + c) / 3 * ar, w + ar)
        out = []
        for f, (s_, w) in acc.items():
            n = np.array(FI[15 * f + 4:15 * f + 7])
            out.append(dict(c=s_ / w, n=n / np.linalg.norm(n), area=w))
        return out

    def free(self, s):
        if s:
            self.L.occt_free_shape(s)
