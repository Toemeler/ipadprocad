/* S15 — the instrument for perf/findings/S15-holes.md §1.
 *
 * WHAT THIS IS FOR, AND WHAT IT MAY BE TRUSTED FOR
 * ------------------------------------------------
 * S14 §12.2 costed the "assemble instead of subtract" route for holed sweeps
 * at 24 profile segments and could not complete it at 1200: it killed the
 * prototype after 25 minutes and said, explicitly, that its explanation —
 * "the process was stuck verifying, not building" — was an inference from
 * where a timer sat rather than a measurement.
 *
 * This program is that measurement. It rebuilds the assembly out of the same
 * OCCT classes the shim uses and times its stages SEPARATELY, so that
 * construction and verification can be told apart:
 *
 *     sweep  caps  sew  unify   <- construction; `unify` is in the shipped path
 *     volume valid                <- verification; NEITHER is in the shipped path
 *
 * It is a REPLICA, and a replica is worth exactly what its agreement with the
 * original is worth. `--reproduce` re-measures S14 §12.2's 24-segment table
 * through this code; read nothing else here unless that arm agrees.
 *
 * It is deliberately NOT a Lane C scenario. Lane C runs on every push and its
 * exponents are a gate; a rung that can take a quarter of an hour has no place
 * in it. Build it with -DBENCH_HOLE_PROBE=ON and run it by hand.
 */

#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include <BRepAlgoAPI_Cut.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepBuilderAPI_Sewing.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepClass3d_SolidClassifier.hxx>
#include <BRepGProp.hxx>
#include <BRepLib_MakeFace.hxx>
#include <BRepOffsetAPI_MakePipeShell.hxx>
#include <BRep_Builder.hxx>
#include <GProp_GProps.hxx>
#include <GeomAPI_Interpolate.hxx>
#include <Precision.hxx>
#include <ShapeUpgrade_UnifySameDomain.hxx>
#include <Standard_Failure.hxx>
#include <TColgp_HArray1OfPnt.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Solid.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Pnt.hxx>

#include "occt_capi.h"

