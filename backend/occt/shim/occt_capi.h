/*
 * Prototype — flat C-ABI shim over OpenCASCADE (OCCT).
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
 *   "Prototype OCCT shim v1 (OCCT 7.9.3)".
 * The literal prefix "Prototype OCCT shim" is what the CI link check greps
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

/* v5 — Boolean cut (difference a \ b): the material of `a` with the material
 * of `b` removed (Inventor's Cut). Inputs stay owned by the caller and remain
 * valid; the result is a NEW shape. NULL on failure (an empty result — b fully
 * swallows a — is reported as failure, not a null shape). */
occt_shape *occt_cut(const occt_shape *a, const occt_shape *b);

/* v5 — Boolean common (intersection a ∩ b): only the material shared by both
 * (Inventor's Intersect). Inputs stay owned by the caller and remain valid;
 * the result is a NEW shape. NULL on failure (disjoint inputs give an empty
 * result, reported as failure). */
occt_shape *occt_common(const occt_shape *a, const occt_shape *b);

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

/* ---- v12: revolve, edge identity, fillet/chamfer, ray casting ----------- */

/*
 * v12 — Revolve a multi-loop profile around an axis LYING IN the profile
 * plane (Inventor's Revolve). Profile encoding is identical to
 * occt_extrude_profile_arcs: `xyb` holds 3 doubles per vertex (x, y, bulge of
 * the edge leaving that vertex), `loop_counts[l]` the vertex count of loop l,
 * loop 0 the outer boundary and the rest holes.
 *
 * The axis is the 2D line through (ax_px, ax_py) with direction
 * (ax_dx, ax_dy) in the SAME z=0 sketch frame; it is lifted to
 * gp_Ax1((ax_px, ax_py, 0), (ax_dx, ax_dy, 0)). `angle_deg` is in (0, 360].
 *
 * Inventor requires the profile and the axis to be coplanar and the profile
 * NOT to cross the axis (a profile straddling the axis sweeps through itself).
 * That is enforced here on the loop VERTICES: every vertex must lie on one
 * side, touching allowed. A loop whose BULGE arcs cross the axis while its
 * vertices do not is not detected — OCCT then fails on its own and the error
 * comes back through occt_last_error().
 *
 * Holes are revolved separately and cut, exactly as in
 * occt_extrude_profile_arcs, because multi-wire faces are not trustworthy
 * here (see the long note at that function). NULL on failure.
 */
occt_shape *occt_revolve_profile(const double *xyb, const int *loop_counts,
                                 int nloops, double ax_px, double ax_py,
                                 double ax_dx, double ax_dy, double angle_deg);

/*
 * v12 — Number of TOPOLOGICAL edges of the shape, i.e. the extent of
 * TopExp::MapShapes(shape, TopAbs_EDGE). This index space (1-based, as OCCT
 * maps are) is what occt_fillet_edges / occt_chamfer_edges address.
 *
 * It is deliberately NOT the same as the mesh's DISPLAY edge list, which
 * drops degenerate, seam and tangent-continuous edges — use
 * occt_mesh_edge_ids to translate a picked display edge into an index here.
 * -1 on error.
 */
int occt_shape_edge_count(const occt_shape *shape);

/*
 * v12 — Identity record of topological edge `index` (1-based), 10 doubles:
 *   [0]    type: 1 line, 2 circle, 3 ellipse, 4 bspline/other curve, 0 unknown
 *   [1..3] midpoint (by arc length) in shape coordinates
 *   [4..6] unit tangent at the midpoint
 *   [7]    arc length
 *   [8]    radius (circle) / major radius (ellipse), 0 otherwise
 *   [9]    number of faces adjacent to this edge (2 = ordinary manifold edge;
 *          1 = free boundary, which cannot be filleted)
 *   [10]   v13: dihedral angle between the adjacent faces, in DEGREES
 *          (0 = tangent-continuous, 90 = square corner)
 *   [11]   v13: +1 CONVEX (exterior corner -> Inventor calls it a round),
 *          -1 CONCAVE (interior corner -> a fillet), 0 unknown/tangent
 * This is the fingerprint Dart persists so a fillet survives a rebuild: OCCT
 * indices are NOT stable across a recompute, midpoint+length+type is.
 * Returns 1/0.
 */
int occt_shape_edge_info(const occt_shape *shape, int index, double *out12);

