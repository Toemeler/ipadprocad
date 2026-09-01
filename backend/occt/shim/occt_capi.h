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
 * swallows a — is reported as failure, not a null shape).
 *
 * v29 — a cut that removes NOTHING is retried once at a fuzzy tolerance, and
 * the retry is kept only if it removes something no larger than the tool. That
 * is what makes a tool TANGENT to a face of `a` — a counterbore against a bore
 * — actually cut, where before it could return the plugs still embedded in the
 * result and so a shape weighing exactly what `a` did. A tool that genuinely
 * misses `a` still returns `a`'s material unchanged, as it always has. */
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

/*
 * v17 — MIRROR a shape about a plane. `plane6` = {px, py, pz, nx, ny, nz}:
 * a point on the plane plus its normal (normalised here; a zero-length
 * normal is refused).
 *
 * Separate from occt_transform because a reflection has determinant -1, and
 * occt_transform refuses that deliberately: a non-rigid matrix arriving there
 * is far more likely to be a caller bug (a scale, a shear, a frame built the
 * wrong way round) than an intended mirror. Asking for a mirror BY NAME
 * cannot be that mistake.
 *
 * The result is orientation-correct: a reflection turns a solid inside out,
 * and OCCT booleans read orientation, so an uncorrected mirrored tool would
 * cut where it should join. The shim measures the volume and reverses the
 * shape if it came back negative. NULL on failure.
 */
occt_shape *occt_mirror(const occt_shape *shape, const double *plane6);

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

/* Write the shape to a STEP (AP214IS, AsIs, millimetres) file at `path`.
 * Returns 1/0. Exactly occt_export_step_named with one unnamed body. */
int occt_export_step(const occt_shape *shape, const char *path);

/*
 * v17 (M214) — write `n` bodies to one STEP file as `n` NAMED products.
 *
 * This is the entry point a part export should use. Each shape becomes its
 * own STEP product carrying `names[i]`, so a part with three bodies opens in
 * the receiving CAD as three named bodies rather than one anonymous lump.
 *
 * Callers must NOT pre-fuse the bodies to get a single shape: a boolean union
 * is slow, can fail outright, and erases the body identity this preserves.
 *
 * `names` may be NULL (all bodies fall back to `product`), and any individual
 * entry may be NULL or empty. `product` names the document in the FILE_NAME
 * header; NULL/empty falls back to a generic name.
 *
 * Units are millimetres and the schema is AP214IS, both pinned explicitly on
 * every call — Interface_Static is process-global, so a STEP file READ earlier
 * in the session could otherwise decide what units this one is written in.
 *
 * Returns 1 on success, 0 on failure (occt_last_error names the body that
 * could not be transferred). Nothing is written on failure.
 */
int occt_export_step_named(const occt_shape **shapes, const char **names,
                           int n,
                           const char *path, const char *product);

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
 *   [1..3]  plane:            point on plane
 *           cylinder/cone:    axis point
 *           sphere/torus:     CENTRE
 *   [4..6]  plane:            OUTWARD normal (face orientation applied)
 *           everything else:  axis direction
 *   [7..9]  x-direction of the surface frame (u = 0 reference)
 *   [10]    radius: cylinder radius, cone reference radius, sphere radius,
 *           torus MAJOR radius; 0 for a plane
 *   [11,12] u parameter range of the face (angle for cylinder)
 *   [13,14] v parameter range of the face (along the axis for cylinder)
 *
 * v18 (M215) — cone, sphere and torus used to fill [0] only and leave the
 * rest zero. Work features read the centre and axis of exactly those three
 * (Through Revolved Face, Center Point of Sphere / Torus), and zeros would
 * have put every one of them at the world origin without an error. The
 * change is additive: [0] still discriminates and every earlier reader
 * switches on it first.
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

