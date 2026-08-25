/* S19 — the instrument for perf/findings/S19-validity.md.
 *
 * WHAT THIS IS FOR, AND WHAT IT MAY BE TRUSTED FOR
 * ------------------------------------------------
 * S18 §5.2 found that `finish_pipe` never asks `BRepCheck_Analyzer` anything,
 * and routed the decision "should it?" to the integrator. That decision needs
 * two numbers and a mechanism:
 *
 *   --cost      what a gate would cost, as a function of the two things the
 *               shape's size is made of (profile segments, path legs), across
 *               the four ways BRepCheck_Analyzer can be asked;
 *   --catch     whether the CHEAP ways of asking catch the defects that are
 *               known to exist — a gate that is cheap and blind is not a gate;
 *   --census    which producible sweep configurations are invalid TODAY, i.e.
 *               exactly the list of parts that would stop building the day a
 *               gate lands;
 *   --offcentre S18 §5.1: an off-centre section going INVALID on a many-jointed
 *               path with no taper, which S18 recorded and did not chase.
 *
 * IT IS NOT A REPLICA. Every shape it checks comes out of the SHIPPED
 * `occt_sweep_profile_ex`, so what is being timed and classified is the
 * program, not a reconstruction of it. The one thing it needs that the C ABI
 * does not expose is the `TopoDS_Shape` inside an `occt_shape`, and that is
 * obtained by declaring the shim's own one-member struct — which is checked
 * rather than assumed: `--cost` and `--census` compare this file's
 * `BRepCheck_Analyzer(unwrap(sh)).IsValid()` against the shim's own
 * `occt_shape_valid(sh)` on EVERY shape they build, and print the count of
 * disagreements. A non-zero count invalidates the whole run and says so.
 *
 * It is deliberately NOT a Lane C scenario, for the reason S15's hole_probe
 * gives: Lane C runs on every push and gates on its exponents, and a rung that
 * checks a 1024-segment solid four different ways has no business there. Build
 * it with -DBENCH_VALID_PROBE=ON and run it by hand.
 */

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

#include <BRepBndLib.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepCheck_ListOfStatus.hxx>
#include <BRepCheck_Result.hxx>
#include <Bnd_Box.hxx>
#include <Standard_Failure.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS_Shape.hxx>

#include "occt_capi.h"

/* The shim's own definition, from occt_capi.cpp:190. One member, no vtable,
 * no ownership: this is a handle type. The `--cost` and `--census` arms check
 * the assumption on every shape they build rather than trusting this comment
 * (see the file header), and `mismatch` is reported whichever way it comes
 * out. */
struct occt_shape
{
    TopoDS_Shape s;
};

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

/* How BRepCheck_Analyzer was asked. The four combinations of the two flags
 * that matter; `theIsExact` stays false, which is the shim's setting and the
 * only one whose cost anybody would consider paying. */
struct Ask
{
    const char *name;
    Standard_Boolean geom;
    Standard_Boolean par;
};

const Ask kAsks[4] = {
    {"full", Standard_True, Standard_False},   /* what occt_shape_valid does */
    {"full-par", Standard_True, Standard_True},
    {"topo", Standard_False, Standard_False},
    {"topo-par", Standard_False, Standard_True},
};

struct CheckResult
{
    bool valid = false;
    double msec = 0.0;
};

CheckResult ask(const TopoDS_Shape &s, const Ask &a)
{
    CheckResult r;
    const clk::time_point t0 = clk::now();
    BRepCheck_Analyzer an(s, a.geom, a.par, Standard_False);
    r.valid = an.IsValid() == Standard_True;
    r.msec = ms(t0, clk::now());
    return r;
}

/* ---- the diagnosis ------------------------------------------------------ */

