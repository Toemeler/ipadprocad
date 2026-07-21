/*
 * iPadProCAD — flat C-ABI shim over OpenCASCADE (OCCT).
 *
 * First hand-picked surface: just enough B-Rep + STEP to prove the kernel
 * works end-to-end (primitive, sketch-profile extrusion, boolean fuse,
 * validity/mass/topology queries, STEP round-trip). NOT the full API — the
 * Dart FFI binding comes in a later session and must not exist yet.
 *
 * Style mirrors backend/qcad-core/src/capi/qcad_capi.h and
 * backend/slvs/shim/slvs_shim.h:
 *   - Pure C interface (extern "C"), opaque handles, no C++ types at the ABI.
 *   - Functions returning `int` use 1 = success, 0 = failure (unless noted).
 *   - Lengths/coordinates are doubles in model units (mm by convention).
 *   - Returned `const char*` point to storage owned by the library; callers
 *     must not free them and must copy if the value has to outlive the next
 *     shim call. Not thread-safe (single UI/solver thread, like the rest of
 *     the app's native layer).
 *   - Every entry point catches all OCCT exceptions internally; nothing ever
 *     unwinds across the C boundary. On failure, occt_last_error() explains.
 */
#ifndef OCCT_CAPI_H
#define OCCT_CAPI_H

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque B-Rep shape handle (wraps a TopoDS_Shape). */
typedef struct occt_shape occt_shape;

/*
 * Human-readable version/marker string, e.g.
 *   "iPadProCAD OCCT shim v1 (OCCT 7.9.3)".
 * The literal prefix "iPadProCAD OCCT shim" is what the CI link check greps
 * for in the Runner binary (same mechanism as the QCAD / SLVS markers).
 */
const char *occt_version(void);

/* Shim ABI version, starts at 1. Bump when the surface changes so an old
 * binary can be detected from Dart (same versioning idea as slvs_shim). */
int occt_shim_version(void);

/* Message of the most recent failure in this shim ("" if none yet). */
const char *occt_last_error(void);

/* ---- Construction ---------------------------------------------------- */

/* Axis-aligned solid box with one corner at the origin. NULL on failure. */
occt_shape *occt_make_box(double dx, double dy, double dz);

/* Solid cylinder: base circle centred at (cx,cy,cz), axis +Z, radius r,
 * height h. NULL on failure. */
occt_shape *occt_make_cylinder(double cx, double cy, double cz,
                               double r, double h);

/*
 * Extrude a closed 2D profile into a solid — the core sketch->part step.
 * `xy` holds npts (x,y) pairs in the z=0 plane, in order, WITHOUT repeating
 * the first point (the polygon is closed automatically); npts >= 3. The
 * profile must be a simple (non-self-intersecting) loop. Extrusion is along
 * +Z by `height` (> 0). NULL on failure.
 */
occt_shape *occt_extrude_polygon(const double *xy, int npts, double height);

/* Boolean fuse (union) of two solids. Inputs stay owned by the caller and
 * remain valid. NULL on failure. */
occt_shape *occt_fuse(const occt_shape *a, const occt_shape *b);

/* ---- Queries ---------------------------------------------------------- */

/* Count unique faces / edges / vertices of the shape. Any out-pointer may be
 * NULL if that count is not wanted. Returns 1/0. */
int occt_shape_counts(const occt_shape *shape,
                      int *faces, int *edges, int *vertices);

/* 1 if BRepCheck_Analyzer considers the shape valid, 0 otherwise/on error. */
int occt_shape_valid(const occt_shape *shape);

/* Enclosed volume (model units^3); negative value on failure. */
double occt_shape_volume(const occt_shape *shape);

/* Axis-aligned bounding box: out6 = {xmin,ymin,zmin,xmax,ymax,zmax}.
 * Returns 1/0. */
int occt_bbox(const occt_shape *shape, double *out6);

/* ---- STEP exchange ----------------------------------------------------- */

/* Write the shape to a STEP (AP214, AsIs) file at `path`. Returns 1/0. */
int occt_export_step(const occt_shape *shape, const char *path);

/* Read a STEP file and return all roots as one shape (compound if several).
 * NULL on failure (missing/garbage file included — never crashes). */
occt_shape *occt_import_step(const char *path);

/* ---- Lifecycle --------------------------------------------------------- */

/* Release a shape returned by any constructor above. NULL is ignored. */
void occt_free_shape(occt_shape *shape);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* OCCT_CAPI_H */
