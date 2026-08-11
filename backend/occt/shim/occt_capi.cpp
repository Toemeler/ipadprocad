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

#include <STEPControl_Reader.hxx>
#include <STEPControl_Writer.hxx>
#include <STEPControl_StepModelType.hxx>
#include <IFSelect_ReturnStatus.hxx>
/* M212 — a STEP file nobody has to apologise for: explicit units, an explicit
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
    /* Keep the grep marker "Prototype OCCT shim" a single literal. */
    static char buf[128] = "";
    if (!buf[0]) {
        std::snprintf(buf, sizeof(buf), "Prototype OCCT shim v18 (OCCT %s)",
                      OCC_VERSION_COMPLETE);
    }
    return buf;
}

extern "C" int occt_shim_version(void) { return 18; }

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

    std::vector<double> verts, norms, edge_pts, edge_curves;
    std::vector<int> tris, edge_starts;
    std::vector<int> edge_ids; /* v12: topological index per display edge */
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
            /* M213 (v18) — cone, sphere and torus used to record their TYPE
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

/* M212 — the write-side translation parameters, pinned EXPLICITLY.
 *
 * Every one of these has an OCCT default, and until M212 the exporter relied
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

/* M212 — writes `n` bodies as `n` named STEP products.
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

/* Unit direction that leaves [edge] and runs INTO [face], tangent to it.
 *
 * Built from the edge tangent oriented along the face's own boundary
 * traversal: with an outward normal and a CCW outer loop seen from outside,
 * the interior lies to the left, i.e. along nOut x T. Taking the orientation
 * from the face's explorer (rather than assuming FORWARD) is what makes this
 * work for the second face of the pair, where the shared edge is traversed
 * the other way. */
