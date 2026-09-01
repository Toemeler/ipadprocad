/*
 * Prototype — flat C-ABI shim over OpenCASCADE (OCCT). See occt_capi.h.
 *
 * Implementation rules:
 *   - Nothing OCCT-ish crosses the ABI: occt_shape wraps a TopoDS_Shape.
 *   - Every entry point is wrapped in try/catch (Standard_Failure and ...);
 *     OCCT throws liberally (e.g. on degenerate input) and an exception
 *     escaping into Dart FFI would abort the app.
 *   - No global OCCT initialisation is required for this surface: the STEP
 *     controller registers itself lazily in the STEPControl_Reader/Writer
 *     constructors, which is reference-driven and therefore safe with static
 *     archives (unlike Qt's generated registration objects — see HANDOFF M5).
 */
#include "occt_capi.h"
#include "mesh_recon.h"

#include <OSD.hxx>

#include <cmath>
#include <cstdio>
#include <cstring>
#include <memory>
#include <unordered_map>
#include <vector>

#include <Standard_Failure.hxx>
#include <Standard_Version.hxx>

#include <gp.hxx>
#include <gp_Ax2.hxx>
#include <gp_Dir.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>
#include <gp_Circ.hxx>
#include <gp_Elips.hxx>
#include <gp_Cylinder.hxx>
#include <gp_Cone.hxx>
#include <gp_Sphere.hxx>
#include <gp_Torus.hxx>

#include <TopoDS_Shape.hxx>
#include <TopoDS_Wire.hxx>
#include <TopoDS_Face.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopExp.hxx>
#include <TopTools_IndexedMapOfShape.hxx>

#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <BRepPrimAPI_MakeCylinder.hxx>
#include <BRepPrimAPI_MakePrism.hxx>
#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepAlgoAPI_Cut.hxx>
#include <BRepAlgoAPI_Common.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepGProp.hxx>
#include <BRepLib.hxx>
#include <BRepBuilderAPI_TransitionMode.hxx>
#include <GProp_GProps.hxx>
#include <Bnd_Box.hxx>
#include <BRepBndLib.hxx>

/* v2: taper (draft), tessellation, edge discretisation */
#include <TopoDS.hxx>
#include <TopExp_Explorer.hxx>
#include <TopLoc_Location.hxx>
#include <gp_Pln.hxx>
#include <gp_Ax3.hxx>
#include <gp_Trsf.hxx>
#include <BRepOffsetAPI_DraftAngle.hxx>
#include <BRepBuilderAPI_Transform.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepLProp_SLProps.hxx>
#include <Geom2d_Curve.hxx>
#include <gp_Pnt2d.hxx>
#include <BRepAdaptor_Curve.hxx>
#include <GeomAbs_SurfaceType.hxx>
#include <GeomAbs_CurveType.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRep_Tool.hxx>
#include <Poly_Triangulation.hxx>
#include <BRepLib_ToolTriangulatedShape.hxx>
#include <GCPnts_TangentialDeflection.hxx>

/* v3: true-arc profile wires, seam-edge suppression */
#include <GC_MakeArcOfCircle.hxx>
#include <Geom_TrimmedCurve.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_ListOfShape.hxx>
#include <TopTools_ListIteratorOfListOfShape.hxx>
#include <ShapeUpgrade_UnifySameDomain.hxx>

/* v12: revolve, fillet/chamfer, ray casting, edge identity */
#include <gp_Ax1.hxx>
#include <gp_Lin.hxx>
#include <BRepPrimAPI_MakeRevol.hxx>
#include <BRepFilletAPI_MakeFillet.hxx>
#include <BRepFilletAPI_MakeChamfer.hxx>
/* v16 — the blend retry ladder needs the alternative circle representations
 * and the per-contour failure status. */
#include <ChFi3d_FilletShape.hxx>
#include <ChFiDS_ErrorStatus.hxx>
#include <vector>
#include <BRepIntCurveSurface_Inter.hxx>
#include <BRepClass3d_SolidClassifier.hxx>
#include <Geom_Circle.hxx>
/* v15: sweep, loft, coil */
#include <BRepOffsetAPI_MakePipeShell.hxx>
/* v27 (S15): the holed-sweep assembly — see assemble_holed_pipe. */
#include <BRepBuilderAPI_Sewing.hxx>
#include <BRepLib_MakeFace.hxx>
#include <BRepTools_WireExplorer.hxx>
#include <Geom_Plane.hxx>
#include <ProjLib.hxx>
#include <Precision.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Solid.hxx>
/* v24: a spine that is a CURVE where the caller sampled one */
#include <GeomAPI_Interpolate.hxx>
#include <TColgp_HArray1OfPnt.hxx>
#include <BRepOffsetAPI_ThruSections.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <Geom_CylindricalSurface.hxx>
#include <Geom2d_Line.hxx>
#include <Law_Linear.hxx>
#include <GProp_GProps.hxx>
#include <BRepGProp.hxx>
#include <BRepLib.hxx>
#include <BRepBuilderAPI_TransitionMode.hxx>
#include <BRepExtrema_DistShapeShape.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <GeomAdaptor_Curve.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepTools.hxx>
#include <Geom_Surface.hxx>
#include <GCPnts_AbscissaPoint.hxx>
#include <TopoDS_Edge.hxx>
#include <algorithm>

/* v20 (M217): Delete Face and Direct Edit. */
#include <BRepAlgoAPI_Defeaturing.hxx>
#include <BRepGProp_Face.hxx>

#include <STEPControl_Reader.hxx>
#include <STEPControl_Writer.hxx>
#include <STEPControl_StepModelType.hxx>
#include <IFSelect_ReturnStatus.hxx>
/* M214 — a STEP file nobody has to apologise for: explicit units, an explicit
 * schema, a real product name per body, and a real FILE_NAME header. */
#include <Interface_Static.hxx>
#include <APIHeaderSection_MakeHeader.hxx>
#include <StepData_StepModel.hxx>
#include <TCollection_HAsciiString.hxx>

/* ---- error plumbing ---------------------------------------------------- */

static char g_err[512] = "";

static void set_err(const char *where, const char *what)
{
    std::snprintf(g_err, sizeof(g_err), "%s: %s", where,
                  (what && *what) ? what : "unknown OCCT failure");
}

/* Runs `expr` with full exception containment; on throw records the message
 * and evaluates to the fallback. Used by every entry point below. */
#define OCCT_TRY(where)                                                        \
    try {
#define OCCT_CATCH(where, failvalue)                                           \
    }                                                                          \
    catch (const Standard_Failure &f)                                          \
    {                                                                          \
        set_err(where, f.GetMessageString());                                  \
        return failvalue;                                                      \
    }                                                                          \
    catch (const std::exception &e)                                            \
    {                                                                          \
        set_err(where, e.what());                                              \
        return failvalue;                                                      \
    }                                                                          \
    catch (...)                                                                \
    {                                                                          \
        set_err(where, "non-standard exception");                              \
        return failvalue;                                                      \
    }

struct occt_shape
{
    TopoDS_Shape s;
    /* M304 — the true area of each face, in TopExp_Explorer order.
     *
     * Filled on the first mesh and never again: a shape is immutable here
     * (every operation returns a new one), so its faces cannot change area,
     * while the tessellation is rebuilt on every zoom. Measured on the whale,
     * BRepGProp over 362 faces costs 150 ms and summing the triangles costs
     * 0.8 ms — so the expensive half is paid once per shape and the cheap half
     * per remesh. */
    mutable std::vector<double> face_area;
};

static occt_shape *wrap(const TopoDS_Shape &s, const char *where)
{
    if (s.IsNull()) {
        set_err(where, "resulting shape is null");
        return nullptr;
    }
    return new occt_shape{s, std::vector<double>()};
}

/* ---- version / errors --------------------------------------------------- */

extern "C" const char *occt_version(void)
{
    /* Keep the grep marker "Prototype OCCT shim" a single literal. */
    static char buf[128] = "";
    if (!buf[0]) {
        /* v28 (S17): ASKS occt_shim_version() instead of repeating it.
         *
         * The note this replaces said it was "kept in step with
         * occt_shim_version() below", having said "v21" while the number went
         * 22, 23 — and it had drifted again by v27/v28, because "kept in step"
         * is a promise a literal cannot make. Now it cannot drift: there is one
         * number and the string reads it. The grep marker "Prototype OCCT shim"
         * stays a single literal, which is all the CI link check needs. */
        std::snprintf(buf, sizeof(buf), "Prototype OCCT shim v%d (OCCT %s)",
                      occt_shim_version(), OCC_VERSION_COMPLETE);
    }
    return buf;
}

/* v19, not v18: TWO branches in flight both claimed v17 — main for
 * occt_mirror, this one for occt_export_step_named — and this branch then
 * built v18 on top of its own v17. The merged surface is strictly larger than
 * either, so it takes the next free number rather than pretending one of the
 * two v17s did not happen. A version that means different things in two
 * binaries is worse than a gap in the sequence. */
/* v21 (S2 of the optimisation split): occt_shape_edges_info. Five sessions
 * are editing this repository in parallel, and the v17 collision above is
 * what happens when two of them pick the same number — this one is taken by
 * the session that owns backend/occt/shim/**, which is the only one adding
 * shim surface. */
/* v22 (S6, round two): the convexity sign in field 11 stops going through
 * BRepClass3d_SolidClassifier — see convexity_sign — and
 * occt_shape_edges_info_ref appears as its test-only reference. Field 11's
 * VALUE changes on shapes with a feature thinner than ‖bbox diagonal‖/1414,
 * where the pre-v22 answer was wrong; nothing else in the record moves. A
 * caller that must know whether it is talking to a binary whose thin-wall
 * convexity can be trusted tests for >= 22. */
/* v23 — AND IT HAPPENED AGAIN, exactly as the v17 note above predicted it
 * would. Two lineages both shipped a "v21": the optimisation branch's
 * occt_shape_edges_info, and main's occt_brep_from_mesh (M232, mesh import).
 * Neither knew about the other, so "v21" named two different ABIs.
 *
 * Resolved the way the v17 collision was, and for the reason recorded there —
 * "a version that means different things in two binaries is worse than a gap
 * in the sequence". The merged surface is strictly larger than either side,
 * so it takes the next free number instead of pretending one of the two v21s
 * did not happen. A v23 binary has ALL of it: edges_info, the local convexity
 * sign, and brep_from_mesh. */
/* v24 (S14, round three): occt_sweep_profile_ex and the OCCT_SWEEP_PATH_*
 * modes — and, more importantly, a CHANGE OF BEHAVIOUR in occt_sweep_profile
 * itself, which now takes OCCT_SWEEP_PATH_AUTO.
 *
 * A sweep whose path came from the application's own curve sampler now runs
 * along an interpolated curve rather than along the sampler's polyline, so its
 * result has `segments + 2` faces where v23 gave `segments x spans + 2`. Same
 * volume to eight figures, about 4.4 % of it in a different place, and it
 * BUILDS in the regime where v23 failed after four minutes or aborted the
 * process. A caller that must have the old shape asks for
 * OCCT_SWEEP_PATH_POLY; a caller that must know whether it is talking to a
 * binary that can build a 1200-segment sweep tests for >= 24.
 *
 * Taken by the session that owns backend/occt/shim/** — the rule that kept the
 * v17 and v21/v23 collisions from being worse, and it is why 24 and not 23.1
 * or a reuse of 23. */
/* v25 (S14, item 1): orientation 1 ("Fixed") stops calling the wrong OCCT
 * mode. It has mapped to GeomFill_ConstantBiNormal since v15, which replaces
 * the sweep frame's tangent with its projection perpendicular to the binormal;
 * on any path that bends, the result was a self-intersecting shell that
 * BRepCheck_Analyzer rejects and whose volume was up to 174 % too large — a
 * part nearly three times too big that the app would accept and draw. It now
 * uses GeomFill_IsFixed ("all sections will be parallel"), which is what the
 * call site has always claimed it meant.
 *
 * Straight single-segment paths are UNCHANGED, bit for bit, in both laws; only
 * bending paths move, and they move from invalid to analytic. A caller that
 * must know whether orientation 1 can be trusted on a bending path tests for
 * >= 25. Independent of v24: the repair works on the v23 polyline spine. */
/* v26 (S14, item 2): a hole is placed the way its own body is placed.
 * finish_pipe had added every hole with WithCorrection = Standard_True since
 * v15 while occt_sweep_profile added the outer wire with the caller's setting,
 * so on any path the section is not perpendicular to, a holed sweep lost about
 * 3.2 % of its volume. Straight paths were exact, which is why it survived.
 * Orientations 0 and 1 move; orientation 2 and occt_coil_profile do not, since
 * they were already passing True. Test for >= 26 if a holed sweep's volume has
 * to be right. */
/* v27 (S15): a holed profile is ASSEMBLED, not subtracted.
 *
 * finish_pipe had removed every hole with a BRepAlgoAPI_Cut since v15. That
 * boolean is cheap between two solids made of planes and ruinous between two
 * made of general swept surfaces — 21 653.6 ms against 66.0 ms for the two
 * sweeps that feed it (S14 §4.1) — which is why occt_sweep_profile_ex forced
 * a holed profile back onto the v23 polyline spine, and why a holed profile
 * kept v23's outright FAILURE at 1200 segments.
 *
 * It now sweeps each wire to its lateral shell, caps both ends with a planar
 * face whose outer boundary is the outer sweep's end section and whose inner
 * boundaries are the holes', sews the pieces and makes a solid. Measured
 * (perf/findings/S15-holes.md §2): at 24 segments the two routes return THE
 * SAME DOUBLE — 5 031.442237 on a polyline spine, 5 031.420889 on a smooth
 * one, relative delta 0.000e+00, same face counts, both valid. At 1200
 * segments the assembly builds in 7 952.7 ms and is valid, where the boolean
 * route does not return a solid at all.
 *
 * Three things a caller learns by testing for >= 27:
 *
 *  1. a holed sweep builds at sizes where v26 did not;
 *  2. OCCT_SWEEP_PATH_AUTO now SMOOTHS a holed path. The nloops > 1
 *     restriction existed because of the boolean's cost. This is a BEHAVIOUR
 *     CHANGE in the same direction v24 made for unholed profiles: a holed
 *     sweep along a sampled arc comes back with a different face count and a
 *     volume that differs in the sixth figure;
 *  3. a hole that is NOT strictly inside the outer boundary, or that overlaps
 *     another hole, still works — by the v26 boolean, unchanged, and AUTO
 *     still forces POLY in that case so the fallback does not land on the
 *     expensive spine. profile_holes_are_separate is what decides.
 *
 * Taken by the session that owns backend/occt/shim/**, per the v17 and
 * v21/v23 collision notes above. */
/* v28 (S17): the three defects S16's audit found away from the trivial value,
 * repaired. All three are BEHAVIOUR changes on inputs no test had ever sent,
 * which is why nine months of green did not catch them. Each has its mechanism
 * at its own site and in perf/findings/S17-oblique.md section 0; this is what
 * a caller learns by testing for >= 28.
 *
 *  1. occt_coil_profile's `clockwise` reverses the WINDING and no longer the
 *     climb. It used to negate both components of the helix's (u,v) direction,
 *     which is the same right-handed helix run backwards: a coil that DESCENDED
 *     to z in [-height, 0] with its handedness unchanged. It now rises by
 *     `height` and is the mirror image of the counterclockwise coil. Volume is
 *     unchanged to the last bit either way — the helix length is the same — so
 *     a caller who needs to know cannot ask the volume; test the version, or
 *     the bounding box.
 *
 *  2. occt_move_faces sweeps each face along the component of the delta on its
 *     OWN NORMAL, not along the whole delta. An oblique delta used to sweep a
 *     LEANING prism, whose union carried an overhang on one side and a
 *     re-entrant notch on the other; it now returns the same solid as the
 *     delta's normal component alone. A 20-cube's top face moved by (5,0,5) is
 *     volume 10 000 and valid BOTH ways — the discriminators are the bounding
 *     box (x-max was 25, is 20) and a ray (the exit above x = 2 was 22, is 25).
 *     A caller who was relying on the lean was relying on an overhang; a caller
 *     who only ever moved along the normal sees nothing change.
 *
 *  3. occt_chamfer_edges mode 2 accepts 0 < angle_deg < 180 - theta, the edge's
 *     own admissible range, where it used to accept 0 < angle_deg < 90. The
 *     bound is the angle between the edge's two outward normals, which is
 *     occt_shape_edge_info field [10], so a caller can compute what will be
 *     accepted. This cuts BOTH ways and a caller should know which it is
 *     relying on: an acute edge now accepts angles that used to be refused (a
 *     60-degree edge reaches 120), and an OBTUSE edge now refuses angles that
 *     used to be passed to OCCT and to fail there (a 135-degree edge stops at
 *     45). An edge whose bound cannot be measured keeps the 90 rule, so every
 *     perpendicular edge — which is every chamfer fixture before [40j] — is
 *     bit-identical.
 *
 * Not in v28, found while establishing (3) and routed rather than fixed:
 * part_model.dart's Flip sends 90 - angle for mode 2, the same hardcoded
 * perpendicular assumption one layer up. Dart is not this session's.
 *
 * Taken by the session that owns backend/occt/shim/**, per the collision notes
 * above; the brief allocated it rather than leaving it to be read off the
 * file, this project having had three identifier collisions already. */
/* v29: occt_cut retries a boolean that removed NOTHING at a fuzzy tolerance.
 *
 * BEHAVIOUR CHANGE, and it is worth knowing which way. Before v29 a cut whose
 * arguments only TOUCH — a counterbore tangent to a bore, the reported case —
 * could come back reporting success with the removed plugs still inside the
 * result, so the shape weighed exactly what it did before the cut and its mesh
 * was not watertight. It now removes the material. A caller that was reading
 * the volume to decide whether a cut had done anything will start seeing a
 * DIFFERENT number on such a model, and the right one.
 *
 * Nothing else moves. The first attempt is still the plain
 * BRepAlgoAPI_Cut(a, b) at OCCT's own tolerance, and the retry is entered only
 * when that removed nothing at all and taken only when it removes something no
 * larger than the tool — so every cut that already worked is bit-identical,
 * and a tool that genuinely misses its body still yields the body unchanged.
 *
 * Taken by the session that owns backend/occt/shim/**, per the collision notes
 * above. */
extern "C" int occt_shim_version(void) { return 29; }

extern "C" const char *occt_last_error(void) { return g_err; }

/* ---- construction -------------------------------------------------------- */

extern "C" occt_shape *occt_make_box(double dx, double dy, double dz)
{
    OCCT_TRY("occt_make_box")
    if (dx <= 0 || dy <= 0 || dz <= 0) {
        set_err("occt_make_box", "extents must be > 0");
        return nullptr;
    }
    BRepPrimAPI_MakeBox mk(dx, dy, dz);
    return wrap(mk.Shape(), "occt_make_box");
    OCCT_CATCH("occt_make_box", nullptr)
}

extern "C" occt_shape *occt_make_cylinder(double cx, double cy, double cz,
                                          double r, double h)
{
    OCCT_TRY("occt_make_cylinder")
    if (r <= 0 || h <= 0) {
        set_err("occt_make_cylinder", "radius and height must be > 0");
        return nullptr;
    }
    gp_Ax2 axis(gp_Pnt(cx, cy, cz), gp_Dir(0.0, 0.0, 1.0));
    BRepPrimAPI_MakeCylinder mk(axis, r, h);
    return wrap(mk.Shape(), "occt_make_cylinder");
    OCCT_CATCH("occt_make_cylinder", nullptr)
}

extern "C" occt_shape *occt_extrude_polygon(const double *xy, int npts,
                                            double height)
{
    OCCT_TRY("occt_extrude_polygon")
    if (!xy || npts < 3) {
        set_err("occt_extrude_polygon", "need at least 3 profile points");
        return nullptr;
    }
    if (height <= 0) {
        set_err("occt_extrude_polygon", "height must be > 0");
        return nullptr;
    }
    BRepBuilderAPI_MakePolygon poly;
    for (int i = 0; i < npts; ++i)
        poly.Add(gp_Pnt(xy[2 * i], xy[2 * i + 1], 0.0));
    poly.Close();
    if (!poly.IsDone()) {
        set_err("occt_extrude_polygon", "profile wire construction failed");
        return nullptr;
    }
    const TopoDS_Wire wire = poly.Wire();
    /* Same explicit plane as the loop profiles: a wire-inferred plane flips
     * its normal with the winding, which also flips the resulting solid's
     * face orientation. */
    const gp_Pln profilePln(gp_Ax3(gp_Pnt(0, 0, 0), gp_Dir(0, 0, 1)));
    BRepBuilderAPI_MakeFace faceMk(profilePln, wire, Standard_True);
    if (!faceMk.IsDone()) {
        set_err("occt_extrude_polygon",
                "profile is not a valid planar face (self-intersecting?)");
        return nullptr;
    }
    const TopoDS_Face face = faceMk.Face();
    BRepPrimAPI_MakePrism prism(face, gp_Vec(0.0, 0.0, height));
    return wrap(prism.Shape(), "occt_extrude_polygon");
    OCCT_CATCH("occt_extrude_polygon", nullptr)
}

/* ---- v3: arc-aware profile loops ---------------------------------------- */

/* Signed area of a bulge loop: shoelace of the vertices plus the signed
 * circular-segment area of every arc edge (bulge b, chord c: sweep
 * θ = 4·atan b, radius r = c / (2 sin(θ/2)), segment = r²(θ − sin θ)/2,
 * signed like the bulge). Needed because e.g. a full circle written as two
 * half-arcs has ZERO shoelace area — the segments carry all of it. */
/* Defined further down next to the boolean entry points; the extrude paths
 * need it earlier to validate a hole cut. */
static bool has_solid_material(const TopoDS_Shape &s);

static double arc_loop_signed_area(const double *xyb, int npts)
{
    double a = 0.0;
    for (int i = 0; i < npts; ++i) {
        const int j = (i + 1) % npts;
        const double x0 = xyb[3 * i], y0 = xyb[3 * i + 1];
        const double x1 = xyb[3 * j], y1 = xyb[3 * j + 1];
        a += 0.5 * (x0 * y1 - x1 * y0);
        const double b = xyb[3 * i + 2];
        if (std::fabs(b) > 1e-12) {
            const double chord = std::hypot(x1 - x0, y1 - y0);
            const double th = 4.0 * std::atan(std::fabs(b));
            const double sh = std::sin(0.5 * th);
            if (chord > 1e-12 && sh > 1e-12) {
                const double r = chord / (2.0 * sh);
                const double seg = 0.5 * r * r * (th - std::sin(th));
                a += (b > 0 ? seg : -seg);
            }
        }
    }
    return a;
}

/* Wire of one bulge loop, traversed forward or reversed (reversal flips the
 * vertex order AND negates every bulge — the bulge belongs to its edge). */
static TopoDS_Wire arc_loop_wire(const double *xyb, int npts, bool forward,
                                 bool *ok)
{
    *ok = false;
    BRepBuilderAPI_MakeWire mk;
    for (int k = 0; k < npts; ++k) {
        int i, j;
        double b;
        if (forward) {
            i = k;
            j = (k + 1) % npts;
            b = xyb[3 * i + 2];
        } else {
            i = (npts - k) % npts;
            j = (npts - 1 - k);
            b = -xyb[3 * j + 2]; /* edge j->i reversed */
        }
        const gp_Pnt p0(xyb[3 * i], xyb[3 * i + 1], 0.0);
        const gp_Pnt p1(xyb[3 * j], xyb[3 * j + 1], 0.0);
        const double dx = p1.X() - p0.X(), dy = p1.Y() - p0.Y();
        const double chord = std::hypot(dx, dy);
        if (chord < 1e-12)
            continue; /* zero-length edge (e.g. a closed spline whose last
                       * sample lands exactly on the start): skip it — the
                       * wire still closes through the shared endpoints, and
                       * a redundant point must not sink the whole profile.
                       * Callers also de-duplicate, this is belt-and-braces. */
        if (std::fabs(b) < 1e-12) {
            BRepBuilderAPI_MakeEdge e(p0, p1);
            if (!e.IsDone())
                return TopoDS_Wire();
            mk.Add(e.Edge());
        } else {
            /* Three-point arc: mid-arc point = chord midpoint pushed by the
             * sagitta s = b·chord/2 along the RIGHT normal of p0->p1.
             * Positive bulge = counter-clockwise sweep (DXF): the CENTRE then
             * lies LEFT of travel and the arc bows AWAY from it, i.e. RIGHT.
             * The left normal here mirrored every arc across its chord — for
             * a full circle (two half-turns across a diameter) that maps the
             * circle onto itself, which is why only asymmetric profiles ever
             * showed it. arc_loop_signed_area already uses this convention:
             * it adds the segment POSITIVELY for a positive bulge. */
            const double s = b * 0.5 * chord;
            const double nx = dy / chord, ny = -dx / chord;
            const gp_Pnt pm(0.5 * (p0.X() + p1.X()) + nx * s,
                            0.5 * (p0.Y() + p1.Y()) + ny * s, 0.0);
            GC_MakeArcOfCircle arc(p0, pm, p1);
            if (!arc.IsDone())
                return TopoDS_Wire();
            BRepBuilderAPI_MakeEdge e(arc.Value());
            if (!e.IsDone())
                return TopoDS_Wire();
            mk.Add(e.Edge());
        }
        if (!mk.IsDone())
            return TopoDS_Wire();
    }
    *ok = mk.IsDone();
    return *ok ? mk.Wire() : TopoDS_Wire();
}

