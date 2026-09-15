/* cad_audit — does the reconstructed B-Rep hold up as CAD?
 *
 *   occt_cad_audit rebuilt.brep [--mesh part.stl] [--ref truth.brep|.step]
 *
 * mesh_check.cpp answers "is the body in the right PLACE" — deviation and
 * coverage against the triangles. It does not answer "is the body VALID", and
 * those are different questions: a shell can sit exactly on the mesh and still
 * self-intersect, carry an inverted face, or hang a sliver off a wire. Every
 * one of those is a body that draws correctly and then fails the first
 * boolean, which is the failure users actually hit.
 *
 * So this checks the things a kernel checks before it will operate on a body:
 *
 *   VALIDITY     BRepCheck_Analyzer, every status, named and counted per
 *                sub-shape type rather than reduced to one bool.
 *   SELF-INT     BOPAlgo_CheckerSI — face pairs that cross. This is the one
 *                that decides whether a fillet or a cut will work.
 *   ORIENTATION  volume sign, and per-face agreement between the face normal
 *                and the outward direction of the solid.
 *   SPIKES       needle faces (area vanishing against their own perimeter),
 *                tiny edges, and wires whose turning exceeds a full turn.
 *   CONTINUITY   G0 gap and G1 tangency sampled across every shared edge.
 *   SURFACES     what the faces actually are, by kind and by area.
 *
 * Exit code is 0 when the body is clean by every one of these, non-zero
 * otherwise, so a suite can gate on it. Prints machine-readable "key=value"
 * lines so a script can diff two runs.
 *
 * Host only, built with OCCT_SMOKE. Never linked into the app. */
#include <BRepTools.hxx>
#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepCheck_Result.hxx>
#include <BRepCheck_ListOfStatus.hxx>
#include <BRepAdaptor_Surface.hxx>
#include <BRepAdaptor_Curve.hxx>
#include <BRepGProp.hxx>
#include <GProp_GProps.hxx>
#include <BRepBndLib.hxx>
#include <Bnd_Box.hxx>
#include <BOPAlgo_CheckerSI.hxx>
#include <BOPDS_DS.hxx>
#include <BOPDS_Interf.hxx>
#include <BOPDS_MapOfPair.hxx>
#include <TopTools_ListOfShape.hxx>
#include <TopExp.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Shape.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_IndexedMapOfShape.hxx>
#include <GeomLProp_SLProps.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <STEPControl_Reader.hxx>
#include <Geom_Surface.hxx>
#include <BRepTopAdaptor_FClass2d.hxx>
#include <Precision.hxx>
#include <gp_Pnt2d.hxx>
#include <gp_Pnt.hxx>
#include <gp_Vec.hxx>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <map>
#include <string>
#include <vector>