const char *statusName(BRepCheck_Status st)
{
    switch (st) {
        case BRepCheck_NoError: return "NoError";
        case BRepCheck_InvalidPointOnCurve: return "InvalidPointOnCurve";
        case BRepCheck_InvalidPointOnCurveOnSurface:
            return "InvalidPointOnCurveOnSurface";
        case BRepCheck_InvalidPointOnSurface: return "InvalidPointOnSurface";
        case BRepCheck_No3DCurve: return "No3DCurve";
        case BRepCheck_Multiple3DCurve: return "Multiple3DCurve";
        case BRepCheck_Invalid3DCurve: return "Invalid3DCurve";
        case BRepCheck_NoCurveOnSurface: return "NoCurveOnSurface";
        case BRepCheck_InvalidCurveOnSurface: return "InvalidCurveOnSurface";
        case BRepCheck_InvalidCurveOnClosedSurface:
            return "InvalidCurveOnClosedSurface";
        case BRepCheck_InvalidSameRangeFlag: return "InvalidSameRangeFlag";
        case BRepCheck_InvalidSameParameterFlag:
            return "InvalidSameParameterFlag";
        case BRepCheck_InvalidDegeneratedFlag:
            return "InvalidDegeneratedFlag";
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
        case BRepCheck_InvalidImbricationOfWires:
            return "InvalidImbricationOfWires";
        case BRepCheck_EmptyShell: return "EmptyShell";
        case BRepCheck_RedundantFace: return "RedundantFace";
        case BRepCheck_InvalidImbricationOfShells:
            return "InvalidImbricationOfShells";
        case BRepCheck_UnorientableShape: return "UnorientableShape";
        case BRepCheck_NotClosed: return "NotClosed";
        case BRepCheck_NotConnected: return "NotConnected";
        case BRepCheck_SubshapeNotInShape: return "SubshapeNotInShape";
        case BRepCheck_BadOrientation: return "BadOrientation";
        case BRepCheck_BadOrientationOfSubshape:
            return "BadOrientationOfSubshape";
        case BRepCheck_InvalidPolygonOnTriangulation:
            return "InvalidPolygonOnTriangulation";
        case BRepCheck_InvalidToleranceValue: return "InvalidToleranceValue";
        case BRepCheck_EnclosedRegion: return "EnclosedRegion";
        case BRepCheck_CheckFail: return "CheckFail";
    }
    return "?";
}

const char *kindName(TopAbs_ShapeEnum k)
{
    switch (k) {
        case TopAbs_VERTEX: return "vertex";
        case TopAbs_EDGE: return "edge";
        case TopAbs_WIRE: return "wire";
        case TopAbs_FACE: return "face";
        case TopAbs_SHELL: return "shell";
        case TopAbs_SOLID: return "solid";
        default: return "other";
    }
}

/* Every distinct (subshape kind, status) pair BRepCheck_Analyzer complains
 * about, with a count. This is the thing `occt_shape_valid`'s bool throws
 * away, and it is what a gate would have to put in an error message. */
struct Complaint
{
    TopAbs_ShapeEnum kind;
    BRepCheck_Status status;
    int count;
};

void collect(const BRepCheck_Analyzer &an, const TopoDS_Shape &s,
             std::vector<Complaint> &out)
{
    static const TopAbs_ShapeEnum kinds[] = {TopAbs_VERTEX, TopAbs_EDGE,
                                             TopAbs_WIRE,   TopAbs_FACE,
                                             TopAbs_SHELL,  TopAbs_SOLID};
    for (const TopAbs_ShapeEnum k : kinds) {
        for (TopExp_Explorer e(s, k); e.More(); e.Next()) {
            const Handle(BRepCheck_Result) &res = an.Result(e.Current());
            if (res.IsNull())
                continue;
            /* InitContextIterator/Status walks the statuses recorded for this
             * subshape in each context it appears in; the context-free list is
             * the one Status() returns before any iteration. */
            for (BRepCheck_ListIteratorOfListOfStatus it(res->Status());
                 it.More(); it.Next()) {
                const BRepCheck_Status st = it.Value();
                if (st == BRepCheck_NoError)
                    continue;
                bool found = false;
                for (Complaint &c : out) {
                    if (c.kind == k && c.status == st) {
                        ++c.count;
                        found = true;
                        break;
                    }
                }
                if (!found)
                    out.push_back({k, st, 1});
            }
        }
    }
}

std::string diagnose(const TopoDS_Shape &s, Standard_Boolean geom)
{
    BRepCheck_Analyzer an(s, geom, Standard_False, Standard_False);
    if (an.IsValid())
        return "valid";
    std::vector<Complaint> cs;
    collect(an, s, cs);
    if (cs.empty())
        return "INVALID (analyzer reports no per-subshape status)";
    std::string out;
    for (const Complaint &c : cs) {
        if (!out.empty())
            out += ", ";
        out += std::string(kindName(c.kind)) + ":" + statusName(c.status) +
               "x" + std::to_string(c.count);
    }
    return out;
}

/* ---- fixtures ----------------------------------------------------------- */