extern "C" occt_shape *occt_extrude_profile_arcs(const double *xyb,
                                                 const int *loop_counts,
                                                 int nloops, double height,
                                                 double taper_deg)
{
    OCCT_TRY("occt_extrude_profile_arcs")
    if (!xyb || !loop_counts || nloops < 1) {
        set_err("occt_extrude_profile_arcs", "null profile arguments");
        return nullptr;
    }
    if (height <= 0) {
        set_err("occt_extrude_profile_arcs", "height must be > 0");
        return nullptr;
    }
    for (int l = 0; l < nloops; ++l) {
        if (loop_counts[l] < 2) { /* 2 vertices = 2 arcs can close a circle */
            set_err("occt_extrude_profile_arcs",
                    "every loop needs at least 2 vertices");
            return nullptr;
        }
    }

    const double *p = xyb;
    bool ok = false;
    const double a0 = arc_loop_signed_area(p, loop_counts[0]);
    if (std::fabs(a0) < 1e-12) {
        set_err("occt_extrude_profile_arcs", "outer loop is degenerate");
        return nullptr;
    }
    TopoDS_Wire outer = arc_loop_wire(p, loop_counts[0], a0 > 0.0, &ok);
    if (!ok) {
        set_err("occt_extrude_profile_arcs", "outer wire construction failed");
        return nullptr;
    }
    /* Build the profile face on an EXPLICIT plane instead of letting MakeFace
     * infer one from the wire. Inferred from a POLYGON, the plane's normal
     * follows the wire's winding, so a rectangle drawn one way yields +Z and
     * the other way -Z. "Counter-clockwise" is defined in that parametric
     * frame, so when it flips, the outer boundary and the holes swap roles:
     * the face's material becomes the HOLE. Measured on device (build
     * d30bb6b) for a 19.5x13.5 rectangle with an r=2.73 hole — the caps came
     * back with area 23.3 (= pi*r^2, the circle alone) instead of 239.5
     * (rectangle minus circle), while the four side walls and the cylinder
     * wall were exact, and the shell reported 8 boundary edges: the walls had
     * no cap to close against. A circle outer never showed this because its
     * plane comes from the circle's own geometry, which is why
     * circle-in-circle extruded correctly all along.
     * Pinning the plane to +Z — the direction the prism is swept along
     * anyway — makes the orientation deterministic for every profile shape. */
    const gp_Pln profilePln(gp_Ax3(gp_Pnt(0, 0, 0), gp_Dir(0, 0, 1)));
    BRepBuilderAPI_MakeFace faceMk(profilePln, outer, Standard_True);
    if (!faceMk.IsDone()) {
        set_err("occt_extrude_profile_arcs",
                "outer loop is not a valid planar face (self-intersecting?)");
        return nullptr;
    }
    p += 3 * loop_counts[0];

    /* HOLES ARE CUT, NOT ADDED AS WIRES.
     *
     * BRepBuilderAPI_MakeFace::Add() was silently producing a face whose
     * MATERIAL was the hole: measured on device (build 37aba27), a
     * 12.3 x 15.0 rectangle with an r=2.65 circle came back with cap faces of
     * area 22.0 — exactly pi*r^2, the circle — while the four side walls were
     * dimensionally perfect and the shell reported 8 boundary edges, one pair
     * per wall with no cap to close against. The loops reach here in the right
     * order and with the right winding (outer +185 forward, hole +22 reversed,
     * both logged from Dart), and arc_loop_wire's reverse traversal is
     * correct, so the fault is in Add() itself.
     *
     * The same device run proved the SINGLE-wire path is exact for polygons —
     * a plain rectangle gives 6 faces, 12 triangles, watertight, caps 162.0 =
     * the rectangle's own area — and it has always been exact for circles. So
     * the outer and every hole are each built through that proven path and the
     * holes are then subtracted with a boolean. Nothing depends on multi-wire
     * face assembly any more.
     *
     * The cutting prisms overshoot the body at both ends: a tool whose cap is
     * COPLANAR with the body's cap is the classic way to make an OCCT boolean
     * fragile, and the overshoot costs nothing. */
    std::vector<TopoDS_Shape> hole_tools;
    const double pad = 0.01 * (std::fabs(height) + 1.0);
    for (int l = 1; l < nloops; ++l) {
        const double a = arc_loop_signed_area(p, loop_counts[l]);
        if (std::fabs(a) < 1e-12) {
            set_err("occt_extrude_profile_arcs", "hole loop is degenerate");
            return nullptr;
        }
        /* built like an OUTER boundary — it is the outer boundary of the tool */
        TopoDS_Wire holeW = arc_loop_wire(p, loop_counts[l], a > 0.0, &ok);
        if (!ok) {
            set_err("occt_extrude_profile_arcs",
                    "hole wire construction failed");
            return nullptr;
        }
        BRepBuilderAPI_MakeFace holeMk(profilePln, holeW, Standard_True);
        if (!holeMk.IsDone()) {
            set_err("occt_extrude_profile_arcs",
                    "hole loop is not a valid planar face");
            return nullptr;
        }
        const double sgn = height >= 0.0 ? 1.0 : -1.0;
        BRepPrimAPI_MakePrism tool(holeMk.Face(),
                                   gp_Vec(0.0, 0.0, height + sgn * 2.0 * pad));
        gp_Trsf down;
        down.SetTranslation(gp_Vec(0.0, 0.0, -sgn * pad));
        BRepBuilderAPI_Transform mv(tool.Shape(), down, Standard_True);
        hole_tools.push_back(mv.Shape());
        p += 3 * loop_counts[l];
    }
    if (!faceMk.IsDone()) {
        set_err("occt_extrude_profile_arcs",
                "outer loop did not yield a planar face");
        return nullptr;
    }
    /* A full circle arrives as TWO half arcs (a single closed arc edge is
     * degenerate), so the prism has two half-cylinder faces separated by two
     * REAL vertical edges — exactly the lines the display must never show.
     * UnifySameDomain merges same-surface faces and same-curve edges back
     * together: one cylindrical face (its seam is suppressed by the mesher)
     * and full-circle rims. */
    BRepPrimAPI_MakePrism prism(faceMk.Face(), gp_Vec(0.0, 0.0, height));
    TopoDS_Shape body = prism.Shape();
    for (const TopoDS_Shape &tool : hole_tools) {
        BRepAlgoAPI_Cut cut(body, tool);
        if (!cut.IsDone() || !has_solid_material(cut.Shape())) {
            set_err("occt_extrude_profile_arcs",
                    "cutting a hole out of the profile failed");
            return nullptr;
        }
        body = cut.Shape();
    }
    if (std::fabs(taper_deg) < 1e-9) {
        ShapeUpgrade_UnifySameDomain uni(body, Standard_True, Standard_True,
                                         Standard_False);
        uni.Build();
        return wrap(uni.Shape(), "occt_extrude_profile_arcs");
    }

    if (std::fabs(taper_deg) >= 90.0) {
        set_err("occt_extrude_profile_arcs",
                "taper must be inside (-90, 90) deg");
        return nullptr;
    }
    /* Same Inventor sign bridge as occt_extrude_profile. Lateral faces are
     * everything except the horizontal caps — including cylindrical faces
     * from arc edges, which BRepOffsetAPI_DraftAngle drafts into cones. */
    const double occtAngle = -taper_deg * (3.14159265358979323846 / 180.0);
    const gp_Dir pullDir(0.0, 0.0, 1.0);
    const gp_Pln neutral(gp_Ax3(gp_Pnt(0, 0, 0), gp_Dir(0, 0, 1)));
    BRepOffsetAPI_DraftAngle draft(body);
    int added = 0;
    for (TopExp_Explorer ex(body, TopAbs_FACE); ex.More();
         ex.Next()) {
        const TopoDS_Face f = TopoDS::Face(ex.Current());
        BRepAdaptor_Surface surf(f, Standard_False);
        if (surf.GetType() == GeomAbs_Plane &&
            std::fabs(surf.Plane().Axis().Direction().Z()) > 0.5)
            continue; /* top/bottom cap */
        draft.Add(f, pullDir, occtAngle, neutral);
        if (!draft.AddDone()) {
            set_err("occt_extrude_profile_arcs",
                    "draft transform rejected a lateral face "
                    "(taper too large for this profile?)");
            return nullptr;
        }
        ++added;
    }
    if (added == 0) {
        set_err("occt_extrude_profile_arcs", "no lateral faces found to taper");
        return nullptr;
    }
    draft.Build();
    if (!draft.IsDone()) {
        set_err("occt_extrude_profile_arcs", "draft transform failed");
        return nullptr;
    }
    ShapeUpgrade_UnifySameDomain uni(draft.Shape(), Standard_True,
                                     Standard_True, Standard_False);
    uni.Build();
    return wrap(uni.Shape(), "occt_extrude_profile_arcs");
    OCCT_CATCH("occt_extrude_profile_arcs", nullptr)
}

extern "C" occt_shape *occt_unify(const occt_shape *shape)
{
    OCCT_TRY("occt_unify")
    if (!shape) {
        set_err("occt_unify", "null shape");
        return nullptr;
    }
    ShapeUpgrade_UnifySameDomain uni(shape->s, Standard_True, Standard_True,
                                     Standard_False);
    uni.Build();
    return wrap(uni.Shape(), "occt_unify");
    OCCT_CATCH("occt_unify", nullptr)
}

extern "C" occt_shape *occt_fuse(const occt_shape *a, const occt_shape *b)
{
    OCCT_TRY("occt_fuse")
    if (!a || !b) {
        set_err("occt_fuse", "null operand");
        return nullptr;
    }
    BRepAlgoAPI_Fuse fuse(a->s, b->s);
    if (!fuse.IsDone()) {
        set_err("occt_fuse", "boolean fuse did not complete");
        return nullptr;
    }
    return wrap(fuse.Shape(), "occt_fuse");
    OCCT_CATCH("occt_fuse", nullptr)
}

/* True when `s` holds no solid/shell material — a boolean whose result is
 * empty (b removes all of a, or disjoint intersect) comes back as an empty
 * compound. We reject that as failure so callers keep the old body instead of
 * replacing it with nothing. */
static bool has_solid_material(const TopoDS_Shape &s)
{
    if (s.IsNull())
        return false;
    for (TopExp_Explorer ex(s, TopAbs_SOLID); ex.More(); ex.Next())
        return true;
    /* accept a lone shell/face result too (rare, but not "empty") */
    for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next())
        return true;
    return false;
}

/* ---- v29: a cut that survives a TANGENCY -------------------------------- */

/* Declared here, defined with the v16 blend guards further down — the same
 * move, and for the same reason, that the v20 section makes further down: the
 * boolean needs exactly the question that function already answers (what does
 * this shape weigh, and is that a number at all), and a second copy of
 * BRepGProp would be two answers to it. */
static double solid_volume(const TopoDS_Shape &s);

/* Fuzzy value for a RETRIED boolean.
 *
 * OCCT intersects at the arguments' own tolerance, and a TANGENCY gives it
 * nothing to find: two cylinders that touch along a line, rather than crossing,
 * are the case BOPAlgo is documented to be fragile on, and the remedy OCCT
 * offers for it is to intersect at a deliberately coarser tolerance instead.
 *
 * The value comes from the model's own size rather than a constant, so a 5 mm
 * part and a 5 m one get the same relative slack. 1e-5 of the pair's bounding
 * diagonal is far below any feature anyone draws (0.5 micron on a 50 mm part)
 * and far above the tolerance the surfaces carry. Floored at ten times OCCT's
 * confusion so it always means something, and capped at 0.01 mm so that on a
 * very large model it can still never swallow a real wall. */
static double boolean_fuzzy(const TopoDS_Shape &a, const TopoDS_Shape &b)
{
    Bnd_Box box;
    BRepBndLib::Add(a, box);
    BRepBndLib::Add(b, box);
    if (box.IsVoid())
        return 0.0;
    double xa, ya, za, xb, yb, zb;
    box.Get(xa, ya, za, xb, yb, zb);
    const double dx = xb - xa, dy = yb - ya, dz = zb - za;
    const double diag = std::sqrt(dx * dx + dy * dy + dz * dz);
    if (!std::isfinite(diag) || diag <= 0.0)
        return 0.0;
    double f = 1.0e-5 * diag;
    const double floorF = Precision::Confusion() * 10.0;
    if (f < floorF)
        f = floorF;
    if (f > 1.0e-2)
        f = 1.0e-2;
    return f;
}

/* a \ b at [fuzzy], or a null shape when the boolean did not complete.
 *
 * The two-argument BRepAlgoAPI_Cut constructor builds immediately and there is
 * no way to set a fuzzy value on it, so the retry has to go through the
 * arguments/tools form. `fuzzy <= 0` leaves OCCT's own tolerance in place,
 * which is exactly what that constructor does — so the FIRST attempt below is
 * still bit-for-bit the pre-v29 call. */
static TopoDS_Shape cut_at(const TopoDS_Shape &a, const TopoDS_Shape &b,
                           double fuzzy)
{
    BRepAlgoAPI_Cut op;
    TopTools_ListOfShape args, tools;
    args.Append(a);
    tools.Append(b);
    op.SetArguments(args);
    op.SetTools(tools);
    if (fuzzy > 0.0)
        op.SetFuzzyValue(fuzzy);
    op.Build();
    if (!op.IsDone())
        return TopoDS_Shape();
    return op.Shape();
}

extern "C" occt_shape *occt_cut(const occt_shape *a, const occt_shape *b)
{
    OCCT_TRY("occt_cut")
    if (!a || !b) {
        set_err("occt_cut", "null operand");
        return nullptr;
    }
    TopoDS_Shape r = cut_at(a->s, b->s, 0.0);
    if (r.IsNull()) {
        set_err("occt_cut", "boolean cut did not complete");
        return nullptr;
    }
    /* v29 — A CUT THAT KEPT WHAT IT REMOVED.
     *
     * Reported from the device: a Ø6 counterbore sunk 18 mm into a sleeve, on
     * three bosses, "irgendwie funktionierte es nicht und das Loch ist nicht
     * da". The cut reported success and the body came back with the SAME
     * volume to the last digit — 10182.8966 before and after — while its face
     * count went 7 -> 27 and its mesh stopped being watertight (1555 free
     * edges). Equal to the last digit is the tell: the counterbore geometry
     * was all there (shortened Ø3.7 walls, Ø6 walls 18 mm long, annular
     * floors), and so were the three plugs it had cut out. BRepGProp adds the
     * solids of a compound, so (a\b) + b weighs exactly a.
     *
     * What is special about that model and not about the through-holes drilled
     * a minute earlier in the same sketch, with the same tool direction, into
     * the same body: the counterbore is EXACTLY TANGENT to the sleeve's bore.
     * The sketch says so in as many words — a tangent constraint between the
     * Ø6 circle and the Ø10 bore, centres 8 apart, 8 = 5 + 3 — so the tool's
     * wall touches the body's bore along a line and never crosses it. That is
     * the tangency BOPAlgo is fragile on, and the fix OCCT offers for it is a
     * fuzzy value.
     *
     * So: the plain cut runs first and unchanged, and only a result that
     * removed NOTHING is retried at boolean_fuzzy(). A tool that genuinely
     * misses the body — which happens on every extrude preview before the
     * target is picked — removes nothing on the retry too, and pays one
     * boolean for the privilege. The retry is taken only when it removes
     * something, and only when what it removed is not wildly more than the
     * tool holds: a cut cannot take out more material than its tool contains,
     * and half again as much is far past any slack a half-micron fuzzy can
     * explain and squarely in "the fuzzy ate a wall". Short of that the plain
     * result stands, so this can subtract from no answer that was already
     * right.
     *
     * Not addressed here, and seen in the same log on the same pair:
     * occt_fuse came back with a shape that could not be tessellated. It is
     * the same tangency and would take the same treatment, but there is no
     * fixture for it in tests/smoke_occt.c and this change is the reported
     * one. */
    const double v0 = solid_volume(a->s);
    const double v1 = solid_volume(r);
    const double eps = (v0 > 0.0) ? 1.0e-9 * v0 : 0.0;
    if (v0 > 0.0 && !(v1 > 0.0 && v1 < v0 - eps)) {
        const double fuzzy = boolean_fuzzy(a->s, b->s);
        const double tool = solid_volume(b->s);
        if (fuzzy > 0.0) {
            const TopoDS_Shape r2 = cut_at(a->s, b->s, fuzzy);
            const double v2 = r2.IsNull() ? -1.0 : solid_volume(r2);
            if (v2 > 0.0 && v2 < v0 - eps && has_solid_material(r2) &&
                (tool <= 0.0 || v0 - v2 <= 1.5 * tool))
                r = r2;
        }
    }
    if (!has_solid_material(r)) {
        set_err("occt_cut", "cut removed all material (empty result)");
        return nullptr;
    }
    return wrap(r, "occt_cut");
    OCCT_CATCH("occt_cut", nullptr)
}

extern "C" occt_shape *occt_common(const occt_shape *a, const occt_shape *b)
{
    OCCT_TRY("occt_common")
    if (!a || !b) {
        set_err("occt_common", "null operand");
        return nullptr;
    }
    BRepAlgoAPI_Common common(a->s, b->s);
    if (!common.IsDone()) {
        set_err("occt_common", "boolean common did not complete");
        return nullptr;
    }
    const TopoDS_Shape r = common.Shape();
    if (!has_solid_material(r)) {
        set_err("occt_common", "inputs do not overlap (empty result)");
        return nullptr;
    }
    return wrap(r, "occt_common");
    OCCT_CATCH("occt_common", nullptr)
}

/* Signed area of loop i (positive = counter-clockwise in the z=0 plane). */
static double loop_signed_area(const double *xy, int npts)
{
    double a = 0.0;
    for (int i = 0; i < npts; ++i) {
        const int j = (i + 1) % npts;
        a += xy[2 * i] * xy[2 * j + 1] - xy[2 * j] * xy[2 * i + 1];
    }
    return 0.5 * a;
}

/* Builds the polygon wire of one loop, in the given traversal direction. */
static TopoDS_Wire loop_wire(const double *xy, int npts, bool forward,
                             bool *ok)
{
    BRepBuilderAPI_MakePolygon poly;
    for (int k = 0; k < npts; ++k) {
        const int i = forward ? k : (npts - 1 - k);
        poly.Add(gp_Pnt(xy[2 * i], xy[2 * i + 1], 0.0));
    }
    poly.Close();
    *ok = poly.IsDone();
    return *ok ? poly.Wire() : TopoDS_Wire();
}

extern "C" occt_shape *occt_extrude_profile(const double *xy,
                                            const int *loop_counts,
                                            int nloops, double height,
                                            double taper_deg)
{
    OCCT_TRY("occt_extrude_profile")
    if (!xy || !loop_counts || nloops < 1) {
        set_err("occt_extrude_profile", "null profile arguments");
        return nullptr;
    }
    if (height <= 0) {
        set_err("occt_extrude_profile", "height must be > 0");
        return nullptr;
    }
    for (int l = 0; l < nloops; ++l) {
        if (loop_counts[l] < 3) {
            set_err("occt_extrude_profile",
                    "every loop needs at least 3 points");
            return nullptr;
        }
    }

    /* Winding is normalised HERE so callers never have to care: the outer
     * boundary is forced counter-clockwise, holes clockwise — the exact
     * orientation BRepBuilderAPI_MakeFace expects for added hole wires. */
    const double *p = xy;
    bool ok = false;
    const double a0 = loop_signed_area(p, loop_counts[0]);
    if (std::fabs(a0) < 1e-12) {
        set_err("occt_extrude_profile", "outer loop is degenerate");
        return nullptr;
    }
    TopoDS_Wire outer = loop_wire(p, loop_counts[0], a0 > 0.0, &ok);
    if (!ok) {
        set_err("occt_extrude_profile", "outer wire construction failed");
        return nullptr;
    }
    /* Build the profile face on an EXPLICIT plane instead of letting MakeFace
     * infer one from the wire. Inferred from a POLYGON, the plane's normal
     * follows the wire's winding, so a rectangle drawn one way yields +Z and
     * the other way -Z. "Counter-clockwise" is defined in that parametric
     * frame, so when it flips, the outer boundary and the holes swap roles:
     * the face's material becomes the HOLE. Measured on device (build
     * d30bb6b) for a 19.5x13.5 rectangle with an r=2.73 hole — the caps came
     * back with area 23.3 (= pi*r^2, the circle alone) instead of 239.5
     * (rectangle minus circle), while the four side walls and the cylinder
     * wall were exact, and the shell reported 8 boundary edges: the walls had
     * no cap to close against. A circle outer never showed this because its
     * plane comes from the circle's own geometry, which is why
     * circle-in-circle extruded correctly all along.
     * Pinning the plane to +Z — the direction the prism is swept along
     * anyway — makes the orientation deterministic for every profile shape. */
    const gp_Pln profilePln(gp_Ax3(gp_Pnt(0, 0, 0), gp_Dir(0, 0, 1)));
    BRepBuilderAPI_MakeFace faceMk(profilePln, outer, Standard_True);
    if (!faceMk.IsDone()) {
        set_err("occt_extrude_profile",
                "outer loop is not a valid planar face (self-intersecting?)");
        return nullptr;
    }
    p += 2 * loop_counts[0];
    for (int l = 1; l < nloops; ++l) {
        const double a = loop_signed_area(p, loop_counts[l]);
        if (std::fabs(a) < 1e-12) {
            set_err("occt_extrude_profile", "hole loop is degenerate");
            return nullptr;
        }
        /* holes run clockwise */
        TopoDS_Wire holeW = loop_wire(p, loop_counts[l], a < 0.0, &ok);
        if (!ok) {
            set_err("occt_extrude_profile", "hole wire construction failed");
            return nullptr;
        }
        faceMk.Add(holeW);
        p += 2 * loop_counts[l];
    }
    if (!faceMk.IsDone()) {
        set_err("occt_extrude_profile",
                "profile face with holes failed (hole outside the outer "
                "loop, or loops intersect?)");
        return nullptr;
    }
    const TopoDS_Face face = faceMk.Face();
    BRepPrimAPI_MakePrism prism(face, gp_Vec(0.0, 0.0, height));
    if (std::fabs(taper_deg) < 1e-9)
        return wrap(prism.Shape(), "occt_extrude_profile");

    /* Taper: OCCT's draft-angle transform on every lateral (side) face.
     * Sign bridge (see occt_capi.h): OCCT removes matter on the Direction
     * side for POSITIVE angles, Inventor's positive taper flares OUTWARD
     * (matter added) — so Inventor angle == MINUS the OCCT angle. */
    if (std::fabs(taper_deg) >= 90.0) {
        set_err("occt_extrude_profile", "taper must be inside (-90, 90) deg");
        return nullptr;
    }
    const double occtAngle = -taper_deg * (3.14159265358979323846 / 180.0);
    const gp_Dir pullDir(0.0, 0.0, 1.0);
    const gp_Pln neutral(gp_Ax3(gp_Pnt(0, 0, 0), gp_Dir(0, 0, 1)));
    BRepOffsetAPI_DraftAngle draft(prism.Shape());
    int added = 0;
    for (TopExp_Explorer ex(prism.Shape(), TopAbs_FACE); ex.More();
         ex.Next()) {
        const TopoDS_Face f = TopoDS::Face(ex.Current());
        BRepAdaptor_Surface surf(f, Standard_False);
        if (surf.GetType() != GeomAbs_Plane)
            continue; /* polygon prisms have only planar faces */
        const double nz = surf.Plane().Axis().Direction().Z();
        if (std::fabs(nz) > 1e-7)
            continue; /* top/bottom cap, not a lateral face */
        draft.Add(f, pullDir, occtAngle, neutral);
        if (!draft.AddDone()) {
            set_err("occt_extrude_profile",
                    "draft transform rejected a lateral face "
                    "(taper too large for this profile?)");
            return nullptr;
        }
        ++added;
    }
    if (added == 0) {
        set_err("occt_extrude_profile", "no lateral faces found to taper");
        return nullptr;
    }
    draft.Build();
    if (!draft.IsDone()) {
        set_err("occt_extrude_profile",
                "draft transform failed (taper too large for this profile?)");
        return nullptr;
    }
    return wrap(draft.Shape(), "occt_extrude_profile");
    OCCT_CATCH("occt_extrude_profile", nullptr)
}

/* ---- queries -------------------------------------------------------------- */

extern "C" int occt_shape_counts(const occt_shape *shape,
                                 int *faces, int *edges, int *vertices)
{
    OCCT_TRY("occt_shape_counts")
    if (!shape) {
        set_err("occt_shape_counts", "null shape");
        return 0;
    }
    if (faces) {
        TopTools_IndexedMapOfShape m;
        TopExp::MapShapes(shape->s, TopAbs_FACE, m);
        *faces = m.Extent();
    }
    if (edges) {
        TopTools_IndexedMapOfShape m;
        TopExp::MapShapes(shape->s, TopAbs_EDGE, m);
        *edges = m.Extent();
    }
    if (vertices) {
        TopTools_IndexedMapOfShape m;
        TopExp::MapShapes(shape->s, TopAbs_VERTEX, m);
        *vertices = m.Extent();
    }
    return 1;
    OCCT_CATCH("occt_shape_counts", 0)
}

extern "C" int occt_shape_valid(const occt_shape *shape)
{
    OCCT_TRY("occt_shape_valid")
    if (!shape) {
        set_err("occt_shape_valid", "null shape");
        return 0;
    }
    BRepCheck_Analyzer an(shape->s);
    return an.IsValid() ? 1 : 0;
    OCCT_CATCH("occt_shape_valid", 0)
}

extern "C" double occt_shape_volume(const occt_shape *shape)
{
    OCCT_TRY("occt_shape_volume")
    if (!shape) {
        set_err("occt_shape_volume", "null shape");
        return -1.0;
    }
    GProp_GProps props;
    BRepGProp::VolumeProperties(shape->s, props);
    return props.Mass();
    OCCT_CATCH("occt_shape_volume", -1.0)
}

extern "C" int occt_bbox(const occt_shape *shape, double *out6)
{
    OCCT_TRY("occt_bbox")
    if (!shape || !out6) {
        set_err("occt_bbox", "null argument");
        return 0;
    }
    Bnd_Box box;
    BRepBndLib::Add(shape->s, box);
    if (box.IsVoid()) {
        set_err("occt_bbox", "empty bounding box");
        return 0;
    }
    box.Get(out6[0], out6[1], out6[2], out6[3], out6[4], out6[5]);
    return 1;
    OCCT_CATCH("occt_bbox", 0)
}

/* mat34 (row-major 3x4) -> gp_Trsf, REFUSING anything that is not a rigid
 * motion. Extracted from occt_transform in v15 so the sweep/loft/coil paths
 * enforce the same rule rather than re-implementing (or forgetting) it.
 *
 * Rigidity is checked HERE and not left to gp_Trsf::SetValues, which accepts
 * an orthogonal matrix TIMES A SCALE FACTOR — so a uniform scale would sail
 * through and silently resize the solid. */
static bool trsf_from_mat34(const double *mat34, gp_Trsf &t, const char *who)
{
    if (!mat34) {
        set_err(who, "null matrix");
        return false;
    }
    const double c[3][3] = {{mat34[0], mat34[1], mat34[2]},
                            {mat34[4], mat34[5], mat34[6]},
                            {mat34[8], mat34[9], mat34[10]}};
    const double tol = 1e-9;
    int ok = 1;
    for (int i = 0; i < 3 && ok; ++i) {
        for (int j = i; j < 3 && ok; ++j) {
            const double d =
                c[0][i] * c[0][j] + c[1][i] * c[1][j] + c[2][i] * c[2][j];
            if (std::fabs(d - (i == j ? 1.0 : 0.0)) > tol)
                ok = 0;
        }
    }
    const double det = c[0][0] * (c[1][1] * c[2][2] - c[1][2] * c[2][1]) -
                       c[0][1] * (c[1][0] * c[2][2] - c[1][2] * c[2][0]) +
                       c[0][2] * (c[1][0] * c[2][1] - c[1][1] * c[2][0]);
    if (!ok || std::fabs(det - 1.0) > tol) {
        set_err(who,
                "matrix is not a rigid motion (need an orthonormal rotation "
                "with determinant +1; scale/shear/mirror are refused)");
        return false;
    }
    t.SetValues(mat34[0], mat34[1], mat34[2], mat34[3], mat34[4], mat34[5],
                mat34[6], mat34[7], mat34[8], mat34[9], mat34[10], mat34[11]);
    return true;
}

extern "C" occt_shape *occt_transform(const occt_shape *shape,
                                      const double *mat34)
{
    OCCT_TRY("occt_transform")
    if (!shape || !mat34) {
        set_err("occt_transform", "null argument");
        return nullptr;
    }
    gp_Trsf t;
    if (!trsf_from_mat34(mat34, t, "occt_transform"))
        return nullptr;
    BRepBuilderAPI_Transform tr(shape->s, t, Standard_True /* copy */);
    if (!tr.IsDone()) {
        set_err("occt_transform", "transform did not complete");
        return nullptr;
    }
    return wrap(tr.Shape(), "occt_transform");
    OCCT_CATCH("occt_transform", nullptr)
}

/* ---- v17: reflection ----------------------------------------------------- */

/*
 * v17 — occt_mirror. The ONE placement occt_transform is not allowed to
 * express, and the reason it needs its own entry point.
 *
 * A reflection has determinant -1, which trsf_from_mat34 refuses on purpose:
 * a matrix arriving there with det != +1 is far more likely to be a bug in
 * the caller (a scale, a shear, a frame built the wrong way round) than a
 * deliberate mirror, and silently resizing or inverting a solid is exactly
 * the class of error that check exists to catch. A mirror asked for BY NAME
 * cannot be that mistake, so it is built here from a plane rather than
 * smuggled in as a matrix.
 *
 * plane6 = {px, py, pz, nx, ny, nz}: a point on the mirror plane and its
 * normal (need not be unit; a zero-length normal is refused).
 *
 * gp_Trsf::SetMirror(gp_Ax2) mirrors about the PLANE of the axis placement,
 * i.e. the plane through its location perpendicular to its main direction.
 *
 * The orientation check afterwards is not decoration. A reflection turns a
 * solid inside out: every face normal that pointed outward now points in,
 * and OCCT's boolean operations read orientation, so a mirrored tool that
 * kept the reversed sense would CUT where it should ADD. BRepBuilderAPI_
 * Transform corrects this itself for a negative-determinant transformation,
 * but "itself" is a behaviour, not a contract — measuring the volume costs
 * one mass property evaluation and turns a silent wrong-boolean into a
 * shape that is right or an error that says so.
 */
extern "C" occt_shape *occt_mirror(const occt_shape *shape,
                                   const double *plane6)
{
    OCCT_TRY("occt_mirror")
    if (!shape || !plane6) {
        set_err("occt_mirror", "null argument");
        return nullptr;
    }
    const double nx = plane6[3], ny = plane6[4], nz = plane6[5];
    const double len = std::sqrt(nx * nx + ny * ny + nz * nz);
    if (!(len > 1e-12)) {
        set_err("occt_mirror", "the mirror plane has no normal direction");
        return nullptr;
    }
    gp_Trsf t;
    t.SetMirror(gp_Ax2(gp_Pnt(plane6[0], plane6[1], plane6[2]),
                       gp_Dir(nx / len, ny / len, nz / len)));
    BRepBuilderAPI_Transform tr(shape->s, t, Standard_True /* copy */);
    if (!tr.IsDone()) {
        set_err("occt_mirror", "mirror did not complete");
        return nullptr;
    }
    TopoDS_Shape out = tr.Shape();
    GProp_GProps props;
    BRepGProp::VolumeProperties(out, props);
    if (props.Mass() < 0.0)
        out = out.Reversed();
    return wrap(out, "occt_mirror");
    OCCT_CATCH("occt_mirror", nullptr)
}

/* ---- v2: tessellation --------------------------------------------------- */