/* v20 (M217) — 1-based TOPOLOGICAL face index per MESH face (nfaces ints).
 * Exactly the problem occt_mesh_edge_ids solves for edges: occt_mesh_create
 * skips a face it cannot triangulate, so mesh face i and topological face i
 * are different numbers as soon as one face fails to mesh. Picking yields the
 * mesh index; occt_delete_faces and occt_move_faces name the topological one.
 * Returns 1/0. */
int occt_mesh_face_ids(const occt_mesh *m, int *out);

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
 *          v22: decided locally, from the two into-face directions, instead
 *          of by stepping off the edge and asking a solid classifier. The
 *          set of edges that get a nonzero sign is unchanged; the SIGN
 *          changes on shapes with a feature thinner than
 *          ‖bbox diagonal‖/1414, where the old answer was wrong. See
 *          convexity_sign in the .cpp.
 * This is the fingerprint Dart persists so a fillet survives a rebuild: OCCT
 * indices are NOT stable across a recompute, midpoint+length+type is.
 * NOTE that [11] is not part of that fingerprint and never has been — Dart
 * stores midpoint, length, type and radius (part_model.dart EdgeSel) — so a
 * change to [11] cannot move which edge a blend reattaches to.
 * Returns 1/0.
 */
int occt_shape_edge_info(const occt_shape *shape, int index, double *out12);

/*
 * v21 — the record of EVERY topological edge, in ONE traversal of the shape.
 *
 * Same twelve doubles per edge, same order, same meaning as
 * occt_shape_edge_info; record i (0-based) describes edge i+1, so
 * out12n[12*i + f] is field f of edge i+1. `cap` is the number of RECORDS the
 * buffer holds — pass occt_shape_edge_count(shape); a buffer smaller than the
 * edge count is refused rather than partially filled. Returns the number of
 * records written, or -1 on failure.
 *
 * WHY THIS EXISTS, and it is not stylistic. occt_shape_edge_info derives four
 * things from the WHOLE shape — the edge map, the edge->face ancestor map, the
 * bounding box, and a solid classifier — and discards all four when it
 * returns. Calling it once per edge is therefore n x Θ(n).
 * PERFORMANCE_PROFILE.md §6.5 measures that on a device as k = 2.012
 * [1.910, 2.113], R² = 1.0000, against a control performing strictly more work
 * at k = 1.063: a ratio of 200.3x at 1440 edges, ten seconds for one
 * enumeration, and an extrapolated 56.4 s on the part that failed in the
 * field. This entry point builds those four once and answers every edge from
 * them.
 *
 * The per-edge computation is literally the same code (see edge_info_ctx in
 * the .cpp), so the two paths agree bit for bit; smoke scenario [35] pins
 * that on four solids across all twelve fields.
 *
 * One departure from the single-edge contract, and it is deliberate: an edge
 * the kernel cannot read does not abandon the enumeration. It comes back with
 * type -1 — outside the documented 0..4 range — and callers drop it. That
 * reproduces exactly what a Dart-side loop over occt_shape_edge_info did with
 * a failing edge. Type 0 remains "degenerate edge, legitimately empty" and is
 * still a valid record.
 */
int occt_shape_edges_info(const occt_shape *shape, double *out12n, int cap);

/*
 * v22 — TEST ONLY, and application code must not call it.
 *
 * occt_shape_edges_info with field 11 (convexity) decided the way v21 and
 * earlier decided it: step ‖bbox diagonal‖/1000 from the edge midpoint along
 * the bisector of the two into-face directions and ask
 * BRepClass3d_SolidClassifier whether the point is inside the solid. Every
 * other field is computed by the same code as the shipping path, so a
 * difference in fields 0..10 between the two is a defect by construction.
 *
 * It exists for one reason: smoke scenario [36] compares the shipping path
 * against it **in the same run on the same machine**, which is what proves
 * the two agree; a golden recorded from one machine would pin that machine's
 * digits and prove nothing (OPTIMIZATION_PLAN_2.md §1.4, and the four red
 * tests of build 437 that taught it).
 *
 * DO NOT SHIP CALLS TO THIS. On a shape carrying a feature thinner than
 * ‖bbox diagonal‖/1414 — a rib, a seal groove, sheet metal — the probe steps
 * clean through the material and the sign comes back inverted. A 200 x 0.1 x
 * 20 box, which is convex, comes back with eight of its twelve edges marked
 * concave. That is why v22 stopped using it.
 */