namespace {

using clk = std::chrono::steady_clock;
double ms(clk::time_point a, clk::time_point b)
{
    return std::chrono::duration<double, std::milli>(b - a).count();
}

int countSub(const TopoDS_Shape &s, TopAbs_ShapeEnum what)
{
    int n = 0;
    for (TopExp_Explorer e(s, what); e.More(); e.Next())
        ++n;
    return n;
}

/* frontend/lib/perf_scenarios_profile.dart arcRing(n, r), as a placed wire. */
TopoDS_Wire ring(int n, double r)
{
    BRepBuilderAPI_MakePolygon poly;
    for (int i = 0; i < n; ++i) {
        const double a = 2.0 * M_PI * i / n;
        poly.Add(gp_Pnt(r * std::cos(a), r * std::sin(a), 0.0));
    }
    poly.Close();
    return poly.Wire();
}

/* The same helix smoke [37d] and [37f] use: a quarter turn of radius 18 in XY
 * while z rises to 60. Kept in the probe's own words so a change to the smoke
 * test cannot silently move this instrument's fixture. */
std::vector<gp_Pnt> arcPath(int spans)
{
    std::vector<gp_Pnt> p;
    for (int i = 0; i <= spans; ++i) {
        const double t = static_cast<double>(i) / spans;
        const double a = t * M_PI / 2.0;
        p.emplace_back(60.0 * std::sin(a) * 0.3, 60.0 * (1.0 - std::cos(a)) * 0.3,
                       t * 60.0);
    }
    return p;
}

/* The shim's two spines. POLY is spine_from_points_ex's polygon branch;
 * SMOOTH is its single-run branch, one GeomAPI_Interpolate over every point,
 * with the same Standard_False / 1.0e-7 the shim passes. */
TopoDS_Wire spinePoly(const std::vector<gp_Pnt> &p)
{
    BRepBuilderAPI_MakePolygon poly;
    for (const gp_Pnt &q : p)
        poly.Add(q);
    return poly.Wire();
}

TopoDS_Wire spineSmooth(const std::vector<gp_Pnt> &p)
{
    Handle(TColgp_HArray1OfPnt) h =
        new TColgp_HArray1OfPnt(1, static_cast<int>(p.size()));
    for (size_t i = 0; i < p.size(); ++i)
        h->SetValue(static_cast<int>(i) + 1, p[i]);
    GeomAPI_Interpolate itp(h, Standard_False, 1.0e-7);
    itp.Perform();
    if (!itp.IsDone())
        return TopoDS_Wire();
    BRepBuilderAPI_MakeEdge e(itp.Curve());
    BRepBuilderAPI_MakeWire w(e.Edge());
    return w.Wire();
}

/* occt_sweep_profile_ex's configuration for orientation 0, exactly: the
 * trihedron follows `smoothed`, and WithCorrection is Standard_False. */
void configure(BRepOffsetAPI_MakePipeShell &mk, const TopoDS_Wire &section,
               bool smoothed)
{
    mk.SetTransitionMode(BRepBuilderAPI_RightCorner);
    mk.SetMode(smoothed ? Standard_False : Standard_True);
    mk.Add(section, Standard_False, Standard_False);
}

struct Stages {
    double sweep = 0, caps = 0, sew = 0, unify = 0, volume = 0, valid = 0;
    double vol = 0;
    int faces = 0;
    bool ok = false, isValid = false;
    const char *why = "";
};

/* Build a planar cap from one outer wire and k inner wires. The inner wires
 * are added with BRep_Builder onto the plane BRepLib_MakeFace found, which is
 * exactly what BRepFill_PipeShell::MakeSolid's own PerformPlan does for the
 * unholed case. */
bool cap(const TopoDS_Wire &outer, const std::vector<TopoDS_Wire> &inner,
         TopoDS_Face &out)
{
    BRepLib_MakeFace mf(outer, Standard_True);
    if (!mf.IsDone())
        return false;
    TopoDS_Face f = mf.Face();
    BRep_Builder bb;
    for (const TopoDS_Wire &w : inner)
        bb.Add(f, w.Reversed());
    out = f;
    return true;
}

/* Route B — the assembly, staged. */
Stages assemble(int seg, int spans, bool smooth, double holeR)
{
    Stages s;
    const std::vector<gp_Pnt> pp = arcPath(spans);
    const TopoDS_Wire spine = smooth ? spineSmooth(pp) : spinePoly(pp);
    if (spine.IsNull()) {
        s.why = "spine";
        return s;
    }
    const TopoDS_Wire outerW = ring(seg, 6.0);
    const bool holed = holeR > 0.0;
    const TopoDS_Wire holeW = holed ? ring(seg, holeR) : TopoDS_Wire();

    /* ---- sweep ---- */
    clk::time_point t0 = clk::now();
    BRepOffsetAPI_MakePipeShell mo(spine);
    configure(mo, outerW, smooth);
    mo.Build();
    if (!mo.IsDone()) {
        s.why = "outer sweep";
        return s;
    }
    const TopoDS_Shape latO = mo.Shape();
    const TopoDS_Shape f0O = mo.FirstShape(), f1O = mo.LastShape();

    TopoDS_Shape latH, f0H, f1H;
    if (holed) {
        BRepOffsetAPI_MakePipeShell mh(spine);
        configure(mh, holeW, smooth);
        mh.Build();
        if (!mh.IsDone()) {
            s.why = "hole sweep";
            return s;
        }
        latH = mh.Shape();
        f0H = mh.FirstShape();
        f1H = mh.LastShape();
    }
    clk::time_point t1 = clk::now();
    s.sweep = ms(t0, t1);

    if (f0O.IsNull() || f1O.IsNull() || f0O.ShapeType() != TopAbs_WIRE
        || f1O.ShapeType() != TopAbs_WIRE) {
        s.why = "end sections are not wires";
        return s;
    }

    /* ---- caps ---- */
    std::vector<TopoDS_Wire> i0, i1;
    if (holed) {
        if (f0H.ShapeType() != TopAbs_WIRE || f1H.ShapeType() != TopAbs_WIRE) {
            s.why = "hole end sections are not wires";
            return s;
        }
        i0.push_back(TopoDS::Wire(f0H));
        i1.push_back(TopoDS::Wire(f1H));
    }
    TopoDS_Face c0, c1;
    if (!cap(TopoDS::Wire(f0O), i0, c0) || !cap(TopoDS::Wire(f1O), i1, c1)) {
        s.why = "cap";
        return s;
    }
    clk::time_point t2 = clk::now();
    s.caps = ms(t1, t2);

    /* ---- sew + solid ---- */
    BRepBuilderAPI_Sewing sew(Precision::Confusion());
    sew.Add(latO);
    if (holed)
        sew.Add(latH);
    sew.Add(c0);
    sew.Add(c1);
    sew.Perform();
    const TopoDS_Shape sewn = sew.SewedShape();
    if (sewn.IsNull()) {
        s.why = "sew";
        return s;
    }
    int nsh = 0;
    TopoDS_Shell shell;
    for (TopExp_Explorer e(sewn, TopAbs_SHELL); e.More(); e.Next()) {
        shell = TopoDS::Shell(e.Current());
        ++nsh;
    }
    if (nsh != 1 || sew.NbFreeEdges() != 0) {
        s.why = "not one closed shell";
        std::printf("      (shells=%d freeEdges=%d multiEdges=%d)\n", nsh,
                    sew.NbFreeEdges(), sew.NbMultipleEdges());
        return s;
    }
    TopoDS_Solid solid;
    BRep_Builder bb;
    bb.MakeSolid(solid);
    bb.Add(solid, shell);
    BRepClass3d_SolidClassifier sc(solid);
    sc.PerformInfinitePoint(Precision::Confusion());
    if (sc.State() == TopAbs_IN) {
        TopoDS_Solid s2;
        bb.MakeSolid(s2);
        bb.Add(s2, TopoDS::Shell(shell.Reversed()));
        solid = s2;
    }
    solid.Closed(Standard_True);
    clk::time_point t3 = clk::now();
    s.sew = ms(t2, t3);

    /* ---- unify (SHIPPED — finish_pipe runs this today) ---- */
    ShapeUpgrade_UnifySameDomain uni(solid, Standard_True, Standard_True,
                                     Standard_False);
    uni.Build();
    const TopoDS_Shape fin = uni.Shape();
    clk::time_point t4 = clk::now();
    s.unify = ms(t3, t4);

    /* ---- verification (NOT shipped) ---- */
    GProp_GProps g;
    BRepGProp::VolumeProperties(fin, g);
    s.vol = g.Mass();
    clk::time_point t5 = clk::now();
    s.volume = ms(t4, t5);

    BRepCheck_Analyzer an(fin);
    s.isValid = an.IsValid();
    clk::time_point t6 = clk::now();
    s.valid = ms(t5, t6);

    s.faces = countSub(fin, TopAbs_FACE);
    s.ok = true;
    return s;
}

/* Route A — the boolean, as finish_pipe does it today. Timed as one number:
 * the point of the probe is the assembly's breakdown, and this is the control
 * it has to beat. */
double booleanRoute(int seg, int spans, bool smooth, double holeR, double *vol,
                    int *faces, bool *valid)
{
    const std::vector<gp_Pnt> pp = arcPath(spans);
    const TopoDS_Wire spine = smooth ? spineSmooth(pp) : spinePoly(pp);
    const TopoDS_Wire outerW = ring(seg, 6.0), holeW = ring(seg, holeR);
    clk::time_point t0 = clk::now();
    BRepOffsetAPI_MakePipeShell mo(spine);
    configure(mo, outerW, smooth);
    mo.Build();
    if (!mo.IsDone() || !mo.MakeSolid())
        return -1.0;
    TopoDS_Shape body = mo.Shape();
    BRepOffsetAPI_MakePipeShell mh(spine);
    configure(mh, holeW, smooth);
    mh.Build();
    if (!mh.IsDone() || !mh.MakeSolid())
        return -1.0;
    BRepAlgoAPI_Cut cut(body, mh.Shape());
    if (!cut.IsDone())
        return -1.0;
    ShapeUpgrade_UnifySameDomain uni(cut.Shape(), Standard_True, Standard_True,
                                     Standard_False);
    uni.Build();
    const TopoDS_Shape fin = uni.Shape();
    const double t = ms(t0, clk::now());
    GProp_GProps g;
    BRepGProp::VolumeProperties(fin, g);
    *vol = g.Mass();
    *faces = countSub(fin, TopAbs_FACE);
    BRepCheck_Analyzer an(fin);
    *valid = an.IsValid();
    return t;
}

void printStages(const char *tag, const Stages &s)
{
    if (!s.ok) {
        std::printf("%-28s REFUSED (%s)\n", tag, s.why);
        return;
    }
    const double cons = s.sweep + s.caps + s.sew + s.unify;
    const double ver = s.volume + s.valid;
    std::printf("%-28s sweep %10.1f  caps %8.1f  sew %9.1f  unify %9.1f  "
                "| volume %9.1f  valid %11.1f\n",
                tag, s.sweep, s.caps, s.sew, s.unify, s.volume, s.valid);
    std::printf("%-28s CONSTRUCTION %10.1f ms (%.1f %%)   VERIFICATION "
                "%11.1f ms (%.1f %%)   total %11.1f ms\n",
                "", cons, 100.0 * cons / (cons + ver), ver,
                100.0 * ver / (cons + ver), cons + ver);
    std::printf("%-28s vol %.6f  faces %d  %s\n", "", s.vol, s.faces,
                s.isValid ? "valid" : "INVALID");
}

} // namespace