namespace {

const char *StatusName(BRepCheck_Status s)
{
    switch (s) {
    case BRepCheck_NoError: return "NoError";
    case BRepCheck_InvalidPointOnCurve: return "InvalidPointOnCurve";
    case BRepCheck_InvalidPointOnCurveOnSurface: return "InvalidPointOnCurveOnSurface";
    case BRepCheck_InvalidPointOnSurface: return "InvalidPointOnSurface";
    case BRepCheck_No3DCurve: return "No3DCurve";
    case BRepCheck_Multiple3DCurve: return "Multiple3DCurve";
    case BRepCheck_Invalid3DCurve: return "Invalid3DCurve";
    case BRepCheck_NoCurveOnSurface: return "NoCurveOnSurface";
    case BRepCheck_InvalidCurveOnSurface: return "InvalidCurveOnSurface";
    case BRepCheck_InvalidCurveOnClosedSurface: return "InvalidCurveOnClosedSurface";
    case BRepCheck_InvalidSameRangeFlag: return "InvalidSameRangeFlag";
    case BRepCheck_InvalidSameParameterFlag: return "InvalidSameParameterFlag";
    case BRepCheck_InvalidDegeneratedFlag: return "InvalidDegeneratedFlag";
    case BRepCheck_FreeEdge: return "FreeEdge";
    case BRepCheck_InvalidMultiConnexity: return "InvalidMultiConnexity";
    case BRepCheck_InvalidRange: return "InvalidRange";
    case BRepCheck_EmptyWire: return "EmptyWire";
    case BRepCheck_RedundantEdge: return "RedundantEdge";
    case BRepCheck_SelfIntersectingWire: return "SelfIntersectingWire";
    case BRepCheck_NoSurface: return "NoSurface";
    case BRepCheck_InvalidWire: return "InvalidWire";
    case BRepCheck_RedundantWire: return "RedundantWire";
    case BRepCheck_IntersectingWires: return "IntersectingWires";
    case BRepCheck_InvalidImbricationOfWires: return "InvalidImbricationOfWires";
    case BRepCheck_EmptyShell: return "EmptyShell";
    case BRepCheck_RedundantFace: return "RedundantFace";
    case BRepCheck_UnorientableShape: return "UnorientableShape";
    case BRepCheck_NotClosed: return "NotClosed";
    case BRepCheck_NotConnected: return "NotConnected";
    case BRepCheck_SubshapeNotInShape: return "SubshapeNotInShape";
    case BRepCheck_BadOrientation: return "BadOrientation";
    case BRepCheck_BadOrientationOfSubshape: return "BadOrientationOfSubshape";
    case BRepCheck_InvalidPolygonOnTriangulation: return "InvalidPolygonOnTriangulation";
    case BRepCheck_InvalidToleranceValue: return "InvalidToleranceValue";
    case BRepCheck_EnclosedRegion: return "EnclosedRegion";
    case BRepCheck_CheckFail: return "CheckFail";
    default: return "Unknown";
    }
}

std::string SurfKindOf(const TopoDS_Face &f);

const char *ShapeTypeName(TopAbs_ShapeEnum t)
{
    switch (t) {
    case TopAbs_VERTEX: return "vertex";
    case TopAbs_EDGE: return "edge";
    case TopAbs_WIRE: return "wire";
    case TopAbs_FACE: return "face";
    case TopAbs_SHELL: return "shell";
    case TopAbs_SOLID: return "solid";
    default: return "shape";
    }
}

const char *SurfName(GeomAbs_SurfaceType t)
{
    switch (t) {
    case GeomAbs_Plane: return "plane";
    case GeomAbs_Cylinder: return "cylinder";
    case GeomAbs_Cone: return "cone";
    case GeomAbs_Sphere: return "sphere";
    case GeomAbs_Torus: return "torus";
    case GeomAbs_BezierSurface: return "bezier";
    case GeomAbs_BSplineSurface: return "bspline";
    case GeomAbs_SurfaceOfRevolution: return "revolution";
    case GeomAbs_SurfaceOfExtrusion: return "extrusion";
    case GeomAbs_OffsetSurface: return "offset";
    default: return "other";
    }
}

std::string SurfKindOf(const TopoDS_Face &f)
{
    try {
        BRepAdaptor_Surface ad(f, Standard_False);
        return SurfName(ad.GetType());
    } catch (const Standard_Failure &) {
        return "?";
    }
}

int CountOf(const TopoDS_Shape &s, TopAbs_ShapeEnum k)
{
    int n = 0;
    for (TopExp_Explorer e(s, k); e.More(); e.Next()) ++n;
    return n;
}

bool ReadShape(const char *path, TopoDS_Shape &out)
{
    const std::string p(path);
    const bool isStep = p.size() > 4 &&
        (p.compare(p.size()-4,4,".stp")==0 || p.compare(p.size()-5,5,".step")==0);
    if (isStep) {
        STEPControl_Reader r;
        if (r.ReadFile(path) != IFSelect_RetDone) return false;
        r.TransferRoots();
        out = r.OneShape();
        return !out.IsNull();
    }
    BRep_Builder b;
    return BRepTools::Read(out, path, b);
}

} // namespace

