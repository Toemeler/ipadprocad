"""Load a STEP file through the app's own kernel (prototype_native.dll, the
OCCT shim) and report, per solid: BRepCheck validity, volume, bounding box
and face/edge/vertex counts. This is exactly the path the app's STEP import
takes (occt_import_step + occt_split_solids).

usage: py validate_step.py file.step [path/to/prototype_native.dll]
"""
import ctypes as C
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DLL = os.path.join(HERE, '..', '..', 'frontend', 'build', 'native', 'prototype_native.dll')


def load(dll_path):
    dll_path = os.path.abspath(dll_path)
    d = os.path.dirname(dll_path)
    for sub in ('', 'deps'):
        p = os.path.join(d, sub)
        if os.path.isdir(p):
            os.add_dll_directory(p)
    lib = C.CDLL(dll_path)
    lib.occt_import_step.restype = C.c_void_p
    lib.occt_import_step.argtypes = [C.c_char_p]
    lib.occt_split_solids.restype = C.c_int
    lib.occt_split_solids.argtypes = [C.c_void_p, C.POINTER(C.c_void_p), C.c_int]
    lib.occt_shape_valid.restype = C.c_int
    lib.occt_shape_valid.argtypes = [C.c_void_p]
    lib.occt_shape_volume.restype = C.c_double
    lib.occt_shape_volume.argtypes = [C.c_void_p]
    lib.occt_bbox.restype = C.c_int
    lib.occt_bbox.argtypes = [C.c_void_p, C.POINTER(C.c_double)]
    lib.occt_shape_counts.restype = C.c_int
    lib.occt_shape_counts.argtypes = [C.c_void_p] + [C.POINTER(C.c_int)] * 3
    lib.occt_free_shape.argtypes = [C.c_void_p]
    lib.occt_last_error.restype = C.c_char_p
    return lib


def validate(step_path, dll_path=DEFAULT_DLL):
    lib = load(dll_path)
    shape = lib.occt_import_step(os.path.abspath(step_path).encode('utf-8'))
    if not shape:
        raise RuntimeError('import failed: ' + (lib.occt_last_error() or b'').decode('utf-8', 'replace'))
    buf = (C.c_void_p * 64)()
    n = lib.occt_split_solids(shape, buf, 64)
    out = []
    for i in range(n):
        s = buf[i]
        bb = (C.c_double * 6)()
        lib.occt_bbox(s, bb)
        f, e, v = C.c_int(), C.c_int(), C.c_int()
        lib.occt_shape_counts(s, C.byref(f), C.byref(e), C.byref(v))
        out.append(dict(valid=bool(lib.occt_shape_valid(s)), volume=lib.occt_shape_volume(s),
                        bbox=list(bb), faces=f.value, edges=e.value, vertices=v.value))
        lib.occt_free_shape(s)
    lib.occt_free_shape(shape)
    return out


if __name__ == '__main__':
    sys.stdout.reconfigure(encoding='utf-8')
    res = validate(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else DEFAULT_DLL)
    ok = True
    for i, r in enumerate(res):
        size = [r['bbox'][k + 3] - r['bbox'][k] for k in range(3)]
        print(f"solid {i}: valid={r['valid']} volume={r['volume']:.3f} mm3 "
              f"faces={r['faces']} edges={r['edges']} vertices={r['vertices']} "
              f"size={[round(x, 3) for x in size]}")
        ok &= r['valid'] and r['volume'] > 0
    print('OK' if ok and res else 'FAILED')
    sys.exit(0 if ok and res else 1)