int occt_shape_edges_info_ref(const occt_shape *shape, double *out12n,
                              int cap);

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
 *
 * v28 (S17) — mode 2's admissible range is THE EDGE'S, not a literal 90:
 *
 *     0 < angle_deg[i] < 180 - theta
 *
 * where theta is the edge's interior dihedral. That bound is the angle between
 * the edge's two OUTWARD normals, i.e. exactly `occt_shape_edge_info` field
 * [10], so a caller can compute what will be accepted before asking. It equals
 * the pre-v28 90 if and only if the edge is perpendicular, which every fixture
 * in this repo happened to be. Past the bound OCCT's own second distance,
 * d1.sin(alpha)/sin(alpha+theta), diverges and then goes negative.
 *
 * So since v28 an acute edge accepts angles the shim used to refuse (a
 * 60-degree edge reaches 120), and an obtuse edge refuses angles it used to
 * pass to OCCT (a 135-degree edge stops at 45, where OCCT was previously being
 * handed a negative distance and failing on its own). An edge whose bound
 * cannot be measured — not exactly two faces, or normals that will not
 * evaluate — keeps the 90 rule.
 *
 * KNOWN, NOT FIXED HERE: Dart's "Flip" sends 90-angle for mode 2, which is the
 * same hardcoded perpendicular assumption one layer up (the flipped angle is
 * 180-theta-angle). On a non-perpendicular edge that now produces a clear
 * refusal from this guard instead of a wrong chamfer or an OCCT failure.
 * part_model.dart is not this session's to change; see
 * perf/findings/S17-oblique.md section 5.1.
 */
occt_shape *occt_chamfer_edges(const occt_shape *shape, const int *edge_ids,
                               const int *modes, const double *d1,
                               const double *d2, const double *angle_deg,
                               int n);

/*
 * v16 — the same two operations, with the two things the plain forms cannot
 * say. Both are what the plain forms now call internally, so the guarantees
 * below hold for every caller; only the REPORTING is extra here.
 *
 * Guarantees:
 *  - the returned shape has been through BRepCheck_Analyzer. BRepFilletAPI
 *    reports IsDone() and still hands back solids with invalid faces; those
 *    are refused rather than passed on to the mesher.
 *  - a size that lands exactly on a tangency (a 2 mm fillet on a 2 mm wall)
 *    is retried a hair smaller instead of failing. OCCT has never been able
 *    to build those; see the note on the retry ladder in the .c file.
 *  - one impossible edge no longer kills the whole set. The edges that CAN
 *    be blended are, and the rest are reported.
 *
 * out_dropped (optional): n ints, 1 where that input edge got no blend.
 * out_scale   (optional): the relative size actually built — 1.0 when the
 *             asked-for size worked, a hair under when a tangency retry was
 *             needed. Never below 0.999.
 */
occt_shape *occt_fillet_edges_ex(const occt_shape *shape, const int *edge_ids,
                                 const double *radii, const double *radii2,
                                 int n, int *out_dropped, double *out_scale);