/* v9 — Is `e` a TANGENT-CONTINUOUS join between its two faces?
 *
 * An arc-approximated gear flank, and equally a tessellated spline, reaches
 * the kernel as a CHAIN of separate faces. Every face boundary was drawn, so
 * a smooth flank came out covered in vertical lines. UnifySameDomain cannot
 * merge these: consecutive flank arcs are genuinely different cylinders
 * (different centre, different radius), so they are not the same domain.
 * Inventor draws an edge only where the surface actually creases, so compare
 * the two surface normals at the middle of the edge and treat a small angle
 * as smooth. Orientation matters: a REVERSED face's natural normal points
 * into the solid.
 */
static bool edge_is_smooth(const TopoDS_Edge &e, const TopoDS_Face &f1,
                           const TopoDS_Face &f2, double cos_tol)
{
    try {
        Standard_Real a0 = 0, a1 = 0, b0 = 0, b1 = 0;
        Handle(Geom2d_Curve) c1 = BRep_Tool::CurveOnSurface(e, f1, a0, a1);
        Handle(Geom2d_Curve) c2 = BRep_Tool::CurveOnSurface(e, f2, b0, b1);
        if (c1.IsNull() || c2.IsNull())
            return false;
        const gp_Pnt2d uv1 = c1->Value(0.5 * (a0 + a1));
        const gp_Pnt2d uv2 = c2->Value(0.5 * (b0 + b1));
        BRepAdaptor_Surface s1(f1, Standard_False);
        BRepAdaptor_Surface s2(f2, Standard_False);
        BRepLProp_SLProps p1(s1, uv1.X(), uv1.Y(), 1, 1e-7);
        BRepLProp_SLProps p2(s2, uv2.X(), uv2.Y(), 1, 1e-7);
        if (!p1.IsNormalDefined() || !p2.IsNormalDefined())
            return false;
        gp_Dir n1 = p1.Normal();
        gp_Dir n2 = p2.Normal();
        if (f1.Orientation() == TopAbs_REVERSED)
            n1.Reverse();
        if (f2.Orientation() == TopAbs_REVERSED)
            n2.Reverse();
        return n1.Dot(n2) >= cos_tol;
    } catch (const Standard_Failure &) {
        return false; /* undecidable: keep the edge, never hide a real one */
    }
}

struct occt_mesh
{
    std::vector<double> verts;      /* 3 per vertex */
    std::vector<double> norms;      /* 3 per vertex, unit, outward */
    std::vector<int> tris;          /* 3 indices per triangle, CCW outside */
    std::vector<int> edge_starts;   /* nedges+1 offsets into edge_pts/3 */
    std::vector<double> edge_pts;   /* 3 per edge point */
    /* v4 */
    std::vector<int> tri_face;      /* 1 face index per triangle */
    std::vector<double> face_infos; /* 15 doubles per face (see header) */
    std::vector<double> edge_curves;/* 16 doubles per edge (see header) */
    /* v12 */
    std::vector<int> edge_ids;      /* 1-based topological index per display edge */
    /* v20 */
    std::vector<int> face_ids;      /* 1-based topological index per mesh face */
};