/*
 * v12 — For every DISPLAY edge of the mesh (same order and count as
 * occt_mesh_edges), its 1-based topological index in the owning shape.
 * `out` must hold nedges ints. This is the bridge from "the user tapped this
 * drawn edge" to "fillet that B-Rep edge". Returns 1/0.
 */
int occt_mesh_edge_ids(const occt_mesh *m, int *out);

/*
 * v12 — Constant-radius edge fillet (Inventor's 3D Model > Modify > Fillet).
 * `edge_ids` holds n 1-based topological edge indices, `radii` the radius per
 * edge (each > 0); differing radii in ONE call are allowed and are what
 * Inventor calls multiple edge sets of a single fillet feature.
 *
 * v13: `radii2` is optional (may be NULL). Where radii2[i] > 0 the fillet
 * VARIES LINEARLY along that edge, from radii[i] at its start to radii2[i] at
 * its end — Inventor's variable-radius fillet with two control points. A zero
 * or absent radii2[i] means constant.
 *
 * Inputs stay owned by the caller; the result is a NEW shape. NULL on failure
 * — a radius too large for the adjacent faces is a clean failure with an OCCT
 * message, never a corrupt solid.
 */
occt_shape *occt_fillet_edges(const occt_shape *shape, const int *edge_ids,
                              const double *radii, const double *radii2, int n);

/*
 * v12 — Edge chamfer with Inventor's three methods, per edge:
 *   modes[i] == 0  equal distance      -> d1[i] on both faces
 *   modes[i] == 1  two distances       -> d1[i] on the reference face,
 *                                         d2[i] on the other
 *   modes[i] == 2  distance and angle  -> d1[i] on the reference face,
 *                                         angle_deg[i] measured from it
 * The reference face is the FIRST face adjacent to the edge in OCCT's
 * ancestor map — deterministic for a given shape, and what Dart's "Flip"
 * toggle swaps by exchanging d1/d2 (mode 1) or sending 90-angle (mode 2).
 * `d2` and `angle_deg` may be NULL when no edge uses the corresponding mode.
 * NULL on failure.
 */
occt_shape *occt_chamfer_edges(const occt_shape *shape, const int *edge_ids,
                               const int *modes, const double *d1,
                               const double *d2, const double *angle_deg,
                               int n);

/*
 * v12 — Cast a ray and report where it enters/leaves the solid: the sorted,
 * de-duplicated distances from the origin along the UNIT direction at which
 * the ray crosses a face of `shape`. Writes at most `max_hits` values into
 * `out` and returns how many were written (0 = miss, -1 = error).
 *
 * This is what Inventor's "To Next" termination needs: extrude from the
 * sketch plane, and the first hit strictly beyond the start is the next face
 * the feature should stop on. "To" on a curved face uses it too, since a
 * cylinder has no single termination plane to intersect analytically.
 */
int occt_ray_hits(const occt_shape *shape, double ox, double oy, double oz,
                  double dx, double dy, double dz, double *out, int max_hits);

/*
 * v13 — the ANGLES at which a point's circular path around an axis crosses a
 * face of `shape`: sorted, de-duplicated, in DEGREES in (0, 360), measured
 * from the point itself. Returns how many were written (0 = never crosses,
 * -1 = error).
 *
 * This is the rotational twin of occt_ray_hits, and what a revolve needs for
 * "To Next": a revolved profile does not travel in a straight line, so no ray
 * cast can say where it first meets material. The axis is the 3D line through
 * (ax_px, ax_py, ax_pz) along (ax_dx, ax_dy, ax_dz); the moving point is
 * (px, py, pz). A point ON the axis has no path and returns 0.
 */
int occt_revolve_hits(const occt_shape *shape, double ax_px, double ax_py,
                      double ax_pz, double ax_dx, double ax_dy, double ax_dz,
                      double px, double py, double pz, double *out,
                      int max_hits);

/*
 * v13 — as occt_revolve_hits, but crossings of ONE face only: the face of
 * `shape` nearest to (fx, fy, fz).
 *
 * This is what a revolve's "To <face>" needs. The whole-shape version reports
 * the first material the sweep meets, which is a different question — a
 * profile can pass through two other faces before reaching the one that was
 * picked. Intersecting a single face answers the picked-face question
 * directly, and OCCT allows it because a TopoDS_Face is a TopoDS_Shape.
 */