occt_shape *occt_chamfer_edges_ex(const occt_shape *shape, const int *edge_ids,
                                  const int *modes, const double *d1,
                                  const double *d2, const double *angle_deg,
                                  int n, int *out_dropped, double *out_scale);

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
 * v25 — orientation 1 was BROKEN on any path that bends, and had been since
 * v15: it selected OCCT's constant-binormal law rather than its fixed-trihedron
 * one, and the constant-binormal law replaces the sweep frame's tangent with a
 * projection of the real one. A 10x10 square on a 16-span arc came out at
 * 16 429 where the analytic answer is 6 000, and failed BRepCheck_Analyzer.
 * Straight single-segment paths were and remain exact. Test for >= 25 if you
 * need orientation 1 to be trustworthy on a bending path.
 *
 * `taper_deg` widens or narrows the section along the path (a linear scaling
 * law); 0 keeps it constant. `twist_deg` is accepted but NOT implemented and
 * a non-zero value is REFUSED rather than silently ignored — a swept solid
 * that quietly failed to twist is a wrong part, not a cosmetic miss.
 *
 * v24 — what happens to that "3D polyline" changed. See occt_sweep_profile_ex
 * below: this entry point is now OCCT_SWEEP_PATH_AUTO, and for a path that
 * came from the caller's own curve sampler it produces a DIFFERENT (smoother,
 * far smaller, and buildable) solid than v23 did.
 *
 * NULL on failure.
 */
occt_shape *occt_sweep_profile(const double *xyb, const int *loop_counts,
                               int nloops, const double *mat34,
                               const double *path_pts, int npath,
                               int orientation, double taper_deg,
                               double twist_deg);

/* ---- v24: how a sampled path becomes a spine ----------------------------- */

/*
 * The path arrives as a polyline whatever the user drew, because
 * `sketchCurve` flattens arcs, circles and splines before the shim is called
 * (`sampleEntity(g, arcSamples: 64)` — 64 spans for EVERY arc, whatever its
 * angle). Every joint of that polyline was then mitered, because the sweep
 * sets BRepBuilderAPI_RightCorner, and inside OCCT a miter is a full
 * BOPAlgo_PaveFiller between the two adjacent shells — one face per profile
 * segment each. It is a boolean per joint over the whole profile.
 *
 * Measured (perf/findings/S14-sweep.md): that is 96.6 % of the call and turns
 * a linear sweep into a cubic one. It made a 1200-segment ring on a 16-span
 * sampled arc FAIL after 231 s on the device, and it makes a 64-segment ring
 * on a 64-span sampled arc — which is what any arc path produces — corrupt the
 * heap and abort the process.
 *
 * So v24 distinguishes joints the user DREW from joints the sampler MADE:
 *
 *   AUTO   — the default, and what occt_sweep_profile now does. Runs of points
 *            whose interior joints are all <= 360/64 = 5.625 deg (the largest
 *            joint the app's own sampler can emit) become one C2 B-spline
 *            edge interpolated THROUGH every point; a joint above that stays a
 *            vertex and is still mitered exactly as before.
 *   POLY   — v23 behaviour, bit for bit: one straight edge per pair of points.
 *            Kept so old and new can be compared in ONE run on ONE machine
 *            (smoke scenario [37]), and as the escape hatch if the integrator
 *            wants the old shape back.
 *   SMOOTH — one interpolated curve through the whole path regardless of its
 *            joints, for a caller that KNOWS its path is a sampled curve.
 *
 * A path of two points is one straight edge in every mode. AND AUTO DOES NOT
 * SMOOTH A PROFILE WITH HOLES: finish_pipe cuts each hole out of the body with
 * a boolean, and between two solids made of general swept surfaces that
 * boolean costs about 80x what it costs between two solids made of planes
 * (measured: 21 653 ms against a 258 ms whole operation). A holed profile
 * therefore keeps the v23 spine — and keeps v23's failure at large segment
 * counts. SMOOTH is not restricted: it is an explicit request.
 *
 * BEHAVIOUR CHANGE, and the integrator's call, not the shim's: an AUTO sweep
 * along a sampled arc has a different FACE COUNT and different topology from
 * the v23 one (segments + 2 instead of segments x spans + 2), the same volume,
 * and about 4.4 % of its volume in a different place. Anything that reattaches
 * a downstream feature to a face or edge of a sweep by index or fingerprint
 * may therefore reattach differently on an existing part.
 */