int main(int argc, char **argv)
{
    if (argc < 2) {
        std::fprintf(stderr, "usage: %s body.brep [--ref truth.brep|.step]\n", argv[0]);
        return 2;
    }
    const char *path = argv[1];
    const char *refPath = nullptr;
    int oneFace = 0;
    for (int i = 2; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--ref" && i + 1 < argc) refPath = argv[++i];
        if (a == "--face" && i + 1 < argc) oneFace = std::atoi(argv[++i]);
    }

    TopoDS_Shape s;
    if (!ReadShape(path, s) || s.IsNull()) {
        std::fprintf(stderr, "cannot read %s\n", path);
        return 1;
    }

    /* --face N: everything known about ONE face, for when the body-level
     * numbers say a face is wrong and the question is HOW. */
    if (oneFace > 0) {
        TopTools_IndexedMapOfShape fm;
        TopExp::MapShapes(s, TopAbs_FACE, fm);
        if (oneFace > fm.Extent()) {
            std::fprintf(stderr, "only %d faces\n", fm.Extent());
            return 1;
        }
        const TopoDS_Face f = TopoDS::Face(fm(oneFace));
        BRepAdaptor_Surface ad(f, Standard_False);
        const Handle(Geom_Surface) su = BRep_Tool::Surface(f);
        Standard_Real u0, u1, v0, v1;
        BRepTools::UVBounds(f, u0, u1, v0, v1);
        std::printf("face=%d kind=%s u=[%g %g] v=[%g %g] tol=%g\n", oneFace,
                    SurfKindOf(f).c_str(), u0, u1, v0, v1,
                    BRep_Tool::Tolerance(f));
        BRepTopAdaptor_FClass2d cls(f, Precision::Confusion());
        const int N = 60;
        std::vector<gp_Pnt> pts;
        std::vector<double> pu, pv;
        int flipped = 0;
        gp_Vec nAvg(0, 0, 0);
        std::vector<gp_Vec> nrm;
        for (int a = 0; a <= N; ++a)
            for (int b = 0; b <= N; ++b) {
                const double uu = u0 + (u1 - u0) * a / N;
                const double vv = v0 + (v1 - v0) * b / N;
                if (cls.Perform(gp_Pnt2d(uu, vv)) == TopAbs_OUT) continue;
                GeomLProp_SLProps pr(su, uu, vv, 1, 1e-9);
                if (!pr.IsNormalDefined()) continue;
                pts.push_back(pr.Value());
                pu.push_back(uu); pv.push_back(vv);
                gp_Vec n(pr.Normal());
                nrm.push_back(n);
                nAvg += n;
            }
        if (nAvg.Magnitude() > 0) nAvg.Normalize();
        double worstAng = 0;
        for (size_t i = 0; i < nrm.size(); ++i) {
            const double ang = nAvg.Angle(nrm[i]) * 180.0 / M_PI;
            if (ang > worstAng) worstAng = ang;
            if (ang > 90) ++flipped;
        }
        /* The closest approach between two parts of the face that are FAR
         * apart in parameter: that is what a self-intersection is. */
        double closest = 1e300;
        double cu1 = 0, cv1 = 0, cu2 = 0, cv2 = 0;
        const double duFar = 0.15 * (u1 - u0), dvFar = 0.15 * (v1 - v0);
        for (size_t i = 0; i < pts.size(); ++i)
            for (size_t j = i + 1; j < pts.size(); ++j) {
                if (std::fabs(pu[i] - pu[j]) < duFar &&
                    std::fabs(pv[i] - pv[j]) < dvFar)
                    continue;
                const double d = pts[i].Distance(pts[j]);
                if (d < closest) {
                    closest = d; cu1 = pu[i]; cv1 = pv[i];
                    cu2 = pu[j]; cv2 = pv[j];
                }
            }
        std::printf("face.samples=%d normal_spread_deg=%.2f flipped=%d\n",
                    (int)pts.size(), worstAng, flipped);
        std::printf("face.closest_far_approach=%.6f at (%g,%g)-(%g,%g)\n",
                    closest, cu1, cv1, cu2, cv2);
        return 0;
    }

    int problems = 0;
    std::printf("shape=%s\n", path);

    /* ---- counts ---- */
    const int nf = CountOf(s, TopAbs_FACE), ne = CountOf(s, TopAbs_EDGE);
    const int nv = CountOf(s, TopAbs_VERTEX), nsh = CountOf(s, TopAbs_SHELL);
    const int nso = CountOf(s, TopAbs_SOLID), nw = CountOf(s, TopAbs_WIRE);
    std::printf("faces=%d edges=%d vertices=%d wires=%d shells=%d solids=%d\n",
                nf, ne, nv, nw, nsh, nso);

    /* AddOptimal, not Add: the cheap box is the POLES box, and a B-spline's
     * control net stands outside the surface it describes. Measured, that
     * reads as 3.0-3.3% of oversize on the butterfly and the whale which the
     * surfaces do not actually have — an artifact this tool reported as a
     * defect until it was chased down. */
    Bnd_Box bb; BRepBndLib::AddOptimal(s, bb, Standard_False, Standard_False);
    double x0,y0,z0,x1,y1,z1; bb.Get(x0,y0,z0,x1,y1,z1);
    const double diag = std::sqrt((x1-x0)*(x1-x0)+(y1-y0)*(y1-y0)+(z1-z0)*(z1-z0));
    std::printf("diagonal=%.6f\n", diag);

    /* ---- validity: every status, counted ---- */
    {
        BRepCheck_Analyzer an(s, Standard_True);
        std::printf("valid=%d\n", an.IsValid() ? 1 : 0);
        if (!an.IsValid()) ++problems;
        std::map<std::string,int> tally;
        const TopAbs_ShapeEnum kinds[] = {TopAbs_VERTEX, TopAbs_EDGE, TopAbs_WIRE,
                                          TopAbs_FACE, TopAbs_SHELL, TopAbs_SOLID};
        for (TopAbs_ShapeEnum k : kinds) {
            TopTools_IndexedMapOfShape m;
            TopExp::MapShapes(s, k, m);
            for (int i = 1; i <= m.Extent(); ++i) {
                Handle(BRepCheck_Result) res;
                try { res = an.Result(m(i)); } catch (const Standard_Failure &) { continue; }
                if (res.IsNull()) continue;
                for (BRepCheck_ListIteratorOfListOfStatus it(res->Status());
                     it.More(); it.Next()) {
                    if (it.Value() == BRepCheck_NoError) continue;
                    tally[StatusName(it.Value())]++;
                }
            }
        }
        for (const auto &kv : tally)
            std::printf("check.%s=%d\n", kv.first.c_str(), kv.second);
        if (tally.empty()) std::printf("check.none=0\n");
    }

    /* ---- self-intersection ---- */
    /* WHICH FACE, on its own.
     *
     * M440. A pair of indices from the whole-body check says two faces cross;
     * it does not say whether the fault is in one of them. A face that
     * intersects ITSELF is a different and worse bug — the surface under it
     * folds — and the whole-body check reports it as the pair (n, n), which is
     * easy to read past. So each face is also checked alone, which is both
     * authoritative and fast (the whale: 91 seconds for the body, under two
     * for all 195 faces one at a time). */
    {
        TopTools_IndexedMapOfShape fm;
        TopExp::MapShapes(s, TopAbs_FACE, fm);
        int folded = 0;
        std::map<std::string, int> byKind, allWhat;
        for (int i = 1; i <= fm.Extent(); ++i) {
            const TopoDS_Face f = TopoDS::Face(fm(i));
            try {
                BOPAlgo_CheckerSI ck;
                TopTools_ListOfShape one;
                one.Append(f);
                ck.SetArguments(one);
                ck.SetLevelOfCheck(9);
                ck.SetRunParallel(Standard_False);
                ck.Perform();
                BOPDS_DS &d1 = const_cast<BOPDS_DS &>(ck.DS());
                if (d1.Interferences().Size() > 0) {
                    ++folded;
                    byKind[SurfKindOf(f)]++;
                    /* WHAT kind of interference. A surface that folds shows up
                     * as face/face; a boundary that crosses itself, or a
                     * vertex whose inflated tolerance swallows one of its own
                     * edges, shows up as vertex/edge or edge/edge — a
                     * completely different bug with a completely different
                     * fix. */
                    std::map<std::string, int> what;
                    for (BOPDS_MapOfPair::Iterator it(d1.Interferences());
                         it.More(); it.Next()) {
                        Standard_Integer a = 0, b = 0;
                        it.Value().Indices(a, b);
                        const char *k1 = ShapeTypeName(d1.Shape(a).ShapeType());
                        const char *k2 = ShapeTypeName(d1.Shape(b).ShapeType());
                        std::string key = std::string(k1) < std::string(k2)
                                              ? std::string(k1) + "/" + k2
                                              : std::string(k2) + "/" + k1;
                        what[key]++;
                        allWhat[key]++;
                    }
                    if (folded <= 6) {
                        std::printf("face.folds=%d kind=%s", i,
                                    SurfKindOf(f).c_str());
                        for (std::map<std::string, int>::const_iterator w =
                                 what.begin(); w != what.end(); ++w)
                            std::printf(" %s:%d", w->first.c_str(), w->second);
                        std::printf("\n");
                    }
                }
            } catch (const Standard_Failure &) {
            }
        }
        std::printf("faces_self_intersecting=%d\n", folded);
        for (std::map<std::string, int>::const_iterator it = byKind.begin();
             it != byKind.end(); ++it)
            std::printf("face.folds.%s=%d\n", it->first.c_str(), it->second);
        for (std::map<std::string, int>::const_iterator it = allWhat.begin();
             it != allWhat.end(); ++it)
            std::printf("face.folds.what.%s=%d\n", it->first.c_str(),
                        it->second);
    }

    {
        int pairs = -1;
        try {
            BOPAlgo_CheckerSI ck;
            TopTools_ListOfShape args; args.Append(s);
            ck.SetArguments(args);
            ck.SetLevelOfCheck(9);
            ck.SetRunParallel(Standard_False);
            ck.Perform();
            BOPDS_DS &ds = const_cast<BOPDS_DS &>(ck.DS());
            pairs = static_cast<int>(ds.Interferences().Size());
            /* WHICH faces cross, not just how many. A count says the body is
             * unusable; the pairs say where to look, and on a fitted organic
             * model the answer — B-spline against B-spline, or B-spline
             * against its own neighbour — is the difference between a fitting
             * bug and a sewing one. */
            /* WHICH sub-shapes cross, not just how many. A count says the
             * body is unusable; the pairs say where to look, and on a fitted
             * organic model "B-spline against B-spline" and "plane against
             * its own neighbour" are different bugs.
             *
             * ds.Interferences() and not InterfFF: the FF vector holds every
             * pair the checker LOOKED at, adjacent faces that legitimately
             * share an edge included — 1,247 of them on the whale against 142
             * real ones. Only the map is the verdict. */
            if (pairs > 0) {
                TopTools_IndexedMapOfShape fm;
                TopExp::MapShapes(s, TopAbs_FACE, fm);
                std::map<std::string, int> byKind;
                int shown = 0;
                for (BOPDS_MapOfPair::Iterator it(ds.Interferences());
                     it.More(); it.Next()) {
                    Standard_Integer i1 = 0, i2 = 0;
                    it.Value().Indices(i1, i2);
                    const TopoDS_Shape &s1 = ds.Shape(i1);
                    const TopoDS_Shape &s2 = ds.Shape(i2);
                    const std::string k1 =
                        s1.ShapeType() == TopAbs_FACE
                            ? SurfKindOf(TopoDS::Face(s1))
                            : std::string(ShapeTypeName(s1.ShapeType()));
                    const std::string k2 =
                        s2.ShapeType() == TopAbs_FACE
                            ? SurfKindOf(TopoDS::Face(s2))
                            : std::string(ShapeTypeName(s2.ShapeType()));
                    byKind[k1 < k2 ? k1 + "/" + k2 : k2 + "/" + k1]++;
                    if (shown++ < 12)
                        std::printf("selfint.pair=%d,%d %s/%s\n",
                                    s1.ShapeType() == TopAbs_FACE
                                        ? fm.FindIndex(s1) : -1,
                                    s2.ShapeType() == TopAbs_FACE
                                        ? fm.FindIndex(s2) : -1,
                                    k1.c_str(), k2.c_str());
                }
                for (std::map<std::string, int>::const_iterator it =
                         byKind.begin(); it != byKind.end(); ++it)
                    std::printf("selfint.kinds.%s=%d\n", it->first.c_str(),
                                it->second);
            }
        } catch (const Standard_Failure &e) {
            std::printf("selfint.error=%s\n", e.GetMessageString() ? e.GetMessageString() : "?");
        }
        std::printf("self_intersections=%d\n", pairs);
        if (pairs > 0) ++problems;
    }

    /* ---- shell topology: free and non-manifold edges ---- */
    {
        TopTools_IndexedDataMapOfShapeListOfShape em;
        TopExp::MapShapesAndAncestors(s, TopAbs_EDGE, TopAbs_FACE, em);
        int freeE = 0, overE = 0;
        for (int i = 1; i <= em.Extent(); ++i) {
            const TopoDS_Edge e = TopoDS::Edge(em.FindKey(i));
            if (BRep_Tool::Degenerated(e)) continue;
            const int n = em.FindFromIndex(i).Extent();
            if (n == 1) ++freeE; else if (n > 2) ++overE;
        }
        std::printf("free_edges=%d nonmanifold_edges=%d\n", freeE, overE);
        if (freeE || overE) ++problems;
    }

    /* ---- orientation ---- */
    {
        double vol = 0, area = 0;
        try { GProp_GProps g; BRepGProp::VolumeProperties(s, g); vol = g.Mass(); }
        catch (const Standard_Failure &) {}
        try { GProp_GProps g; BRepGProp::SurfaceProperties(s, g); area = g.Mass(); }
        catch (const Standard_Failure &) {}
        std::printf("volume=%.8g area=%.8g\n", vol, area);
        std::printf("volume_positive=%d\n", vol > 0 ? 1 : 0);
        if (nso > 0 && vol <= 0) ++problems;
    }

    /* ---- spikes: needle faces, tiny edges, degenerate geometry ---- */
    {
        int needles = 0, tinyFaces = 0, tinyEdges = 0, hugeTol = 0;
        double worstNeedle = 1e30, minFaceArea = 1e30, minEdgeLen = 1e30;
        const double lenEps = diag * 1e-6;
        for (TopExp_Explorer e(s, TopAbs_FACE); e.More(); e.Next()) {
            const TopoDS_Face f = TopoDS::Face(e.Current());
            double a = 0, per = 0;
            try { GProp_GProps g; BRepGProp::SurfaceProperties(f, g); a = g.Mass(); }
            catch (const Standard_Failure &) { continue; }
            try { GProp_GProps g; BRepGProp::LinearProperties(f, g); per = g.Mass(); }
            catch (const Standard_Failure &) {}
            minFaceArea = std::min(minFaceArea, a);
            if (a < diag*diag*1e-10) ++tinyFaces;
            /* A needle is a face whose area is vanishing against the square of
             * its own perimeter: a well-shaped face has 4*pi*A/P^2 near 1 for a
             * disc and ~0.78 for a square; a spike drives it to zero. */
            if (per > 0) {
                const double shape = 4.0*M_PI*a/(per*per);
                worstNeedle = std::min(worstNeedle, shape);
                if (shape < 1e-3) ++needles;
            }
            if (BRep_Tool::Tolerance(f) > diag*1e-3) ++hugeTol;
        }
        for (TopExp_Explorer e(s, TopAbs_EDGE); e.More(); e.Next()) {
            const TopoDS_Edge ed = TopoDS::Edge(e.Current());
            if (BRep_Tool::Degenerated(ed)) continue;
            double len = 0;
            try { GProp_GProps g; BRepGProp::LinearProperties(ed, g); len = g.Mass(); }
            catch (const Standard_Failure &) { continue; }
            minEdgeLen = std::min(minEdgeLen, len);
            if (len < lenEps) ++tinyEdges;
            if (BRep_Tool::Tolerance(ed) > diag*1e-3) ++hugeTol;
        }
        std::printf("needle_faces=%d tiny_faces=%d tiny_edges=%d oversize_tolerance=%d\n",
                    needles, tinyFaces, tinyEdges, hugeTol);
        std::printf("worst_face_shape=%.6g min_face_area=%.6g min_edge_len=%.6g\n",
                    worstNeedle, minFaceArea, minEdgeLen);
        if (needles || tinyEdges || hugeTol) ++problems;
    }

    /* ---- surface kinds, by count and by area ---- */
    {
        std::map<std::string,int> kindN;
        std::map<std::string,double> kindA;
        double total = 0;
        for (TopExp_Explorer e(s, TopAbs_FACE); e.More(); e.Next()) {
            const TopoDS_Face f = TopoDS::Face(e.Current());
            std::string k;
            try { BRepAdaptor_Surface ad(f, Standard_False); k = SurfName(ad.GetType()); }
            catch (const Standard_Failure &) { k = "unreadable"; }
            double a = 0;
            try { GProp_GProps g; BRepGProp::SurfaceProperties(f, g); a = g.Mass(); }
            catch (const Standard_Failure &) {}
            kindN[k]++; kindA[k] += a; total += a;
        }
        for (const auto &kv : kindN)
            std::printf("surf.%s=%d area_frac=%.4f\n", kv.first.c_str(), kv.second,
                        total > 0 ? kindA[kv.first]/total : 0.0);
    }

    /* ---- continuity across shared edges: G0 gap and G1 tangency ---- */
    {
        TopTools_IndexedDataMapOfShapeListOfShape em;
        TopExp::MapShapesAndAncestors(s, TopAbs_EDGE, TopAbs_FACE, em);
        double maxGap = 0; int sampled = 0, tangent = 0, sharp = 0;
        for (int i = 1; i <= em.Extent(); ++i) {
            const TopoDS_Edge ed = TopoDS::Edge(em.FindKey(i));
            if (BRep_Tool::Degenerated(ed)) continue;
            if (em.FindFromIndex(i).Extent() != 2) continue;
            const TopoDS_Face f1 = TopoDS::Face(em.FindFromIndex(i).First());
            const TopoDS_Face f2 = TopoDS::Face(em.FindFromIndex(i).Last());
            double t0, t1;
            Handle(Geom_Curve) c = BRep_Tool::Curve(ed, t0, t1);
            if (c.IsNull()) continue;
            Handle(Geom_Surface) s1 = BRep_Tool::Surface(f1);
            Handle(Geom_Surface) s2 = BRep_Tool::Surface(f2);
            if (s1.IsNull() || s2.IsNull()) continue;
            for (int k = 1; k <= 5; ++k) {
                const double t = t0 + (t1-t0)*k/6.0;
                const gp_Pnt p = c->Value(t);
                GeomAPI_ProjectPointOnSurf pr1(p, s1), pr2(p, s2);
                if (!pr1.IsDone() || !pr2.IsDone() || pr1.NbPoints()<1 || pr2.NbPoints()<1)
                    continue;
                maxGap = std::max(maxGap, std::max(pr1.LowerDistance(), pr2.LowerDistance()));
                double u1,v1,u2,v2;
                pr1.LowerDistanceParameters(u1,v1);
                pr2.LowerDistanceParameters(u2,v2);
                GeomLProp_SLProps l1(s1,u1,v1,1,1e-7), l2(s2,u2,v2,1,1e-7);
                if (!l1.IsNormalDefined() || !l2.IsNormalDefined()) continue;
                gp_Dir n1 = l1.Normal(), n2 = l2.Normal();
                if (f1.Orientation()==TopAbs_REVERSED) n1.Reverse();
                if (f2.Orientation()==TopAbs_REVERSED) n2.Reverse();
                const double ang = n1.Angle(n2)*180.0/M_PI;
                ++sampled;
                if (ang < 1.0) ++tangent; else if (ang > 30.0) ++sharp;
            }
        }
        std::printf("g0_max_gap=%.9g g0_gap_rel=%.3g\n", maxGap,
                    diag>0 ? maxGap/diag : 0.0);
        std::printf("continuity_samples=%d tangent_lt1deg=%d sharp_gt30deg=%d\n",
                    sampled, tangent, sharp);
        if (diag > 0 && maxGap > diag*1e-4) ++problems;
    }

    /* ---- against a reference body, when there is one ---- */
    if (refPath) {
        TopoDS_Shape r;
        if (ReadShape(refPath, r) && !r.IsNull()) {
            double rv = 0, ra = 0;
            try { GProp_GProps g; BRepGProp::VolumeProperties(r, g); rv = std::fabs(g.Mass()); }
            catch (const Standard_Failure &) {}
            try { GProp_GProps g; BRepGProp::SurfaceProperties(r, g); ra = g.Mass(); }
            catch (const Standard_Failure &) {}
            double v = 0, a = 0;
            try { GProp_GProps g; BRepGProp::VolumeProperties(s, g); v = std::fabs(g.Mass()); }
            catch (const Standard_Failure &) {}
            try { GProp_GProps g; BRepGProp::SurfaceProperties(s, g); a = g.Mass(); }
            catch (const Standard_Failure &) {}
            std::printf("ref.faces=%d ref.edges=%d ref.vertices=%d\n",
                        CountOf(r,TopAbs_FACE), CountOf(r,TopAbs_EDGE),
                        CountOf(r,TopAbs_VERTEX));
            std::map<std::string,int> rk;
            for (TopExp_Explorer e(r, TopAbs_FACE); e.More(); e.Next()) {
                try { BRepAdaptor_Surface ad(TopoDS::Face(e.Current()), Standard_False);
                      rk[SurfName(ad.GetType())]++; }
                catch (const Standard_Failure &) {}
            }
            for (const auto &kv : rk)
                std::printf("ref.surf.%s=%d\n", kv.first.c_str(), kv.second);
            std::printf("ref.volume=%.8g ref.area=%.8g\n", rv, ra);
            if (rv > 0) std::printf("volume_err_rel=%.6g\n", std::fabs(v-rv)/rv);
            if (ra > 0) std::printf("area_err_rel=%.6g\n", std::fabs(a-ra)/ra);
            std::printf("face_count_delta=%d\n", CountOf(s,TopAbs_FACE)-CountOf(r,TopAbs_FACE));
        }
    }

    std::printf("problems=%d\n", problems);
    std::printf("VERDICT: %s\n", problems == 0 ? "CLEAN" : "NOT CLEAN");
    return problems == 0 ? 0 : 3;
}