/* bench_sweep.h's arcPathXYZ, verbatim — the device fixture, and S14's, S15's
 * and S18's. A helix: a quarter turn of radius 0.3r in XY while z rises to r.
 * At r = 60 the arc length is 66.33 and the radius of curvature is 99.06. */
std::vector<double> helixPath(int n, double r = 60.0)
{
    std::vector<double> out;
    for (int i = 0; i < n; ++i) {
        const double t = static_cast<double>(i) / (n - 1);
        const double a = t * M_PI / 2.0;
        out.push_back(r * std::sin(a) * 0.3);
        out.push_back(r * (1.0 - std::cos(a)) * 0.3);
        out.push_back(t * r);
    }
    return out;
}

/* A straight path along +Z. One leg, no joints, nothing to mitre. */
std::vector<double> straightPath(double len = 40.0)
{
    return {0, 0, 0, 0, 0, len};
}

/* A planar zigzag in the XZ plane, starting along +Z: `legs` legs of length L,
 * each turning by `turnDeg` alternately left and right. The point of it is
 * that L and theta are INDEPENDENT here, which they are not on the helix.
 * Starting along +Z means the section (which the identity placement puts in
 * the XY plane) is perpendicular to the first leg — the control for the
 * helix's 25.23-degree tilt. */
std::vector<double> zigzagPath(int legs, double L, double turnDeg)
{
    std::vector<double> out{0, 0, 0};
    double x = 0, z = 0, dir = 0; /* dir = angle from +Z toward +X */
    for (int i = 0; i < legs; ++i) {
        if (i > 0)
            dir += (i % 2 ? -1.0 : 1.0) * turnDeg * M_PI / 180.0;
        x += L * std::sin(dir);
        z += L * std::cos(dir);
        out.push_back(x);
        out.push_back(0.0);
        out.push_back(z);
    }
    return out;
}

/* An L: two legs of length L meeting at `turnDeg`, in the XZ plane, first leg
 * along +Z. S18 §4.1's taper fixture, as a path. */
std::vector<double> elbowPath(double L, double turnDeg)
{
    return zigzagPath(2, L, turnDeg);
}

/* A square of side `side` whose lower-left corner is at (ox, oy), as the
 * (x, y, bulge) triplets the shim's profile reader takes. */
std::vector<double> squareXYB(double ox, double oy, double side)
{
    return {ox,        oy,        0, ox + side, oy,        0,
            ox + side, oy + side, 0, ox,        oy + side, 0};
}

/* An n-gon of radius r centred at (cx, cy) — bench_sweep.h's arcRingXYB with
 * a centre, so the same fixture can be moved off the spine. */
std::vector<double> ringXYB(int n, double r, double cx = 0.0, double cy = 0.0)
{
    std::vector<double> out;
    for (int i = 0; i < n; ++i) {
        const double a = 2.0 * M_PI * i / n;
        out.push_back(cx + r * std::cos(a));
        out.push_back(cy + r * std::sin(a));
        out.push_back(0.0);
    }
    return out;
}

const double kIdentity[12] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0};

/* Total turning and the largest joint of a polyline, in degrees. */
void pathAngles(const std::vector<double> &p, double &maxDeg, double &sumDeg)
{
    maxDeg = 0.0;
    sumDeg = 0.0;
    const int n = static_cast<int>(p.size() / 3);
    for (int i = 1; i + 1 < n; ++i) {
        double a[3], b[3];
        for (int k = 0; k < 3; ++k) {
            a[k] = p[3 * i + k] - p[3 * (i - 1) + k];
            b[k] = p[3 * (i + 1) + k] - p[3 * i + k];
        }
        const double na = std::sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
        const double nb = std::sqrt(b[0] * b[0] + b[1] * b[1] + b[2] * b[2]);
        if (na <= 0 || nb <= 0)
            continue;
        double c = (a[0] * b[0] + a[1] * b[1] + a[2] * b[2]) / (na * nb);
        c = c > 1.0 ? 1.0 : (c < -1.0 ? -1.0 : c);
        const double d = std::acos(c) * 180.0 / M_PI;
        maxDeg = std::max(maxDeg, d);
        sumDeg += d;
    }
}

double pathLength(const std::vector<double> &p)
{
    double L = 0.0;
    const int n = static_cast<int>(p.size() / 3);
    for (int i = 1; i < n; ++i) {
        double d = 0;
        for (int k = 0; k < 3; ++k) {
            const double t = p[3 * i + k] - p[3 * (i - 1) + k];
            d += t * t;
        }
        L += std::sqrt(d);
    }
    return L;
}