#define OCCT_SWEEP_PATH_AUTO 0
#define OCCT_SWEEP_PATH_POLY 1
#define OCCT_SWEEP_PATH_SMOOTH 2

occt_shape *occt_sweep_profile_ex(const double *xyb, const int *loop_counts,
                                  int nloops, const double *mat34,
                                  const double *path_pts, int npath,
                                  int orientation, double taper_deg,
                                  double twist_deg, int path_mode);

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

/* ---- v20 (M217): Delete Face and Direct Edit ---------------------------- */

/*
 * Inventor's Delete Face with Heal: removes the `n` TOPOLOGICAL faces named by
 * `ids` (1-based, occt_mesh_face_ids space) and closes the wound by extending
 * their neighbours until they intersect — deleting a fillet gives back the
 * sharp corner, deleting a hole's cylindrical face fills the hole.
 *
 * `heal` must be non-zero. Inventor's un-healed variant turns the part into a
 * SURFACE body; this app has no surface bodies, so that mode is REFUSED with
 * an explanation rather than returning an open shell every caller would
 * mishandle. NULL on failure.
 */
occt_shape *occt_delete_faces(const occt_shape *shape, const int *ids, int n,
                              int heal);

/*
 * Inventor's Direct > Move / Size on faces: slides the `n` faces named by
 * `ids` by the vector (dx,dy,dz).
 *
 * Implemented by sweeping each face along the delta and fusing or cutting the
 * swept volume — fuse when the delta runs along that face's OUTWARD normal,
 * cut when it runs against it, decided per face so a mixed selection still
 * does the right thing on each. Faces moved parallel to themselves are
 * skipped (they change nothing).
 *
 * v28 (S17): each face is swept along the component of the delta ALONG ITS OWN
 * NORMAL, not along the whole delta. The neighbouring walls stay where they
 * are, so a planar face's new outline is still the intersection of its moved
 * plane with those walls, and the tangential part of the delta is carried onto
 * the face's own plane — unobservable, exactly as the skip above already says
 * for a wholly tangential delta. Two consequences worth testing for:
 *
 *   1. an OBLIQUE delta now returns the same solid as its normal component
 *      alone. Before v28 it swept a LEANING prism, whose union with the body
 *      carried an unsupported overhang on one side and a re-entrant notch on
 *      the other; a 20-cube's top face moved by (5,0,5) kept material out to
 *      x = 25, and the volume was 10 000 either way, so nothing in the suite
 *      could see it;
 *   2. the result is continuous in the delta. Before v28, moving that face by
 *      (5,0,0) changed nothing while (5,0,0.001) grew a 5 mm overhang.
 *
 * So it is now exact for every delta on a PLANAR face, which is what the
 * pre-v28 "exact whenever the neighbouring walls are parallel to the motion"
 * was scoping around. On a CURVED face the outward normal is sampled at the
 * mid-parameter point and prism-and-fuse remains an approximation of unstated
 * quality — that case was never right and v28 does not make it so.
 *
 * NOT this operation: moving a face and letting its neighbouring WALLS tilt to
 * follow it. That slides surfaces the caller did not select; it is the same
 * class of work as Direct > Rotate, which this app deliberately does not ship
 * (see DirectEditFeature in part_model.dart). NULL on failure.
 */
occt_shape *occt_move_faces(const occt_shape *shape, const int *ids, int n,
                            double dx, double dy, double dz);

/*
 * Inventor's Direct > Scale: uniform scale of the whole body about (cx,cy,cz)
 * by `factor` (> 0). Its own entry point because occt_transform deliberately
 * REFUSES a non-rigid matrix — placing a feature must never resize it, while
 * scaling is a command in its own right. NULL on failure.
 */
occt_shape *occt_scale_shape(const occt_shape *shape, double cx, double cy,
                             double cz, double factor);

/* ---- Lifecycle --------------------------------------------------------- */

