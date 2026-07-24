/*
 * iPadProCAD — flat C-ABI shim over OpenCASCADE (OCCT). See occt_capi.h.
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

#include <cmath>
#include <cstdio>
#include <cstring>
#include <vector>

#include <Standard_Failure.hxx>
#include <Standard_Version.hxx>

#include <gp_Ax2.hxx>
#include <gp_Dir.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>
#include <gp_Circ.hxx>
#include <gp_Elips.hxx>
#include <gp_Cylinder.hxx>

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

#include <STEPControl_Reader.hxx>
#include <STEPControl_Writer.hxx>
#include <STEPControl_StepModelType.hxx>
#include <IFSelect_ReturnStatus.hxx>

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
};

static occt_shape *wrap(const TopoDS_Shape &s, const char *where)
{
    if (s.IsNull()) {
        set_err(where, "resulting shape is null");
        return nullptr;
    }
    return new occt_shape{s};
}

/* ---- version / errors --------------------------------------------------- */

extern "C" const char *occt_version(void)
{
    /* Keep the grep marker "iPadProCAD OCCT shim" a single literal. */
    static char buf[128] = "";
    if (!buf[0]) {
        std::snprintf(buf, sizeof(buf), "iPadProCAD OCCT shim v7 (OCCT %s)",
                      OCC_VERSION_COMPLETE);
    }
    return buf;
}

extern "C" int occt_shim_version(void) { return 7; }

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
             * sagitta s = b·chord/2 along the LEFT normal of p0->p1 (positive
             * bulge = counter-clockwise, i.e. the arc bows left). */
            const double s = b * 0.5 * chord;
            const double nx = -dy / chord, ny = dx / chord;
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

extern "C" occt_shape *occt_cut(const occt_shape *a, const occt_shape *b)
{
    OCCT_TRY("occt_cut")
    if (!a || !b) {
        set_err("occt_cut", "null operand");
        return nullptr;
    }
    BRepAlgoAPI_Cut cut(a->s, b->s);
    if (!cut.IsDone()) {
        set_err("occt_cut", "boolean cut did not complete");
        return nullptr;
    }
    const TopoDS_Shape r = cut.Shape();
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

extern "C" occt_shape *occt_transform(const occt_shape *shape,
                                      const double *mat34)
{
    OCCT_TRY("occt_transform")
    if (!shape || !mat34) {
        set_err("occt_transform", "null argument");
        return nullptr;
    }
    gp_Trsf t;
    /* Rigidity is enforced HERE, not left to gp_Trsf::SetValues: that
     * accepts an orthogonal matrix TIMES A SCALE FACTOR, so a uniform
     * scale would sail through and silently resize the solid. The header
     * promises a pure rotation, so check orthonormality (columns unit and
     * mutually perpendicular) and a right-handed determinant of +1. */
    {
        const double c[3][3] = {{mat34[0], mat34[1], mat34[2]},
                                {mat34[4], mat34[5], mat34[6]},
                                {mat34[8], mat34[9], mat34[10]}};
        const double tol = 1e-9;
        int ok = 1;
        for (int i = 0; i < 3 && ok; ++i) {
            for (int j = i; j < 3 && ok; ++j) {
                const double d = c[0][i] * c[0][j] + c[1][i] * c[1][j] +
                                 c[2][i] * c[2][j];
                if (std::fabs(d - (i == j ? 1.0 : 0.0)) > tol)
                    ok = 0;
            }
        }
        const double det =
            c[0][0] * (c[1][1] * c[2][2] - c[1][2] * c[2][1]) -
            c[0][1] * (c[1][0] * c[2][2] - c[1][2] * c[2][0]) +
            c[0][2] * (c[1][0] * c[2][1] - c[1][1] * c[2][0]);
        if (!ok || std::fabs(det - 1.0) > tol) {
            set_err("occt_transform",
                    "matrix is not a rigid motion (need an orthonormal "
                    "rotation with determinant +1; scale/shear/mirror "
                    "are refused)");
            return nullptr;
        }
    }
    t.SetValues(mat34[0], mat34[1], mat34[2], mat34[3],
                mat34[4], mat34[5], mat34[6], mat34[7],
                mat34[8], mat34[9], mat34[10], mat34[11]);
    BRepBuilderAPI_Transform tr(shape->s, t, Standard_True /* copy */);
    if (!tr.IsDone()) {
        set_err("occt_transform", "transform did not complete");
        return nullptr;
    }
    return wrap(tr.Shape(), "occt_transform");
    OCCT_CATCH("occt_transform", nullptr)
}

/* ---- v2: tessellation --------------------------------------------------- */

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
    BRepMesh_IncrementalMesh mesher(shape->s, lin_deflection,
                                    Standard_False, ang_deflection,
                                    Standard_False);
    (void)mesher;

    std::vector<double> verts, norms, edge_pts, edge_curves;
    std::vector<int> tris, edge_starts;
    edge_starts.push_back(0);

    /* Faces -> shaded triangles. Vertices are emitted PER FACE, so B-Rep
     * edges stay crisp while each curved face shades smoothly. */
    std::vector<int> tri_face;
    std::vector<double> face_infos;
    int face_idx = 0;
    for (TopExp_Explorer ex(shape->s, TopAbs_FACE); ex.More(); ex.Next()) {
        const TopoDS_Face face = TopoDS::Face(ex.Current());
        TopLoc_Location loc;
        Handle(Poly_Triangulation) tri = BRep_Tool::Triangulation(face, loc);
        if (tri.IsNull() || tri->NbTriangles() < 1)
            continue;
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
            case GeomAbs_Cone:   rec[0] = 2; break;
            case GeomAbs_Sphere: rec[0] = 3; break;
            case GeomAbs_Torus:  rec[0] = 4; break;
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
        BRepAdaptor_Curve curve(edge);
        GCPnts_TangentialDeflection disc(curve, ang_deflection,
                                         lin_deflection, 2);
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

extern "C" int occt_export_step(const occt_shape *shape, const char *path)
{
    OCCT_TRY("occt_export_step")
    if (!shape || !path || !*path) {
        set_err("occt_export_step", "null shape or path");
        return 0;
    }
    STEPControl_Writer writer;
    if (writer.Transfer(shape->s, STEPControl_AsIs) != IFSelect_RetDone) {
        set_err("occt_export_step", "shape transfer to STEP model failed");
        return 0;
    }
    if (writer.Write(path) != IFSelect_RetDone) {
        set_err("occt_export_step", "writing STEP file failed");
        return 0;
    }
    return 1;
    OCCT_CATCH("occt_export_step", 0)
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

/* ---- lifecycle -------------------------------------------------------------- */

extern "C" void occt_free_shape(occt_shape *shape)
{
    delete shape; /* delete nullptr is a no-op */
}