/* ---- one built shape ---------------------------------------------------- */

struct Built
{
    occt_shape *sh = nullptr;
    double buildMs = 0.0;
    int faces = 0;
    bool ok = false;
    std::string err;

    ~Built()
    {
        if (sh)
            occt_free_shape(sh);
    }
    const TopoDS_Shape &shape() const { return sh->s; }
};

/* The SHIPPED entry point, with one profile loop or several. */
void build(Built &b, const std::vector<std::vector<double>> &loops,
           const std::vector<double> &path, int orientation, double taperDeg,
           int pathMode)
{
    std::vector<double> xyb;
    std::vector<int> counts;
    for (const std::vector<double> &l : loops) {
        counts.push_back(static_cast<int>(l.size() / 3));
        xyb.insert(xyb.end(), l.begin(), l.end());
    }
    const clk::time_point t0 = clk::now();
    b.sh = occt_sweep_profile_ex(
        xyb.data(), counts.data(), static_cast<int>(loops.size()), kIdentity,
        path.data(), static_cast<int>(path.size() / 3), orientation, taperDeg,
        0.0, pathMode);
    b.buildMs = ms(t0, clk::now());
    b.ok = b.sh != nullptr;
    if (!b.ok) {
        b.err = occt_last_error();
        return;
    }
    b.faces = countSub(b.shape(), TopAbs_FACE);
}

int g_mismatch = 0;

/* The check on the ODR assumption in this file's header: the shim's own
 * predicate against ours, on the same shape, every time a shape is built. */
bool shimAgrees(const Built &b)
{
    const bool mine =
        BRepCheck_Analyzer(b.shape(), Standard_True, Standard_False,
                           Standard_False)
            .IsValid() == Standard_True;
    const bool theirs = occt_shape_valid(b.sh) != 0;
    if (mine != theirs)
        ++g_mismatch;
    return mine;
}

/* ---- the arms ----------------------------------------------------------- */

/* Least-squares exponent of y against x, in logs — bench_stats.cpp's fit()
 * without the standard error, which needs more rungs than these ladders have.
 */
double exponent(const std::vector<double> &x, const std::vector<double> &y)
{
    double sx = 0, sy = 0, sxx = 0, sxy = 0;
    int n = 0;
    for (size_t i = 0; i < x.size(); ++i) {
        if (x[i] <= 0 || y[i] <= 0)
            continue;
        const double lx = std::log(x[i]), ly = std::log(y[i]);
        sx += lx;
        sy += ly;
        sxx += lx * lx;
        sxy += lx * ly;
        ++n;
    }
    if (n < 2)
        return 0.0;
    const double d = n * sxx - sx * sx;
    if (std::fabs(d) < 1e-300)
        return 0.0;
    return (n * sxy - sx * sy) / d;
}