int occt_revolve_hits_face(const occt_shape *shape, double ax_px, double ax_py,
                           double ax_pz, double ax_dx, double ax_dy,
                           double ax_dz, double px, double py, double pz,
                           double fx, double fy, double fz, double *out,
                           int max_hits);

/* ---- v15: sweep, loft, coil ---------------------------------------------- */

/*
 * v15 — Sweep a profile along a PATH (Inventor's Sweep).
 *
 * The profile is encoded exactly as occt_extrude_profile_arcs (x, y, bulge per
 * vertex, loop 0 outer, the rest holes) in its own z=0 sketch frame, and
 * `mat34` places that frame in the world. The path arrives as a world-space
 * 3D polyline (`path_pts`, 3 doubles per point, `npath` points): the caller
 * has already sampled whatever sketch curve the user picked, so the shim does
 * not need to know about sketches.
 *
 * `orientation` follows Inventor's three buttons:
 *   0 = Follow Path — the section stays perpendicular to the path (Frenet).
 *   1 = Fixed       — the section keeps its original orientation.
 *   2 = Follow Path and Guide — as 0, corrected against the path's own frame.
 *
 * `taper_deg` widens or narrows the section along the path (a linear scaling
 * law); 0 keeps it constant. `twist_deg` is accepted but NOT implemented and
 * a non-zero value is REFUSED rather than silently ignored — a swept solid
 * that quietly failed to twist is a wrong part, not a cosmetic miss.
 *
 * NULL on failure.
 */
occt_shape *occt_sweep_profile(const double *xyb, const int *loop_counts,
                               int nloops, const double *mat34,
                               const double *path_pts, int npath,
                               int orientation, double taper_deg,
                               double twist_deg);

/*
 * v15 — Loft through a series of SECTIONS (Inventor's Loft).
 *
 * `xyb` holds every section's vertices back to back; `loop_counts[i]` is the
 * vertex count of section i; `mats` holds 12 doubles per section placing that
 * section's z=0 frame in the world. One closed loop per section — the common
 * case, and what the panel offers.
 *
 * `solid` closes the ends (Inventor's Output: Solid rather than Surface).
 * `ruled` makes straight transitions between sections instead of a smooth
 * spline (Inventor's Transition tab). `closed` loops the last section back to
 * the first (Closed Loop).
 *
 * NULL on failure — notably when two sections are not compatible, which OCCT
 * detects and which is a real modelling error rather than something to paper
 * over.
 */
occt_shape *occt_loft_sections(const double *xyb, const int *loop_counts,
                               const double *mats, int nsections, int solid,
                               int ruled, int closed);

/*
 * v15 — Coil / helical sweep (Inventor's Coil).
 *
 * Profile and `mat34` as for the sweep. The axis is the world-space line
 * through (ax_p*) along (ax_d*); Inventor requires it NOT to pass through the
 * profile, and the helix radius is the distance from the axis to the profile's
 * centroid.
 *
 * `revolutions` and `height` give Inventor's "Revolution and Height" method;
 * the panel's other methods (Pitch and Revolution, Pitch and Height, Spiral)
 * are all expressible as a revolutions/height pair, so the conversion lives in
 * Dart and the shim takes only the resolved pair.
 *
 * `taper_deg` tapers the coil (a linear scaling law along the helix).
 * `clockwise` picks the handedness. `close_start` / `close_end` are accepted
 * for signature stability but are NOT implemented and a non-zero value is
 * REFUSED — a flat-ended coil where the user asked for a closed one is a
 * different part.
 *
 * NULL on failure.
 */
occt_shape *occt_coil_profile(const double *xyb, const int *loop_counts,
                              int nloops, const double *mat34, double ax_px,
                              double ax_py, double ax_pz, double ax_dx,
                              double ax_dy, double ax_dz, double revolutions,
                              double height, double taper_deg, int clockwise,
                              int close_start, int close_end);

/* ---- Lifecycle --------------------------------------------------------- */

/* Release a shape returned by any constructor above. NULL is ignored. */
/* M110 — explodes a shape into its SOLIDS (see the .cpp for why: an imported
 * assembly should become several BODIES, not one opaque compound). Fills at
 * most [max] entries, returns the count. The caller owns the results.
 */
int occt_split_solids(const occt_shape *shape, occt_shape **out, int max);

void occt_free_shape(occt_shape *shape);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* OCCT_CAPI_H */