static bool into_face_dir(const TopoDS_Face &face, const TopoDS_Edge &edge,
                         double t, const gp_Dir &nOut, gp_Dir &out)
{
    TopAbs_Orientation ori = TopAbs_FORWARD;
    bool found = false;
    for (TopExp_Explorer ex(face, TopAbs_EDGE); ex.More(); ex.Next()) {
        if (ex.Current().IsSame(edge)) {
            ori = ex.Current().Orientation();
            found = true;
            break;
        }
    }
    if (!found)
        return false;
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

extern "C" int occt_shape_edge_info(const occt_shape *shape, int index,
                                    double *out12)
{
    OCCT_TRY("occt_shape_edge_info")
    double *out10 = out12; /* first ten fields are unchanged since v12 */
    if (!shape || !out12) {
        set_err("occt_shape_edge_info", "null argument");
        return 0;
    }
    TopTools_IndexedMapOfShape m;
    TopExp::MapShapes(shape->s, TopAbs_EDGE, m);
    if (index < 1 || index > m.Extent()) {
        set_err("occt_shape_edge_info", "edge index out of range");
        return 0;
    }
    const TopoDS_Edge edge = TopoDS::Edge(m.FindKey(index));
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

    TopTools_IndexedDataMapOfShapeListOfShape edgeFaces;
    TopExp::MapShapesAndAncestors(shape->s, TopAbs_EDGE, TopAbs_FACE,
                                  edgeFaces);
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
            /* The BISECTOR OF THE TWO INTO-FACE DIRECTIONS, not of the two
             * normals. The first attempt used the normals and reported every
             * edge convex: stepping inward along the averaged normal lands in
             * material for a concave edge just as much as for a convex one, so
             * it does not discriminate at all. Walking into the faces does:
             * for an exterior corner the bisector points into the solid, for
             * an interior corner it points into the void the corner opens
             * onto. */
            if (out12[10] > 1.0e-3 &&
                into_face_dir(f1, edge, tmid, n1, u1) &&
                into_face_dir(f2, edge, tmid, n2, u2)) {
                gp_Vec m(u1.XYZ() + u2.XYZ());
                if (m.Magnitude() > 1e-9) {
                    m.Normalize();
                    Bnd_Box bb;
                    BRepBndLib::Add(shape->s, bb);
                    const double step =
                        1.0e-3 * (bb.IsVoid() ? 1.0 : sqrt(bb.SquareExtent()));
                    BRepClass3d_SolidClassifier cls(shape->s);
                    cls.Perform(pm.Translated(m * step), 1.0e-7);
                    out12[11] = (cls.State() == TopAbs_IN) ? 1.0 : -1.0;
                }
            }
        }
    }
    return 1;
    OCCT_CATCH("occt_shape_edge_info", 0)
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
        if (modes[i] == 2 &&
            (!angle_deg || !(angle_deg[i] > 0.0) || angle_deg[i] >= 90.0)) {
            set_err("occt_chamfer_edges",
                    "chamfer angle must be in (0, 90) deg");
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

/* A spine wire through world-space points. Straight segments: the caller has
 * already sampled the curve it picked, so interpolating again would only add
 * error the user cannot see or control. */
static bool spine_from_points(const double *pts, int n, const char *who,
                              TopoDS_Wire &out)
{
    if (!pts || n < 2) {
        set_err(who, "a path needs at least 2 points");
        return false;
    }
    BRepBuilderAPI_MakePolygon poly;
    gp_Pnt prev(pts[0], pts[1], pts[2]);
    poly.Add(prev);
    int used = 1;
    for (int i = 1; i < n; ++i) {
        const gp_Pnt q(pts[3 * i], pts[3 * i + 1], pts[3 * i + 2]);
        if (q.Distance(prev) < 1e-9)
            continue; /* duplicate sample: an edge of zero length breaks sweeps */
        poly.Add(q);
        prev = q;
        ++used;
    }
    if (used < 2 || !poly.IsDone()) {
        set_err(who, "the path collapsed to a single point");
        return false;
    }
    out = poly.Wire();
    return true;
}

/* Runs a MakePipeShell that has already been given its mode and profile, and
 * returns the solid. Shared by sweep and coil. */
static occt_shape *finish_pipe(BRepOffsetAPI_MakePipeShell &mk,
                               const std::vector<TopoDS_Wire> &holes,
                               const TopoDS_Wire &spine, int orientation,
                               double taper_deg, const char *who)
{
    (void)orientation;
    mk.Build();
    if (!mk.IsDone()) {
        set_err(who, "the sweep failed (path too tight for the section?)");
        return nullptr;
    }
    if (!mk.MakeSolid()) {
        set_err(who, "the swept surface could not be closed into a solid");
        return nullptr;
    }
    TopoDS_Shape body = mk.Shape();
    if (!has_solid_material(body)) {
        set_err(who, "the sweep produced no material");
        return nullptr;
    }
    /* Holes are swept separately and cut, for the same reason the extrude and
     * revolve paths do it: a multi-wire section is not reliable here. */
    for (const TopoDS_Wire &h : holes) {
        BRepOffsetAPI_MakePipeShell hm(spine);
        hm.SetTransitionMode(BRepBuilderAPI_RightCorner);
        hm.SetMode(Standard_True);
        if (taper_deg != 0.0) {
            const double k = std::tan(taper_deg * M_PI / 180.0);
            Handle(Law_Linear) law = new Law_Linear();
            law->Set(0.0, 1.0, 1.0, 1.0 + k);
            hm.SetLaw(h, law, Standard_False, Standard_True);
        } else {
            hm.Add(h, Standard_False, Standard_True);
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
    ShapeUpgrade_UnifySameDomain uni(body, Standard_True, Standard_True,
                                     Standard_False);
    uni.Build();
    return wrap(uni.Shape(), who);
}

extern "C" occt_shape *occt_sweep_profile(const double *xyb,
                                          const int *loop_counts, int nloops,
                                          const double *mat34,
                                          const double *path_pts, int npath,
                                          int orientation, double taper_deg,
                                          double twist_deg)
{
    OCCT_TRY("occt_sweep_profile")
    if (std::fabs(twist_deg) > 1e-9) {
        /* Refused, not ignored: a sweep that quietly did not twist is a wrong
         * part, and the user has no way to see that from the result. */
        set_err("occt_sweep_profile", "twist is not implemented yet");
        return nullptr;
    }
    TopoDS_Wire outer, spine;
    std::vector<TopoDS_Wire> holes;
    if (!placed_profile_wires(xyb, loop_counts, nloops, mat34,
                              "occt_sweep_profile", outer, holes))
        return nullptr;
    if (!spine_from_points(path_pts, npath, "occt_sweep_profile", spine))
        return nullptr;

    BRepOffsetAPI_MakePipeShell mk(spine);
    /* A path with a SHARP corner (an L, the common case for a swept bar) fails
     * outright in the default Transformed mode. RightCorner miters the section
     * through the corner, which is both what OCCT can build and what a swept
     * bar actually looks like. */
    mk.SetTransitionMode(BRepBuilderAPI_RightCorner);
    /* 1 = Fixed keeps the section's own orientation; 0 and 2 both follow the
     * path, 2 additionally correcting against the spine's frame. */
    if (orientation == 1)
        mk.SetMode(gp_Dir(0, 0, 1));
    else
        mk.SetMode(Standard_True); /* Frenet */
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
                       "occt_sweep_profile");
    OCCT_CATCH("occt_sweep_profile", nullptr)
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
    const gp_Dir2d d2(clockwise != 0 ? -1.0 : 1.0,
                      clockwise != 0 ? -slope : slope);
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
    return finish_pipe(mk, holes, spine, 0, taper_deg, "occt_coil_profile");
    OCCT_CATCH("occt_coil_profile", nullptr)
}