void armCost(int reps)
{
    std::printf("=== S19 --cost: what a BRepCheck_Analyzer gate costs ===\n");
    std::printf("shim %s\n\n", occt_version());

    /* P1 — quadratic in profile segments, at one leg. */
    std::printf("--- P1: n-gon profile, STRAIGHT one-leg path, 40 mm\n");
    std::printf("%6s %7s %10s %10s %10s %10s %10s %7s\n", "n", "faces",
                "build", "full", "full-par", "topo", "topo-par", "valid");
    std::vector<double> xs, ysFull, ysTopo, ysPar;
    for (const int n : {128, 256, 512, 1024}) {
        Built b;
        build(b, {ringXYB(n, 6.0)}, straightPath(), 0, 0.0, 1 /* POLY */);
        if (!b.ok) {
            std::printf("%6d  BUILD FAILED: %s\n", n, b.err.c_str());
            continue;
        }
        const bool v = shimAgrees(b);
        double best[4] = {1e18, 1e18, 1e18, 1e18};
        for (int r = 0; r < reps; ++r)
            for (int a = 0; a < 4; ++a)
                best[a] = std::min(best[a], ask(b.shape(), kAsks[a]).msec);
        std::printf("%6d %7d %10.1f %10.1f %10.1f %10.2f %10.2f %7s\n", n,
                    b.faces, b.buildMs, best[0], best[1], best[2], best[3],
                    v ? "yes" : "NO");
        xs.push_back(n);
        ysFull.push_back(best[0]);
        ysPar.push_back(best[1]);
        ysTopo.push_back(best[2]);
        std::fflush(stdout);
    }
    std::printf("  exponent in n: full %.3f   full-par %.3f   topo %.3f\n",
                exponent(xs, ysFull), exponent(xs, ysPar),
                exponent(xs, ysTopo));
    if (!xs.empty()) {
        double sp = 0, ch = 0;
        for (size_t i = 0; i < xs.size(); ++i) {
            sp += ysFull[i] / ysPar[i];
            ch += ysFull[i] / ysTopo[i];
        }
        std::printf("  full/full-par mean %.2fx   full/topo mean %.2fx\n",
                    sp / xs.size(), ch / xs.size());
    }

    /* P2 — linear in path legs, at one profile size. */
    std::printf("\n--- P2: 256-gon profile, POLYLINE helix, spans varying\n");
    std::printf("%6s %7s %10s %10s %10s %10s %10s %7s\n", "spans", "faces",
                "build", "full", "full-par", "topo", "topo-par", "valid");
    std::vector<double> sx, syFull;
    for (const int spans : {1, 4, 16, 64}) {
        Built b;
        const std::vector<double> path =
            spans == 1 ? straightPath() : helixPath(spans + 1);
        build(b, {ringXYB(256, 6.0)}, path, 0, 0.0, 1 /* POLY */);
        if (!b.ok) {
            std::printf("%6d  BUILD FAILED: %s\n", spans, b.err.c_str());
            continue;
        }
        const bool v = shimAgrees(b);
        double best[4] = {1e18, 1e18, 1e18, 1e18};
        for (int r = 0; r < reps; ++r)
            for (int a = 0; a < 4; ++a)
                best[a] = std::min(best[a], ask(b.shape(), kAsks[a]).msec);
        std::printf("%6d %7d %10.1f %10.1f %10.1f %10.2f %10.2f %7s\n", spans,
                    b.faces, b.buildMs, best[0], best[1], best[2], best[3],
                    v ? "yes" : "NO");
        sx.push_back(spans);
        syFull.push_back(best[0]);
        std::fflush(stdout);
    }
    std::printf("  exponent in spans: full %.3f\n", exponent(sx, syFull));

    /* The ratio the decision actually turns on. */
    std::printf("\n--- the gate's share: check / build, on the shapes above\n");
    struct Row
    {
        const char *what;
        int n;
        int spans;
        int mode;
    };
    const Row rows[] = {
        {"24-gon, 16-leg helix", 24, 16, 1},
        {"256-gon, 16-leg helix", 256, 16, 1},
        {"1024-gon, straight", 1024, 1, 1},
        {"1024-gon, 16-span helix SMOOTH", 1024, 16, 2},
    };
    std::printf("%34s %7s %9s %9s %8s %9s %8s\n", "shape", "faces", "build",
                "full", "share", "topo", "share");
    for (const Row &r : rows) {
        Built b;
        const std::vector<double> path =
            r.spans == 1 ? straightPath() : helixPath(r.spans + 1);
        build(b, {ringXYB(r.n, 6.0)}, path, 0, 0.0, r.mode);
        if (!b.ok) {
            std::printf("%34s  BUILD FAILED: %s\n", r.what, b.err.c_str());
            continue;
        }
        shimAgrees(b);
        double full = 1e18, topo = 1e18;
        for (int i = 0; i < reps; ++i) {
            full = std::min(full, ask(b.shape(), kAsks[0]).msec);
            topo = std::min(topo, ask(b.shape(), kAsks[2]).msec);
        }
        std::printf("%34s %7d %9.1f %9.1f %7.1f%% %9.2f %7.2f%%\n", r.what,
                    b.faces, b.buildMs, full, 100.0 * full / b.buildMs, topo,
                    100.0 * topo / b.buildMs);
        std::fflush(stdout);
    }
    std::printf("\nshim/probe validity disagreements: %d\n", g_mismatch);
}

/* One census row: build it, classify it, say what is wrong with it. */
struct Row
{
    std::string what;
    int faces = 0;
    double volume = 0.0;
    double buildMs = 0.0;
    bool built = false;
    bool full = false;
    bool topo = false;
    std::string diag;
};

Row classify(const std::string &what,
             const std::vector<std::vector<double>> &loops,
             const std::vector<double> &path, int orientation, double taperDeg,
             int pathMode, bool wantDiag = true)
{
    Row r;
    r.what = what;
    Built b;
    build(b, loops, path, orientation, taperDeg, pathMode);
    r.built = b.ok;
    r.buildMs = b.buildMs;
    if (!b.ok) {
        r.diag = b.err;
        return r;
    }
    r.faces = b.faces;
    r.volume = occt_shape_volume(b.sh);
    r.full = shimAgrees(b);
    r.topo = BRepCheck_Analyzer(b.shape(), Standard_False, Standard_False,
                                Standard_False)
                 .IsValid() == Standard_True;
    if (!r.full && wantDiag)
        r.diag = diagnose(b.shape(), Standard_True);
    return r;
}

