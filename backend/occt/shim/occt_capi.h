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

/* v4 — Merge same-domain faces and edges (ShapeUpgrade_UnifySameDomain):
 * boolean results and arc-built prisms carry split faces/edges that render
 * as spurious lines; unify returns a NEW cleaned shape. NULL on failure. */
occt_shape *occt_unify(const occt_shape *shape);

/*
 * v2 — Extrude a MULTI-LOOP profile (outer boundary + holes) with an
 * optional taper, the full Inventor "Extrude" semantics:
 *   - `xy` holds the (x,y) pairs of ALL loops back to back, in the z=0
 *     plane, WITHOUT repeating a loop's first point.
 *   - `loop_counts[i]` is the number of points of loop i (>= 3 each);
 *     `nloops` >= 1. Loop 0 is the OUTER boundary; loops 1.. are HOLES and
 *     must lie strictly inside the outer loop (and not intersect it or each
 *     other). Winding order of the input is irrelevant — the shim
 *     normalises orientations itself (outer CCW, holes CW).
 *   - Extrusion is along +Z from z=0 by `height` (> 0).
 *   - `taper_deg` tilts every lateral face about the base plane, INVENTOR
 *     sign convention: positive flares OUTWARD going up (outer boundary
 *     grows, holes shrink), negative tapers inward, 0 = straight prism.
 *     Implemented with OCCT's draft-angle transform, so extreme angles
 *     that would break the topology fail cleanly (NULL + last_error).
 * NULL on failure.
 */
occt_shape *occt_extrude_profile(const double *xy, const int *loop_counts,
                                 int nloops, double height, double taper_deg);

/*
 * v3 — Extrude a multi-loop profile whose loops may contain TRUE ARCS, so a
 * circle becomes an exact cylindrical B-Rep face (no polygon facet edges).
 * `xyb` holds 3 doubles per vertex: x, y, and the DXF-style bulge of the
 * edge LEAVING that vertex toward the next (0 = straight line,
 * bulge = tan(sweep/4), positive = counter-clockwise). `loop_counts[l]` is
 * the number of VERTICES of loop l; loop 0 is the outer boundary, the rest
 * are holes. Winding is normalised here exactly like occt_extrude_profile
 * (signed area includes the circular-segment contributions of the bulges).
 * Height/taper semantics are identical to occt_extrude_profile; the taper
 * drafts curved lateral faces too. NULL on failure.
 */
occt_shape *occt_extrude_profile_arcs(const double *xyb,
                                      const int *loop_counts, int nloops,
                                      double height, double taper_deg);

/*
 * v2 — Rigid placement: returns a NEW shape = `shape` moved by the
 * row-major 3x4 matrix `mat34` = {r00 r01 r02 tx, r10 r11 r12 ty,
 * r20 r21 r22 tz}. The 3x3 part must be a pure rotation (orthonormal,
 * det +1); scale, shear and mirror are REFUSED (checked here rather than
 * left to gp_Trsf, which would accept rotation*scale and silently resize
 * the solid) — this is how a feature extruded in its sketch-local frame is
 * placed into part/world coordinates, so solids from different sketch
 * planes share one coordinate system (booleans, STEP). NULL on failure.
 */
occt_shape *occt_transform(const occt_shape *shape, const double *mat34);

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

/* ---- v2: Tessellation (display mesh) ------------------------------------ */

/*
 * Opaque triangulation of a shape, produced once and then read out through
 * the occt_mesh_* accessors below. Buffers live inside the mesh handle and
 * stay valid until occt_free_mesh. Layout:
 *   - vertices:  nvertices * 3 doubles (x,y,z). Vertices are per-face (not
 *                shared across B-Rep faces), so edges between faces stay
 *                crisp while curved faces shade smoothly.
 *   - normals:   nvertices * 3 doubles, unit length, OUTWARD facing.
 *   - triangles: ntriangles * 3 ints, 0-based indices into the vertex
 *                buffer, wound COUNTER-CLOCKWISE seen from outside.
 *   - edges:     the B-Rep edges as polylines for edge display: `starts`
 *                holds nedges+1 point offsets (starts[0] = 0, edge i spans
 *                points [starts[i], starts[i+1])), `pts` holds
 *                nedge_points * 3 doubles.
 */
typedef struct occt_mesh occt_mesh;

/* Triangulate `shape` with the given linear deflection (model units) and
 * angular deflection (radians). NULL on failure. */
occt_mesh *occt_mesh_create(const occt_shape *shape,
                            double lin_deflection, double ang_deflection);

/* Sizes of the mesh buffers. Any out-pointer may be NULL. Returns 1/0. */
int occt_mesh_counts(const occt_mesh *m, int *nvertices, int *ntriangles,
                     int *nedges, int *nedge_points);

/* Copy out the buffers described above. `out` must hold nvertices*3 /
 * ntriangles*3 / (nedges+1 and nedge_points*3) elements respectively.
 * Return 1/0. */
int occt_mesh_vertices(const occt_mesh *m, double *out);
int occt_mesh_normals(const occt_mesh *m, double *out);
int occt_mesh_triangles(const occt_mesh *m, int *out);
int occt_mesh_edges(const occt_mesh *m, int *starts, double *pts);

/* ---- v4: face identity + analytic display curves ------------------------ */

/* Number of triangulated faces in the mesh (their index space is shared by
 * occt_mesh_triangle_faces / occt_mesh_face_infos). -1 on NULL. */
int occt_mesh_face_count(const occt_mesh *m);

/* Per-triangle face index (ntriangles ints): which B-Rep face every display
 * triangle belongs to — hover highlighting and per-face silhouettes need
 * this. Returns 1/0. */
int occt_mesh_triangle_faces(const occt_mesh *m, int *out);

/* Per-face surface record, 15 doubles each:
 *   [0] type: 0 plane, 1 cylinder, 2 cone, 3 sphere, 4 torus, 5 other
 *   [1..3]  plane: point on plane   | cylinder/cone: axis point
 *   [4..6]  plane: OUTWARD normal (face orientation applied)
 *           cylinder/cone: axis direction
 *   [7..9]  x-direction of the surface frame (u = 0 reference)
 *   [10]    radius (cylinder/cone base), 0 otherwise
 *   [11,12] u parameter range of the face (angle for cylinder)
 *   [13,14] v parameter range of the face (along the axis for cylinder)
 * Returns 1/0. */
int occt_mesh_face_infos(const occt_mesh *m, double *out);

/* Per-edge analytic curve record, 16 doubles each, aligned with the edge
 * order of occt_mesh_edges:
 *   type 1 line:    [1, p0.xyz, p1.xyz, 0...]
 *   type 2 circle:  [2, center.xyz, xdir.xyz, ydir.xyz, radius, t0, t1, 0..]
 *   type 3 ellipse: [3, center.xyz, xdir.xyz, ydir.xyz, majR, minR, t0, t1]
 *   type 0 other:   render the polyline from occt_mesh_edges instead
 * point(t) = center + xdir*R*cos(t) + ydir*R*sin(t)  (ellipse: majR/minR).
 * Under any affine (orthographic) projection these stay lines/ellipses, so
 * the display can draw them as exact vector curves at every zoom.
 * Returns 1/0. */
int occt_mesh_edge_curves(const occt_mesh *m, double *out);

/* Release a mesh returned by occt_mesh_create. NULL is ignored. */
void occt_free_mesh(occt_mesh *m);

/* ---- Lifecycle --------------------------------------------------------- */

/* Release a shape returned by any constructor above. NULL is ignored. */
void occt_free_shape(occt_shape *shape);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* OCCT_CAPI_H */