/* Release a shape returned by any constructor above. NULL is ignored. */
/* M110 — explodes a shape into its SOLIDS (see the .cpp for why: an imported
 * assembly should become several BODIES, not one opaque compound). Fills at
 * most [max] entries, returns the count. The caller owns the results.
 */
int occt_split_solids(const occt_shape *shape, occt_shape **out, int max);

void occt_free_shape(occt_shape *shape);

/* ---- v21 (M232): mesh -> B-Rep -------------------------------------- */

/*
 * Reconstructs a B-Rep SOLID from a triangle mesh — the kernel half of Open
 * for an STL, OBJ or 3MF. The file itself is parsed in Dart
 * (frontend/lib/mesh_io.dart); what arrives here is a plain indexed mesh in
 * millimetres, because parsing is I/O and this is geometry.
 *
 * `xyz` holds nv*3 coordinates, `tri` holds nt*3 zero-based vertex indices.
 * Winding is taken as the file gave it: a mesh that is inside-out, unwelded,
 * or inconsistently wound is repaired internally rather than refused, which
 * is the normal condition of anything downloaded.
 *
 * mode 0 — FACETED. One planar face per triangle, then coplanar faces merged.
 *          Fast, exact to the mesh, and of very limited use afterwards: a
 *          cylinder stays a hundred flat strips, so it cannot be filleted and
 *          it exports as a hundred faces.
 * mode 1 — SURFACES (recommended). Segments the mesh, fits planes, cylinders,
 *          cones, spheres and tori to the pieces, makes the surfaces agree
 *          with each other, and builds real trimmed faces whose edges are the
 *          exact intersection curves. A drilled hole comes back a cylinder
 *          with a circular rim, so a fillet has a circle to roll along.
 *
 * Tuning — pass <= 0 for the built-in default, which is what callers should
 * normally do:
 *   tol_frac   surface fit tolerance as a FRACTION of the bounding-box
 *              diagonal (default 0.002). Relative because one absolute
 *              tolerance cannot serve a 200 mm bracket and a 4 mm pin.
 *   sharp_deg  dihedral angle past which an edge is a feature boundary
 *              (default 22).
 *   max_faceted  refuse to emit more than this many face-per-triangle faces
 *              (default 120000). A half-million-face B-Rep is not a CAD model.
 *
 * `report_ints` (OCCT_MESH_REPORT_INTS entries) and `report_reals`
 * (OCCT_MESH_REPORT_REALS entries) receive what happened; either may be NULL.
 * They are filled in even on failure, because "it fitted four thousand faceted
 * patches" is the explanation for a bad result and the caller is entitled to
 * it. Field order is given by the OCCT_MR_* indices below.
 *
 * Returns NULL on failure with occt_last_error() set. The result is a SOLID
 * when the mesh closed, otherwise a shell or a compound — never null-but-
 * successful.
 */
occt_shape *occt_brep_from_mesh(const double *xyz, int nv,
                                const int *tri, int nt,
                                int mode, double tol_frac, double sharp_deg,
                                int max_faceted,
                                int *report_ints, double *report_reals);

/* ---- what the converter is doing, while it is doing it ----------------
 *
 * M333. occt_brep_from_mesh blocks its caller for as long as it runs — a
 * second on a small model, half a minute on a big one — so nothing on the
 * calling thread can report progress. These are for a DIFFERENT thread: the
 * one drawing the wait indicator, which is idle throughout.
 *
 * Safe to call at any time from any thread, including while a conversion is
 * running and when none is. Never blocks and never allocates.
 *
 * `stage` is one of OCCT_MS_*; `done` and `total` describe position within it.
 * A `total` of 0 means the stage has nothing meaningful to count, and the
 * caller should show an indeterminate indicator rather than invent a fraction.
 * Any out-pointer may be NULL. */
void occt_mesh_progress(int *stage, int *done, int *total);