void printRow(const Row &r)
{
    if (!r.built) {
        std::printf("%-52s  REFUSED  %s\n", r.what.c_str(), r.diag.c_str());
        return;
    }
    std::printf("%-52s %5d %14.6f %8.1f  %-7s %-5s %s\n", r.what.c_str(),
                r.faces, r.volume, r.buildMs, r.full ? "valid" : "INVALID",
                r.topo ? "ok" : "BAD", r.diag.c_str());
}

void armCatch()
{
    std::printf("=== S19 --catch: does the CHEAP check see the defects? ===\n");
    std::printf("%-52s %5s %14s %8s  %-7s %-5s %s\n", "configuration", "faces",
                "volume", "build", "full", "topo", "what BRepCheck says");

    /* S18 §4.1's tapered drawn corner: an L of 70/40 mm legs at 15 and 90
     * degrees, 10x10 section, taper 10. The volumes there are 8688.921317 and
     * 11136.303683. */
    for (const double turn : {0.4, 0.6, 15.0, 90.0}) {
        for (const double taper : {0.0, 10.0}) {
            char buf[128];
            std::snprintf(buf, sizeof(buf),
                          "L corner %.1f deg, centred section, taper %.1f",
                          turn, taper);
            printRow(classify(buf, {squareXYB(-5, -5, 10)},
                              elbowPath(40.0, turn), 0, taper, 1));
        }
    }
    /* S18 §5.1's off-centre section, no taper anywhere. */
    for (const int spans : {16}) {
        for (const double off : {-5.0, 0.0}) {
            char buf[128];
            std::snprintf(buf, sizeof(buf),
                          "helix %d legs POLY, square at [%.0f,%.0f], no taper",
                          spans, off, off + 10.0);
            printRow(classify(buf, {squareXYB(off, off, 10)},
                              helixPath(spans + 1), 0, 0.0, 1));
        }
    }
    std::printf("\nshim/probe validity disagreements: %d\n", g_mismatch);
}

