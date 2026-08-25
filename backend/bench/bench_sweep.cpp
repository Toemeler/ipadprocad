/* Lane C — the sweep pipeline, rebuilt so its phases can be told apart.
 * See bench_sweep.h for what this may and may not be trusted for. */

#include "bench_sweep.h"

#include <chrono>
#include <cmath>
#include <limits>

#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepFill_PipeShell.hxx>
#include <BRepGProp.hxx>
#include <GProp_GProps.hxx>
#include <GeomAPI_Interpolate.hxx>
#include <ShapeUpgrade_UnifySameDomain.hxx>
#include <Standard_Failure.hxx>
#include <TColgp_HArray1OfPnt.hxx>
#include <TopAbs.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <gp_Pnt.hxx>

namespace {

using clk = std::chrono::steady_clock;

double msBetween(clk::time_point a, clk::time_point b)
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

} // namespace

namespace bench {

/* frontend/lib/perf_scenarios_kernel.dart arcRing(n, r): a regular n-gon of
 * circumradius r in the XY plane, bulge zero on every vertex. */
std::vector<double> arcRingXYB(int n, double r)
{
    std::vector<double> out;
    out.reserve(static_cast<size_t>(n) * 3);
    for (int i = 0; i < n; ++i) {
        const double a = 2.0 * M_PI * i / n;
        out.push_back(r * std::cos(a));
        out.push_back(r * std::sin(a));
        out.push_back(0.0);
    }
    return out;
}

/* arcPath(n, r): t = i/(n-1), a = t·π/2, (r sin a · 0.3, r (1 − cos a) · 0.3,
 * t·r). A helix — a quarter turn of radius 0.3r in XY while z rises linearly
 * to r. Constant speed; at r = 60 its arc length is 66.33 and its radius of
 * curvature is 99.06 everywhere. */
std::vector<double> arcPathXYZ(int n, double r)
{
    std::vector<double> out;
    out.reserve(static_cast<size_t>(n) * 3);
    for (int i = 0; i < n; ++i) {
        const double t = static_cast<double>(i) / (n - 1);
        const double a = t * M_PI / 2.0;
        out.push_back(r * std::sin(a) * 0.3);
        out.push_back(r * (1.0 - std::cos(a)) * 0.3);
        out.push_back(t * r);
    }
    return out;
}

static double cornerDeg(const std::vector<double> &p, int i)
{
    const double ax = p[3 * i] - p[3 * (i - 1)];
    const double ay = p[3 * i + 1] - p[3 * (i - 1) + 1];
    const double az = p[3 * i + 2] - p[3 * (i - 1) + 2];
    const double bx = p[3 * (i + 1)] - p[3 * i];
    const double by = p[3 * (i + 1) + 1] - p[3 * i + 1];
    const double bz = p[3 * (i + 1) + 2] - p[3 * i + 2];
    const double na = std::sqrt(ax * ax + ay * ay + az * az);
    const double nb = std::sqrt(bx * bx + by * by + bz * bz);
    if (na <= 0.0 || nb <= 0.0)
        return 0.0;
    double c = (ax * bx + ay * by + az * bz) / (na * nb);
    c = c > 1.0 ? 1.0 : (c < -1.0 ? -1.0 : c);
    return std::acos(c) * 180.0 / M_PI;
}

double pathTurnDeg(const std::vector<double> &xyz)
{
    const int n = static_cast<int>(xyz.size() / 3);
    double sum = 0.0;
    for (int i = 1; i + 1 < n; ++i)
        sum += cornerDeg(xyz, i);
    return sum;
}

double pathMaxCornerDeg(const std::vector<double> &xyz)
{
    const int n = static_cast<int>(xyz.size() / 3);
    double mx = 0.0;
    for (int i = 1; i + 1 < n; ++i) {
        const double a = cornerDeg(xyz, i);
        if (a > mx)
            mx = a;
    }
    return mx;
}

SweepPhases sweepReplica(int segments, int spans, Corner corner, Spine spine,
                         bool unify, double angminRad)
{
    SweepPhases ph;
    const std::vector<double> prof = arcRingXYB(segments, 6.0);
    const std::vector<double> path = arcPathXYZ(spans + 1, 60.0);
    const auto t0 = clk::now();
    try {
        /* The shipped shim runs arc_loop_wire over (x, y, bulge) triplets;
         * with every bulge zero that is exactly this polygon, and the identity
         * placement matrix makes BRepBuilderAPI_Transform a no-op. The
         * replica-vs-shim ratio the benchmark prints is what checks that
         * claim rather than asserting it. */
        BRepBuilderAPI_MakePolygon mp;
        for (int i = 0; i < segments; ++i)
            mp.Add(gp_Pnt(prof[3 * i], prof[3 * i + 1], prof[3 * i + 2]));
        mp.Close();
        const TopoDS_Wire outer = mp.Wire();
        const auto t1 = clk::now();
        ph.wire = msBetween(t0, t1);

        TopoDS_Wire spineWire;
        if (spine == Spine::Polyline) {
            BRepBuilderAPI_MakePolygon sp;
            for (int i = 0; i <= spans; ++i)
                sp.Add(gp_Pnt(path[3 * i], path[3 * i + 1], path[3 * i + 2]));
            spineWire = sp.Wire();
        } else {
            const int n = spans + 1;
            Handle(TColgp_HArray1OfPnt) pts = new TColgp_HArray1OfPnt(1, n);
            for (int i = 0; i < n; ++i)
                pts->SetValue(i + 1, gp_Pnt(path[3 * i], path[3 * i + 1],
                                            path[3 * i + 2]));
            GeomAPI_Interpolate itp(pts, Standard_False, 1.0e-7);
            itp.Perform();
            if (!itp.IsDone()) {
                ph.err = "spine interpolation failed";
                ph.total = msBetween(t0, clk::now());
                return ph;
            }
            spineWire = BRepBuilderAPI_MakeWire(
                            BRepBuilderAPI_MakeEdge(itp.Curve()).Edge())
                            .Wire();
        }
        const auto t2 = clk::now();
        ph.spine = msBetween(t1, t2);
        ph.spineEdges = countSub(spineWire, TopAbs_EDGE);

        Handle(BRepFill_PipeShell) mk = new BRepFill_PipeShell(spineWire);
        /* BRepOffsetAPI_MakePipeShell's own defaults, so mode RightCorner with
         * angminRad = 1e-2 reproduces the shim exactly. */
        mk->SetTolerance(1.0e-4, 1.0e-4, 1.0e-2);
        mk->SetTransition(corner == Corner::RightCorner   ? BRepFill_Right
                          : corner == Corner::Transformed ? BRepFill_Modified
                                                          : BRepFill_Round,
                          angminRad, 6.0);
        mk->Set(Standard_True); /* Frenet, as orientation 0 does */
        mk->Add(outer, Standard_False, Standard_False);
        const bool built = mk->Build();
        const auto t3 = clk::now();
        ph.build = msBetween(t2, t3);
        if (!built) {
            ph.err = "Build() returned false";
            ph.total = msBetween(t0, clk::now());
            return ph;
        }
        if (!mk->MakeSolid()) {
            ph.err = "MakeSolid() returned false";
            ph.total = msBetween(t0, clk::now());
            return ph;
        }
        const TopoDS_Shape body = mk->Shape();
        const auto t4 = clk::now();
        ph.solid = msBetween(t3, t4);

        TopoDS_Shape out = body;
        if (unify) {
            ShapeUpgrade_UnifySameDomain uni(body, Standard_True, Standard_True,
                                             Standard_False);
            uni.Build();
            out = uni.Shape();
        }
        const auto t5 = clk::now();
        ph.unify = msBetween(t4, t5);
        ph.total = msBetween(t0, t5);

        ph.faces = countSub(out, TopAbs_FACE);
        GProp_GProps g;
        BRepGProp::VolumeProperties(out, g);
        ph.volume = g.Mass();
        ph.valid = BRepCheck_Analyzer(out).IsValid() == Standard_True;
        ph.ok = true;
        return ph;
    } catch (const Standard_Failure &f) {
        ph.err = std::string("Standard_Failure: ") + f.GetMessageString();
    } catch (const std::exception &e) {
        ph.err = std::string("std::exception: ") + e.what();
    } catch (...) {
        ph.err = "non-standard exception";
    }
    ph.total = msBetween(t0, clk::now());
    return ph;
}

/* ---- S18: the DRAWN corner ------------------------------------------------ */

double cornerSectionArea(double w)
{
    return w * w;
}

double cornerSectionTurnOffset(double w)
{
    /* The square is [0,w] x [0,w] in its own plane and the turn is toward +X,
     * so what the mitre integral needs is the centroid's x, which is w/2.
     * It is NOT zero, and that is the whole reason a mitred corner changes the
     * volume at all — see the c_t = 0 remark under (I). */
    return 0.5 * w;
}

namespace {

/* The spine of a drawn corner: start at the origin heading +Z, walk each leg,
 * and turn by turnDeg[i] toward +X between legs. Returns the points. */
std::vector<gp_Pnt> cornerSpinePoints(const std::vector<double> &legs,
                                      const std::vector<double> &turnDeg)
{
    std::vector<gp_Pnt> p;
    p.reserve(legs.size() + 1);
    double x = 0.0, z = 0.0, phi = 0.0;
    p.emplace_back(0.0, 0.0, 0.0);
    for (size_t i = 0; i < legs.size(); ++i) {
        x += legs[i] * std::sin(phi);
        z += legs[i] * std::cos(phi);
        p.emplace_back(x, 0.0, z);
        if (i < turnDeg.size())
            phi += turnDeg[i] * M_PI / 180.0;
    }
    return p;
}

} // namespace

double cornerMiterVolume(const std::vector<double> &legs,
                         const std::vector<double> &turnDeg, double w)
{
    const double A = cornerSectionArea(w);
    const double ct = cornerSectionTurnOffset(w);
    double len = 0.0;
    for (double l : legs)
        len += l;
    double wedge = 0.0;
    for (double t : turnDeg)
        wedge += std::tan(0.5 * t * M_PI / 180.0);
    return A * len - 2.0 * A * ct * wedge;
}

double cornerTransformedVolume(const std::vector<double> &legs,
                               const std::vector<double> &turnDeg, double w)
{
    const double A = cornerSectionArea(w);
    double v = 0.0, phi = 0.0;
    for (size_t i = 0; i < legs.size(); ++i) {
        v += A * legs[i] * std::cos(phi);
        if (i < turnDeg.size())
            phi += turnDeg[i] * M_PI / 180.0;
    }
    return v;
}

CornerRun cornerReplica(const std::vector<double> &legs,
                        const std::vector<double> &turnDeg, double w,
                        Corner corner, double angminRad, int ringSegments)
{
    CornerRun r;
    const auto t0 = clk::now();
    try {
        /* The section, exactly as occt_sweep_profile's arc_loop_wire builds it
         * from zero-bulge (x, y) pairs under an identity placement. */
        BRepBuilderAPI_MakePolygon mp;
        if (ringSegments > 0) {
            const std::vector<double> ring = arcRingXYB(ringSegments, w);
            for (int i = 0; i < ringSegments; ++i)
                mp.Add(gp_Pnt(ring[3 * i], ring[3 * i + 1], ring[3 * i + 2]));
        } else {
            mp.Add(gp_Pnt(0.0, 0.0, 0.0));
            mp.Add(gp_Pnt(w, 0.0, 0.0));
            mp.Add(gp_Pnt(w, w, 0.0));
            mp.Add(gp_Pnt(0.0, w, 0.0));
        }
        mp.Close();
        const TopoDS_Wire outer = mp.Wire();

        const std::vector<gp_Pnt> pts = cornerSpinePoints(legs, turnDeg);
        BRepBuilderAPI_MakePolygon sp;
        for (const gp_Pnt &q : pts)
            sp.Add(q);
        const TopoDS_Wire spineWire = sp.Wire();

        Handle(BRepFill_PipeShell) mk = new BRepFill_PipeShell(spineWire);
        mk->SetTolerance(1.0e-4, 1.0e-4, 1.0e-2);
        mk->SetTransition(corner == Corner::RightCorner   ? BRepFill_Right
                          : corner == Corner::Transformed ? BRepFill_Modified
                                                          : BRepFill_Round,
                          angminRad, 6.0);
        mk->Set(Standard_True); /* Frenet, as orientation 0 does */
        mk->Add(outer, Standard_False, Standard_False);
        if (!mk->Build()) {
            r.err = "Build() returned false";
            r.ms = msBetween(t0, clk::now());
            return r;
        }
        if (!mk->MakeSolid()) {
            r.err = "MakeSolid() returned false";
            r.ms = msBetween(t0, clk::now());
            return r;
        }
        /* UnifySameDomain, because the shim runs it and S14 measured it at
         * 2 ms in 7 260 — it is in the pipeline, it is not the cost, and
         * leaving it out would make the face counts incomparable. */
        ShapeUpgrade_UnifySameDomain uni(mk->Shape(), Standard_True,
                                         Standard_True, Standard_False);
        uni.Build();
        const TopoDS_Shape out = uni.Shape();
        r.ms = msBetween(t0, clk::now());
        r.faces = countSub(out, TopAbs_FACE);
        r.spineEdges = countSub(spineWire, TopAbs_EDGE);
        GProp_GProps g;
        BRepGProp::VolumeProperties(out, g);
        r.volume = g.Mass();
        r.valid = BRepCheck_Analyzer(out).IsValid() == Standard_True;
        r.ok = true;
        return r;
    } catch (const Standard_Failure &f) {
        r.err = std::string("Standard_Failure: ") + f.GetMessageString();
    } catch (const std::exception &e) {
        r.err = std::string("std::exception: ") + e.what();
    } catch (...) {
        r.err = "non-standard exception";
    }
    r.ms = msBetween(t0, clk::now());
    return r;
}

double cornerCrossoverDeg(double L1, double L2, double w, double loDeg,
                          double hiDeg, double tolDeg, double angminRad)
{
    const std::vector<double> legs{L1, L2};
    /* f(theta) = measured Transformed - measured RightCorner. Positive below
     * the crossover, negative above it — that is (III)'s claim and bisecting
     * the MEASURED difference is what tests it. */
    auto f = [&](double th) -> double {
        const std::vector<double> turn{th};
        const CornerRun a = cornerReplica(legs, turn, w, Corner::Transformed,
                                          angminRad);
        const CornerRun b = cornerReplica(legs, turn, w, Corner::RightCorner,
                                          angminRad);
        if (!a.ok || !b.ok)
            return std::numeric_limits<double>::quiet_NaN();
        return a.volume - b.volume;
    };
    double flo = f(loDeg), fhi = f(hiDeg);
    /* An EXACT zero at a bracket end is not a bracket, and it is what the
     * first attempt at this measurement hit: below OCCT's angmin deadband of
     * 1.0e-2 rad = 0.5730 deg, BRepFill_Sweep::PerformCorner declares "this is
     * not a corner" and RightCorner stops mitring, so the two modes agree to
     * the last bit and the difference is 0.0, not a sign. Bracketing there
     * reports no crossover however plainly the crossover exists above it. The
     * caller must start above the deadband; this refuses rather than
     * pretending. */
    if (!(flo == flo) || !(fhi == fhi) || flo == 0.0 || fhi == 0.0
        || (flo > 0.0) == (fhi > 0.0))
        return -1.0;
    while (hiDeg - loDeg > tolDeg) {
        const double mid = 0.5 * (loDeg + hiDeg);
        const double fm = f(mid);
        if (!(fm == fm))
            return -1.0;
        if ((fm > 0.0) == (flo > 0.0)) {
            loDeg = mid;
            flo = fm;
        } else {
            hiDeg = mid;
            fhi = fm;
        }
    }
    return 0.5 * (loDeg + hiDeg);
}

} // namespace bench