extern "C" occt_mesh *occt_mesh_create(const occt_shape *shape,
                                       double lin_deflection,
                                       double ang_deflection)
{
    OCCT_TRY("occt_mesh_create")
    if (!shape) {
        set_err("occt_mesh_create", "null shape");
        return nullptr;
    }
    if (!(lin_deflection > 0) || !(ang_deflection > 0)) {
        set_err("occt_mesh_create", "deflections must be > 0");
        return nullptr;
    }
    /* Triangulate in place (results are cached on the faces). */
    /* v10: mesh the faces IN PARALLEL (last argument). A gear prism carries
     * 442-827 faces and each is tessellated independently, so this is
     * embarrassingly parallel; on device the single-threaded mesher cost
     * 397-2580 ms per call and blocked the UI thread for all of it. */
    BRepMesh_IncrementalMesh mesher(shape->s, lin_deflection,
                                    Standard_False, ang_deflection,
                                    Standard_True);
    (void)mesher;

    /* M282 — a face the mesher refused is a hole you can see through.
     *
     * BRepMesh gives up on some trimmed B-splines and says nothing: it returns
     * no triangulation for that face and the loop below, which has always
     * skipped an untriangulated face, quietly leaves it out of the model. The
     * shape is not at fault — on the whale the three faces this happened to
     * were valid, their wires closed in 3D and in uv, and they were the
     * SIMPLEST surfaces in the model (4x5, 5x4 and 4x6 control nets) while
     * faces four times as complicated meshed without complaint. Nor is it a
     * property that can be designed out upstream: the same face meshes at
     * deflection 0.60, fails at 0.15 and meshes again at 0.0375, and the app
     * changes deflection every time the user zooms.
     *
     * So ask again, differently. Nudging the deflection is enough to get past
     * it, and a face drawn at a slightly different deflection costs a hairline
     * seam where its neighbours' nodes no longer coincide — which is a trade
     * worth making. Measured on the whale at the deflection the app asked for:
     * three faces recovered, none left empty, the worst gap in the display
     * mesh down from 5.18 mm to 3.42 mm, cracks wider than a millimetre down
     * from 122.6 mm to 34.0 mm, and the edges with no neighbour at all down
     * from 74 to 20. What it costs is seams a few microns wide.
     *
     * Nothing here touches the B-Rep. The solid stays the one that was sewn,
     * checked and closed; only the triangles handed to the renderer change. */
    {
        /* M304 — "has triangles" was the wrong question.
         *
         * M282 asked whether a refused face had any triangles at all, and
         * recovered the three faces of the whale that had none. It missed the
         * larger half of the same defect: a face BRepMesh gives up on PART of
         * the way through keeps the triangles it managed and reports success.
         * Face 253 of the whale came back with five triangles covering 0.1% of
         * its 68 mm2 — indistinguishable, to that test, from a healthy face.
         * Measured across the model: three faces with no triangles at all,
         * 366 mm2; twelve faces under-covered, 547 mm2. The bigger hole was
         * the one that passed.
         *
         * So compare what was drawn against what should have been. The catch
         * is that a chord always cuts the corner off a curved face, so even a
         * perfect tessellation under-reports — 98.6% across this whole model at
         * the deflection the app asks for. The bar therefore sits at 95%, well
         * below what chords cost and well above the 88.3% and 94.6% of the
         * faces that are genuinely torn.
         *
         * A face that misses the bar is re-meshed at a nudged deflection until
         * it clears it. If none of them does, it is put back the way it was, so
         * a face flagged by mistake costs a little time and changes nothing. */
        static const double kNudge[] = {1.37, 0.73, 2.11, 0.41, 4.0, 0.19};
        static const double kCoverBar = 0.95;

        auto meshedArea = [](const TopoDS_Face &f) -> double {
            TopLoc_Location loc;
            const Handle(Poly_Triangulation) t = BRep_Tool::Triangulation(f, loc);
            if (t.IsNull())
                return 0.0;
            const gp_Trsf &tr = loc.Transformation();
            double a = 0;
            for (int i = 1; i <= t->NbTriangles(); ++i) {
                int n1, n2, n3;
                t->Triangle(i).Get(n1, n2, n3);
                const gp_Pnt A = t->Node(n1).Transformed(tr);
                const gp_Pnt B = t->Node(n2).Transformed(tr);
                const gp_Pnt C = t->Node(n3).Transformed(tr);
                a += 0.5 * gp_Vec(A, B).Crossed(gp_Vec(A, C)).Magnitude();
            }
            return a;
        };

        if (shape->face_area.empty()) {
            for (TopExp_Explorer ex(shape->s, TopAbs_FACE); ex.More(); ex.Next()) {
                double a = 0;
                try {
                    GProp_GProps g;
                    BRepGProp::SurfaceProperties(TopoDS::Face(ex.Current()), g);
                    a = g.Mass();
                } catch (const Standard_Failure &) {
                } catch (...) {
                }
                shape->face_area.push_back(a);
            }
        }

        size_t fi = 0;
        for (TopExp_Explorer ex(shape->s, TopAbs_FACE); ex.More(); ex.Next(), ++fi) {
            const TopoDS_Face f = TopoDS::Face(ex.Current());
            const double want = fi < shape->face_area.size() ? shape->face_area[fi] : 0.0;
            if (!(want > 0))
                continue;
            if (meshedArea(f) >= want * kCoverBar)
                continue;
            bool healed = false;
            for (size_t k = 0; k < sizeof(kNudge) / sizeof(kNudge[0]) && !healed; ++k) {
                try {
                    BRepTools::Clean(f);
                    BRepMesh_IncrementalMesh retry(f, lin_deflection * kNudge[k],
                                                   Standard_False, ang_deflection,
                                                   Standard_True);
                    (void)retry;
                } catch (const Standard_Failure &) {
                } catch (...) {
                }
                healed = meshedArea(f) >= want * kCoverBar;
            }
            if (!healed) {
                /* Nothing did better. Put it back as it was, so this can only
                 * ever add coverage and never take any away. */
                try {
                    BRepTools::Clean(f);
                    BRepMesh_IncrementalMesh back(f, lin_deflection, Standard_False,
                                                  ang_deflection, Standard_True);
                    (void)back;
                } catch (const Standard_Failure &) {
                } catch (...) {
                }
            }
        }
    }

    std::vector<double> verts, norms, edge_pts, edge_curves;
    std::vector<int> tris, edge_starts;
    std::vector<int> edge_ids; /* v12: topological index per display edge */
    /* v20 — the same problem edge_ids solves, for faces. The loop below SKIPS
     * a face with no triangulation, so the mesh's face index and the
     * topological index (TopExp_Explorer order) part company the moment one
     * face fails to mesh. Picking produces the mesh index; every kernel
     * operation that names a face — delete, move — needs the topological one.
     * Deriving it later by re-exploring would be guesswork; recording it here,
     * where both numbers are in hand, cannot be wrong. */
    std::vector<int> face_ids;
    edge_starts.push_back(0);

    /* Faces -> shaded triangles. Vertices are emitted PER FACE, so B-Rep
     * edges stay crisp while each curved face shades smoothly. */
    std::vector<int> tri_face;
    std::vector<double> face_infos;
    int face_idx = 0;
    int topo_face = 0; /* v20: advances for EVERY face, meshed or not */
    for (TopExp_Explorer ex(shape->s, TopAbs_FACE); ex.More(); ex.Next()) {
        const TopoDS_Face face = TopoDS::Face(ex.Current());
        ++topo_face;
        TopLoc_Location loc;
        Handle(Poly_Triangulation) tri = BRep_Tool::Triangulation(face, loc);
        if (tri.IsNull() || tri->NbTriangles() < 1)
            continue;
        face_ids.push_back(topo_face);
        /* v4: one 15-double surface record per triangulated face */
        {
            BRepAdaptor_Surface surf(face, Standard_True);
            double rec[15] = {5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
            const double sgn =
                (face.Orientation() == TopAbs_REVERSED) ? -1.0 : 1.0;
            switch (surf.GetType()) {
            case GeomAbs_Plane: {
                const gp_Pln pl = surf.Plane();
                rec[0] = 0;
                const gp_Pnt o = pl.Location();
                const gp_Dir n = pl.Axis().Direction();
                const gp_Dir x = pl.XAxis().Direction();
                rec[1] = o.X(); rec[2] = o.Y(); rec[3] = o.Z();
                rec[4] = sgn * n.X(); rec[5] = sgn * n.Y();
                rec[6] = sgn * n.Z();
                rec[7] = x.X(); rec[8] = x.Y(); rec[9] = x.Z();
                break;
            }
            case GeomAbs_Cylinder: {
                const gp_Cylinder cy = surf.Cylinder();
                rec[0] = 1;
                const gp_Pnt o = cy.Location();
                const gp_Dir a = cy.Axis().Direction();
                const gp_Dir x = cy.XAxis().Direction();
                rec[1] = o.X(); rec[2] = o.Y(); rec[3] = o.Z();
                rec[4] = a.X(); rec[5] = a.Y(); rec[6] = a.Z();
                rec[7] = x.X(); rec[8] = x.Y(); rec[9] = x.Z();
                rec[10] = cy.Radius();
                break;
            }
            /* M215 (v18) — cone, sphere and torus used to record their TYPE
             * and nothing else: slots 1..10 stayed zero. Nothing needed them
             * until work features arrived, and then three Inventor methods
             * (Through Revolved Face, Center Point of Sphere, Center Point of
             * Torus) would all have quietly produced a feature at the WORLD
             * ORIGIN — geometry in the wrong place, with no error. Filling
             * them is purely additive: every previous reader either ignores
             * these types or switches on rec[0] first. */
            case GeomAbs_Cone: {
                const gp_Cone co = surf.Cone();
                rec[0] = 2;
                const gp_Pnt o = co.Location();
                const gp_Dir a = co.Axis().Direction();
                const gp_Dir x = co.XAxis().Direction();
                rec[1] = o.X(); rec[2] = o.Y(); rec[3] = o.Z();
                rec[4] = a.X(); rec[5] = a.Y(); rec[6] = a.Z();
                rec[7] = x.X(); rec[8] = x.Y(); rec[9] = x.Z();
                rec[10] = co.RefRadius();
                break;
            }
            case GeomAbs_Sphere: {
                const gp_Sphere sp = surf.Sphere();
                rec[0] = 3;
                /* Location() IS the centre for a sphere — the one point the
                 * "Center Point of Sphere" method exists to find. */
                const gp_Pnt o = sp.Location();
                const gp_Dir a = sp.Position().Direction();
                const gp_Dir x = sp.XAxis().Direction();
                rec[1] = o.X(); rec[2] = o.Y(); rec[3] = o.Z();
                rec[4] = a.X(); rec[5] = a.Y(); rec[6] = a.Z();
                rec[7] = x.X(); rec[8] = x.Y(); rec[9] = x.Z();
                rec[10] = sp.Radius();
                break;
            }
            case GeomAbs_Torus: {
                const gp_Torus to = surf.Torus();
                rec[0] = 4;
                const gp_Pnt o = to.Location();
                const gp_Dir a = to.Axis().Direction();
                const gp_Dir x = to.XAxis().Direction();
                rec[1] = o.X(); rec[2] = o.Y(); rec[3] = o.Z();
                rec[4] = a.X(); rec[5] = a.Y(); rec[6] = a.Z();
                rec[7] = x.X(); rec[8] = x.Y(); rec[9] = x.Z();
                rec[10] = to.MajorRadius();
                break;
            }
            default:             rec[0] = 5; break;
            }
            rec[11] = surf.FirstUParameter();
            rec[12] = surf.LastUParameter();
            rec[13] = surf.FirstVParameter();
            rec[14] = surf.LastVParameter();
            for (int r = 0; r < 15; ++r)
                face_infos.push_back(rec[r]);
        }
        BRepLib_ToolTriangulatedShape::ComputeNormals(face, tri);
        const gp_Trsf trsf = loc.Transformation();
        const bool reversed = (face.Orientation() == TopAbs_REVERSED);
        const int base = (int)(verts.size() / 3);
        const int nn = tri->NbNodes();
        for (int i = 1; i <= nn; ++i) {
            gp_Pnt p = tri->Node(i).Transformed(trsf);
            verts.push_back(p.X());
            verts.push_back(p.Y());
            verts.push_back(p.Z());
            gp_Dir n = tri->Normal(i);
            if (loc.IsIdentity() == Standard_False)
                n.Transform(trsf); /* rotate normals with the location */
            const double s = reversed ? -1.0 : 1.0;
            norms.push_back(s * n.X());
            norms.push_back(s * n.Y());
            norms.push_back(s * n.Z());
        }
        for (int t = 1; t <= tri->NbTriangles(); ++t) {
            int n1, n2, n3;
            tri->Triangle(t).Get(n1, n2, n3);
            if (reversed)
                std::swap(n2, n3); /* keep CCW-from-outside winding */
            tris.push_back(base + n1 - 1);
            tris.push_back(base + n2 - 1);
            tris.push_back(base + n3 - 1);
            tri_face.push_back(face_idx);
        }
        ++face_idx;
    }

    /* Edges -> display polylines, discretised straight from the curves so
     * they are smooth regardless of the face tessellation. */
    TopTools_IndexedMapOfShape edgeMap;
    TopExp::MapShapes(shape->s, TopAbs_EDGE, edgeMap);
    /* Seam edges (an edge a closed face uses TWICE, e.g. the vertical
     * parameter seam of a cylinder barrel) are artifacts of the surface
     * parameterisation, not model edges — Inventor never shows them. */
    TopTools_IndexedDataMapOfShapeListOfShape edgeFaces;
    TopExp::MapShapesAndAncestors(shape->s, TopAbs_EDGE, TopAbs_FACE,
                                  edgeFaces);
    for (int i = 1; i <= edgeMap.Extent(); ++i) {
        const TopoDS_Edge edge = TopoDS::Edge(edgeMap.FindKey(i));
        if (BRep_Tool::Degenerated(edge))
            continue;
        bool seam = false;
        if (edgeFaces.Contains(edge)) {
            const TopTools_ListOfShape &fl = edgeFaces.FindFromKey(edge);
            for (TopTools_ListIteratorOfListOfShape it(fl); it.More();
                 it.Next()) {
                if (BRep_Tool::IsClosed(edge, TopoDS::Face(it.Value()))) {
                    seam = true;
                    break;
                }
            }
        }
        if (seam)
            continue;
        /* v9: drop tangent-continuous joins (see edge_is_smooth). cos(8 deg)
         * — a real model crease is far sharper, and the arc-chain joins this
         * removes are well under one degree.
         *
         * v14: ONLY when the two faces are the SAME surface type. A fillet is
         * tangent to its neighbours BY CONSTRUCTION, so the blanket rule threw
         * away exactly the line where the round meets the flat — a filleted
         * box rendered as one smooth blob with no outline at either end of the
         * radius, which is not what any CAD package draws. An arc-chain join
         * (the artifact this rule exists for) is cylinder-to-cylinder, so
         * restricting it to same-type pairs keeps that cleanup intact while
         * plane-to-cylinder and cylinder-to-torus boundaries come back.
         *
         * Known limit: a fillet running tangentially into ANOTHER fillet of
         * the same surface type is still suppressed. Distinguishing that from
         * an arc chain needs more than the surface type. */
        if (edgeFaces.Contains(edge)) {
            const TopTools_ListOfShape &fl2 = edgeFaces.FindFromKey(edge);
            if (fl2.Extent() == 2) {
                const TopoDS_Face fa = TopoDS::Face(fl2.First());
                const TopoDS_Face fb = TopoDS::Face(fl2.Last());
                BRepAdaptor_Surface sa(fa, Standard_False);
                BRepAdaptor_Surface sb(fb, Standard_False);
                if (sa.GetType() == sb.GetType() &&
                    edge_is_smooth(edge, fa, fb, 0.990268))
                    continue;
            }
        }
        BRepAdaptor_Curve curve(edge);
        /* v11: edges are discretised MUCH finer than the faces. An edge is a
         * 1D curve, so points on it are nearly free, while the face
         * tessellation that shares the same deflection is 2D and dominates
         * the cost. Sharing one number meant that every time the triangle
         * budget coarsened the faces, the black outlines went visibly
         * angular with it — the cheapest part of the picture degraded to pay
         * for the most expensive. Outlines are what the eye judges, so they
         * get a fixed fine deflection of their own. */
        const double edge_lin = lin_deflection < 5.0e-3 ? lin_deflection : 5.0e-3;
        const double edge_ang = ang_deflection < 0.05 ? ang_deflection : 0.05;
        GCPnts_TangentialDeflection disc(curve, edge_ang, edge_lin, 2);
        const int np = disc.NbPoints();
        if (np < 2)
            continue;
        for (int k = 1; k <= np; ++k) {
            const gp_Pnt p = disc.Value(k);
            edge_pts.push_back(p.X());
            edge_pts.push_back(p.Y());
            edge_pts.push_back(p.Z());
        }
        edge_starts.push_back((int)(edge_pts.size() / 3));
        /* v12: remember WHICH topological edge this display edge came from.
         * The loop above skips degenerate, seam and tangent-continuous edges,
         * so the display index and the TopExp::MapShapes index drift apart
         * the moment a model has a fillet or a cylinder in it. Fillet and
         * chamfer address the topological index; picking hands back a display
         * index. Without this row the two silently disagree and the fillet
         * lands on a different edge than the one the user tapped. */
        edge_ids.push_back(i);
        /* v4: one 16-double analytic record per exported edge, so the
         * display can draw lines/circles/ellipses as exact vector curves.
         * Anything else keeps type 0 and renders from the polyline. */
        {
            double rec[16] = {0};
            switch (curve.GetType()) {
            case GeomAbs_Line: {
                const gp_Pnt p0 = curve.Value(curve.FirstParameter());
                const gp_Pnt p1 = curve.Value(curve.LastParameter());
                rec[0] = 1;
                rec[1] = p0.X(); rec[2] = p0.Y(); rec[3] = p0.Z();
                rec[4] = p1.X(); rec[5] = p1.Y(); rec[6] = p1.Z();
                break;
            }
            case GeomAbs_Circle: {
                const gp_Circ ci = curve.Circle();
                const gp_Pnt c = ci.Location();
                const gp_Dir x = ci.XAxis().Direction();
                const gp_Dir y = ci.YAxis().Direction();
                rec[0] = 2;
                rec[1] = c.X(); rec[2] = c.Y(); rec[3] = c.Z();
                rec[4] = x.X(); rec[5] = x.Y(); rec[6] = x.Z();
                rec[7] = y.X(); rec[8] = y.Y(); rec[9] = y.Z();
                rec[10] = ci.Radius();
                rec[11] = curve.FirstParameter();
                rec[12] = curve.LastParameter();
                break;
            }
            case GeomAbs_Ellipse: {
                const gp_Elips el = curve.Ellipse();
                const gp_Pnt c = el.Location();
                const gp_Dir x = el.XAxis().Direction();
                const gp_Dir y = el.YAxis().Direction();
                rec[0] = 3;
                rec[1] = c.X(); rec[2] = c.Y(); rec[3] = c.Z();
                rec[4] = x.X(); rec[5] = x.Y(); rec[6] = x.Z();
                rec[7] = y.X(); rec[8] = y.Y(); rec[9] = y.Z();
                rec[10] = el.MajorRadius();
                rec[11] = el.MinorRadius();
                rec[12] = curve.FirstParameter();
                rec[13] = curve.LastParameter();
                break;
            }
            default:
                break; /* type 0: polyline fallback */
            }
            for (int r = 0; r < 16; ++r)
                edge_curves.push_back(rec[r]);
        }
    }

    if (tris.empty()) {
        set_err("occt_mesh_create", "triangulation produced no triangles");
        return nullptr;
    }
    occt_mesh *m = new occt_mesh();
    m->verts.swap(verts);
    m->norms.swap(norms);
    m->tris.swap(tris);
    m->edge_starts.swap(edge_starts);
    m->edge_pts.swap(edge_pts);
    m->tri_face.swap(tri_face);
    m->face_infos.swap(face_infos);
    m->edge_curves.swap(edge_curves);
    m->edge_ids.swap(edge_ids);
    m->face_ids.swap(face_ids);
    return m;
    OCCT_CATCH("occt_mesh_create", nullptr)
}

extern "C" int occt_mesh_counts(const occt_mesh *m, int *nvertices,
                                int *ntriangles, int *nedges,
                                int *nedge_points)
{
    if (!m) {
        set_err("occt_mesh_counts", "null mesh");
        return 0;
    }
    if (nvertices)
        *nvertices = (int)(m->verts.size() / 3);
    if (ntriangles)
        *ntriangles = (int)(m->tris.size() / 3);
    if (nedges)
        *nedges = (int)(m->edge_starts.size() - 1);
    if (nedge_points)
        *nedge_points = (int)(m->edge_pts.size() / 3);
    return 1;
}

extern "C" int occt_mesh_vertices(const occt_mesh *m, double *out)
{
    if (!m || !out) {
        set_err("occt_mesh_vertices", "null argument");
        return 0;
    }
    std::memcpy(out, m->verts.data(), m->verts.size() * sizeof(double));
    return 1;
}

extern "C" int occt_mesh_normals(const occt_mesh *m, double *out)
{
    if (!m || !out) {
        set_err("occt_mesh_normals", "null argument");
        return 0;
    }
    std::memcpy(out, m->norms.data(), m->norms.size() * sizeof(double));
    return 1;
}

extern "C" int occt_mesh_triangles(const occt_mesh *m, int *out)
{
    if (!m || !out) {
        set_err("occt_mesh_triangles", "null argument");
        return 0;
    }
    std::memcpy(out, m->tris.data(), m->tris.size() * sizeof(int));
    return 1;
}

extern "C" int occt_mesh_edges(const occt_mesh *m, int *starts, double *pts)
{
    if (!m || !starts || !pts) {
        set_err("occt_mesh_edges", "null argument");
        return 0;
    }
    std::memcpy(starts, m->edge_starts.data(),
                m->edge_starts.size() * sizeof(int));
    std::memcpy(pts, m->edge_pts.data(), m->edge_pts.size() * sizeof(double));
    return 1;
}

extern "C" int occt_mesh_face_count(const occt_mesh *m)
{
    return m ? (int)(m->face_infos.size() / 15) : -1;
}

extern "C" int occt_mesh_triangle_faces(const occt_mesh *m, int *out)
{
    if (!m || !out) {
        set_err("occt_mesh_triangle_faces", "null argument");
        return 0;
    }
    std::copy(m->tri_face.begin(), m->tri_face.end(), out);
    return 1;
}

extern "C" int occt_mesh_face_infos(const occt_mesh *m, double *out)
{
    if (!m || !out) {
        set_err("occt_mesh_face_infos", "null argument");
        return 0;
    }
    std::copy(m->face_infos.begin(), m->face_infos.end(), out);
    return 1;
}

extern "C" int occt_mesh_edge_curves(const occt_mesh *m, double *out)
{
    if (!m || !out) {
        set_err("occt_mesh_edge_curves", "null argument");
        return 0;
    }
    std::copy(m->edge_curves.begin(), m->edge_curves.end(), out);
    return 1;
}

extern "C" void occt_free_mesh(occt_mesh *m)
{
    delete m; /* delete nullptr is a no-op */
}

/* ---- STEP ------------------------------------------------------------------ */

/* M214 — the write-side translation parameters, pinned EXPLICITLY.
 *
 * Every one of these has an OCCT default, and until M214 the exporter relied
 * on all of them. That is not the same as them being right:
 *
 *   - Interface_Static is PROCESS-GLOBAL and PERSISTENT. Anything that reads
 *     a STEP file earlier in the session runs through the same registry, and
 *     the app does read them (occt_import_step, on every reopen of a part
 *     with an imported body). Leaning on "the default is still whatever it
 *     was at startup" is a bet, not a contract — and the losing side of that
 *     bet is a file that is silently off by a factor of 25.4.
 *   - The header advertises AP214; nothing enforced it. `write.step.schema`
 *     is settable by anyone in the process, so the advertised schema and the
 *     written schema were only coincidentally the same.
 *   - AP214IS deliberately, NOT AP242. AP242 is the newer schema, but the job
 *     of this file is to open everywhere — including in the older readers a
 *     machine shop actually runs. AP242 only starts paying for itself with
 *     colours/PMI, which need XCAF (see occt_export_step_named).
 *
 * Called after the writer is constructed, because the STEP controller (which
 * is what REGISTERS these parameter names) initialises lazily in that
 * constructor — see the file header. Setting them before would silently do
 * nothing.
 */
/* Returns 1 when the UNIT took, 0 when it did not. The unit is the one
 * parameter worth refusing to write over: a file silently in inches is a part
 * machined 25.4x wrong, whereas a schema or curve-mode fallback is cosmetic.
 * Enum parameters are set by NAME rather than by index — the numbering is an
 * OCCT implementation detail, the names are the documented interface. */
static int step_write_setup(void)
{
    /* Millimetres — the unit every length in this shim is documented in
     * (occt_capi.h) and the unit the app models in. */
    Interface_Static::SetCVal("write.step.unit", "MM");
    /* AP214, international standard — what occt_capi.h promises. */
    Interface_Static::SetCVal("write.step.schema", "AP214IS");
    /* Each transferred root is its own product; no assembly wrapper is
     * synthesised around bodies that are not an assembly. */
    Interface_Static::SetCVal("write.step.assembly", "Off");
    /* Write both the 3D curve and its parametric (pcurve) counterpart. Some
     * readers trust one and some the other; writing both is what makes a
     * trimmed cylindrical face (i.e. every hole in this app) survive the
     * trip into a reader that rebuilds surfaces from pcurves. */
    Interface_Static::SetIVal("write.surfacecurve.mode", 1);
    /* Tolerances come from the shape itself rather than a fixed value, so a
     * fillet built at 1e-7 does not get flattened to a coarser global. */
    Interface_Static::SetIVal("write.precision.mode", 0);

    /* Read back rather than trust the setter: SetCVal on an unregistered or
     * mis-spelled parameter returns quietly and leaves the old value in
     * place, which is exactly the silent-wrong-units failure this guards. */
    const char *unit = Interface_Static::CVal("write.step.unit");
    return (unit && std::strcmp(unit, "MM") == 0) ? 1 : 0;
}

/* M214 — writes `n` bodies as `n` named STEP products.
 *
 * WHY NOT ONE FUSED SOLID (what the Dart side used to do): a part with two
 * separate bodies is two bodies. Fusing them to get a single shape to hand
 * over is wrong three times — it destroys body identity, it runs a full
 * boolean (slow, and it can FAIL, which turned "export two bodies" into
 * "export nothing"), and on disjoint solids it is pure cost for no change.
 *
 * WHY NOT ONE COMPOUND: a compound transfers as ONE product, so the receiving
 * CAD shows one body called "OCCT STEP model" no matter how many bodies went
 * in. Transferring each solid separately gives each its own PRODUCT, and
 * `write.step.product.name` is read by STEPControl_ActorWrite at TRANSFER
 * time — so setting it between transfers is what names them individually.
 * That is the whole trick, and it is why the loop looks redundant but is not.
 *
 * `names` may be NULL, and any individual entry may be NULL/empty; such a
 * body falls back to `product`, then to a generic name. `product` names the
 * document in the FILE_NAME header.
 */
extern "C" int occt_export_step_named(const occt_shape **shapes,
                                      const char **names, int n,
                                      const char *path, const char *product)
{
    OCCT_TRY("occt_export_step_named")
    if (!shapes || n <= 0 || !path || !*path) {
        set_err("occt_export_step_named", "null shapes/path or n <= 0");
        return 0;
    }
    const char *doc = (product && *product) ? product : "Part";

    STEPControl_Writer writer;
    if (!step_write_setup()) {
        set_err("occt_export_step_named",
                "could not pin the STEP write units to millimetres — refusing "
                "to write a file whose scale cannot be guaranteed");
        return 0;
    }

    for (int i = 0; i < n; ++i) {
        if (!shapes[i] || shapes[i]->s.IsNull()) {
            set_err("occt_export_step_named", "null shape in the export set");
            return 0;
        }
        /* Read at TRANSFER time by STEPControl_ActorWrite, so setting it here
         * — between transfers — is what gives each body its own name. */
        const char *nm = (names && names[i] && *names[i]) ? names[i] : doc;
        Interface_Static::SetCVal("write.step.product.name", nm);
        if (writer.Transfer(shapes[i]->s, STEPControl_AsIs)
            != IFSelect_RetDone) {
            /* Name the body that failed. "transfer failed" on a ten-body part
             * is not something the user can act on; "Solid7 failed" is. */
            char msg[256];
            std::snprintf(msg, sizeof(msg),
                          "body \"%s\" (%d of %d) could not be transferred to "
                          "the STEP model", nm, i + 1, n);
            set_err("occt_export_step_named", msg);
            return 0;
        }
    }

    /* FILE_NAME. Written AFTER the transfers: the model does not exist until
     * the first one runs. Without this the header carries OCCT's own defaults,
     * so every file the app has ever produced claimed to be an unnamed model
     * from a generic translator — the document's own name appeared nowhere in
     * the file the user just shared.
     *
     * Only the two SINGLE-VALUED header fields are set. The array-valued ones
     * (author, organisation, description) are addressed by index, and writing
     * index 1 of a list the writer may not have sized is an out-of-range throw
     * — i.e. a lost export in exchange for a cosmetic string. Not a trade
     * worth making. */
    Handle(StepData_StepModel) model = writer.Model();
    if (!model.IsNull()) {
        APIHeaderSection_MakeHeader header(model);
        header.SetName(new TCollection_HAsciiString(doc));
        header.SetOriginatingSystem(
            new TCollection_HAsciiString(occt_version()));
    }

    if (writer.Write(path) != IFSelect_RetDone) {
        set_err("occt_export_step_named", "writing the STEP file failed "
                                          "(path not writable?)");
        return 0;
    }
    return 1;
    OCCT_CATCH("occt_export_step_named", 0)
}

extern "C" int occt_export_step(const occt_shape *shape, const char *path)
{
    if (!shape) {
        set_err("occt_export_step", "null shape or path");
        return 0;
    }
    /* One body, unnamed: exactly occt_export_step_named with n = 1, so the
     * two entry points cannot drift apart on units or schema. */
    return occt_export_step_named(&shape, nullptr, 1, path, nullptr);
}

extern "C" occt_shape *occt_import_step(const char *path)
{
    OCCT_TRY("occt_import_step")
    if (!path || !*path) {
        set_err("occt_import_step", "null path");
        return nullptr;
    }
    STEPControl_Reader reader;
    if (reader.ReadFile(path) != IFSelect_RetDone) {
        set_err("occt_import_step", "file missing or not parseable as STEP");
        return nullptr;
    }
    if (reader.TransferRoots() < 1) {
        set_err("occt_import_step", "no transferable roots in STEP file");
        return nullptr;
    }
    return wrap(reader.OneShape(), "occt_import_step");
    OCCT_CATCH("occt_import_step", nullptr)
}

/* M110 — explodes a shape into its SOLIDS.
 *
 * occt_import_step returns OneShape(), which for a multi-part STEP file is a
 * compound. The browser's unit of work is a BODY, so an imported assembly
 * should arrive as several bodies you can hide, rename and boolean against
 * individually, exactly like the ones this app builds. A compound would be one
 * opaque lump instead.
 *
 * Fills at most [max] entries of [out] and returns how many were written; 0
 * for a shape with no solids (a surface or wireframe import), so the caller
 * can say something honest rather than adding an empty body. The caller owns
 * every returned shape.
 */
extern "C" int occt_split_solids(const occt_shape *shape, occt_shape **out,
                                 int max)
{
    OCCT_TRY("occt_split_solids")
    if (!shape || !out || max <= 0) {
        set_err("occt_split_solids", "null shape/out or max <= 0");
        return 0;
    }
    int n = 0;
    for (TopExp_Explorer ex(shape->s, TopAbs_SOLID); ex.More() && n < max;
         ex.Next()) {
        occt_shape *w = wrap(ex.Current(), "occt_split_solids");
        if (w) out[n++] = w;
    }
    return n;
    OCCT_CATCH("occt_split_solids", 0)
}


/* ---- v20 (M217): Delete Face and Direct Edit --------------------------- */

/* Defined with the v16 blend guards further down; forward-declared because
 * the catastrophe check it powers ("the operation said done and emptied the
 * body") is wanted here too, and moving the definition up would drag the
 * whole blend section with it. */
static double solid_volume(const TopoDS_Shape &s);

/* The 1-based topological faces named by `ids`, or an empty list when any id
 * is out of range. Out of range is a CALLER bug (a stale pick), and silently
 * dropping it would delete a different face than the one that was tapped. */
static TopTools_ListOfShape faces_by_id(const TopoDS_Shape &shape,
                                        const int *ids, int n, int *bad)
{
    TopTools_ListOfShape out;
    TopTools_IndexedMapOfShape map;
    TopExp::MapShapes(shape, TopAbs_FACE, map);
    for (int i = 0; i < n; ++i) {
        if (ids[i] < 1 || ids[i] > map.Extent()) {
            if (bad) *bad = ids[i];
            out.Clear();
            return out;
        }
        out.Append(map(ids[i]));
    }
    return out;
}

/* Outward unit normal of `face` at its parametric middle, face orientation
 * applied. BRepGProp_Face::Normal already accounts for REVERSED, so this is
 * the direction that points OUT of the material. */
static Standard_Boolean face_outward(const TopoDS_Face &face, gp_Dir &out)
{
    BRepGProp_Face prop(face);
    Standard_Real u0, u1, v0, v1;
    prop.Bounds(u0, u1, v0, v1);
    gp_Pnt p;
    gp_Vec n;
    prop.Normal((u0 + u1) * 0.5, (v0 + v1) * 0.5, p, n);
    if (n.Magnitude() < 1e-12) return Standard_False;
    out = gp_Dir(n);
    return Standard_True;
}

/*
 * M217 — Inventor's Delete Face with Heal.
 *
 * BRepAlgoAPI_Defeaturing IS this command: OCCT's own description of it is
 * "removal of features from a shape", and the way it closes the wound is
 * exactly Inventor's Heal — the faces around the hole are extended until they
 * intersect. Deleting a fillet gives back the sharp corner; deleting the
 * cylindrical face of a hole fills the hole.
 *
 * `heal` = 0 is REFUSED rather than approximated. Inventor's un-healed Delete
 * Face converts the part into a SURFACE body and says so in the browser; this
 * app has no surface bodies at all — every KernelSolid is a solid with a
 * volume, booleans and a STEP product. Returning an open shell here would
 * hand every one of those a shape it cannot honour. Saying no is the honest
 * answer until surface bodies exist.
 */
extern "C" occt_shape *occt_delete_faces(const occt_shape *shape,
                                         const int *ids, int n, int heal)
{
    OCCT_TRY("occt_delete_faces")
    if (!shape || !ids || n <= 0) {
        set_err("occt_delete_faces", "null shape/ids or n <= 0");
        return nullptr;
    }
    if (!heal) {
        set_err("occt_delete_faces",
                "Delete Face without Heal would leave an open surface body, "
                "which this app has no representation for — leave Heal on");
        return nullptr;
    }
    int bad = 0;
    TopTools_ListOfShape rm = faces_by_id(shape->s, ids, n, &bad);
    if (rm.IsEmpty()) {
        char msg[128];
        std::snprintf(msg, sizeof(msg),
                      "face %d does not exist on this body any more", bad);
        set_err("occt_delete_faces", msg);
        return nullptr;
    }
    BRepAlgoAPI_Defeaturing df;
    df.SetShape(shape->s);
    df.AddFacesToRemove(rm);
    df.SetRunParallel(Standard_False);
    df.Build();
    if (!df.IsDone()) {
        set_err("occt_delete_faces",
                "the faces could not be removed — the gap they leave cannot "
                "be closed by extending their neighbours");
        return nullptr;
    }
    const TopoDS_Shape res = df.Shape();
    if (res.IsNull()) {
        set_err("occt_delete_faces", "removal produced nothing");
        return nullptr;
    }
    /* A defeaturing that silently emptied or exploded the body is a failure
     * even when OCCT calls it done — the same catastrophe guard the blends
     * use. */
    const double before = solid_volume(shape->s);
    const double after = solid_volume(res);
    if (after <= 0 || (before > 0 && after > before * 100)) {
        set_err("occt_delete_faces",
                "removal produced a degenerate body");
        return nullptr;
    }
    return wrap(res, "occt_delete_faces");
    OCCT_CATCH("occt_delete_faces", nullptr)
}

/*
 * M217 — Inventor's Direct > Move / Size on a set of faces.
 *
 * WHY A PRISM AND A BOOLEAN, and not a surface-level face move: the honest
 * kernel answer for "slide this face and re-trim its neighbours" is a
 * BRepTools_Modification subclass, which is real work and, more to the point,
 * work whose failure modes only show up on shapes. Sweeping the face itself
 * along the delta and fusing or cutting the swept volume produces EXACTLY the
 * same solid whenever the neighbouring walls are parallel to the motion —
 * which is every prismatic part, i.e. what Direct Edit is reached for. On a
 * tapered neighbour the two differ, and the caller is told (see the Dart
 * side) rather than being handed a quiet approximation.
 *
 * v28 (S17): the prism is swept along the delta's component ALONG EACH FACE'S
 * OWN NORMAL rather than along the whole delta, which is what makes the
 * paragraph above true of an oblique delta and not only of a perpendicular
 * one. The long note at the sweep itself has the mechanism and what was
 * rejected.
 *
 * Fuse or cut is decided PER FACE by the sign of delta against that face's
 * outward normal: moving a face along its outward normal adds the swept
 * material, moving it inward removes it. A selection whose faces disagree is
 * fine — each one is applied with the operation its own geometry calls for.
 */
extern "C" occt_shape *occt_move_faces(const occt_shape *shape,
                                       const int *ids, int n,
                                       double dx, double dy, double dz)
{
    OCCT_TRY("occt_move_faces")
    if (!shape || !ids || n <= 0) {
        set_err("occt_move_faces", "null shape/ids or n <= 0");
        return nullptr;
    }
    const gp_Vec delta(dx, dy, dz);
    if (delta.Magnitude() < 1e-9) {
        set_err("occt_move_faces", "zero move");
        return nullptr;
    }
    int bad = 0;
    TopTools_ListOfShape sel = faces_by_id(shape->s, ids, n, &bad);
    if (sel.IsEmpty()) {
        char msg[128];
        std::snprintf(msg, sizeof(msg),
                      "face %d does not exist on this body any more", bad);
        set_err("occt_move_faces", msg);
        return nullptr;
    }
    TopoDS_Shape acc = shape->s;
    for (TopTools_ListIteratorOfListOfShape it(sel); it.More(); it.Next()) {
        const TopoDS_Face f = TopoDS::Face(it.Value());
        gp_Dir outward;
        if (!face_outward(f, outward)) {
            set_err("occt_move_faces", "a selected face has no usable normal");
            return nullptr;
        }
        const double along = delta.Dot(gp_Vec(outward));
        if (std::fabs(along) < 1e-12) {
            /* Sliding a face along its own plane changes nothing about the
             * solid. Skipping it is right; failing would make a multi-face
             * move fail because one face happened to be edge-on. */
            continue;
        }
        /* v28 (S17): sweep the OBSERVABLE part of the delta, which is its
         * component along this face's own normal.
         *
         * Until v28 the prism was built from `delta` entire, and the six lines
         * above already say why that cannot be right: a delta lying wholly in
         * the face's plane is skipped BECAUSE it "changes nothing about the
         * solid". That is true, and it is true for the tangential PART of an
         * oblique delta for exactly the same reason — a planar face slid
         * inside its own plane is carried onto itself, and with the
         * neighbouring walls where they were, the face's outline is still the
         * intersection of its plane with those walls. The two statements
         * cannot both be honoured by one prism, and until now the guard held
         * one and the sweep held the other.
         *
         * What the whole delta produced instead: BRepPrimAPI_MakePrism is a
         * pure translational sweep (BRepSweep_Prism hands V to
         * BRepSweep_Translation, which does gpt.SetTranslation(V)), so the
         * prism LEANED, and the union carried an unsupported overhang on one
         * side and a re-entrant notch on the other. Neither belongs to any
         * reading of "move this face". S16 measured it — a 20-cube's top face
         * moved by (5,0,5) kept material out to z = 22 above x = 2, and out to
         * x = 25 in the bargain — and could see it with neither volume (a
         * leaning prism has volume A|delta.n|, the perpendicular answer, and
         * shearing the top face is Cavalieri-neutral) nor BRepCheck_Analyzer
         * (the union is a perfectly valid solid).
         *
         * The sharpest form of it, and the reason this is a defect rather than
         * a scoping question about tapered neighbours: moving that top face by
         * (5,0,0) returned the box untouched, by the skip above, while moving
         * it by (5,0,0.001) grew a 5 mm overhang. A 5 mm jump in the answer for
         * a 0.001 mm change in the input.
         *
         * NOT adopted: sweeping the face and letting the neighbouring WALLS
         * follow it (S16 section 5.2's reading, ray exit at 10 rather than 25).
         * That reading contradicts the skip above — a purely tangential move
         * would shear the box instead of doing nothing — it moves surfaces the
         * caller never selected, and it is precisely the operation
         * part_model.dart:3321 records the repo as deliberately not shipping
         * ("sliding its surface and re-trimming its neighbours — a
         * BRepTools_Modification subclass whose failure modes only appear on
         * real shapes"). perf/findings/S17-oblique.md section 0.2 argues it
         * out; the disagreement with S16 is registered there rather than
         * buried here.
         *
         * SCOPE, stated because the header's guarantee is what got scoped and
         * never enforced: this is exact for a PLANAR face. For a curved one
         * face_outward samples the mid-parameter normal and prism-and-fuse was
         * ill-posed before this change and is ill-posed after it — projecting
         * onto one representative normal of a cylinder is as arbitrary as
         * sweeping the whole delta was. That case is untouched and unclaimed. */
        const gp_Vec push = gp_Vec(outward) * along;
        BRepPrimAPI_MakePrism prism(f, push);
        if (!prism.IsDone()) {
            set_err("occt_move_faces", "could not sweep a selected face");
            return nullptr;
        }
        const TopoDS_Shape tool = prism.Shape();
        TopoDS_Shape next;
        if (along > 0) {
            BRepAlgoAPI_Fuse op(acc, tool);
            if (!op.IsDone()) {
                set_err("occt_move_faces", "adding the swept material failed");
                return nullptr;
            }
            next = op.Shape();
        } else {
            BRepAlgoAPI_Cut op(acc, tool);
            if (!op.IsDone()) {
                set_err("occt_move_faces",
                        "removing the swept material failed");
                return nullptr;
            }
            next = op.Shape();
        }
        if (next.IsNull() || solid_volume(next) <= 0) {
            set_err("occt_move_faces",
                    "the move would consume the body — try a smaller distance");
            return nullptr;
        }
        acc = next;
    }
    /* Booleans leave co-planar splits behind; without this a moved face comes
     * back drawn with a seam across it (the v4 unify note). */
    ShapeUpgrade_UnifySameDomain uni(acc, Standard_True, Standard_True,
                                     Standard_True);
    uni.Build();
    const TopoDS_Shape out = uni.Shape().IsNull() ? acc : uni.Shape();
    return wrap(out, "occt_move_faces");
    OCCT_CATCH("occt_move_faces", nullptr)
}

/*
 * M217 — Inventor's Direct > Scale: a uniform scale of the whole body about
 * `c`. Its own entry point rather than a matrix through occt_transform,
 * because occt_transform REFUSES a non-rigid matrix on purpose (v2) — it
 * places features, and a scale slipping through there would silently resize a
 * solid. Scaling is a deliberate command, so it gets a deliberate door.
 */
extern "C" occt_shape *occt_scale_shape(const occt_shape *shape,
                                        double cx, double cy, double cz,
                                        double factor)
{
    OCCT_TRY("occt_scale_shape")
    if (!shape) {
        set_err("occt_scale_shape", "null shape");
        return nullptr;
    }
    if (!(factor > 1e-9) || !std::isfinite(factor)) {
        set_err("occt_scale_shape", "scale factor must be positive");
        return nullptr;
    }
    gp_Trsf t;
    t.SetScale(gp_Pnt(cx, cy, cz), factor);
    BRepBuilderAPI_Transform op(shape->s, t, Standard_True);
    if (!op.IsDone()) {
        set_err("occt_scale_shape", "scaling failed");
        return nullptr;
    }
    return wrap(op.Shape(), "occt_scale_shape");
    OCCT_CATCH("occt_scale_shape", nullptr)
}

/* ---- lifecycle -------------------------------------------------------------- */

extern "C" void occt_free_shape(occt_shape *shape)
{
    delete shape; /* delete nullptr is a no-op */
}

/* ---- v12: revolve, edge identity, fillet/chamfer, ray casting ----------- */

/* Signed offset of (x,y) from the 2D line through (px,py) along (dx,dy).
 * Only the SIGN is used — it says which side of the revolve axis a profile
 * vertex sits on. */
static double axis_side(double px, double py, double dx, double dy,
                        double x, double y)
{
    return dx * (y - py) - dy * (x - px);
}

/* The face a chamfer measures its first distance on. OCCT needs one to
 * disambiguate the two asymmetric methods; the ancestor map's first entry is
 * deterministic for a given shape, which is all the caller needs in order to
 * offer a stable "Flip". Null face when the edge is a free boundary. */
static TopoDS_Face edge_ref_face(
    const TopTools_IndexedDataMapOfShapeListOfShape &edgeFaces,
    const TopoDS_Edge &edge)
{
    if (!edgeFaces.Contains(edge))
        return TopoDS_Face();
    const TopTools_ListOfShape &fl = edgeFaces.FindFromKey(edge);
    if (fl.IsEmpty())
        return TopoDS_Face();
    return TopoDS::Face(fl.First());
}

extern "C" occt_shape *occt_revolve_profile(const double *xyb,
                                            const int *loop_counts, int nloops,
                                            double ax_px, double ax_py,
                                            double ax_dx, double ax_dy,
                                            double angle_deg)
{
    OCCT_TRY("occt_revolve_profile")
    if (!xyb || !loop_counts || nloops < 1) {
        set_err("occt_revolve_profile", "null profile arguments");
        return nullptr;
    }
    if (!(angle_deg > 0.0) || angle_deg > 360.0 + 1e-9) {
        set_err("occt_revolve_profile", "angle must be in (0, 360] deg");
        return nullptr;
    }
    const double alen = std::sqrt(ax_dx * ax_dx + ax_dy * ax_dy);
    if (!(alen > 1e-12)) {
        set_err("occt_revolve_profile", "axis direction is degenerate");
        return nullptr;
    }
    ax_dx /= alen;
    ax_dy /= alen;
    for (int l = 0; l < nloops; ++l) {
        if (loop_counts[l] < 2) {
            set_err("occt_revolve_profile",
                    "every loop needs at least 2 vertices");
            return nullptr;
        }
    }

    /* The profile must stay on ONE side of the axis. A profile straddling it
     * sweeps through itself and OCCT either fails deep inside the sweeper or,
     * worse, returns a self-intersecting solid that only shows up as a broken
     * boolean three features later. Inventor rejects it up front, so do that
     * here — with a tolerance scaled to the profile, not an absolute epsilon,
     * because a profile whose edge merely TOUCHES the axis (the common case:
     * a shaft revolved about its own centreline) is legal and must pass. */
    {
        int ntot = 0;
        for (int l = 0; l < nloops; ++l)
            ntot += loop_counts[l];
        double scale = 0.0;
        for (int i = 0; i < ntot; ++i) {
            const double s =
                std::fabs(axis_side(ax_px, ax_py, ax_dx, ax_dy,
                                    xyb[3 * i], xyb[3 * i + 1]));
            if (s > scale)
                scale = s;
        }
        const double tol = 1e-7 * (scale + 1.0);
        bool anyPos = false, anyNeg = false;
        for (int i = 0; i < ntot; ++i) {
            const double s = axis_side(ax_px, ax_py, ax_dx, ax_dy,
                                       xyb[3 * i], xyb[3 * i + 1]);
            if (s > tol)
                anyPos = true;
            if (s < -tol)
                anyNeg = true;
        }
        if (anyPos && anyNeg) {
            set_err("occt_revolve_profile",
                    "profile crosses the axis of revolution");
            return nullptr;
        }
    }

    const gp_Ax1 axis(gp_Pnt(ax_px, ax_py, 0.0), gp_Dir(ax_dx, ax_dy, 0.0));
    const double angle_rad = angle_deg * M_PI / 180.0;
    /* Same explicit +Z profile plane as occt_extrude_profile_arcs: inferring
     * it from the wire makes the normal follow the winding, which swaps
     * material and hole. See the long note there. */
    const gp_Pln profilePln(gp_Ax3(gp_Pnt(0, 0, 0), gp_Dir(0, 0, 1)));

    const double *p = xyb;
    bool ok = false;
    const double a0 = arc_loop_signed_area(p, loop_counts[0]);
    if (std::fabs(a0) < 1e-12) {
        set_err("occt_revolve_profile", "outer loop is degenerate");
        return nullptr;
    }
    TopoDS_Wire outer = arc_loop_wire(p, loop_counts[0], a0 > 0.0, &ok);
    if (!ok) {
        set_err("occt_revolve_profile", "outer wire construction failed");
        return nullptr;
    }
    BRepBuilderAPI_MakeFace faceMk(profilePln, outer, Standard_True);
    if (!faceMk.IsDone()) {
        set_err("occt_revolve_profile",
                "outer loop is not a valid planar face (self-intersecting?)");
        return nullptr;
    }
    p += 3 * loop_counts[0];

    BRepPrimAPI_MakeRevol rev(faceMk.Face(), axis, angle_rad);
    if (!rev.IsDone()) {
        set_err("occt_revolve_profile", "revolution of the outer loop failed");
        return nullptr;
    }
    TopoDS_Shape body = rev.Shape();

    /* Holes are revolved separately and cut, for the same reason the extrude
     * path cuts them: multi-wire faces came back with the HOLE as the
     * material. Every tool is a full solid of revolution built through the
     * proven single-wire path. */
    for (int l = 1; l < nloops; ++l) {
        const double a = arc_loop_signed_area(p, loop_counts[l]);
        if (std::fabs(a) < 1e-12) {
            set_err("occt_revolve_profile", "hole loop is degenerate");
            return nullptr;
        }
        TopoDS_Wire holeW = arc_loop_wire(p, loop_counts[l], a > 0.0, &ok);
        if (!ok) {
            set_err("occt_revolve_profile", "hole wire construction failed");
            return nullptr;
        }
        BRepBuilderAPI_MakeFace holeMk(profilePln, holeW, Standard_True);
        if (!holeMk.IsDone()) {
            set_err("occt_revolve_profile",
                    "hole loop is not a valid planar face");
            return nullptr;
        }
        BRepPrimAPI_MakeRevol holeRev(holeMk.Face(), axis, angle_rad);
        if (!holeRev.IsDone()) {
            set_err("occt_revolve_profile", "revolution of a hole failed");
            return nullptr;
        }
        BRepAlgoAPI_Cut cut(body, holeRev.Shape());
        if (!cut.IsDone() || !has_solid_material(cut.Shape())) {
            set_err("occt_revolve_profile",
                    "cutting a hole out of the revolution failed");
            return nullptr;
        }
        body = cut.Shape();
        p += 3 * loop_counts[l];
    }

    /* A full 360 revolution of an arc-built profile arrives as several
     * same-surface patches split at the seam, exactly like the two-half-arc
     * circle in the extrude path. Merge them so the display shows one
     * cylindrical/toroidal face and no phantom meridian lines. */
    ShapeUpgrade_UnifySameDomain uni(body, Standard_True, Standard_True,
                                     Standard_False);
    uni.Build();
    return wrap(uni.Shape(), "occt_revolve_profile");
    OCCT_CATCH("occt_revolve_profile", nullptr)
}

extern "C" int occt_shape_edge_count(const occt_shape *shape)
{
    OCCT_TRY("occt_shape_edge_count")
    if (!shape) {
        set_err("occt_shape_edge_count", "null shape");
        return -1;
    }
    TopTools_IndexedMapOfShape m;
    TopExp::MapShapes(shape->s, TopAbs_EDGE, m);
    return m.Extent();
    OCCT_CATCH("occt_shape_edge_count", -1)
}

/* Outward unit normal of [face] at the point on [edge] with parameter t.
 * Honours the face orientation, which is what makes it OUTWARD rather than
 * merely normal to the surface. */
static bool face_outward_normal(const TopoDS_Face &face, const TopoDS_Edge &edge,
                                double t, gp_Dir &out)
{
    Standard_Real f = 0, l = 0;
    Handle(Geom2d_Curve) pc = BRep_Tool::CurveOnSurface(edge, face, f, l);
    if (pc.IsNull())
        return false;
    const gp_Pnt2d uv = pc->Value(t);
    BRepAdaptor_Surface surf(face, Standard_False);
    gp_Pnt p;
    gp_Vec du, dv;
    surf.D1(uv.X(), uv.Y(), p, du, dv);
    gp_Vec n = du.Crossed(dv);
    if (n.Magnitude() < 1e-12)
        return false;
    n.Normalize();
    if (face.Orientation() == TopAbs_REVERSED)
        n.Reverse();
    out = gp_Dir(n);
    return true;
}

/* Orientation of `edge` where it sits in `face`'s own boundary traversal, by
 * SCANNING the face. The first occurrence wins — a seam edge appears twice,
 * once each way, and taking the first is what this has always done.
 *
 * v21 note: this scan is O(edges of the face) and is asked twice per edge.
 * On an n-gon prism — the profile's own fixture — the two end faces carry n
 * edges each and two thirds of all edges touch one, so an enumeration pays
 * 2n x O(n). See edge_info_ctx::edge_orientation_in for the index that
 * replaces it when the whole shape is being enumerated, and §6.5 of the
 * profile for why that matters. */
static bool edge_ori_in_face(const TopoDS_Face &face, const TopoDS_Edge &edge,
                             TopAbs_Orientation &out)
{
    for (TopExp_Explorer ex(face, TopAbs_EDGE); ex.More(); ex.Next()) {
        if (ex.Current().IsSame(edge)) {
            out = ex.Current().Orientation();
            return true;
        }
    }
    return false;
}

/* Unit direction that leaves [edge] and runs INTO [face], tangent to it, given
 * the edge's orientation in that face's own boundary traversal.
 *
 * Built from the edge tangent oriented along that traversal: with an outward
 * normal and a CCW outer loop seen from outside, the interior lies to the
 * left, i.e. along nOut x T. Taking the orientation from the face (rather than
 * assuming FORWARD) is what makes this work for the second face of the pair,
 * where the shared edge is traversed the other way.
 *
 * The orientation arrives as an argument rather than being looked up here, so
 * that the bulk path can serve it from a per-shape index and the single-edge
 * path from a scan, with not one line of the geometry duplicated between
 * them. */
static bool into_face_dir_with_ori(const TopoDS_Edge &edge, double t,
                                   const gp_Dir &nOut, TopAbs_Orientation ori,
                                   gp_Dir &out)
{
    BRepAdaptor_Curve c(edge);
    gp_Pnt p;
    gp_Vec d1;
    c.D1(t, p, d1);
    if (d1.Magnitude() < 1e-12)
        return false;
    d1.Normalize();
    if (ori == TopAbs_REVERSED)
        d1.Reverse();
    const gp_Vec u = gp_Vec(nOut).Crossed(d1);
    if (u.Magnitude() < 1e-12)
        return false;
    out = gp_Dir(u);
    return true;
}

/*
 * v21 — everything one edge query derives from the WHOLE SHAPE rather than
 * from the edge it was asked about.
 *
 * This struct exists because of a measurement. `occt_shape_edge_info` used to
 * build all four of these inline, per call, and throw them away; enumerating
 * every edge of a solid therefore cost n x Θ(n). PERFORMANCE_PROFILE.md §6.5
 * measures that as k = 2.012 [1.910, 2.113], R² = 1.0000, against a control
 * doing strictly more work at k = 1.063 — 200.3x at 1440 edges, and an
 * extrapolated 56.4 s on the part that died in the field.
 *
 * None of the four depends on `index`:
 *   - MapShapes(EDGE)                is a pure function of the shape
 *   - MapShapesAndAncestors(E, F)    is a pure function of the shape
 *   - the bounding box, hence `step`, is a pure function of the shape
 *   - the solid classifier is LOADED with the shape and then asked about
 *     points; construction is the expensive half, Perform is the query
 *
 * So one context per SHAPE serves every edge, and edge_info_one below cannot
 * tell whether it was handed a context built for it alone (the single-edge
 * entry point, whose cost is therefore exactly what it always was) or one
 * shared across an enumeration (the bulk entry point). That is what makes the
 * two paths bit-identical by construction rather than by testing — though
 * smoke scenario [35] tests it anyway, on all twelve doubles, exactly.
 *
 * Each member is built LAZILY, so the single-edge path still performs exactly
 * the operations it performed before, in the same order, and no others: a
 * degenerate edge returns before the ancestor map is ever needed, and an edge
 * with other than two adjacent faces never reaches the classifier.
 */
struct edge_info_ctx
{
    const TopoDS_Shape &s;
    TopTools_IndexedMapOfShape edges;

    /* `shared` = this context will serve EVERY edge of the shape, so indices
     * whose build cost is Θ(shape) pay for themselves. A context built for one
     * query leaves them alone: that path is this branch's control and must
     * cost exactly what it always did.
     *
     * `classifier_convexity` = decide field 11 the pre-v22 way, with
     * BRepClass3d_SolidClassifier. TEST ONLY — see convexity_sign and
     * occt_shape_edges_info_ref. Nothing the app calls sets it. */
    explicit edge_info_ctx(const TopoDS_Shape &sh, bool shared = false,
                           bool classifier_convexity = false)
        : s(sh), m_shared(shared), m_cls_convexity(classifier_convexity)
    {
        TopExp::MapShapes(s, TopAbs_EDGE, edges);
    }

    bool convexity_by_classifier() const { return m_cls_convexity; }

    const TopTools_IndexedDataMapOfShapeListOfShape &faces()
    {
        if (!m_faces_done) {
            TopExp::MapShapesAndAncestors(s, TopAbs_EDGE, TopAbs_FACE,
                                          m_edge_faces);
            m_faces_done = true;
        }
        return m_edge_faces;
    }

    /* The distance to step off the edge before asking the solid where we
     * landed: 1/1000 of the shape's diagonal, exactly as the per-call code
     * computed it. */
    double classifier_step()
    {
        if (!m_step_done) {
            Bnd_Box bb;
            BRepBndLib::Add(s, bb);
            m_step = 1.0e-3 * (bb.IsVoid() ? 1.0 : sqrt(bb.SquareExtent()));
            m_step_done = true;
        }
        return m_step;
    }

    BRepClass3d_SolidClassifier &classifier()
    {
        if (!m_cls)
            m_cls.reset(new BRepClass3d_SolidClassifier(s));
        return *m_cls;
    }

    /* Orientation of `edge` where it sits in `face`'s boundary traversal.
     *
     * THE SECOND QUADRATIC. Hoisting the four whole-shape objects took a
     * factor of ~20 out of the constant and left the exponent at k = 1.909
     * [1.887, 1.932] (Lane C, shim v21, four rungs, R² = 0.9999) — measured,
     * not guessed, and it refuted the prediction that the exponent would fall
     * to 1. What remained is this: `edge_ori_in_face` scans the face's edges
     * to find the one it was asked about, and is asked twice per edge. On the
     * fixture the profile ladders over — an n-gon prism, two end faces of n
     * edges each and n side faces of four — two thirds of all edges touch an
     * end face, so an enumeration performs 2n × O(n) explorer steps.
     *
     * Lane C's allocation counters fit that arithmetic and not much else:
     * allocations per edge come to 12.25·n + 290 over four rungs, exactly
     * linear in n, which is a per-edge cost proportional to the FACE being
     * scanned. The classifier hypothesis Session 1 raised fits the totals too
     * — the discriminator is that this scan is a plain O(n) loop visible in
     * the source, and removing it is free.
     *
     * The index is built PER FACE, on first request, by exploring the very
     * TopoDS_Face object the caller passed. Not from a separate MapShapes
     * pass: a face reached through the ancestor map and a face reached through
     * MapShapes could in principle differ in orientation, and every edge
     * orientation the explorer reports is composed with the face's. Exploring
     * the caller's own object removes that question rather than answering it.
     * The guard below covers the remaining case — a second face that is IsSame
     * to an indexed one but oriented the other way falls back to the scan.
     *
     * Total build cost is one explorer pass per face, i.e. Θ(face-edge
     * incidences) = Θ(E) on a manifold solid, against the Θ(E·F) it replaces.
     */
    bool edge_orientation_in(const TopoDS_Face &face, const TopoDS_Edge &edge,
                             TopAbs_Orientation &out)
    {
        if (!m_shared)
            return edge_ori_in_face(face, edge, out);
        if (m_face_idx.Extent() == 0)
            TopExp::MapShapes(s, TopAbs_FACE, m_face_idx);
        const int fi = m_face_idx.FindIndex(face);
        const int ei = edges.FindIndex(edge);
        if (fi < 1 || ei < 1)
            return edge_ori_in_face(face, edge, out);
        if (m_row_ori.size() < (size_t)m_face_idx.Extent() + 1) {
            m_row_ori.assign((size_t)m_face_idx.Extent() + 1,
                             (signed char)-1);
        }
        const signed char have = m_row_ori[(size_t)fi];
        if (have < 0) {
            /* First question about this face: index it, from THIS object. */
            for (TopExp_Explorer ex(face, TopAbs_EDGE); ex.More(); ex.Next()) {
                const int k = edges.FindIndex(ex.Current());
                if (k < 1)
                    continue;
                /* emplace, not assignment: the FIRST occurrence wins, which is
                 * what the scan's `break` did. A seam edge appears twice. */
                m_ori.emplace(ori_key(fi, k),
                              (int)ex.Current().Orientation());
            }
            m_row_ori[(size_t)fi] = (signed char)face.Orientation();
        } else if (have != (signed char)face.Orientation()) {
            /* Same face by IsSame, opposite orientation: its edges would come
             * back composed the other way. Do not serve those from the index. */
            return edge_ori_in_face(face, edge, out);
        }
        const std::unordered_map<unsigned long long, int>::const_iterator it =
            m_ori.find(ori_key(fi, ei));
        if (it == m_ori.end())
            return false; /* not on this face — same answer the scan gives */
        out = (TopAbs_Orientation)it->second;
        return true;
    }

    /* Throw the shared classifier away after a failed query. The per-edge path
     * this replaces built a fresh one every time, so a classifier left in a
     * bad state by one edge could not affect the next; sharing one across an
     * enumeration would break that, and a WRONG convexity is far worse than a
     * slow one — it is what decides fillet from round, and it is persisted
     * into the fingerprint a blend is reattached by. */
    void forget_classifier() { m_cls.reset(); }

  private:
    static unsigned long long ori_key(int face_idx, int edge_idx)
    {
        return ((unsigned long long)(unsigned)face_idx << 32) |
               (unsigned long long)(unsigned)edge_idx;
    }

    const bool m_shared;
    const bool m_cls_convexity;
    bool m_faces_done = false;
    TopTools_IndexedDataMapOfShapeListOfShape m_edge_faces;
    bool m_step_done = false;
    double m_step = 0.0;
    std::unique_ptr<BRepClass3d_SolidClassifier> m_cls;
    /* Face-edge orientation index, shared path only. m_row_ori[i] is -1 until
     * face i has been indexed, then holds the orientation of the face object
     * it was indexed from. */
    TopTools_IndexedMapOfShape m_face_idx;
    std::vector<signed char> m_row_ori;
    std::unordered_map<unsigned long long, int> m_ori;
};

/*
 * v22 — CONVEXITY: +1 exterior corner (a "round"), -1 interior corner (a
 * "fillet"). This is field 11, and it is the only field this function decides.
 *
 * THE LOCAL TEST. u1 leaves the edge into face 1, u2 into face 2, both
 * perpendicular to the edge and tangent to their face. Write T for the edge
 * tangent along face 1's own boundary traversal, so u1 = n1 x T and
 * u2 = n2 x (-T). Then
 *
 *     u1 . n2  =  (n1 x T) . n2  =  T . (n2 x n1)  =  u2 . n1
 *
 * identically -- the two dot products are the same number, so there is no
 * second opinion available from computing both. Its sign is the answer:
 * walking into face 1 takes you to the INNER side of face 2's tangent plane
 * exactly when the corner is exterior.
 *
 * WHAT IT REPLACED, AND WHY. Until v21 this stepped ‖bbox diagonal‖/1000 along
 * the bisector of u1 and u2 and asked BRepClass3d_SolidClassifier whether the
 * point had landed in the solid. Two problems, one of cost and one of
 * correctness, and the second is the one that matters:
 *
 *   COST. BRepClass3d_SClassifier::Perform is Theta(shape) per call -- it
 *   rebuilds the whole solid's edge->face ancestor map every time
 *   (BRepClass3d_SClassifier.cxx:227 in V7_9_3) and intersects its ray against
 *   every face, because RejectShell and RejectFace return Standard_False
 *   unconditionally (BRepClass3d_SolidExplorer.cxx:1025, :1075). One call per
 *   edge is therefore Theta(E*F): measured at 98.6 % of a whole enumeration
 *   and k = 1.889 [1.755, 2.023] on the profile's own ladder fixture.
 *   perf/findings/S6-shim2.md §4.
 *
 *   CORRECTNESS. The step is a property of the WHOLE SHAPE and is not scaled
 *   to local feature size, and the bisector stands at 45 degrees to each face
 *   of a square corner, so the probe crosses any wall thinner than
 *   ‖diagonal‖/(1000*sqrt(2)) and answers about the far side of it. A box is
 *   a convex solid; a 200 x 0.1 x 20 box has eight of its twelve edges
 *   reported CONCAVE by the classifier path. That is not a tie between two
 *   opinions. Measured threshold and sweep: S6-shim2.md §5.1, pinned by smoke
 *   scenario [36].
 *
 * The classifier path is kept, reachable only through
 * occt_shape_edges_info_ref, so that [36] can compare the two in one run on
 * one machine -- which is what proves the claim, where a recorded golden
 * would only pin one machine's digits (OPTIMIZATION_PLAN_2.md §1.4).
 */
static double convexity_sign(edge_info_ctx &ctx, const gp_Pnt &pm, gp_Vec m,
                             const gp_Dir &n2, const gp_Dir &u1)
{
    if (!ctx.convexity_by_classifier())
        return (u1.Dot(n2) < 0.0) ? 1.0 : -1.0;

    /* Reference path: pre-v22 behaviour, byte for byte. Test-only. `m` is
     * taken BY VALUE and normalised here rather than at the call site, so the
     * shipping path does not pay a square root it has no use for. */
    m.Normalize();
    const double step = ctx.classifier_step();
    BRepClass3d_SolidClassifier &cls = ctx.classifier();
    cls.Perform(pm.Translated(m * step), 1.0e-7);
    return (cls.State() == TopAbs_IN) ? 1.0 : -1.0;
}

/*
 * The twelve doubles for ONE edge, 1-based `index` into ctx.edges.
 *
 * This is the body `occt_shape_edge_info` has always had, moved verbatim so
 * that the single-edge and bulk entry points cannot drift apart. Returns 1 on
 * success, 0 if the edge could not be read at all.
 */
static int edge_info_one(edge_info_ctx &ctx, int index, double *out12)
{
    double *out10 = out12; /* first ten fields are unchanged since v12 */
    const TopoDS_Edge edge = TopoDS::Edge(ctx.edges.FindKey(index));
    for (int i = 0; i < 12; ++i)
        out12[i] = 0.0;
    if (BRep_Tool::Degenerated(edge))
        return 1; /* type 0, zero length — an honest "nothing here" */

    BRepAdaptor_Curve c(edge);
    const double len = GCPnts_AbscissaPoint::Length(c);
    /* Midpoint by ARC LENGTH, not by parameter: on a B-spline the parametric
     * midpoint wanders as the curve is rebuilt, and this point is the anchor
     * a fillet is re-matched against after a recompute. Arc length is a
     * geometric property of the curve, so it stays put. */
    double tmid = 0.5 * (c.FirstParameter() + c.LastParameter());
    if (len > 1e-12) {
        GCPnts_AbscissaPoint ap(c, len * 0.5, c.FirstParameter());
        if (ap.IsDone())
            tmid = ap.Parameter();
    }
    gp_Pnt pm;
    gp_Vec d1;
    c.D1(tmid, pm, d1);
    if (d1.Magnitude() > 1e-12)
        d1.Normalize();

    switch (c.GetType()) {
    case GeomAbs_Line:
        out10[0] = 1;
        break;
    case GeomAbs_Circle:
        out10[0] = 2;
        out10[8] = c.Circle().Radius();
        break;
    case GeomAbs_Ellipse:
        out10[0] = 3;
        out10[8] = c.Ellipse().MajorRadius();
        break;
    default:
        out10[0] = 4;
        break;
    }
    out10[1] = pm.X();
    out10[2] = pm.Y();
    out10[3] = pm.Z();
    out10[4] = d1.X();
    out10[5] = d1.Y();
    out10[6] = d1.Z();
    out10[7] = len;

    const TopTools_IndexedDataMapOfShapeListOfShape &edgeFaces = ctx.faces();
    out10[9] = edgeFaces.Contains(edge)
                   ? (double)edgeFaces.FindFromKey(edge).Extent()
                   : 0.0;

    /* v13 — dihedral angle and CONVEXITY, which is what tells a fillet
     * (concave, interior corner) from a round (convex, exterior corner) and so
     * what Inventor's "All Fillets" / "All Rounds" select on.
     *
     * Sign by classification rather than by juggling normal and tangent
     * orientations: step a short way from the edge along the INWARD average
     * normal and ask the solid whether that point is inside. Inside means the
     * material wraps around the edge from outside, i.e. a convex edge. It is
     * one classifier call per edge and immune to the face-orientation traps
     * that make the cross-product formulations fragile. */
    if (out10[9] == 2.0) {
        const TopTools_ListOfShape &fl = edgeFaces.FindFromKey(edge);
        const TopoDS_Face f1 = TopoDS::Face(fl.First());
        const TopoDS_Face f2 = TopoDS::Face(fl.Last());
        gp_Dir n1, n2, u1, u2;
        if (face_outward_normal(f1, edge, tmid, n1) &&
            face_outward_normal(f2, edge, tmid, n2)) {
            const double c = std::max(-1.0, std::min(1.0, n1.Dot(n2)));
            out12[10] = std::acos(c) * 180.0 / M_PI;
            /* v22 — the sign comes from the two INTO-FACE DIRECTIONS, and
             * from nothing else. See convexity_sign below for what this
             * replaced and why; the guards around it are unchanged, so
             * exactly the same set of edges receives a sign as before.
             *
             * (The historical note that belongs here: the FIRST attempt at a
             * local test averaged the two NORMALS and reported every edge
             * convex, because stepping inward along the averaged normal lands
             * in material for a concave edge just as much as for a convex
             * one. That failure is what sent this code to a solid classifier.
             * It was the wrong local test, not a proof that local tests
             * cannot work: walking into the FACES discriminates, and the
             * bisector's sign against the opposite face's normal is the
             * discrimination.) */
            TopAbs_Orientation o1 = TopAbs_FORWARD, o2 = TopAbs_FORWARD;
            if (out12[10] > 1.0e-3 &&
                ctx.edge_orientation_in(f1, edge, o1) &&
                into_face_dir_with_ori(edge, tmid, n1, o1, u1) &&
                ctx.edge_orientation_in(f2, edge, o2) &&
                into_face_dir_with_ori(edge, tmid, n2, o2, u2)) {
                gp_Vec m(u1.XYZ() + u2.XYZ());
                if (m.Magnitude() > 1e-9)
                    out12[11] = convexity_sign(ctx, pm, m, n2, u1);
            }
        }
    }
    return 1;
}

extern "C" int occt_shape_edge_info(const occt_shape *shape, int index,
                                    double *out12)
{
    OCCT_TRY("occt_shape_edge_info")
    if (!shape || !out12) {
        set_err("occt_shape_edge_info", "null argument");
        return 0;
    }
    edge_info_ctx ctx(shape->s);
    if (index < 1 || index > ctx.edges.Extent()) {
        set_err("occt_shape_edge_info", "edge index out of range");
        return 0;
    }
    return edge_info_one(ctx, index, out12);
    OCCT_CATCH("occt_shape_edge_info", 0)
}

/*
 * v21 — every edge's record in ONE traversal. See occt_capi.h for the
 * contract and edge_info_ctx above for why this is not merely a convenience
 * wrapper around the call above.
 *
 * A failure on ONE edge does not abandon the enumeration. The per-edge path it
 * replaces was called from Dart in a loop that dropped a null result and
 * carried on, so abandoning the whole array here would be a behaviour change
 * on exactly the malformed shapes where behaviour matters most. Such an edge
 * gets type -1 — outside the documented 0..4 range — and the caller drops it,
 * which reproduces the old loop exactly. Type 0 still means "degenerate edge,
 * legitimately empty" and is still KEPT.
 */
extern "C" int occt_shape_edges_info(const occt_shape *shape, double *out12n,
                                     int cap)
{
    OCCT_TRY("occt_shape_edges_info")
    if (!shape || !out12n) {
        set_err("occt_shape_edges_info", "null argument");
        return -1;
    }
    edge_info_ctx ctx(shape->s, /*shared=*/true);
    const int n = ctx.edges.Extent();
    if (cap < n) {
        set_err("occt_shape_edges_info", "output buffer too small");
        return -1;
    }
    for (int i = 1; i <= n; ++i) {
        double *rec = out12n + 12 * (i - 1);
        try {
            if (!edge_info_one(ctx, i, rec))
                rec[0] = -1.0;
        } catch (const Standard_Failure &) {
            for (int k = 0; k < 12; ++k)
                rec[k] = 0.0;
            rec[0] = -1.0;
            ctx.forget_classifier();
        } catch (...) {
            for (int k = 0; k < 12; ++k)
                rec[k] = 0.0;
            rec[0] = -1.0;
            ctx.forget_classifier();
        }
    }
    return n;
    OCCT_CATCH("occt_shape_edges_info", -1)
}

/*
 * v22 — TEST ONLY. occt_shape_edges_info with field 11 decided the pre-v22
 * way, by BRepClass3d_SolidClassifier.
 *
 * It exists so that the shipping path can be compared against the path it
 * replaced **in one run, on one machine** — smoke scenario [36] — which is
 * what makes the comparison a proof of equivalence rather than a record of
 * one machine's digits. OPTIMIZATION_PLAN_2.md §1.4 is the rule and the
 * cautionary tale behind it.
 *
 * It is deliberately NOT bound in frontend/lib/ffi/occt_engine.dart and no
 * application code may call it: on shapes with a feature thinner than
 * ‖bbox diagonal‖/1414 it returns WRONG convexity signs, which is why v22
 * stopped using it. See convexity_sign.
 */
extern "C" int occt_shape_edges_info_ref(const occt_shape *shape,
                                         double *out12n, int cap)
{
    OCCT_TRY("occt_shape_edges_info_ref")
    if (!shape || !out12n) {
        set_err("occt_shape_edges_info_ref", "null argument");
        return -1;
    }
    edge_info_ctx ctx(shape->s, /*shared=*/true, /*classifier_convexity=*/true);
    const int n = ctx.edges.Extent();
    if (cap < n) {
        set_err("occt_shape_edges_info_ref", "output buffer too small");
        return -1;
    }
    for (int i = 1; i <= n; ++i) {
        double *rec = out12n + 12 * (i - 1);
        try {
            if (!edge_info_one(ctx, i, rec))
                rec[0] = -1.0;
        } catch (const Standard_Failure &) {
            for (int k = 0; k < 12; ++k)
                rec[k] = 0.0;
            rec[0] = -1.0;
            ctx.forget_classifier();
        } catch (...) {
            for (int k = 0; k < 12; ++k)
                rec[k] = 0.0;
            rec[0] = -1.0;
            ctx.forget_classifier();
        }
    }
    return n;
    OCCT_CATCH("occt_shape_edges_info_ref", -1)
}

extern "C" int occt_mesh_edge_ids(const occt_mesh *m, int *out)
{
    OCCT_TRY("occt_mesh_edge_ids")
    if (!m || !out) {
        set_err("occt_mesh_edge_ids", "null argument");
        return 0;
    }
    for (size_t i = 0; i < m->edge_ids.size(); ++i)
        out[i] = m->edge_ids[i];
    return 1;
    OCCT_CATCH("occt_mesh_edge_ids", 0)
}

extern "C" int occt_mesh_face_ids(const occt_mesh *m, int *out)
{
    OCCT_TRY("occt_mesh_face_ids")
    if (!m || !out) {
        set_err("occt_mesh_face_ids", "null argument");
        return 0;
    }
    for (size_t i = 0; i < m->face_ids.size(); ++i)
        out[i] = m->face_ids[i];
    return 1;
    OCCT_CATCH("occt_mesh_face_ids", 0)
}

/* ---- v16: a fillet and chamfer that cannot hand back a broken solid ------ */

/* Volume of a shape, or -1 when it has none. Used only as a CATASTROPHE
 * guard: a blend nudges a solid, it never doubles or annihilates it. */
static double solid_volume(const TopoDS_Shape &s)
{
    if (s.IsNull())
        return -1.0;
    GProp_GProps props;
    BRepGProp::VolumeProperties(s, props);
    const double v = props.Mass();
    return (v > 0.0 && std::isfinite(v)) ? v : -1.0;
}

/* Would we hand this shape to the rest of the app?
 *
 * IsDone() is necessary and NOT sufficient. BRepFilletAPI reports success and
 * still returns solids that fail BRepCheck_Analyzer — a long-standing OCCT
 * behaviour (self-intersecting wires, invalid pcurves on the blend faces).
 * Downstream that surfaces as a mesher that grinds for ten seconds and emits
 * sixty thousand triangles for a twenty-face solid, which is exactly the
 * "the fillet looks broken" report this function exists to stop.
 *
 * `base_vol` is the volume before the blend, or -1 to skip the volume gate. */
static bool blend_result_ok(const TopoDS_Shape &out, double base_vol)
{
    if (!has_solid_material(out))
        return false;
    const double v = solid_volume(out);
    if (base_vol > 0.0) {
        /* A blend trims or pads the corners of a body. Ten percent of the
         * original volume left, or triple it, means the builder produced
         * something that is not a blend of this body at all. The bounds are
         * deliberately loose: they catch catastrophes, not design choices. */
        if (!(v > 0.0) || v < 0.1 * base_vol || v > 3.0 * base_vol)
            return false;
    } else if (!(v > 0.0)) {
        return false;
    }
    return BRepCheck_Analyzer(out).IsValid() == Standard_True;
}

/* The relative sizes a blend is retried at.
 *
 * OCCT cannot build a blend that lands EXACTLY on a tangency — a 2 mm fillet
 * on a 2 mm wall, or the 5 mm fillet on a 10 mm cube of OCCT issue #172, open
 * since 2010. The arc consumes the whole face, the walking algorithm has no
 * linear segment left to walk, and Build() reports failure. One part in a
 * thousand smaller and the same fillet builds without complaint.
 *
 * Refusing is the wrong answer: a full quarter-round is an ordinary, buildable
 * piece of design intent that every other CAD system produces. So retry a
 * hair under the asked-for size. The ladder tops out at one part in a
 * thousand — 2 micrometres on a 2 mm fillet, which is below the tolerance of
 * any process that could make the part and far below anything the display can
 * resolve, but still a thousand times OCCT's own Precision::Confusion. The
 * caller is TOLD which rung was used; nothing here is hidden. */
static const double kBlendScales[] = {1.0, 1.0 - 1.0e-6, 1.0 - 1.0e-5,
                                      1.0 - 1.0e-4, 1.0 - 1.0e-3};
static const int kBlendScaleCount = 5;

/* Hard ceiling on builds per call, so a pathological body cannot wedge the
 * app in a retry storm. Each build is O(100 ms) on a phone-class core, and
 * only a FAILING blend ever gets past the first rung — the common case is one
 * build. Sized so the salvage path below completes for the edge counts a
 * person actually picks by hand: probing four edges singly, then rebuilding
 * the survivors, fits inside it with room to spare. */
static const int kBlendBuildBudget = 64;

/* One fillet build at a given size and surface representation. Returns the
 * result shape (null when the attempt failed) and never throws. */
static TopoDS_Shape try_fillet_build(const TopoDS_Shape &base,
                                     const TopTools_IndexedMapOfShape &emap,
                                     const std::vector<int> &use,
                                     const int *edge_ids, const double *radii,
                                     const double *radii2, double scale,
                                     ChFi3d_FilletShape fshape, double base_vol)
{
    try {
        BRepFilletAPI_MakeFillet mk(base, fshape);
        int added = 0;
        for (size_t k = 0; k < use.size(); ++k) {
            const int i = use[k];
            const TopoDS_Edge e = TopoDS::Edge(emap.FindKey(edge_ids[i]));
            if (BRep_Tool::Degenerated(e))
                continue;
            const double r1 = radii[i] * scale;
            if (radii2 && radii2[i] > 0.0 &&
                std::fabs(radii2[i] - radii[i]) > 1.0e-12)
                mk.Add(r1, radii2[i] * scale, e);
            else
                mk.Add(r1, e);
            ++added;
        }
        if (added == 0)
            return TopoDS_Shape();
        mk.Build();
        if (!mk.IsDone())
            return TopoDS_Shape();
        const TopoDS_Shape out = mk.Shape();
        if (!blend_result_ok(out, base_vol))
            return TopoDS_Shape();
        return out;
    } catch (const Standard_Failure &) {
        /* BRepFilletAPI throws out of Build() on some inputs rather than
         * reporting NotDone. Swallowing it here is what makes the ladder
         * able to carry on to the next rung. */
        return TopoDS_Shape();
    } catch (...) {
        return TopoDS_Shape();
    }
}

/* One chamfer build at a given size. Mirrors try_fillet_build. */
static TopoDS_Shape try_chamfer_build(
    const TopoDS_Shape &base, const TopTools_IndexedMapOfShape &emap,
    const TopTools_IndexedDataMapOfShapeListOfShape &edgeFaces,
    const std::vector<int> &use, const int *edge_ids, const int *modes,
    const double *d1, const double *d2, const double *angle_deg, double scale,
    double base_vol)
{
    try {
        BRepFilletAPI_MakeChamfer mk(base);
        int added = 0;
        for (size_t k = 0; k < use.size(); ++k) {
            const int i = use[k];
            const TopoDS_Edge e = TopoDS::Edge(emap.FindKey(edge_ids[i]));
            if (BRep_Tool::Degenerated(e))
                continue;
            const TopoDS_Face ref = edge_ref_face(edgeFaces, e);
            if (ref.IsNull())
                continue;
            switch (modes[i]) {
            case 1:
                mk.Add(d1[i] * scale, d2[i] * scale, e, ref);
                break;
            case 2:
                /* The ANGLE is design intent and is never scaled; only the
                 * distance moves, which is what keeps the chamfer's face at
                 * the angle the user asked for. */
                mk.AddDA(d1[i] * scale, angle_deg[i] * M_PI / 180.0, e, ref);
                break;
            default:
                mk.Add(d1[i] * scale, e);
                break;
            }
            ++added;
        }
        if (added == 0)
            return TopoDS_Shape();
        mk.Build();
        if (!mk.IsDone())
            return TopoDS_Shape();
        const TopoDS_Shape out = mk.Shape();
        if (!blend_result_ok(out, base_vol))
            return TopoDS_Shape();
        return out;
    } catch (const Standard_Failure &) {
        return TopoDS_Shape();
    } catch (...) {
        return TopoDS_Shape();
    }
}

/* Everything a blend attempt needs to know, so the search strategy below can
 * be written once for fillets and chamfers. */
struct blend_ctx
{
    bool fillet;
    const TopoDS_Shape *base;
    const TopTools_IndexedMapOfShape *emap;
    const TopTools_IndexedDataMapOfShapeListOfShape *edgeFaces;
    const int *edge_ids;
    const double *radii, *radii2; /* fillet */
    const int *modes;             /* chamfer */
    const double *d1, *d2, *angle_deg;
    double base_vol;
    int builds; /* consumed budget, mutated as we go */
};

/* Build `use` at `scale`.
 *
 * ChFi3d_Rational only. The other two circle representations are available
 * and were tried here first, on the theory that a different approximation
 * path might succeed where the default fails — but that is a guess, and it
 * doubles the cost of every rung of the ladder below, which is what the
 * salvage path spends its budget on. The size ladder is the mechanism with
 * evidence behind it; this one is not, so it is not here. */
static TopoDS_Shape blend_at(blend_ctx &c, const std::vector<int> &use,
                             double scale)
{
    if (c.builds >= kBlendBuildBudget)
        return TopoDS_Shape();
    ++c.builds;
    if (c.fillet)
        return try_fillet_build(*c.base, *c.emap, use, c.edge_ids, c.radii,
                                c.radii2, scale, ChFi3d_Rational, c.base_vol);
    return try_chamfer_build(*c.base, *c.emap, *c.edgeFaces, use, c.edge_ids,
                             c.modes, c.d1, c.d2, c.angle_deg, scale,
                             c.base_vol);
}

/* Walk the size ladder for one edge set. Reports the rung that worked. */
static TopoDS_Shape blend_ladder(blend_ctx &c, const std::vector<int> &use,
                                 double *out_scale)
{
    for (int si = 0; si < kBlendScaleCount; ++si) {
        const TopoDS_Shape s = blend_at(c, use, kBlendScales[si]);
        if (!s.IsNull()) {
            if (out_scale)
                *out_scale = kBlendScales[si];
            return s;
        }
    }
    return TopoDS_Shape();
}

/* The whole strategy, shared by fillet and chamfer.
 *
 * A blend feature carries a SET of edges, and one impossible edge used to
 * kill the whole feature — the body lost every round in the set, not just the
 * one that could not be built. Inventor keeps the rest, and so do we:
 *
 *   1. the whole set, walking the size ladder;
 *   2. if that fails, probe each edge ALONE, which names the edges that are
 *      individually impossible;
 *   3. build the survivors together;
 *   4. if the survivors still interact badly, shed them one at a time until
 *      what remains builds.
 *
 * Every probe runs against the ORIGINAL shape, so the caller's edge indices
 * stay valid throughout — no topological remapping, and no chance of a blend
 * landing on an edge the user never picked.
 *
 * `keep` lists the caller-space indices worth trying. `dropped` is indexed by
 * caller-space index and is set to 1 for every edge that did not make it into
 * the returned shape; entries not in `keep` must already be marked by the
 * caller. */
static TopoDS_Shape blend_edges_subset(blend_ctx &c,
                                       const std::vector<int> &keep,
                                       std::vector<char> &dropped,
                                       double *out_scale)
{
    TopoDS_Shape s = blend_ladder(c, keep, out_scale);
    if (!s.IsNull())
        return s;
    if (keep.size() < 2)
        return TopoDS_Shape();

    /* 2 — who can stand on their own? */
    std::vector<int> viable;
    for (size_t k = 0; k < keep.size(); ++k) {
        const std::vector<int> one(1, keep[k]);
        double sc = 1.0;
        if (!blend_ladder(c, one, &sc).IsNull())
            viable.push_back(keep[k]);
        else
            dropped[keep[k]] = 1;
    }
    if (viable.empty())
        return TopoDS_Shape();

    /* 3 — the survivors together. */
    if (viable.size() < keep.size()) {
        s = blend_ladder(c, viable, out_scale);
        if (!s.IsNull())
            return s;
    }

    /* 4 — each edge works alone but they interact. Build the set up greedily:
     * start from nothing and keep an edge only if the set still builds with it
     * added. That is O(n) builds and what comes out provably builds together,
     * where dropping candidates one at a time only ever tests sets of size
     * n-1 and gives up if no single removal is enough. */
    std::vector<int> acc;
    TopoDS_Shape best;
    for (size_t k = 0; k < viable.size(); ++k) {
        std::vector<int> trial = acc;
        trial.push_back(viable[k]);
        double sc = 1.0;
        const TopoDS_Shape t = blend_ladder(c, trial, &sc);
        if (!t.IsNull()) {
            acc.swap(trial);
            best = t;
            if (out_scale)
                *out_scale = sc;
        }
        if (c.builds >= kBlendBuildBudget)
            break;
    }
    /* Whatever did not make it into the accepted set is out, including any
     * the build budget cut short. */
    for (size_t k = 0; k < viable.size(); ++k) {
        bool in = false;
        for (size_t j = 0; j < acc.size(); ++j)
            if (acc[j] == viable[k])
                in = true;
        if (!in)
            dropped[viable[k]] = 1;
    }
    return best;
}

/* Turn what BRepFilletAPI knows about its own failure into something a person
 * can act on. The old message guessed "radius too large?" at every failure. */
static void fillet_failure_reason(const TopoDS_Shape &base,
                                  const TopTools_IndexedMapOfShape &emap,
                                  const std::vector<int> &use,
                                  const int *edge_ids, const double *radii,
                                  const double *radii2, char *buf, size_t cap)
{
    std::snprintf(buf, cap, "no radius in this size range builds on these edges");
    try {
        BRepFilletAPI_MakeFillet mk(base, ChFi3d_Rational);
        for (size_t k = 0; k < use.size(); ++k) {
            const int i = use[k];
            const TopoDS_Edge e = TopoDS::Edge(emap.FindKey(edge_ids[i]));
            if (BRep_Tool::Degenerated(e))
                continue;
            if (radii2 && radii2[i] > 0.0 &&
                std::fabs(radii2[i] - radii[i]) > 1.0e-12)
                mk.Add(radii[i], radii2[i], e);
            else
                mk.Add(radii[i], e);
        }
        mk.Build();
        if (mk.IsDone())
            return;
        if (mk.NbFaultyContours() > 0) {
            const int ic = mk.FaultyContour(1);
            const char *why = "the blend could not be run along the edge";
            switch (mk.StripeStatus(ic)) {
            case ChFiDS_StartsolFailure:
                why = "no starting section fits — the radius is too large for "
                      "the faces meeting at this edge";
                break;
            case ChFiDS_TwistedSurface:
                why = "the blend surface twists on itself at this radius";
                break;
            case ChFiDS_WalkingFailure:
                why = "the blend runs off the end of the faces it follows";
                break;
            default:
                break;
            }
            std::snprintf(buf, cap, "edge set %d: %s", ic, why);
            return;
        }
        if (mk.NbFaultyVertices() > 0) {
            std::snprintf(buf, cap,
                          "%d corner(s) where the rounds meet cannot be closed "
                          "at this radius",
                          mk.NbFaultyVertices());
            return;
        }
    } catch (...) {
        /* keep the generic message */
    }
}

extern "C" occt_shape *occt_fillet_edges_ex(const occt_shape *shape,
                                            const int *edge_ids,
                                            const double *radii,
                                            const double *radii2, int n,
                                            int *out_dropped, double *out_scale)
{
    OCCT_TRY("occt_fillet_edges")
    if (out_scale)
        *out_scale = 1.0;
    if (out_dropped)
        for (int i = 0; i < n; ++i)
            out_dropped[i] = 0;
    if (!shape || !edge_ids || !radii || n < 1) {
        set_err("occt_fillet_edges", "null or empty edge set");
        return nullptr;
    }
    TopTools_IndexedMapOfShape emap;
    TopExp::MapShapes(shape->s, TopAbs_EDGE, emap);
    /* Validate and filter BEFORE any build, so a bad index is a clear error
     * rather than a mystery failure forty builds later. */
    std::vector<int> keep;
    for (int i = 0; i < n; ++i) {
        if (edge_ids[i] < 1 || edge_ids[i] > emap.Extent()) {
            set_err("occt_fillet_edges", "edge index out of range");
            return nullptr;
        }
        if (!(radii[i] > 0.0)) {
            set_err("occt_fillet_edges", "radius must be > 0");
            return nullptr;
        }
        if (BRep_Tool::Degenerated(TopoDS::Edge(emap.FindKey(edge_ids[i]))))
            continue;
        keep.push_back(i);
    }
    if (keep.empty()) {
        set_err("occt_fillet_edges", "no filletable edge in the set");
        return nullptr;
    }

    blend_ctx c;
    c.fillet = true;
    c.base = &shape->s;
    c.emap = &emap;
    c.edgeFaces = nullptr;
    c.edge_ids = edge_ids;
    c.radii = radii;
    c.radii2 = radii2;
    c.modes = nullptr;
    c.d1 = c.d2 = c.angle_deg = nullptr;
    c.base_vol = solid_volume(shape->s);
    c.builds = 0;

    /* Everything not in `keep` is already out (degenerate edges); the search
     * whittles the rest down from there, in the caller's index space. */
    std::vector<char> sub(n, 1);
    for (size_t k = 0; k < keep.size(); ++k)
        sub[keep[k]] = 0;
    double scale = 1.0;
    const TopoDS_Shape out = blend_edges_subset(c, keep, sub, &scale);
    if (out.IsNull()) {
        char why[320];
        fillet_failure_reason(shape->s, emap, keep, edge_ids, radii, radii2,
                              why, sizeof(why));
        set_err("occt_fillet_edges", why);
        return nullptr;
    }
    if (out_scale)
        *out_scale = scale;
    if (out_dropped)
        for (int i = 0; i < n; ++i)
            out_dropped[i] = sub[i] ? 1 : 0;
    return wrap(out, "occt_fillet_edges");
    OCCT_CATCH("occt_fillet_edges", nullptr)
}

extern "C" occt_shape *occt_fillet_edges(const occt_shape *shape,
                                         const int *edge_ids,
                                         const double *radii,
                                         const double *radii2, int n)
{
    return occt_fillet_edges_ex(shape, edge_ids, radii, radii2, n, nullptr,
                                nullptr);
}

/*
 * v28 (S17) — the largest mode-2 chamfer angle THIS edge admits, in degrees.
 *
 * OCCT's own plane/plane chamfer prints the rule. ChFiKPart_MakeChAsym builds
 * the two into-face directions at the edge, takes cosP as their dot product,
 * and computes the second distance as
 *
 *     dis2 = Dis / (cosP + sinP / Tan(Angle))
 *
 * (src/ChFiKPart/ChFiKPart_ComputeData_ChAsymPlnPln.cxx). Those two directions
 * are the ones edge_info's convexity sign is built from, so cosP is the cosine
 * of the INTERIOR DIHEDRAL theta, and the expression is the law of sines:
 *
 *     dis2 = d1 . sin(alpha) / sin(alpha + theta)
 *
 * with alpha the angle at the reference face's tangent point — which is also
 * why AddDA's angle is measured FROM that face: Dis and Angle are both
 * anchored on the face handed to it. dis2 blows up at alpha + theta = 180 and
 * goes NEGATIVE past it, so the admissible range is
 *
 *     0 < alpha < 180 - theta
 *
 * exactly, and that equals the historical 90 if and only if theta is 90.
 * 180 - theta is the angle between the two OUTWARD normals, which is what
 * occt_shape_edge_info reports as field [10] — so this limit and that field
 * are the same number by construction, computed here from the same helper at
 * the same arc-length midpoint so the two cannot drift apart.
 *
 * False when it cannot be measured — an edge without exactly two faces, or
 * normals that will not evaluate — and `out_deg` is then left alone. The
 * caller keeps the historical 90 in that case: refusing instead would be a
 * second behaviour change nobody asked for.
 */
static bool edge_chamfer_angle_limit(
    const TopTools_IndexedDataMapOfShapeListOfShape &edgeFaces,
    const TopoDS_Edge &edge, double &out_deg)
{
    if (!edgeFaces.Contains(edge))
        return false;
    const TopTools_ListOfShape &fl = edgeFaces.FindFromKey(edge);
    if (fl.Extent() != 2)
        return false;
    BRepAdaptor_Curve ec(edge);
    /* The SAME midpoint edge_info uses: by arc length, not by parameter, so
     * that a rebuilt B-spline does not move it. */
    double tmid = 0.5 * (ec.FirstParameter() + ec.LastParameter());
    const double len = GCPnts_AbscissaPoint::Length(ec);
    if (len > 1e-12) {
        GCPnts_AbscissaPoint ap(ec, len * 0.5, ec.FirstParameter());
        if (ap.IsDone())
            tmid = ap.Parameter();
    }
    gp_Dir n1, n2;
    if (!face_outward_normal(TopoDS::Face(fl.First()), edge, tmid, n1) ||
        !face_outward_normal(TopoDS::Face(fl.Last()), edge, tmid, n2))
        return false;
    const double dot = std::max(-1.0, std::min(1.0, n1.Dot(n2)));
    const double deg = std::acos(dot) * 180.0 / M_PI;
    if (!(deg > 1e-9))
        return false; /* tangent faces: no chamfer angle is admissible, and
                       * saying so through the 90 rule is no worse than
                       * inventing a limit of 0 here. */
    out_deg = deg;
    return true;
}

extern "C" occt_shape *occt_chamfer_edges_ex(
    const occt_shape *shape, const int *edge_ids, const int *modes,
    const double *d1, const double *d2, const double *angle_deg, int n,
    int *out_dropped, double *out_scale)
{
    OCCT_TRY("occt_chamfer_edges")
    if (out_scale)
        *out_scale = 1.0;
    if (out_dropped)
        for (int i = 0; i < n; ++i)
            out_dropped[i] = 0;
    if (!shape || !edge_ids || !modes || !d1 || n < 1) {
        set_err("occt_chamfer_edges", "null or empty edge set");
        return nullptr;
    }
    TopTools_IndexedMapOfShape emap;
    TopExp::MapShapes(shape->s, TopAbs_EDGE, emap);
    TopTools_IndexedDataMapOfShapeListOfShape edgeFaces;
    TopExp::MapShapesAndAncestors(shape->s, TopAbs_EDGE, TopAbs_FACE,
                                  edgeFaces);
    std::vector<int> keep;
    for (int i = 0; i < n; ++i) {
        if (edge_ids[i] < 1 || edge_ids[i] > emap.Extent()) {
            set_err("occt_chamfer_edges", "edge index out of range");
            return nullptr;
        }
        if (!(d1[i] > 0.0)) {
            set_err("occt_chamfer_edges", "distance must be > 0");
            return nullptr;
        }
        if (modes[i] == 1 && (!d2 || !(d2[i] > 0.0))) {
            set_err("occt_chamfer_edges",
                    "two-distance chamfer needs a positive second distance");
            return nullptr;
        }
        if (modes[i] == 2 && (!angle_deg || !(angle_deg[i] > 0.0))) {
            set_err("occt_chamfer_edges",
                    "chamfer angle must be greater than 0 deg");
            return nullptr;
        }
        const TopoDS_Edge e = TopoDS::Edge(emap.FindKey(edge_ids[i]));
        if (BRep_Tool::Degenerated(e))
            continue;
        if (edge_ref_face(edgeFaces, e).IsNull()) {
            set_err("occt_chamfer_edges",
                    "edge has no adjacent face to measure from");
            return nullptr;
        }
        /* v28 (S17): the upper bound is the EDGE'S, not a literal 90.
         *
         * Until v28 this read `angle_deg[i] >= 90.0`. That is the exactly
         * correct rule for a perpendicular edge and wrong in BOTH directions
         * away from one, because the admissible range is alpha < 180 - theta
         * (see edge_chamfer_angle_limit for OCCT's own arithmetic):
         *
         *  - on an ACUTE edge it was too STRICT. On an equilateral prism's
         *    60-degree edge the range reaches 120, and alpha = 100 was refused
         *    though OCCT builds it perfectly well — and builds it when the
         *    SAME chamfer is spelled as two distances, which mode 1 let
         *    through. Two spellings of one chamfer, one refused for no
         *    geometric reason. That asymmetry is what S16 measured ([40j]).
         *  - on an OBTUSE edge it was too PERMISSIVE. On a 135-degree edge the
         *    range is only 45, so alpha = 60 passed the guard and handed OCCT
         *    dis2 = -6.692130, a negative distance. The user got OCCT's
         *    failure where the guard's own sentence was available. [41a].
         *
         * It is checked here, after the degenerate skip and the reference-face
         * check, because it needs the edge; the mode-2 "> 0" test above stays
         * where it was, being argument validation rather than geometry, so a
         * degenerate edge is still skipped rather than judged. */
        if (modes[i] == 2) {
            double limit = 90.0; /* the historical rule, kept for an edge whose
                                  * own limit cannot be measured */
            edge_chamfer_angle_limit(edgeFaces, e, limit);
            if (angle_deg[i] >= limit) {
                char msg[192];
                std::snprintf(msg, sizeof(msg),
                              "chamfer angle must be in (0, %.6g) deg on this "
                              "edge: its faces meet at %.6g deg, and the "
                              "chamfer degenerates when the angle reaches "
                              "180 minus that",
                              limit, 180.0 - limit);
                set_err("occt_chamfer_edges", msg);
                return nullptr;
            }
        }
        keep.push_back(i);
    }
    if (keep.empty()) {
        set_err("occt_chamfer_edges", "no chamferable edge in the set");
        return nullptr;
    }

    blend_ctx c;
    c.fillet = false;
    c.base = &shape->s;
    c.emap = &emap;
    c.edgeFaces = &edgeFaces;
    c.edge_ids = edge_ids;
    c.radii = c.radii2 = nullptr;
    c.modes = modes;
    c.d1 = d1;
    c.d2 = d2;
    c.angle_deg = angle_deg;
    c.base_vol = solid_volume(shape->s);
    c.builds = 0;

    std::vector<char> sub(n, 1);
    for (size_t k = 0; k < keep.size(); ++k)
        sub[keep[k]] = 0;
    double scale = 1.0;
    const TopoDS_Shape out = blend_edges_subset(c, keep, sub, &scale);
    if (out.IsNull()) {
        set_err("occt_chamfer_edges",
                "no distance in this size range builds on these edges "
                "(too large for the faces meeting at the edge?)");
        return nullptr;
    }
    if (out_scale)
        *out_scale = scale;
    if (out_dropped)
        for (int i = 0; i < n; ++i)
            out_dropped[i] = sub[i] ? 1 : 0;
    return wrap(out, "occt_chamfer_edges");
    OCCT_CATCH("occt_chamfer_edges", nullptr)
}

extern "C" occt_shape *occt_chamfer_edges(const occt_shape *shape,
                                          const int *edge_ids, const int *modes,
                                          const double *d1, const double *d2,
                                          const double *angle_deg, int n)
{
    return occt_chamfer_edges_ex(shape, edge_ids, modes, d1, d2, angle_deg, n,
                                 nullptr, nullptr);
}

extern "C" int occt_ray_hits(const occt_shape *shape, double ox, double oy,
                             double oz, double dx, double dy, double dz,
                             double *out, int max_hits)
{
    OCCT_TRY("occt_ray_hits")
    if (!shape || !out || max_hits < 1) {
        set_err("occt_ray_hits", "null argument");
        return -1;
    }
    const double dlen = std::sqrt(dx * dx + dy * dy + dz * dz);
    if (!(dlen > 1e-12)) {
        set_err("occt_ray_hits", "ray direction is degenerate");
        return -1;
    }
    const gp_Lin line(gp_Pnt(ox, oy, oz),
                      gp_Dir(dx / dlen, dy / dlen, dz / dlen));
    BRepIntCurveSurface_Inter inter;
    inter.Init(shape->s, line, 1.0e-7);
    std::vector<double> ws;
    for (; inter.More(); inter.Next())
        ws.push_back(inter.W());
    std::sort(ws.begin(), ws.end());
    /* Adjacent faces meeting on an edge report the same crossing twice, and a
     * "To Next" that stopped on a duplicate would measure zero thickness. */
    int written = 0;
    double last = 0.0;
    bool have = false;
    for (size_t i = 0; i < ws.size() && written < max_hits; ++i) {
        if (have && std::fabs(ws[i] - last) <= 1.0e-7)
            continue;
        out[written++] = ws[i];
        last = ws[i];
        have = true;
    }
    return written;
    OCCT_CATCH("occt_ray_hits", -1)
}

/* The circle a point traces about an axis, plus its validity. Shared by the
 * whole-shape and single-face variants so the angle origin can only be
 * defined once. */
static bool revolve_circle(double ax_px, double ax_py, double ax_pz,
                          double ax_dx, double ax_dy, double ax_dz, double px,
                          double py, double pz, Handle(Geom_Circle) &out)
{
    const gp_Vec axis(ax_dx, ax_dy, ax_dz);
    if (axis.Magnitude() < 1e-12)
        return false;
    const gp_Dir adir(axis);
    const gp_Pnt apt(ax_px, ax_py, ax_pz);
    const gp_Pnt p(px, py, pz);
    const gp_Vec w(apt, p);
    const gp_Pnt centre = apt.Translated(gp_Vec(adir) * w.Dot(gp_Vec(adir)));
    const gp_Vec radial(centre, p);
    if (radial.Magnitude() < 1e-12)
        return false; /* on the axis: no path */
    out = new Geom_Circle(gp_Ax2(centre, adir, gp_Dir(radial)),
                          radial.Magnitude());
    return true;
}

/* Sorted, de-duplicated crossing angles in degrees of `circ` against `target`,
 * measured from the circle's own X direction. */
static int circle_hit_angles(const TopoDS_Shape &target,
                            const Handle(Geom_Circle) &circ, double *out,
                            int max_hits)
{
    GeomAdaptor_Curve gac(circ, 0.0, 2.0 * M_PI);
    BRepIntCurveSurface_Inter inter;
    inter.Init(target, gac, 1.0e-7);
    std::vector<double> ang;
    for (; inter.More(); inter.Next()) {
        double a = inter.W();
        while (a <= 1.0e-9)
            a += 2.0 * M_PI;
        while (a > 2.0 * M_PI + 1.0e-9)
            a -= 2.0 * M_PI;
        ang.push_back(a * 180.0 / M_PI);
    }
    std::sort(ang.begin(), ang.end());
    int written = 0;
    double last = 0.0;
    bool have = false;
    for (size_t i = 0; i < ang.size() && written < max_hits; ++i) {
        if (have && std::fabs(ang[i] - last) <= 1.0e-6)
            continue;
        out[written++] = ang[i];
        last = ang[i];
        have = true;
    }
    return written;
}

extern "C" int occt_revolve_hits_face(const occt_shape *shape, double ax_px,
                                      double ax_py, double ax_pz, double ax_dx,
                                      double ax_dy, double ax_dz, double px,
                                      double py, double pz, double fx,
                                      double fy, double fz, double *out,
                                      int max_hits)
{
    OCCT_TRY("occt_revolve_hits_face")
    if (!shape || !out || max_hits < 1) {
        set_err("occt_revolve_hits_face", "null argument");
        return -1;
    }
    Handle(Geom_Circle) circ;
    if (!revolve_circle(ax_px, ax_py, ax_pz, ax_dx, ax_dy, ax_dz, px, py, pz,
                       circ)) {
        if (std::sqrt(ax_dx * ax_dx + ax_dy * ax_dy + ax_dz * ax_dz) < 1e-12) {
            set_err("occt_revolve_hits_face", "axis direction is degenerate");
            return -1;
        }
        return 0;
    }
    /* nearest face to the picked point — FaceSel stores a point ON the face,
     * so the nearest face is the one that was picked */
    const TopoDS_Vertex v = BRepBuilderAPI_MakeVertex(gp_Pnt(fx, fy, fz));
    TopoDS_Face best;
    double bestD = 1.0e300;
    for (TopExp_Explorer ex(shape->s, TopAbs_FACE); ex.More(); ex.Next()) {
        const TopoDS_Face f = TopoDS::Face(ex.Current());
        BRepExtrema_DistShapeShape d(v, f);
        if (!d.IsDone() || d.NbSolution() < 1)
            continue;
        if (d.Value() < bestD) {
            bestD = d.Value();
            best = f;
        }
    }
    if (best.IsNull()) {
        set_err("occt_revolve_hits_face", "no face found near that point");
        return -1;
    }
    return circle_hit_angles(best, circ, out, max_hits);
    OCCT_CATCH("occt_revolve_hits_face", -1)
}

extern "C" int occt_revolve_hits(const occt_shape *shape, double ax_px,
                                 double ax_py, double ax_pz, double ax_dx,
                                 double ax_dy, double ax_dz, double px,
                                 double py, double pz, double *out,
                                 int max_hits)
{
    OCCT_TRY("occt_revolve_hits")
    if (!shape || !out || max_hits < 1) {
        set_err("occt_revolve_hits", "null argument");
        return -1;
    }
    Handle(Geom_Circle) circ;
    if (!revolve_circle(ax_px, ax_py, ax_pz, ax_dx, ax_dy, ax_dz, px, py, pz,
                       circ)) {
        if (std::sqrt(ax_dx * ax_dx + ax_dy * ax_dy + ax_dz * ax_dz) < 1e-12) {
            set_err("occt_revolve_hits", "axis direction is degenerate");
            return -1;
        }
        return 0; /* the point is ON the axis: it never moves */
    }
    return circle_hit_angles(shape->s, circ, out, max_hits);
    OCCT_CATCH("occt_revolve_hits", -1)
}

/* ---- v15: sweep, loft, coil ---------------------------------------------- */

/* ---- v27: is a hole really a hole? --------------------------------------
 *
 * THE ASSEMBLY BELOW IS A SPECIAL OPERATION WHERE THE BOOLEAN WAS A GENERAL
 * ONE, and this is the whole of the difference. BRepAlgoAPI_Cut removes
 * whatever the hole solid occupies — inside the body, outside it, straddling
 * its wall, overlapping another hole. An assembled annulus assumes each hole
 * is a genuine hole: strictly inside the outer boundary, and disjoint from
 * every other hole. Nothing in placed_profile_wires has ever checked that,
 * because nothing needed it to.
 *
 * So the assembly is gated on this test, and when it says no the caller runs
 * the v26 boolean unchanged. A false "no" costs the old speed; a false "yes"
 * would produce a WRONG SOLID, so every uncertainty in here resolves to no.
 *
 * It is done in the profile's own 2D coordinates, on xyb, before any wire
 * exists. That is a choice with a reason: placed_profile_wires maps every loop
 * through ONE mat34, and an affine placement preserves inside and outside, so
 * containment in the sketch plane IS containment in 3D. Testing the placed
 * wires instead would mean 3D distance queries over B-Rep edges to learn the
 * same thing.
 *
 * SUFFICIENCY, because the guard is an argument and not just a filter:
 *
 *   If one vertex of hole H is inside outer O, and no point of H's boundary
 *   comes within `margin` of O's boundary, then H is entirely inside O — a
 *   connected closed curve that never touches O cannot have points on both
 *   sides of it.
 *
 * The margin is what makes the polygon test honest about arcs. A bulged edge
 * bows off its chord, so each loop is flattened at 2 degrees per sub-chord and
 * the largest sagitta thrown away is carried alongside; the separation has to
 * beat the sum of both loops' sagittae plus a scale-free term. */

/* One profile loop flattened to a polygon, and the largest distance by which
 * that polygon can be inside the true arc it replaces. */
struct flat_loop {
    std::vector<double> xy;
    double sag = 0.0;
};

/* At most this many points per flattened loop. It is a BUDGET, not a refusal:
 * 2 degrees per sub-chord is the target, and a loop that would blow the budget
 * gets a coarser step instead — which makes its sagitta larger, which makes
 * the clearance margin larger, which makes the guard MORE conservative. The
 * error is carried, so coarsening cannot turn a "no" into a "yes".
 *
 * Without it the flattening is unbounded in a way that matters: a full circle
 * is 180 sub-chords at 2 degrees, so a 1200-vertex loop of full-circle arcs
 * would be 216 000 points and the pairwise test 4.7e10 pairs. Nothing a user
 * draws looks like that; a file a user IMPORTS might. */
static const int kFlatBudget = 8192;

static void flatten_loop(const double *xyb, int npts, flat_loop &out)
{
    /* Pass 1: how much turning is there, and can 2 degrees pay for it? */
    double turn = 0.0;
    for (int i = 0; i < npts; ++i) {
        const double b = xyb[3 * i + 2];
        if (std::fabs(b) > 1e-12)
            turn += std::fabs(4.0 * std::atan(b));
    }
    const int room = kFlatBudget > npts ? kFlatBudget - npts : 1;
    double kStep = 2.0 * M_PI / 180.0; /* 2 degrees per sub-chord */
    if (turn / kStep > room)
        kStep = turn / room;
    for (int i = 0; i < npts; ++i) {
        const int j = (i + 1) % npts;
        const double x0 = xyb[3 * i], y0 = xyb[3 * i + 1];
        const double b = xyb[3 * i + 2];
        const double x1 = xyb[3 * j], y1 = xyb[3 * j + 1];
        out.xy.push_back(x0);
        out.xy.push_back(y0);
        if (std::fabs(b) <= 1e-12)
            continue;
        const double chord = std::hypot(x1 - x0, y1 - y0);
        const double th = 4.0 * std::atan(b); /* DXF bulge = tan(theta/4) */
        const double sh = std::sin(0.5 * th);
        if (chord < 1e-12 || std::fabs(sh) < 1e-12)
            continue;
        const double r = chord / (2.0 * sh);
        /* Centre: the chord midpoint, stepped ALONG the left normal by
         * r cos(theta/2). A DXF bulge is tan(theta/4) and a positive one is a
         * counter-clockwise arc; a body turning counter-clockwise keeps its
         * centre of curvature on its LEFT, so the belly is on the RIGHT — and
         * a right-hand belly on a counter-clockwise loop bulges OUTWARD, which
         * is why arc_loop_signed_area ADDS the segment area for b > 0.
         *
         * THE SIGN HERE WAS WRONG ON FIRST WRITING, and it is worth saying how
         * it was caught, because the failure mode is the one this whole guard
         * exists to prevent. Stepping against the normal instead of along it
         * puts the arc on the wrong side of its chord, so the flattened
         * polygon traces a shape the profile does not have — and the guard
         * then answers a question about the wrong region and can say "this
         * hole is safely inside" about a hole that is not. It was found by a
         * bulged fixture that reported "separate" for a hole outside the
         * profile, and the arithmetic that settles it is one line: with
         * p0 = (0,0), p1 = (10,0) and b = tan(22.5 deg), rotating p0 about the
         * centre by theta must land ON p1, and it does so only for
         * m + n*h — the other sign lands at (0, -10). */
        const double ux = (x1 - x0) / chord, uy = (y1 - y0) / chord;
        const double nx = -uy, ny = ux;
        const double h = r * std::cos(0.5 * th);
        const double cx = 0.5 * (x0 + x1) + nx * h;
        const double cy = 0.5 * (y0 + y1) + ny * h;
        int nsub = static_cast<int>(std::ceil(std::fabs(th) / kStep));
        if (nsub < 1)
            nsub = 1;
        if (nsub > kFlatBudget)
            nsub = kFlatBudget;
        const double phi = th / nsub;
        const double sag = std::fabs(r) * (1.0 - std::cos(0.5 * phi));
        if (sag > out.sag)
            out.sag = sag;
        for (int k = 1; k < nsub; ++k) {
            const double a = phi * k, c = std::cos(a), sn = std::sin(a);
            const double dx = x0 - cx, dy = y0 - cy;
            out.xy.push_back(cx + dx * c - dy * sn);
            out.xy.push_back(cy + dx * sn + dy * c);
        }
    }
}

static double pt_seg_d2(double px, double py, double x0, double y0, double x1,
                        double y1)
{
    const double dx = x1 - x0, dy = y1 - y0;
    const double l2 = dx * dx + dy * dy;
    double t = l2 > 0.0 ? ((px - x0) * dx + (py - y0) * dy) / l2 : 0.0;
    if (t < 0.0)
        t = 0.0;
    else if (t > 1.0)
        t = 1.0;
    const double qx = x0 + t * dx - px, qy = y0 + t * dy - py;
    return qx * qx + qy * qy;
}

/* Squared distance between two 2D segments; zero when they properly cross. */
static double seg_seg_d2(const double *a, const double *b, const double *c,
                         const double *d)
{
    const double d1 = (b[0]-a[0])*(c[1]-a[1]) - (b[1]-a[1])*(c[0]-a[0]);
    const double d2 = (b[0]-a[0])*(d[1]-a[1]) - (b[1]-a[1])*(d[0]-a[0]);
    const double d3 = (d[0]-c[0])*(a[1]-c[1]) - (d[1]-c[1])*(a[0]-c[0]);
    const double d4 = (d[0]-c[0])*(b[1]-c[1]) - (d[1]-c[1])*(b[0]-c[0]);
    if (((d1 > 0.0) != (d2 > 0.0)) && ((d3 > 0.0) != (d4 > 0.0)))
        return 0.0;
    double m = pt_seg_d2(c[0], c[1], a[0], a[1], b[0], b[1]);
    const double m2 = pt_seg_d2(d[0], d[1], a[0], a[1], b[0], b[1]);
    if (m2 < m) m = m2;
    const double m3 = pt_seg_d2(a[0], a[1], c[0], c[1], d[0], d[1]);
    if (m3 < m) m = m3;
    const double m4 = pt_seg_d2(b[0], b[1], c[0], c[1], d[0], d[1]);
    if (m4 < m) m = m4;
    return m;
}

/* Crossing-number point-in-polygon. */
static bool pt_in_poly(double px, double py, const std::vector<double> &p)
{
    const size_t n = p.size() / 2;
    bool in = false;
    for (size_t i = 0, j = n - 1; i < n; j = i++) {
        const double yi = p[2 * i + 1], yj = p[2 * j + 1];
        if ((yi > py) != (yj > py)) {
            const double xi = p[2 * i], xj = p[2 * j];
            if (px < xi + (py - yi) * (xj - xi) / (yj - yi))
                in = !in;
        }
    }
    return in;
}

/* True when the two closed polygons keep more than `margin` between their
 * boundaries. The axis-aligned box rejection in the inner loop is what keeps
 * this affordable: at 1200 x 1200 segments almost every pair is four
 * comparisons and nothing else. */
static bool loops_clear_of(const std::vector<double> &a,
                           const std::vector<double> &b, double margin)
{
    const size_t na = a.size() / 2, nb = b.size() / 2;
    const double m2 = margin * margin;
    for (size_t i = 0, ip = na - 1; i < na; ip = i++) {
        const double A[2] = {a[2 * ip], a[2 * ip + 1]};
        const double B[2] = {a[2 * i], a[2 * i + 1]};
        const double alo0 = A[0] < B[0] ? A[0] : B[0];
        const double ahi0 = A[0] < B[0] ? B[0] : A[0];
        const double alo1 = A[1] < B[1] ? A[1] : B[1];
        const double ahi1 = A[1] < B[1] ? B[1] : A[1];
        for (size_t j = 0, jp = nb - 1; j < nb; jp = j++) {
            const double C[2] = {b[2 * jp], b[2 * jp + 1]};
            const double D[2] = {b[2 * j], b[2 * j + 1]};
            if ((C[0] < D[0] ? C[0] : D[0]) > ahi0 + margin) continue;
            if ((C[0] < D[0] ? D[0] : C[0]) < alo0 - margin) continue;
            if ((C[1] < D[1] ? C[1] : D[1]) > ahi1 + margin) continue;
            if ((C[1] < D[1] ? D[1] : C[1]) < alo1 - margin) continue;
            if (seg_seg_d2(A, B, C, D) <= m2)
                return false;
        }
    }
    return true;
}

/* The gate. True only when every hole is STRICTLY inside loop 0 and the holes
 * are pairwise disjoint and un-nested — which is exactly when the assembly and
 * the subtraction are the same solid. */
static bool profile_holes_are_separate(const double *xyb,
                                       const int *loop_counts, int nloops)
{
    if (!xyb || !loop_counts || nloops < 2)
        return nloops >= 1;
    std::vector<flat_loop> f(static_cast<size_t>(nloops));
    const double *p = xyb;
    double lo0 = 0, lo1 = 0, hi0 = 0, hi1 = 0;
    bool first = true;
    for (int l = 0; l < nloops; ++l) {
        if (loop_counts[l] < 2)
            return false;
        flatten_loop(p, loop_counts[l], f[static_cast<size_t>(l)]);
        p += 3 * loop_counts[l];
        const std::vector<double> &v = f[static_cast<size_t>(l)].xy;
        if (v.size() < 6)
            return false; /* fewer than three points is not a boundary */
        for (size_t i = 0; i < v.size(); i += 2) {
            if (first) {
                lo0 = hi0 = v[i];
                lo1 = hi1 = v[i + 1];
                first = false;
            } else {
                if (v[i] < lo0) lo0 = v[i];
                if (v[i] > hi0) hi0 = v[i];
                if (v[i + 1] < lo1) lo1 = v[i + 1];
                if (v[i + 1] > hi1) hi1 = v[i + 1];
            }
        }
    }
    const double diag = std::hypot(hi0 - lo0, hi1 - lo1);
    if (!(diag > 0.0))
        return false;
    for (int i = 1; i < nloops; ++i) {
        const flat_loop &h = f[static_cast<size_t>(i)];
        const double m = f[0].sag + h.sag + 1e-7 * diag;
        if (!pt_in_poly(h.xy[0], h.xy[1], f[0].xy))
            return false;
        if (!loops_clear_of(f[0].xy, h.xy, m))
            return false;
        for (int j = i + 1; j < nloops; ++j) {
            const flat_loop &g = f[static_cast<size_t>(j)];
            const double m2 = h.sag + g.sag + 1e-7 * diag;
            if (pt_in_poly(g.xy[0], g.xy[1], h.xy))
                return false;
            if (pt_in_poly(h.xy[0], h.xy[1], g.xy))
                return false;
            if (!loops_clear_of(h.xy, g.xy, m2))
                return false;
        }
    }
    return true;
}

/* The placed OUTER wire of a profile, plus its hole wires. Shared by sweep,
 * loft and coil, all of which need wires rather than the faces the extrude
 * path builds. Returns false and sets the error on failure. */
static bool placed_profile_wires(const double *xyb, const int *loop_counts,
                                 int nloops, const double *mat34,
                                 const char *who, TopoDS_Wire &outer,
                                 std::vector<TopoDS_Wire> &holes)
{
    if (!xyb || !loop_counts || nloops < 1 || !mat34) {
        set_err(who, "null profile arguments");
        return false;
    }
    gp_Trsf t;
    if (!trsf_from_mat34(mat34, t, who))
        return false;
    const double *p = xyb;
    for (int l = 0; l < nloops; ++l) {
        if (loop_counts[l] < 2) {
            set_err(who, "every loop needs at least 2 vertices");
            return false;
        }
        const double a = arc_loop_signed_area(p, loop_counts[l]);
        if (std::fabs(a) < 1e-12) {
            set_err(who, "a profile loop is degenerate");
            return false;
        }
        bool ok = false;
        TopoDS_Wire w = arc_loop_wire(p, loop_counts[l], a > 0.0, &ok);
        if (!ok) {
            set_err(who, "profile wire construction failed");
            return false;
        }
        BRepBuilderAPI_Transform mv(w, t, Standard_True);
        if (!mv.IsDone()) {
            set_err(who, "placing the profile failed");
            return false;
        }
        const TopoDS_Wire pw = TopoDS::Wire(mv.Shape());
        if (l == 0)
            outer = pw;
        else
            holes.push_back(pw);
        p += 3 * loop_counts[l];
    }
    return true;
}

/* ---- v24: the spine of a SAMPLED path ------------------------------------
 *
 * The comment this replaces said "the caller has already sampled the curve it
 * picked, so interpolating again would only add error the user cannot see or
 * control". That reasoning was about ACCURACY and it is still right about
 * accuracy. It was wrong about cost, by three orders of magnitude, and the
 * measurement is in perf/findings/S14-sweep.md:
 *
 *   - Every joint of a polyline spine is mitered, because occt_sweep_profile
 *     sets BRepBuilderAPI_RightCorner. Inside OCCT that reaches
 *     BRepFill_Sweep::PerformCorner, which hands the two adjacent shells —
 *     one face per profile segment EACH — to a full BOPAlgo_PaveFiller. It is
 *     a boolean, per joint, over the whole profile.
 *   - Measured: 96.6 % of the call, and it turns a linear sweep into a cubic
 *     one. A 512-segment ring on a 16-span path is 447 s; the same ring on a
 *     1-span path, which has no joint at all, is 62 ms.
 *   - At 1200 segments x 16 spans it does not merely cost, it FAILS —
 *     "BRep_API: command not done" after 742 s here and 231 s on the device.
 *   - At 64 segments x 64 spans, which is what sampleEntity(arcSamples: 64)
 *     produces for ANY arc, it corrupts the heap and aborts the process.
 *
 * So: joints somebody DREW still get a polyline and still get mitered, which
 * is the behaviour scenario [30] pins and the reason RightCorner is set at
 * all. Runs of points that came from the caller's own curve sampler get a C2
 * B-spline interpolated THROUGH every one of them — the samples all stay on
 * the spine, so the spine is never further from the path than the path was
 * from what the user drew, and there is no joint left to miter.
 */

/* The largest joint angle the application's own curve sampler can emit.
 *
 * sketchCurve (frontend/lib/part_model.dart:8647) hands every arc and every
 * circle to sampleEntity(g, arcSamples: 64) (frontend/lib/snap.dart:453),
 * which splits the entity's sweep into 64 EQUAL steps whatever its angle. A
 * full circle is 64 joints of 360/64 = 5.625 deg; a 90 deg arc is 64 joints of
 * 1.406 deg. 5.625 deg is the ceiling and only a closed circle reaches it.
 *
 * So a joint at or below this CAN have come from the sampler, and a joint
 * above it CANNOT: it is a vertex somebody drew. That is the whole derivation
 * — the number is a property of the caller, not one chosen to make a benchmark
 * fast. IF arcSamples EVER STOPS BEING 64, THIS MUST MOVE WITH IT.
 *
 * What it costs to be wrong at that angle, measured (S14 §2.6): at 5.625 deg a
 * mitered and an un-mitered joint differ by 0.50 % of the swept volume; at
 * 90 deg they differ by 46.7 % and the un-mitered one is invalid. The
 * threshold sits where the two treatments still nearly agree, four times
 * further out than the catastrophe. */
static const double kSampledJointDeg = 360.0 / 64.0;

/* Slack on the comparison so a circle's own 5.625 deg joints, arrived at
 * through cos and sin, land INSIDE the threshold rather than on it. */
static const double kJointEps = 1.0e-6;

/* The turn between two consecutive segments, in degrees: 0 straight, 180 a
 * reversal. */
static double joint_deg(const gp_Pnt &a, const gp_Pnt &b, const gp_Pnt &c)
{
    const gp_Vec u(a, b), v(b, c);
    if (u.Magnitude() < 1e-12 || v.Magnitude() < 1e-12)
        return 0.0;
    return u.Angle(v) * 180.0 / M_PI;
}

/* True when every interior joint of pts[i0..i1] is straight to within floating
 * point. Such a run must NOT be interpolated: a B-spline through collinear
 * points is geometrically the same line, but it is a B-SPLINE, so the faces
 * swept along it stop being planes — and a plane is what makes the boolean
 * that removes a hole cheap (§4.1 of S14's findings measured that at 80x).
 * Nothing curved is being given up here, so v23's straight segments stay. */
static bool run_is_straight(const std::vector<gp_Pnt> &pts, int i0, int i1)
{
    for (int i = i0 + 1; i < i1; ++i)
        if (joint_deg(pts[i - 1], pts[i], pts[i + 1]) > 1.0e-9)
            return false;
    return true;
}

/* One edge through pts[i0..i1] inclusive. Two points give a line; more give a
 * C2 B-spline INTERPOLATED through every point, not fitted near them. */
static bool run_edge(const std::vector<gp_Pnt> &pts, int i0, int i1,
                     TopoDS_Edge &out)
{
    const int n = i1 - i0 + 1;
    if (n < 2)
        return false;
    if (n == 2) {
        BRepBuilderAPI_MakeEdge mk(pts[i0], pts[i1]);
        if (!mk.IsDone())
            return false;
        out = mk.Edge();
        return true;
    }
    Handle(TColgp_HArray1OfPnt) h = new TColgp_HArray1OfPnt(1, n);
    for (int i = 0; i < n; ++i)
        h->SetValue(i + 1, pts[i0 + i]);
    GeomAPI_Interpolate itp(h, Standard_False, 1.0e-7);
    itp.Perform();
    if (!itp.IsDone())
        return false;
    BRepBuilderAPI_MakeEdge mk(itp.Curve());
    if (!mk.IsDone())
        return false;
    out = mk.Edge();
    return true;
}

/* A spine wire through world-space points.
 *
 * `path_mode` is one of OCCT_SWEEP_PATH_*. `smoothed` reports whether any run
 * was interpolated, which the caller needs: on a spine that is a curve the
 * Frenet trihedron carries the curve's TORSION and rotates the section about
 * the tangent — measured at 81 deg over this project's own sweep fixture —
 * where a polyline, having no torsion, does not. The corrected Frenet
 * trihedron is the one that reproduces the polyline's section orientation, and
 * on a polyline the two are identical (measured at 2, 4 and 16 spans: same
 * volume, same bounding box, to every printed digit). */
static bool spine_from_points_ex(const double *pts, int n, int path_mode,
                                 const char *who, TopoDS_Wire &out,
                                 bool *smoothed)
{
    if (smoothed)
        *smoothed = false;
    if (!pts || n < 2) {
        set_err(who, "a path needs at least 2 points");
        return false;
    }

    /* Deduplicate exactly as the polyline path always has: an edge of zero
     * length breaks sweeps, and it would make the interpolation singular. */
    std::vector<gp_Pnt> p;
    p.reserve(static_cast<size_t>(n));
    p.emplace_back(pts[0], pts[1], pts[2]);
    for (int i = 1; i < n; ++i) {
        const gp_Pnt q(pts[3 * i], pts[3 * i + 1], pts[3 * i + 2]);
        if (q.Distance(p.back()) < 1e-9)
            continue;
        p.push_back(q);
    }
    if (p.size() < 2) {
        set_err(who, "the path collapsed to a single point");
        return false;
    }

    const int np = static_cast<int>(p.size());
    /* Two points is one straight edge in every mode, and the polygon path is
     * what has always built it. */
    if (path_mode == OCCT_SWEEP_PATH_POLY || np == 2) {
        BRepBuilderAPI_MakePolygon poly;
        for (const gp_Pnt &q : p)
            poly.Add(q);
        if (!poly.IsDone()) {
            set_err(who, "the path collapsed to a single point");
            return false;
        }
        out = poly.Wire();
        return true;
    }

    /* Split into maximal runs whose INTERIOR joints are all shallow enough to
     * have come from the sampler. A run boundary is a joint somebody drew, and
     * it stays a vertex of the wire so RightCorner still miters it. In SMOOTH
     * mode there is one run over everything, which is the escape hatch a
     * caller who KNOWS its path is a sampled curve can ask for. */
    std::vector<int> cut; /* indices where a run ends and the next begins */
    if (path_mode != OCCT_SWEEP_PATH_SMOOTH) {
        for (int i = 1; i + 1 < np; ++i)
            if (joint_deg(p[i - 1], p[i], p[i + 1]) >
                kSampledJointDeg + kJointEps)
                cut.push_back(i);
    }

    /* Nothing to smooth: every joint was drawn. Take the polygon path
     * unchanged — byte for byte the v23 result, which is what scenario [37]'s
     * differential arm checks. */
    if (static_cast<int>(cut.size()) == np - 2) {
        BRepBuilderAPI_MakePolygon poly;
        for (const gp_Pnt &q : p)
            poly.Add(q);
        if (!poly.IsDone()) {
            set_err(who, "the path collapsed to a single point");
            return false;
        }
        out = poly.Wire();
        return true;
    }

    BRepBuilderAPI_MakeWire mk;
    int start = 0;
    bool any = false;
    cut.push_back(np - 1); /* the last run ends at the last point */
    for (const int end : cut) {
        TopoDS_Edge e;
        if (run_is_straight(p, start, end)) {
            /* A straight run is v23's straight run, edge for edge. */
            for (int i = start; i < end; ++i) {
                BRepBuilderAPI_MakeEdge le(p[i], p[i + 1]);
                if (!le.IsDone()) {
                    set_err(who, "the path collapsed to a single point");
                    return false;
                }
                mk.Add(le.Edge());
            }
        } else if (!run_edge(p, start, end, e)) {
            /* An interpolation that will not run is not a reason to fail the
             * sweep: fall back to the straight segments of that run, which is
             * exactly what v23 would have built for the whole path. */
            for (int i = start; i < end; ++i) {
                BRepBuilderAPI_MakeEdge le(p[i], p[i + 1]);
                if (!le.IsDone()) {
                    set_err(who, "the path collapsed to a single point");
                    return false;
                }
                mk.Add(le.Edge());
            }
        } else {
            if (end - start >= 2)
                any = true;
            mk.Add(e);
        }
        start = end;
    }
    if (!mk.IsDone()) {
        set_err(who, "the path could not be assembled into a spine");
        return false;
    }
    out = mk.Wire();
    if (smoothed)
        *smoothed = any;
    return true;
}

/* The v23 entry point, unchanged for every caller that does not care. */
static bool spine_from_points(const double *pts, int n, const char *who,
                              TopoDS_Wire &out)
{
    return spine_from_points_ex(pts, n, OCCT_SWEEP_PATH_POLY, who, out,
                                nullptr);
}

/* One hole's sweep, configured EXACTLY as the boolean branch configures it.
 * Shared so that the two routes cannot drift apart: whatever is true of the
 * hole's placement is true of it in both, and v26's repair — the hole is
 * placed the way its body is placed — stays one piece of code. */
static void configure_hole_pipe(BRepOffsetAPI_MakePipeShell &hm,
                                const TopoDS_Wire &h, int orientation,
                                double taper_deg, bool corrected_frenet,
                                Standard_Boolean with_correction)
{
    hm.SetTransitionMode(BRepBuilderAPI_RightCorner);
    if (orientation == 1)
        hm.SetMode(gp_Ax2(gp::Origin(), gp_Dir(0, 0, 1), gp_Dir(1, 0, 0)));
    else
        hm.SetMode(corrected_frenet ? Standard_False : Standard_True);
    if (taper_deg != 0.0) {
        const double k = std::tan(taper_deg * M_PI / 180.0);
        Handle(Law_Linear) law = new Law_Linear();
        law->Set(0.0, 1.0, 1.0, 1.0 + k);
        hm.SetLaw(h, law, Standard_False, with_correction);
    } else {
        hm.Add(h, Standard_False, with_correction);
    }
}

/* The signed area of a wire projected onto a plane, from the wire's ordered
 * vertices. Only its SIGN is used, and the sign of a polygon through points
 * that lie ON the loop is the loop's own sense whatever the edges do between
 * them. */
static double wire_sense_on(const TopoDS_Wire &w, const gp_Pln &pl)
{
    double a = 0.0;
    gp_Pnt2d prev, firstp;
    bool have = false;
    for (BRepTools_WireExplorer ex(w); ex.More(); ex.Next()) {
        const gp_Pnt2d q =
            ProjLib::Project(pl, BRep_Tool::Pnt(ex.CurrentVertex()));
        if (have)
            a += 0.5 * (prev.X() * q.Y() - q.X() * prev.Y());
        else
            firstp = q;
        prev = q;
        have = true;
    }
    if (have)
        a += 0.5 * (prev.X() * firstp.Y() - firstp.X() * prev.Y());
    return a;
}

/* A planar end cap: `outer` bounds it, every wire in `inner` is a hole in it.
 *
 * The plane comes from BRepLib_MakeFace(outer, onlyPlane), which is the same
 * call BRepFill_PipeShell::MakeSolid's own PerformPlan makes for the unholed
 * case — so an unholed cap built here is the cap OCCT would have built.
 *
 * Two things are CHECKED rather than assumed, and both resolve to "refuse":
 *  - every vertex of every inner wire lies in that plane. See
 *    perf/findings/S15-holes.md P12 for why no fixture reaches this; it is a
 *    backstop against a future change breaking one of the four agreements
 *    between the outer sweep and the holes' that make it true.
 *  - each inner wire runs OPPOSITE to the face's own outer bound. That is
 *    read off the projected signed areas rather than assumed from the fact
 *    that arc_loop_wire builds every loop counter-clockwise, because a wire
 *    that circulates the wrong way makes a face whose "hole" adds material
 *    instead of removing it, and nothing downstream would notice. */
static bool planar_cap(const TopoDS_Wire &outer,
                       const std::vector<TopoDS_Wire> &inner, TopoDS_Face &out)
{
    BRepLib_MakeFace mf(outer, Standard_True);
    if (!mf.IsDone())
        return false;
    TopoDS_Face f = mf.Face();
    if (inner.empty()) {
        out = f;
        return true;
    }
    Handle(Geom_Plane) gp_pl =
        Handle(Geom_Plane)::DownCast(BRep_Tool::Surface(f));
    if (gp_pl.IsNull())
        return false;
    const gp_Pln pln = gp_pl->Pln();
    Bnd_Box bb;
    BRepBndLib::Add(outer, bb);
    if (bb.IsVoid())
        return false;
    double x0, y0, z0, x1, y1, z1;
    bb.Get(x0, y0, z0, x1, y1, z1);
    const double tol =
        1.0e-6 * gp_Pnt(x0, y0, z0).Distance(gp_Pnt(x1, y1, z1))
        + Precision::Confusion();
    const TopoDS_Wire ow = BRepTools::OuterWire(f);
    if (ow.IsNull())
        return false;
    const double osense = wire_sense_on(ow, pln);
    if (std::fabs(osense) < 1e-12)
        return false;
    BRep_Builder bb2;
    for (const TopoDS_Wire &w : inner) {
        for (TopExp_Explorer e(w, TopAbs_VERTEX); e.More(); e.Next())
            if (pln.Distance(BRep_Tool::Pnt(TopoDS::Vertex(e.Current())))
                > tol)
                return false; /* not coplanar with the outer end section */
        const double is = wire_sense_on(w, pln);
        if (std::fabs(is) < 1e-12)
            return false;
        bb2.Add(f, (is * osense > 0.0) ? TopoDS::Wire(w.Reversed()) : w);
    }
    out = f;
    return true;
}

/* v27 — the holed sweep, ASSEMBLED.
 *
 * `mk` has been Built and NOT made solid: BRepFill_PipeShell::MakeSolid caps
 * the shell in place and turns FirstShape()/LastShape() from the end WIRES
 * into the end FACES, so the wires this needs are only available before it.
 *
 * Returns false for anything it does not recognise, and the caller then runs
 * the v26 boolean. Every check below is a reason to fall back, never a reason
 * to fail the sweep. */
static bool assemble_holed_pipe(BRepOffsetAPI_MakePipeShell &mk,
                                const std::vector<TopoDS_Wire> &holes,
                                const TopoDS_Wire &spine, int orientation,
                                double taper_deg, bool corrected_frenet,
                                Standard_Boolean with_correction,
                                TopoDS_Shape &out)
{
    const TopoDS_Shape lat0 = mk.Shape();
    const TopoDS_Shape a0 = mk.FirstShape(), a1 = mk.LastShape();
    if (lat0.IsNull() || a0.IsNull() || a1.IsNull()
        || a0.ShapeType() != TopAbs_WIRE || a1.ShapeType() != TopAbs_WIRE
        || a0.IsSame(a1))
        return false; /* IsSame means a closed spine: one end, not two */

    std::vector<TopoDS_Shape> lat;
    std::vector<TopoDS_Wire> w0, w1;
    lat.push_back(lat0);
    for (const TopoDS_Wire &h : holes) {
        BRepOffsetAPI_MakePipeShell hm(spine);
        configure_hole_pipe(hm, h, orientation, taper_deg, corrected_frenet,
                            with_correction);
        hm.Build();
        if (!hm.IsDone())
            return false;
        const TopoDS_Shape hl = hm.Shape();
        const TopoDS_Shape h0 = hm.FirstShape(), h1 = hm.LastShape();
        if (hl.IsNull() || h0.IsNull() || h1.IsNull()
            || h0.ShapeType() != TopAbs_WIRE || h1.ShapeType() != TopAbs_WIRE)
            return false;
        lat.push_back(hl);
        w0.push_back(TopoDS::Wire(h0));
        w1.push_back(TopoDS::Wire(h1));
    }

    TopoDS_Face c0, c1;
    if (!planar_cap(TopoDS::Wire(a0), w0, c0)
        || !planar_cap(TopoDS::Wire(a1), w1, c1))
        return false;

    /* Sewing rather than a hand-built shell, deliberately. The caps' outer
     * wires ARE the lateral shells' free boundaries — the same TShapes — so
     * there is little for it to match, and in exchange it settles the face
     * orientations (the hole's shell has to face INTO the hole) and reports
     * NbFreeEdges(), which is the closed-shell test this needs anyway. */
    BRepBuilderAPI_Sewing sew(Precision::Confusion());
    int want = 2;
    for (const TopoDS_Shape &s : lat) {
        sew.Add(s);
        for (TopExp_Explorer e(s, TopAbs_FACE); e.More(); e.Next())
            ++want;
    }
    sew.Add(c0);
    sew.Add(c1);
    sew.Perform();
    const TopoDS_Shape sewn = sew.SewedShape();
    if (sewn.IsNull() || sew.NbFreeEdges() != 0 || sew.NbMultipleEdges() != 0)
        return false;

    int nshell = 0, nface = 0;
    TopoDS_Shell shell;
    for (TopExp_Explorer e(sewn, TopAbs_SHELL); e.More(); e.Next()) {
        shell = TopoDS::Shell(e.Current());
        ++nshell;
    }
    for (TopExp_Explorer e(sewn, TopAbs_FACE); e.More(); e.Next())
        ++nface;
    if (nshell != 1 || nface != want)
        return false;

    /* Global sense, exactly as BRepFill_PipeShell::MakeSolid settles it. */
    TopoDS_Solid solid;
    BRep_Builder bld;
    bld.MakeSolid(solid);
    bld.Add(solid, shell);
    BRepClass3d_SolidClassifier sc(solid);
    sc.PerformInfinitePoint(Precision::Confusion());
    if (sc.State() == TopAbs_IN) {
        TopoDS_Solid flipped;
        bld.MakeSolid(flipped);
        bld.Add(flipped, TopoDS::Shell(shell.Reversed()));
        solid = flipped;
    }
    solid.Closed(Standard_True);
    if (!has_solid_material(solid))
        return false;
    out = solid;
    return true;
}

/* Runs a MakePipeShell that has already been given its mode and profile, and
 * returns the solid. Shared by sweep and coil. */
static occt_shape *finish_pipe(BRepOffsetAPI_MakePipeShell &mk,
                               const std::vector<TopoDS_Wire> &holes,
                               const TopoDS_Wire &spine, int orientation,
                               double taper_deg, const char *who,
                               bool corrected_frenet,
                               Standard_Boolean with_correction,
                               bool holes_are_separate)
{
    mk.Build();
    if (!mk.IsDone()) {
        set_err(who, "the sweep failed (path too tight for the section?)");
        return nullptr;
    }

    /* v27: assemble the annulus when every hole is really a hole, and fall
     * back to v26's subtraction when it is not. `mk` must NOT be made solid
     * before the attempt — MakeSolid caps the shell in place and turns the end
     * WIRES the assembly needs into the end FACES. */
    TopoDS_Shape body;
    bool assembled = false;
    if (!holes.empty() && holes_are_separate)
        assembled = assemble_holed_pipe(mk, holes, spine, orientation,
                                        taper_deg, corrected_frenet,
                                        with_correction, body);

    if (!assembled) {
        if (!mk.MakeSolid()) {
            set_err(who, "the swept surface could not be closed into a solid");
            return nullptr;
        }
        body = mk.Shape();
        if (!has_solid_material(body)) {
            set_err(who, "the sweep produced no material");
            return nullptr;
        }
        /* Holes are swept separately and cut, for the same reason the extrude and
         * revolve paths do it: a multi-wire section is not reliable here.
         *
         * v27: this is now the FALLBACK, taken when the assembly above declined —
         * a hole that pokes outside the outer boundary, two holes that overlap or
         * nest, an end section that is not planar, a sew that did not close. It is
         * the v26 code unchanged, deliberately: the claim "the fallback produces
         * what the boolean produced" is only as good as the fallback BEING the
         * boolean. The holes are swept a second time here, which costs one sweep
         * per hole on a path that was already going to pay for a boolean. */
        for (const TopoDS_Wire &h : holes) {
            BRepOffsetAPI_MakePipeShell hm(spine);
            hm.SetTransitionMode(BRepBuilderAPI_RightCorner);
            /* v24: the hole is swept along the SAME spine wire, so it inherits the
             * smoothing for free — but it must inherit the TRIHEDRON too, or the
             * hole spirals through a body that does not. The caller says which,
             * rather than this function guessing from the spine: the coil's spine
             * has always been a curve and its holes have always been Frenet, and a
             * guess here would change that silently. */
            /* v26, and this is the half the first measurement of the fix
             * uncovered: `orientation` has been a parameter of this function since
             * v15 and its first line threw it away with `(void)orientation`. So a
             * hole was swept with a Frenet trihedron even when its body was swept
             * with a fixed one, and repairing WithCorrection alone left
             * orientation 1 at +0.17 % instead of -3.17 %. Both are the same
             * defect — the hole is not placed the way its body is placed — and
             * both parameters of that placement now come from the body. */
            if (orientation == 1)
                hm.SetMode(gp_Ax2(gp::Origin(), gp_Dir(0, 0, 1), gp_Dir(1, 0, 0)));
            else
                hm.SetMode(corrected_frenet ? Standard_False : Standard_True);
            /* `with_correction` is the CALLER'S, not a hard-coded
             * Standard_True. It had been True here since v15 while
             * occt_sweep_profile added the OUTER wire with the caller's own
             * setting — Standard_False for orientations 0 and 1 — so the two wires
             * of one solid were placed against different frames and the hole did
             * not sit where the body was.
             *
             * The measurement that pins it needs no analytic model: a tube's
             * volume must be the difference of the two single-loop sweeps that
             * make it. On a 24-segment r=6 ring with an r=3 hole over the arc
             * path, outer 6 708.589649 minus hole 1 677.147412 is 5 031.442237,
             * and the tube came out 4 871.741766 — 3.17 % short.
             *
             * The control is already in the code: ORIENTATION 2 passes
             * Standard_True, which is what this line hard-coded, and its tube is
             * exact to every digit. So is occt_coil_profile's, which also passes
             * True. Threading the caller's value through leaves both of those
             * untouched and repairs the two that disagreed. */
            if (taper_deg != 0.0) {
                const double k = std::tan(taper_deg * M_PI / 180.0);
                Handle(Law_Linear) law = new Law_Linear();
                law->Set(0.0, 1.0, 1.0, 1.0 + k);
                hm.SetLaw(h, law, Standard_False, with_correction);
            } else {
                hm.Add(h, Standard_False, with_correction);
            }
            hm.Build();
            if (!hm.IsDone() || !hm.MakeSolid()) {
                set_err(who, "sweeping a hole failed");
                return nullptr;
            }
            BRepAlgoAPI_Cut cut(body, hm.Shape());
            if (!cut.IsDone() || !has_solid_material(cut.Shape())) {
                set_err(who, "cutting a hole out of the sweep failed");
                return nullptr;
            }
            body = cut.Shape();
        }
    }
    ShapeUpgrade_UnifySameDomain uni(body, Standard_True, Standard_True,
                                     Standard_False);
    uni.Build();
    return wrap(uni.Shape(), who);
}

extern "C" occt_shape *occt_sweep_profile_ex(const double *xyb,
                                             const int *loop_counts,
                                             int nloops, const double *mat34,
                                             const double *path_pts, int npath,
                                             int orientation, double taper_deg,
                                             double twist_deg, int path_mode)
{
    OCCT_TRY("occt_sweep_profile")
    if (std::fabs(twist_deg) > 1e-9) {
        /* Refused, not ignored: a sweep that quietly did not twist is a wrong
         * part, and the user has no way to see that from the result. */
        set_err("occt_sweep_profile", "twist is not implemented yet");
        return nullptr;
    }
    if (path_mode < OCCT_SWEEP_PATH_AUTO || path_mode > OCCT_SWEEP_PATH_SMOOTH) {
        set_err("occt_sweep_profile", "unknown path mode");
        return nullptr;
    }
    TopoDS_Wire outer, spine;
    std::vector<TopoDS_Wire> holes;
    if (!placed_profile_wires(xyb, loop_counts, nloops, mat34,
                              "occt_sweep_profile", outer, holes))
        return nullptr;
    /* v27: A HOLE NO LONGER COSTS MORE THAN THE CORNERS SAVE — usually.
     *
     * v24's reason for forcing a holed profile back onto the polyline spine is
     * quoted here because it is still exactly right about the boolean: on a
     * polyline spine the cut is between two solids made of planes and it costs
     * 85.4 ms; on a smoothed spine it is between two made of general swept
     * surfaces and it costs 21 653.6 ms — 99.7 % of the call, against 258.7 ms
     * for the whole v23 operation (S14 §4.1). So a holed profile kept v23's
     * spine, and with it v23's outright FAILURE at 1200 segments.
     *
     * finish_pipe no longer cuts. It assembles, at 7 952.7 ms for a
     * 1200-segment holed profile that the boolean route does not build at all
     * (perf/findings/S15-holes.md §2.2). The restriction's reason is gone with
     * the boolean, so the restriction goes.
     *
     * It goes ONLY where the assembly can run. When a hole is not strictly
     * inside the outer boundary, or two holes overlap, finish_pipe falls back
     * to the v26 boolean — and that fallback must not land on the spine that
     * makes the boolean 80x slower. So the guard decides the spine too, and
     * AUTO keeps v24's behaviour exactly in the case v24's arithmetic was
     * about.
     *
     * OCCT_SWEEP_PATH_SMOOTH is still deliberately NOT restricted: it is an
     * explicit request from a caller who has decided for itself, and a caller
     * that declares SMOOTH for a poking hole gets the slow boolean it asked
     * for rather than a silently different spine. */
    const bool holes_are_separate =
        profile_holes_are_separate(xyb, loop_counts, nloops);
    const int effective_mode =
        (path_mode == OCCT_SWEEP_PATH_AUTO && nloops > 1
         && !holes_are_separate)
            ? OCCT_SWEEP_PATH_POLY
            : path_mode;
    bool smoothed = false;
    if (!spine_from_points_ex(path_pts, npath, effective_mode,
                              "occt_sweep_profile", spine, &smoothed))
        return nullptr;

    BRepOffsetAPI_MakePipeShell mk(spine);
    /* A path with a SHARP corner (an L, the common case for a swept bar) fails
     * outright in the default Transformed mode. RightCorner miters the section
     * through the corner, which is both what OCCT can build and what a swept
     * bar actually looks like.
     *
     * v24: still set, and now usually inert. It applies to the joints between
     * spine EDGES, and a smoothed run is one edge — so a path that came from
     * the curve sampler has no joints left and pays nothing, while a drawn
     * corner is still a joint and is still mitered exactly as before. */
    mk.SetTransitionMode(BRepBuilderAPI_RightCorner);
    /* 1 = Fixed keeps the section's own orientation; 0 and 2 both follow the
     * path, 2 additionally correcting against the spine's frame.
     *
     * v25: "Fixed" was calling the WRONG OCCT MODE, and had been since v15.
     * SetMode(gp_Dir) is BRepFill_PipeShell::Set(const gp_Dir&), which builds a
     * GeomFill_ConstantBiNormal — a law that pins the binormal and then, in its
     * D0, REPLACES the frame's tangent with `Normal ^ BiNormal`, i.e. with the
     * real tangent's projection perpendicular to the binormal. On a path that
     * climbs at 25 deg from +Z that projection is 65 deg away from where the
     * spine actually goes, and on a polyline the mismatch compounds at every
     * joint into a shell that passes through itself.
     *
     * SetMode(gp_Ax2) is Set(const gp_Ax2&) -> GeomFill_IsFixed, whose own
     * documentation is "all sections will be parallel" — which is what this
     * comment has always said orientation 1 means.
     *
     * Measured on a 10x10 square over the arc path (S14 §9.2), against an
     * analytic 6000 that Cavalieri gives whatever the path does in XY:
     *
     *     spans   ConstantBiNormal            Fixed
     *       2     7 448.5352  +24.1 % INVALID  6 000.0000 valid
     *       4     8 980.7801  +49.7 % INVALID  6 000.0000 valid
     *      16    16 429.0722 +173.8 % INVALID  6 000.0000 valid
     *
     * A single straight segment is 4 000.0000 / 6 000.0000 in BOTH laws, which
     * is why nothing caught this: the mode only goes wrong once the path bends.
     *
     * The axis is a readable constant rather than something derived from
     * mat34, and that is measured, not assumed: GeomFill_Fixed is a CONSTANT
     * trihedron, so it cancels out of the location law's relative transform.
     * Three unrelated gp_Ax2 values — (origin, +Z, +X), ((7,-3,11), +X, +Y) and
     * (origin, (1,2,3), (3,0,-1)) — give the same solid to every printed digit
     * (S14 §9.3). */
    if (orientation == 1)
        mk.SetMode(gp_Ax2(gp::Origin(), gp_Dir(0, 0, 1), gp_Dir(1, 0, 0)));
    else
        /* v24: on a spine carrying a real curve, plain Frenet also carries its
         * TORSION and spins the section about the tangent — 81 deg over this
         * project's own sweep fixture, which a circular section hides and a
         * square one does not. Corrected Frenet is the trihedron that
         * reproduces what the polyline did, and on a polyline the two are
         * measurably identical, so this changes nothing where nothing was
         * smoothed. */
        mk.SetMode(smoothed ? Standard_False : Standard_True);
    const Standard_Boolean correct =
        orientation == 2 ? Standard_True : Standard_False;
    if (taper_deg != 0.0) {
        const double k = std::tan(taper_deg * M_PI / 180.0);
        Handle(Law_Linear) law = new Law_Linear();
        law->Set(0.0, 1.0, 1.0, 1.0 + k);
        mk.SetLaw(outer, law, Standard_False, correct);
    } else {
        mk.Add(outer, Standard_False, correct);
    }
    return finish_pipe(mk, holes, spine, orientation, taper_deg,
                       "occt_sweep_profile", smoothed, correct,
                       holes_are_separate);
    OCCT_CATCH("occt_sweep_profile", nullptr)
}

extern "C" occt_shape *occt_sweep_profile(const double *xyb,
                                          const int *loop_counts, int nloops,
                                          const double *mat34,
                                          const double *path_pts, int npath,
                                          int orientation, double taper_deg,
                                          double twist_deg)
{
    return occt_sweep_profile_ex(xyb, loop_counts, nloops, mat34, path_pts,
                                 npath, orientation, taper_deg, twist_deg,
                                 OCCT_SWEEP_PATH_AUTO);
}

extern "C" occt_shape *occt_loft_sections(const double *xyb,
                                          const int *loop_counts,
                                          const double *mats, int nsections,
                                          int solid, int ruled, int closed)
{
    OCCT_TRY("occt_loft_sections")
    if (!xyb || !loop_counts || !mats || nsections < 2) {
        set_err("occt_loft_sections", "a loft needs at least 2 sections");
        return nullptr;
    }
    BRepOffsetAPI_ThruSections mk(solid != 0, ruled != 0, 1.0e-6);
    const double *p = xyb;
    for (int i = 0; i < nsections; ++i) {
        if (loop_counts[i] < 2) {
            set_err("occt_loft_sections", "a section needs at least 2 vertices");
            return nullptr;
        }
        const double a = arc_loop_signed_area(p, loop_counts[i]);
        if (std::fabs(a) < 1e-12) {
            set_err("occt_loft_sections", "a section is degenerate");
            return nullptr;
        }
        bool ok = false;
        TopoDS_Wire w = arc_loop_wire(p, loop_counts[i], a > 0.0, &ok);
        if (!ok) {
            set_err("occt_loft_sections", "section wire construction failed");
            return nullptr;
        }
        gp_Trsf t;
        if (!trsf_from_mat34(mats + 12 * i, t, "occt_loft_sections"))
            return nullptr;
        BRepBuilderAPI_Transform mv(w, t, Standard_True);
        if (!mv.IsDone()) {
            set_err("occt_loft_sections", "placing a section failed");
            return nullptr;
        }
        mk.AddWire(TopoDS::Wire(mv.Shape()));
        p += 3 * loop_counts[i];
    }
    if (closed != 0) {
        /* Closed Loop: repeat the first section so the run comes back round. */
        const double a0 = arc_loop_signed_area(xyb, loop_counts[0]);
        bool ok = false;
        TopoDS_Wire w0 = arc_loop_wire(xyb, loop_counts[0], a0 > 0.0, &ok);
        gp_Trsf t0;
        if (ok && trsf_from_mat34(mats, t0, "occt_loft_sections")) {
            BRepBuilderAPI_Transform mv0(w0, t0, Standard_True);
            if (mv0.IsDone())
                mk.AddWire(TopoDS::Wire(mv0.Shape()));
        }
    }
    mk.CheckCompatibility(Standard_True);
    mk.Build();
    if (!mk.IsDone()) {
        set_err("occt_loft_sections",
                "the loft failed (are the sections compatible?)");
        return nullptr;
    }
    if (solid != 0 && !has_solid_material(mk.Shape())) {
        set_err("occt_loft_sections", "the loft produced no material");
        return nullptr;
    }
    ShapeUpgrade_UnifySameDomain uni(mk.Shape(), Standard_True, Standard_True,
                                     Standard_False);
    uni.Build();
    return wrap(uni.Shape(), "occt_loft_sections");
    OCCT_CATCH("occt_loft_sections", nullptr)
}

extern "C" occt_shape *occt_coil_profile(const double *xyb,
                                         const int *loop_counts, int nloops,
                                         const double *mat34, double ax_px,
                                         double ax_py, double ax_pz,
                                         double ax_dx, double ax_dy,
                                         double ax_dz, double revolutions,
                                         double height, double taper_deg,
                                         int clockwise, int close_start,
                                         int close_end)
{
    OCCT_TRY("occt_coil_profile")
    if (close_start != 0 || close_end != 0) {
        set_err("occt_coil_profile", "coil ends are not implemented yet");
        return nullptr;
    }
    if (!(revolutions > 0.0)) {
        set_err("occt_coil_profile", "revolutions must be > 0");
        return nullptr;
    }
    const gp_Vec axis(ax_dx, ax_dy, ax_dz);
    if (axis.Magnitude() < 1e-12) {
        set_err("occt_coil_profile", "axis direction is degenerate");
        return nullptr;
    }
    TopoDS_Wire outer;
    std::vector<TopoDS_Wire> holes;
    if (!placed_profile_wires(xyb, loop_counts, nloops, mat34,
                              "occt_coil_profile", outer, holes))
        return nullptr;

    /* Helix radius = distance from the axis to the section's centroid, so the
     * coil passes through where the user drew the profile. */
    GProp_GProps props;
    BRepGProp::LinearProperties(outer, props);
    const gp_Pnt c = props.CentreOfMass();
    const gp_Dir adir(axis);
    const gp_Pnt apt(ax_px, ax_py, ax_pz);
    const gp_Vec w(apt, c);
    const gp_Pnt foot = apt.Translated(gp_Vec(adir) * w.Dot(gp_Vec(adir)));
    const double r = gp_Vec(foot, c).Magnitude();
    if (r < 1e-9) {
        set_err("occt_coil_profile", "the profile sits on the axis");
        return nullptr;
    }
    /* Frame the cylinder so u = 0 passes through the section: the helix then
     * starts AT the profile instead of some arbitrary meridian. */
    const gp_Ax3 frame(foot, adir, gp_Dir(gp_Vec(foot, c)));
    Handle(Geom_CylindricalSurface) cyl = new Geom_CylindricalSurface(frame, r);
    const double turns = revolutions * 2.0 * M_PI;
    /* A straight line in the cylinder's (u, v) space IS a helix: u winds
     * around, v climbs the axis. Slope = total rise over total turn. */
    const double slope = height / turns;
    /* v28 (S17): only the WINDING is negated, never the climb.
     *
     * What (u, v) mean is settled by ElSLib::CylinderD0, which
     * Geom_CylindricalSurface::D0 delegates to:
     *     P(u, v) = Loc + R cos u . XDir + R sin u . YDir + v . ZDir
     * and the frame above is built with gp_Ax3(P, N, Vx), whose inline body
     * (gp_Ax3.hxx) sets vydir = theN ^ vxdir -- YDir = N x XDir, so the frame
     * is right-handed and Direct() is 1. Increasing u therefore turns
     * COUNTERCLOCKWISE about the axis while increasing v advances along it:
     * (du > 0, dv > 0) is a right-handed screw and the left-handed one is
     * (du < 0, dv > 0).
     *
     * Until v28 this negated BOTH components for `clockwise`, giving
     * (-1, -slope). That is antiparallel to (1, slope) -- the same line
     * through the origin in (u, v), so the same point set, so the SAME
     * right-handed helix, merely traversed backwards and occupying
     * v in [-height, 0]. A user who ticked the box got a coil hanging BELOW
     * the profile with its handedness unchanged, and no volume check could
     * ever see it: the helix length, and so the material, is identical either
     * way. S16 measured exactly that (z[-50.9969, 0.9968] against
     * z[-0.9968, 50.9969]); perf/findings/S17-oblique.md section 0.1 has the
     * upstream lines.
     *
     * With one component negated the coil is the mirror image of the
     * counterclockwise one through the plane containing the axis and the
     * starting section -- opposite handedness, same rise, same volume, which
     * is what the header's "picks the handedness" has always claimed.
     *
     * `plen` below is unaffected: gp_Dir2d normalises, so |d2.X()| is
     * 1/sqrt(1+slope^2) whichever sign the winding has, and the line still
     * reaches u = -+turns, v = +height at t = plen. */
    const gp_Dir2d d2(clockwise != 0 ? -1.0 : 1.0, slope);
    Handle(Geom2d_Line) line2d = new Geom2d_Line(gp_Pnt2d(0.0, 0.0), d2);
    /* Parameter length along the 2D line that spans `turns` in u. */
    const double plen = turns / std::fabs(d2.X());
    BRepBuilderAPI_MakeEdge he(line2d, cyl, 0.0, plen);
    if (!he.IsDone()) {
        set_err("occt_coil_profile", "helix construction failed");
        return nullptr;
    }
    TopoDS_Edge hedge = he.Edge();
    BRepLib::BuildCurve3d(hedge);
    BRepBuilderAPI_MakeWire hw(hedge);
    if (!hw.IsDone()) {
        set_err("occt_coil_profile", "helix wire construction failed");
        return nullptr;
    }
    const TopoDS_Wire spine = hw.Wire();

    BRepOffsetAPI_MakePipeShell mk(spine);
    mk.SetMode(Standard_True); /* a coil always follows its helix */
    if (taper_deg != 0.0) {
        const double k = std::tan(taper_deg * M_PI / 180.0);
        Handle(Law_Linear) law = new Law_Linear();
        law->Set(0.0, 1.0, 1.0, 1.0 + k);
        mk.SetLaw(outer, law, Standard_False, Standard_True);
    } else {
        mk.Add(outer, Standard_False, Standard_True);
    }
    /* Frenet for the holes, as it has always been: the coil's own outer sweep
     * is Frenet and the two must agree. And Standard_True for the correction,
     * because that is what the coil adds its OUTER wire with, twenty lines
     * up — which is why the coil has never had the defect v26 repairs in the
     * sweep. */
    return finish_pipe(mk, holes, spine, 0, taper_deg, "occt_coil_profile",
                       false, Standard_True,
                       profile_holes_are_separate(xyb, loop_counts, nloops));
    OCCT_CATCH("occt_coil_profile", nullptr)
}

/* ---- v21 (M232): mesh -> B-Rep ------------------------------------------ */

/* Turns OCCT's own faults into exceptions this shim can catch.
 *
 * Without it, a fault INSIDE OCCT — a null dereference, a bad access, a
 * division by zero in some algorithm handed geometry it did not expect — is a
 * raw SIGSEGV. The process dies. Not an exception, so none of the catch
 * clauses below ever run; not a Dart error, so the app's log ends mid-line
 * with no explanation and iOS files it as no crash at all.
 *
 * With it, the same fault arrives as an OSD_Signal, which derives from
 * Standard_Failure, which every entry point here already catches. The user
 * gets a sentence instead of a dead app.
 *
 * Standard_False: do NOT trap floating-point exceptions. Geometry code
 * produces the occasional NaN or infinity in the ordinary course of
 * converging a fit, and turning those into crashes would be trading one bad
 * failure for a worse one.
 *
 * Idempotent and lazy rather than a static initialiser: the handlers are
 * installed on the calling thread, and this shim is called from exactly one
 * (the header says so), so installing them on first use is both correct and
 * easier to reason about than static-init order across a static library. */
static void ensure_signal_handlers()
{
    static bool done = false;
    if (done) return;
    done = true;
    try {
        OSD::SetSignal(Standard_False);
    } catch (...) {
        /* An old or restricted platform that will not let us install them.
         * Nothing to do but carry on without the safety net. */
    }
}

extern "C" occt_shape *occt_brep_from_mesh(const double *xyz, int nv,
                                           const int *tri, int nt,
                                           int mode, double tol_frac,
                                           double sharp_deg, int max_faceted,
                                           int *report_ints,
                                           double *report_reals)
{
    OCCT_TRY("occt_brep_from_mesh")
    ensure_signal_handlers();
    meshrecon::Report rep;
    meshrecon::ClearReport(rep);

    /* Publish the report on EVERY path, including the early refusals below.
     * A caller that has to explain a failure to a user needs the numbers most
     * exactly when there is no shape to look at. */
    struct Publish {
        const meshrecon::Report &r;
        int *ints;
        double *reals;
        ~Publish()
        {
            if (ints) {
                ints[OCCT_MR_TRIANGLES_IN] = r.triangles_in;
                ints[OCCT_MR_VERTICES_IN] = r.vertices_in;
                ints[OCCT_MR_TRIANGLES_USED] = r.triangles_used;
                ints[OCCT_MR_VERTICES_WELDED] = r.vertices_welded;
                ints[OCCT_MR_NON_MANIFOLD_EDGES] = r.non_manifold_edges;
                ints[OCCT_MR_BOUNDARY_EDGES] = r.boundary_edges;
                ints[OCCT_MR_FLIPPED_TRIANGLES] = r.flipped_triangles;
                ints[OCCT_MR_PATCHES] = r.patches;
                ints[OCCT_MR_PLANES] = r.planes;
                ints[OCCT_MR_CYLINDERS] = r.cylinders;
                ints[OCCT_MR_CONES] = r.cones;
                ints[OCCT_MR_SPHERES] = r.spheres;
                ints[OCCT_MR_TORI] = r.tori;
                ints[OCCT_MR_FREEFORM] = r.freeform;
                ints[OCCT_MR_FACETED_PATCHES] = r.faceted_patches;
                ints[OCCT_MR_FACES_BUILT] = r.faces_built;
                ints[OCCT_MR_FACES_FAILED] = r.faces_failed;
                ints[OCCT_MR_ANALYTIC_EDGES] = r.analytic_edges;
                ints[OCCT_MR_APPROXIMATED_EDGES] = r.approximated_edges;
                ints[OCCT_MR_SHELLS] = r.shells;
                ints[OCCT_MR_SOLIDS] = r.solids;
                ints[OCCT_MR_CLOSED] = r.closed;
            }
            if (reals) {
                reals[OCCT_MR_FIT_RMS] = r.fit_rms;
                reals[OCCT_MR_DIAGONAL] = r.diagonal;
            }
        }
    } publish{rep, report_ints, report_reals};

    if (!xyz || !tri || nv < 3 || nt < 1) {
        set_err("occt_brep_from_mesh", "no mesh data");
        return nullptr;
    }
    /* nv*3 and nt*3 are computed as int in the reader; refuse sizes where that
     * would overflow rather than index past the end of the caller's arrays. */
    if (nv > 700000000 || nt > 700000000) {
        set_err("occt_brep_from_mesh", "mesh is too large");
        return nullptr;
    }

    meshrecon::Params p = meshrecon::Defaults();
    p.mode = (mode == 0) ? 0 : 1;
    if (tol_frac > 0) p.tol_frac = tol_frac;
    if (sharp_deg > 0) p.sharp_deg = sharp_deg;
    if (max_faceted > 0) p.max_faceted_triangles = max_faceted;

    std::string err;
    const TopoDS_Shape out =
        meshrecon::Reconstruct(xyz, nv, tri, nt, p, rep, err);
    if (out.IsNull()) {
        set_err("occt_brep_from_mesh",
                err.empty() ? "the mesh could not be converted" : err.c_str());
        return nullptr;
    }
    return wrap(out, "occt_brep_from_mesh");
    OCCT_CATCH("occt_brep_from_mesh", nullptr)
}