void armOffcentre()
{
    std::printf("=== S19 --offcentre: chasing S18 5.1 ===\n\n");

    /* The reproduction first. Nothing below is worth reading unless this row
     * is S18's row. */
    std::printf("--- reproduction: S18 5.1's three rows, verbatim\n");
    std::printf("%-52s %5s %14s %8s  %-7s %-5s %s\n", "configuration", "faces",
                "volume", "build", "full", "topo", "what BRepCheck says");
    printRow(classify("[-5,5]^2 centred, helix 16 legs POLY",
                      {squareXYB(-5, -5, 10)}, helixPath(17), 0, 0.0, 1));
    printRow(classify("[0,2]^2, helix 16 legs POLY", {squareXYB(0, 0, 2)},
                      helixPath(17), 0, 0.0, 1));
    printRow(classify("[0,10]^2 corner on spine, helix 16 legs POLY",
                      {squareXYB(0, 0, 10)}, helixPath(17), 0, 0.0, 1));

    /* P8 — the deadband. The SAME section over the SAME path, subdivided. The
     * fold condition (I) says finer legs are MORE dangerous; the extension
     * mechanism says everything under 0.5730 deg is untouched and therefore
     * safe. */
    std::printf("\n--- P8: the same off-centre square, path subdivided\n");
    std::printf("%6s %9s %9s %6s %14s %-8s %s\n", "spans", "leg", "maxjoint",
                "faces", "volume", "verdict", "diagnosis");
    for (const int spans : {2, 4, 8, 16, 32, 64, 96, 128, 192}) {
        const std::vector<double> path = helixPath(spans + 1);
        double mx = 0, sum = 0;
        pathAngles(path, mx, sum);
        const Row r = classify("", {squareXYB(0, 0, 10)}, path, 0, 0.0, 1);
        std::printf("%6d %9.4f %9.4f %6d %14.6f %-8s %s\n", spans,
                    pathLength(path) / spans, mx, r.faces, r.volume,
                    !r.built ? "REFUSED" : (r.full ? "valid" : "INVALID"),
                    r.diag.c_str());
        std::fflush(stdout);
    }

    /* P9 — the boundary in the centroid offset, at a fixed leg. The square
     * keeps its size; only where it sits moves. */
    std::printf("\n--- P9a: offset ladder at spans=16 (leg 4.1452, joint "
                "2.3962 deg)\n");
    std::printf("%9s %9s %6s %14s %-8s %s\n", "c_t", "reach", "faces",
                "volume", "verdict", "diagnosis");
    for (const double c : {0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 12.0, 20.0,
                           40.0, 80.0, 99.0, 120.0}) {
        /* A 10x10 square whose CENTROID sits at (c/sqrt2, c/sqrt2), so the
         * offset is c and the reach is c + 7.071. */
        const double h = c / std::sqrt(2.0);
        const Row r = classify("", {squareXYB(h - 5, h - 5, 10)}, helixPath(17),
                               0, 0.0, 1);
        std::printf("%9.3f %9.3f %6d %14.6f %-8s %s\n", c, c + 7.071, r.faces,
                    r.volume,
                    !r.built ? "REFUSED" : (r.full ? "valid" : "INVALID"),
                    r.diag.c_str());
        std::fflush(stdout);
    }

    /* P9b — and the same ladder with the leg length varied at a fixed offset.
     * The zigzag is used here rather than the helix because it is the only
     * fixture in which L and theta move independently. */
    std::printf("\n--- P9b: zigzag, 6 legs, turn 5 deg, section [0,10]^2 "
                "(c_t 7.071), leg varying\n");
    std::printf("%9s %6s %14s %-8s %s\n", "leg", "faces", "volume", "verdict",
                "diagnosis");
    for (const double L : {1.0, 2.0, 4.0, 6.0, 8.0, 12.0, 20.0, 40.0}) {
        const Row r = classify("", {squareXYB(0, 0, 10)}, zigzagPath(6, L, 5.0),
                               0, 0.0, 1);
        std::printf("%9.3f %6d %14.6f %-8s %s\n", L, r.faces, r.volume,
                    !r.built ? "REFUSED" : (r.full ? "valid" : "INVALID"),
                    r.diag.c_str());
        std::fflush(stdout);
    }

    std::printf("\n--- P9c: zigzag, 6 legs, leg 20, section [0,10]^2, turn "
                "varying\n");
    std::printf("%9s %6s %14s %-8s %s\n", "turn", "faces", "volume", "verdict",
                "diagnosis");
    for (const double t : {0.3, 0.5, 0.55, 0.6, 1.0, 2.0, 5.0, 15.0, 30.0,
                           60.0, 90.0}) {
        const Row r = classify("", {squareXYB(0, 0, 10)}, zigzagPath(6, 20.0, t),
                               0, 0.0, 1);
        std::printf("%9.3f %6d %14.6f %-8s %s\n", t, r.faces, r.volume,
                    !r.built ? "REFUSED" : (r.full ? "valid" : "INVALID"),
                    r.diag.c_str());
        std::fflush(stdout);
    }

    /* P7 — the bounding box tell. EvalExtrapol's arithmetic against the
     * shape's own extent, on a fixture whose geometry makes the overshoot
     * readable on one axis. */
    std::printf("\n--- P7: the extension, measured on the bounding box\n");
    std::printf("%-46s %10s %10s %10s\n", "configuration", "zmin", "zmax",
                "path zmax");
    struct BB
    {
        const char *what;
        double turn;
        double off;
    };
    for (const BB &e : {BB{"L 90 deg, centred", 90.0, -5.0},
                        BB{"L 90 deg, [0,10]^2", 90.0, 0.0},
                        BB{"L 15 deg, centred", 15.0, -5.0},
                        BB{"L 15 deg, [0,10]^2", 15.0, 0.0},
                        BB{"L 5 deg, [0,10]^2", 5.0, 0.0},
                        BB{"L 0.4 deg, [0,10]^2", 0.4, 0.0}}) {
        Built b;
        const std::vector<double> path = elbowPath(40.0, e.turn);
        build(b, {squareXYB(e.off, e.off, 10)}, path, 0, 0.0, 1);
        if (!b.ok) {
            std::printf("%-46s  REFUSED %s\n", e.what, b.err.c_str());
            continue;
        }
        Bnd_Box box;
        BRepBndLib::Add(b.shape(), box);
        double x0, y0, z0, x1, y1, z1;
        box.Get(x0, y0, z0, x1, y1, z1);
        double pz = 0;
        for (size_t i = 2; i < path.size(); i += 3)
            pz = std::max(pz, path[i]);
        std::printf("%-46s %10.4f %10.4f %10.4f  %s\n", e.what, z0, z1, pz,
                    BRepCheck_Analyzer(b.shape()).IsValid() ? "valid"
                                                            : "INVALID");
        std::fflush(stdout);
    }

    std::printf("\nshim/probe validity disagreements: %d\n", g_mismatch);
}