int main(int argc, char **argv)
{
    std::string what = argc > 1 ? argv[1] : "help";
    try {
        if (what == "reproduce") {
            /* P0 — S14 §12.2's table, through this instrument. */
            for (int m = 0; m < 2; ++m) {
                const bool smooth = m == 1;
                double bv = 0;
                int bf = 0;
                bool bok = false;
                const double bt = booleanRoute(24, 16, smooth, 3.0, &bv, &bf,
                                               &bok);
                const Stages s = assemble(24, 16, smooth, 3.0);
                std::printf("--- 24 seg, r=3 hole, 16 spans, %s spine\n",
                            smooth ? "SMOOTH" : "polyline");
                std::printf("  A boolean : %10.1f ms  vol %.6f  faces %d  %s\n",
                            bt, bv, bf, bok ? "valid" : "INVALID");
                printStages("  B assembly:", s);
                if (s.ok)
                    std::printf("  A/B volume delta: %.3e relative\n",
                                std::fabs(s.vol - bv) / bv);
            }
        } else if (what == "stages") {
            const int seg = argc > 2 ? std::atoi(argv[2]) : 1200;
            const int spans = argc > 3 ? std::atoi(argv[3]) : 16;
            const bool smooth = !(argc > 4 && std::strcmp(argv[4], "poly") == 0);
            std::printf("--- %d seg, 16-span arc, %s spine\n", seg,
                        smooth ? "SMOOTH" : "polyline");
            const Stages u = assemble(seg, spans, smooth, 0.0);
            printStages("  UNHOLED control:", u);
            const Stages h = assemble(seg, spans, smooth, 3.0);
            printStages("  HOLED assembly :", h);
            if (u.ok && h.ok)
                std::printf("  valid(holed)/valid(unholed) = %.1fx\n",
                            h.valid / (u.valid > 0 ? u.valid : 1e-9));
        } else if (what == "shipped") {
            /* P4 — the shipped v26 entry point, at the size that matters. */
            const int seg = argc > 2 ? std::atoi(argv[2]) : 1200;
            const int spans = argc > 3 ? std::atoi(argv[3]) : 16;
            std::vector<double> xyb(static_cast<size_t>(seg) * 2 * 3);
            std::vector<int> lc = {seg, seg};
            for (int i = 0; i < seg; ++i) {
                const double a = 2.0 * M_PI * i / seg;
                xyb[3 * i + 0] = 6.0 * std::cos(a);
                xyb[3 * i + 1] = 6.0 * std::sin(a);
                xyb[3 * i + 2] = 0.0;
                xyb[3 * (seg + i) + 0] = 3.0 * std::cos(a);
                xyb[3 * (seg + i) + 1] = 3.0 * std::sin(a);
                xyb[3 * (seg + i) + 2] = 0.0;
            }
            const double I[12] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0};
            std::vector<double> path;
            for (const gp_Pnt &q : arcPath(spans)) {
                path.push_back(q.X());
                path.push_back(q.Y());
                path.push_back(q.Z());
            }
            std::printf("--- shipped occt_sweep_profile_ex, %d seg x %d spans, "
                        "2 loops, AUTO\n", seg, spans);
            std::fflush(stdout);
            const clk::time_point t0 = clk::now();
            occt_shape *sh = occt_sweep_profile_ex(
                xyb.data(), lc.data(), 2, I, path.data(), spans + 1, 0, 0.0,
                0.0, 0 /* AUTO */);
            const double t = ms(t0, clk::now());
            if (!sh) {
                std::printf("  FAILED after %.1f ms: %s\n", t,
                            occt_last_error());
            } else {
                std::printf("  built in %.1f ms  vol %.6f  %s\n", t,
                            occt_shape_volume(sh),
                            occt_shape_valid(sh) ? "valid" : "INVALID");
                occt_free_shape(sh);
            }
        } else {
            std::printf("usage: hole_probe reproduce | stages [seg] [spans] "
                        "[poly] | shipped [seg] [spans]\n");
        }
    } catch (const Standard_Failure &e) {
        std::printf("EXCEPTION: %s\n", e.GetMessageString());
        return 1;
    }
    std::fflush(stdout);
    return 0;
}