/* A short English name for a stage, for a caller with no catalogue of its
 * own. Never NULL; "" for OCCT_MS_IDLE. The storage is static. */
const char *occt_mesh_stage_name(int stage);

/* ---- one bar for the whole conversion, and a way out of it -------------
 *
 * M335. `permille` is where the bar is over the WHOLE conversion, 0..1000,
 * and it never goes backwards. `ceiling` is the furthest the current stage
 * could take it: for a stage that can count itself the two move together, and
 * for one that cannot — merging coplanar faces is a third of a 1:1 conversion
 * and OCCT offers no way in — `permille` sits at the bottom of the stage's
 * span and `ceiling` is the top. Ease between them on elapsed time, and never
 * past the ceiling: the estimate then lives in the drawing, where being wrong
 * costs a bar that moves at the wrong speed, instead of in the measurement,
 * where it would be a lie about the work. Both are 0 when nothing is running.
 * Either out-pointer may be NULL. */
void occt_mesh_overall(int *permille, int *ceiling);

/* Asks a running conversion to stop. Safe from any thread, and when none is
 * running. The conversion abandons its work at the next point where that is
 * cheap and safe and returns no shape, with the error text
 * OCCT_MESH_CANCELLED, so a caller can tell a cancellation from a failure.
 *
 * How soon, measured on an 83k-triangle model: within 5 ms while fitting
 * surfaces, 127 ms while building a 1:1 body — and up to four seconds if it
 * lands inside ShapeUpgrade_UnifySameDomain, which OCCT gives no way to
 * interrupt. The request is consumed by the run it stops and can never cancel
 * the next one. */
void occt_mesh_cancel(void);

/* The exact error text a cancelled conversion reports. */
#define OCCT_MESH_CANCELLED "cancelled"

#define OCCT_MS_IDLE        0
#define OCCT_MS_WELDING     1
#define OCCT_MS_SEGMENTING  2
#define OCCT_MS_FITTING     3
#define OCCT_MS_FREEFORM    4
#define OCCT_MS_BUILDING    5
#define OCCT_MS_SEWING      6
#define OCCT_MS_FACETED     7
#define OCCT_MS_MERGING     8

#define OCCT_MESH_REPORT_INTS 22
#define OCCT_MESH_REPORT_REALS 2

/* Indices into `report_ints`. */
#define OCCT_MR_TRIANGLES_IN       0
#define OCCT_MR_VERTICES_IN        1
#define OCCT_MR_TRIANGLES_USED     2   /* after welding, minus degenerates */
#define OCCT_MR_VERTICES_WELDED    3
#define OCCT_MR_NON_MANIFOLD_EDGES 4
#define OCCT_MR_BOUNDARY_EDGES     5   /* holes in the mesh; >0 cannot close */
#define OCCT_MR_FLIPPED_TRIANGLES  6
#define OCCT_MR_PATCHES            7
#define OCCT_MR_PLANES             8
#define OCCT_MR_CYLINDERS          9
#define OCCT_MR_CONES              10
#define OCCT_MR_SPHERES            11
#define OCCT_MR_TORI               12
#define OCCT_MR_FREEFORM           13
#define OCCT_MR_FACETED_PATCHES    14  /* fell back to one face per triangle */
#define OCCT_MR_FACES_BUILT        15
#define OCCT_MR_FACES_FAILED       16
#define OCCT_MR_ANALYTIC_EDGES     17  /* exact surface-intersection curves */
#define OCCT_MR_APPROXIMATED_EDGES 18
#define OCCT_MR_SHELLS             19
#define OCCT_MR_SOLIDS             20
#define OCCT_MR_CLOSED             21  /* 1 when the result is a closed solid */

/* Indices into `report_reals`. */
#define OCCT_MR_FIT_RMS  0   /* area-weighted, in model units */
#define OCCT_MR_DIAGONAL 1   /* bounding-box diagonal of the input mesh */

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* OCCT_CAPI_H */