void armCensus()
{
    std::printf("=== S19 --census: which producible sweeps are invalid "
                "today ===\n");
    std::printf("shim %s\n\n", occt_version());
    std::printf("%-52s %5s %14s %8s  %-7s %-5s %s\n", "configuration", "faces",
                "volume", "build", "full", "topo", "what BRepCheck says");

    struct P
    {
        const char *name;
        std::vector<double> pts;
        int mode;
    };
    /* Every path kind sweepPathModeOf can assign, plus the drawn corners a
     * user makes by hand. */
    const std::vector<P> paths = {
        {"straight", straightPath(), 1},
        {"L 90deg", elbowPath(40.0, 90.0), 1},
        {"L 15deg", elbowPath(40.0, 15.0), 1},
        {"zigzag 6x20 @5deg", zigzagPath(6, 20.0, 5.0), 1},
        {"zigzag 6x4 @5deg", zigzagPath(6, 4.0, 5.0), 1},
        {"helix16 POLY", helixPath(17), 1},
        {"helix16 AUTO", helixPath(17), 0},
        {"helix16 SMOOTH", helixPath(17), 2},
        {"helix4 POLY", helixPath(5), 1},
    };
    struct S
    {
        const char *name;
        std::vector<std::vector<double>> loops;
    };
    const std::vector<S> sections = {
        {"square centred", {squareXYB(-5, -5, 10)}},
        {"square c_t=7.07", {squareXYB(0, 0, 10)}},
        {"square c_t=21.2", {squareXYB(10, 10, 10)}},
        {"ring24 centred + hole", {ringXYB(24, 6), ringXYB(24, 3)}},
        {"ring24 c_t=20 + hole",
         {ringXYB(24, 6, 20, 0), ringXYB(24, 3, 20, 0)}},
    };

    int total = 0, refused = 0, invalid = 0, topoBad = 0;
    for (const P &p : paths) {
        for (const S &s : sections) {
            for (const int orient : {0, 1, 2}) {
                for (const double taper : {0.0, 5.0, -5.0}) {
                    char buf[160];
                    std::snprintf(buf, sizeof(buf), "%s | %s | or%d | tap%+.0f",
                                  p.name, s.name, orient, taper);
                    const Row r =
                        classify(buf, s.loops, p.pts, orient, taper, p.mode);
                    ++total;
                    if (!r.built)
                        ++refused;
                    else if (!r.full) {
                        ++invalid;
                        if (!r.topo)
                            ++topoBad;
                    }
                    /* Only the interesting rows are printed: a census that
                     * prints 405 valid lines hides its own result. */
                    if (!r.built || !r.full)
                        printRow(r);
                    std::fflush(stdout);
                }
            }
        }
    }
    std::printf("\n--- census: %d configurations, %d refused, %d INVALID "
                "(%.1f%% of what built), %d of those caught by the "
                "topology-only check\n",
                total, refused, invalid,
                total - refused ? 100.0 * invalid / (total - refused) : 0.0,
                topoBad);
    std::printf("shim/probe validity disagreements: %d\n", g_mismatch);
}

} // namespace

int main(int argc, char **argv)
{
    const std::string arm = argc > 1 ? argv[1] : "";
    const int reps = argc > 2 ? std::atoi(argv[2]) : 3;
    try {
        if (arm == "--cost")
            armCost(reps);
        else if (arm == "--catch")
            armCatch();
        else if (arm == "--census")
            armCensus();
        else if (arm == "--offcentre")
            armOffcentre();
        else {
            std::printf("usage: valid_probe --cost [reps] | --catch | "
                        "--census | --offcentre\n");
            return 2;
        }
    } catch (const Standard_Failure &e) {
        std::printf("EXCEPTION: %s\n", e.GetMessageString());
        return 1;
    }
    if (g_mismatch)
        std::printf("\n*** %d shim/probe disagreement(s): the struct layout "
                    "assumption in this file's header is WRONG and nothing "
                    "above may be read.\n",
                    g_mismatch);
    std::fflush(stdout);
    return 0;
}
