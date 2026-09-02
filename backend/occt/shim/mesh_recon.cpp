/* M232 — mesh -> B-Rep reconstruction. See mesh_recon.h for the shape of it.
 *
 * WHERE THE TOLERANCE COMES FROM, and why it is not decided here.
 *
 * tol_frac is a fraction of the bounding-box DIAGONAL, and on its own that is
 * the wrong scale for anything flat: the diagonal says how big a model is and
 * nothing about how fine it is. A 2 mm bookmark 166 mm across got 0.333 mm of
 * tolerance from its diagonal and came back a solid slab — all 37 of its
 * cut-outs closed, as thirty-nine separate solids carrying 171% too much
 * material. Bounded by its 2 mm thickness instead it converts at +0.17% with
 * every opening open. The mechanism in between is NOT established; see the
 * note on kVolumeDivergenceBar for what was ruled out.
 *
 * The rule that bounds it lives in ONE place, and that place is the caller —
 * frontend/lib/mesh_io.dart, brepTolFractionFor(), which caps the tolerance at
 * the model's thinnest dimension as well as its diagonal. It lives there
 * because the caller has the mesh's bounds in hand before the conversion
 * starts and can say so in the import log, where a person can read it.
 *
 * p.tol_frac below is therefore a FALLBACK, not a second opinion: it applies
 * only to a caller that passes 0. Nothing in this file clamps tol_frac again,
 * deliberately — two clamps would mean the smaller one silently wins and
 * neither the log nor the code would say which tolerance actually applied.
 *
 * What this file does instead is check its own answer. No rule can predict a
 * safe tolerance, because the quantity that matters is the narrowest gap
 * between two walls and every cheap proxy for it is dominated by tessellation
 * slivers — measured across the fixtures here, all four have two unconnected
 * vertices within 0.03 mm of each other, the perforated ones included. So the
 * converter builds the solid and then measures it against the volume of the
 * mesh it was given, and refuses to pass off a body that is not that part.
 */
#include "mesh_recon.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <map>
#include <unordered_map>
#include <unordered_set>
#include <vector>

#include <BRep_Builder.hxx>
#include <BRep_Tool.hxx>
#include <Bnd_Box.hxx>
#include <BRepBuilderAPI_MakeEdge.hxx>
#include <BRepBuilderAPI_MakeFace.hxx>
#include <BRepBuilderAPI_MakePolygon.hxx>
#include <BRepBuilderAPI_MakeSolid.hxx>
#include <BRepBndLib.hxx>
#include <BRepBuilderAPI_MakeVertex.hxx>
#include <BRepBuilderAPI_MakeWire.hxx>
#include <Message_ProgressIndicator.hxx>
#include <Message_ProgressScope.hxx>
#include <Message_ProgressRange.hxx>
#include <BRepBuilderAPI_Sewing.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepGProp.hxx>
#include <BRepLib.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepTools.hxx>
#include <ElSLib.hxx>
#include <GProp_GProps.hxx>
#include <Geom_BSplineCurve.hxx>
#include <Geom_BSplineSurface.hxx>
#include <Geom_ConicalSurface.hxx>
#include <Geom_Circle.hxx>
#include <Geom_CylindricalSurface.hxx>
#include <Geom_ElementarySurface.hxx>
#include <Geom_Plane.hxx>
#include <Geom_RectangularTrimmedSurface.hxx>
#include <Geom_SphericalSurface.hxx>
#include <Geom_Surface.hxx>
#include <Geom_TrimmedCurve.hxx>
#include <Geom_ToroidalSurface.hxx>
#include <GeomAPI_IntSS.hxx>
#include <GeomAPI_PointsToBSplineSurface.hxx>
#include <GeomAPI_PointsToBSpline.hxx>
#include <GeomAPI_ProjectPointOnCurve.hxx>
#include <GeomAPI_ProjectPointOnSurf.hxx>
#include <ShapeBuild_ReShape.hxx>
#include <ShapeFix_Edge.hxx>
#include <ShapeFix_Face.hxx>
#include <ShapeFix_Shape.hxx>
#include <ShapeFix_Shell.hxx>
#include <ShapeUpgrade_UnifySameDomain.hxx>
#include <TColStd_Array1OfInteger.hxx>
#include <TColStd_Array1OfReal.hxx>
#include <TColgp_Array1OfPnt.hxx>
#include <TColgp_Array2OfPnt.hxx>
#include <Poly_PolygonOnTriangulation.hxx>
#include <Poly_Triangulation.hxx>
#include <queue>
#include <TopExp.hxx>
#include <TopTools_DataMapOfShapeInteger.hxx>
#include <TopTools_IndexedDataMapOfShapeListOfShape.hxx>
#include <TopTools_ListIteratorOfListOfShape.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS.hxx>
#include <TopoDS_Compound.hxx>
#include <TopoDS_Edge.hxx>
#include <TopoDS_Face.hxx>
#include <TopoDS_Shell.hxx>
#include <TopoDS_Solid.hxx>
#include <TopoDS_Vertex.hxx>
#include <TopoDS_Wire.hxx>
#include <gp_Ax3.hxx>
#include <gp_Circ.hxx>
#include <gp_Cone.hxx>
#include <gp_Cylinder.hxx>
#include <gp_Lin.hxx>
#include <gp_Pln.hxx>
#include <gp_Sphere.hxx>
#include <gp_Torus.hxx>

namespace meshrecon {

/* ---- progress ---------------------------------------------------------
 *
 * Three atomics and nothing else. They are written by the converting thread
 * and read by whatever thread is drawing the busy card, so they are relaxed
 * atomics rather than plain ints: torn reads on a progress bar are harmless,
 * but a data race is undefined behaviour and this is a library.
 *
 * Deliberately global. A conversion is one at a time by contract (the kernel
 * is single-threaded, which is why the isolate blocks inside it), so there is
 * nothing to key them by, and a caller who wants them cannot reach into
 * Reconstruct's locals from another thread anyway. */
std::atomic<int> g_stage(kStageIdle);
std::atomic<int> g_done(0);
std::atomic<int> g_total(0);

/* ---- one bar, not five ---------------------------------------------------
 *
 * A bar per stage means a bar that empties and refills four times, and a user
 * watching it cannot tell the fourth 20% from the first. So the stages own
 * SPANS of a single 0..1, and the bar only ever moves forward.
 *
 * The spans are measured, not guessed. Per-stage share of the total, over four
 * models spanning 1,138 to 83,178 triangles (whale / broomholder / TOKA /
 * a tessellated ellipsoid):
 *
 *   fitting surfaces  49.1  62.8  69.2  80.2 %      building faces   2.1 - 12.7 %
 *   covering freeform  0.0   3.9  11.3   0.1 %      sewing          15.2 - 34.1 %
 *
 * and the 1:1 path, which is steadier still:
 *
 *   building triangles 40.1  42.1  46.3  48.0 %     merging  33.1 - 43.6 %
 *   sewing             14.8  15.5  17.2  17.3 %
 *
 * The spans below are the medians of those, rounded. A model that does not
 * match them makes the bar move unevenly, which is what an uneven job looks
 * like; it can never make it go backwards or reach the end early, because a
 * stage is clamped to its own span. */
struct Span { double a, b; };

Span SpanOf(int stage)
{
    switch (stage) {
    case kStageWelding:    return {0.000, 0.005};
    case kStageSegmenting: return {0.005, 0.010};
    case kStageFitting:    return {0.010, 0.660};
    case kStageFreeform:   return {0.660, 0.720};
    case kStageBuilding:   return {0.720, 0.800};
    case kStageFaceted:    return {0.000, 0.450};
    case kStageMerging:    return {0.610, 1.000};
    /* Sewing ends both paths, and starts wherever the path before it ended. */
    case kStageSewing:     return {0.800, 1.000};
    default:               return {0.0, 0.0};
    }
}

/* Where the bar is, over the whole conversion, as thousandths.
 *
 * Thousandths rather than a double so the whole snapshot stays plain ints
 * across the C ABI, and because no bar on any screen resolves better. */
std::atomic<int> g_overall(0);

/* How far the CURRENT stage could possibly take it — the top of its span.
 *
 * A stage that can count itself publishes a position and this is only a bound.
 * A stage that cannot — merging coplanar faces is 33-44% of a 1:1 conversion
 * and OCCT offers no way in — would otherwise freeze the bar for a third of
 * the job. So this side publishes what it actually knows, which is "somewhere
 * between here and there", and the side DRAWING the bar eases across that gap
 * on elapsed time without ever passing it. The estimate then lives in the
 * presentation, where a wrong one costs a bar that moves at the wrong speed,
 * rather than in the measurement, where it would be a lie about the work. */
std::atomic<int> g_ceiling(0);

/* Sewing ends the fitted path and sits in the middle of the 1:1 one, so its
 * span depends on which is running — and only Reconstruct knows that, so it
 * says. Fitted: 0.80 to the end. 1:1: 0.45 to 0.61, with the coplanar-face
 * merge taking the rest, which is what the measurements above show. */
std::atomic<int> g_sewFrom(800);
std::atomic<int> g_sewTo(1000);

void PublishOverall()
{
    const int st = g_stage.load(std::memory_order_relaxed);
    if (st <= kStageIdle || st >= kStageCount) {
        g_overall.store(0, std::memory_order_relaxed);
        g_ceiling.store(0, std::memory_order_relaxed);
        return;
    }
    Span sp = SpanOf(st);
    if (st == kStageSewing) {
        sp.a = g_sewFrom.load(std::memory_order_relaxed) / 1000.0;
        sp.b = g_sewTo.load(std::memory_order_relaxed) / 1000.0;
    }
    const int tot = g_total.load(std::memory_order_relaxed);
    const int dn = g_done.load(std::memory_order_relaxed);
    double f = 0;
    if (tot > 0)
        f = std::min(1.0, std::max(0.0, double(dn) / double(tot)));
    g_ceiling.store(int(sp.b * 1000.0 + 0.5), std::memory_order_relaxed);
    const int want = int((sp.a + (sp.b - sp.a) * f) * 1000.0 + 0.5);
    /* Never backwards. A stage that publishes a total larger than it turns out
     * to need would otherwise pull the bar back when the next stage starts
     * lower, and a bar that retreats reads as work being undone. */
    int cur = g_overall.load(std::memory_order_relaxed);
    if (want > cur)
        g_overall.store(want, std::memory_order_relaxed);
}

/* ---- cancelling ----------------------------------------------------------
 *
 * The conversion blocks its caller for as long as it runs, so "wait or force
 * quit" is the whole of the user's control over it without this. The flag is
 * set from the thread drawing the card and read by the converting thread at
 * every point where abandoning the work is cheap and safe: between patches,
 * between regions, and — through OCCT's own Message_ProgressIndicator — inside
 * the sewing, which is the single longest call and cannot be interrupted any
 * other way.
 *
 * Nothing is half-written when it fires: Reconstruct returns a null shape and
 * the caller sees a cancellation, exactly as it sees a refusal. */
std::atomic<bool> g_cancel(false);

/* The exact words a cancelled run reports. The app matches on them to tell a
 * cancellation from a failure — one deserves a message and the other does not
 * — so they are a constant and not a literal typed twice. */
extern const char *const kCancelledMessage = "cancelled";

bool Cancelled()
{
    return g_cancel.load(std::memory_order_relaxed);
}

void SetStage(int stage, int total)
{
    g_done.store(0, std::memory_order_relaxed);
    g_total.store(total, std::memory_order_relaxed);
    g_stage.store(stage, std::memory_order_relaxed);
    PublishOverall();
}

void SetDone(int done)
{
    g_done.store(done, std::memory_order_relaxed);
    PublishOverall();
}

/* Adds to the count. Only the converting thread writes, so this needs no
 * read-modify-write against anyone; fetch_add is simply the shortest way to
 * say it without keeping a second copy of the value. */
void AddDone(int delta)
{
    if (delta > 0) {
        g_done.fetch_add(delta, std::memory_order_relaxed);
        PublishOverall();
    }
}

/* Zeroed on the way out of every exit, so a card that outlives a conversion
 * shows nothing rather than the last thing it saw. */
struct StageGuard
{
    /* Cleared on the way IN as well as out.
     *
     * The flag is set by a person tapping a button, and a tap that lands in
     * the moment between one conversion finishing and the next one starting
     * would otherwise cancel a run that had not begun when they asked — they
     * would see the next import they started die instantly for no reason.
     * A cancellation belongs to the run that was on screen when it was asked
     * for, and to no other. */
    StageGuard() { g_cancel.store(false, std::memory_order_relaxed); }

    ~StageGuard()
    {
        SetStage(kStageIdle, 0);
        g_overall.store(0, std::memory_order_relaxed);
        g_ceiling.store(0, std::memory_order_relaxed);
        /* A cancellation is consumed by the run it stopped. Leaving it set
         * would cancel the NEXT import before it drew a triangle. */
        g_cancel.store(false, std::memory_order_relaxed);
    }
};

void Progress(int &stage, int &done, int &total)
{
    stage = g_stage.load(std::memory_order_relaxed);
    done = g_done.load(std::memory_order_relaxed);
    total = g_total.load(std::memory_order_relaxed);
}

int Overall()
{
    return g_overall.load(std::memory_order_relaxed);
}

int Ceiling()
{
    return g_ceiling.load(std::memory_order_relaxed);
}

void RequestCancel()
{
    g_cancel.store(true, std::memory_order_relaxed);
}

bool Cancelled_ForTest()
{
    return g_cancel.load(std::memory_order_relaxed);
}

/* What to put under the bar.
 *
 * These are read by someone waiting for their model, not by whoever wrote the
 * pipeline: "sewing the solid" and "merging coplanar faces" name the algorithm
 * and tell that person nothing they can act on. What helps is knowing roughly
 * where the work is, in the words they would use about their own model. The
 * app has its own translations keyed off the stage NUMBER; this is the
 * fallback for a caller that has none. */
const char *StageName(int stage)
{
    switch (stage) {
    case kStageWelding: return "Reading the model";
    case kStageSegmenting: return "Finding surfaces";
    case kStageFitting: return "Fitting surfaces";
    case kStageFreeform: return "Shaping curved areas";
    case kStageBuilding: return "Building faces";
    case kStageSewing: return "Finishing";
    case kStageFaceted: return "Building faces";
    case kStageMerging: return "Simplifying";
    default: return "";
    }
}

Params Defaults()
{
    Params p;
    p.mode = 1;
    /* A fallback for callers that do not compute one. The app does: see the
     * note at the top of this file, and brepTolFractionFor() in mesh_io.dart. */
    p.tol_frac = 2.0e-3;
    p.sharp_deg = 22.0;
    p.weld_frac = 1.0e-6;
    p.snap_deg = 1.5;
    p.snap_radius_frac = 2.0e-3;
    p.max_faceted_triangles = 120000;
    p.min_patch_triangles = 2;
    return p;
}

void ClearReport(Report &r)
{
    std::memset(&r, 0, sizeof(r));
}

/* ====================================================================== */
/* Small vector maths. Deliberately local: pulling gp_Vec through the      */
/* fitting inner loops costs more than three doubles are worth, and the    */
/* eigen solver below has no OCCT equivalent that is any simpler to call.  */
/* ====================================================================== */
namespace {

struct V3
{
    double x, y, z;
    V3() : x(0), y(0), z(0) {}
    V3(double a, double b, double c) : x(a), y(b), z(c) {}
    V3 operator+(const V3 &o) const { return V3(x + o.x, y + o.y, z + o.z); }
    V3 operator-(const V3 &o) const { return V3(x - o.x, y - o.y, z - o.z); }
    V3 operator*(double s) const { return V3(x * s, y * s, z * s); }
    V3 &operator+=(const V3 &o)
    {
        x += o.x;
        y += o.y;
        z += o.z;
        return *this;
    }
};

inline double Dot(const V3 &a, const V3 &b)
{
    return a.x * b.x + a.y * b.y + a.z * b.z;
}
inline V3 Cross(const V3 &a, const V3 &b)
{
    return V3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z,
              a.x * b.y - a.y * b.x);
}
inline double Norm(const V3 &a)
{
    return std::sqrt(Dot(a, a));
}
inline V3 Unit(const V3 &a)
{
    const double n = Norm(a);
    return n > 0 ? V3(a.x / n, a.y / n, a.z / n) : V3(0, 0, 1);
}
inline gp_Pnt P(const V3 &a)
{
    return gp_Pnt(a.x, a.y, a.z);
}
inline gp_Dir D(const V3 &a)
{
    return gp_Dir(a.x, a.y, a.z);
}

/* Eigen-decomposition of a symmetric 3x3, by cyclic Jacobi.
 *
 * m is row-major and is destroyed. Eigenvalues come back in `val` ASCENDING,
 * with the matching unit eigenvectors in the ROWS of `vec`. Every surface fit
 * below leans on this: a plane's normal, a cylinder's axis and a cone's axis
 * are all "the eigenvector of some covariance with the smallest eigenvalue". */
void Jacobi3(double m[9], double val[3], double vec[9])
{
    for (int i = 0; i < 9; ++i)
        vec[i] = (i % 4 == 0) ? 1.0 : 0.0;
    for (int sweep = 0; sweep < 24; ++sweep) {
        double off = 0;
        for (int i = 0; i < 3; ++i)
            for (int j = i + 1; j < 3; ++j)
                off += m[i * 3 + j] * m[i * 3 + j];
        if (off < 1e-30)
            break;
        for (int p = 0; p < 3; ++p) {
            for (int q = p + 1; q < 3; ++q) {
                const double apq = m[p * 3 + q];
                if (std::fabs(apq) < 1e-300)
                    continue;
                const double theta = (m[q * 3 + q] - m[p * 3 + p]) / (2 * apq);
                const double t =
                    (theta >= 0 ? 1.0 : -1.0) /
                    (std::fabs(theta) + std::sqrt(theta * theta + 1));
                const double c = 1 / std::sqrt(t * t + 1), s = t * c;
                for (int k = 0; k < 3; ++k) {
                    const double akp = m[k * 3 + p], akq = m[k * 3 + q];
                    m[k * 3 + p] = c * akp - s * akq;
                    m[k * 3 + q] = s * akp + c * akq;
                }
                for (int k = 0; k < 3; ++k) {
                    const double apk = m[p * 3 + k], aqk = m[q * 3 + k];
                    m[p * 3 + k] = c * apk - s * aqk;
                    m[q * 3 + k] = s * apk + c * aqk;
                }
                for (int k = 0; k < 3; ++k) {
                    const double vkp = vec[k * 3 + p], vkq = vec[k * 3 + q];
                    vec[k * 3 + p] = c * vkp - s * vkq;
                    vec[k * 3 + q] = s * vkp + c * vkq;
                }
            }
        }
    }
    /* vec currently holds eigenvectors in COLUMNS; sort ascending and transpose
     * into rows so callers can say vec[0..2] for "the smallest". */
    int order[3] = {0, 1, 2};
    double d[3] = {m[0], m[4], m[8]};
    for (int i = 0; i < 3; ++i)
        for (int j = i + 1; j < 3; ++j)
            if (d[order[j]] < d[order[i]])
                std::swap(order[i], order[j]);
    double out[9];
    for (int i = 0; i < 3; ++i) {
        val[i] = d[order[i]];
        for (int k = 0; k < 3; ++k)
            out[i * 3 + k] = vec[k * 3 + order[i]];
    }
    std::memcpy(vec, out, sizeof(out));
}

/* Gauss elimination with partial pivoting. n <= 8. False if singular. */
bool SolveLin(double *a, double *b, int n)
{
    for (int c = 0; c < n; ++c) {
        int piv = c;
        for (int r = c + 1; r < n; ++r)
            if (std::fabs(a[r * n + c]) > std::fabs(a[piv * n + c]))
                piv = r;
        if (std::fabs(a[piv * n + c]) < 1e-14)
            return false;
        if (piv != c) {
            for (int k = 0; k < n; ++k)
                std::swap(a[c * n + k], a[piv * n + k]);
            std::swap(b[c], b[piv]);
        }
        for (int r = 0; r < n; ++r) {
            if (r == c)
                continue;
            const double f = a[r * n + c] / a[c * n + c];
            if (f == 0)
                continue;
            for (int k = c; k < n; ++k)
                a[r * n + k] -= f * a[c * n + k];
            b[r] -= f * b[c];
        }
    }
    for (int i = 0; i < n; ++i)
        b[i] /= a[i * n + i];
    return true;
}

/* ====================================================================== */
/* The mesh                                                               */
/* ====================================================================== */

struct Mesh
{
    std::vector<V3> pos;
    std::vector<int> tri;      /* 3 per triangle */
    std::vector<V3> tnorm;     /* per triangle, unit */
    std::vector<double> tarea; /* per triangle */
    double area = 0;           /* their sum: the model's whole surface */
    /* adj[t*3+k] is the triangle across the k-th edge of triangle t — the
     * edge (tri[t*3+k], tri[t*3+(k+1)%3]) — or -1 at a boundary or at a
     * non-manifold edge. */
    std::vector<int> adj;
    V3 bbmin, bbmax;
    double diagonal = 0;

    int triCount() const { return static_cast<int>(tri.size() / 3); }
    int vertCount() const { return static_cast<int>(pos.size()); }
};

/* Welds vertices within `tol` using a hash grid, probing the 27 neighbouring
 * cells so a pair straddling a cell boundary still merges. This is the weld
 * mesh_io.dart deliberately does not do: it needs a spatial index over
 * millions of points and it needs the part's own scale to pick `tol`. */
struct WeldGrid
{
    double cell;
    std::unordered_map<long long, std::vector<int>> cells;
    const std::vector<V3> *pts;

    static long long Key(long long a, long long b, long long c)
    {
        /* Three 21-bit cell coordinates in one 64-bit key. The offset keeps
         * negative coordinates in range without a signed-shift question. */
        const long long m = 0x1FFFFF;
        return ((a + 0x100000) & m) | (((b + 0x100000) & m) << 21) |
               (((c + 0x100000) & m) << 42);
    }

    int Find(const V3 &p, double tol2) const
    {
        const long long ci = static_cast<long long>(std::floor(p.x / cell));
        const long long cj = static_cast<long long>(std::floor(p.y / cell));
        const long long ck = static_cast<long long>(std::floor(p.z / cell));
        for (int dx = -1; dx <= 1; ++dx)
            for (int dy = -1; dy <= 1; ++dy)
                for (int dz = -1; dz <= 1; ++dz) {
                    auto it = cells.find(Key(ci + dx, cj + dy, ck + dz));
                    if (it == cells.end())
                        continue;
                    for (int idx : it->second) {
                        const V3 d = (*pts)[idx] - p;
                        if (Dot(d, d) <= tol2)
                            return idx;
                    }
                }
        return -1;
    }

    void Add(const V3 &p, int idx)
    {
        const long long ci = static_cast<long long>(std::floor(p.x / cell));
        const long long cj = static_cast<long long>(std::floor(p.y / cell));
        const long long ck = static_cast<long long>(std::floor(p.z / cell));
        cells[Key(ci, cj, ck)].push_back(idx);
    }
};

bool BuildMesh(const double *xyz, int nv, const int *tri, int nt,
               const Params &prm, Mesh &m, Report &rep)
{
    rep.vertices_in = nv;
    rep.triangles_in = nt;
    if (nv < 3 || nt < 1)
        return false;

    m.bbmin = V3(1e300, 1e300, 1e300);
    m.bbmax = V3(-1e300, -1e300, -1e300);
    for (int i = 0; i < nv; ++i) {
        const V3 p(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2]);
        m.bbmin.x = std::min(m.bbmin.x, p.x);
        m.bbmax.x = std::max(m.bbmax.x, p.x);
        m.bbmin.y = std::min(m.bbmin.y, p.y);
        m.bbmax.y = std::max(m.bbmax.y, p.y);
        m.bbmin.z = std::min(m.bbmin.z, p.z);
        m.bbmax.z = std::max(m.bbmax.z, p.z);
    }
    m.diagonal = Norm(m.bbmax - m.bbmin);
    if (!(m.diagonal > 0))
        return false;
    rep.diagonal = m.diagonal;

    const double tol = std::max(m.diagonal * prm.weld_frac, 1e-12);
    WeldGrid grid;
    grid.cell = tol * 2;
    grid.pts = &m.pos;
    m.pos.reserve(nv);
    std::vector<int> remap(nv, -1);
    const double tol2 = tol * tol;
    for (int i = 0; i < nv; ++i) {
        const V3 p(xyz[i * 3], xyz[i * 3 + 1], xyz[i * 3 + 2]);
        int hit = grid.Find(p, tol2);
        if (hit < 0) {
            hit = static_cast<int>(m.pos.size());
            m.pos.push_back(p);
            grid.Add(p, hit);
        }
        remap[i] = hit;
    }
    rep.vertices_welded = static_cast<int>(m.pos.size());

    m.tri.reserve(nt * 3);
    for (int t = 0; t < nt; ++t) {
        const int a = tri[t * 3], b = tri[t * 3 + 1], c = tri[t * 3 + 2];
        if (a < 0 || b < 0 || c < 0 || a >= nv || b >= nv || c >= nv)
            continue;
        const int ra = remap[a], rb = remap[b], rc = remap[c];
        if (ra == rb || rb == rc || ra == rc)
            continue;
        const V3 n = Cross(m.pos[rb] - m.pos[ra], m.pos[rc] - m.pos[ra]);
        /* A triangle with no area carries no normal and no adjacency worth
         * having; keeping it only puts a degenerate face in the shell. */
        if (Norm(n) <= 1e-24 * m.diagonal * m.diagonal)
            continue;
        m.tri.push_back(ra);
        m.tri.push_back(rb);
        m.tri.push_back(rc);
    }
    rep.triangles_used = m.triCount();
    if (m.triCount() < 1)
        return false;

    m.tnorm.resize(m.triCount());
    m.tarea.resize(m.triCount());
    for (int t = 0; t < m.triCount(); ++t) {
        const V3 n = Cross(m.pos[m.tri[t * 3 + 1]] - m.pos[m.tri[t * 3]],
                           m.pos[m.tri[t * 3 + 2]] - m.pos[m.tri[t * 3]]);
        m.tarea[t] = Norm(n) * 0.5;
        m.area += m.tarea[t];
        m.tnorm[t] = Unit(n);
    }
    return true;
}

/* Reverses one triangle's winding, keeping its adjacency straight.
 *
 * adj[t*3+k] is the neighbour across the edge (tri[k], tri[k+1]). Swapping
 * vertices 1 and 2 renames those edges — old edge 0 becomes new edge 2 and
 * vice versa — so the adjacency has to be permuted with them. Flipping without
 * this leaves the mesh believing in neighbours it does not have, and the bug
 * only shows up on meshes that needed flipping at all. */
void FlipTriangle(Mesh &m, int t)
{
    std::swap(m.tri[t * 3 + 1], m.tri[t * 3 + 2]);
    if (!m.adj.empty())
        std::swap(m.adj[t * 3 + 0], m.adj[t * 3 + 2]);
    m.tnorm[t] = V3(-m.tnorm[t].x, -m.tnorm[t].y, -m.tnorm[t].z);
}

/* Fills m.adj. An edge shared by more than two triangles is non-manifold; both
 * sides are left unlinked, which turns it into a patch boundary. That is the
 * right answer rather than an error: downloaded models are full of them, and a
 * non-manifold edge IS a feature boundary in every case that matters. */
void BuildAdjacency(Mesh &m, Report &rep)
{
    m.adj.assign(m.tri.size(), -1);
    /* Key an undirected edge on its two welded vertex ids. */
    std::unordered_map<long long, int> half; /* edge -> first (t*3+k) */
    std::unordered_map<long long, int> count;
    half.reserve(m.tri.size());
    count.reserve(m.tri.size());
    const long long n = m.vertCount();
    for (int t = 0; t < m.triCount(); ++t) {
        for (int k = 0; k < 3; ++k) {
            const int a = m.tri[t * 3 + k], b = m.tri[t * 3 + (k + 1) % 3];
            const long long key =
                (long long)std::min(a, b) * n + std::max(a, b);
            const int c = ++count[key];
            if (c == 1) {
                half[key] = t * 3 + k;
            } else if (c == 2) {
                const int other = half[key];
                m.adj[t * 3 + k] = other / 3;
                m.adj[other] = t;
            } else {
                /* Third and later: unlink the pair already made. */
                const int other = half[key];
                if (m.adj[other] >= 0) {
                    const int o2 = m.adj[other];
                    for (int kk = 0; kk < 3; ++kk)
                        if (m.adj[o2 * 3 + kk] == other / 3)
                            m.adj[o2 * 3 + kk] = -1;
                    m.adj[other] = -1;
                }
                m.adj[t * 3 + k] = -1;
            }
        }
    }
    for (auto &e : count) {
        if (e.second == 1)
            rep.boundary_edges++;
        else if (e.second > 2)
            rep.non_manifold_edges++;
    }
}

/* Makes the winding consistent across each connected component, then flips
 * whole components whose enclosed volume comes out negative.
 *
 * Downloaded meshes are routinely inside-out, and an inside-out shell sews
 * into a solid of negative volume that every boolean afterwards gets wrong. */
void OrientMesh(Mesh &m, Report &rep)
{
    const int nt = m.triCount();
    std::vector<char> seen(nt, 0);
    std::vector<int> stack, comp;
    for (int seed = 0; seed < nt; ++seed) {
        if (seen[seed])
            continue;
        stack.clear();
        comp.clear();
        stack.push_back(seed);
        seen[seed] = 1;
        while (!stack.empty()) {
            const int t = stack.back();
            stack.pop_back();
            comp.push_back(t);
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0 || seen[o])
                    continue;
                /* Neighbours agree when they traverse the shared edge in
                 * OPPOSITE directions. If they do not, flip the neighbour. */
                const int a = m.tri[t * 3 + k], b = m.tri[t * 3 + (k + 1) % 3];
                bool same = false;
                for (int kk = 0; kk < 3; ++kk) {
                    if (m.tri[o * 3 + kk] == a &&
                        m.tri[o * 3 + (kk + 1) % 3] == b) {
                        same = true;
                        break;
                    }
                }
                if (same) {
                    FlipTriangle(m, o);
                    rep.flipped_triangles++;
                }
                seen[o] = 1;
                stack.push_back(o);
            }
        }
        /* Signed volume of this component about the origin; negative means the
         * component is inside-out as a whole. */
        double vol = 0;
        for (int t : comp) {
            const V3 &a = m.pos[m.tri[t * 3]];
            const V3 &b = m.pos[m.tri[t * 3 + 1]];
            const V3 &c = m.pos[m.tri[t * 3 + 2]];
            vol += Dot(a, Cross(b, c));
        }
        if (vol < 0) {
            for (int t : comp) {
                FlipTriangle(m, t);
                rep.flipped_triangles++;
            }
        }
    }
}

/* ====================================================================== */
/* Surface fitting                                                        */
/* ====================================================================== */

enum SurfKind {
    kNone = 0,
    kPlane,
    kCylinder,
    kCone,
    kSphere,
    kTorus,
    kFreeform,
    kFaceted
};

/* A fitted surface as parameters, before it becomes a Geom_Surface.
 *
 * q[] is the same parameter vector the refiner works on, laid out per kind:
 *   plane    nx ny nz d                (n unit, d = n.p)
 *   sphere   cx cy cz r
 *   cylinder px py pz ax ay az r       (p any point on the axis, a unit)
 *   cone     apex(3) axis(3) halfangle
 *   torus    cx cy cz ax ay az R r
 * Keeping one vector for all five is what lets one Gauss-Newton serve them. */
struct Fit
{
    SurfKind kind = kNone;
    double q[8] = {0, 0, 0, 0, 0, 0, 0, 0};
    double rms = 1e300;
    /* Mean |cos| between this surface's normals and the mesh's. Kept on the
     * fit because MergeRegions holds it to a far higher standard than the
     * first-pass classifier does — see kMergeNormalGate. */
    double agree = 0;
};

int ParamCount(SurfKind k)
{
    switch (k) {
    case kPlane:
        return 4;
    case kSphere:
        return 4;
    case kCylinder:
        return 7;
    case kCone:
        return 7;
    case kTorus:
        return 8;
    default:
        return 0;
    }
}

/* Signed distance from p to the surface described by q. Sign is meaningful
 * (outside positive for the closed kinds); only the magnitude is ever used. */
double SurfDist(SurfKind k, const double *q, const V3 &p)
{
    switch (k) {
    case kPlane: {
        return q[0] * p.x + q[1] * p.y + q[2] * p.z - q[3];
    }
    case kSphere: {
        const V3 v(p.x - q[0], p.y - q[1], p.z - q[2]);
        return Norm(v) - q[3];
    }
    case kCylinder: {
        const V3 v(p.x - q[0], p.y - q[1], p.z - q[2]);
        const V3 a(q[3], q[4], q[5]);
        const double u = Dot(v, a);
        return Norm(v - a * u) - q[6];
    }
    case kCone: {
        const V3 v(p.x - q[0], p.y - q[1], p.z - q[2]);
        const V3 a(q[3], q[4], q[5]);
        const double u = Dot(v, a);
        const double w = Norm(v - a * u);
        return w * std::cos(q[6]) - u * std::sin(q[6]);
    }
    case kTorus: {
        const V3 v(p.x - q[0], p.y - q[1], p.z - q[2]);
        const V3 a(q[3], q[4], q[5]);
        const double u = Dot(v, a);
        const double w = Norm(v - a * u);
        const double dr = w - q[6];
        return std::sqrt(dr * dr + u * u) - q[7];
    }
    default:
        return 0;
    }
}

/* Keeps the direction entries of q unit-length. Gauss-Newton walks them off
 * the sphere otherwise and the distance function stops meaning anything. */
void Renormalise(SurfKind k, double *q)
{
    if (k == kPlane) {
        const V3 n = Unit(V3(q[0], q[1], q[2]));
        q[0] = n.x;
        q[1] = n.y;
        q[2] = n.z;
    } else if (k == kCylinder || k == kCone || k == kTorus) {
        const V3 a = Unit(V3(q[3], q[4], q[5]));
        q[3] = a.x;
        q[4] = a.y;
        q[5] = a.z;
    }
}

/* What a fit reads off a set of triangles.
 *
 * TWO clouds, and the split is the hard-won part. `pts` are the patch's unique
 * VERTICES and carry the residual: they sit exactly on the original surface.
 * `spos`/`snrm` are oriented SAMPLES — each triangle contributes its three
 * corners, each tagged with that triangle's own normal — and every
 * direction-sensitive step reads those.
 *
 * Two wrong versions of this were written before the right one, and both
 * are worth keeping in view because both look reasonable:
 *
 *   per-VERTEX averaged normals. A vertex normal has to be blended from the
 *   triangles around it, and on a cylinder's rim those belong to the barrel AND
 *   to the cap. The blend points somewhere that exists on neither surface, and
 *   it is enough to convince the fitter that cap and barrel are one cylinder.
 *
 *   per-TRIANGLE centroids and normals. Uncontaminated, and degenerate exactly
 *   where it matters: a tessellated barrel is RULED, so every centroid lands at
 *   mid-height — the one height where a sphere through the two end rings has a
 *   radial normal too. A drilled hole came back a ball.
 *
 * Corner positions with the owning triangle's normal have neither problem. The
 * normal never blends, and the samples spread over the whole patch instead of
 * collapsing onto one iso-line. */
struct PatchData
{
    std::vector<V3> pts;        /* unique vertices, for the residual */
    std::vector<V3> spos, snrm; /* corner positions + owning triangle normal */
};

/* The surface normal at p, as the gradient of the distance function.
 *
 * Numerical rather than five hand-derived gradients, for the same reason the
 * refiner's Jacobian is: SurfDist is already the single definition of each
 * surface, and a normal from it cannot drift out of agreement with it. */
V3 SurfNormal(SurfKind k, const double *q, const V3 &p, double h)
{
    const V3 g(SurfDist(k, q, V3(p.x + h, p.y, p.z)) -
                   SurfDist(k, q, V3(p.x - h, p.y, p.z)),
               SurfDist(k, q, V3(p.x, p.y + h, p.z)) -
                   SurfDist(k, q, V3(p.x, p.y - h, p.z)),
               SurfDist(k, q, V3(p.x, p.y, p.z + h)) -
                   SurfDist(k, q, V3(p.x, p.y, p.z - h)));
    return Unit(g);
}

/* Mean |cos| between the fitted surface's normal and the mesh's own normal.
 *
 * WHY THIS EXISTS. Point distance alone does not identify a surface, and the
 * case that proves it is the common one: a tessellated cylinder barrel is a
 * RULED strip, so every vertex sits on one of the two end circles and nowhere
 * in between. Those two circles lie exactly on a sphere as well as on the
 * cylinder, so a points-only fit reports a perfect sphere and means it. The
 * normals are what tell them apart — a cylinder's point along the radius, the
 * sphere's tilt toward its centre — and checking them is the difference
 * between recognising a hole and inventing a ball. */
double NormalAgreement(SurfKind k, const double *q, const std::vector<V3> &spos,
                       const std::vector<V3> &snrm, double scale)
{
    if (spos.empty() || snrm.size() != spos.size())
        return 0;
    const double h = std::max(scale * 1e-5, 1e-9);
    double acc = 0;
    int n = 0;
    for (size_t i = 0; i < spos.size(); ++i) {
        const V3 sn = SurfNormal(k, q, spos[i], h);
        if (Norm(sn) < 0.5)
            continue; /* on an axis or at an apex */
        acc += std::fabs(Dot(sn, snrm[i]));
        n++;
    }
    return n > 0 ? acc / n : 0;
}

double FitRms(SurfKind k, const double *q, const std::vector<V3> &pts)
{
    if (pts.empty())
        return 1e300;
    double s = 0;
    for (const V3 &p : pts) {
        const double d = SurfDist(k, q, p);
        s += d * d;
    }
    return std::sqrt(s / pts.size());
}

/* Gauss-Newton with a numerical Jacobian and Levenberg damping.
 *
 * Numerical rather than analytic on purpose: five surface kinds times up to
 * eight parameters is forty derivatives to get right and to keep right, and
 * the fit runs once per patch, not per frame. The damping is what makes it
 * survive a bad seed, which on a downloaded mesh it will regularly get. */
/* Slides a cylinder's axis POINT to the middle of its own data.
 *
 * A cylinder has five degrees of freedom described by seven numbers, and one
 * of the two spare ones is where the point sits along the axis. Nothing about
 * the surface changes when it slides — but everything about the ARITHMETIC
 * does. A fitter that finds its axis point a hundred and forty millimetres up
 * the line from the eighteen millimetres of fillet it is describing has a
 * lever that long: turn the direction by half a thousandth of a radian, which
 * is what snapping it to the Y axis does, and the axis line moves nearly a
 * tenth of a millimetre where the data actually is. That is how three of the
 * four segments of the user's rounded edge lost their fit to a snap that was
 * supposed to be a rounding of the last decimal.
 *
 * Put the point where the surface is and the lever is gone. */
void RecentreAxis(SurfKind k, double *q, const std::vector<V3> &pts)
{
    if (k != kCylinder || pts.empty())
        return;
    const V3 ax = Unit(V3(q[3], q[4], q[5]));
    if (Norm(ax) < 0.5)
        return;
    V3 c;
    for (const V3 &p : pts)
        c += p;
    c = c * (1.0 / static_cast<double>(pts.size()));
    const double along = (c.x - q[0]) * ax.x + (c.y - q[1]) * ax.y +
                         (c.z - q[2]) * ax.z;
    q[0] += ax.x * along;
    q[1] += ax.y * along;
    q[2] += ax.z * along;
}

void RefineFit(SurfKind k, double *q, const std::vector<V3> &pts, double scale,
               const bool *freeMask = nullptr)
{
    const int n = ParamCount(k);
    if (n == 0 || pts.size() < static_cast<size_t>(n))
        return;
    RecentreAxis(k, q, pts);
    const double h = std::max(scale * 1e-6, 1e-12);
    double lambda = 1e-6;
    double best = FitRms(k, q, pts);
    std::vector<double> J(n);
    for (int iter = 0; iter < 24; ++iter) {
        double JtJ[64] = {0}, Jtr[8] = {0};
        for (const V3 &p : pts) {
            const double r = SurfDist(k, q, p);
            for (int i = 0; i < n; ++i) {
                if (freeMask && !freeMask[i]) {
                    J[i] = 0;
                    continue;
                }
                const double save = q[i];
                q[i] = save + h;
                const double rp = SurfDist(k, q, p);
                q[i] = save - h;
                const double rm = SurfDist(k, q, p);
                q[i] = save;
                J[i] = (rp - rm) / (2 * h);
            }
            for (int i = 0; i < n; ++i) {
                Jtr[i] -= J[i] * r;
                for (int j = 0; j < n; ++j)
                    JtJ[i * n + j] += J[i] * J[j];
            }
        }
        double A[64], b[8];
        std::memcpy(A, JtJ, sizeof(A));
        std::memcpy(b, Jtr, sizeof(b));
        for (int i = 0; i < n; ++i) {
            if (freeMask && !freeMask[i]) {
                A[i * n + i] = 1.0;
                continue;
            }
            A[i * n + i] *= (1.0 + lambda);
        }
        if (!SolveLin(A, b, n))
            break;
        double cand[8];
        std::memcpy(cand, q, sizeof(cand));
        for (int i = 0; i < n; ++i)
            cand[i] += b[i];
        Renormalise(k, cand);
        if (freeMask) {
            for (int i = 0; i < n; ++i)
                if (!freeMask[i])
                    cand[i] = q[i];
        }
        const double rms = FitRms(k, cand, pts);
        if (!(rms < best)) {
            lambda *= 8;
            if (lambda > 1e8)
                break;
            continue;
        }
        const double gain = best - rms;
        std::memcpy(q, cand, sizeof(cand));
        best = rms;
        lambda = std::max(lambda * 0.3, 1e-12);
        if (gain < scale * 1e-12)
            break;
    }
}

/* --- seeds ----------------------------------------------------------- */

void Centroid(const std::vector<V3> &pts, V3 &c)
{
    c = V3();
    for (const V3 &p : pts)
        c += p;
    if (!pts.empty())
        c = c * (1.0 / pts.size());
}

/* Covariance of pts about their centroid, row-major. */
void Covariance(const std::vector<V3> &pts, const V3 &c, double m[9])
{
    std::memset(m, 0, sizeof(double) * 9);
    for (const V3 &p : pts) {
        const V3 d = p - c;
        const double v[3] = {d.x, d.y, d.z};
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j)
                m[i * 3 + j] += v[i] * v[j];
    }
}

bool SeedPlane(const std::vector<V3> &pts, double *q)
{
    if (pts.size() < 3)
        return false;
    V3 c;
    Centroid(pts, c);
    double m[9], val[3], vec[9];
    Covariance(pts, c, m);
    Jacobi3(m, val, vec);
    const V3 n = Unit(V3(vec[0], vec[1], vec[2])); /* smallest eigenvalue */
    q[0] = n.x;
    q[1] = n.y;
    q[2] = n.z;
    q[3] = Dot(n, c);
    return true;
}

/* Algebraic sphere: |p|^2 = 2c.p + (r^2 - |c|^2), which is linear in
 * (cx, cy, cz, k). Good enough to start Gauss-Newton from. */
bool SeedSphere(const std::vector<V3> &pts, double *q)
{
    if (pts.size() < 4)
        return false;
    double A[16] = {0}, b[4] = {0};
    for (const V3 &p : pts) {
        const double row[4] = {2 * p.x, 2 * p.y, 2 * p.z, 1.0};
        const double rhs = p.x * p.x + p.y * p.y + p.z * p.z;
        for (int i = 0; i < 4; ++i) {
            b[i] += row[i] * rhs;
            for (int j = 0; j < 4; ++j)
                A[i * 4 + j] += row[i] * row[j];
        }
    }
    if (!SolveLin(A, b, 4))
        return false;
    const double r2 = b[3] + b[0] * b[0] + b[1] * b[1] + b[2] * b[2];
    if (!(r2 > 0))
        return false;
    q[0] = b[0];
    q[1] = b[1];
    q[2] = b[2];
    q[3] = std::sqrt(r2);
    return true;
}

/* A cylinder's normals are all perpendicular to its axis, so the axis is the
 * direction the normal cloud never points in: the smallest eigenvector of
 * sum(n n^T). With the axis known the rest is a 2D circle fit. */
bool SeedCylinder(const std::vector<V3> &pts, const std::vector<V3> &nrm,
                  double *q)
{
    if (pts.size() < 5 || nrm.size() != pts.size())
        return false;
    double m[9] = {0}, val[3], vec[9];
    for (const V3 &n : nrm) {
        const double v[3] = {n.x, n.y, n.z};
        for (int i = 0; i < 3; ++i)
            for (int j = 0; j < 3; ++j)
                m[i * 3 + j] += v[i] * v[j];
    }
    Jacobi3(m, val, vec);
    const V3 a = Unit(V3(vec[0], vec[1], vec[2]));
    /* Build an orthonormal frame across the axis and fit a circle in it. */
    V3 e1 = Cross(a, std::fabs(a.x) < 0.9 ? V3(1, 0, 0) : V3(0, 1, 0));
    e1 = Unit(e1);
    const V3 e2 = Cross(a, e1);
    V3 c;
    Centroid(pts, c);
    double A[9] = {0}, b[3] = {0};
    for (const V3 &p : pts) {
        const V3 d = p - c;
        const double x = Dot(d, e1), y = Dot(d, e2);
        const double row[3] = {2 * x, 2 * y, 1.0};
        const double rhs = x * x + y * y;
        for (int i = 0; i < 3; ++i) {
            b[i] += row[i] * rhs;
            for (int j = 0; j < 3; ++j)
                A[i * 3 + j] += row[i] * row[j];
        }
    }
    if (!SolveLin(A, b, 3))
        return false;
    const double r2 = b[2] + b[0] * b[0] + b[1] * b[1];
    if (!(r2 > 0))
        return false;
    const V3 axisPt = c + e1 * b[0] + e2 * b[1];
    q[0] = axisPt.x;
    q[1] = axisPt.y;
    q[2] = axisPt.z;
    q[3] = a.x;
    q[4] = a.y;
    q[5] = a.z;
    q[6] = std::sqrt(r2);
    return true;
}

/* A cone's normals all make the same angle with its axis, so they lie on a
 * PLANE when read as points on the unit sphere: that plane's normal is the
 * axis. The apex then falls out of a 2D fit in the plane across it. */
bool SeedCone(const std::vector<V3> &pts, const std::vector<V3> &nrm, double *q)
{
    if (pts.size() < 6 || nrm.size() != pts.size())
        return false;
    double pl[4];
    if (!SeedPlane(nrm, pl))
        return false;
    V3 a = Unit(V3(pl[0], pl[1], pl[2]));
    double sinA = pl[3];
    if (sinA < 0) {
        a = a * -1.0;
        sinA = -sinA;
    }
    if (!(sinA > 1e-3) || sinA > 0.999)
        return false; /* cylinder or plane */
    const double alpha = std::asin(std::min(1.0, sinA));

    /* Axis line: in the plane across `a` the projected normals point away from
     * the axis, so the axis point is the least-squares intersection of the
     * projected normal lines. Each line contributes (I - dd^T). */
    V3 e1 = Unit(Cross(a, std::fabs(a.x) < 0.9 ? V3(1, 0, 0) : V3(0, 1, 0)));
    const V3 e2 = Cross(a, e1);
    V3 c;
    Centroid(pts, c);
    double A[4] = {0}, b[2] = {0};
    for (size_t i = 0; i < pts.size(); ++i) {
        const V3 d = pts[i] - c;
        const double px = Dot(d, e1), py = Dot(d, e2);
        V3 np = nrm[i] - a * Dot(nrm[i], a);
        const double nn = Norm(np);
        if (nn < 1e-9)
            continue;
        np = np * (1.0 / nn);
        const double dx = Dot(np, e1), dy = Dot(np, e2);
        /* Distance from x to the line through (px,py) along (dx,dy): the
         * normal of that line is (-dy, dx). */
        const double lx = -dy, ly = dx;
        const double off = lx * px + ly * py;
        A[0] += lx * lx;
        A[1] += lx * ly;
        A[2] += ly * lx;
        A[3] += ly * ly;
        b[0] += lx * off;
        b[1] += ly * off;
    }
    if (!SolveLin(A, b, 2))
        return false;
    const V3 axisPt = c + e1 * b[0] + e2 * b[1];

    /* Apex: distance from the axis falls linearly to zero along it. */
    double su = 0, sw = 0, suu = 0, suw = 0;
    const int n = static_cast<int>(pts.size());
    for (const V3 &p : pts) {
        const V3 v = p - axisPt;
        const double u = Dot(v, a);
        const double w = Norm(v - a * u);
        su += u;
        sw += w;
        suu += u * u;
        suw += u * w;
    }
    const double den = n * suu - su * su;
    if (std::fabs(den) < 1e-18)
        return false;
    const double slope = (n * suw - su * sw) / den;
    const double inter = (sw - slope * su) / n;
    if (std::fabs(slope) < 1e-9)
        return false;
    const double uApex = -inter / slope;
    const V3 apex = axisPt + a * uApex;
    /* Point the axis from the apex INTO the material, so the half-angle is
     * positive and Geom_ConicalSurface gets a growing radius. */
    const V3 dir = slope > 0 ? a : a * -1.0;
    q[0] = apex.x;
    q[1] = apex.y;
    q[2] = apex.z;
    q[3] = dir.x;
    q[4] = dir.y;
    q[5] = dir.z;
    q[6] = alpha;
    return true;
}

/* Fits a circle to points already known to be near-coplanar, in that plane.
 *
 * Algebraic (Kasa) form: |x|^2 = 2 x.c + k, which is linear in (c, k). Exact
 * for points on a circle, and these are — they are tube centres. */
bool CircleInPlane(const std::vector<V3> &s, const V3 &a, V3 &centre,
                   double &radius)
{
    if (s.size() < 3)
        return false;
    V3 u = Cross(a, V3(0, 0, 1));
    if (Norm(u) < 1e-6)
        u = Cross(a, V3(1, 0, 0));
    u = Unit(u);
    const V3 v = Unit(Cross(a, u));
    V3 o;
    Centroid(s, o);
    double A[9] = {0}, b[3] = {0};
    for (const V3 &x : s) {
        const V3 d = x - o;
        const double du = Dot(d, u), dv = Dot(d, v);
        const double row[3] = {2 * du, 2 * dv, 1};
        const double rhs = du * du + dv * dv;
        for (int i = 0; i < 3; ++i) {
            b[i] += row[i] * rhs;
            for (int j = 0; j < 3; ++j)
                A[i * 3 + j] += row[i] * row[j];
        }
    }
    if (!SolveLin(A, b, 3))
        return false;
    const double rr = b[2] + b[0] * b[0] + b[1] * b[1];
    if (!(rr > 0))
        return false;
    radius = std::sqrt(rr);
    centre = o + u * b[0] + v * b[1];
    /* Put the centre in the plane the points lie in. */
    double off = 0;
    for (const V3 &x : s)
        off += Dot(x - centre, a);
    centre = centre + a * (off / static_cast<double>(s.size()));
    return true;
}

/* Fits a torus by searching for its MINOR radius.
 *
 * The old seed paired each point's normal with one a stride away and
 * intersected the two lines. On a cylinder or a cone that recovers the axis,
 * which is why it was written that way — but on a torus a normal line does not
 * meet the axis, it meets the SPINE, the circle of tube centres. Two normals a
 * step apart along a meridian meet on the spine; two a step apart around the
 * spine meet near the axis instead, a long way off. Averaging the two kinds
 * gave a torus of major radius 16.1 and minor 16.1-not-6 where the truth was
 * 20 and 6, at a residual of 4.6 mm on a mesh with no noise in it at all. A
 * plain torus was therefore never recognised once, at any tessellation, and a
 * fillet ring — which is the only torus most parts contain — came back as
 * several hundred planes.
 *
 * The structure that IS reliable: every point of a torus lies exactly its
 * minor radius from the spine, along its own normal. So for the true r, the
 * points p - r n collapse onto a circle, and for any other r they do not.
 * That makes r a one-dimensional search with a sharp, well-behaved minimum:
 * scan it, take the sign of n that works (outward on a boss, inward in a
 * blend), and read the axis, centre and major radius off the circle. */
bool SeedTorus(const std::vector<V3> &pts, const std::vector<V3> &nrm,
               double *q)
{
    const size_t n = pts.size();
    if (n < 12 || nrm.size() != n)
        return false;
    /* Bounded work per call: this runs inside the RANSAC trial loop. */
    std::vector<V3> p, d;
    const size_t stride = std::max<size_t>(1, n / 400);
    for (size_t i = 0; i < n; i += stride) {
        p.push_back(pts[i]);
        d.push_back(nrm[i]);
    }
    const size_t m = p.size();
    if (m < 12)
        return false;
    V3 c0;
    Centroid(p, c0);
    double ext = 0;
    for (const V3 &x : p)
        ext = std::max(ext, Norm(x - c0));
    if (!(ext > 0))
        return false;

    std::vector<V3> spine(m);
    double out[8];
    /* How far from a circle the tube centres fall for this minor radius. */
    auto residual = [&](double r, int sgn, double *keep) -> double {
        for (size_t i = 0; i < m; ++i)
            spine[i] = p[i] + d[i] * (sgn * r);
        double pl[4];
        if (!SeedPlane(spine, pl))
            return 1e300;
        const V3 a = Unit(V3(pl[0], pl[1], pl[2]));
        V3 c;
        double R = 0;
        if (!CircleInPlane(spine, a, c, R))
            return 1e300;
        if (!(R > r))
            return 1e300; /* r >= R is a self-intersecting torus, not a part */
        double ss = 0;
        for (const V3 &x : spine) {
            const V3 v = x - c;
            const double u = Dot(v, a);
            const double w = Norm(v - a * u) - R;
            ss += u * u + w * w;
        }
        if (keep) {
            keep[0] = c.x;
            keep[1] = c.y;
            keep[2] = c.z;
            keep[3] = a.x;
            keep[4] = a.y;
            keep[5] = a.z;
            keep[6] = R;
            keep[7] = r;
        }
        return std::sqrt(ss / static_cast<double>(m));
    };

    const double lo = ext * 0.004, hi = ext * 2.0;
    const int steps = 56;
    double bestR = -1, bestScore = 1e300;
    int bestSign = 1;
    for (int sgn = -1; sgn <= 1; sgn += 2) {
        for (int i = 0; i <= steps; ++i) {
            const double r =
                lo * std::pow(hi / lo, i / static_cast<double>(steps));
            const double sc = residual(r, sgn, nullptr);
            if (sc < bestScore) {
                bestScore = sc;
                bestR = r;
                bestSign = sgn;
            }
        }
    }
    if (!(bestR > 0) || bestScore > 1e299)
        return false;
    /* Golden-section down to a fraction of the step the scan used. */
    const double ratio = std::pow(hi / lo, 1.0 / steps);
    double a0 = bestR / ratio, b0 = bestR * ratio;
    const double gr = 0.6180339887498949;
    double x1 = b0 - gr * (b0 - a0), x2 = a0 + gr * (b0 - a0);
    double f1 = residual(x1, bestSign, nullptr);
    double f2 = residual(x2, bestSign, nullptr);
    for (int it = 0; it < 32 && b0 - a0 > bestR * 1e-6; ++it) {
        if (f1 < f2) {
            b0 = x2;
            x2 = x1;
            f2 = f1;
            x1 = b0 - gr * (b0 - a0);
            f1 = residual(x1, bestSign, nullptr);
        } else {
            a0 = x1;
            x1 = x2;
            f1 = f2;
            x2 = a0 + gr * (b0 - a0);
            f2 = residual(x2, bestSign, nullptr);
        }
    }
    const double rFinal = 0.5 * (a0 + b0);
    if (residual(rFinal, bestSign, out) > 1e299)
        return false;
    for (int i = 0; i < 8; ++i)
        q[i] = out[i];
    return true;
}

/* Tries all five and keeps the simplest one that fits inside `tol`.
 *
 * Order matters and is not by residual alone: a sphere will fit a shallow
 * cylindrical patch to within tolerance, and a torus will fit almost anything
 * given enough freedom. Preferring the earlier kind at equal quality is what
 * keeps a flat face a PLANE instead of a sphere of radius 10^6. */
#ifdef MESHRECON_TRACE
#define MR_TRACE(...) std::fprintf(stderr, __VA_ARGS__)
/* Wall-clock at each stage boundary, so a model that takes twenty seconds can
 * say which pass took them. */
static std::chrono::steady_clock::time_point mrPrev;
#define MR_STAGE(name)                                                        \
    do {                                                                      \
        static std::chrono::steady_clock::time_point mrLast;                  \
        const auto mrNow = std::chrono::steady_clock::now();                  \
        if (std::string(name) == "start")                                     \
            std::fprintf(stderr, "  [stage] --- start ---\n");                \
        else                                                                  \
            std::fprintf(                                                     \
                stderr, "  [stage] %-28s %8.1f ms\n", name,                   \
                std::chrono::duration<double, std::milli>(mrNow - mrPrev)      \
                    .count());                                                \
        (void)mrLast;                                                         \
        mrPrev = mrNow;                                                       \
    } while (0)
/* Compiled in only for the development harness; see backend/occt/tests. */
const char *KindName(SurfKind k)
{
    switch (k) {
    case kPlane:
        return "plane";
    case kSphere:
        return "sphere";
    case kCylinder:
        return "cyl";
    case kCone:
        return "cone";
    case kTorus:
        return "torus";
    case kFreeform:
        return "freeform";
    default:
        return "?";
    }
}
#else
#define MR_TRACE(...) ((void)0)
#define MR_STAGE(name) ((void)0)
#endif

/* Mean |cos| a candidate surface's normals must reach to be believed. About
 * 25 degrees of average slack: loose enough for a coarse download's estimated
 * vertex normals, tight enough that a sphere never passes for a cylinder. */
const double kMinNormalAgreement = 0.90;

/* How much better a later, more complex kind must agree with the mesh normals
 * before it displaces an earlier one that also fits. Level kinds keep the
 * simpler answer. */
const double kAgreeSlack = 0.004;

/* Agreement past which no later kind could win by more than the slack, so the
 * search can stop. */
const double kAgreeCertain = 0.9995;

/* Where in the sorted dihedrals of a patch to read "the sharpest edges in it".
 * A crease ring is a few per cent of a patch's internal edges. */
const double kCreaseQuantile = 0.98;

/* How many times the ordinary curvature step that ring must reach before it is
 * a crease and not just the tessellation. Below this the crease and the facet
 * angle are the same size and no dihedral test can separate them. */
const double kCreaseRatio = 2.0;

/* And an absolute floor, so a very finely tessellated smooth patch is never cut
 * at a two-degree "crease" that is really its own curvature. */
const double kMinCreaseAngle = 2.0 * M_PI / 180.0;

/* A patch with more creases than this is not a pair of surfaces, it is noise. */
const int kMaxCreaseDepth = 4;

/* How many times the splitter may hand its own leftover back to itself. Each
 * round is strictly smaller, so this only bounds the pathological case. */
const int kMaxSplitDepth = 6;

/* RANSAC budget. Bounded on purpose: this runs only on patches that fitted
 * nothing, and being thorough on a pathological patch at the cost of being
 * slow on every model is not a trade worth making. */
const int kRansacRounds = 32;   /* surfaces extracted per patch */
const int kRansacMinPatch = 10; /* below this, growing is fine */
const int kRansacMinSupport = 6;/* triangles a winner must explain */
const double kRansacNormalGate = 0.90;

/* HOW BIG a neighbourhood a candidate is fitted to — and the reason this is a
 * ladder rather than a number.
 *
 * A sample that straddles two surfaces fits neither, so it proposes nothing.
 * A fixed forty-triangle seed is therefore not "more evidence", it is a
 * commitment to features at least forty triangles wide: on a 60 mm plate whose
 * corner fillets are twelve facets each, every one of the forty-eight trials
 * on the side band drew a sample containing wall AND fillet, every fit failed,
 * and RANSAC returned nothing at all — measured, 56 triangles in, 0 surfaces
 * out. The fillets then went to triangles, which is what "the radiuses are not
 * radiuses" looks like from the outside.
 *
 * Classical RANSAC avoids this by sampling MINIMALLY — three points for a
 * plane — precisely so a sample cannot span a boundary. But a minimal sample
 * off a coarse mesh also fits a sphere the size of a house through any four
 * facets. So sample at several scales and let support decide: the small seeds
 * find the small features, the large seeds are stable on the large ones, and a
 * proposal that describes nothing real claims nothing and loses. */
const int kRansacSeedLadder[] = {4, 6, 10, 18, 30, 48};
const int kRansacLadderSteps =
    (int)(sizeof(kRansacSeedLadder) / sizeof(kRansacSeedLadder[0]));
const int kRansacTrialsPerSize = 12; /* candidates per rung, per round */

/* A residual this far below tolerance is not "within tolerance", it is the
 * surface the mesh was made from. */
const double kExactFitFraction = 0.02;

/* Below this an edge is not turning at all: the quad diagonals of a
 * quad-meshed surface sit at exactly zero and must never be averaged in. */
const double kBendFloorDeg = 0.5;

/* The band the feature angle is allowed to land in, and the sample it needs
 * before it is worth reading at all. Outside the band the histogram is saying
 * something the geometry does not support — a model with no features, or one
 * that is nothing but features — and the caller's own value stands. */
const double kFeatureAngleMinDeg = 12.0;
const double kFeatureAngleMaxDeg = 55.0;
const int kFeatureAngleMinEdges = 24;

/* What makes the split believable: each side of it must hold at least a
 * twelfth of the bending edges, and the gap between them must be this many
 * degrees wide. */
const double kFeatureModeFraction = 12.0;
const int kFeatureGapBins = 6; /* degrees of empty histogram that make a gap */

/* How much slack a second sewing pass gets when the first leaves a hybrid
 * shell open. Bounded: past this the "seam" being closed is a real gap. */
const double kSewRetryFactor = 5.0;

/* When a facet's own normal stops being evidence and becomes rounding noise.
 *
 * A triangle only reports a surface direction if it has a shape. Take one
 * whose three vertices are nearly collinear: the odd vertex sits h off the
 * line through the other two, and moving it by e tips the normal by about
 * e/h. Once h is a small fraction of the facet's own length, the normal says
 * more about where the tessellator rounded that vertex than about the part.
 *
 * Meshers emit these constantly — a cap where one fillet crosses another, a
 * needle along a trimmed boundary — and nearly all of them are harmless,
 * because they sit INSIDE a smooth run and the run's fit outvotes them. The
 * one that is not harmless is the sliver whose noisy normal happens to differ
 * from all three neighbours by more than the feature angle: that makes it a
 * smooth run of ONE triangle, which is a face of its own, and it cuts the
 * surface it lies on into two pieces that nothing downstream puts back
 * together. On the user's bracket exactly one triangle does this, and it costs
 * two visible defects at once — a 0.13 mm shard standing proud between the
 * boss blend and the top-edge fillet, and that fillet arriving as two
 * cylinders that overlap each other by 1.9 mm across the shard.
 *
 * A fortieth is deliberately deep into degenerate territory. Thin facets that
 * mean something are common (a chamfer tessellated in one row is 1:10 and its
 * normal is exact); 1:25 and worse is a tessellator artefact. */
const double kSliverAspect = 0.04; /* height on the longest edge, over it */

/* ---- Ties decide the model -------------------------------------------
 *
 * Every ordering in this file must be a TOTAL order, and the reason is not
 * tidiness.
 *
 * std::sort is not stable, and where a comparator says two elements are
 * equal the order it leaves them in is the standard library's business.
 * libstdc++ and libc++ do not agree — and this converter is compiled against
 * libstdc++ for the development harness and libc++ for the device. A
 * tessellated part is FULL of exact ties: a twelve-sided hole is twenty-four
 * triangles of identical area and identical bend, and the order they are
 * sorted into is the order the splitter seeds from. Different seeds, different
 * patches, different part.
 *
 * Measured on the user's part, same 1138 triangles, same code: the harness
 * came back 20 planes, 18 cylinders, 1 faceted patch and 50 faces; the iPad
 * came back 19, 17, 2 and 47 — the centre hole a polygon on one and a cylinder
 * on the other. Every number this file has ever been tuned against was
 * measured on a segmentation the user was not getting.
 *
 * So: no comparator may return false both ways for two different elements.
 * Break the tie on something intrinsic — the triangle's index, the patch's
 * index, the order the wire was built in — never on where the element happens
 * to sit in a hash table.
 * ---------------------------------------------------------------------- */

/* Fewer triangles than this and the fit has no sample to speak of. */
const int kMinTrustTriangles = 6;

/* How much of the tolerance a surface may use up and still be believed to be
 * THE surface rather than one that happens to pass nearby. */
const double kTrustRmsFraction = 0.15;

/* How far off a facet's interior a fitted surface may bow, as a fraction of
 * that facet's own size. A surface the mesh was tessellated from bows by the
 * chord height, which is quadratic in facet size and therefore small: measured
 * on a 12-segment cylinder, under a hundredth of the facet. A quarter of the
 * facet is not a tessellation of anything. */
const double kCentroidFacetFraction = 0.25;

/* When a smooth run is judged freeform rather than prismatic: it has to be big
 * enough for the judgement to mean anything, less than half of it accounted
 * for by surfaces, and those surfaces facet-sized. */
const int kFreeformMinRun = 60;
const int kFreeformPieceTriangles = 8;
const int kFreeformCoverDenom = 8; /* under an eighth explained: freeform */

/* How small a fitted patch must be, as a fraction of the model's surface,
 * before being alone among triangles is reason enough to become triangles. */
const double kScrapAreaFraction = 0.002;

/* The precision a tessellated model's own vertices hold, as a fraction of its
 * size: float32 gives about a tenth of this, so it is a bar with headroom and
 * still four hundred times tighter than a typical tolerance. */
const double kMeshPrecisionFrac = 1.0e-6;

/* How far round its own surface a patch must reach before the radius it
 * fitted means anything. Twenty-five degrees of arc; below that a wide range
 * of radii pass through the same points within tolerance. */
const double kMinSweepRad = 25.0 * M_PI / 180.0;

/* The same question of a patch with no witness but the fit itself: see the
 * "shallow" test in Identifiable. Every real feature on a drawn part sweeps a
 * quarter turn or more — a fillet, a hole, a blend ring — so this costs
 * nothing that exists. */
const double kMinSweepFragmentRad = 45.0 * M_PI / 180.0;

/* How big a patch may be and still be dissolved into its neighbours when it
 * explains nothing. A handful of facets in the seam between two features is
 * what this is for; a large region that fits nothing is a real freeform region
 * and belongs in the faceted shell whole. */
const int kDissolveMaxTriangles = 16;

/* How many facet steps of normal disagreement a fit may have and still be
 * describing THIS surface. Half a step is what a perfect fit costs on a
 * tessellation; four times that is something else. */
const double kAgreeFacetFactor = 2.0;

/* ...and a floor, so an exactly-tessellated flat face is not held to zero. */
const double kAgreeFloorRad = 4.0 * M_PI / 180.0;

/* How much of a patch may disagree with its own surface before the surface is
 * the thing in doubt rather than the strays. A third is generous: the case
 * this exists for is ten facets in seventy-three. */
const double kTrimKeepFraction = 0.5;

/* How far past the middle of the pack a triangle has to be before the surface
 * disowns it, and how many times to drop and refit. The strays bias the very
 * fit that finds them, so one pass is not enough; six is far more than any
 * measured case has needed. */
const double kTrimDistFactor = 3.0;
const int kTrimRounds = 6;

/* How much more of a periodic surface a face may cover than its own triangles
 * do before it is the wrong side of its own boundary. A correct face exceeds
 * the mesh by a facet; a face on the wrong side exceeds it several times
 * over. */
const double kUvSpanSlack = 1.5;


/* Freeform surfacing — see FreeformSurfaces.
 *
 * REGION SIZE sets how many faces the model comes back as, and the whale is
 * the measurement: at 600 triangles a region it becomes 128 surfaces whose
 * median distance from the mesh is 0.148 against a tolerance of 0.408, and
 * two regions that no plane is a graph over. Coarser costs accuracy — at
 * 1300 a region, 64 surfaces, eleven of them miss tolerance — and finer buys
 * little: 256 surfaces only take the median to 0.104, for twice the faces.
 *
 * THE GRID BAR is what a region has to prove before a surface is built on it.
 * It is measured against the resampled grid rather than the finished surface
 * because that costs a multiply per vertex where projecting onto a B-spline
 * costs milliseconds — 12 s against 0.02 for the whale's 128 regions. Seven
 * tenths, not one: the approximator is asked for a quarter of tolerance on
 * top and does not always deliver it, and a region measured at 0.34 came back
 * as a surface 0.51 out.
 *
 * ROUNDS is where the partition stops moving; the whale's distortion is flat
 * from about eight. */
const int kFreeformRegionTriangles = 600;
const int kFreeformMinRegion = 24;
const int kFreeformMaxRegions = 400;
const int kFreeformRounds = 12;
const int kFreeformSplitDepth = 9;
const int kFreeformMergePasses = 12;
const int kFreeformCheckSamples = 48;
const int kFreeformMaxRegionTriangles = 20000;
const int kFreeformGridMax = 32;
const double kFreeformGridBar = 0.7;
const double kFreeformApproxFraction = 0.25;
/* Fairing weight for the least-squares control net, scaled by the point count
 * so it means the same on a region of two hundred vertices and one of twenty
 * thousand. The ridge is smaller again and exists only so the Cholesky cannot
 * meet a zero on a net row no vertex reaches. */
const double kFreeformFairing = 2.0e-7;
const double kFreeformRidge = 1.0e-9;
/* Triangles sampled when asking how far the surface goes BETWEEN the data. */
const int kFreeformBetweenSamples = 2000;
/* How far the finished solid may stand from the volume of the mesh it was
 * made from before it stops being that part.
 *
 * Every conversion that works lands inside a couple of per cent: the whale
 * -0.92%, the TOKA boss +0.18%, the broomholder +1.67%, the butterfly
 * bookmark +0.17% once its tolerance fits. The one that does not work is not
 * close: the same bookmark converted with a tolerance wider than the webs
 * between its cut-outs came back +171.84%, having grown all 37 of them shut.
 * A quarter is far above everything that passes and far below the only thing
 * that fails, which is what a threshold wants to be. */
const double kVolumeDivergenceBar = 0.25;
/* How far past its own data the net reaches, as a fraction of the parameter
 * range. The face is trimmed by the region's boundary, so the surface has to
 * exist a little way OUTSIDE it or the boundary has nowhere to project and
 * the wire cannot be built. The raster this replaces got the same margin for
 * free — badly, from cells the region never reached — and the fairing term
 * now supplies it properly, by continuing the surface rather than inventing
 * heights for it. */
const double kFreeformNetMargin = 0.06;

/* Above this many faces, sewing is not a fallback, it is a hang.
 *
 * BRepBuilderAPI_Sewing rediscovers by geometric search the adjacency this
 * file already computed exactly, and it costs more than linearly in the faces
 * it is handed. Measured on the user's whale — 83,178 triangles of organic
 * shell — plain triangle faces sew in 3.4 s at ten thousand, 7.9 at twenty
 * thousand, 22.8 at forty; at the model's OWN tolerance the same twenty
 * thousand take 25.4 s, and the real 82,683 never finished at all.
 *
 * The tolerance is why. It is a fraction of the bounding-box diagonal, which
 * is the right way to ask whether two SURFACES describe the same thing and
 * the wrong way to ask whether two edges are the same edge: on that model it
 * is 0.408 against a median mesh edge of 0.73, so a quarter of all edges are
 * shorter than the tolerance and every one of them has several candidate
 * partners.
 *
 * A face count this high means the result is one face per triangle, and those
 * already share their edges — BuildFaceted makes them that way. What sewing
 * could add is the handful of seams where a fitted face meets them, and
 * minutes for a handful of seams is not a trade worth making when the faceted
 * build below closes the model outright. */
const int kMaxSewFaces = 20000;

/* When the fitted result stopped being a READING of the shape.
 *
 * The fitted pass earns an open shell by being light: on the curved shell in
 * the test suite it finds four drilled holes and turns the rest to triangles —
 * nine faces for 2,674 triangles — and replacing that to gain a solid would
 * throw the holes away. On the user's whale it finds seven faces and 82,676
 * triangles, which is not a reading of a whale; it is the faceted build with
 * seven seams in it that stop the shell closing.
 *
 * So measure it: what fraction of the mesh the fitted pass left as triangles.
 * 78% on the curved shell, 99.4% on the whale. Past this share there is
 * nothing to protect — the faceted build is no heavier than what the fitted
 * pass already produced, and it closes. */
const int kFittedIsFacetedPercent = 95;

/* M333 — how much of a shape must be carried by FITTED surfaces before the
 * result counts as a reading of it rather than an attempt at one.
 *
 * Two thirds, which every organic fixture clears by a wide margin (the
 * ellipsoids sit at 99.8-100% and the fused pair at 98.4%) and which nothing
 * that fell apart could. It is a floor, not a threshold to tune. */
const int kFittedIsReadingPercent = 66;

/* Above this the faceted fallback is not a rescue, it is a freeze.
 *
 * Measured at 90 to 140 microseconds a triangle — a tenth of what it cost
 * before the shell was built directly, but still a hundred times the fitted
 * path — and an iPad is a few times slower than the machine it was measured
 * on. Thirty thousand triangles is then of the order of ten seconds with a
 * notice on screen, which is a long wait for an import and a short one for a
 * mistake. Past it the fitted result is kept however poor: a model that is
 * visibly wrong beats an app that is visibly dead, and its faces are at least
 * bounded now. */
const int kMaxAutoFacetedTriangles = 30000;

/* Fewer triangles per patch than this and the fit did not read the model, it
 * came apart on it. A recognised part runs to tens or hundreds of triangles a
 * face; the download that exposed this managed six. */
const int kShatterTrianglesPerPatch = 10;

/* And the ratio says nothing on a small mesh: a cube with one face missing is
 * five patches for ten triangles and exactly right. */
const int kShatterFloorTriangles = 200;

/* Largest fitted radius worth believing, as a multiple of the part's own
 * bounding-box diagonal. */
const double kMaxRadiusFactor = 4.0;

/* How much of a surface a sample actually goes ROUND, in radians.
 *
 * A radius is only knowable from a sample that turns far enough about it.
 * Twenty degrees of a cylinder is an arc that a thousand different radii pass
 * through within tolerance, and the one a fitter picks off it is noise. The
 * same is true of a sphere's cap and of a torus's spine. A plane has no radius
 * to pin down, so it is always fully covered. */
double SurfaceCoverage(SurfKind k, const double *q, const std::vector<V3> &pts)
{
    if (k == kPlane)
        return 2.0 * M_PI;
    if (pts.size() < 3)
        return 0;
    if (k == kSphere) {
        const V3 c(q[0], q[1], q[2]);
        V3 mean;
        for (const V3 &x : pts)
            mean += Unit(x - c);
        if (Norm(mean) < 1e-12)
            return 2.0 * M_PI; /* points all round it: a whole sphere */
        mean = Unit(mean);
        /* The RANGE of colatitude, not its maximum.
         *
         * On a genuine cap the mean direction is inside it, so the range runs
         * from zero and the two are the same number. On a thin RING they are
         * not: the mean points at the pole the ring encircles, every point is
         * the same distance from it, and a cap-angle test reads the ring's
         * latitude — wide — where its actual extent is a few degrees. That
         * matters because one row of a surface of revolution lies EXACTLY on
         * a sphere centred on its axis: a boss's fillet ring came back as a
         * stack of concentric spherical bands, each with a residual of zero,
         * because nothing asked whether the sample had any width. */
        double lo = M_PI, hi = 0;
        for (const V3 &x : pts) {
            const double t =
                std::acos(std::max(-1.0, std::min(1.0, Dot(Unit(x - c), mean))));
            lo = std::min(lo, t);
            hi = std::max(hi, t);
        }
        return (hi - lo) * 2.0;
    }
    /* Cylinder, cone and torus all turn about an axis. */
    const V3 c(q[0], q[1], q[2]);
    const V3 ax = Unit(V3(q[3], q[4], q[5]));
    if (!(Norm(ax) > 0.5))
        return 0;
    V3 u = Cross(ax, V3(0, 0, 1));
    if (Norm(u) < 1e-6)
        u = Cross(ax, V3(1, 0, 0));
    u = Unit(u);
    const V3 v = Unit(Cross(ax, u));
    std::vector<double> ang;
    ang.reserve(pts.size());
    for (const V3 &x : pts) {
        const V3 d = (x - c) - ax * Dot(x - c, ax);
        if (Norm(d) < 1e-12)
            continue;
        ang.push_back(std::atan2(Dot(d, v), Dot(d, u)));
    }
    if (ang.size() < 3)
        return 0;
    std::sort(ang.begin(), ang.end());
    /* The sweep is a full turn minus the widest gap between samples. */
    double gap = ang.front() + 2.0 * M_PI - ang.back();
    for (size_t i = 1; i < ang.size(); ++i)
        gap = std::max(gap, ang[i] - ang[i - 1]);
    return 2.0 * M_PI - gap;
}

Fit FitPatch(const PatchData &d, double tol, double scale)
{
    const std::vector<V3> &pts = d.pts;
    Fit best;
    Fit chosen;
    bool have = false;
    bool chosenPinned = false;
    bool chosenExact = false;
    const SurfKind order[5] = {kPlane, kSphere, kCylinder, kCone, kTorus};
    for (int i = 0; i < 5; ++i) {
        const SurfKind k = order[i];
        double q[8] = {0};
        bool ok = false;
        switch (k) {
        case kPlane:
            ok = SeedPlane(pts, q);
            break;
        case kSphere:
            ok = SeedSphere(pts, q);
            break;
        case kCylinder:
            ok = SeedCylinder(d.spos, d.snrm, q);
            break;
        case kCone:
            ok = SeedCone(d.spos, d.snrm, q);
            break;
        case kTorus:
            ok = SeedTorus(d.spos, d.snrm, q);
            break;
        default:
            break;
        }
        if (!ok)
            continue;
        Renormalise(k, q);
        RefineFit(k, q, pts, scale);
        const double rms = FitRms(k, q, pts);
#ifdef MESHRECON_TRACE
        std::fprintf(
            stderr,
            "      %-6s rms=%.6f tol=%.6f nrm=%.3f n=%d  "
            "q=[%.3f %.3f %.3f %.3f %.3f %.3f %.4f %.4f]\n",
            KindName(k), rms, tol, NormalAgreement(k, q, d.spos, d.snrm, scale),
            (int)pts.size(), q[0], q[1], q[2], q[3], q[4], q[5], q[6], q[7]);
#endif
        if (!(rms < 1e299))
            continue;
        /* Reject degenerate radii outright: a "cylinder" of radius 10^6 across
         * a 20 mm part is a plane that fitted by accident, and it would build
         * a surface no downstream operation can use. */
        /* A radius many times the whole part is not a feature of it. Such a
         * fit is a plane that curved slightly by accident — and `plane` was
         * tried first and already declined, so there is nothing to lose by
         * refusing it and letting the patch be split further. */
        const double rMax = scale * kMaxRadiusFactor;
        if ((k == kCylinder && q[6] > rMax) || (k == kSphere && q[3] > rMax) ||
            (k == kTorus && (q[6] > rMax || q[7] > rMax))) {
            continue;
        }
        /* And a radius BELOW tolerance is not a feature either: the mesh
         * cannot hold a curve finer than the tolerance it is being read at,
         * so such a fit is a sliver, not a surface. On the user's part six
         * "cylinders" of radius 0.01 mm came out of the slivers where the
         * small holes meet a step — each one a face of area 0.06 mm², and
         * between them twenty-four open edges that stopped the shell being a
         * solid. */
        if ((k == kCylinder && q[6] < tol) || (k == kSphere && q[3] < tol) ||
            (k == kTorus && q[7] < tol)) {
            continue;
        }
        /* A torus whose tube is nearly as wide as the ring it follows has no
         * ring left: its inner circle closes up, the surface touches itself on
         * the axis, and whatever face is built on it is not the shape the
         * triangles came from. R=5.19 against r=4.86 appeared on the user's
         * part and took seventeen percent off its volume. */
        if (k == kTorus && q[6] < q[7] + tol)
            continue;
        /* A surface that passes through the points but faces the wrong way is
         * not the surface those points came off. See NormalAgreement. */
        const double agree = NormalAgreement(k, q, d.spos, d.snrm, scale);
        if (agree < kMinNormalAgreement)
            continue;
        if (rms <= tol) {
            /* Which of the kinds that PASS through the points is the surface
             * these points came off. Three questions, in order.
             *
             * CAN THIS SAMPLE PIN IT DOWN? Twenty degrees of a cylinder is an
             * arc a thousand radii pass through within tolerance. Six
             * triangles off a coarse corner fillet fit a sphere marginally
             * better than the cylinder they came from — the normals barely
             * separate them — but they go ninety degrees round the cylinder
             * and a few round the sphere. Only one of the two is knowable from
             * this sample, and taking the other sent the fillet to triangles.
             *
             * IS IT EXACT? A tessellation puts its vertices ON the surface
             * they came from, so this is not a matter of degree: it separates
             * the surface the part was built from one that merely passes near.
             * Two rows of a boss's fillet ring were fitted by a sphere at
             * 0.0377, a cone at 0.0350 and a torus at 0.0000030 — the true
             * R=10.5, r=1.5, to seven figures — while their normal agreements
             * were 0.985, 0.987 and 0.987. At three decimals the normals
             * cannot tell them apart; the residual does, by twelve thousand.
             * (On a noisy mesh nothing is exact, every candidate lands in the
             * same tier, and this question simply does not arise.)
             *
             * DOES IT POINT THE WAY THE MESH DOES, and is the simpler kind
             * level with it? A plane fits three columns of a tessellated
             * cylinder to well inside tolerance and so does a sphere the size
             * of a house; the residual cannot tell those apart but the normals
             * can, by a wide margin — 0.94 against 0.999 on that strip. The
             * slack keeps a genuinely flat face a PLANE rather than a sphere
             * of radius ten thousand. */
            const bool pinned = SurfaceCoverage(k, q, pts) >= kMinSweepRad;
            const bool exact = rms <= tol * kExactFitFraction;
            const bool better =
                !have || (pinned && !chosenPinned) ||
                (pinned == chosenPinned && exact && !chosenExact) ||
                (pinned == chosenPinned && exact == chosenExact &&
                 agree > chosen.agree + kAgreeSlack);
            if (better) {
                chosen.kind = k;
                std::memcpy(chosen.q, q, sizeof(q));
                chosen.rms = rms;
                chosen.agree = agree;
                chosenPinned = pinned;
                chosenExact = exact;
                have = true;
            }
            /* Nothing later can beat this by more than the slack, so stop —
             * which is the common case (a flat face, first kind tried). */
            if (chosenPinned && chosenExact && chosen.agree >= kAgreeCertain)
                return chosen;
            continue;
        }
        if (rms < best.rms) {
            best.kind = k;
            std::memcpy(best.q, q, sizeof(q));
            best.rms = rms;
            best.agree = agree;
        }
    }
    if (have)
        return chosen;
    if (best.rms > tol)
        best.kind = kNone; /* nothing fitted; caller decides */
    return best;
}

/* ====================================================================== */
/* Segmentation                                                           */
/* ====================================================================== */

struct Patch
{
    std::vector<int> tris;
    Fit fit;
    /* Which smooth patch this came out of. MergeRegions will only put two
     * patches back together if they started as one, which is what keeps a
     * merge from ever crossing a sharp edge. */
    int origin = -1;
    /* How many triangles stand behind this surface, counting the other
     * patches that Consolidate found to be pieces of the SAME one. A five-
     * facet scrap of a fillet is not slender evidence when thirty-six facets
     * along the same edge measured the same cylinder. 0 means "just my own". */
    int evidence = 0;
    /* A surface that failed the verdict ONLY for being too small a sample,
     * kept aside while the dissolve decides whether the neighbours want the
     * triangles. See DissolveUnexplained's closing pass. */
    Fit shelved;
    /* A fitted B-spline, for a patch that is kFreeform. The analytic kinds
     * are eight numbers and are carried in Fit; this one is a surface and
     * cannot be, so it rides here and MakeSurface never sees it. */
    Handle(Geom_Surface) freeSurf;
};

void PatchPoints(const Mesh &m, const std::vector<int> &tris, PatchData &d,
                 int cap)
{
    d.pts.clear();
    d.spos.clear();
    d.snrm.clear();
    std::unordered_map<int, char> seen;
    seen.reserve(tris.size() * 2);
    /* Fitting a million points buys no accuracy over fitting four thousand of
     * them, and costs a second per patch. Stride, do not truncate: the first
     * four thousand triangles of a patch are one corner of it. */
    const size_t step = (cap > 0 && tris.size() > static_cast<size_t>(cap))
                            ? tris.size() / cap + 1
                            : 1;
    d.spos.reserve(tris.size() / step * 3 + 3);
    d.snrm.reserve(tris.size() / step * 3 + 3);
    for (size_t i = 0; i < tris.size(); i += step) {
        const int t = tris[i];
        for (int k = 0; k < 3; ++k) {
            const int v = m.tri[t * 3 + k];
            d.spos.push_back(m.pos[v]);
            d.snrm.push_back(m.tnorm[t]);
            if (seen.emplace(v, 1).second)
                d.pts.push_back(m.pos[v]);
        }
    }
}

/* At what angle an edge stops being TESSELLATION and becomes a FEATURE — read
 * off this mesh, not fixed in advance.
 *
 * A fixed bar cannot work, because the two things it separates live at
 * different angles in different files. The user's part is a 20x50 plate from
 * Shapr3D: its fillets are tessellated in so few rows that consecutive facets
 * turn by 22 to 30 degrees, while its real edges turn by 80 to 100. At the
 * shipped 22 degrees, 252 of those tessellation steps counted as features and
 * the model arrived at the fitter as 149 smooth runs — most of them a single
 * facet — where the part has about twenty faces. Nothing downstream recovers
 * from that: a face carved out of one facet fits its own plane exactly, and
 * 124 of them were kept.
 *
 * The mesh says where the line is. A tessellated CAD model has a bimodal
 * histogram — a dense cluster of small steps from tessellating smooth
 * surfaces, a second cluster at the corners — and the answer is the valley
 * between them. Otsu's threshold (maximum between-class variance) finds it
 * without assuming where it is: on that plate it lands at 42.5 degrees, and
 * the count of sharp edges is flat at 385-387 anywhere from 30 to 50, which
 * is what a real valley looks like.
 *
 * Biased high on purpose. Under-segmentation is recoverable — a patch holding
 * two surfaces is exactly what SplitPatch, the crease cut and RANSAC are for —
 * and over-segmentation is not. */
double FeatureAngleDeg(const Mesh &m, double fallback)
{
    std::vector<int> hist(180, 0);
    int nb = 0;
    const int nt = m.triCount();
    for (int t = 0; t < nt; ++t) {
        for (int k = 0; k < 3; ++k) {
            const int o = m.adj[t * 3 + k];
            if (o < 0 || o < t)
                continue;
            const double c =
                std::max(-1.0, std::min(1.0, Dot(m.tnorm[t], m.tnorm[o])));
            const double deg = std::acos(c) * 180.0 / M_PI;
            /* The quad diagonals of a quad-meshed surface sit at exactly zero
             * and say nothing about where the line is. */
            if (deg <= kBendFloorDeg)
                continue;
            hist[std::min(179, static_cast<int>(deg))]++;
            nb++;
        }
    }
    if (nb < kFeatureAngleMinEdges)
        return fallback;

    /* Walk UP from the middle of the tessellation until the histogram opens.
     *
     * Otsu's threshold was the obvious tool and it is the wrong one, because
     * the histogram often has three clusters rather than two: on a plate with
     * large corner fillets there is a mode where the fillet leaves the wall
     * tangentially, a second at the fillet's own facet steps, and a third at
     * the ninety-degree edges. Otsu maximises between-class variance, lands in
     * the FIRST valley at 21 degrees, and cuts the fillet along its own
     * tessellation — precisely the failure this exists to prevent.
     *
     * Walking down from the sharpest edge is wrong the other way: it clears
     * every tessellation cluster but also every OBLIQUE feature, and on the
     * user's part that put the line at 57 degrees, swallowing eighteen real
     * edges between 45 and 56.
     *
     * The median bending angle is inside the tessellation by construction —
     * that is what most edges are on a tessellated model — so start there and
     * take the first real gap above it. Below the gap is how finely this mesh
     * was cut up; above it is the part. */
    int med = 0;
    {
        int seen = 0;
        for (int i = 0; i < 180; ++i) {
            seen += hist[i];
            if (seen * 2 >= nb) {
                med = i;
                break;
            }
        }
    }
    int at = -1, run = 0;
    for (int i = med + 1; i < 180; ++i) {
        if (hist[i] == 0) {
            if (++run == 1)
                at = i;
            if (run >= kFeatureGapBins)
                break;
        } else {
            run = 0;
            at = -1;
        }
    }
    /* No gap above the median: the mesh is nothing but tessellation (an
     * organic shell) or nothing but features (a low-poly design). Neither
     * wants a computed angle, and the caller's own value stands. */
    if (at < 0 || run < kFeatureGapBins)
        return fallback;
    double above = 0;
    for (int i = at; i < 180; ++i)
        above += hist[i];
    const double below = nb - above;
    if (std::min(above, below) * kFeatureModeFraction < nb)
        return fallback;

    return std::max(kFeatureAngleMinDeg,
                    std::min(kFeatureAngleMaxDeg, at + 0.0));
}

/* The triangle's height on its longest edge, over that edge — 0.87 for an
 * equilateral one, 0 for three collinear points. See kSliverAspect. */
double FacetAspect(const Mesh &m, int t)
{
    double lmax = 0;
    for (int k = 0; k < 3; ++k) {
        const V3 &a = m.pos[m.tri[t * 3 + k]];
        const V3 &b = m.pos[m.tri[t * 3 + (k + 1) % 3]];
        lmax = std::max(lmax, Norm(b - a));
    }
    if (lmax <= 0)
        return 0;
    return 2.0 * m.tarea[t] / (lmax * lmax);
}

/* Which of t's three edges is the longest. Ties go to the lowest index, so
 * this is a total order — see "Ties decide the model". */
int LongestEdge(const Mesh &m, int t)
{
    int best = 0;
    double blen = -1;
    for (int k = 0; k < 3; ++k) {
        const V3 &a = m.pos[m.tri[t * 3 + k]];
        const V3 &b = m.pos[m.tri[t * 3 + (k + 1) % 3]];
        const double l = Norm(b - a);
        if (l > blen) {
            blen = l;
            best = k;
        }
    }
    return best;
}

/* Groups triangles into patches bounded by sharp edges — the cheap, correct
 * first cut. A model that came from CAD (which is most of what gets
 * downloaded) is already almost segmented this way: a cylinder's barrel is one
 * smooth run bounded by the sharp circles at its ends. */
void SmoothPatches(const Mesh &m, double sharpDeg, std::vector<int> &patchOf,
                   int &patchCount)
{
    const double cosSharp = std::cos(sharpDeg * M_PI / 180.0);
    const int nt = m.triCount();
    patchOf.assign(nt, -1);
    patchCount = 0;
    std::vector<int> stack;
    for (int seed = 0; seed < nt; ++seed) {
        if (patchOf[seed] >= 0)
            continue;
        const int id = patchCount++;
        stack.clear();
        stack.push_back(seed);
        patchOf[seed] = id;
        while (!stack.empty()) {
            const int t = stack.back();
            stack.pop_back();
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0 || patchOf[o] >= 0)
                    continue;
                if (Dot(m.tnorm[t], m.tnorm[o]) < cosSharp)
                    continue;
                patchOf[o] = id;
                stack.push_back(o);
            }
        }
    }

    /* A run of ONE sliver is not a face, it is a tessellation artefact.
     *
     * Its normal is noise (kSliverAspect), so the sharp edges that isolated it
     * are noise too, and leaving it alone leaves a shard AND a surface cut in
     * two. Give it to the neighbour across its LONGEST edge: a sliver's long
     * edges run ALONG the surface it belongs to and its short one is the
     * degenerate direction, so the long edge is the most surface it shares
     * with anybody.
     *
     * Only lone runs. A sliver with a smooth neighbour is already inside a run
     * and needs nothing; and a sliver lying exactly along a real CAD edge —
     * meshers put them there too — keeps that edge, because it can only ever
     * be handed to one side of it, never bridge across. */
    std::vector<int> runSize(patchCount, 0);
    for (int t = 0; t < nt; ++t)
        runSize[patchOf[t]]++;
    std::vector<int> uf(patchCount);
    for (int i = 0; i < patchCount; ++i)
        uf[i] = i;
    auto find = [&uf](int a) {
        while (uf[a] != a)
            a = uf[a] = uf[uf[a]];
        return a;
    };
    int folded = 0;
    for (int t = 0; t < nt; ++t) {
        if (runSize[patchOf[t]] != 1)
            continue;
        if (FacetAspect(m, t) >= kSliverAspect)
            continue;
        const int o = m.adj[t * 3 + LongestEdge(m, t)];
        if (o < 0)
            continue;
        const int a = find(patchOf[t]), b = find(patchOf[o]);
        if (a == b)
            continue;
        /* The surviving id is the smaller one, so the result does not depend
         * on which of the two was visited first. */
        uf[std::max(a, b)] = std::min(a, b);
        ++folded;
    }
    if (folded == 0)
        return;
    MR_TRACE("  smooth: %d lone sliver%s folded into a neighbour\n", folded,
             folded == 1 ? "" : "s");

    /* Renumber to stay dense: everything downstream indexes by patch id. */
    std::vector<int> remap(patchCount, -1);
    int next = 0;
    for (int t = 0; t < nt; ++t) {
        const int r = find(patchOf[t]);
        if (remap[r] < 0)
            remap[r] = next++;
        patchOf[t] = remap[r];
    }
    patchCount = next;
}

/* Is a fitted surface EVIDENCE, or an artifact of the sample it was fitted to?
 *
 * This is the question that decides whether a model comes back as CAD or as a
 * bag of triangles, and getting it wrong in either direction is visible. Six
 * triangles off a curved shell fit a plane to well inside tolerance and a
 * sphere the size of a house even better; keeping those is how a smooth shell
 * became 179 "surfaces" that met nowhere. Throwing the whole model away
 * because of them is how its real holes stopped being circles.
 *
 * So it is asked per patch, on two counts.
 *
 * COVERAGE. A radius is only knowable from a patch that goes round enough of
 * it. Twenty degrees of a cylinder is an arc that a thousand different radii
 * pass through within tolerance, and the one the fitter picked is noise. This
 * is an absolute geometric fact, independent of how finely the thing is
 * tessellated, so it is an absolute threshold.
 *
 * AGREEMENT, against what the tessellation can actually deliver. A coarse
 * twelve-sided cylinder has facet normals fifteen degrees off the surface at
 * the corners; demanding better than that would reject every low-poly download
 * there is. So the bar is not a fixed angle but the patch's own facet step:
 * a fit whose normals are off by about half a facet is as good as this mesh
 * can be, and one that is off by four times that is describing something else.
 */
/* How far a surface strays from a facet's INTERIOR, against what that facet's
 * size allows.
 *
 * Three vertices pin a fit; the surface between them is then free, and a
 * surface with enough parameters uses that freedom. Returns the worst
 * deviation at the centroid and the three edge midpoints — the points furthest
 * from the vertices — and sets `bar` to what a real tessellation of this facet
 * would show there, which is the chord height: quadratic in facet size and so
 * far below the facet itself that the two never come close. */
double FacetBulge(SurfKind k, const double *q, const Mesh &m, int t,
                  double &bar)
{
    const V3 &a = m.pos[m.tri[t * 3]];
    const V3 &b = m.pos[m.tri[t * 3 + 1]];
    const V3 &c = m.pos[m.tri[t * 3 + 2]];
    const V3 probe[4] = {V3((a.x + b.x + c.x) / 3, (a.y + b.y + c.y) / 3,
                            (a.z + b.z + c.z) / 3),
                         V3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2),
                         V3((b.x + c.x) / 2, (b.y + c.y) / 2, (b.z + c.z) / 2),
                         V3((c.x + a.x) / 2, (c.y + a.y) / 2, (c.z + a.z) / 2)};
    double worst = 0;
    for (int i = 0; i < 4; ++i)
        worst = std::max(worst, std::fabs(SurfDist(k, q, probe[i])));
    bar = std::max(std::max(Norm(b - a), Norm(c - b)), Norm(a - c)) *
          kCentroidFacetFraction;
    return worst;
}

#ifdef MESHRECON_TRACE
const char *g_why = "ok";
#define WHY(x) (g_why = (x))
#else
#define WHY(x) ((void)0)
#endif

/* How far a normal may be from the surface's, on THIS tessellation.
 *
 * What the mesh can deliver: the median angle between neighbouring facets
 * inside the patch. A fit cannot be truer than half of that.
 *
 * NOT the plain median. Half the internal edges of a quad-meshed surface are
 * the diagonals inside the quads, whose dihedral is exactly zero, so a median
 * reads 0 on every tessellated cylinder — and then the bar collapses to the
 * floor and real cylinders sit on the edge of rejection. Take the median of
 * the edges that actually bend. */
double AgreementAllowed(const Patch &p, const Mesh &m)
{
    std::vector<double> step;
    step.reserve(p.tris.size());
    std::unordered_set<int> mine(p.tris.begin(), p.tris.end());
    for (int t : p.tris) {
        for (int k = 0; k < 3; ++k) {
            const int o = m.adj[t * 3 + k];
            if (o < 0 || o < t || mine.find(o) == mine.end())
                continue;
            step.push_back(std::acos(std::max(
                -1.0, std::min(1.0, Dot(m.tnorm[t], m.tnorm[o])))));
        }
    }
    /* The MEAN of the edges that bend, not their median.
     *
     * What this bar is compared against is a MEAN: the fit's agreement is the
     * average |cos| over every sampled corner of the patch, so a patch whose
     * facets are half narrow and half wide gets an average pulled up by the
     * wide ones. A median answers a different question — it reads the narrow
     * half and calls that the tessellation.
     *
     * Where the facets are all one size the two are the same number and
     * nothing changes: the plate's counterbores are 27-degree steps all the
     * way round and read 27 either way. Where they are not, the median is
     * simply the wrong statistic. The user's centre hole is tessellated at
     * thirty-four different azimuths because the four counterbores run tangent
     * to it and force extra vertices in: its steps run from 3 degrees to 28,
     * the median reads 8 and set a bar of 16, and the barrel's honest average
     * disagreement of 18 was rejected against it — a five-millimetre hole came
     * back as a polygon of loose facets. The mean reads 10 and sets 20. */
    double facet = 0;
    if (!step.empty()) {
        std::sort(step.begin(), step.end());
        const double floorAng = std::max(step.back() * 0.05, 1e-4);
        size_t lo = 0;
        while (lo < step.size() && step[lo] < floorAng)
            lo++;
        if (lo < step.size()) {
            double sum = 0;
            for (size_t i = lo; i < step.size(); ++i)
                sum += step[i];
            facet = sum / static_cast<double>(step.size() - lo);
        }
    }
    return std::max(facet * kAgreeFacetFactor, kAgreeFloorRad);
}

bool Identifiable(const Patch &p, const Mesh &m, double tol, bool fragment,
                  bool verdict = false, bool *tooSmallOnly = nullptr)
{
    WHY("ok");
    if (p.fit.kind == kNone)
        return WHY("nofit"), false;

    /* RESIDUAL. This is the sharpest of the three, and the reason is that a
     * tessellation puts its vertices ON the surface it came from: a real hole
     * fits its cylinder with a residual of nothing at all, at any mesh
     * density. A surface that merely happens to pass through a patch does not
     * — it squeaks inside tolerance and no further. Measured on a curved shell
     * with four drilled holes, at a tolerance of 0.20 mm: the four real
     * cylinders came back at 0.000, and the twenty "spheres" the fitter
     * invented on the shell at 0.05 to 0.16. Nothing lands in between. */
    if (p.fit.rms > tol * kTrustRmsFraction)
        return WHY("rms"), false;
    /* And a FRAGMENT is held to the exact bar instead.
     *
     * A patch that is a whole smooth run has a witness: the mesh's own sharp
     * edges bound it, and the model is saying "this is one face". A patch the
     * splitter carved out of a bigger one has no witness at all — the splitter
     * will always find something, and on a smooth organic shell it finds
     * hundreds of little planes that each sit inside the ordinary residual bar
     * and none of which exist. Measured on a 2676-triangle ellipsoidal shell:
     * 129 invented planes and 3 spheres, every one of them under 0.15 of
     * tolerance, and every one of them gone at 0.02 — while the four real
     * drilled holes in the same shell fit at 0.00000 and stay. */
    if (fragment && p.fit.rms > tol * kExactFitFraction)
        return WHY("notexact"), false;
    /* A plane is pinned down exactly by three points, so the sample-size floor
     * is for the CURVED kinds only — a box face is two triangles and perfectly
     * knowable, and holding it to six was how a box lost its planes.
     *
     * That exemption assumes the mesh is WITNESSING the plane, and a whole
     * smooth run does: the model's own sharp edges bound it, so two triangles
     * of a box face are plenty, and so are the seven flat strips a cylinder
     * comes back as when it is tessellated at fifty degrees a step — those
     * really are planes, and this must not take them.
     *
     * A FRAGMENT has no such witness. Three points are ALWAYS coplanar, so an
     * exact residual says nothing whatever about a piece of one or two facets
     * that the splitter carved out of a bigger run and that is also a
     * thousandth of the part's surface, and the residual test above cannot
     * reject it. Measured on the user's part: where the boss blend crosses the
     * top-edge fillet, six such pieces — nine triangles between them — each
     * became a face of its own, and every one is a visible crease across what
     * should be a smooth rounded edge. */
    bool floorApplies = p.fit.kind != kPlane;
    if (!floorApplies && fragment) {
        /* ...and how small is small enough to be nothing? The same fraction of
         * the model's surface that decides whether a scrap of a face is worth
         * less than its own triangles. A plate's end wall is two triangles and
         * a fragment of the rim's run — and thirty square millimetres, one and
         * a half percent of the part: a face. The pieces left at the crossing
         * are one and two triangles and a fifth of a square millimetre. */
        double a = 0;
        for (int t : p.tris)
            a += m.tarea[t];
        floorApplies = a <= m.area * kScrapAreaFraction;
    }
    const bool tooSmall =
        floorApplies &&
        std::max(static_cast<int>(p.tris.size()), p.evidence) <
            kMinTrustTriangles;

    const double allowed = AgreementAllowed(p, m);
    if (std::acos(std::max(-1.0, std::min(1.0, p.fit.agree))) > allowed)
        return WHY("agree"), false;

    /* A plane has no radius to pin down, so agreement is the whole test —
     * so a plane that reaches here and fails only the sample-size floor has
     * failed NOTHING about the surface itself, and the caller is told so. */
    if (p.fit.kind == kPlane) {
        if (tooSmall) {
            if (tooSmallOnly)
                *tooSmallOnly = true;
            return WHY("tootiny"), false;
        }
        return true;
    }
    if (tooSmall)
        return WHY("tootiny"), false;

    /* Does the surface pass through the mesh's FACES, or only its vertices?
     *
     * Everything above is measured at vertices, and a surface with enough
     * freedom can thread every vertex of a patch and still bulge through the
     * middle of it. That is not a hypothetical: a 12 mm corner fillet plus two
     * triangles of the wall beside it was fitted EXACTLY — residual 0.00000 at
     * every vertex — by a torus of major radius 25 mm about the part's own
     * vertical axis, which bows 11.2 mm out through the facets in between. Its
     * trimmed face added three hundred percent to the model's volume.
     *
     * A facet is a chord of the surface it came off, so the surface stands off
     * its interior by the chord height, which is quadratic in facet size and
     * tiny: 0.05 mm on the real fillets in that same model, against 11.2 for
     * the torus. Sampling the centroid and the three edge midpoints — the
     * points furthest from the vertices that pinned the fit — separates the
     * two by two orders of magnitude, so the bar can be loose and still
     * decisive. */
    {
        const int stride2 = std::max<int>(1, (int)p.tris.size() / 256);
        for (size_t i = 0; i < p.tris.size(); i += stride2) {
            double bar = 0;
            if (FacetBulge(p.fit.kind, p.fit.q, m, p.tris[i], bar) >
                std::max(bar, tol))
                return WHY("bulge"), false;
        }
    }

    /* Sample the patch's corners — a few hundred is ample to establish a
     * quarter turn, and a patch can hold thousands. */
    std::vector<V3> pts;
    const int stride = std::max<int>(1, static_cast<int>(p.tris.size()) / 96);
    for (size_t i = 0; i < p.tris.size(); i += stride)
        for (int k = 0; k < 3; ++k)
            pts.push_back(m.pos[m.tri[p.tris[i] * 3 + k]]);
    if (pts.size() < 3)
        return WHY("nopoints"), false;
    /* And a FRAGMENT has to sweep further before its curve is believed.
     *
     * A patch that is a whole smooth run has the mesh's own sharp edges as its
     * witness — the model is saying "this is one face" — and a quarter turn of
     * it is plenty. A patch the splitter carved out of a bigger one has no
     * witness, and a shallow arc is where an invented surface hides: the lower
     * band of the user's top edge is six facets thirteen millimetres long, and
     * a cylinder of radius 31 threads every one of their vertices to a
     * five-thousandth of a millimetre. It sweeps 26 degrees. The r=1 fillet it
     * is actually part of sweeps ninety. */
    const double sweep = SurfaceCoverage(p.fit.kind, p.fit.q, pts);
    if (sweep < kMinSweepRad)
        return WHY("sweep"), false;
    /* Only when the verdict is final. Inside the splitter and the merge this
     * same routine is asked whether a candidate is worth pursuing, and a
     * shallow arc there is a perfectly good reason to keep looking rather than
     * to stop — asked the strict question in those places instead, the whole
     * segmentation of the user's part changed and it came back 129 faces and
     * an open shell. */
    if (verdict && fragment && sweep < kMinSweepFragmentRad)
        return WHY("shallow"), false;
    return true;
}

/* Cuts a patch at its own sharpest internal crease, if it has one.
 *
 * A smooth patch that fits no primitive is often two surfaces meeting at an
 * angle SHALLOWER than the global sharp-edge threshold: a cylinder into a
 * gentle cone, a nozzle, a tapered boss, a shallow chamfer. Region growing
 * handles a TANGENT seam well and a creased one badly — at a crease every seed
 * near it straddles both surfaces and fits neither, and the patch comes apart
 * into shards instead of two faces.
 *
 * The crease is visible in the patch's own dihedral statistics, with no
 * absolute angle anywhere: on a smoothly curved patch every internal dihedral
 * is about the tessellation step, so the distribution is tight; a crease puts
 * one ring of edges far above it. Comparing a high quantile against that step
 * is self-calibrating — it reads the same on a 12-segment download as on a
 * 2000-segment export, and it says "no crease" on a sphere.
 *
 * The step is NOT the plain median: half the internal edges of a quad-meshed
 * surface are the diagonals inside the quads, whose dihedral is exactly zero,
 * so a median reads zero on every cylinder and the cut lands everywhere. Take
 * the median of the edges that actually bend. */
bool SplitAtCrease(const Mesh &m, const std::vector<int> &tris, int minTris,
                   std::vector<std::vector<int>> &parts)
{
    parts.clear();
    if (tris.size() < 8)
        return false;
    std::unordered_map<int, int> local;
    for (size_t i = 0; i < tris.size(); ++i)
        local.emplace(tris[i], static_cast<int>(i));

    std::vector<double> ang;
    ang.reserve(tris.size() * 3 / 2);
    for (int t : tris) {
        for (int k = 0; k < 3; ++k) {
            const int o = m.adj[t * 3 + k];
            if (o < 0 || o < t || local.find(o) == local.end())
                continue;
            const double c =
                std::max(-1.0, std::min(1.0, Dot(m.tnorm[t], m.tnorm[o])));
            ang.push_back(std::acos(c));
        }
    }
    if (ang.size() < 8)
        return false;
    std::sort(ang.begin(), ang.end());
    const double hi = ang[(size_t)(ang.size() * kCreaseQuantile)];
    if (hi < kMinCreaseAngle)
        return false;
    const double floorAng = std::max(hi * 0.05, 0.2 * M_PI / 180.0);
    size_t lo = 0;
    while (lo < ang.size() && ang[lo] < floorAng)
        lo++;
    if (lo >= ang.size())
        return false;
    const double step = ang[lo + (ang.size() - lo) / 2];
    if (hi < kCreaseRatio * std::max(step, 1e-4))
        return false;

    /* Cut between the two: above every ordinary curvature step, below the
     * crease. The geometric mean puts it there on any tessellation. */
    double thr = std::sqrt(std::max(step, 1e-6) * hi);
    thr = std::max(thr, 1.5 * step);
    thr = std::min(thr, 0.8 * hi);
    const double cosThr = std::cos(thr);

    std::vector<int> comp(tris.size(), -1);
    int n = 0;
    std::vector<int> stack;
    for (size_t si = 0; si < tris.size(); ++si) {
        if (comp[si] >= 0)
            continue;
        const int id = n++;
        stack.assign(1, static_cast<int>(si));
        comp[si] = id;
        while (!stack.empty()) {
            const int i = stack.back();
            stack.pop_back();
            const int t = tris[i];
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0)
                    continue;
                auto it = local.find(o);
                if (it == local.end() || comp[it->second] >= 0)
                    continue;
                if (Dot(m.tnorm[t], m.tnorm[o]) < cosThr)
                    continue;
                comp[it->second] = id;
                stack.push_back(it->second);
            }
        }
    }
    if (n < 2)
        return false;
    parts.assign(n, std::vector<int>());
    for (size_t i = 0; i < tris.size(); ++i)
        parts[comp[i]].push_back(tris[i]);
    /* Two real pieces, not one piece and a rim of strays. */
    int big = 0;
    for (const std::vector<int> &pp : parts)
        if (static_cast<int>(pp.size()) >= std::max(minTris, 3))
            big++;
    if (big < 2) {
        parts.clear();
        return false;
    }
    return true;
}

/* How closely a candidate triangle's normal must follow the running fit's, to
 * be taken into the region. About 8 degrees: tight enough that a plane stops
 * one facet into a blend, loose enough that a blend's own facets — half a facet
 * angle off the fitted surface — all get in. */
const double kGrowNormalGate = 0.99;

/* Publishes the triangles that finished patches have retired.
 *
 * Fitting is the long stage and one run inside it can be most of the mesh: on
 * the whale, sixteen runs take seven of the ten seconds and ONE of them is
 * six of those seven. A counter that ticks per run therefore sits still for
 * six seconds, which is a worse lie than the indeterminate sweep it replaced,
 * because a stopped bar reads as a hang. Counting the TRIANGLES each finished
 * patch retires moves it whenever anything is genuinely finished, at every
 * depth of the recursion, and needs no estimate of anything.
 *
 * Converting thread only. `out` is append-only, so walking from the cursor is
 * exact however the recursion interleaves, and it cannot double-count: each
 * patch is passed exactly once. Calling it more often than necessary costs a
 * size comparison, so the call sites err towards more.
 *
 * The watched vector is remembered because the splitter is ALSO run on a
 * scratch vector — DissolveUnexplained re-splits a trimmed patch into a local
 * one — and counting that as progress would advance a stage that has already
 * ended, against a total that was never about it. Anything but the vector
 * RetireFrom named is ignored. */
static const void *g_retireWatch = 0;
static size_t g_retireCursor = 0;

void RetireFrom(const std::vector<Patch> &out)
{
    g_retireWatch = &out;
    g_retireCursor = out.size();
}

void Retire(const std::vector<Patch> &out)
{
    if (&out != g_retireWatch)
        return;
    int add = 0;
    for (; g_retireCursor < out.size(); ++g_retireCursor)
        add += static_cast<int>(out[g_retireCursor].tris.size());
    AddDone(add);
}

/* Splits one patch that fitted nothing into sub-patches that do, by growing a
 * region from a seed while a running fit keeps holding.
 *
 * This is the step that separates a fillet from the faces it blends. A fillet
 * meets its neighbours TANGENTIALLY, so no dihedral threshold will ever cut
 * there — but a plane fit stops accepting triangles the moment the surface
 * starts to curve, and that is exactly the fillet's edge. */
void SplitByFit(const Mesh &m, const std::vector<int> &tris, double tol,
                double scale, int minTris, int origin, std::vector<Patch> &out)
{
    std::unordered_map<int, int> local; /* triangle -> index in tris */
    for (size_t i = 0; i < tris.size(); ++i)
        local.emplace(tris[i], static_cast<int>(i));
    std::vector<char> taken(tris.size(), 0);

    /* How sharply the surface turns at each triangle: the largest angle to a
     * neighbour INSIDE this patch. Used ONLY to order the seeds.
     *
     * It is tempting to gate the growth on this too, and it does not work: the
     * value is the max over neighbours, so a flat triangle that happens to
     * touch a fillet reports the fillet's angle and is indistinguishable from
     * one. As a seed ORDER it is still worth having — the flat, confident parts
     * of the patch claim their triangles before a blend starts guessing. */
    std::vector<double> bend(tris.size(), 0.0);
    for (size_t i = 0; i < tris.size(); ++i) {
        const int t = tris[i];
        double worst = 0;
        for (int k = 0; k < 3; ++k) {
            const int o = m.adj[t * 3 + k];
            if (o < 0 || local.find(o) == local.end())
                continue;
            const double c =
                std::max(-1.0, std::min(1.0, Dot(m.tnorm[t], m.tnorm[o])));
            worst = std::max(worst, std::acos(c));
        }
        bend[i] = worst;
    }

    /* Flattest first, then largest. A planar face is the most confident thing
     * in the patch, so it should claim its triangles before a blend does. */
    std::vector<int> byArea(tris.size());
    for (size_t i = 0; i < tris.size(); ++i)
        byArea[i] = static_cast<int>(i);
    /* Flattest first, then largest — and QUANTISED, not compared against a
     * threshold.
     *
     * "Equal if within 1e-4" is not an ordering at all: a can tie b and b tie
     * c while a and c are a fifth of a milliradian apart, and std::sort is
     * entitled to do anything at all with a comparator like that, up to
     * running off the end of the array. Rounding to the same grid says the
     * same thing about which bends count as equal and says it transitively.
     * Then area, then the triangle's own index, so the order is total. */
    std::vector<long long> bendBin(tris.size());
    for (size_t i = 0; i < tris.size(); ++i)
        bendBin[i] = static_cast<long long>(std::llround(bend[i] * 1e4));
    std::sort(byArea.begin(), byArea.end(), [&](int a, int b) {
        if (bendBin[a] != bendBin[b])
            return bendBin[a] < bendBin[b];
        if (m.tarea[tris[a]] != m.tarea[tris[b]])
            return m.tarea[tris[a]] > m.tarea[tris[b]];
        /* And a TOTAL order, always. See "Ties decide the model". */
        return tris[a] < tris[b];
    });

    std::vector<int> region, frontier;
    PatchData pd;
    for (int si : byArea) {
        if (taken[si])
            continue;
        region.clear();
        region.push_back(tris[si]);
        taken[si] = 1;

        /* Seed the fit from the immediate neighbourhood, then grow. */
        Fit fit;
        int sinceRefit = 0;
        frontier.assign(1, tris[si]);
        while (!frontier.empty()) {
            const int t = frontier.back();
            frontier.pop_back();
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0)
                    continue;
                auto it = local.find(o);
                if (it == local.end() || taken[it->second])
                    continue;
                bool accept;
                if (fit.kind == kNone) {
                    /* Before there is a fit there is nothing to test against,
                     * so hold the seed together by normal alone and let the fit
                     * take over as soon as there are points enough to make one.
                     * This only has to avoid turning a corner; a tangent seam
                     * it cannot see; MergeRegions repairs that after. */
                    accept = region.size() < 12 &&
                             Dot(m.tnorm[o], m.tnorm[tris[si]]) > 0.9;
                } else {
                    accept = true;
                    V3 c;
                    for (int kk = 0; kk < 3 && accept; ++kk) {
                        const V3 &p = m.pos[m.tri[o * 3 + kk]];
                        c += p;
                        if (std::fabs(SurfDist(fit.kind, fit.q, p)) >
                            tol * 1.5) {
                            accept = false;
                        }
                    }
                    /* Distance alone lets a PLANE eat into a fillet.
                     *
                     * The blend leaves the plane tangentially, so its first
                     * facets are only microns off it and pass any distance
                     * test — and once two of them are in the region, the fit
                     * is of a plane-and-a-bit-of-arc, which lands on a sphere
                     * of radius fifty on a forty-five millimetre part. Where
                     * the surface goes is what separates them: one facet into
                     * the blend the direction is already visibly turning. */
                    if (accept) {
                        const V3 sn =
                            SurfNormal(fit.kind, fit.q, c * (1.0 / 3.0),
                                       std::max(scale * 1e-5, 1e-9));
                        if (Norm(sn) > 0.5 &&
                            std::fabs(Dot(sn, m.tnorm[o])) < kGrowNormalGate) {
                            accept = false;
                        }
                    }
                }
                if (!accept)
                    continue;
                taken[it->second] = 1;
                region.push_back(o);
                frontier.push_back(o);
                if (++sinceRefit >=
                    std::max<int>(8, static_cast<int>(region.size()) / 4)) {
                    sinceRefit = 0;
                    PatchPoints(m, region, pd, 2000);
                    const Fit f = FitPatch(pd, tol, scale);
                    if (f.kind != kNone)
                        fit = f;
                }
            }
        }
        PatchPoints(m, region, pd, 4000);
        Patch pa;
        pa.tris = region;
        pa.origin = origin;
        pa.fit = FitPatch(pd, tol, scale);
        if (pa.fit.kind == kNone && static_cast<int>(region.size()) < minTris) {
            /* Too small to say anything about; it will be emitted faceted. */
        }
        out.push_back(pa);
        Retire(out);
    }
}

/* RANSAC over one patch: propose many primitives, keep the one the mesh
 * supports best, take its triangles, repeat.
 *
 * This is the segmentation step the classical literature settled on (Schnabel,
 * Wahl & Klein 2007) and it is what the commercial converters use, because
 * greedy region growing has a failure mode it cannot escape: it commits to
 * whatever the first seed suggested. On a coarse prismatic model — a
 * downloaded one, in other words — the first seed off a twelve-sided cylinder
 * is a PLANE that fits three columns to well inside tolerance, and the barrel
 * comes back as a fan of planar strips.
 *
 * Proposing instead of committing removes that. A candidate is grown from a
 * random seed, fitted, and then scored against the WHOLE patch: how many
 * triangles does this surface actually explain? The plane explains three
 * columns; the cylinder explains the barrel. The cylinder wins on evidence
 * rather than on being asked first.
 *
 * Deterministic on purpose — the generator is seeded from the patch — because
 * a converter whose output depends on the weather cannot be tested. */
/* Which of two RANSAC proposals describes the part better.
 *
 * Support alone is the obvious score and it is wrong, because a surface with
 * one more degree of freedom can always reach a little further. Measured on a
 * 60 mm plate with four r=5 corner fillets: three came back as cylinders with
 * 32 triangles and a residual of EXACTLY zero, and the fourth as a torus with
 * 34 — the same fillet plus two triangles of the wall it is tangent to, held
 * together by a major radius of 15 mm that exists nowhere in the part. Two
 * extra triangles bought it the round, and the trimmed torus that came out of
 * it added forty-two percent to the model's volume.
 *
 * The residual is what separates them, and it separates them completely. A
 * tessellation puts its vertices ON the surface they came from, so a proposal
 * that is really that surface fits it to zero while a proposal that is merely
 * near it does not. So: an exact candidate beats an inexact one no matter how
 * much more the inexact one claims; among equals, more support wins; and on a
 * genuine tie the simpler primitive does, since kind order runs plane, sphere,
 * cylinder, cone, torus. On a noisy scan nothing is exact, everything lands in
 * the lower tier, and this is support-first again, as it was. */
bool BeatsCandidate(size_t nA, double rmsA, double seedA, SurfKind kA,
                    size_t nB, double rmsB, double seedB, SurfKind kB,
                    double tol)
{
    if (nA == 0)
        return false;
    if (nB == 0)
        return true;
    const bool exA = rmsA <= tol * kExactFitFraction;
    const bool exB = rmsB <= tol * kExactFitFraction;
    if (exA != exB)
        return exA;
    /* Then whether the SEED itself was exact.
     *
     * A claim made at tolerance is fuzzy at a tangency, so two proposals can
     * claim the same triangles and look equally inexact while only one of them
     * started from a surface that is really in the mesh. That distinction is
     * everything, because the tight re-claim that rescues a fuzzy claim is
     * made around the seed: measured on the user's part, a cylinder seeded at
     * residual zero on the r=1 fillet along its long edge lost the round to
     * one seeded at 0.0013 with the same support, and the re-claim around
     * THAT found nothing at all — 41 triangles down to none — so the fillet
     * went to triangles at both ends of the part. */
    const bool sA = seedA <= tol * kExactFitFraction;
    const bool sB = seedB <= tol * kExactFitFraction;
    if (sA != sB)
        return sA;
    if (nA != nB)
        return nA > nB;
    if (std::fabs(rmsA - rmsB) > tol * 1e-3)
        return rmsA < rmsB;
    return kA < kB;
}

void SplitByRansac(const Mesh &m, const std::vector<int> &tris, double tol,
                   double scale, int minTris, int origin,
                   std::vector<Patch> &out, std::vector<int> &leftover)
{
    leftover.clear();
    const int n = static_cast<int>(tris.size());
    if (n < kRansacMinPatch) {
        leftover = tris;
        return;
    }
    std::unordered_map<int, int> local;
    for (int i = 0; i < n; ++i)
        local.emplace(tris[i], i);
    const size_t before = out.size();
    std::vector<char> taken(n, 0);
    std::vector<char> barred(n, 0); /* seeds that led nowhere */
    int remaining = n;

    unsigned rng = 0x9E3779B9u ^ (unsigned)n ^ ((unsigned)tris[0] * 2654435761u);
    auto next = [&rng]() {
        rng ^= rng << 13;
        rng ^= rng >> 17;
        rng ^= rng << 5;
        return rng;
    };

    PatchData pd;
    std::vector<int> seedRegion, stack, inliers, best;
    Fit bestFit;
    double bestRms = 1e300;
    int bestStart = -1;
    const int trials = kRansacLadderSteps * kRansacTrialsPerSize;
    std::vector<int> pool;
    for (int round = 0; round < kRansacRounds && remaining >= minTris; ++round) {
        if (Cancelled())
            break;
        pool.clear();
        for (int i = 0; i < n; ++i)
            if (!taken[i] && !barred[i])
                pool.push_back(i);
        best.clear();
        bestFit = Fit();
        bestRms = 1e300;
        bestStart = -1;
        for (int trial = 0; trial < trials; ++trial) {
            if ((trial & 31) == 0 && Cancelled())
                break;
            const int want = kRansacSeedLadder[trial % kRansacLadderSteps];
            /* Draw the seed from what is actually LEFT.
             *
             * Rejection sampling over the whole patch looks harmless and is
             * not: by the twentieth round nine tenths of the triangles are
             * taken, sixteen draws miss, and most trials never propose
             * anything at all. The last surfaces of a part are exactly the
             * ones extracted late, so this is where it costs. */
            if (pool.empty())
                break;
            const int start = pool[next() % (unsigned)pool.size()];
            if (taken[start] || barred[start])
                continue;
            seedRegion.clear();
            stack.assign(1, start);
            std::unordered_map<int, char> inSeed;
            inSeed.emplace(tris[start], 1);
            while (!stack.empty() && (int)seedRegion.size() < want) {
                const int i = stack.back();
                stack.pop_back();
                seedRegion.push_back(tris[i]);
                for (int k = 0; k < 3; ++k) {
                    const int o = m.adj[tris[i] * 3 + k];
                    if (o < 0)
                        continue;
                    auto it = local.find(o);
                    if (it == local.end() || taken[it->second])
                        continue;
                    if (inSeed.find(o) != inSeed.end())
                        continue;
                    inSeed.emplace(o, 1);
                    stack.push_back(it->second);
                }
            }
            if ((int)seedRegion.size() < 4)
                continue;
            PatchPoints(m, seedRegion, pd, 600);
            const Fit f = FitPatch(pd, tol, scale);
            if (f.kind == kNone || f.rms > tol * kTrustRmsFraction)
                continue;

            /* Score it against the whole patch, CONNECTED to the seed: a
             * cylinder must not claim the identical hole on the far side of
             * the part. */
            inliers.clear();
            double ss = 0;
            int sn2 = 0;
            std::unordered_map<int, char> mark;
            stack.assign(1, start);
            mark.emplace(tris[start], 1);
            while (!stack.empty()) {
                const int i = stack.back();
                stack.pop_back();
                const int t = tris[i];
                bool ok = true;
                double d2 = 0;
                for (int k = 0; k < 3 && ok; ++k) {
                    const V3 &p = m.pos[m.tri[t * 3 + k]];
                    const double dd = SurfDist(f.kind, f.q, p);
                    if (std::fabs(dd) > tol)
                        ok = false;
                    d2 += dd * dd;
                }
                if (ok) {
                    const V3 sn = SurfNormal(f.kind, f.q, m.pos[m.tri[t * 3]],
                                             std::max(scale * 1e-5, 1e-9));
                    if (Norm(sn) > 0.5 &&
                        std::fabs(Dot(sn, m.tnorm[t])) < kRansacNormalGate)
                        ok = false;
                }
                /* And it must pass through the facet, not merely its corners.
                 * A torus threaded exactly through every vertex of a wall,
                 * a corner fillet and the next wall bulges 12.5 mm out
                 * through the middle of them; on vertices alone it was an
                 * exact fit claiming 22 triangles, and it beat the true
                 * cylinder claiming 8. */
                if (ok) {
                    double bar = 0;
                    if (FacetBulge(f.kind, f.q, m, t, bar) >
                        std::max(bar, tol))
                        ok = false;
                }
                if (!ok)
                    continue;
                inliers.push_back(i);
                ss += d2;
                sn2 += 3;
                for (int k = 0; k < 3; ++k) {
                    const int o = m.adj[t * 3 + k];
                    if (o < 0)
                        continue;
                    auto it = local.find(o);
                    if (it == local.end() || taken[it->second])
                        continue;
                    if (mark.find(o) != mark.end())
                        continue;
                    mark.emplace(o, 1);
                    stack.push_back(it->second);
                }
            }
            const double candRms = sn2 ? std::sqrt(ss / sn2) : 1e300;
            /* A candidate that cannot be kept must not be allowed to win.
             *
             * Four triangles fit a sphere exactly wherever you put them, and
             * such a sphere — support 4, residual zero — took the round from a
             * cylinder explaining nineteen triangles of a real fillet, purely
             * by being exact. The extraction then stopped for want of support
             * and two thirds of the run went to triangles. Nothing below the
             * floor is evidence; it should not be on the ballot. */
            if ((int)inliers.size() < std::max(minTris, kRansacMinSupport))
                continue;
            if (BeatsCandidate(inliers.size(), candRms, f.rms, f.kind,
                               best.size(), bestRms, bestFit.rms, bestFit.kind,
                               tol)) {
                best = inliers;
                bestFit = f;
                bestRms = candRms;
                bestStart = start;
            }
        }
#ifdef MESHRECON_TRACE
        {
            V3 lo(1e30, 1e30, 1e30), hi(-1e30, -1e30, -1e30);
            for (int i : best)
                for (int k = 0; k < 3; ++k) {
                    const V3 &q = m.pos[m.tri[tris[i] * 3 + k]];
                    lo = V3(std::min(lo.x, q.x), std::min(lo.y, q.y),
                            std::min(lo.z, q.z));
                    hi = V3(std::max(hi.x, q.x), std::max(hi.y, q.y),
                            std::max(hi.z, q.z));
                }
            MR_TRACE("        round %d: best %d tri, kind %s, rms %.6f, "
                     "box (%.2f %.2f %.2f)-(%.2f %.2f %.2f) (remaining %d)\n",
                     round, (int)best.size(), KindName(bestFit.kind), bestRms,
                     lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, remaining);
        }
#endif
        if ((int)best.size() < std::max(minTris, kRansacMinSupport)) {
            MR_TRACE("        -> too little support, stop\n");
            break;
        }

        /* TIGHTEN the claim — either because the winner is exact, or as a
         * RECOVERY when its refit is not.
         *
         * Claiming at tolerance is right for the surface being proposed and
         * too generous at a TANGENCY, where the neighbouring face hugs the
         * proposal for a strip sqrt(2 r tol) wide — 1.2 mm where an r=5 fillet
         * meets its wall. Those triangles pass the distance test and the
         * normal test (at the tangent line the two surfaces share a normal),
         * so the fillet arrives at the refit carrying two triangles of flat
         * wall and comes back as a torus bent round an axis that exists
         * nowhere in the part.
         *
         * A surface the mesh was tessellated from is met by its own vertices
         * exactly, so re-claiming at that standard drops the tangent strip and
         * moves nothing that really is the surface. Worth doing when the
         * winner already looks exact, and worth doing AGAIN, around the refit,
         * when it does not: a mixed claim whose refit misses the exact bar is
         * usually one good surface plus a fringe, and the fringe is what the
         * tight threshold removes. */
        auto tighten = [&](SurfKind kind, const double *q) {
            if (bestStart < 0)
                return;
            /* The mesh's OWN precision, not a fraction of tolerance.
             *
             * A tessellated CAD model's vertices sit on their surface to
             * float32 — three millionths of a millimetre at this size — so
             * anything measurably off it belongs to something else. Measured
             * on the user's part: every triangle of the r=1 fillet along its
             * long edge lies at 0.0000 from that cylinder, and the ten
             * triangles of the transition beside it at 0.0018 to 0.0275. A
             * bar of two thousandths let the nearest of those in, the strip
             * stopped being a cylinder, and the whole fillet went to
             * triangles. */
            const double tight = std::max(scale * kMeshPrecisionFrac, 1e-9);
            std::vector<int> tightened;
            std::unordered_map<int, char> mark2;
            stack.assign(1, bestStart);
            mark2.emplace(tris[bestStart], 1);
            while (!stack.empty()) {
                const int i = stack.back();
                stack.pop_back();
                const int t = tris[i];
                bool ok = true;
                for (int k = 0; k < 3 && ok; ++k)
                    if (std::fabs(SurfDist(kind, q, m.pos[m.tri[t * 3 + k]])) >
                        tight)
                        ok = false;
                if (!ok)
                    continue;
                tightened.push_back(i);
                for (int k = 0; k < 3; ++k) {
                    const int o = m.adj[t * 3 + k];
                    if (o < 0)
                        continue;
                    auto it = local.find(o);
                    if (it == local.end() || taken[it->second])
                        continue;
                    if (mark2.find(o) != mark2.end())
                        continue;
                    mark2.emplace(o, 1);
                    stack.push_back(it->second);
                }
            }
            if ((int)tightened.size() >= std::max(minTris, kRansacMinSupport))
                best.swap(tightened);
        };
        /* Refit on everything it claimed, and keep it only if it still holds. */
        std::vector<int> claimed;
        claimed.reserve(best.size());
        for (int i : best)
            claimed.push_back(tris[i]);
        PatchPoints(m, claimed, pd, 4000);
        Patch pa;
        pa.tris = claimed;
        pa.origin = origin;
        pa.fit = FitPatch(pd, tol, scale);
        /* EXACT, not merely within tolerance.
         *
         * RANSAC is being asked to find a surface inside a patch that fitted
         * nothing, and it will always find something: four triangles of an
         * organic shell fit a plane, six fit a sphere, and with a small enough
         * seed it can propose one anywhere. Held to the ordinary residual bar
         * it carved a smooth 2676-triangle shell into 129 invented planes and
         * three spheres — the "179 surfaces that met nowhere" failure, back
         * again from the other end.
         *
         * A tessellation puts its vertices ON the surface it came from, so a
         * surface that is really there is recovered to zero and one that is
         * merely nearby is not. That is the whole difference between a
         * downloaded CAD model, where this pass should find every fillet, and
         * an organic one, where it should find nothing at all. */
        /* Re-claim at the mesh's OWN precision when the refit is not exact.
         *
         * A claim made at tolerance is fuzzy at a TANGENCY: the neighbouring
         * face hugs the proposal for a strip sqrt(2 r tol) wide — 1.2 mm where
         * an r=5 fillet meets its wall — and those triangles pass both the
         * distance and the normal test, so the fillet arrives at the refit
         * carrying flat wall and comes back as a torus bent round an axis that
         * exists nowhere in the part. A surface the mesh was tessellated from
         * is met by its own vertices exactly, so re-claiming at that standard
         * drops the strip and moves nothing that really is the surface.
         *
         * Around the SEED first, because the seed is usually a real local
         * surface — measured on the user's part, thirteen rounds in a row
         * proposed one and had its claim spoiled this way — and around the
         * refit second, in case the seed itself was the poorer of the two. */
        for (int attempt = 0; attempt < 2; ++attempt) {
            if (pa.fit.kind != kNone &&
                pa.fit.rms <= tol * kExactFitFraction)
                break;
            const double *q = attempt == 0 ? bestFit.q : pa.fit.q;
            const SurfKind kind = attempt == 0 ? bestFit.kind : pa.fit.kind;
            if (kind == kNone)
                continue;
            const size_t was = best.size();
            tighten(kind, q);
            if (best.size() == was)
                continue;
            claimed.clear();
            for (int i : best)
                claimed.push_back(tris[i]);
            PatchPoints(m, claimed, pd, 4000);
            pa.tris = claimed;
            pa.fit = FitPatch(pd, tol, scale);
        }
        if (pa.fit.kind == kNone || pa.fit.rms > tol * kExactFitFraction ||
            !Identifiable(pa, m, tol, true)) {
            /* A proposal that does not survive its refit is not the end of the
             * search — it only means this seed was a bad one. Bar its
             * triangles from seeding again (or the same winner comes back
             * every round) and carry on; they stay claimable by anything else
             * and otherwise fall through to the leftover. Stopping here
             * instead left two thirds of the user's part unexplained. */
            MR_TRACE("        -> refit %s rms %.6f rejected, reseeding\n",
                     KindName(pa.fit.kind), pa.fit.rms);
            bool anyNew = false;
            for (int i : best)
                if (!barred[i]) {
                    barred[i] = 1;
                    anyNew = true;
                }
            if (!anyNew)
                break;
            continue;
        }
        MR_TRACE("        -> KEEP %s %d tri rms %.6f q=[%.3f %.3f %.3f | "
                 "%.3f %.3f %.3f | %.4f %.4f]\n",
                 KindName(pa.fit.kind), (int)pa.tris.size(), pa.fit.rms,
                 pa.fit.q[0], pa.fit.q[1], pa.fit.q[2], pa.fit.q[3],
                 pa.fit.q[4], pa.fit.q[5], pa.fit.q[6], pa.fit.q[7]);
        out.push_back(pa);
        Retire(out); /* a whole extraction can be seconds; tick per surface */
        for (int i : best) {
            taken[i] = 1;
            remaining--;
        }
        /* A seed that led nowhere may lead somewhere now: taking a surface out
         * changes what its neighbours are next to, and the claim that ran past
         * a transition last time may stop at it this time. */
        std::fill(barred.begin(), barred.end(), 0);
    }
    /* Sweep the leftovers into the surfaces already found.
     *
     * What RANSAC leaves behind is rarely a surface of its own — it is the
     * fringe of one it already has, dropped because a claim stopped a row
     * short or a seed was barred. A triangle lying EXACTLY on a surface this
     * patch is already known to contain belongs to it, and taking it there is
     * both more accurate and one seam fewer than emitting it as loose
     * triangles. Held to the mesh's own precision, not to tolerance, so
     * nothing is dragged across a tangency. */
    if (out.size() > before) {
        const double tight = std::max(tol * kExactFitFraction, scale * 1e-6);
        std::vector<int> owner(n, -1);
        for (size_t p = before; p < out.size(); ++p)
            for (int t : out[p].tris) {
                auto it = local.find(t);
                if (it != local.end())
                    owner[it->second] = static_cast<int>(p);
            }
        bool moved = true;
        while (moved) {
            moved = false;
            for (int i = 0; i < n; ++i) {
                if (taken[i])
                    continue;
                const int t = tris[i];
                int into = -1;
                for (int k = 0; k < 3 && into < 0; ++k) {
                    const int o = m.adj[t * 3 + k];
                    if (o < 0)
                        continue;
                    auto it = local.find(o);
                    if (it == local.end() || owner[it->second] < 0)
                        continue;
                    const Fit &f = out[owner[it->second]].fit;
                    bool ok = true;
                    for (int v = 0; v < 3 && ok; ++v)
                        if (std::fabs(SurfDist(f.kind, f.q,
                                               m.pos[m.tri[t * 3 + v]])) >
                            tight)
                            ok = false;
                    if (ok) {
                        const V3 sn =
                            SurfNormal(f.kind, f.q, m.pos[m.tri[t * 3]],
                                       std::max(scale * 1e-5, 1e-9));
                        if (Norm(sn) > 0.5 &&
                            std::fabs(Dot(sn, m.tnorm[t])) < kRansacNormalGate)
                            ok = false;
                    }
                    if (ok) {
                        double bar = 0;
                        if (FacetBulge(f.kind, f.q, m, t, bar) >
                            std::max(bar, tol))
                            ok = false;
                    }
                    if (ok)
                        into = owner[it->second];
                }
                if (into >= 0) {
                    out[into].tris.push_back(t);
                    owner[i] = into;
                    taken[i] = 1;
                    moved = true;
                }
            }
        }
    }

    for (int i = 0; i < n; ++i)
        if (!taken[i])
            leftover.push_back(tris[i]);
}

/* Splits a patch that fits nothing: crease first, running fit second.
 *
 * Cutting at a crease is both cheaper and more reliable than growing across
 * one, so it is tried first and recursed into; SplitByFit then handles what is
 * left, which is the tangent case it was written for. */
void SplitPatch(const Mesh &m, const std::vector<int> &tris, double tol,
                double scale, int minTris, int origin, int depth,
                std::vector<Patch> &out)
{
    if (Cancelled())
        return;
    Retire(out);
    PatchData pd;
    PatchPoints(m, tris, pd, 4000);
    Patch pa;
    pa.tris = tris;
    pa.origin = origin;
    pa.fit = FitPatch(pd, tol, scale);
    if (pa.fit.kind != kNone || static_cast<int>(tris.size()) < minTris * 4) {
        out.push_back(pa);
        return;
    }
    MR_TRACE("    split %d tri (depth %d): fit %s\n", (int)tris.size(), depth,
             KindName(pa.fit.kind));
    if (depth < kMaxCreaseDepth) {
        std::vector<std::vector<int>> parts;
        if (SplitAtCrease(m, tris, minTris, parts)) {
#ifdef MESHRECON_TRACE
            MR_TRACE("      crease ->");
            for (const std::vector<int> &pp : parts)
                MR_TRACE(" %d", (int)pp.size());
            MR_TRACE("\n");
#endif
            for (const std::vector<int> &pp : parts)
                SplitPatch(m, pp, tol, scale, minTris, origin, depth + 1, out);
            return;
        }
    }
    /* Propose-and-score before grow-and-hope. RANSAC takes the surfaces the
     * mesh actually supports; SplitByFit then works on what is left, which is
     * the tangent-blend case it was written for and is good at. */
    const size_t before = out.size();
    std::vector<int> rest;
    SplitByRansac(m, tris, tol, scale, minTris, origin, out, rest);
    Retire(out);
    MR_TRACE("      ransac %d tri -> %d surfaces, %d left\n", (int)tris.size(),
             (int)(out.size() - before), (int)rest.size());
    if (rest.empty())
        return;
    if (rest.size() < tris.size()) {
        /* Something was recognised, so the remainder is a strictly smaller
         * problem — and worth the same treatment rather than a straight fall
         * to region growing. RANSAC's seeds are drawn from what is left, so on
         * a smaller set they land where the work is: on the user's part the
         * leftover after the first pass is the fillet along one long edge plus
         * the place where the blend ring round the boss runs into it, and
         * growing simply merged the two again. The depth guard is what stops
         * this recursing on a patch that is not shrinking. */
        if (depth < kMaxSplitDepth)
            /* Past the crease stage on purpose. What RANSAC leaves is not a
             * smooth run any more, so cutting it at creases is arbitrary — on
             * the user's part it sliced the leftover fillet band into its own
             * facet rows, 3, 10, 10, 10, 7, 2, ... , and each row is too small
             * to say anything. Let RANSAC have the smaller set instead. */
            SplitPatch(m, rest, tol, scale, minTris, origin,
                       std::max(depth + 1, kMaxCreaseDepth), out);
        else
            SplitByFit(m, rest, tol, scale, minTris, origin, out);
        if (out.size() == before)
            out.push_back(pa);
        Retire(out);
        return;
    }
    SplitByFit(m, tris, tol, scale, minTris, origin, out);
    if (out.size() == before)
        out.push_back(pa);
    Retire(out);
}

/* Weight on the angular half of the boundary score, as a fraction of the part's
 * diagonal per unit of (1 - |cos|). Half a degree of disagreement then weighs
 * about as much as tolerance-sized distance does on a typical part. */
const double kBoundaryAngleWeight = 0.5;

/* Moves boundary triangles to whichever fitted surface actually describes them.
 *
 * Greedy growth leaves its seams in roughly the right place, not exactly. The
 * case that matters is a blend leaving a flat face: the first facet of the
 * blend is tangent, so it is within tolerance of the PLANE too and whichever
 * region got there first keeps it. When the plane keeps it, the planar face
 * reaches a facet past the true tangency and bulges out beyond the real
 * surface — about 1.2% of the volume of a filleted block, in the case that
 * found this.
 *
 * Deciding it by fit rather than by arrival order is both cheaper and more
 * honest than trying to grow perfectly: by the time this runs, both surfaces
 * exist and the triangle can simply be asked which one it is on. Distance
 * alone cannot answer at a tangency — both are zero there — so the direction
 * the surface goes has to carry the decision, which is why the score mixes the
 * two. */
/* A surface explains the triangles whose normals it predicts and whose points
 * it passes through. The rest are not its, however close they happen to lie.
 *
 * Two of the three defects the user could see in the rebuilt part were this
 * one thing, twice.
 *
 * The 5 mm hole has four radial slits cut through the lower half of its wall,
 * and wall and slits arrive as one patch because the slits are too narrow for
 * the splitter to find a better cut. The cylinder fitted to that patch is
 * exactly right — radius 2.5010 where the part was drawn at 2.5. It was thrown
 * away all the same, on normals: the ten slit-wall facets stand at up to
 * seventy degrees to the barrel they are cut into and they drag the mean past
 * the bar. The hole then came out as thirty little planes.
 *
 * The long edge is rounded at r = 1, and where the boss's blend ring runs over
 * it there is a short stretch belonging to neither. Those few facets sit in
 * the fillet's patch and pull its axis half a tenth of a millimetre out of
 * true — inside tolerance, nowhere near exact, and rejected for it. Three of
 * the four segments of that edge came back as triangles.
 *
 * In both cases the evidence was never mixed, only summed. Per triangle it
 * separates cleanly: on the hole, a median of 3.9 degrees, three quarters
 * under fifteen, and ten outliers above thirty. So cut where the evidence
 * says. The triangles the surface accounts for stay with it; the ones it does
 * not go back through the splitter as a patch of their own, where the slit
 * walls are recognised as the planes they are and the transition strip becomes
 * its own small face.
 *
 * Iterated, because the strays bias the very fit used to find them: drop the
 * worst, fit again, and repeat while the surface keeps getting better. And
 * only ever when the strays are a MINORITY — if half a patch disagrees, the
 * surface is the thing in doubt and trimming it to fit would be inventing
 * evidence rather than reading it. */
void TrimStrays(const Mesh &m, std::vector<Patch> &patches, double tol,
                double scale, int minTris)
{
    const size_t n0 = patches.size();
    std::vector<Patch> extra;
    std::vector<int> local(m.triCount(), -1);
    const double h = std::max(scale * 1e-5, 1e-9);
    const double exactBar = tol * kExactFitFraction;
    PatchData pd;

    for (size_t i = 0; i < n0; ++i) {
        Patch &pa = patches[i];
        if (pa.fit.kind == kNone ||
            static_cast<int>(pa.tris.size()) < kMinTrustTriangles)
            continue;
        const double allowedAng = AgreementAllowed(pa, m);
        const bool badAng =
            std::acos(std::max(-1.0, std::min(1.0, pa.fit.agree))) > allowedAng;
        const bool badRms = pa.fit.rms > exactBar;
        if (!badAng && !badRms)
            continue; /* the surface already answers for everything it has */

        const std::vector<int> tris = pa.tris;
        const size_t floorCount = std::max<size_t>(
            kMinTrustTriangles,
            static_cast<size_t>(tris.size() * kTrimKeepFraction));
        std::vector<char> keep(tris.size(), 1);
        Fit cur = pa.fit;
        size_t nKeep = tris.size();
        bool clean = false;

        for (int round = 0; round < kTrimRounds; ++round) {
            std::vector<double> dist(tris.size(), 0.0), ang(tris.size(), 0.0);
            std::vector<double> live;
            live.reserve(nKeep);
            for (size_t k = 0; k < tris.size(); ++k) {
                if (!keep[k])
                    continue;
                const int t = tris[k];
                V3 c;
                double w = 0;
                for (int j = 0; j < 3; ++j) {
                    const V3 &q = m.pos[m.tri[t * 3 + j]];
                    c += q;
                    w = std::max(w, std::fabs(SurfDist(cur.kind, cur.q, q)));
                }
                dist[k] = w;
                const V3 sn = SurfNormal(cur.kind, cur.q, c * (1.0 / 3.0), h);
                ang[k] = (Norm(sn) > 0.5)
                             ? std::acos(std::max(
                                   -1.0,
                                   std::min(1.0, std::fabs(
                                                     Dot(sn, m.tnorm[t])))))
                             : M_PI;
                live.push_back(w);
            }
            std::sort(live.begin(), live.end());
            const double med = live.empty() ? 0.0 : live[live.size() / 2];
            const double distBar = std::max(exactBar, med * kTrimDistFactor);

            size_t strays = 0;
            double keptArea = 0, strayArea = 0;
            std::vector<char> next = keep;
            for (size_t k = 0; k < tris.size(); ++k) {
                if (!keep[k])
                    continue;
                if (ang[k] > allowedAng || dist[k] > distBar) {
                    next[k] = 0;
                    strays++;
                    strayArea += m.tarea[tris[k]];
                } else {
                    keptArea += m.tarea[tris[k]];
                }
            }
            if (strays == 0) {
                clean = (cur.rms <= exactBar &&
                         std::acos(std::max(
                             -1.0, std::min(1.0, cur.agree))) <= allowedAng);
                break;
            }
            if (nKeep - strays < floorCount)
                break; /* too much of it disagrees to call the rest the truth */
            (void)keptArea;
            (void)strayArea;
            keep.swap(next);
            nKeep -= strays;

            std::vector<int> liveTris;
            liveTris.reserve(nKeep);
            for (size_t k = 0; k < tris.size(); ++k)
                if (keep[k])
                    liveTris.push_back(tris[k]);
            PatchPoints(m, liveTris, pd, 4000);
            const Fit f = FitPatch(pd, tol, scale);
            if (f.kind == kNone)
                break;
            cur = f;
            if (cur.rms <= exactBar &&
                std::acos(std::max(-1.0, std::min(1.0, cur.agree))) <=
                    allowedAng) {
                clean = true;
                break;
            }
        }
        if (!clean || nKeep == tris.size())
            continue;

        /* Connected pieces, so that no face comes out in two halves. */
        for (size_t k = 0; k < tris.size(); ++k)
            local[tris[k]] = static_cast<int>(k);
        std::vector<int> comp(tris.size(), -1), stack;
        int nComp = 0;
        for (size_t k = 0; k < tris.size(); ++k) {
            if (comp[k] >= 0)
                continue;
            stack.assign(1, static_cast<int>(k));
            comp[k] = nComp;
            while (!stack.empty()) {
                const int at = stack.back();
                stack.pop_back();
                for (int j = 0; j < 3; ++j) {
                    const int o = m.adj[tris[at] * 3 + j];
                    if (o < 0)
                        continue;
                    const int li = local[o];
                    if (li < 0 || comp[li] >= 0 || keep[li] != keep[at])
                        continue;
                    comp[li] = nComp;
                    stack.push_back(li);
                }
            }
            nComp++;
        }
        for (int t : tris)
            local[t] = -1;
        if (nComp < 2)
            continue;

        std::vector<std::vector<int>> pieces(nComp);
        for (size_t k = 0; k < tris.size(); ++k)
            pieces[comp[k]].push_back(tris[k]);
        /* Every piece goes back through the splitter, the kept ones included:
         * a barrel with its slit walls taken out may still be two barrels. */
        std::vector<Patch> made;
        for (const std::vector<int> &piece : pieces)
            SplitPatch(m, piece, tol, scale, minTris, pa.origin, 0, made);
        if (made.empty())
            continue;
        MR_TRACE("  patch %3d trimmed: %d tri -> %d kept, %d pieces -> %d "
                 "patches (rms %.5f -> %.5f)\n",
                 (int)i, (int)tris.size(), (int)nKeep, nComp, (int)made.size(),
                 pa.fit.rms, cur.rms);
        patches[i] = made[0];
        for (size_t k = 1; k < made.size(); ++k)
            extra.push_back(made[k]);
    }
    for (Patch &e : extra)
        patches.push_back(e);
}

void RefineBoundaries(const Mesh &m, std::vector<Patch> &patches, double tol,
                      double scale, int passes)
{
    const int n = static_cast<int>(patches.size());
    if (n < 2)
        return;
    const double h = std::max(scale * 1e-5, 1e-9);
    PatchData pd;

    /* How badly patch `pi` describes triangle `t`. Length units throughout, so
     * the two halves are comparable: the angular term is scaled by the part
     * size to become a distance. */
    auto score = [&](int pi, int t) -> double {
        const Fit &f = patches[pi].fit;
        if (f.kind == kNone)
            return 1e300;
        double worst = 0;
        V3 c;
        for (int k = 0; k < 3; ++k) {
            const V3 &p = m.pos[m.tri[t * 3 + k]];
            c += p;
            worst = std::max(worst, std::fabs(SurfDist(f.kind, f.q, p)));
        }
        const V3 sn = SurfNormal(f.kind, f.q, c * (1.0 / 3.0), h);
        const double agree =
            (Norm(sn) > 0.5) ? std::fabs(Dot(sn, m.tnorm[t])) : 0.0;
        return worst + scale * kBoundaryAngleWeight * (1.0 - agree);
    };

    for (int pass = 0; pass < passes; ++pass) {
        std::vector<int> patchOf(m.triCount(), -1);
        for (int i = 0; i < n; ++i) {
            for (int t : patches[i].tris)
                patchOf[t] = i;
        }
        std::vector<std::pair<int, int>> moves; /* (triangle, new patch) */
        std::vector<int> sizes(n);
        for (int i = 0; i < n; ++i)
            sizes[i] = static_cast<int>(patches[i].tris.size());

        for (int t = 0; t < m.triCount(); ++t) {
            const int own = patchOf[t];
            if (own < 0 || patches[own].fit.kind == kNone)
                continue;
            double mine = score(own, t);
            int bestP = -1;
            double best = mine;
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0)
                    continue;
                const int q = patchOf[o];
                if (q < 0 || q == own)
                    continue;
                /* Only ever move within one smooth patch, for the same reason
                 * MergeRegions does: a sharp edge is a real boundary and no
                 * amount of good fit on the far side changes that. */
                if (patches[q].origin < 0 ||
                    patches[q].origin != patches[own].origin) {
                    continue;
                }
                const double sc = score(q, t);
                if (sc < best) {
                    best = sc;
                    bestP = q;
                }
            }
            /* A clear win only, and never the last triangle of a patch. */
            if (bestP >= 0 && best < mine * 0.5 && sizes[own] > 1) {
                moves.emplace_back(t, bestP);
                sizes[own]--;
                sizes[bestP]++;
            }
        }
        if (moves.empty())
            return;

        for (const std::pair<int, int> &mv : moves)
            patchOf[mv.first] = mv.second;
        std::vector<std::vector<int>> rebuilt(n);
        for (int t = 0; t < m.triCount(); ++t) {
            if (patchOf[t] >= 0)
                rebuilt[patchOf[t]].push_back(t);
        }
        for (int i = 0; i < n; ++i) {
            if (rebuilt[i].size() == patches[i].tris.size())
                continue;
            patches[i].tris.swap(rebuilt[i]);
            if (patches[i].tris.empty())
                continue;
            PatchPoints(m, patches[i].tris, pd, 4000);
            const Fit f = FitPatch(pd, tol, scale);
            if (f.kind != kNone)
                patches[i].fit = f;
        }
        std::vector<Patch> keep;
        keep.reserve(patches.size());
        for (Patch &pa : patches) {
            if (!pa.tris.empty())
                keep.push_back(std::move(pa));
        }
        patches.swap(keep);
        if (static_cast<int>(patches.size()) != n)
            return; /* sizes moved; stop */
    }
}

/* How well a merged surface's normals must follow the mesh's before two
 * patches are put together: about 8 degrees of mean slack, against the 25 the
 * first-pass classifier allows. */
const double kMergeNormalGate = 0.99;

/* Merges neighbouring patches that turn out to share one surface.
 *
 * The repair pass for greedy growth, and the thing that finally recovers a
 * fillet. Growing from a seed cannot see a tangent seam, so a 3 mm blend comes
 * out as three or four planar slivers, each of which honestly fits a plane over
 * its own two facets. Fitting the UNION of two of them finds the cylinder they
 * were always part of, and one merge makes the next one easier. Sweeping
 * smallest-first means slivers get absorbed into real surfaces rather than real
 * surfaces into each other.
 *
 * The tolerance gate is what keeps this safe: a merge only happens when ONE
 * primitive describes both patches to within the same tolerance every other
 * stage uses, so two perpendicular faces of a box are never candidates. */
/* Which smooth runs are FREEFORM rather than prismatic.
 *
 * Asked once per run, not once per piece, because the splitter always
 * succeeds: a quad of a quad-meshed surface is exactly planar, so a plane
 * through it has no residual at all and passes every per-piece test there is —
 * correctly, since two triangles really is a box's face. On a 2676-triangle
 * organic shell that produced 129 invented planes and 3 spheres, none of which
 * exists.
 *
 * What separates them is the run. A prismatic run is ACCOUNTED FOR: its pieces
 * are faces and they cover it. A freeform run is not — most of it fits nothing
 * and what does fit is facet-sized. A plate's side band, four fillets and four
 * walls, is covered to the last triangle and is never touched.
 *
 * It is worth knowing EARLY as well as late. Everything downstream of
 * segmentation — merging pairs, refining boundaries, building faces — is
 * per-patch work on a run that is about to be thrown away whole, and on an
 * organic model that is nearly all of the time the conversion takes: 3.5
 * seconds of merging on a 3480-triangle blob, against 0.4 for the faceted
 * build that is the eventual answer. */
void FreeformRuns(const std::vector<Patch> &patches, const Mesh &m, double tol,
                  std::unordered_set<int> &freeform)
{
    freeform.clear();
    std::unordered_map<int, int> cutInto;
    for (const Patch &pa : patches)
        cutInto[pa.origin]++;
    std::unordered_map<int, std::pair<int, int>> cover; /* kept, total */
    std::unordered_map<int, std::vector<int>> keptSizes;
    for (const Patch &pa : patches) {
        if (pa.origin < 0)
            continue;
        std::pair<int, int> &c = cover[pa.origin];
        c.second += static_cast<int>(pa.tris.size());
        const bool frag = cutInto[pa.origin] > 1;
        const bool id = pa.fit.kind != kNone && Identifiable(pa, m, tol, frag);
        if (pa.tris.size() >= 8)
            MR_TRACE("     run %d piece %4d tri %-7s rms %.6f -> %s (%s)\n",
                     pa.origin, (int)pa.tris.size(), KindName(pa.fit.kind),
                     pa.fit.rms, id ? "keep" : "drop",
#ifdef MESHRECON_TRACE
                     g_why
#else
                     ""
#endif
            );
        if (id) {
            c.first += static_cast<int>(pa.tris.size());
            keptSizes[pa.origin].push_back(static_cast<int>(pa.tris.size()));
        }
    }
    for (std::unordered_map<int, std::pair<int, int>>::iterator it =
             cover.begin();
         it != cover.end(); ++it) {
        const int kept = it->second.first, total = it->second.second;
        if (total < kFreeformMinRun || kept * 2 >= total)
            continue;
        std::vector<int> &sz = keptSizes[it->first];
        if (sz.empty()) {
            freeform.insert(it->first);
            continue;
        }
        /* Barely accounted for at all: freeform whatever the pieces look like.
         * A run that is 98% triangles is not a set of faces with a few gaps,
         * and the two or three surfaces standing in it are worth less than the
         * seams they cost. */
        if (kept * kFreeformCoverDenom < total) {
            freeform.insert(it->first);
            continue;
        }
        /* And most of what IS explained has to be scraps.
         *
         * The median piece size looked like the right statistic and is not: a
         * run can be mostly triangles and still contain one real face, and
         * then the median is dominated by the scraps beside it. On the user's
         * part the blend ring round the boss on the underside — a torus, 87
         * triangles, residual zero — shared its run with sixteen one-triangle
         * offcuts, so the median said "facet-sized" and the whole run, ring
         * included, went to triangles. Weigh by triangles instead: 87 of the
         * 106 explained are that one ring, so the run is not scrap. */
        int scrap = 0;
        for (int x : sz)
            if (x < kFreeformPieceTriangles)
                scrap += x;
        if (scrap * 2 > kept)
            freeform.insert(it->first);
    }
    MR_TRACE("  [freeform] %d of %d runs\n", (int)freeform.size(),
             (int)cover.size());
    for (std::unordered_map<int, std::pair<int, int>>::iterator it =
             cover.begin();
         it != cover.end(); ++it)
        MR_TRACE("     run %d: kept %d of %d in %d pieces%s\n", it->first,
                 it->second.first, it->second.second,
                 (int)keptSizes[it->first].size(),
                 freeform.count(it->first) ? "  FREEFORM" : "");
}

void MergeRegions(const Mesh &m, std::vector<Patch> &patches, double tol,
                  double scale, int maxPasses,
                  const std::unordered_set<int> &skipOrigins)
{
    PatchData pd;
    for (int pass = 0; pass < maxPasses; ++pass) {
        const int n = static_cast<int>(patches.size());
        if (n < 2)
            return;
        std::vector<int> patchOf(m.triCount(), -1);
        for (int i = 0; i < n; ++i) {
            for (int t : patches[i].tris)
                patchOf[t] = i;
        }
        /* Which patches touch which. */
        std::vector<std::pair<int, int>> pairs;
        {
            std::vector<long long> seen;
            seen.reserve(m.tri.size());
            for (int t = 0; t < m.triCount(); ++t) {
                const int a = patchOf[t];
                if (a < 0)
                    continue;
                for (int k = 0; k < 3; ++k) {
                    const int o = m.adj[t * 3 + k];
                    if (o < 0)
                        continue;
                    const int b = patchOf[o];
                    if (b < 0 || b == a)
                        continue;
                    seen.push_back(static_cast<long long>(std::min(a, b)) * n +
                                   std::max(a, b));
                }
            }
            std::sort(seen.begin(), seen.end());
            seen.erase(std::unique(seen.begin(), seen.end()), seen.end());
            pairs.reserve(seen.size());
            for (long long k : seen) {
                pairs.emplace_back(static_cast<int>(k / n),
                                   static_cast<int>(k % n));
            }
        }
        if (pairs.empty())
            return;
        /* Smallest first. */
        std::sort(
            pairs.begin(), pairs.end(),
            [&](const std::pair<int, int> &x, const std::pair<int, int> &y) {
                const size_t sx = std::min(patches[x.first].tris.size(),
                                           patches[x.second].tris.size());
                const size_t sy = std::min(patches[y.first].tris.size(),
                                           patches[y.second].tris.size());
                if (sx != sy)
                    return sx < sy;
                return x < y; /* a TOTAL order; see "Ties decide the model" */
            });

        std::vector<int> mergedInto(n, -1);
        std::vector<char> touched(n, 0);
        bool changed = false;
        std::vector<int> uni;
        for (const std::pair<int, int> &pr : pairs) {
            const int a = pr.first, b = pr.second;
            if (touched[a] || touched[b])
                continue;
            if (mergedInto[a] >= 0 || mergedInto[b] >= 0)
                continue;
            /* Only ever reunite what one smooth patch was cut into.
             *
             * Without this the pass is not a repair, it is a demolition. A
             * box's eight corners lie EXACTLY on their circumsphere, so a
             * sphere fits six merged faces with zero residual and normals that
             * agree to within six degrees — and the box becomes a ball. A
             * cylinder's cap and barrel go the same way. A sharp edge is a
             * feature boundary and nothing on the far side of one belongs to
             * this surface, however well it fits. */
            if (patches[a].origin < 0 ||
                patches[a].origin != patches[b].origin) {
                continue;
            }
            /* And nothing at all inside a run already judged freeform: every
             * pair there costs a full five-kind fit and every one of them
             * fails. */
            if (skipOrigins.find(patches[a].origin) != skipOrigins.end())
                continue;
            uni.clear();
            uni.reserve(patches[a].tris.size() + patches[b].tris.size());
            uni.insert(uni.end(), patches[a].tris.begin(),
                       patches[a].tris.end());
            uni.insert(uni.end(), patches[b].tris.begin(),
                       patches[b].tris.end());
            PatchPoints(m, uni, pd, 4000);
            const Fit f = FitPatch(pd, tol, scale);
            MR_TRACE("  merge? %d(%s,%d) + %d(%s,%d) -> %s rms %.5f agree "
                     "%.4f (tol %.5f)\n",
                     a, KindName(patches[a].fit.kind),
                     (int)patches[a].tris.size(), b,
                     KindName(patches[b].fit.kind),
                     (int)patches[b].tris.size(), KindName(f.kind), f.rms,
                     f.agree, tol);
            if (f.kind == kNone || f.rms > tol)
                continue;
            /* Merging is never obligatory, so it should only happen on strong
             * evidence. The residual alone is not strong: a side face and the
             * first facets of the blend leaving it are fitted to within
             * tolerance by a sphere the size of a small planet, and merging on
             * that turns four flat faces and four fillets into four spheres.
             * Demanding that the merged surface also POINT the way the mesh
             * does, and much more strictly than the first-pass classifier
             * does, is what tells a real shared surface from a coincidence. */
            /* An EXACT merged fit is believed on its residual instead.
             *
             * The normal gate is a proxy for "is this really one surface", and
             * it is the right proxy when the fit is approximate. When the fit
             * is exact it is the weaker evidence of the two, and it says no to
             * things that are plainly true: two adjacent rows of a boss's
             * fillet ring merged into a torus at residual 0.0000000 — the
             * fillet, exactly — with mean normal agreement 0.9872, and were
             * kept apart by a bar of 0.99. Their coarse facet normals cannot
             * agree better than that; the surface underneath them is still the
             * torus. The facet test below is what keeps this honest. */
            const bool mergedExact = f.rms <= tol * kExactFitFraction;
            if (!mergedExact && f.agree < kMergeNormalGate)
                continue;
            /* Merging two surfaces that were each already RECOGNISED must not
             * make the fit worse than either of them was.
             *
             * The pass exists to reunite one surface that the splitter cut in
             * two, and there the union fits exactly, because both halves did.
             * When it instead joins two DIFFERENT surfaces the union fits only
             * loosely — and loosely is still inside tolerance, which is why
             * the residual gate alone let it through. Measured: an r=5 corner
             * fillet (32 triangles, cylinder, residual zero) merged with the
             * two triangles of the flat wall it is tangent to (plane, residual
             * zero) and came back as a torus at 0.0102, wrapped around a major
             * radius of 15 mm that is nowhere in the part; trimmed, it added
             * 42% to the model's volume. Neither half was improved by the
             * merge, and that is exactly what the test should say.
             *
             * A patch that fitted NOTHING has nothing to lose, so the repair
             * case this pass was written for is untouched. */
            /* And the merged surface must pass through the FACETS of both,
             * not merely their vertices — the same test the fitter and RANSAC
             * apply, and for the same reason: this is where a torus threaded
             * through a fillet and the flat wall beside it gives itself away. */
            {
                bool bulges = false;
                const int st = std::max<int>(1, (int)uni.size() / 256);
                for (size_t i = 0; i < uni.size() && !bulges; i += st) {
                    double bar = 0;
                    if (FacetBulge(f.kind, f.q, m, uni[i], bar) >
                        std::max(bar, tol))
                        bulges = true;
                }
                if (bulges)
                    continue;
            }
            if (patches[a].fit.kind != kNone && patches[b].fit.kind != kNone) {
                const double worse =
                    std::max(patches[a].fit.rms, patches[b].fit.rms);
                if (f.rms > std::max(worse, tol * kExactFitFraction))
                    continue;
            }
            patches[a].tris.swap(uni);
            patches[a].fit = f;
            patches[a].origin = patches[b].origin;
            patches[b].tris.clear();
            mergedInto[b] = a;
            touched[a] = touched[b] = 1;
            changed = true;
        }
        /* Drop the emptied patches. */
        std::vector<Patch> keep;
        keep.reserve(patches.size());
        for (Patch &p : patches) {
            if (!p.tris.empty())
                keep.push_back(std::move(p));
        }
        patches.swap(keep);
        if (!changed)
            return;
    }
}

/* ====================================================================== */
/* Regularisation — where "design intent" comes from                      */
/* ====================================================================== */

/* Snaps `d` to the nearest global axis, or to an already-agreed direction,
 * when it is within `cosTol` of one. Returns true when it moved. */
bool SnapDirection(V3 &d, const std::vector<V3> &agreed, double cosTol)
{
    const V3 globals[3] = {V3(1, 0, 0), V3(0, 1, 0), V3(0, 0, 1)};
    for (int i = 0; i < 3; ++i) {
        const double c = Dot(d, globals[i]);
        if (std::fabs(c) >= cosTol) {
            d = c >= 0 ? globals[i] : globals[i] * -1.0;
            return true;
        }
    }
    for (const V3 &a : agreed) {
        const double c = Dot(d, a);
        if (std::fabs(c) >= cosTol) {
            d = c >= 0 ? a : a * -1.0;
            return true;
        }
    }
    return false;
}

/* Makes the fitted surfaces agree with each other.
 *
 * A fit is an independent estimate per patch, so a part whose faces are
 * genuinely parallel comes back with twelve normals a tenth of a degree apart
 * and eight cylinders of radius 5.0013, 4.9987, 5.0004. Every downstream
 * operation — a boolean, a fillet, a STEP export someone opens in Inventor —
 * is worse for that. This pass is what makes the output look like a part
 * somebody modelled rather than a part somebody measured. */
/* Pieces of ONE surface, fitted together.
 *
 * A fillet along an edge is not interrupted because a boss blend crosses it —
 * it is one cylinder, cut into four faces by what runs over it. Fitted apart,
 * each of those four sees a fraction of the evidence: the user's part has its
 * long edge rounded at r = 1 about the line x = -9, z = -1, and the four
 * fragments put that axis at z = -0.948, -0.983, -0.958 and -0.940 — every one
 * of them inside tolerance, not one of them exact, and three of the four were
 * thrown out for it. The +x edge, whose fragments happened to land closer,
 * survived. Two rounded edges where there should be one is what that looks
 * like on screen.
 *
 * Nothing about the evidence was weak; it was only divided. Surfaces that
 * agree on direction, on radius and on where their axis LIES are one surface,
 * so fit them as one and give every piece the answer. A piece then also stands
 * on the whole group's triangles rather than its own five, which is the other
 * half of why the small ones were being lost. */
void Consolidate(std::vector<Patch> &patches, const Mesh &m, const Params &prm,
                 double tol, double scale)
{
    if (!(prm.snap_radius_frac > 0) || !(prm.snap_deg > 0))
        return;
    const double rTol = scale * prm.snap_radius_frac;
    const double cosTol = std::cos(prm.snap_deg * M_PI / 180.0);

    std::vector<int> cyl;
    for (size_t i = 0; i < patches.size(); ++i)
        if (patches[i].fit.kind == kCylinder)
            cyl.push_back(static_cast<int>(i));

    std::vector<char> done(cyl.size(), 0);
    PatchData pd;
    for (size_t a = 0; a < cyl.size(); ++a) {
        if (done[a])
            continue;
        const Fit &fa = patches[cyl[a]].fit;
        const V3 axA = Unit(V3(fa.q[3], fa.q[4], fa.q[5]));
        const V3 ptA(fa.q[0], fa.q[1], fa.q[2]);
        std::vector<int> group(1, cyl[a]);
        done[a] = 1;
        for (size_t b = a + 1; b < cyl.size(); ++b) {
            if (done[b])
                continue;
            const Fit &fb = patches[cyl[b]].fit;
            const V3 axB = Unit(V3(fb.q[3], fb.q[4], fb.q[5]));
            if (std::fabs(Dot(axA, axB)) < cosTol)
                continue;
            if (std::fabs(fb.q[6] - fa.q[6]) > rTol)
                continue;
            /* The same axis LINE, not merely a parallel one: four holes drilled
             * on the same bolt circle share a direction and a radius and are
             * four different holes. */
            const V3 off(fb.q[0] - ptA.x, fb.q[1] - ptA.y, fb.q[2] - ptA.z);
            const double along = Dot(off, axA);
            const double perp2 =
                Dot(off, off) - along * along;
            if (perp2 > rTol * rTol)
                continue;
            group.push_back(cyl[b]);
            done[b] = 1;
        }
        if (group.size() < 2)
            continue;

        /* One fit over everything the group has seen. */
        std::vector<int> all;
        for (int g : group)
            all.insert(all.end(), patches[g].tris.begin(),
                       patches[g].tris.end());
        PatchPoints(m, all, pd, 8000);
        /* Start from whichever member already explains the whole group best,
         * not from whichever happens to be first. */
        double q2[8];
        double joint = 1e300;
        for (int g : group) {
            const double r = FitRms(kCylinder, patches[g].fit.q, pd.pts);
            if (r < joint) {
                joint = r;
                std::memcpy(q2, patches[g].fit.q, sizeof(q2));
            }
        }
        /* Slide the axis POINT to the group's centroid before refining. A
         * cylinder has five degrees of freedom described by seven numbers, and
         * one of the two spare ones is the point's position along the axis:
         * left where it was, a hundred and forty millimetres up the line from
         * anything it describes, the refiner has a nearly-null direction to
         * wander in and it does — the first attempt at this came back with the
         * radius moved from 0.9998 to 0.9726 and the residual ten times
         * worse. */
        {
            V3 c;
            Centroid(pd.pts, c);
            const V3 ax = Unit(V3(q2[3], q2[4], q2[5]));
            const V3 off(c.x - q2[0], c.y - q2[1], c.z - q2[2]);
            const double along = Dot(off, ax);
            q2[0] += ax.x * along;
            q2[1] += ax.y * along;
            q2[2] += ax.z * along;
        }
        {
            double q3[8];
            std::memcpy(q3, q2, sizeof(q3));
            bool freeMask[8];
            for (int k = 0; k < 8; ++k)
                freeMask[k] = true;
            RefineFit(kCylinder, q3, pd.pts, scale, freeMask);
            Renormalise(kCylinder, q3);
            const double refined = FitRms(kCylinder, q3, pd.pts);
            if (refined < joint) {
                std::memcpy(q2, q3, sizeof(q2));
                joint = refined;
            }
        }
        const int ev = static_cast<int>(all.size());
        MR_TRACE("  consolidate %d cylinders r=%.4f: joint rms %.5f over %d "
                 "tri\n",
                 (int)group.size(), q2[6], joint, ev);
        for (int g : group) {
            Patch &pg = patches[g];
            PatchPoints(m, pg.tris, pd, 4000);
            const double mine = FitRms(kCylinder, q2, pd.pts);
            /* Only where the group's answer is at least as good on this
             * patch's own triangles as the patch's private one — and then the
             * evidence behind it is the group's, not this patch's five facets.
             *
             * (Handing every member the group's evidence regardless was tried
             * and measured: it recovers two more segments of the user's long
             * edge and costs the shell — those segments are five-facet slivers
             * whose faces will not sew to the one-triangle planes beside them,
             * and the part came back an open shell at -0.20% instead of a
             * closed solid at +0.21%. A body that closes is worth more than
             * two faces that do not.) */
            if (mine <= std::max(pg.fit.rms, tol * kExactFitFraction)) {
                std::memcpy(pg.fit.q, q2, sizeof(q2));
                pg.fit.rms = mine;
                pg.fit.agree = NormalAgreement(kCylinder, q2, pd.spos, pd.snrm,
                                               scale);
                pg.evidence = ev;
            }
        }
    }
}

/* Two patches of one smooth run whose surfaces this mesh cannot tell apart.
 *
 * The splitter grows greedily, so a long fillet comes out as several pieces,
 * and a piece that straddles the fillet and the transition leaving it fits a
 * cylinder tilted a few degrees off the fillet's own axis — exactly, on its
 * own seven facets, and wrong. Nothing about that piece alone refutes it: its
 * residual is zero because the surface was fitted to it. What refutes it is
 * the forty millimetres of the same fillet on either side, measured at
 * radius 0.9998 about an axis that does not tilt.
 *
 * Refitting the union is NOT the answer, and this is why the pass is separate
 * from MergeRegions: the union is the fillet PLUS the transition, and fitting
 * it drags the radius of a forty-millimetre edge from 1.0000 to 0.9524 to
 * accommodate a strip three millimetres long. Measured on the user's part.
 *
 * So do not refit. Ask instead whether the better-witnessed of the two
 * surfaces already describes the other's triangles to within the tolerance the
 * whole pipeline works to, pointing the way the mesh does; if it does, the two
 * are one surface as far as this mesh can say, and the one with the evidence
 * keeps its numbers and takes the triangles. The user's top edge goes from
 * three faces with a four-degree kink between them to one, and its radius
 * stays the radius it was drawn with. */
void AdoptStronger(const Mesh &m, std::vector<Patch> &patches, double tol,
                   double scale)
{
    const double h = std::max(scale * 1e-5, 1e-9);
    const double exactBar = tol * kExactFitFraction;
    auto weight = [](const Patch &p) {
        return std::max(static_cast<int>(p.tris.size()), p.evidence);
    };

    for (int pass = 0; pass < 6; ++pass) {
        std::vector<int> own(m.triCount(), -1);
        for (size_t i = 0; i < patches.size(); ++i)
            for (int t : patches[i].tris)
                own[t] = static_cast<int>(i);
        std::vector<std::pair<int, int>> pairs;
        for (int t = 0; t < m.triCount(); ++t) {
            const int a = own[t];
            if (a < 0)
                continue;
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0)
                    continue;
                const int b = own[o];
                if (b < 0 || b == a)
                    continue;
                pairs.emplace_back(std::min(a, b), std::max(a, b));
            }
        }
        std::sort(pairs.begin(), pairs.end());
        pairs.erase(std::unique(pairs.begin(), pairs.end()), pairs.end());

        std::vector<double> allowed(patches.size(), -1.0);
        auto allowanceOf = [&](int i) {
            if (allowed[i] < 0)
                allowed[i] = AgreementAllowed(patches[i], m);
            return allowed[i];
        };
        /* Does A's surface account for every triangle B has? */
        auto explains = [&](int ai, int bi) {
            const Fit &f = patches[ai].fit;
            const double allow = allowanceOf(ai);
            for (int t : patches[bi].tris) {
                V3 c;
                for (int q = 0; q < 3; ++q) {
                    const V3 &p = m.pos[m.tri[t * 3 + q]];
                    c += p;
                    if (std::fabs(SurfDist(f.kind, f.q, p)) > tol)
                        return false;
                }
                const V3 sn = SurfNormal(f.kind, f.q, c * (1.0 / 3.0), h);
                if (Norm(sn) < 0.5)
                    return false;
                const double ang = std::acos(std::max(
                    -1.0, std::min(1.0, std::fabs(Dot(sn, m.tnorm[t])))));
                if (ang > allow)
                    return false;
            }
            return true;
        };

        bool changed = false;
        std::vector<char> gone(patches.size(), 0);
        for (const std::pair<int, int> &pr : pairs) {
            if (gone[pr.first] || gone[pr.second])
                continue;
            const Patch &p0 = patches[pr.first];
            const Patch &p1 = patches[pr.second];
            if (p0.fit.kind == kNone || p0.fit.kind != p1.fit.kind)
                continue;
            /* Same smooth run only, as everywhere else: a sharp edge is a real
             * boundary and nothing across one is the same surface. */
            if (p0.origin < 0 || p0.origin != p1.origin)
                continue;
            int a = pr.first, b = pr.second;
            if (weight(p1) > weight(p0))
                std::swap(a, b);
            /* Equal weight is not a reason to leave two faces on one surface.
             *
             * It is the signature of ONE region the splitter cut in two, which
             * is the case this pass exists for. What "nothing to choose
             * between them" should mean is that either would do — so ask
             * whether they are interchangeable: if each one's surface accounts
             * for the other's triangles, adopting in either direction costs
             * nothing and saves a seam, and if they are not the same surface
             * the one-way test below already says no.
             *
             * On the user's bracket the top-edge fillet on one side arrives as
             * two halves of one 30-triangle region carrying byte-identical
             * cylinders, because the boss blend crossing it pulls a few
             * vertices off true in the middle. Left apart they are two faces
             * on one surface that overlap for 1.9 mm across the crossing —
             * two rounded edges drawn over each other, which is what the user
             * sees. The other side of the same part is one face, and the only
             * difference is which way this tie fell. */
            if (weight(patches[a]) <= weight(patches[b]) && !explains(b, a))
                continue;
            /* The stronger surface must not be the LOOSER one: adopting it
             * would trade an exact surface for an approximate one, which is
             * the opposite of what this is for. */
            if (patches[a].fit.rms >
                std::max(patches[b].fit.rms, exactBar))
                continue;
            if (!explains(a, b))
                continue;
            /* And only where there is a disagreement to settle.
             *
             * When A explains B EXACTLY, B is simply a piece of A that the
             * splitter cut off: the two carry the same surface, their faces
             * meet along it seamlessly, and putting them together changes
             * nothing anyone can see. It does change the topology, and badly —
             * five exact segments of the user's centre hole, joined, wrap the
             * whole way round, and a full wrap has no boundary to build a face
             * from, so the radial slits cut through it disappeared and the
             * part came back five percent light.
             *
             * The case this pass is for is the other one: A explains B to
             * within tolerance but NOT exactly, which is what it looks like
             * when B's own surface has been pulled off true by triangles that
             * belong to neither. */
            {
                PatchData bd;
                PatchPoints(m, patches[b].tris, bd, 4000);
                if (FitRms(patches[a].fit.kind, patches[a].fit.q, bd.pts) <=
                    exactBar)
                    continue;
            }
            MR_TRACE("  patch %3d (%s, %d tri) adopts %3d (%d tri): one "
                     "surface\n",
                     a, KindName(patches[a].fit.kind),
                     (int)patches[a].tris.size(), b,
                     (int)patches[b].tris.size());
            patches[a].tris.insert(patches[a].tris.end(),
                                   patches[b].tris.begin(),
                                   patches[b].tris.end());
            patches[a].evidence =
                std::max(patches[a].evidence,
                         static_cast<int>(patches[a].tris.size()));
            patches[b].tris.clear();
            gone[b] = 1;
            changed = true;
        }
        std::vector<Patch> keep;
        keep.reserve(patches.size());
        for (Patch &p : patches)
            if (!p.tris.empty())
                keep.push_back(std::move(p));
        patches.swap(keep);
        if (!changed)
            return;
    }
}

void Regularise(std::vector<Patch> &patches, const Mesh &m, const Params &prm,
                double tol, double scale)
{
    if (!(prm.snap_deg > 0))
        return;
    const double cosTol = std::cos(prm.snap_deg * M_PI / 180.0);

    /* Pass 1 — directions. Largest patches first, so the big faces set the
     * convention and the small ones follow it rather than the reverse. */
    std::vector<int> order;
    for (size_t i = 0; i < patches.size(); ++i) {
        if (patches[i].fit.kind != kNone)
            order.push_back(static_cast<int>(i));
    }
    std::sort(order.begin(), order.end(), [&](int a, int b) {
        if (patches[a].tris.size() != patches[b].tris.size())
            return patches[a].tris.size() > patches[b].tris.size();
        return a < b; /* a TOTAL order; see "Ties decide the model" */
    });

    std::vector<V3> agreed;
    PatchData pd;
    for (int i : order) {
        Fit &f = patches[i].fit;
        const int dirOff =
            (f.kind == kPlane)                                             ? 0
            : (f.kind == kCylinder || f.kind == kCone || f.kind == kTorus) ? 3
                                                                           : -1;
        if (dirOff < 0)
            continue;
        V3 d = Unit(V3(f.q[dirOff], f.q[dirOff + 1], f.q[dirOff + 2]));
        const V3 before = d;
        if (!SnapDirection(d, agreed, cosTol)) {
            agreed.push_back(d);
            continue;
        }
        f.q[dirOff] = d.x;
        f.q[dirOff + 1] = d.y;
        f.q[dirOff + 2] = d.z;
        /* Re-settle everything else around the snapped direction, then keep it
         * only if the fit is still inside tolerance. Snapping a direction must
         * never make the surface stop describing the mesh. */
        PatchPoints(m, patches[i].tris, pd, 4000);
        bool freeMask[8];
        for (int k = 0; k < 8; ++k)
            freeMask[k] = true;
        freeMask[dirOff] = freeMask[dirOff + 1] = freeMask[dirOff + 2] = false;
        double q2[8];
        std::memcpy(q2, f.q, sizeof(q2));
        /* Before turning the axis, put the point it turns ABOUT where the
         * surface is — see RecentreAxis. Afterwards is too late: the line has
         * already swung away from the data. */
        q2[dirOff] = before.x;
        q2[dirOff + 1] = before.y;
        q2[dirOff + 2] = before.z;
        RecentreAxis(f.kind, q2, pd.pts);
        q2[dirOff] = d.x;
        q2[dirOff + 1] = d.y;
        q2[dirOff + 2] = d.z;
        RefineFit(f.kind, q2, pd.pts, scale, freeMask);
        const double rms = FitRms(f.kind, q2, pd.pts);
        /* A snap may not cost the fit its EXACTNESS.
         *
         * "Still inside tolerance" is the wrong bar, because tolerance is not
         * what this surface will be judged by afterwards: Identifiable holds a
         * fragment to a fiftieth of it, on the argument that a tessellation
         * puts its vertices ON the surface they came from. So a snap that
         * takes a residual from 0.00000 to 0.0149 passes here and is rejected
         * fifty lines later — and that is precisely what happened to three of
         * the four segments of the user's long-edge fillet. Each was an exact
         * cylinder of radius 0.9998; snapping its axis to Y moved the axis two
         * hundredths of a millimetre in z without re-settling the position
         * properly, and all three came back as triangles. Two rounded edges
         * drawn on top of each other is what that looks like on screen.
         *
         * Hold the snap to the bar the surface will actually face. */
        if (rms <= std::max(f.rms * 1.5, tol * kExactFitFraction)) {
            std::memcpy(f.q, q2, sizeof(q2));
            f.rms = rms;
        } else {
            f.q[dirOff] = before.x;
            f.q[dirOff + 1] = before.y;
            f.q[dirOff + 2] = before.z;
        }
    }

    /* Pass 2 — radii. Cylinders sharing an axis direction and a radius within
     * tolerance are one hole drilled several times; give them one number. */
    if (!(prm.snap_radius_frac > 0))
        return;
    const double rTol = scale * prm.snap_radius_frac;
    std::vector<int> cyl;
    for (size_t i = 0; i < patches.size(); ++i) {
        if (patches[i].fit.kind == kCylinder)
            cyl.push_back(static_cast<int>(i));
    }
    std::vector<char> done(cyl.size(), 0);
    for (size_t a = 0; a < cyl.size(); ++a) {
        if (done[a])
            continue;
        std::vector<int> group(1, cyl[a]);
        done[a] = 1;
        const V3 axA =
            Unit(V3(patches[cyl[a]].fit.q[3], patches[cyl[a]].fit.q[4],
                    patches[cyl[a]].fit.q[5]));
        for (size_t b = a + 1; b < cyl.size(); ++b) {
            if (done[b])
                continue;
            const Fit &fb = patches[cyl[b]].fit;
            const V3 axB = Unit(V3(fb.q[3], fb.q[4], fb.q[5]));
            if (std::fabs(Dot(axA, axB)) < cosTol)
                continue;
            if (std::fabs(fb.q[6] - patches[cyl[a]].fit.q[6]) > rTol)
                continue;
            group.push_back(cyl[b]);
            done[b] = 1;
        }
        if (group.size() < 2)
            continue;
        /* Weight by patch size: the radius the biggest surface measured is the
         * one with the most evidence behind it. */
        double num = 0, den = 0;
        for (int g : group) {
            const double w = static_cast<double>(patches[g].tris.size());
            num += patches[g].fit.q[6] * w;
            den += w;
        }
        const double r = num / den;
        for (int g : group) {
            Fit &f = patches[g].fit;
            const double saved = f.q[6];
            f.q[6] = r;
            PatchPoints(m, patches[g].tris, pd, 4000);
            bool freeMask[8] = {true,  true,  true,  false,
                                false, false, false, true};
            double q2[8];
            std::memcpy(q2, f.q, sizeof(q2));
            RefineFit(f.kind, q2, pd.pts, scale, freeMask);
            const double rms = FitRms(f.kind, q2, pd.pts);
            /* Same bar as the direction snap above: agreeing on a radius is
             * worth having, but not at the price of the exactness that is the
             * evidence the radius is real. */
            if (rms <= std::max(f.rms * 1.5, tol * kExactFitFraction)) {
                std::memcpy(f.q, q2, sizeof(q2));
                f.rms = rms;
            } else {
                f.q[6] = saved;
            }
        }
    }
}

/* ====================================================================== */
/* B-Rep construction                                                     */
/* ====================================================================== */

/* The fitted parameters as a real OCCT surface. Null when the parameters are
 * degenerate — a cone of zero angle, a torus whose tube swallows its hole —
 * which the caller treats as "this patch is freeform after all". */
Handle(Geom_Surface) MakeSurface(const Fit &f)
{
    try {
        switch (f.kind) {
        case kPlane: {
            const V3 n(f.q[0], f.q[1], f.q[2]);
            return new Geom_Plane(gp_Pln(P(n * f.q[3]), D(n)));
        }
        case kSphere: {
            if (!(f.q[3] > 0))
                return nullptr;
            return new Geom_SphericalSurface(
                gp_Ax3(gp_Pnt(f.q[0], f.q[1], f.q[2]), gp_Dir(0, 0, 1)),
                f.q[3]);
        }
        case kCylinder: {
            if (!(f.q[6] > 0))
                return nullptr;
            return new Geom_CylindricalSurface(
                gp_Ax3(gp_Pnt(f.q[0], f.q[1], f.q[2]),
                       gp_Dir(f.q[3], f.q[4], f.q[5])),
                f.q[6]);
        }
        case kCone: {
            /* OCCT wants the half-angle strictly inside (0, pi/2). */
            if (!(f.q[6] > 1e-4) || f.q[6] > M_PI / 2 - 1e-4)
                return nullptr;
            return new Geom_ConicalSurface(
                gp_Ax3(gp_Pnt(f.q[0], f.q[1], f.q[2]),
                       gp_Dir(f.q[3], f.q[4], f.q[5])),
                f.q[6], 0.0);
        }
        case kTorus: {
            if (!(f.q[6] > 0) || !(f.q[7] > 0) || f.q[7] >= f.q[6])
                return nullptr;
            return new Geom_ToroidalSurface(
                gp_Ax3(gp_Pnt(f.q[0], f.q[1], f.q[2]),
                       gp_Dir(f.q[3], f.q[4], f.q[5])),
                f.q[6], f.q[7]);
        }
        default:
            return nullptr;
        }
    } catch (const Standard_Failure &) {
        return nullptr;
    }
}

/* One run of boundary edges of a patch that all face the SAME neighbouring
 * patch. This is the unit an edge gets built from: a whole circular rim
 * between a barrel and its cap is one chain and becomes one exact circle,
 * where per-mesh-edge construction would have made two hundred segments. */
struct Chain
{
    std::vector<int> verts; /* in order; front()==back() when closed */
    int other = -1;         /* neighbouring patch, or -1 at a free boundary */
    bool closed = false;
};

/* Walks a patch's boundary into oriented loops, then cuts each loop into
 * chains at the points where the neighbouring patch changes. */
void PatchChains(const Mesh &m, const std::vector<int> &tris,
                 const std::vector<int> &patchOf, int self,
                 std::vector<std::vector<Chain>> &loops)
{
    /* Directed boundary edges, in the winding of the owning triangle, so the
     * loop already runs anticlockwise about the patch's own normal. */
    struct BE
    {
        int b;
        int other;
    };
    std::unordered_map<int, std::vector<BE>> outgoing;
    size_t total = 0;
    for (int t : tris) {
        for (int k = 0; k < 3; ++k) {
            const int o = m.adj[t * 3 + k];
            const int op = (o < 0) ? -1 : patchOf[o];
            if (op == self)
                continue;
            const int a = m.tri[t * 3 + k], b = m.tri[t * 3 + (k + 1) % 3];
            BE e;
            e.b = b;
            e.other = op;
            outgoing[a].push_back(e);
            total++;
        }
    }
    if (total == 0)
        return;

    std::unordered_map<int, size_t> cursor;
    size_t consumed = 0;
    while (consumed < total) {
        /* Start at the LOWEST-numbered vertex with an unused outgoing edge.
         * Not "any": an unordered_map's order is its implementation's, and the
         * two the app is built with do not agree. See "Ties decide the
         * model". */
        int start = -1;
        for (std::unordered_map<int, std::vector<BE>>::iterator it =
                 outgoing.begin();
             it != outgoing.end(); ++it) {
            if (cursor[it->first] < it->second.size() &&
                (start < 0 || it->first < start))
                start = it->first;
        }
        if (start < 0)
            break;

        std::vector<int> loopVerts;
        std::vector<int> loopOther;
        int v = start;
        while (true) {
            auto it = outgoing.find(v);
            if (it == outgoing.end())
                break;
            size_t &c = cursor[v];
            if (c >= it->second.size())
                break;
            const BE e = it->second[c++];
            consumed++;
            loopVerts.push_back(v);
            loopOther.push_back(e.other);
            v = e.b;
            if (v == start)
                break;
        }
        if (loopVerts.size() < 2)
            continue;
        const bool closedLoop = (v == start);

        /* Cut into chains where `other` changes. Rotate a closed loop so it
         * starts at a change, or the first and last chain would be two halves
         * of the same one. */
        const size_t n = loopVerts.size();
        size_t begin = 0;
        if (closedLoop) {
            size_t k = 0;
            for (; k < n; ++k) {
                if (loopOther[k] != loopOther[(k + n - 1) % n])
                    break;
            }
            begin =
                (k == n) ? 0 : k; /* k==n: one neighbour all the way round */
        }
        std::vector<Chain> chains;
        Chain cur;
        cur.other = loopOther[begin];
        cur.verts.push_back(loopVerts[begin]);
        for (size_t i = 1; i <= n; ++i) {
            const size_t idx = closedLoop ? (begin + i) % n : begin + i;
            if (!closedLoop && idx >= n) {
                cur.verts.push_back(v); /* the open loop's final vertex */
                break;
            }
            const int nextOther = closedLoop ? loopOther[idx] : loopOther[idx];
            const int vertex = closedLoop ? loopVerts[idx] : loopVerts[idx];
            cur.verts.push_back(vertex);
            if (i == n)
                break;
            if (nextOther != cur.other) {
                chains.push_back(cur);
                cur = Chain();
                cur.other = nextOther;
                cur.verts.push_back(vertex);
            }
        }
        /* The i == n step above already appended loopVerts[begin], which is
         * what closes the loop; appending it a second time here left every
         * final chain one vertex longer than the same chain seen from the
         * neighbouring patch, so the two never agreed on a key and the shared
         * edge was built twice. */
        if (closedLoop && chains.empty())
            cur.closed = true;
        if (cur.verts.size() >= 2)
            chains.push_back(cur);
        if (!chains.empty())
            loops.push_back(chains);
    }
}

/* An edge built once and used by both faces that meet along it.
 *
 * Sharing the TopoDS_Edge is not an optimisation — it is what makes the shell
 * sew. Two faces holding geometrically-equal but distinct edges sew only by
 * tolerance, and on a model with ten thousand of them, some pair fails. */
struct EdgeKey
{
    int p1, p2, v1, v2, vm;
    bool operator<(const EdgeKey &o) const
    {
        if (p1 != o.p1)
            return p1 < o.p1;
        if (p2 != o.p2)
            return p2 < o.p2;
        if (v1 != o.v1)
            return v1 < o.v1;
        if (v2 != o.v2)
            return v2 < o.v2;
        return vm < o.vm;
    }
};

/* A name for a chain that BOTH patches sharing it will arrive at.
 *
 * This has to be independent of which way the chain is walked and of where the
 * walk started, because the two patches either side of a boundary traverse it
 * in opposite directions, and a closed rim may not even begin at the same
 * vertex. Keying on the endpoints and a midpoint — the obvious first try —
 * satisfies none of that: for a two-vertex chain the "midpoint" is the far END,
 * so the key flipped with the direction, every shared edge was built twice, and
 * the two copies then had to be reconciled by sewing tolerance. Boxes survived
 * that. Filleted parts did not.
 *
 * The vertex SET of a chain is the same from both sides however it is walked,
 * so its extremes and its length name it canonically. */
EdgeKey KeyFor(const Chain &c, int self)
{
    EdgeKey k;
    k.p1 = std::min(self, c.other);
    k.p2 = std::max(self, c.other);
    int lo = c.verts[0], hi = c.verts[0];
    for (int v : c.verts) {
        lo = std::min(lo, v);
        hi = std::max(hi, v);
    }
    k.v1 = lo;
    k.v2 = hi;
    /* Length separates two chains that join the same patches over overlapping
     * vertex ranges — a rim cut in half is the case that needs it. */
    k.vm = static_cast<int>(c.verts.size());
    return k;
}

struct BuildCtx
{
    const Mesh *m = nullptr;
    double tol = 0;
    double scale = 0;
    std::map<EdgeKey, TopoDS_Edge> edges;
    std::unordered_map<int, TopoDS_Vertex> verts;
    /* One straight edge per MESH edge, keyed on its two vertex ids. Shared by
     * every faceted triangle that uses it, so triangles are sewn to each other
     * by construction rather than by geometric search afterwards. */
    std::unordered_map<long long, TopoDS_Edge> meshEdges;
    int analytic = 0, approximated = 0;
};

TopoDS_Vertex VertexAt(BuildCtx &ctx, int v)
{
    auto it = ctx.verts.find(v);
    if (it != ctx.verts.end())
        return it->second;
    const TopoDS_Vertex tv = BRepBuilderAPI_MakeVertex(P((*ctx.m).pos[v]));
    ctx.verts.emplace(v, tv);
    return tv;
}

/* Reads a quadric's axis and size, for the degeneracy test below. */
struct Quadric
{
    int kind = -1; /* 0 plane, 1 cylinder, 2 cone, 3 sphere, 4 torus */
    gp_Pnt loc;
    gp_Dir dir;
    double size = 0; /* radius, or a cone's semi-angle */
};

bool ReadQuadric(const Handle(Geom_Surface) & s, Quadric &q)
{
    if (Handle(Geom_Plane) x = Handle(Geom_Plane)::DownCast(s)) {
        q.kind = 0;
        q.loc = x->Position().Location();
        q.dir = x->Position().Direction();
        return true;
    }
    if (Handle(Geom_CylindricalSurface) x =
            Handle(Geom_CylindricalSurface)::DownCast(s)) {
        q.kind = 1;
        q.loc = x->Position().Location();
        q.dir = x->Position().Direction();
        q.size = x->Radius();
        return true;
    }
    if (Handle(Geom_ConicalSurface) x =
            Handle(Geom_ConicalSurface)::DownCast(s)) {
        q.kind = 2;
        q.loc = x->Position().Location();
        q.dir = x->Position().Direction();
        q.size = x->SemiAngle();
        return true;
    }
    if (Handle(Geom_SphericalSurface) x =
            Handle(Geom_SphericalSurface)::DownCast(s)) {
        q.kind = 3;
        q.loc = x->Position().Location();
        q.dir = x->Position().Direction();
        q.size = x->Radius();
        return true;
    }
    if (Handle(Geom_ToroidalSurface) x =
            Handle(Geom_ToroidalSurface)::DownCast(s)) {
        q.kind = 4;
        q.loc = x->Position().Location();
        q.dir = x->Position().Direction();
        q.size = x->MajorRadius();
        return true;
    }
    return false;
}

/* Which surface pairs are safe to hand to GeomAPI_IntSS.
 *
 * IntSS has no time bound, and OCCT's implicit-implicit intersector can grind
 * on a quadric pair indefinitely — two parallel cylinders whose axes are a
 * millimetre apart took over ninety seconds on a 444-triangle mesh and had not
 * finished. On an iPad that is not a slow conversion; it is a frozen app the
 * watchdog kills, indistinguishable from the crash this same file already cost
 * a day to find. There is no way to interrupt it once it is running, so the
 * only safe bound is on what goes in.
 *
 * Two cases carry essentially all the value, and both are the well-trodden
 * paths in OCCT:
 *
 *   - a PLANE against anything, including another plane. This is the hole rim,
 *     the cap edge, the box edge, the flat a boss stands on — a circle or a
 *     line, exactly, and OCCT solves it in closed form.
 *   - two COAXIAL quadrics of different kinds: a cylinder into a cone is the
 *     rim of a countersunk hole, a cylinder into a torus the rim of a filleted
 *     one. Also a circle, exactly.
 *
 * Everything else — two cylinders crossing, a cone against a sphere — meets in
 * a curve of degree four that OCCT would hand back approximated anyway, so the
 * polyline fallback loses nothing that was ever exact. Coaxial pairs of the
 * SAME kind are refused outright: they meet nowhere or everywhere. */
bool IntersectablePair(const Handle(Geom_Surface) & s1,
                       const Handle(Geom_Surface) & s2, double tol)
{
    Quadric a, b;
    if (!ReadQuadric(s1, a) || !ReadQuadric(s2, b))
        return false;
    const double cosPar = 1.0 - 1e-7;
    if (a.kind == 0 && b.kind == 0) /* parallel planes meet nowhere */
        return std::fabs(a.dir.Dot(b.dir)) <= cosPar;
    if (a.kind == 0 || b.kind == 0)
        return true;
    /* Same axis LINE, not merely the same direction. */
    if (std::fabs(a.dir.Dot(b.dir)) <= cosPar)
        return false;
    if (a.kind == b.kind)
        return false;
    const gp_Vec off(a.loc, b.loc);
    const double along = off.Dot(gp_Vec(a.dir));
    const double perp2 = off.SquareMagnitude() - along * along;
    const double gap = perp2 > 0 ? std::sqrt(perp2) : 0.0;
    return gap <= tol;
}

/* The exact intersection curve of two analytic surfaces, when there is one
 * that follows this chain. Null otherwise.
 *
 * This is the whole quality argument for the prismatic path: a hole's rim
 * comes out a real gp_Circ, so a fillet on it later has a circle to roll along
 * and a STEP export carries a circle rather than a 200-segment spline. */
/* The circle where a fillet TOUCHES what it blends into.
 *
 * A fillet meets its neighbours tangentially — that is what a fillet is — and
 * a tangential contact is the one case a general surface intersector cannot
 * do: the two surfaces do not cross, they graze, and the system is singular
 * exactly along the answer. GeomAPI_IntSS returns nothing, the edge falls back
 * to the polyline through the mesh vertices, and the fillet's own face keeps
 * the true circle. Measured on a boss fillet ring: the torus side carried a
 * circle of circumference 65.973 and the plate top an inscribed polygon of
 * 64.529, half a millimetre apart at the middle of every segment, and the
 * shell stayed open along that one seam — 2 free edges out of 45.
 *
 * But a fillet's contacts are not general intersections at all, they are
 * known: a torus is touched by the plane perpendicular to its axis at exactly
 * its minor radius, in the circle of its MAJOR radius; and by the coaxial
 * cylinder of radius R+r or R-r, in the circle of that radius. Both are
 * closed-form, both are exact, and both are checked against the chain before
 * being believed. */
Handle(Geom_Curve) TangentContact(const Handle(Geom_Surface) & s1,
                                  const Handle(Geom_Surface) & s2, double tol)
{
    Handle(Geom_ToroidalSurface) tor =
        Handle(Geom_ToroidalSurface)::DownCast(s1);
    Handle(Geom_Surface) other = s2;
    if (tor.IsNull()) {
        tor = Handle(Geom_ToroidalSurface)::DownCast(s2);
        other = s1;
    }
    if (tor.IsNull())
        return nullptr;
    const gp_Pnt c = tor->Position().Location();
    const gp_Dir d = tor->Position().Direction();
    const double R = tor->MajorRadius(), r = tor->MinorRadius();
    const double cosPar = 1.0 - 1e-7;

    if (Handle(Geom_Plane) pl = Handle(Geom_Plane)::DownCast(other)) {
        if (std::fabs(pl->Position().Direction().Dot(d)) < cosPar)
            return nullptr;
        const double h =
            gp_Vec(c, pl->Position().Location()).Dot(gp_Vec(d));
        if (std::fabs(std::fabs(h) - r) > tol)
            return nullptr;
        return new Geom_Circle(gp_Ax2(c.Translated(gp_Vec(d) * h), d), R);
    }
    if (Handle(Geom_CylindricalSurface) cy =
            Handle(Geom_CylindricalSurface)::DownCast(other)) {
        if (std::fabs(cy->Position().Direction().Dot(d)) < cosPar)
            return nullptr;
        /* The same axis LINE, not merely the same direction. */
        const gp_Vec off(c, cy->Position().Location());
        const double along = off.Dot(gp_Vec(d));
        const double perp2 = off.SquareMagnitude() - along * along;
        if (perp2 > tol * tol)
            return nullptr;
        const double cr = cy->Radius();
        double want = 0;
        if (std::fabs(cr - (R + r)) <= tol)
            want = R + r;
        else if (R > r && std::fabs(cr - (R - r)) <= tol)
            want = R - r;
        else
            return nullptr;
        return new Geom_Circle(gp_Ax2(c, d), want);
    }
    return nullptr;
}

Handle(Geom_Curve) IntersectionCurve(const Handle(Geom_Surface) & s1,
                                     const Handle(Geom_Surface) & s2,
                                     const std::vector<gp_Pnt> &pts, double tol)
{
    if (s1.IsNull() || s2.IsNull())
        return nullptr;
    /* A grazing contact first: the intersector cannot find it and it has a
     * closed form. Believed only if the chain really is on it. */
    if (Handle(Geom_Curve) t = TangentContact(s1, s2, tol)) {
        bool on = true;
        try {
            for (size_t k = 0; k < pts.size() && on;
                 k += std::max<size_t>(1, pts.size() / 6)) {
                GeomAPI_ProjectPointOnCurve pp(pts[k], t);
                if (pp.NbPoints() < 1 || pp.LowerDistance() > tol * 3)
                    on = false;
            }
        } catch (const Standard_Failure &) {
            on = false;
        }
        if (on)
            return t;
    }
    if (!IntersectablePair(s1, s2, tol))
        return MR_TRACE("          isect: pair rejected\n"), nullptr;
    /* And the chain has to be ON both surfaces before it is worth asking where
     * they meet: if it is not, whatever curve comes back is not this edge, and
     * the check costs a handful of projections against an intersection that can
     * cost everything. */
    try {
        for (size_t k = 0; k < pts.size();
             k += std::max<size_t>(1, pts.size() / 4)) {
            GeomAPI_ProjectPointOnSurf p1(pts[k], s1);
            if (!p1.IsDone() || p1.NbPoints() < 1 ||
                p1.LowerDistance() > tol * 3)
                return MR_TRACE("          isect: chain off s1 by %.6f "
                                "(tol*3 %.6f)\n",
                                p1.NbPoints() ? p1.LowerDistance() : -1.0,
                                tol * 3),
                       nullptr;
            GeomAPI_ProjectPointOnSurf p2(pts[k], s2);
            if (!p2.IsDone() || p2.NbPoints() < 1 ||
                p2.LowerDistance() > tol * 3)
                return MR_TRACE("          isect: chain off s2 by %.6f "
                                "(tol*3 %.6f)\n",
                                p2.NbPoints() ? p2.LowerDistance() : -1.0,
                                tol * 3),
                       nullptr;
        }
    } catch (const Standard_Failure &) {
        return nullptr;
    }
    try {
        GeomAPI_IntSS iss(s1, s2, tol * 0.1);
        if (!iss.IsDone() || iss.NbLines() < 1)
            return MR_TRACE("          isect: IntSS done=%d lines=%d\n",
                            (int)iss.IsDone(),
                            iss.IsDone() ? iss.NbLines() : -1),
                   nullptr;
        Handle(Geom_Curve) best;
        double bestErr = 1e300;
        for (int i = 1; i <= iss.NbLines(); ++i) {
            Handle(Geom_Curve) c = iss.Line(i);
            if (c.IsNull())
                continue;
            /* IntSS hands back a Geom_TrimmedCurve WRAPPING the real conic,
             * and a trimmed curve reports IsClosed() and IsPeriodic() as
             * false however complete it is. Left wrapped, a cap rim never
             * takes the full-circle path and every hole in the model came out
             * as a spline through the mesh points instead of the circle it
             * actually is. Unwrap to the basis curve and the conic is itself
             * again. */
            for (int guard = 0; guard < 4; ++guard) {
                Handle(Geom_TrimmedCurve) tc =
                    Handle(Geom_TrimmedCurve)::DownCast(c);
                if (tc.IsNull())
                    break;
                c = tc->BasisCurve();
            }
            if (c.IsNull())
                continue;
            /* Score by how far the chain's own points sit from the candidate:
             * two surfaces can meet in more than one curve and only one of them
             * is the edge this chain is walking. */
            double err = 0;
            int n = 0;
            for (size_t k = 0; k < pts.size();
                 k += std::max<size_t>(1, pts.size() / 8)) {
                GeomAPI_ProjectPointOnCurve pp(pts[k], c);
                if (pp.NbPoints() < 1) {
                    err = 1e300;
                    break;
                }
                err += pp.LowerDistance();
                n++;
            }
            if (n == 0)
                continue;
            err /= n;
            if (err < bestErr) {
                bestErr = err;
                best = c;
            }
        }
        if (best.IsNull() || bestErr > tol * 3)
            return MR_TRACE("          isect: best err %.6f > tol*3 %.6f\n",
                            bestErr, tol * 3),
                   nullptr;
        return best;
    } catch (const Standard_Failure &) {
        return nullptr;
    }
}

/* Builds (or reuses) the edge for one chain. */
/* Does this curve go where the chain goes?
 *
 * A B-spline fitted through a chain is an APPROXIMATION, and the fitter's own
 * tolerance only promises that the POINTS it was given are near the curve. It
 * promises nothing about the space between them, and that is where the classic
 * overshoot lives: the user's side wall meets its top-edge fillet along
 * eighteen millimetres of a straight tangency line with a single kink at the
 * far end, where a fillet crossing pulls the last vertex up by a tenth of a
 * millimetre. A C2 spline through that bows a MILLIMETRE the other way in the
 * middle — and the wall and the fillet, which share the edge, both follow it
 * out of the model. Measured: half a millimetre of flap, four and a half times
 * tolerance, the length of the part.
 *
 * So measure the space between: sample the curve and ask how far each sample
 * strays from the polyline the chain actually walks. This is asked of the
 * FITTED curve only. An exact conic is not an approximation of the chain — the
 * chain is a chord approximation of IT — so it is entitled to bow out by the
 * tessellation's sagitta and is never asked. */
/* How far the chain itself bends: for each interior vertex, how far it stands
 * off the chord of its two neighbours.
 *
 * This is the slack a fitted curve is entitled to. A chain round a coarse hole
 * turns by fifteen degrees a step and its own vertices stand a quarter of a
 * millimetre off their neighbours' chords — a smooth curve through them bows
 * out too, and must be allowed to. A chain down a straight tangency line does
 * not bend at all, so nothing fitted through it has any business leaving it. */
double ChainBow(const std::vector<gp_Pnt> &pts)
{
    double worst = 0;
    for (size_t i = 1; i + 1 < pts.size(); ++i) {
        const gp_Vec seg(pts[i - 1], pts[i + 1]);
        const double len2 = seg.SquareMagnitude();
        if (!(len2 > 0))
            continue;
        double t = gp_Vec(pts[i - 1], pts[i]).Dot(seg) / len2;
        t = std::max(0.0, std::min(1.0, t));
        const gp_Pnt on(pts[i - 1].X() + seg.X() * t, pts[i - 1].Y() + seg.Y() * t,
                        pts[i - 1].Z() + seg.Z() * t);
        worst = std::max(worst, std::sqrt(pts[i].SquareDistance(on)));
    }
    return worst;
}

double CurveOffChain(const Handle(Geom_Curve) & cur, double u1, double u2,
                     const std::vector<gp_Pnt> &pts)
{
    if (cur.IsNull() || pts.size() < 2)
        return 0;
    double worst = 0;
    const int samples = static_cast<int>(pts.size()) * 4 + 8;
    for (int i = 1; i < samples; ++i) {
        const double u = u1 + (u2 - u1) * i / samples;
        const gp_Pnt q = cur->Value(u);
        double best = 1e300;
        for (size_t k = 0; k + 1 < pts.size(); ++k) {
            const gp_Vec seg(pts[k], pts[k + 1]);
            const double len2 = seg.SquareMagnitude();
            double t = 0;
            if (len2 > 0) {
                t = gp_Vec(pts[k], q).Dot(seg) / len2;
                t = std::max(0.0, std::min(1.0, t));
            }
            const gp_Pnt on(pts[k].X() + seg.X() * t, pts[k].Y() + seg.Y() * t,
                            pts[k].Z() + seg.Z() * t);
            best = std::min(best, q.SquareDistance(on));
        }
        worst = std::max(worst, std::sqrt(best));
    }
    return worst;
}

TopoDS_Edge ChainEdge(BuildCtx &ctx, const Chain &c, int self,
                      const Handle(Geom_Surface) & selfSurf,
                      const std::vector<Handle(Geom_Surface)> &surfs)
{
    const EdgeKey key = KeyFor(c, self);
    auto it = ctx.edges.find(key);
    MR_TRACE("        chain key(%d %d %d %d %d) self %d other %d verts %d %s\n",
             key.p1, key.p2, key.v1, key.v2, key.vm, self, c.other,
             (int)c.verts.size(), it != ctx.edges.end() ? "HIT" : "new");
    if (it != ctx.edges.end())
        return it->second;

    std::vector<gp_Pnt> pts;
    pts.reserve(c.verts.size());
    for (int v : c.verts)
        pts.push_back(P(ctx.m->pos[v]));

    TopoDS_Edge e;
    const bool closed = c.verts.front() == c.verts.back();

    /* Whether the far side of this chain is triangles rather than a surface.
     *
     * An edge is ONE curve and both faces either side must agree on it. Where
     * the neighbour is faceted, the triangles' chords are what it agrees to,
     * so nothing smoother may be used here however exact it is on this side —
     * a hole's rim came back a true circle while the shell beside it was the
     * inscribed polygon, and a coarse mesh's sagitta is wider than any sewing
     * tolerance. That left the four holes recognised and the shell unsewn
     * round every one of them. The cylinder is still a cylinder of radius
     * exactly 2; only its RIM gives up being a conic, and only where it meets
     * triangles. Between two fitted faces the exact conic still wins. */
    const bool neighbourFaceted =
        c.other < 0 || c.other >= static_cast<int>(surfs.size()) ||
        surfs[c.other].IsNull();

    /* 1 — the exact curve where two analytic surfaces meet. */
    if (!neighbourFaceted && !selfSurf.IsNull()) {
        const Handle(Geom_Curve) cur =
            IntersectionCurve(selfSurf, surfs[c.other], pts, ctx.tol);
        if (!cur.IsNull()) {
            try {
                if (closed && cur->IsClosed()) {
                    BRepBuilderAPI_MakeEdge me(cur);
                    if (me.IsDone())
                        e = me.Edge();
                } else {
                    GeomAPI_ProjectPointOnCurve p1(pts.front(), cur);
                    GeomAPI_ProjectPointOnCurve p2(pts.back(), cur);
                    if (p1.NbPoints() > 0 && p2.NbPoints() > 0) {
                        double u1 = p1.LowerDistanceParameter();
                        double u2 = p2.LowerDistanceParameter();
                        if (cur->IsPeriodic()) {
                            /* Go round the way the chain actually goes: check a
                             * midpoint rather than assuming the short arc. */
                            const double per = cur->Period();
                            while (u2 <= u1)
                                u2 += per;
                            while (u2 - u1 > per)
                                u2 -= per;
                            GeomAPI_ProjectPointOnCurve pm(pts[pts.size() / 2],
                                                           cur);
                            if (pm.NbPoints() > 0) {
                                double um = pm.LowerDistanceParameter();
                                while (um <= u1)
                                    um += per;
                                while (um - u1 > per)
                                    um -= per;
                                if (um > u2)
                                    u2 -= per; /* the other way round */
                            }
                        }
                        /* Which END is at which parameter matters.
                         *
                         * MakeEdge is told a first vertex and a first
                         * parameter and checks that they are the same point;
                         * sorting the two parameters and keeping the vertices
                         * in chain order tells it the opposite of the truth
                         * whenever the chain runs the DECREASING way along the
                         * curve, which is half of them. It then refuses to
                         * build, the exact conic is dropped, and the rim of
                         * every second hole came back a polyline through the
                         * mesh points — 5 exact edges in the user's part where
                         * there should be sixty. Hand them over the way round
                         * they actually are: the edge is the same arc either
                         * way, and the wire orients it. */
                        /* The vertex has to admit how well it knows where
                         * it is.
                         *
                         * MakeEdge is handed a vertex and a parameter and
                         * refuses the pair unless the two agree to within the
                         * VERTEX's tolerance, which a freshly built vertex sets
                         * at Precision::Confusion — a ten-millionth of a
                         * millimetre. A mesh vertex is nothing like that
                         * certain: it arrives as a 32-bit float and the curve
                         * it is being placed on is a least-squares fit through
                         * several hundred of its neighbours, so a micron of
                         * disagreement is normal and honest. Left at the
                         * default it is fatal instead: eighty-eight of the
                         * ninety-six exact trims in the user's part were
                         * refused for distances of one micron, and every one of
                         * those rims fell back to a polyline through the very
                         * same points. Say what the uncertainty really is, and
                         * never more than the MESH's own precision.
                         *
                         * Not more, measured: letting the bound reach a
                         * twentieth of tolerance takes exact edges on the
                         * user's part from 45 to 117 and the volume error from
                         * +0.21% to +0.05%, and seven FACES then fail to build
                         * — wires whose arcs are each exact and no longer meet
                         * — so the part arrives as 257 faces instead of 72.
                         * The refusals it would have bought are chain
                         * endpoints one to four thousandths of a millimetre
                         * off an intersection curve: corners where three
                         * fitted surfaces do not quite agree. Forcing the edge
                         * through one only moves the disagreement into the
                         * wire. */
                        if (std::fabs(u2 - u1) > 1e-12) {
                            const TopoDS_Vertex va =
                                VertexAt(ctx, c.verts.front());
                            const TopoDS_Vertex vb =
                                VertexAt(ctx, c.verts.back());
                            BRep_Builder bb;
                            /* Bounded by what a MESH knows, not by what the
                             * conversion tolerates. A vertex allowed the full
                             * reconstruction tolerance is a vertex that can
                             * swallow its neighbours: sewing merges anything
                             * inside it and ShapeFix is licensed to grow it a
                             * hundredfold, which on the user's part reached
                             * 2.7 mm — wider than the slits — and took a fifth
                             * of the model's volume with it. The float the
                             * vertex arrived as is good to about a millionth
                             * of the model, and that is the whole of the
                             * doubt it is entitled to. */
                            const double vmax = std::max(
                                ctx.scale * kMeshPrecisionFrac, 1e-9);
                            bb.UpdateVertex(
                                va,
                                std::min(p1.LowerDistance() * 2.0 + 1e-9, vmax));
                            bb.UpdateVertex(
                                vb,
                                std::min(p2.LowerDistance() * 2.0 + 1e-9, vmax));
                            const double lo = std::min(u1, u2);
                            const double hi = std::max(u1, u2);
                            /* And the arc has to be the one the chain walks.
                             *
                             * Two points on a circle name two arcs, and the
                             * parameters alone do not say which. Taking the
                             * wrong one puts a face's boundary right round the
                             * far side of its own cylinder: on a filleted
                             * block it cost a third of the volume and left the
                             * solid invalid. The chain's own interior points
                             * settle it — they lie on the arc that belongs to
                             * this edge and nowhere near the other. */
                            bool follows = true;
                            for (size_t k = 1; k + 1 < pts.size() && follows;
                                 ++k) {
                                GeomAPI_ProjectPointOnCurve pp(pts[k], cur);
                                if (pp.NbPoints() < 1 ||
                                    pp.LowerDistance() > ctx.tol) {
                                    follows = false;
                                    break;
                                }
                                double up = pp.LowerDistanceParameter();
                                if (cur->IsPeriodic()) {
                                    const double per = cur->Period();
                                    while (up < lo - 1e-9)
                                        up += per;
                                    while (up > lo + per + 1e-9)
                                        up -= per;
                                }
                                if (up < lo - 1e-6 || up > hi + 1e-6)
                                    follows = false;
                            }
                            if (!follows) {
                                MR_TRACE("          trim: the arc does not "
                                         "follow the chain\n");
                            } else if (u1 < u2) {
                                BRepBuilderAPI_MakeEdge me(cur, va, vb, u1, u2);
                                if (me.IsDone())
                                    e = me.Edge();
                                else
                                    MR_TRACE("          trim fwd err=%d d "
                                             "%.7f/%.7f vmax %.7f\n",
                                             (int)me.Error(),
                                             p1.LowerDistance(),
                                             p2.LowerDistance(), vmax);
                            } else {
                                BRepBuilderAPI_MakeEdge me(cur, vb, va, u2, u1);
                                if (me.IsDone())
                                    e = me.Edge();
                                else
                                    MR_TRACE("          trim rev err=%d d "
                                             "%.7f/%.7f vmax %.7f\n",
                                             (int)me.Error(),
                                             p1.LowerDistance(),
                                             p2.LowerDistance(), vmax);
                            }
                        }
                    }
                }
            } catch (const Standard_Failure &) {
                e = TopoDS_Edge();
            }
            if (!e.IsNull())
                ctx.analytic++;
        }
    }

    /* 2 — a straight edge, when the chain is one mesh edge long. */
    if (e.IsNull() && c.verts.size() == 2) {
        try {
            BRepBuilderAPI_MakeEdge me(VertexAt(ctx, c.verts.front()),
                                       VertexAt(ctx, c.verts.back()));
            if (me.IsDone()) {
                e = me.Edge();
                ctx.approximated++;
            }
        } catch (const Standard_Failure &) {
        }
    }

    /* 3a — the POLYLINE, when the other side of this chain is triangles.
     *
     * A fitted face and a faceted region have to meet along the same curve or
     * the shell does not sew, and the two disagree by construction: the spline
     * below is an APPROXIMATION within tolerance, while the triangles use the
     * straight chords between the very same vertices. On a coarse mesh that
     * gap is bigger than the sewing tolerance, and the result is a model with
     * its holes recognised and a seam round every one of them.
     *
     * Where the neighbour is faceted, the chords ARE the truth. A degree-one
     * B-spline through the chain is exactly them. */
    auto chainPolyline = [&]() {
        if (pts.size() < 3)
            return;
        try {
            const int n = static_cast<int>(pts.size());
            TColgp_Array1OfPnt poles(1, n);
            for (int i = 0; i < n; ++i)
                poles.SetValue(i + 1, pts[i]);
            TColStd_Array1OfReal knots(1, n);
            TColStd_Array1OfInteger mult(1, n);
            for (int i = 0; i < n; ++i) {
                knots.SetValue(i + 1, i);
                mult.SetValue(i + 1, 1);
            }
            mult.SetValue(1, 2);
            mult.SetValue(n, 2);
            Handle(Geom_BSplineCurve) poly =
                new Geom_BSplineCurve(poles, knots, mult, 1);
            BRepBuilderAPI_MakeEdge me(poly, VertexAt(ctx, c.verts.front()),
                                       VertexAt(ctx, c.verts.back()),
                                       poly->FirstParameter(),
                                       poly->LastParameter());
            if (me.IsDone()) {
                e = me.Edge();
                ctx.approximated++;
            }
        } catch (const Standard_Failure &) {
            e = TopoDS_Edge();
        }
    };
    if (e.IsNull() && neighbourFaceted)
        chainPolyline();

    /* 3 — a spline through the chain. Not exact, but continuous and compact,
     *     which a polyline of two hundred segments is not. */
    if (e.IsNull() && pts.size() >= 3) {
        try {
            const int n = static_cast<int>(pts.size()) - (closed ? 1 : 0);
            if (n >= 3) {
                TColgp_Array1OfPnt arr(1, n);
                for (int i = 0; i < n; ++i)
                    arr.SetValue(i + 1, pts[i]);
                GeomAPI_PointsToBSpline approx(arr, 3, 8, GeomAbs_C2, ctx.tol);
                Handle(Geom_BSplineCurve) bs = approx.Curve();
                const double off =
                    bs.IsNull() ? 1e300
                                : CurveOffChain(bs, bs->FirstParameter(),
                                                bs->LastParameter(), pts);
                const double bar = std::max(ctx.tol, ChainBow(pts));
                if (!bs.IsNull() && off > bar) {
                    /* The chords ARE the boundary when nothing smoother can
                     * be trusted to stay on it. */
                    MR_TRACE("          spline strays %.4f from its chain "
                             "(bar %.4f): polyline instead\n", off, bar);
                    chainPolyline();
                } else if (!bs.IsNull()) {
                    if (closed)
                        bs->SetPeriodic();
                    BRepBuilderAPI_MakeEdge me(bs);
                    if (me.IsDone()) {
                        e = me.Edge();
                        ctx.approximated++;
                    }
                }
            }
        } catch (const Standard_Failure &) {
            e = TopoDS_Edge();
        }
    }

    /* 4 — a polyline. Always available, never pretty. */
    if (e.IsNull() && pts.size() >= 2) {
        try {
            BRepBuilderAPI_MakeEdge me(VertexAt(ctx, c.verts.front()),
                                       VertexAt(ctx, c.verts.back()));
            if (me.IsDone()) {
                e = me.Edge();
                ctx.approximated++;
            }
        } catch (const Standard_Failure &) {
        }
    }

    if (!e.IsNull())
        ctx.edges.emplace(key, e);
    return e;
}

/* Every triangle of a patch as its own planar face — the honest fallback when
 * the patch fitted nothing, or when the analytic face refused to build. */
/* A face has to stay inside the triangles it was built from.
 *
 * The wires come from mesh vertices, so a well-built face is within a facet's
 * sagitta of its own patch. One that is not has lost its trimming — a plane
 * whose wire failed to bound it is INFINITE, and an infinite plane in a shell
 * is not a slightly wrong face, it is a black shard across the model with
 * edges running off to the horizon and a bounding box that grows every time
 * the viewer re-tessellates it. That is exactly what a real organic download
 * produced: faces reaching nearly three times the whole model's diagonal
 * outside it.
 *
 * The patch's own triangles are the honest bound, and the margin is generous
 * by two orders of magnitude against what a broken face does, so this cannot
 * refuse a face that is merely imperfect. */
bool FaceWithinPatch(const TopoDS_Face &face, const Mesh &m,
                     const std::vector<int> &tris, double tol)
{
    if (tris.empty())
        return false;
    V3 lo(1e300, 1e300, 1e300), hi(-1e300, -1e300, -1e300);
    for (int t : tris) {
        for (int k = 0; k < 3; ++k) {
            const V3 &p = m.pos[m.tri[t * 3 + k]];
            lo.x = std::min(lo.x, p.x);
            lo.y = std::min(lo.y, p.y);
            lo.z = std::min(lo.z, p.z);
            hi.x = std::max(hi.x, p.x);
            hi.y = std::max(hi.y, p.y);
            hi.z = std::max(hi.z, p.z);
        }
    }
    const double slack = std::max(tol * 8.0, Norm(hi - lo) * 0.08);
    /* Two boxes, cheap first.
     *
     * BRepBndLib::Add boxes a face by its pcurves' POLES, so it never
     * UNDERstates the face — if that box is inside the patch, the face
     * certainly is, and on a model that is behaving this is the only box ever
     * computed. It does overstate: a B-spline's control polygon stands well
     * outside the curve, which on a plate's end cap read as 1.7 mm of
     * overshoot on a face that was exactly right. So a failure there is not a
     * verdict, only a reason to pay for AddOptimal, which evaluates the curves
     * instead of trusting their hulls. */
    auto inside = [&](const Bnd_Box &b) {
        if (b.IsVoid() || b.IsWhole() || b.IsOpenXmin() || b.IsOpenXmax() ||
            b.IsOpenYmin() || b.IsOpenYmax() || b.IsOpenZmin() || b.IsOpenZmax())
            return false;
        Standard_Real x0, y0, z0, x1, y1, z1;
        b.Get(x0, y0, z0, x1, y1, z1);
        const double v[6] = {x0, y0, z0, x1, y1, z1};
        for (int k = 0; k < 6; ++k)
            if (!(v[k] > -1e99 && v[k] < 1e99))
                return false;
        return x0 >= lo.x - slack && y0 >= lo.y - slack && z0 >= lo.z - slack &&
               x1 <= hi.x + slack && y1 <= hi.y + slack && z1 <= hi.z + slack;
    };
    try {
        Bnd_Box quick;
        BRepBndLib::Add(face, quick, Standard_False);
        if (inside(quick))
            return true;
        Bnd_Box tight;
        BRepBndLib::AddOptimal(face, tight, Standard_False, Standard_False);
        return inside(tight);
    } catch (const Standard_Failure &) {
        return false;
    }
}

/* Does the face FOLD THROUGH ITSELF?
 *
 * FaceWithinPatch asks whether the face covers the right REGION, and it
 * answers from bounding boxes — which is exactly the question a folded face
 * slips past. A wire that crosses itself on the surface encloses a region
 * that doubles back through itself, and every box of it is still the patch's
 * box, because the box of a face with no triangulation yet is the box of its
 * EDGES and the edges are where they should be. What is wrong is between
 * them. On the user's broom holder two tori invented over the embossed logo
 * do this: patch box (0.31 22.56 -3.09)-(6.15 23.04 2.71), and the face
 * reaches y 19.6 — three and a half millimetres of flap standing out of an
 * engraving half a millimetre deep.
 *
 * BRepCheck is the authority and names both halves of it — SelfIntersectingWire
 * on the wire, UnorientableShape on the face — but only with its geometric
 * controls on, and on raw faces whose edges have not been through
 * SameParameter yet that costs twenty times the whole conversion. So it is
 * asked about hardly any faces.
 *
 * AREA is what decides who it is asked about, and it is the right screen
 * because a fold covers its own region TWICE. A face otherwise covers what
 * its triangles cover, a little more: the triangles are chords, so they
 * always fall short of the surface, by an amount quadratic in facet size.
 * Measured, that shortfall is tiny — nothing above 1.05 anywhere in the 216
 * tessellations of the plate sweep, 1.051 on the user's bracket, 1.129 on the
 * broom holder — while the two flaps stand at 2.91 and 5.31.
 *
 * A screen is not a verdict, which matters: a face trimmed by the surface's
 * own parameter rectangle rather than by a wire legitimately overshoots, and
 * the four hole barrels through the curved shell in the test suite reach 2.92
 * that way. They are sound, BRepCheck says so, and they are kept. */
const double kFaceAreaScreen = 1.5;

bool FaceIsSound(const TopoDS_Face &face, const Mesh &m,
                 const std::vector<int> &tris)
{
    double patchArea = 0;
    for (int t : tris)
        patchArea += m.tarea[t];
    if (!(patchArea > 0))
        return true;
    try {
        GProp_GProps g;
        BRepGProp::SurfaceProperties(face, g);
        if (g.Mass() <= patchArea * kFaceAreaScreen)
            return true;
    } catch (const Standard_Failure &) {
        return true; /* no measurement is not evidence of a fold */
    }
    try {
        return BRepCheck_Analyzer(face).IsValid() == Standard_True;
    } catch (const Standard_Failure &) {
        return false;
    } catch (...) {
        return false;
    }
}

/* One face per triangle, sharing this build's vertices and mesh edges.
 *
 * Loose triangles have to be re-matched to each other by BRepBuilderAPI_Sewing
 * afterwards, and on a hybrid model that left the shell open where one faceted
 * region met another — a model with its holes recognised and a split down its
 * side. Sharing the edge makes those seams exact rather than approximate, and
 * it costs nothing: the mesh already knows which triangles share which edge. */
void EmitFacetedShared(BuildCtx &ctx, const Mesh &m,
                       const std::vector<int> &tris,
                       std::vector<TopoDS_Face> &out)
{
    BRep_Builder bb;
    const long long n = m.vertCount();
    auto edgeFor = [&](int a, int b) {
        const int lo = std::min(a, b), hi = std::max(a, b);
        const long long key = (long long)lo * n + hi;
        auto it = ctx.meshEdges.find(key);
        if (it != ctx.meshEdges.end())
            return it->second;
        const TopoDS_Edge e =
            BRepBuilderAPI_MakeEdge(VertexAt(ctx, lo), VertexAt(ctx, hi));
        ctx.meshEdges.emplace(key, e);
        return e;
    };
    for (int t : tris) {
        try {
            const int v[3] = {m.tri[t * 3], m.tri[t * 3 + 1], m.tri[t * 3 + 2]};
            TopoDS_Wire w;
            bb.MakeWire(w);
            for (int k = 0; k < 3; ++k) {
                const int a = v[k], b = v[(k + 1) % 3];
                const TopoDS_Edge e = edgeFor(a, b);
                bb.Add(w, TopoDS::Edge(e.Oriented(
                              a < b ? TopAbs_FORWARD : TopAbs_REVERSED)));
            }
            BRepBuilderAPI_MakeFace mf(w, Standard_True);
            if (!mf.IsDone())
                continue;
            TopoDS_Face f = mf.Face();
            const Handle(Geom_Plane) pl =
                Handle(Geom_Plane)::DownCast(BRep_Tool::Surface(f));
            if (!pl.IsNull()) {
                const gp_Dir d = pl->Position().Direction();
                V3 nn(d.X(), d.Y(), d.Z());
                if (f.Orientation() == TopAbs_REVERSED)
                    nn = V3(-nn.x, -nn.y, -nn.z);
                if (Dot(nn, m.tnorm[t]) < 0)
                    f.Reverse();
            }
            out.push_back(f);
        } catch (const Standard_Failure &) {
        }
    }
}

/* Turns the face the way the mesh faces.
 *
 * A face built on a fitted surface has whatever normal the fit happened to
 * produce, and half of them come out pointing into the material. Sewing does
 * not care; every boolean and every fillet afterwards does. */
void OrientFaceLikeMesh(TopoDS_Face &face, const Handle(Geom_Surface) & surf,
                        const Mesh &m, const std::vector<int> &tris)
{
    double area = 0;
    V3 meshN;
    for (int t : tris) {
        meshN += m.tnorm[t] * m.tarea[t];
        area += m.tarea[t];
    }
    if (!(area > 0))
        return;
    meshN = Unit(meshN);
    try {
        GProp_GProps gp;
        BRepGProp::SurfaceProperties(face, gp);
        GeomAPI_ProjectPointOnSurf proj(gp.CentreOfMass(), surf);
        if (proj.NbPoints() < 1)
            return;
        Standard_Real u, v;
        proj.LowerDistanceParameters(u, v);
        gp_Pnt sp;
        gp_Vec du, dv;
        surf->D1(u, v, sp, du, dv);
        const gp_Vec sn = du.Crossed(dv);
        if (sn.Magnitude() <= 1e-12)
            return;
        const V3 nn = Unit(V3(sn.X(), sn.Y(), sn.Z()));
        const bool reversed = (face.Orientation() == TopAbs_REVERSED);
        if (Dot(nn, meshN) * (reversed ? -1.0 : 1.0) < 0)
            face.Reverse();
    } catch (const Standard_Failure &) {
    }
}

/* Where the patch sits in the surface's own (u,v) parameters. */
struct UvExtent
{
    double u1 = 0, u2 = 0, v1 = 0, v2 = 0;
    bool uFull = false, vFull = false;
    bool ok = false;
};

UvExtent MeasureUv(const Mesh &m, const std::vector<int> &tris,
                   const Handle(Geom_Surface) & surf)
{
    UvExtent e;
    Standard_Real nu1, nu2, nv1, nv2;
    surf->Bounds(nu1, nu2, nv1, nv2);
    const bool uPer = surf->IsUPeriodic() != Standard_False;
    const bool vPer = surf->IsVPeriodic() != Standard_False;

    /* Sampling rather than projecting every vertex: projection onto an
     * analytic surface is not cheap and the extent of a patch is not a
     * quantity that needs a million witnesses. */
    std::vector<int> vids;
    const size_t step = std::max<size_t>(1, tris.size() / 400);
    for (size_t i = 0; i < tris.size(); i += step) {
        for (int k = 0; k < 3; ++k)
            vids.push_back(m.tri[tris[i] * 3 + k]);
    }
    std::vector<double> us, vs;
    us.reserve(vids.size());
    vs.reserve(vids.size());
    try {
        for (int v : vids) {
            GeomAPI_ProjectPointOnSurf proj(P(m.pos[v]), surf);
            if (proj.NbPoints() < 1)
                continue;
            Standard_Real u, w;
            proj.LowerDistanceParameters(u, w);
            us.push_back(u);
            vs.push_back(w);
        }
    } catch (const Standard_Failure &) {
        return e;
    }
    if (us.size() < 3)
        return e;

    /* A periodic direction is "full" when the samples leave no wide gap
     * anywhere around the circle. Sorting and taking the largest CYCLIC gap is
     * what distinguishes a whole barrel from a fillet's quarter of one. */
    auto span = [&](std::vector<double> &t, bool periodic, double lo, double hi,
                    double &a, double &b, bool &full) {
        std::sort(t.begin(), t.end());
        if (!periodic) {
            a = t.front();
            b = t.back();
            full = false;
            return;
        }
        const double per = hi - lo;
        double gap = t.front() + per - t.back();
        size_t at = 0;
        for (size_t i = 1; i < t.size(); ++i) {
            const double g = t[i] - t[i - 1];
            if (g > gap) {
                gap = g;
                at = i;
            }
        }
        if (gap < per * 0.15) {
            a = lo;
            b = hi;
            full = true;
            return;
        }
        full = false;
        if (at == 0) {
            a = t.front();
            b = t.back();
        } else {
            a = t[at];
            b = t[at - 1] + per;
        }
    };
    span(us, uPer, nu1, nu2, e.u1, e.u2, e.uFull);
    span(vs, vPer, nv1, nv2, e.v1, e.v2, e.vFull);
    if (!(e.u2 > e.u1) || !(e.v2 > e.v1))
        return e;
    e.ok = true;
    return e;
}

/* Where a point sits in an elementary surface's own parameters.
 *
 * Closed form rather than GeomAPI_ProjectPointOnSurf, because the split below
 * asks it once per triangle rather than once per patch. */
bool ElementaryUv(const Handle(Geom_Surface) & s, const gp_Pnt &p, double &u,
                  double &v)
{
    if (Handle(Geom_CylindricalSurface) x =
            Handle(Geom_CylindricalSurface)::DownCast(s)) {
        ElSLib::Parameters(x->Cylinder(), p, u, v);
        return true;
    }
    if (Handle(Geom_ConicalSurface) x =
            Handle(Geom_ConicalSurface)::DownCast(s)) {
        ElSLib::Parameters(x->Cone(), p, u, v);
        return true;
    }
    if (Handle(Geom_SphericalSurface) x =
            Handle(Geom_SphericalSurface)::DownCast(s)) {
        ElSLib::Parameters(x->Sphere(), p, u, v);
        return true;
    }
    if (Handle(Geom_ToroidalSurface) x =
            Handle(Geom_ToroidalSurface)::DownCast(s)) {
        ElSLib::Parameters(x->Torus(), p, u, v);
        return true;
    }
    if (Handle(Geom_Plane) x = Handle(Geom_Plane)::DownCast(s)) {
        ElSLib::Parameters(x->Pln(), p, u, v);
        return true;
    }
    return false;
}

/* Turns the surface's own seam out of the patch's way.
 *
 * Every periodic surface has one meridian where its u parameter restarts, and
 * a face is not allowed to straddle it: a wire that runs from u = 6.2 to
 * u = 0.1 is, in the only language MakeFace speaks, a wire that runs the long
 * way round the other side. Where the seam falls is arbitrary — it is wherever
 * the fitter's arithmetic happened to leave the surface's X axis — so a fillet
 * on one corner of a part builds and the identical fillet on the next corner
 * comes back inside out.
 *
 * The patch says where it may go. Sort the patch's own u values and the widest
 * empty run between them is the ground the patch does not stand on; put the
 * seam in the middle of it and no wire of this face can ever cross it. This is
 * re-parametrisation, not movement: the same points in the same places, read
 * from a different zero. */
void AlignSurfaceSeam(const Handle(Geom_Surface) & surf, const Mesh &m,
                      const std::vector<int> &tris)
{
    Handle(Geom_ElementarySurface) es =
        Handle(Geom_ElementarySurface)::DownCast(surf);
    if (es.IsNull() || surf->IsUPeriodic() == Standard_False || tris.empty())
        return;
    Standard_Real nu1, nu2, nv1, nv2;
    surf->Bounds(nu1, nu2, nv1, nv2);
    const double per = nu2 - nu1;
    if (!(per > 0))
        return;

    std::vector<double> us;
    const size_t step = std::max<size_t>(1, tris.size() / 400);
    for (size_t i = 0; i < tris.size(); i += step) {
        for (int k = 0; k < 3; ++k) {
            double u = 0, v = 0;
            if (ElementaryUv(surf, P(m.pos[m.tri[tris[i] * 3 + k]]), u, v))
                us.push_back(u);
        }
    }
    if (us.size() < 3)
        return;
    std::sort(us.begin(), us.end());
    double gap = us.front() + per - us.back();
    double mid = us.back() + gap * 0.5;
    for (size_t i = 1; i < us.size(); ++i) {
        const double g = us[i] - us[i - 1];
        if (g > gap) {
            gap = g;
            mid = us[i - 1] + g * 0.5;
        }
    }
    /* No gap at all: the patch really does go the whole way round and there is
     * nowhere to put the seam. SplitFullWraps has already seen to those. */
    if (gap < per * 1e-4)
        return;
    try {
        const gp_Ax3 pos = es->Position();
        const gp_Vec vx(pos.XDirection());
        const gp_Vec vy(pos.YDirection());
        const gp_Vec nx = vx * std::cos(mid) + vy * std::sin(mid);
        if (nx.Magnitude() < 1e-12)
            return;
        gp_Ax3 np(pos.Location(), pos.Direction(), gp_Dir(nx));
        if (np.Direct() != pos.Direct())
            np.YReverse();
        es->SetPosition(np);
    } catch (const Standard_Failure &) {
    }
}

/* Gives away the triangles of a patch that explains nothing.
 *
 * A patch left without a surface goes to the faceted shell, and where it sits
 * among patches that DO have surfaces that is usually the wrong home for it.
 * The lower band of the user's top edge is the case: the splitter could not cut
 * it at x = ±5, so the straight fillet and the two corner blends arrive as one
 * patch of six facets, and the only surface fitting all six at once is a
 * cylinder of radius 31 that exists nowhere on the part. Refused — a fragment
 * has to sweep further than 26 degrees to be believed — the six would become
 * six little planes.
 *
 * Their neighbours know what they are. Two of them lie exactly on the r=1
 * fillet above; the other four lie exactly on the R=4 corner blends. So ask,
 * triangle by triangle: does an adjacent patch's surface pass through this
 * one's corners and predict its normal? Then it belongs there. What nobody can
 * explain stays where it is and goes to triangles, as it should.
 *
 * Only OUT of patches with no surface and only INTO patches that have one, so
 * an organic model — where nothing has a surface — is untouched. */
void DissolveUnexplained(const Mesh &m, std::vector<Patch> &patches, double tol,
                         double scale)
{
    const double exactBar = tol * kExactFitFraction;
    const double h = std::max(scale * 1e-5, 1e-9);
    std::vector<int> own(m.triCount(), -1);
    std::vector<double> allowed(patches.size(), 0.0);
    for (size_t i = 0; i < patches.size(); ++i) {
        for (int t : patches[i].tris)
            own[t] = static_cast<int>(i);
        if (patches[i].fit.kind != kNone)
            allowed[i] = AgreementAllowed(patches[i], m);
    }

    /* Which recognised surfaces touch each mesh vertex.
     *
     * This is the map that says whether a corner is a JUNCTION — a point where
     * faces meet — and it is built from the surfaces only, because a patch
     * that fits nothing witnesses nothing. */
    std::vector<std::vector<int>> touch(m.pos.size());
    for (size_t i = 0; i < patches.size(); ++i) {
        if (patches[i].fit.kind == kNone)
            continue;
        for (int t : patches[i].tris) {
            for (int k = 0; k < 3; ++k) {
                std::vector<int> &tv = touch[m.tri[t * 3 + k]];
                if (tv.empty() || tv.back() != static_cast<int>(i))
                    tv.push_back(static_cast<int>(i));
            }
        }
    }
    auto junction = [&](int v, int notJ) {
        for (int k : touch[v]) {
            if (k == notJ)
                continue;
            const Fit &f = patches[k].fit;
            if (f.kind != kNone &&
                std::fabs(SurfDist(f.kind, f.q, m.pos[v])) <= exactBar)
                return true;
        }
        return false;
    };

    /* Two tiers, tightest first.
     *
     * TIER 1 is the exact bar, and it is the one that matters for a fragment
     * of a real surface: a tessellation puts its vertices ON the surface they
     * came from, so a stray of a hole's barrel rejoins the barrel and nothing
     * else does.
     *
     * TIER 2 is the model tolerance, and it is for the transition that is not
     * a surface at all. Where the boss blend crosses the top-edge fillet, the
     * ball that rolls along the edge is rolling on the blend rather than on
     * the flat, so the part has a strip there that is neither the torus nor
     * the cylinder: taken together it fits a cylinder of radius 0.93 at thirty
     * times the exact bar, and taken apart it is a dozen loose facets in the
     * middle of a rounded edge — which is the one defect a user actually sees.
     * At tolerance the fillet explains all of it but ONE corner.
     *
     * That corner is allowed to be further off, and only that kind of corner:
     * one that lies EXACTLY on another recognised surface is a point where
     * surfaces meet, a vertex of the model, and no single face is required to
     * pass through it — the builder gives it a vertex tolerance and both faces
     * end there. On the user's part it is the one point of the boss blend's
     * tangency circle that reaches the edge: 0.141 mm off the r=1 cylinder and
     * 0.000 off the torus it belongs to. */
    for (int tier = 0; tier < 2; ++tier) {
        const double bar = tier == 0 ? exactBar : tol;
        bool moved = true;
        for (int pass = 0; pass < 3 && moved; ++pass) {
            moved = false;
            for (size_t i = 0; i < patches.size(); ++i) {
                if (patches[i].fit.kind != kNone || patches[i].tris.empty())
                    continue;
                if (static_cast<int>(patches[i].tris.size()) >
                    kDissolveMaxTriangles)
                    continue;
                std::vector<int> stay;
                stay.reserve(patches[i].tris.size());
                const size_t had = patches[i].tris.size();
                for (int t : patches[i].tris) {
                    int best = -1;
                    double bestErr = 1e300;
                    for (int k = 0; k < 3; ++k) {
                        const int o = m.adj[t * 3 + k];
                        if (o < 0)
                            continue;
                        const int j = own[o];
                        if (j < 0 || j == static_cast<int>(i) ||
                            patches[j].fit.kind == kNone)
                            continue;
                        /* Same smooth run only, for the reason MergeRegions
                         * and RefineBoundaries have it: a sharp edge is a real
                         * boundary and nothing across one belongs here. */
                        if (patches[j].origin < 0 ||
                            patches[j].origin != patches[i].origin)
                            continue;
                        const Fit &f = patches[j].fit;
                        double worst = 0;
                        V3 c;
                        bool over = false;
                        for (int q = 0; q < 3; ++q) {
                            const int vi = m.tri[t * 3 + q];
                            const V3 &pnt = m.pos[vi];
                            c += pnt;
                            const double d =
                                std::fabs(SurfDist(f.kind, f.q, pnt));
                            worst = std::max(worst, d);
                            if (d > bar && !(tier == 1 && junction(vi, j)))
                                over = true;
                        }
                        if (over)
                            continue;
                        const V3 sn =
                            SurfNormal(f.kind, f.q, c * (1.0 / 3.0), h);
                        if (Norm(sn) < 0.5)
                            continue;
                        const double cosA = std::max(
                            -1.0, std::min(1.0, std::fabs(Dot(sn,
                                                              m.tnorm[t]))));
                        /* One sliver on its own has no direction to offer.
                         *
                         * A patch of several thin facets still has a shape,
                         * and the slit walls below depend on being judged by
                         * it. A patch that is a SINGLE sliver has nothing but
                         * a normal set by where the tessellator rounded one
                         * near-collinear vertex — see kSliverAspect — so that
                         * normal must neither veto a neighbour nor choose
                         * between two. Its vertices still have to lie on the
                         * surface; that is the test above, and it is the only
                         * evidence such a patch has.
                         *
                         * Left in, the shard at the crossing of the boss blend
                         * and the top-edge fillet stays: two of its corners
                         * are on that fillet to within a thousandth of a
                         * millimetre and its noise normal stands 58 degrees
                         * off it. It is also a notch in the middle of the
                         * fillet's boundary, and the fillet face cannot be
                         * built around it. */
                        const bool lone = patches[i].tris.size() == 1 &&
                                          FacetAspect(m, t) < kSliverAspect;
                        if (!lone && std::acos(cosA) > allowed[j])
                            continue;
                        /* Which neighbour, when more than one will have it.
                         *
                         * Tier 1 goes by residual, because there the surface is
                         * exact and the residual is what says so. Tier 2 has no
                         * exact answer to find — every candidate is inside
                         * tolerance by construction — so what tells which
                         * surface the strip is leaving is the way it FACES, and
                         * the score is the one RefineBoundaries uses. On the
                         * user's part the triangle at the apex of the crossing
                         * is 0.113 from the boss blend and 0.141 from the edge
                         * fillet, and it is the fillet's: six degrees off its
                         * normal against eleven off the blend's. Given to the
                         * blend instead, the blend's rim closes into a whole
                         * circle and the flat top beside it, whose rim is two
                         * arcs, has nothing to sew to. */
                        const double sc =
                            (tier == 0 || lone)
                                ? worst
                                : worst + scale * kBoundaryAngleWeight *
                                              (1.0 - cosA);
                        if (sc < bestErr) {
                            bestErr = sc;
                            best = j;
                        }
                    }
                    if (best < 0) {
                        stay.push_back(t);
                        continue;
                    }
                    patches[best].tris.push_back(t);
                    own[t] = best;
                    moved = true;
                }
                if (stay.size() != had) {
                    MR_TRACE("  patch %3d dissolved (tier %d): %d of %d "
                             "triangles taken by neighbours\n",
                             (int)i, tier, (int)(had - stay.size()), (int)had);
                    patches[i].tris.swap(stay);
                }
            }
        }
    }
    /* What nobody wanted keeps the plane it fitted.
     *
     * Size alone cannot tell a two-facet scrap from a small real face, and on
     * the user's part it gets it exactly backwards: the slit walls cut through
     * the centre hole are four facets and a fortieth of a square millimetre,
     * while the strips at the crossing of two fillets are one facet and half a
     * square millimetre. What separates them is not how big they are but what
     * stands next to them. The crossing strip lies along the fillet beside it
     * and the fillet takes it. A slit wall stands at right angles to
     * everything it touches and no neighbour will have it — which is the mesh
     * saying it is a face. Give it back its plane, which sews to its
     * neighbours as a face and would not as loose triangles. */
    for (Patch &pa : patches) {
        if (pa.fit.kind == kNone && pa.shelved.kind != kNone &&
            !pa.tris.empty()) {
            MR_TRACE("  patch restored: %d triangles no neighbour would take\n",
                     (int)pa.tris.size());
            pa.fit = pa.shelved;
        }
        pa.shelved = Fit();
    }

    std::vector<Patch> keep;
    keep.reserve(patches.size());
    for (Patch &pa : patches)
        if (!pa.tris.empty())
            keep.push_back(std::move(pa));
    patches.swap(keep);
}

/* ====================================================================== */
/* Freeform surfacing                                                     */
/* ====================================================================== */

/* What to do with the part of a model that is not made of primitives.
 *
 * Everything above this point asks "which of plane, cylinder, cone, sphere,
 * torus is this?", and on a designed part that is the whole question. On a
 * scanned or sculpted one it has no answer, and until now the answer was one
 * B-Rep face per triangle: on the user's whale, 83,162 of them. That is a
 * body, not a conversion — it cannot be filleted, it cannot be selected face
 * by face, and it is the reason the import took twenty-five seconds.
 *
 * What a reverse-engineering tool does instead is cover the shape in a few
 * large NURBS patches, and there are two halves to that.
 *
 * WHERE THE PATCHES GO is Variational Shape Approximation (Cohen-Steiner,
 * Alliez and Desbrun, SIGGRAPH 2004). Grow regions from seeds under the L2,1
 * metric — a triangle's cost of joining a region is its area times the squared
 * difference between its normal and the region's — then refit each region's
 * proxy to its own area-weighted average normal and grow again. A dozen
 * rounds settle. The regions that come out are as close to planar as the
 * count allows, which is exactly the property the other half needs.
 *
 * WHAT COVERS EACH ONE is then a height field. A region that is nearly planar
 * is a graph over its own proxy plane, so project its vertices for (u, v),
 * keep the signed height, resample onto a grid, and hand that to OCCT's
 * approximator. The grid is what makes this cheap: GeomAPI_PointsToBSplineSurface
 * wants one anyway, and the cells the region does not reach are filled by
 * relaxation so the surface leaves the region smoothly instead of flying off.
 *
 * Measured on the whale, 83,162 triangles: 128 regions in 0.26 s, 128 surfaces
 * in 2.9 s, and the median surface sits 0.148 from the mesh against a
 * tolerance of 0.408.
 *
 * A region that will not fit is left alone and its triangles go faceted, which
 * is the same bargain the rest of the file makes: two of the 128 are not
 * height fields over any plane — the thin edge of the tail fluke turns 96
 * degrees inside one region — and no grid resolution rescues them. */
struct Proxy
{
    V3 n, c;
};

/* One partition sweep: multi-source region growing under L2,1, cheapest
 * first. Deterministic — the queue breaks ties on triangle then region, and
 * both are total orders; see "Ties decide the model". */
void VsaGrow(const Mesh &m, const std::vector<int> &tris,
             const std::vector<char> &mine, const std::vector<Proxy> &px,
             const std::vector<int> &seed, std::vector<int> &label)
{
    struct Item
    {
        double cost;
        int tri, lab;
    };
    struct Cmp
    {
        bool operator()(const Item &a, const Item &b) const
        {
            if (a.cost != b.cost)
                return a.cost > b.cost;
            if (a.tri != b.tri)
                return a.tri > b.tri;
            return a.lab > b.lab;
        }
    };
    for (int t : tris)
        label[t] = -1;
    std::priority_queue<Item, std::vector<Item>, Cmp> pq;
    auto push = [&](int from, int lab) {
        for (int k = 0; k < 3; ++k) {
            const int o = m.adj[from * 3 + k];
            if (o < 0 || !mine[o] || label[o] >= 0)
                continue;
            const V3 d = m.tnorm[o] - px[lab].n;
            pq.push(Item{m.tarea[o] * Dot(d, d), o, lab});
        }
    };
    for (size_t i = 0; i < seed.size(); ++i) {
        if (seed[i] < 0)
            continue;
        label[seed[i]] = static_cast<int>(i);
        push(seed[i], static_cast<int>(i));
    }
    while (!pq.empty()) {
        const Item it = pq.top();
        pq.pop();
        if (label[it.tri] >= 0)
            continue;
        label[it.tri] = it.lab;
        push(it.tri, it.lab);
    }
}

/* Refit every proxy to its region, and pick the triangle that best represents
 * it as the next round's seed. */
void VsaRefit(const Mesh &m, const std::vector<int> &tris,
              const std::vector<int> &label, int k, std::vector<Proxy> &px,
              std::vector<int> &seed)
{
    px.assign(k, Proxy());
    seed.assign(k, -1);
    std::vector<double> aw(k, 0.0), best(k, 1e300);
    for (int t : tris) {
        const int l = label[t];
        if (l < 0)
            continue;
        px[l].n += m.tnorm[t] * m.tarea[t];
        V3 g;
        for (int q = 0; q < 3; ++q)
            g += m.pos[m.tri[t * 3 + q]];
        px[l].c += g * (m.tarea[t] / 3.0);
        aw[l] += m.tarea[t];
    }
    for (int i = 0; i < k; ++i) {
        if (aw[i] > 0) {
            px[i].n = Unit(px[i].n);
            px[i].c = px[i].c * (1.0 / aw[i]);
        }
    }
    for (int t : tris) {
        const int l = label[t];
        if (l < 0)
            continue;
        const V3 d = m.tnorm[t] - px[l].n;
        const double e = m.tarea[t] * Dot(d, d);
        if (e < best[l] || (e == best[l] && t < seed[l])) {
            best[l] = e;
            seed[l] = t;
        }
    }
}

/* A B-spline over one region's proxy plane, or null when the region is not a
 * height field over it. `err` comes back as the worst distance from the
 * region's own vertices to the GRID the surface was approximated from, which
 * is what the caller judges it on. */
/* The height field a region makes over its own proxy plane: the resampled
 * grid, and how far the region's vertices are from it.
 *
 * Split by THIS and not by a fitted surface. It is the same question — is the
 * region a graph over its plane, to within tolerance — and it costs a bilinear
 * evaluation per vertex where fitting costs OCCT an approximation: measured on
 * the whale, deciding the splits by surface fit took seven minutes and by grid
 * twelve seconds, for the same partition. Surfaces are built once, at the end,
 * on the regions that survive. */
struct RegionGrid
{
    V3 e1, e2, n, c;
    double u0 = 0, v0 = 0, su = 0, sv = 0;
    int nu = 0, nv = 0;
    std::vector<double> h;
    double err = 1e300;
    bool ok = false;
};

void BuildRegionGrid(const Mesh &m, const std::vector<int> &tris,
                     const Proxy &px, double tol, RegionGrid &rg)
{
    rg.ok = false;
    rg.err = 1e300;
    if (tris.empty())
        return;
    const V3 n = px.n;
    V3 e1 = std::fabs(n.x) < 0.9 ? Cross(n, V3(1, 0, 0)) : Cross(n, V3(0, 1, 0));
    e1 = Unit(e1);
    const V3 e2 = Cross(n, e1);
    rg.n = n;
    rg.c = px.c;
    rg.e1 = e1;
    rg.e2 = e2;

    std::vector<int> seen;
    seen.reserve(tris.size() * 3);
    for (int t : tris)
        for (int k = 0; k < 3; ++k)
            seen.push_back(m.tri[t * 3 + k]);
    std::sort(seen.begin(), seen.end());
    seen.erase(std::unique(seen.begin(), seen.end()), seen.end());

    std::vector<double> U(seen.size()), V(seen.size()), H(seen.size());
    double u0 = 1e300, u1 = -1e300, v0 = 1e300, v1 = -1e300;
    for (size_t i = 0; i < seen.size(); ++i) {
        const V3 d = m.pos[seen[i]] - px.c;
        U[i] = Dot(d, e1);
        V[i] = Dot(d, e2);
        H[i] = Dot(d, n);
        u0 = std::min(u0, U[i]);
        u1 = std::max(u1, U[i]);
        v0 = std::min(v0, V[i]);
        v1 = std::max(v1, V[i]);
    }
    const double du = u1 - u0, dv = v1 - v0;
    if (!(du > 0) || !(dv > 0))
        return;

    /* About one cell per mesh facet, bounded at both ends: below four there is
     * no surface to speak of, and above kFreeformGridMax the approximation
     * costs more than the faces it saves. */
    double areaSum = 0;
    for (int t : tris)
        areaSum += m.tarea[t];
    const double cell = std::sqrt(areaSum / static_cast<double>(tris.size())) * 1.6;
    int nu = static_cast<int>(std::ceil(du / std::max(cell, 1e-9))) + 1;
    int nv = static_cast<int>(std::ceil(dv / std::max(cell, 1e-9))) + 1;
    nu = std::max(4, std::min(nu, kFreeformGridMax));
    nv = std::max(4, std::min(nv, kFreeformGridMax));
    const double su = du / (nu - 1), sv = dv / (nv - 1);
    rg.u0 = u0;
    rg.v0 = v0;
    rg.su = su;
    rg.sv = sv;
    rg.nu = nu;
    rg.nv = nv;

    std::vector<double> g(static_cast<size_t>(nu) * nv, 0.0),
        w(static_cast<size_t>(nu) * nv, 0.0);
    for (size_t i = 0; i < seen.size(); ++i) {
        const double fu = (U[i] - u0) / su, fv = (V[i] - v0) / sv;
        const int iu = static_cast<int>(std::floor(fu));
        const int iv = static_cast<int>(std::floor(fv));
        for (int a = 0; a < 2; ++a)
            for (int b = 0; b < 2; ++b) {
                const int cu = iu + a, cv = iv + b;
                if (cu < 0 || cu >= nu || cv < 0 || cv >= nv)
                    continue;
                const double ww = std::max(0.0, 1.0 - std::fabs(fu - cu)) *
                                  std::max(0.0, 1.0 - std::fabs(fv - cv));
                g[static_cast<size_t>(cu) * nv + cv] += H[i] * ww;
                w[static_cast<size_t>(cu) * nv + cv] += ww;
            }
    }
    std::vector<char> known(g.size(), 0);
    double hLo = 1e300, hHi = -1e300;
    for (size_t i = 0; i < g.size(); ++i)
        if (w[i] > 1e-12) {
            g[i] /= w[i];
            known[i] = 1;
            hLo = std::min(hLo, g[i]);
            hHi = std::max(hHi, g[i]);
        }
    if (hLo > hHi)
        return;
    /* The cells the region does not reach get a smooth continuation of the
     * ones it does, so the surface leaves the region flat rather than flying
     * off. The face is trimmed to the region anyway; this only decides how it
     * behaves just outside, where the trimming curve has to live. */
    for (int pass = 0; pass < 200; ++pass) {
        double moved = 0;
        for (int a = 0; a < nu; ++a)
            for (int b = 0; b < nv; ++b) {
                const size_t i = static_cast<size_t>(a) * nv + b;
                if (known[i])
                    continue;
                double sum = 0;
                int c = 0;
                if (a > 0) { sum += g[i - nv]; ++c; }
                if (a < nu - 1) { sum += g[i + nv]; ++c; }
                if (b > 0) { sum += g[i - 1]; ++c; }
                if (b < nv - 1) { sum += g[i + 1]; ++c; }
                if (!c)
                    continue;
                /* Clamped to the region's own envelope. Relaxation is a
                 * smooth continuation, not an extrapolation with a licence:
                 * unclamped, four of the whale's faces had poles far enough
                 * outside their region for the builder to refuse them, and
                 * their triangles — most of the 1,871 that were still faceted
                 * — went back to being triangles. The surface is only ever
                 * used inside the region, so it has no business leaving it. */
                const double nvl = std::max(hLo, std::min(hHi, sum / c));
                moved = std::max(moved, std::fabs(nvl - g[i]));
                g[i] = nvl;
            }
        if (moved < tol * 1e-3)
            break;
    }

    /* How well the grid represents the region, bilinearly. */
    double err = 0;
    for (size_t i = 0; i < seen.size(); ++i) {
        const double fu = (U[i] - u0) / su, fv = (V[i] - v0) / sv;
        int iu = std::max(0, std::min(static_cast<int>(std::floor(fu)), nu - 2));
        int iv = std::max(0, std::min(static_cast<int>(std::floor(fv)), nv - 2));
        const double au = fu - iu, av = fv - iv;
        const double h00 = g[static_cast<size_t>(iu) * nv + iv];
        const double h10 = g[static_cast<size_t>(iu + 1) * nv + iv];
        const double h01 = g[static_cast<size_t>(iu) * nv + iv + 1];
        const double h11 = g[static_cast<size_t>(iu + 1) * nv + iv + 1];
        const double hi = (h00 * (1 - au) + h10 * au) * (1 - av) +
                          (h01 * (1 - au) + h11 * au) * av;
        err = std::max(err, std::fabs(hi - H[i]));
    }
    rg.err = err;
    rg.h.swap(g);
    rg.ok = true;
}


/* ---- fitting a surface to the region, not to a raster of it ------------
 *
 * SurfaceFromGrid below resamples the region onto a 32x32 height raster and
 * asks OCCT to approximate THAT. Two things go wrong with it, and both were
 * measured on the whale rather than guessed:
 *
 *   - Most of the raster is invention. On the regions that came out worst,
 *     between 14% and 55% of the cells were reached by any vertex at all; the
 *     rest were filled by the clamped relaxation below, and a cell of fill
 *     next to a cell of data is a step in the net that the surface has to
 *     climb.
 *   - The approximation is asked to pass within tol/4 of every node of that
 *     net, so it inserts a knot per column — 31 poles across 32 nodes — and
 *     interpolates the steps. Between the nodes the cubic then overshoots:
 *     4.57 mm on a 0.41 mm tolerance, over cells that carried data.
 *
 * Neither of the tests in front of it can see that. rg.err asks the vertices
 * about a BILINEAR reading of the grid, which cannot overshoot; and
 * SurfaceOffRegion asks the vertices about the surface, which passes near
 * them by construction. Nothing looked between the samples — which is the
 * whole of what BRepMesh has to tessellate, and the whole of what is on
 * screen. One face of the whale needed 14,973 triangles to hold 227 mm2 of
 * area and stood 2.97 mm off the model at its rim.
 *
 * So solve for the control net directly against the vertices, with a fairing
 * term to hold it where they are sparse, and then measure the surface where
 * it was never measured: between them. */

/* Clamped uniform cubic knots for n control points. */
void ClampedKnots(int n, std::vector<double> &kv)
{
    const int seg = n - 3;
    kv.assign(n + 4, 0.0);
    for (int i = 0; i < seg - 1; ++i)
        kv[4 + i] = static_cast<double>(i + 1) / seg;
    for (int i = 0; i < 4; ++i)
        kv[n + i] = 1.0;
}

int KnotSpan(const std::vector<double> &kv, int n, double t)
{
    if (t >= kv[n])
        return n - 1;
    if (t <= kv[3])
        return 3;
    int lo = 3, hi = n, mid = (lo + hi) / 2;
    while (t < kv[mid] || t >= kv[mid + 1]) {
        if (t < kv[mid])
            hi = mid;
        else
            lo = mid;
        mid = (lo + hi) / 2;
    }
    return mid;
}

/* The four non-zero cubic basis functions at t (Piegl & Tiller A2.2). */
void BasisFuns(int span, double t, const std::vector<double> &kv, double *N)
{
    double left[4], right[4];
    N[0] = 1.0;
    for (int j = 1; j <= 3; ++j) {
        left[j] = t - kv[span + 1 - j];
        right[j] = kv[span + j] - t;
        double saved = 0.0;
        for (int r = 0; r < j; ++r) {
            const double den = right[r + 1] + left[j - r];
            const double tmp = den > 0 ? N[r] / den : 0.0;
            N[r] = saved + right[r + 1] * tmp;
            saved = left[j - r] * tmp;
        }
        N[j] = saved;
    }
}

/* Cholesky solve of a small dense symmetric positive-definite system, in
 * place. Returns false if it is not positive definite. */
bool CholeskySolve(std::vector<double> &A, int n, double *rhs, int nrhs)
{
    for (int i = 0; i < n; ++i) {
        for (int j = 0; j <= i; ++j) {
            double s = A[static_cast<size_t>(i) * n + j];
            for (int k = 0; k < j; ++k)
                s -= A[static_cast<size_t>(i) * n + k] *
                     A[static_cast<size_t>(j) * n + k];
            if (i == j) {
                if (!(s > 0))
                    return false;
                A[static_cast<size_t>(i) * n + i] = std::sqrt(s);
            } else {
                A[static_cast<size_t>(i) * n + j] =
                    s / A[static_cast<size_t>(j) * n + j];
            }
        }
    }
    for (int c = 0; c < nrhs; ++c) {
        double *b = rhs + static_cast<size_t>(c) * n;
        for (int i = 0; i < n; ++i) {
            double s = b[i];
            for (int k = 0; k < i; ++k)
                s -= A[static_cast<size_t>(i) * n + k] * b[k];
            b[i] = s / A[static_cast<size_t>(i) * n + i];
        }
        for (int i = n - 1; i >= 0; --i) {
            double s = b[i];
            for (int k = i + 1; k < n; ++k)
                s -= A[static_cast<size_t>(k) * n + i] * b[k];
            b[i] = s / A[static_cast<size_t>(i) * n + i];
        }
    }
    return true;
}

/* The region's vertices and where each one sits on the proxy plane.
 *
 * This is a parameterisation and not a guess: the split recursion has already
 * established that the region is a graph over this plane — that is the whole
 * of what it measures — so the projection is injective on it. */
struct RegionUv
{
    std::vector<int> vert; /* ascending; a TOTAL order */
    std::vector<double> u, v;
    double spanU = 1, spanV = 1;
};

void RegionUvOf(const Mesh &m, const std::vector<int> &tris,
                const RegionGrid &rg, RegionUv &out)
{
    out.vert.clear();
    out.vert.reserve(tris.size() * 3);
    for (int t : tris)
        for (int k = 0; k < 3; ++k)
            out.vert.push_back(m.tri[t * 3 + k]);
    std::sort(out.vert.begin(), out.vert.end());
    out.vert.erase(std::unique(out.vert.begin(), out.vert.end()),
                   out.vert.end());
    out.spanU = std::max((rg.nu - 1) * rg.su, 1e-12);
    out.spanV = std::max((rg.nv - 1) * rg.sv, 1e-12);
    out.u.resize(out.vert.size());
    out.v.resize(out.vert.size());
    for (size_t i = 0; i < out.vert.size(); ++i) {
        const V3 d = m.pos[out.vert[i]] - rg.c;
        const double k = 1.0 - 2.0 * kFreeformNetMargin;
        out.u[i] = kFreeformNetMargin + k * std::max(0.0, std::min(1.0,
                       (Dot(d, rg.e1) - rg.u0) / out.spanU));
        out.v[i] = kFreeformNetMargin + k * std::max(0.0, std::min(1.0,
                       (Dot(d, rg.e2) - rg.v0) / out.spanV));
    }
}

/* A cubic tensor-product net, evaluated without going through OCCT. The
 * between-the-data check below evaluates it tens of thousands of times per
 * region and Geom_BSplineSurface::Value is not the way to do that. */
struct Net
{
    int nu = 0, nv = 0;
    std::vector<double> ku, kv;
    std::vector<double> p; /* nc * 3, xyz interleaved */
    V3 At(double uu, double vv) const
    {
        const int su = KnotSpan(ku, nu, uu), sv = KnotSpan(kv, nv, vv);
        double Nu[4], Nv[4];
        BasisFuns(su, uu, ku, Nu);
        BasisFuns(sv, vv, kv, Nv);
        V3 s;
        for (int i = 0; i < 4; ++i)
            for (int j = 0; j < 4; ++j) {
                const size_t id =
                    (static_cast<size_t>(su - 3 + i) * nv + (sv - 3 + j)) * 3;
                const double w = Nu[i] * Nv[j];
                s.x += w * p[id];
                s.y += w * p[id + 1];
                s.z += w * p[id + 2];
            }
        return s;
    }
};

/* Least squares for the control net, with a fairing term.
 *
 * A plain least squares with more control points than local data is singular;
 * the second difference of the net is the cheapest thing that makes it
 * definite, and it costs nothing where the data is dense. Scaled by the point
 * count so it means the same on a region of two hundred vertices and one of
 * twenty thousand. Returns the worst residual AT THE DATA. */
double FitNet(const Mesh &m, const RegionUv &uv, int nu, int nv, Net &out)
{
    const int nc = nu * nv;
    const int np = static_cast<int>(uv.vert.size());
    if (nc < 16 || np * 2 < nc)
        return 1e300;
    out.nu = nu;
    out.nv = nv;
    ClampedKnots(nu, out.ku);
    ClampedKnots(nv, out.kv);

    std::vector<double> A(static_cast<size_t>(nc) * nc, 0.0);
    std::vector<double> rhs(static_cast<size_t>(nc) * 3, 0.0);
    int ci[16];
    double cw[16];
    for (int q = 0; q < np; ++q) {
        const double uu = uv.u[q], vv = uv.v[q];
        const int su = KnotSpan(out.ku, nu, uu), sv = KnotSpan(out.kv, nv, vv);
        double Nu[4], Nv[4];
        BasisFuns(su, uu, out.ku, Nu);
        BasisFuns(sv, vv, out.kv, Nv);
        for (int i = 0; i < 4; ++i)
            for (int j = 0; j < 4; ++j) {
                ci[i * 4 + j] = (su - 3 + i) * nv + (sv - 3 + j);
                cw[i * 4 + j] = Nu[i] * Nv[j];
            }
        const V3 &g = m.pos[uv.vert[q]];
        for (int i = 0; i < 16; ++i) {
            if (cw[i] == 0)
                continue;
            for (int j = 0; j < 16; ++j)
                A[static_cast<size_t>(ci[i]) * nc + ci[j]] += cw[i] * cw[j];
            rhs[static_cast<size_t>(0) * nc + ci[i]] += cw[i] * g.x;
            rhs[static_cast<size_t>(1) * nc + ci[i]] += cw[i] * g.y;
            rhs[static_cast<size_t>(2) * nc + ci[i]] += cw[i] * g.z;
        }
    }
    {
        const double w = kFreeformFairing * np;
        const double coef[3] = {1.0, -2.0, 1.0};
        int trip[3];
        for (int a = 0; a + 2 < nu; ++a)
            for (int c = 0; c < nv; ++c) {
                for (int k = 0; k < 3; ++k)
                    trip[k] = (a + k) * nv + c;
                for (int i = 0; i < 3; ++i)
                    for (int j = 0; j < 3; ++j)
                        A[static_cast<size_t>(trip[i]) * nc + trip[j]] +=
                            w * coef[i] * coef[j];
            }
        for (int a = 0; a < nu; ++a)
            for (int c = 0; c + 2 < nv; ++c) {
                for (int k = 0; k < 3; ++k)
                    trip[k] = a * nv + (c + k);
                for (int i = 0; i < 3; ++i)
                    for (int j = 0; j < 3; ++j)
                        A[static_cast<size_t>(trip[i]) * nc + trip[j]] +=
                            w * coef[i] * coef[j];
            }
        for (int i = 0; i < nc; ++i)
            A[static_cast<size_t>(i) * nc + i] += kFreeformRidge * np;
    }
    if (!CholeskySolve(A, nc, rhs.data(), 3))
        return 1e300;
    out.p.assign(static_cast<size_t>(nc) * 3, 0.0);
    for (int i = 0; i < nc; ++i)
        for (int c = 0; c < 3; ++c)
            out.p[static_cast<size_t>(i) * 3 + c] =
                rhs[static_cast<size_t>(c) * nc + i];

    double worst = 0;
    for (int q = 0; q < np; ++q) {
        const V3 s = out.At(uv.u[q], uv.v[q]);
        worst = std::max(worst, Norm(s - m.pos[uv.vert[q]]));
    }
    return worst;
}

/* Squared distance from p to the triangle abc (Ericson, Real-Time Collision
 * Detection 5.1.5). */
double PointTriangle2(const V3 &p, const V3 &a, const V3 &b, const V3 &c)
{
    const V3 ab = b - a, ac = c - a, ap = p - a;
    const double d1 = Dot(ab, ap), d2 = Dot(ac, ap);
    if (d1 <= 0 && d2 <= 0) return Dot(p - a, p - a);
    const V3 bp = p - b;
    const double d3 = Dot(ab, bp), d4 = Dot(ac, bp);
    if (d3 >= 0 && d4 <= d3) return Dot(p - b, p - b);
    const double vc = d1 * d4 - d3 * d2;
    if (vc <= 0 && d1 >= 0 && d3 <= 0) {
        const double t = d1 / (d1 - d3);
        return Dot(p - (a + ab * t), p - (a + ab * t));
    }
    const V3 cp = p - c;
    const double d5 = Dot(ab, cp), d6 = Dot(ac, cp);
    if (d6 >= 0 && d5 <= d6) return Dot(p - c, p - c);
    const double vb = d5 * d2 - d1 * d6;
    if (vb <= 0 && d2 >= 0 && d6 <= 0) {
        const double t = d2 / (d2 - d6);
        return Dot(p - (a + ac * t), p - (a + ac * t));
    }
    const double va = d3 * d6 - d5 * d4;
    if (va <= 0 && (d4 - d3) >= 0 && (d5 - d6) >= 0) {
        const double t = (d4 - d3) / ((d4 - d3) + (d5 - d6));
        const V3 q = b + (c - b) * t;
        return Dot(p - q, p - q);
    }
    const double den = 1.0 / (va + vb + vc);
    const V3 q = a + ab * (vb * den) + ac * (vc * den);
    return Dot(p - q, p - q);
}

/* How far the surface goes BETWEEN the data.
 *
 * The one measurement nothing else makes. Sample the net at the centroid and
 * the three edge midpoints of a triangle and ask how far that is from the
 * triangle itself: the parameterisation is a graph, so the correspondence is
 * known and there is no search to do. Strided, because a region of twenty
 * thousand triangles does not need all of them to say whether its surface
 * ripples. */
double NetBetween(const Mesh &m, const std::vector<int> &tris,
                  const RegionUv &uv, const Net &net, double giveUp)
{
    const size_t step =
        std::max<size_t>(1, tris.size() / kFreeformBetweenSamples);
    double worst = 0;
    double pu[3], pv[3];
    for (size_t i = 0; i < tris.size(); i += step) {
        const int t = tris[i];
        V3 g[3];
        bool ok = true;
        for (int k = 0; k < 3; ++k) {
            const int vtx = m.tri[t * 3 + k];
            const std::vector<int>::const_iterator it =
                std::lower_bound(uv.vert.begin(), uv.vert.end(), vtx);
            if (it == uv.vert.end() || *it != vtx) { ok = false; break; }
            const size_t s = static_cast<size_t>(it - uv.vert.begin());
            pu[k] = uv.u[s];
            pv[k] = uv.v[s];
            g[k] = m.pos[vtx];
        }
        if (!ok)
            continue;
        static const double bary[4][3] = {{1. / 3, 1. / 3, 1. / 3},
                                          {0.5, 0.5, 0.0},
                                          {0.0, 0.5, 0.5},
                                          {0.5, 0.0, 0.5}};
        for (int s = 0; s < 4; ++s) {
            const double uu = bary[s][0] * pu[0] + bary[s][1] * pu[1] +
                              bary[s][2] * pu[2];
            const double vv = bary[s][0] * pv[0] + bary[s][1] * pv[1] +
                              bary[s][2] * pv[2];
            const double d2 =
                PointTriangle2(net.At(uu, vv), g[0], g[1], g[2]);
            if (d2 > worst * worst) {
                worst = std::sqrt(d2);
                if (worst > giveUp)
                    return worst;
            }
        }
    }
    return worst;
}

Handle(Geom_BSplineSurface) NetToSurface(const Net &net)
{
    try {
        TColgp_Array2OfPnt poles(1, net.nu, 1, net.nv);
        for (int i = 0; i < net.nu; ++i)
            for (int j = 0; j < net.nv; ++j) {
                const size_t id =
                    (static_cast<size_t>(i) * net.nv + j) * 3;
                poles.SetValue(i + 1, j + 1,
                               gp_Pnt(net.p[id], net.p[id + 1], net.p[id + 2]));
            }
        const int segU = net.nu - 3, segV = net.nv - 3;
        TColStd_Array1OfReal uk(1, segU + 1), vk(1, segV + 1);
        TColStd_Array1OfInteger um(1, segU + 1), vm(1, segV + 1);
        for (int i = 0; i <= segU; ++i) {
            uk.SetValue(i + 1, static_cast<double>(i) / segU);
            um.SetValue(i + 1, (i == 0 || i == segU) ? 4 : 1);
        }
        for (int i = 0; i <= segV; ++i) {
            vk.SetValue(i + 1, static_cast<double>(i) / segV);
            vm.SetValue(i + 1, (i == 0 || i == segV) ? 4 : 1);
        }
        return Handle(Geom_BSplineSurface)(
            new Geom_BSplineSurface(poles, uk, vk, um, vm, 3, 3));
    } catch (const Standard_Failure &) {
    } catch (...) {
    }
    return Handle(Geom_BSplineSurface)();
}

/* As few control points as the tolerance allows, and no more.
 *
 * Doubling up the ladder rather than starting fine is what keeps a flat flank
 * a 4x4 net: the first rung that meets tolerance wins, so the net's size is a
 * measurement of how much the region curves rather than a setting. The rung
 * is judged on the WORSE of the two errors — at the data and between it —
 * because a net fine enough to thread every vertex is exactly the one that
 * can ripple in between, and a surface is only as good as its worse half. */
Handle(Geom_Surface) SurfaceForRegion(const Mesh &m,
                                      const std::vector<int> &tris,
                                      const RegionGrid &rg, double tol,
                                      double &err)
{
    err = 1e300;
    if (!rg.ok || tris.empty())
        return Handle(Geom_Surface)();
    RegionUv uv;
    RegionUvOf(m, tris, rg, uv);
    if (uv.vert.size() < 16)
        return Handle(Geom_Surface)();
    /* The net follows the region's shape: a square net over a flank three
     * times longer than it is wide puts most of its freedom where there is no
     * data. */
    double su = 1, sv = 1;
    {
        const double r = std::sqrt(std::max(1e-9, uv.spanU) /
                                   std::max(1e-9, uv.spanV));
        su = std::max(0.35, std::min(r, 3.0));
        sv = 1.0 / su;
    }
    static const int rung[] = {4, 6, 8, 11, 15, 20};
    static const int rungs = static_cast<int>(sizeof(rung) / sizeof(rung[0]));
    Net best;
    double bestWorst = 1e300;
    for (int r = 0; r < rungs; ++r) {
        const int nu = std::max(4, static_cast<int>(std::lround(rung[r] * su)));
        const int nv = std::max(4, static_cast<int>(std::lround(rung[r] * sv)));
        if (nu * nv > 2 * static_cast<int>(uv.vert.size()))
            break;
        Net net;
        const double at = FitNet(m, uv, nu, nv, net);
        if (!(at < 1e299))
            continue;
        const double between = NetBetween(m, tris, uv, net, tol * 8);
        const double worse = std::max(at, between);
        if (worse < bestWorst) {
            bestWorst = worse;
            /* Reported as the residual AT THE DATA, which is what every other
             * kind of patch reports and what the import line has always
             * meant. The between-the-data number decides which rung wins; it
             * is a different question and mixing the two into one printed
             * figure would make a better surface look like a worse one. */
            err = at;
            best = net;
        }
        if (worse <= tol)
            break;
    }
    if (best.nu == 0)
        return Handle(Geom_Surface)();
    return Handle(Geom_Surface)(NetToSurface(best));
}

/* The B-spline over the height raster, kept only as a floor.
 *
 * SurfaceForRegion above solves for the net against the region's own
 * vertices and is better on every count measured; this is what a region
 * falls back to when that will not solve at all — too few vertices for the
 * smallest net, or a Cholesky that meets a zero — so that no region which
 * used to become a face stops becoming one. See the note on SurfaceForRegion
 * for what is wrong with fitting the raster instead of the region. */
Handle(Geom_Surface) SurfaceFromGrid(const RegionGrid &rg, double tol)
{
    if (!rg.ok)
        return Handle(Geom_Surface)();
    TColgp_Array2OfPnt pts(1, rg.nu, 1, rg.nv);
    for (int a = 0; a < rg.nu; ++a)
        for (int b = 0; b < rg.nv; ++b) {
            const V3 p = rg.c + rg.e1 * (rg.u0 + a * rg.su) +
                         rg.e2 * (rg.v0 + b * rg.sv) +
                         rg.n * rg.h[static_cast<size_t>(a) * rg.nv + b];
            pts.SetValue(a + 1, b + 1, gp_Pnt(p.x, p.y, p.z));
        }
    try {
        GeomAPI_PointsToBSplineSurface ap(pts, 3, 3, GeomAbs_C1,
                                          tol * kFreeformApproxFraction);
        if (ap.IsDone())
            return Handle(Geom_Surface)(ap.Surface());
    } catch (const Standard_Failure &) {
    } catch (...) {
    }
    return Handle(Geom_Surface)();
}

/* How far the region really is from the surface built over it.
 *
 * The grid check is a proxy and it is too kind: it asks the vertices about the
 * GRID, and between the grid nodes a B-spline through a coarse net can swing
 * a long way further. On the whale, regions the grid put inside 0.29 came back
 * as faces standing 3.0 from the mesh — the pectoral fins, where a merge had
 * grown a region until one plane could no longer hold it. So the surface is
 * asked directly, on a sample: projection costs milliseconds, which is why it
 * is not what the SPLITTING is decided by, but a few dozen points once per
 * finished region is affordable and it is the number that matters. */
double SurfaceOffRegion(const Mesh &m, const std::vector<int> &tris,
                        const Handle(Geom_Surface) &surf, double giveUp)
{
    if (surf.IsNull() || tris.empty())
        return 1e300;
    std::vector<int> seen;
    seen.reserve(tris.size() * 3);
    for (int t : tris)
        for (int k = 0; k < 3; ++k)
            seen.push_back(m.tri[t * 3 + k]);
    std::sort(seen.begin(), seen.end());
    seen.erase(std::unique(seen.begin(), seen.end()), seen.end());
    const size_t step =
        std::max<size_t>(1, seen.size() / kFreeformCheckSamples);
    double worst = 0;
    for (size_t i = 0; i < seen.size(); i += step) {
        const V3 &p = m.pos[seen[i]];
        try {
            GeomAPI_ProjectPointOnSurf pr(gp_Pnt(p.x, p.y, p.z), surf);
            if (pr.NbPoints() > 0)
                worst = std::max(worst, static_cast<double>(pr.LowerDistance()));
        } catch (const Standard_Failure &) {
            return 1e300;
        } catch (...) {
            return 1e300;
        }
        if (worst > giveUp)
            return worst;
    }
    return worst;
}

/* The area-weighted proxy of a set of triangles. */
bool ProxyOf(const Mesh &m, const std::vector<int> &tris, Proxy &pr)
{
    pr = Proxy();
    double aw = 0;
    for (int t : tris) {
        pr.n += m.tnorm[t] * m.tarea[t];
        V3 g;
        for (int q = 0; q < 3; ++q)
            g += m.pos[m.tri[t * 3 + q]];
        pr.c += g * (m.tarea[t] / 3.0);
        aw += m.tarea[t];
    }
    if (!(aw > 0))
        return false;
    pr.n = Unit(pr.n);
    pr.c = pr.c * (1.0 / aw);
    return true;
}

/* Replaces the patches that fitted nothing with a few large B-spline ones.
 *
 * Works per smooth run, because a run is the largest thing that is certainly
 * one surface: its boundary is the mesh's own sharp edges, and a region that
 * crossed one would be covering two faces of the part with one. */
void FreeformSurfaces(const Mesh &m, std::vector<Patch> &patches, double tol,
                      int &made)
{
    made = 0;
    /* Which triangles are still unexplained, grouped by the run they came
     * from. A patch with a fit is a face already and is left alone. */
    std::unordered_map<int, std::vector<int>> loose;
    for (const Patch &pa : patches) {
        if (pa.fit.kind != kNone || pa.tris.empty())
            continue;
        std::vector<int> &v = loose[pa.origin];
        v.insert(v.end(), pa.tris.begin(), pa.tris.end());
    }
    std::vector<int> origins;
    for (std::unordered_map<int, std::vector<int>>::iterator it = loose.begin();
         it != loose.end(); ++it)
        origins.push_back(it->first);
    std::sort(origins.begin(), origins.end()); /* a TOTAL order */

    /* Counted in triangles for the same reason fitting is: the whale's loose
     * area arrives as a handful of runs and one of them is nearly all of it. */
    {
        int looseTotal = 0;
        for (int org : origins)
            looseTotal += static_cast<int>(loose[org].size());
        SetStage(kStageFreeform, looseTotal);
    }

    std::vector<Patch> add;
    std::vector<char> consumed(m.triCount(), 0);
    std::vector<char> mine(m.triCount(), 0);
    std::vector<int> label(m.triCount(), -1);

    for (int org : origins) {
        if (Cancelled())
            return;
        std::vector<int> &tris = loose[org];
        const size_t addWas = add.size();
        if (static_cast<int>(tris.size()) < kFreeformMinRegion) {
            AddDone(static_cast<int>(tris.size())); /* dealt with, by refusing */
            continue;
        }
        std::sort(tris.begin(), tris.end()); /* a TOTAL order */
        for (int t : tris)
            mine[t] = 1;

        const int k = std::max(
            1, std::min(kFreeformMaxRegions,
                        static_cast<int>(tris.size()) / kFreeformRegionTriangles));
        std::vector<int> seed(k);
        for (int i = 0; i < k; ++i)
            seed[i] = tris[static_cast<size_t>(
                static_cast<long long>(i) * tris.size() / k)];
        std::vector<Proxy> px(k);
        for (int i = 0; i < k; ++i) {
            px[i].n = m.tnorm[seed[i]];
            V3 g;
            for (int q = 0; q < 3; ++q)
                g += m.pos[m.tri[seed[i] * 3 + q]];
            px[i].c = g * (1.0 / 3.0);
        }
        for (int it = 0; it < kFreeformRounds; ++it) {
            VsaGrow(m, tris, mine, px, seed, label);
            VsaRefit(m, tris, label, k, px, seed);
        }
        VsaGrow(m, tris, mine, px, seed, label);

        std::vector<std::vector<int>> regs(k);
        for (int t : tris)
            if (label[t] >= 0)
                regs[label[t]].push_back(t);
        for (int t : tris)
            mine[t] = 0;

        /* Cut a region in two until each half is a height field, and only
         * then build a surface on it.
         *
         * This is what makes the face count follow the SHAPE rather than the
         * triangle count: a flank that is already flat enough passes the very
         * first test and stays ONE face however large it is, while the tail
         * fluke, where the surface turns through ninety degrees in a few
         * millimetres, is cut until each piece is a graph. Starting coarse is
         * the whole point — kFreeformRegionTriangles is a ceiling on the first
         * cut, not a target size.
         *
         * Split by the GRID and not by a fitted surface. It is the same
         * question, and it costs a bilinear evaluation per vertex where
         * fitting costs OCCT an approximation: measured on the whale, deciding
         * the splits by surface fit took seven minutes, by grid twelve
         * seconds. Only what reaches the bottom of the recursion still folded
         * goes faceted. */
        std::vector<std::pair<std::vector<int>, int>> work;
        for (int i = 0; i < k; ++i)
            if (!regs[i].empty())
                work.push_back(std::make_pair(regs[i], 0));
        std::vector<std::pair<std::vector<int>, RegionGrid>> good;
        while (!work.empty()) {
            std::vector<int> reg;
            reg.swap(work.back().first);
            const int depth = work.back().second;
            work.pop_back();
            if (static_cast<int>(reg.size()) < kFreeformMinRegion)
                continue;
            Proxy pr;
            if (!ProxyOf(m, reg, pr))
                continue;
            RegionGrid rg;
            BuildRegionGrid(m, reg, pr, tol, rg);
            if (rg.ok && rg.err <= tol * kFreeformGridBar) {
                good.push_back(std::make_pair(std::vector<int>(), RegionGrid()));
                good.back().first.swap(reg);
                good.back().second = rg;
                continue;
            }
            if (depth >= kFreeformSplitDepth ||
                static_cast<int>(reg.size()) < kFreeformMinRegion * 2) {
                MR_TRACE("    freeform region %d tri: not a height field at "
                         "depth %d (err %.4f)\n",
                         (int)reg.size(), depth, rg.err);
                continue;
            }
            std::sort(reg.begin(), reg.end());
            for (int t : reg)
                mine[t] = 1;
            /* Seed the cut at the two triangles that face the most different
             * ways. Taking the first and the middle of the list seeds both
             * halves in the same place as often as not, and then one half
             * comes back empty and the region is abandoned — which is where
             * 2,878 of the whale's triangles were still going. */
            std::vector<int> sseed(2);
            std::vector<Proxy> spx(2);
            sseed[0] = reg.front();
            {
                double far = -1;
                for (int t : reg) {
                    const double d = 1.0 - Dot(m.tnorm[t], pr.n);
                    if (d > far) { far = d; sseed[0] = t; }
                }
                far = -1;
                sseed[1] = reg.back();
                for (int t : reg) {
                    const double d = 1.0 - Dot(m.tnorm[t], m.tnorm[sseed[0]]);
                    if (d > far && t != sseed[0]) { far = d; sseed[1] = t; }
                }
            }
            for (int i = 0; i < 2; ++i) {
                spx[i].n = m.tnorm[sseed[i]];
                V3 g;
                for (int q = 0; q < 3; ++q)
                    g += m.pos[m.tri[sseed[i] * 3 + q]];
                spx[i].c = g * (1.0 / 3.0);
            }
            for (int it = 0; it < kFreeformRounds; ++it) {
                VsaGrow(m, reg, mine, spx, sseed, label);
                VsaRefit(m, reg, label, 2, spx, sseed);
            }
            VsaGrow(m, reg, mine, spx, sseed, label);
            std::vector<std::vector<int>> half(2);
            for (int t : reg)
                if (label[t] >= 0)
                    half[label[t]].push_back(t);
            for (int t : reg)
                mine[t] = 0;
            if (half[0].empty() || half[1].empty()) {
                /* The partition would not divide it; divide it anyway rather
                 * than abandon it — a region growing pass on a set that is
                 * already one proxy has nothing to say, but the halves still
                 * flatten. */
                half[0].assign(reg.begin(), reg.begin() + reg.size() / 2);
                half[1].assign(reg.begin() + reg.size() / 2, reg.end());
                if (half[0].empty() || half[1].empty())
                    continue;
            }
            for (int i = 0; i < 2; ++i)
                work.push_back(std::make_pair(half[i], depth + 1));
        }
        /* Then put back together everything that did not need cutting.
         *
         * Segmenting finely is what makes the cover COMPLETE — every region
         * small enough to be a graph over its plane — and it is the wrong
         * answer to how many faces the model should have: a flat flank comes
         * back as a dozen faces because a dozen is how the seeds happened to
         * fall, not because the flank is a dozen surfaces. Starting coarse
         * instead does not work either: two proxies cut a folded region into
         * two folded regions, and on the whale that left three hundred pieces
         * still faceted at the bottom of the recursion.
         *
         * So over-segment, then merge back while the union is STILL a height
         * field. That is a measurement, not a guess, and it is the same one
         * the splitting used. What comes out follows the shape: the flat
         * flanks and the underside collapse into a few large faces, and the
         * tail fluke and the blowhole, where nothing merges, keep theirs. */
        {
            std::vector<std::vector<int>> reg;
            std::vector<RegionGrid> grid;
            for (size_t i = 0; i < good.size(); ++i) {
                reg.push_back(std::vector<int>());
                reg.back().swap(good[i].first);
                grid.push_back(good[i].second);
            }
            std::vector<int> owner(m.triCount(), -1);
            bool merged = true;
            for (int pass = 0; pass < kFreeformMergePasses && merged; ++pass) {
                merged = false;
                for (size_t i = 0; i < reg.size(); ++i)
                    for (int t : reg[i])
                        owner[t] = static_cast<int>(i);
                /* Adjacent pairs, smallest union first so the small pieces are
                 * absorbed before the big ones grow past what a grid can hold.
                 * A TOTAL order; see "Ties decide the model". */
                std::vector<std::pair<int, int>> pairs;
                for (size_t i = 0; i < reg.size(); ++i)
                    for (int t : reg[i])
                        for (int q = 0; q < 3; ++q) {
                            const int o = m.adj[t * 3 + q];
                            if (o < 0)
                                continue;
                            const int j = owner[o];
                            if (j < 0 || j == static_cast<int>(i))
                                continue;
                            pairs.push_back(std::make_pair(
                                std::min(static_cast<int>(i), j),
                                std::max(static_cast<int>(i), j)));
                        }
                std::sort(pairs.begin(), pairs.end());
                pairs.erase(std::unique(pairs.begin(), pairs.end()), pairs.end());
                std::stable_sort(
                    pairs.begin(), pairs.end(),
                    [&](const std::pair<int, int> &a,
                        const std::pair<int, int> &b) {
                        const size_t sa = reg[a.first].size() + reg[a.second].size();
                        const size_t sb = reg[b.first].size() + reg[b.second].size();
                        if (sa != sb)
                            return sa < sb;
                        return a < b;
                    });
                std::vector<char> touched(reg.size(), 0);
                for (size_t pi = 0; pi < pairs.size(); ++pi) {
                    const int a = pairs[pi].first, b = pairs[pi].second;
                    if (touched[a] || touched[b] || reg[a].empty() || reg[b].empty())
                        continue;
                    if (static_cast<int>(reg[a].size() + reg[b].size()) >
                        kFreeformMaxRegionTriangles)
                        continue;
                    std::vector<int> uni(reg[a]);
                    uni.insert(uni.end(), reg[b].begin(), reg[b].end());
                    Proxy pr;
                    if (!ProxyOf(m, uni, pr))
                        continue;
                    RegionGrid rg;
                    BuildRegionGrid(m, uni, pr, tol, rg);
                    if (!rg.ok || rg.err > tol * kFreeformGridBar)
                        continue;
                    /* Judged by the surface the union would actually get,
                     * which is the one solved against its vertices — asking
                     * the raster instead let unions through that the finished
                     * face could not honour, and refused ones it could. */
                    {
                        double e = 1e300;
                        Handle(Geom_Surface) su =
                            SurfaceForRegion(m, uni, rg, tol, e);
                        if (su.IsNull()) {
                            su = SurfaceFromGrid(rg, tol);
                            if (su.IsNull() ||
                                SurfaceOffRegion(m, uni, su, tol) > tol)
                                continue;
                        } else if (e > tol) {
                            continue;
                        }
                    }
                    std::sort(uni.begin(), uni.end());
                    reg[a].swap(uni);
                    grid[a] = rg;
                    reg[b].clear();
                    touched[a] = touched[b] = 1;
                    merged = true;
                }
            }
            for (size_t i = 0; i < reg.size(); ++i) {
                if (reg[i].empty())
                    continue;
                /* Solve for the net against the region's own vertices, and
                 * fall back to the raster's answer only if that will not
                 * solve at all.
                 *
                 * Unlike the merge above, a net that misses tolerance is
                 * still taken here. The merge is a choice — refusing it
                 * leaves two faces where there might have been one — but by
                 * this point the region has already been cut as far as the
                 * recursion goes, and the only thing below the best surface
                 * available is one B-Rep face per triangle. */
                double err = 1e300;
                Handle(Geom_Surface) su =
                    SurfaceForRegion(m, reg[i], grid[i], tol, err);
                if (su.IsNull()) {
                    su = SurfaceFromGrid(grid[i], tol);
                    err = grid[i].err;
                }
                if (su.IsNull())
                    continue;
                Patch np;
                np.tris = reg[i];
                np.origin = org;
                np.fit.kind = kFreeform;
                np.fit.rms = err;
                np.freeSurf = su;
                add.push_back(np);
                for (int t : np.tris)
                    consumed[t] = 1;
                AddDone(static_cast<int>(np.tris.size()));
                ++made;
            }
        }
        /* Triangles this run could not cover are still done being TRIED, and
         * the bar counts work, not success — otherwise it stops short of its
         * own total on every model with a bit the fitter gives up on. */
        {
            int covered = 0;
            for (size_t i = addWas; i < add.size(); ++i)
                covered += static_cast<int>(add[i].tris.size());
            AddDone(static_cast<int>(tris.size()) - covered);
        }
    }
    if (add.empty())
        return;

    /* Whatever the surfaces took comes out of the patches that had it. */
    for (Patch &pa : patches) {
        if (pa.fit.kind != kNone || pa.tris.empty())
            continue;
        std::vector<int> keep;
        keep.reserve(pa.tris.size());
        for (int t : pa.tris)
            if (!consumed[t])
                keep.push_back(t);
        pa.tris.swap(keep);
    }
    std::vector<Patch> out;
    out.reserve(patches.size() + add.size());
    for (Patch &pa : patches)
        if (!pa.tris.empty())
            out.push_back(std::move(pa));
    for (Patch &pa : add)
        out.push_back(std::move(pa));
    patches.swap(out);
    MR_TRACE("  freeform: %d surfaces over %d runs\n", made, (int)origins.size());
}

/* Cuts in half every patch that wraps the whole way round.
 *
 * A patch that closes on itself — a hole's barrel, the ring of a boss blend —
 * has no seam in the mesh, so there is no boundary to build a wire from and
 * the only way to build it at all is from the surface's own parameter
 * rectangle. That rescue works, and it costs the shell: a parametrically
 * trimmed face's rim is the surface's exact circle, while the face beside it
 * ends on the chain of mesh edges, and the two are only ever as close as the
 * tessellation is fine. Nobody shares an edge, sewing is left to reconcile
 * them by distance, and round a coarse hole it cannot. Measured on the user's
 * part: twenty-two of the twenty-six edges that stopped the shell closing were
 * on one of these faces or on its neighbour, and every one of the nine
 * parametric faces in the model had a neighbour among them.
 *
 * So do not let the case arise. Cut the patch along a meridian and both halves
 * are ordinary trimmed faces whose every edge is a chain the neighbour sees
 * too, including the cut itself, which both halves walk. Two half-barrels are
 * a perfectly good B-Rep — most kernels write a drilled hole exactly that way
 * — and what is lost, one face where there were two, is put back at the end by
 * UnifySameDomain, which merges faces on a common surface and knows how to
 * build the seam that we could not.
 *
 * A patch with NO boundary at all — a whole sphere, a whole torus — is left
 * alone: there is no wire to be had there under any cut, and having no
 * neighbours it has nothing to disagree with either. */
void SplitFullWraps(const Mesh &m, std::vector<Patch> &patches,
                    std::vector<int> &patchOf, int &splitCount)
{
    const size_t n0 = patches.size();
    std::vector<int> local(m.triCount(), -1);
    std::vector<int> comp, stack;
    for (size_t i = 0; i < n0; ++i) {
        /* A freeform patch is a height field over a plane: it has no seam to
         * be on the wrong side of, and MakeSurface cannot rebuild it anyway.
         * Asking anyway cost 29 s on the user's whale. */
        if (patches[i].fit.kind == kNone || patches[i].fit.kind == kPlane ||
            patches[i].fit.kind == kFreeform)
            continue;
        if (patches[i].tris.size() < 4)
            continue;
        const Handle(Geom_Surface) surf = MakeSurface(patches[i].fit);
        if (surf.IsNull())
            continue;
        const bool uPer = surf->IsUPeriodic() != Standard_False;
        const bool vPer = surf->IsVPeriodic() != Standard_False;
        if (!uPer && !vPer)
            continue;
        /* Not a torus or a sphere. Cutting a singly-periodic surface leaves
         * halves that an ordinary wire bounds unambiguously — a half barrel is
         * a half barrel. Cutting a DOUBLY periodic one does not: the wire
         * round a band of a torus bounds that band and equally the whole rest
         * of the tube, and MakeFace answers by the surface's parametrisation
         * rather than by the mesh. Measured on the user's part, the blend ring
         * round the boss came back as everything except itself — the tube
         * curling up over the top of the model, a flap standing a millimetre
         * proud of it from every angle. Left whole, the same ring is trimmed
         * from the mesh's own uv extent and is exactly right. */
        if (uPer && vPer)
            continue;

        bool hasBoundary = false;
        for (int t : patches[i].tris) {
            for (int k = 0; k < 3; ++k) {
                const int o = m.adj[t * 3 + k];
                if (o < 0 || patchOf[o] != static_cast<int>(i)) {
                    hasBoundary = true;
                    break;
                }
            }
            if (hasBoundary)
                break;
        }
        if (!hasBoundary)
            continue;

        const UvExtent e = MeasureUv(m, patches[i].tris, surf);
        if (!e.ok)
            continue;
        const bool inU = uPer && e.uFull;
        const bool inV = !inU && vPer && e.vFull;
        if (!inU && !inV)
            continue;

        /* Only where the rim cannot be sewn WHOLE.
         *
         * A patch that closes on itself is trimmed from its own parameters,
         * and its rim is then the surface's exact circle while the face beside
         * it ends on that face's own edge. Those two sew, because both are the
         * same conic to the last decimal — that is what the exact-arc work in
         * ChainEdge bought, and it is why a plain hole, a cone and a blend
         * ring can each stay ONE face.
         *
         * It holds only while each boundary loop is a single closed chain, so
         * that rim and chain are the same curve end to end. The user's 5 mm
         * hole has four slits cut through the lower half of its wall: its
         * lower boundary is a dozen open chains, no one of them is the rim,
         * and the exact circle has nothing to be sewn to. That patch is cut in
         * half instead, and each half is an ordinary trimmed face bounded by
         * chains its neighbours share. Two half-barrels are a perfectly good
         * B-Rep — most kernels write a drilled hole exactly that way. */
        bool rimsAreWhole = true;
        {
            std::vector<std::vector<Chain>> loops;
            PatchChains(m, patches[i].tris, patchOf, static_cast<int>(i),
                        loops);
            for (const std::vector<Chain> &cs : loops) {
                if (cs.size() != 1 ||
                    cs[0].verts.front() != cs[0].verts.back()) {
                    rimsAreWhole = false;
                    break;
                }
            }
            MR_TRACE("  patch %3d full wrap: %d loops ->%s\n", (int)i,
                     (int)loops.size(), rimsAreWhole ? " share" : " SPLIT");
        }
        if (rimsAreWhole)
            continue;

        Standard_Real nu1, nu2, nv1, nv2;
        surf->Bounds(nu1, nu2, nv1, nv2);
        const double lo = inU ? nu1 : nv1;
        const double per = inU ? (nu2 - nu1) : (nv2 - nv1);
        if (!(per > 0))
            continue;

        /* Which side of the cut each triangle falls on, by its centroid. */
        const std::vector<int> tris = patches[i].tris;
        std::vector<int> side(tris.size(), 0);
        bool ok = true;
        for (size_t k = 0; k < tris.size() && ok; ++k) {
            const int t = tris[k];
            V3 c;
            for (int j = 0; j < 3; ++j)
                c += m.pos[m.tri[t * 3 + j]];
            c = c * (1.0 / 3.0);
            double u = 0, w = 0;
            if (!ElementaryUv(surf, P(c), u, w)) {
                ok = false;
                break;
            }
            double a = (inU ? u : w) - lo;
            a -= std::floor(a / per) * per;
            side[k] = (a < per * 0.5) ? 0 : 1;
        }
        if (!ok)
            continue;

        /* Each half in its own right: a cut can leave more than two connected
         * pieces and every piece has to be one face. */
        for (size_t k = 0; k < tris.size(); ++k)
            local[tris[k]] = static_cast<int>(k);
        comp.assign(tris.size(), -1);
        int nComp = 0;
        for (size_t k = 0; k < tris.size(); ++k) {
            if (comp[k] >= 0)
                continue;
            stack.clear();
            stack.push_back(static_cast<int>(k));
            comp[k] = nComp;
            while (!stack.empty()) {
                const int at = stack.back();
                stack.pop_back();
                const int t = tris[at];
                for (int j = 0; j < 3; ++j) {
                    const int o = m.adj[t * 3 + j];
                    if (o < 0)
                        continue;
                    const int li = local[o];
                    if (li < 0 || comp[li] >= 0 || side[li] != side[at])
                        continue;
                    comp[li] = nComp;
                    stack.push_back(li);
                }
            }
            nComp++;
        }
        for (int t : tris)
            local[t] = -1;
        if (nComp < 2)
            continue;

        std::vector<std::vector<int>> pieces(nComp);
        for (size_t k = 0; k < tris.size(); ++k)
            pieces[comp[k]].push_back(tris[k]);
        patches[i].tris = pieces[0];
        for (int c = 1; c < nComp; ++c) {
            Patch np;
            np.tris = pieces[c];
            np.fit = patches[i].fit;
            np.origin = patches[i].origin;
            patches.push_back(np);
        }
        splitCount++;
        MR_TRACE("  patch %3d wraps fully in %s: cut into %d\n", (int)i,
                 inU ? "u" : "v", nComp);
    }
    patchOf.assign(m.triCount(), -1);
    for (size_t i = 0; i < patches.size(); ++i)
        for (int t : patches[i].tris)
            patchOf[t] = static_cast<int>(i);
}

/* Builds the face straight from parameter bounds.
 *
 * The path for a patch that wraps the whole way round a periodic surface — a
 * cylinder's barrel, a hole, a cone, a whole sphere. Such a patch has NO seam
 * in the mesh (it is a closed tube), so there is no boundary chain to build a
 * wire from and the wire path cannot work at all. Asking the surface for its
 * own parametric rectangle gives the seam for free, which is exactly what the
 * B-Rep needs and the mesh never had. */
bool BuildParametricFace(BuildCtx &ctx, const Mesh &m, const Patch &patch,
                         const Handle(Geom_Surface) & surf,
                         std::vector<TopoDS_Face> &out)
{
    try {
        const UvExtent e = MeasureUv(m, patch.tris, surf);
        TopoDS_Face face;
        if (!e.ok) {
            BRepBuilderAPI_MakeFace mf(surf, ctx.tol);
            if (!mf.IsDone()) {
                MR_TRACE("      param: natural bounds failed\n");
                return false;
            }
            face = mf.Face();
        } else {
            BRepBuilderAPI_MakeFace mf(surf, e.u1, e.u2, e.v1, e.v2, ctx.tol);
            if (!mf.IsDone()) {
                MR_TRACE(
                    "      param: bounds u[%.3f %.3f] v[%.3f %.3f] failed\n",
                    e.u1, e.u2, e.v1, e.v2);
                return false;
            }
            face = mf.Face();
        }
        if (face.IsNull())
            return false;
        OrientFaceLikeMesh(face, surf, m, patch.tris);
        out.push_back(face);
        return true;
    } catch (const Standard_Failure &f) {
        MR_TRACE("      param: exception %s\n",
                 f.GetMessageString() ? f.GetMessageString() : "(none)");
        return false;
    }
}

/* Builds one analytic face. Returns false when the patch has to go faceted. */
bool BuildAnalyticFace(BuildCtx &ctx, const Mesh &m, const Patch &patch,
                       int self, const std::vector<int> &patchOf,
                       const std::vector<Handle(Geom_Surface)> &surfs,
                       std::vector<TopoDS_Face> &out)
{
    const Handle(Geom_Surface) &surf = surfs[self];
    if (surf.IsNull())
        return false;

    std::vector<std::vector<Chain>> loops;
    PatchChains(m, patch.tris, patchOf, self, loops);
    MR_TRACE("      face %d: kind=%s loops=%d tris=%d\n", self,
             KindName(patch.fit.kind), (int)loops.size(),
             (int)patch.tris.size());

    /* No boundary at all means a closed surface the mesh wrapped completely —
      * a whole sphere, a whole torus. Only the parametric path has it. */
    if (loops.empty())
        return BuildParametricFace(ctx, m, patch, surf, out);

    /* Every boundary run closed, and the patch goes the whole way round: also
     * seamless, also parametric. A barrel between two caps is this case. */
    /* A boundary that goes all the way ROUND a periodic surface does not say
     * which side of itself the face is on.
     *
     * Two circles round a torus bound the ninety-degree band between them and
     * equally the two-hundred-and-seventy-degree band the other way, and
     * MakeFace picks by the surface's own parametrisation rather than by the
     * mesh. On the user's part the blend ring round the boss came back as
     * three quarters of its tube — a face of area 535 where the ring is 160,
     * ballooning out of the model and adding fifteen percent to its volume.
     * The mesh knows which band it is: MeasureUv reads the extent off the
     * triangles. So whenever a direction comes back FULL, trim
     * parametrically and do not ask MakeFace to guess. */
    if (surf->IsUPeriodic() || surf->IsVPeriodic()) {
        const UvExtent e = MeasureUv(m, patch.tris, surf);
        MR_TRACE("      periodic: uv ok=%d u[%.3f %.3f]%s v[%.3f %.3f]%s\n",
                 (int)e.ok, e.u1, e.u2, e.uFull ? " FULL" : "", e.v1, e.v2,
                 e.vFull ? " FULL" : "");
        if (e.ok && (e.uFull || e.vFull)) {
            if (BuildParametricFace(ctx, m, patch, surf, out))
                return true;
        }
    }

    std::vector<TopoDS_Wire> wires;
    for (const std::vector<Chain> &chains : loops) {
        BRepBuilderAPI_MakeWire mw;
        bool ok = true;
        for (const Chain &c : chains) {
            /* Against a FACETED neighbour, walk the mesh edges one by one and
             * take the very objects the triangles are using.
             *
             * A single edge spanning the whole chain is geometrically the same
             * polyline, and it still will not sew: the far side has one edge
             * per triangle and OCCT is left to reconcile one long curve with a
             * dozen short ones. Sharing them removes the reconciliation
             * entirely — this is what took the last 26 open edges out of a
             * hybrid shell and turned it into a solid. */
            const bool faceted =
                c.other < 0 || c.other >= static_cast<int>(surfs.size()) ||
                surfs[c.other].IsNull();
            std::vector<TopoDS_Edge> segs;
            if (faceted && c.verts.size() >= 2) {
                const long long nv = ctx.m->vertCount();
                for (size_t i = 0; i + 1 < c.verts.size(); ++i) {
                    const int a = c.verts[i], b = c.verts[i + 1];
                    if (a == b)
                        continue;
                    const int lo = std::min(a, b), hi = std::max(a, b);
                    const long long key = (long long)lo * nv + hi;
                    auto it = ctx.meshEdges.find(key);
                    TopoDS_Edge me;
                    if (it != ctx.meshEdges.end()) {
                        me = it->second;
                    } else {
                        try {
                            BRepBuilderAPI_MakeEdge mk(VertexAt(ctx, lo),
                                                       VertexAt(ctx, hi));
                            if (mk.IsDone()) {
                                me = mk.Edge();
                                ctx.meshEdges.emplace(key, me);
                            }
                        } catch (const Standard_Failure &) {
                        }
                    }
                    if (me.IsNull()) {
                        segs.clear();
                        break;
                    }
                    segs.push_back(TopoDS::Edge(me.Oriented(
                        a < b ? TopAbs_FORWARD : TopAbs_REVERSED)));
                }
            }
            if (segs.empty()) {
                const TopoDS_Edge e = ChainEdge(ctx, c, self, surf, surfs);
                if (e.IsNull()) {
                    ok = false;
                    break;
                }
                /* Which way round to walk it.
                 *
                 * A wire has a direction and the face is what lies to its
                 * LEFT, so the loop has to run the way the chains do — they
                 * were walked in the winding of the triangles that own them,
                 * which is anticlockwise about the patch's own normal. The
                 * EDGE, though, points whichever way its curve happens to be
                 * parametrised, and the two faces either side of it need it
                 * the opposite way from each other in any case. Left to
                 * MakeWire, a loop that starts on a backwards edge runs
                 * backwards entire, and the face comes out as everything
                 * OUTSIDE its own boundary: negative area, invalid, and on a
                 * filleted block a third of the volume gone with the top cap.
                 * It showed up only when the cap's four arcs became exact
                 * conics, because a polyline had happened to be parametrised
                 * the other way.
                 *
                 * The chain says which end is the start. */
                TopAbs_Orientation how = TopAbs_FORWARD;
                try {
                    TopoDS_Vertex ev1, ev2;
                    TopExp::Vertices(e, ev1, ev2);
                    if (!ev1.IsNull() && !ev2.IsNull()) {
                        const gp_Pnt a = BRep_Tool::Pnt(ev1);
                        const gp_Pnt b = BRep_Tool::Pnt(ev2);
                        const gp_Pnt f = P(m.pos[c.verts.front()]);
                        const gp_Pnt l = P(m.pos[c.verts.back()]);
                        if (a.Distance(f) + b.Distance(l) >
                            a.Distance(l) + b.Distance(f))
                            how = TopAbs_REVERSED;
                        else if (c.verts.front() == c.verts.back() &&
                                 c.verts.size() > 2) {
                            /* A closed rim: both ends are the same point, so
                             * the endpoints say nothing. Ask the tangent — at
                             * the parameter where the chain actually starts,
                             * not at the curve's own origin, which for a
                             * circle is wherever the intersector left it. */
                            Standard_Real p1, p2;
                            Handle(Geom_Curve) cu =
                                BRep_Tool::Curve(e, p1, p2);
                            if (!cu.IsNull()) {
                                GeomAPI_ProjectPointOnCurve pp0(
                                    P(m.pos[c.verts[0]]), cu);
                                if (pp0.NbPoints() > 0) {
                                    gp_Pnt pp;
                                    gp_Vec d1;
                                    cu->D1(pp0.LowerDistanceParameter(), pp,
                                           d1);
                                    const V3 go =
                                        m.pos[c.verts[1]] - m.pos[c.verts[0]];
                                    if (d1.X() * go.x + d1.Y() * go.y +
                                            d1.Z() * go.z <
                                        0)
                                        how = TopAbs_REVERSED;
                                }
                            }
                        }
                    }
                } catch (const Standard_Failure &) {
                }
                segs.push_back(TopoDS::Edge(e.Oriented(how)));
            } else {
                ctx.approximated++;
            }
            for (const TopoDS_Edge &e : segs) {
                try {
                    mw.Add(e);
                } catch (const Standard_Failure &f) {
                    MR_TRACE("        wire: Add threw (%s)\n",
                             f.GetMessageString() ? f.GetMessageString()
                                                  : "?");
                    ok = false;
                    break;
                }
                if (!mw.IsDone()) {
                    MR_TRACE("        wire: Add refused, err=%d\n",
                             (int)mw.Error());
                    ok = false;
                    break;
                }
            }
            if (!ok)
                break;
        }
        if (!ok || !mw.IsDone()) {
            MR_TRACE("      face %d: wire of %d chains failed\n", self,
                     (int)chains.size());
            /* A boundary that will not close is not a reason to throw the
             * SURFACE away — but nor may the loop simply be dropped, because
             * an inner rim left out is a hole not cut and the face then
             * covers it (measured: +194% volume, and no solid). On a periodic
             * surface the mesh's own uv extent trims it honestly instead,
             * which is how a recognised blend ring stays a blend ring when a
             * neighbouring patch leaves a nick in its edge. FaceWithinPatch
             * has the last word on anything that overreaches, and sends it to
             * triangles as before. */
            if (surf->IsUPeriodic() || surf->IsVPeriodic())
                return BuildParametricFace(ctx, m, patch, surf, out);
            return false;
        }
        wires.push_back(mw.Wire());
    }
    if (wires.empty())
        return false;

    try {
        /* Largest wire first: BRepBuilderAPI_MakeFace takes the first as the
         * outer boundary and the rest as holes. Measured once, and the order
         * settled on the ORDER THE WIRES WERE BUILT IN when two are the same
         * length — see "Ties decide the model". */
        {
            std::vector<std::pair<double, int>> byLen(wires.size());
            for (size_t i = 0; i < wires.size(); ++i) {
                GProp_GProps g;
                BRepGProp::LinearProperties(wires[i], g);
                byLen[i] = std::make_pair(-g.Mass(), static_cast<int>(i));
            }
            std::sort(byLen.begin(), byLen.end());
            std::vector<TopoDS_Wire> sorted;
            sorted.reserve(wires.size());
            for (const std::pair<double, int> &kv : byLen)
                sorted.push_back(wires[kv.second]);
            wires.swap(sorted);
        }
        /* On a periodic surface a closed wire does not say which side of
         * itself the face is on, and MakeFace decides by the surface's own
         * parametrisation rather than by the mesh.
         *
         * The blend ring round the user's boss is the case: a band of the
         * torus a millimetre thick, correctly bounded, built as everything
         * BUT that band — the rest of the tube, curling up over the top of
         * the part. Its tessellation then had nowhere sane to go and came out
         * as a flap standing a millimetre proud of the model, which is the
         * "weird artifact" visible from every angle.
         *
         * The mesh knows the answer: MeasureUv reads the band's extent off the
         * triangles. So build it, ask what it covers, and if that is not what
         * the triangles cover, take the wire the other way round. */
        const bool periodic = surf->IsUPeriodic() || surf->IsVPeriodic();

        BRepBuilderAPI_MakeFace mf(surf, wires[0], Standard_False);
        if (!mf.IsDone()) {
            MR_TRACE("      face %d: MakeFace(outer of %d wires) failed\n",
                     self, (int)wires.size());
            return false;
        }
        TopoDS_Face face = mf.Face();
        const Handle(Geom_Surface) carrier = surf;
        (void)periodic;

        /* Inner wires go on TOPOLOGICALLY, not through MakeFace::Add.
         *
         * MakeFace::Add classifies each new wire as outer or inner, and to do
         * that it needs the wire's bounding box in the surface's PARAMETERS —
         * which these edges do not have yet, because they were built from 3D
         * intersection curves. Asked anyway, OCCT raises "Bnd_Box is void", and
         * on this pipeline that meant the two faces that carry every hole in a
         * drilled plate fell back to triangles: eighteen surfaces recovered
         * perfectly and the part still arrived as 281 faces.
         *
         * ShapeFix_Face below builds the pcurves and then sorts outer from
         * inner itself, which is the order these two steps must go in. */
        {
            BRep_Builder bb;
            for (size_t i = 1; i < wires.size(); ++i)
                bb.Add(face, wires[i]);
        }

        /* The wires were built from 3D curves; the face needs pcurves on the
         * surface and a consistent outer/inner orientation before it is worth
         * sewing. ShapeFix does both, and is the reason this pipeline can hand
         * OCCT approximate input at all. */
        BRepLib::BuildCurves3d(face);

        /* Give the edges their pcurves IN PLACE, before anything is allowed to
         * rebuild them.
         *
         * ShapeFix_Face::Perform heals a face by making a new one, and the new
         * one has new edges. That is right for a face assembled from loose
         * geometry and ruinous here: these wires are built from the very
         * TopoDS_Edge objects the triangles beside them are using, which is
         * what lets a fitted face and a faceted region be sewn already rather
         * than reconciled afterwards. Measured on a curved shell with four
         * drilled holes: 719 of 3379 edges belonged to one face only after
         * Perform, and 29 of 3030 without it. ShapeFix_Edge adds the pcurve to
         * the edge that is there. */
        {
            Handle(ShapeFix_Edge) fe = new ShapeFix_Edge;
            for (TopExp_Explorer ex(face, TopAbs_EDGE); ex.More(); ex.Next()) {
                try {
                    fe->FixAddPCurve(TopoDS::Edge(ex.Current()), face,
                                     Standard_False, ctx.tol);
                } catch (const Standard_Failure &) {
                }
            }
        }
        Handle(ShapeFix_Face) fix = new ShapeFix_Face(face);
        /* The context is NOT optional, and leaving it out is what killed the
         * app on real models.
         *
         * ShapeFix_Face::Perform runs FixPeriodicDegenerated, which fires on a
         * CONICAL face whose single wire wraps the full 2*pi — a countersink, a
         * chamfered hole, a tapered boss: the commonest features there are in a
         * printed part. Every other Context() use in that file is guarded by
         * IsNull(); its last line is not:
         *
         *     myResult = aNewFace;
         *     Context()->Replace(myFace, myResult);   // ShapeFix_Face.cxx
         *
         * ShapeFix_Face, unlike ShapeFix_Shape and ShapeFix_Shell, never makes
         * a context of its own, so without this line that dereferences null and
         * takes the process down — no exception, nothing to catch, the app is
         * simply gone. Present in 7.6 and still present in the 7.9.3 we pin.
         * Giving it a context is also what ShapeFix_Shape does when it drives
         * this same tool, and it stops the null being handed further down to
         * ShapeFix_Wire, which never checks it at all. */
        fix->SetContext(new ShapeBuild_ReShape);
        fix->SetPrecision(ctx.tol);
        fix->SetMaxTolerance(ctx.tol * 100);
        fix->FixAddNaturalBoundMode() = Standard_False;
        /* Orientation only: sorting outer wire from inner, which does not
         * touch the edges. The full Perform is the thing that replaces them. */
        fix->FixOrientation();
        face = fix->Face();
        if (face.IsNull()) {
            MR_TRACE("      face %d: ShapeFix returned null\n", self);
            return false;
        }

        OrientFaceLikeMesh(face, carrier, m, patch.tris);
        out.push_back(face);
        return true;
    } catch (const Standard_Failure &f) {
        MR_TRACE("      face %d: exception %s\n", self,
                 f.GetMessageString() ? f.GetMessageString() : "(none)");
        return false;
    }
}

} // namespace

/* ====================================================================== */
/* The pipeline                                                           */
/* ====================================================================== */

namespace {

/* Sews faces into a shell, heals it, and closes it into a solid if it can.
 *
 * "If it can" is deliberate. A downloaded mesh with a hole in it cannot become
 * a solid, and returning the open shell — which the app can still display,
 * still section, still export — beats returning nothing. */
TopoDS_Shape Solidify(const TopoDS_Shape &sewn, Report &rep);

/* Is this shell closed, by the DEFINITION rather than by the flag?
 *
 * A shell is closed when every edge in it is used exactly twice — count USES,
 * not neighbouring faces, because a tube's seam edge is used twice by the one
 * face it belongs to and an ancestor map reads that as a single neighbour.
 * Degenerate edges (a cone's apex, a sphere's poles) are not boundary at all
 * and are not counted.
 *
 * The flag is asked first everywhere it is set correctly; this exists because
 * BRepBuilderAPI_Sewing does not always set it. A cone fused on a cylinder,
 * where the two meet along one full circle that each face uses once, sews into
 * a perfectly closed shell that reports itself open — and the pipeline then
 * threw a three-face reconstruction away for five hundred triangles. */
bool ShellIsClosed(const TopoDS_Shape &sh)
{
    try {
        TopTools_DataMapOfShapeInteger uses;
        bool any = false;
        for (TopExp_Explorer fx(sh, TopAbs_FACE); fx.More(); fx.Next()) {
            for (TopExp_Explorer ex(fx.Current(), TopAbs_EDGE); ex.More();
                 ex.Next()) {
                const TopoDS_Shape &e = ex.Current();
                if (BRep_Tool::Degenerated(TopoDS::Edge(e)))
                    continue;
                any = true;
                if (uses.IsBound(e))
                    uses.ChangeFind(e) += 1;
                else
                    uses.Bind(e, 1);
            }
        }
        if (!any)
            return false;
        for (TopTools_DataMapIteratorOfDataMapOfShapeInteger it(uses);
             it.More(); it.Next())
            if (it.Value() != 2)
                return false;
    } catch (const Standard_Failure &) {
        return false;
    }
    return true;
}

/* Assembles faces that ALREADY share their edges into a shell, without sewing.
 *
 * BRepBuilderAPI_Sewing rebuilds the topology it is given: it takes the faces
 * apart and re-creates their edges by geometric search. That is exactly what
 * is wanted for a pile of loose faces and exactly wrong for these, which were
 * built sharing one TopoDS_Edge per boundary on purpose — the fitted faces
 * take their seams from the same pool the triangles use. Sewing threw that
 * away and then failed to rediscover it, leaving twenty-six edges open around
 * the holes of a model whose holes were otherwise perfect.
 *
 * Returns a null shape when the faces do NOT in fact close, so the caller can
 * fall back to sewing, which is still the right tool when they don't. */
TopoDS_Shape AssembleShell(const std::vector<TopoDS_Face> &faces)
{
    if (faces.empty())
        return TopoDS_Shape();
    BRep_Builder bb;
    TopoDS_Shell sh;
    bb.MakeShell(sh);
    for (const TopoDS_Face &f : faces)
        bb.Add(sh, f);
    if (!ShellIsClosed(sh))
        return TopoDS_Shape();
    sh.Closed(Standard_True);
    return sh;
}

/* OCCT's own progress, wired to ours — and its own way of being stopped.
 *
 * Sewing is 15-34% of a fitted conversion and 15-17% of a faceted one, it is
 * one call, and until now it was the longest stretch with nothing to show and
 * no way out. BRepBuilderAPI_Sewing::Perform takes a Message_ProgressRange, so
 * both problems have the same answer: hand it an indicator that publishes what
 * it reports and answers UserBreak from the cancel flag. OCCT then unwinds the
 * sewing itself, at a point of its own choosing where its data structures are
 * consistent — which is the only safe way to interrupt it. */
class ShimProgress : public Message_ProgressIndicator
{
public:
    Standard_Boolean UserBreak() Standard_OVERRIDE { return Cancelled(); }

    void Show(const Message_ProgressScope &, const Standard_Boolean) Standard_OVERRIDE
    {
        /* GetPosition is 0..1 over the whole range. A thousand steps is finer
         * than any bar resolves and keeps the published pair as plain ints. */
        const double p = GetPosition();
        SetDone(int(std::min(1.0, std::max(0.0, p)) * 1000.0 + 0.5));
    }
};

TopoDS_Shape SewAndSolidify(const std::vector<TopoDS_Face> &faces, double tol,
                            Report &rep)
{
    /* 1000, not 0: sewing reports a real fraction of itself now, so this is a
     * counted stage like the others rather than one the bar has to sweep. */
    SetStage(kStageSewing, 1000);
    if (faces.empty())
        return TopoDS_Shape();
    TopoDS_Shape sewn;
    try {
        BRepBuilderAPI_Sewing sew(tol, Standard_True, Standard_True,
                                  Standard_True, Standard_False);
        for (const TopoDS_Face &f : faces)
            sew.Add(f);
        Handle(ShimProgress) pi = new ShimProgress;
        sew.Perform(pi->Start());
        if (Cancelled())
            return TopoDS_Shape();
        sewn = sew.SewedShape();
    } catch (const Standard_Failure &) {
        sewn = TopoDS_Shape();
    }
    if (sewn.IsNull()) {
        BRep_Builder b;
        TopoDS_Compound c;
        b.MakeCompound(c);
        for (const TopoDS_Face &f : faces)
            b.Add(c, f);
        return c;
    }

    try {
        Handle(ShapeFix_Shape) fix = new ShapeFix_Shape(sewn);
        fix->SetPrecision(tol);
        fix->SetMaxTolerance(tol * 100);
        fix->Perform();
        if (!fix->Shape().IsNull())
            sewn = fix->Shape();
    } catch (const Standard_Failure &) {
    }

    /* Sewing a single face returns the FACE, not a shell — which is exactly
     * what a whole sphere or a whole torus arrives as. Wrap the loose faces in
     * a shell first, or the explorer below finds nothing and the caller gets an
     * empty compound for a perfectly good surface. */
    if (!TopExp_Explorer(sewn, TopAbs_SHELL).More()) {
        std::vector<TopoDS_Face> loose;
        for (TopExp_Explorer ex(sewn, TopAbs_FACE); ex.More(); ex.Next()) {
            loose.push_back(TopoDS::Face(ex.Current()));
        }
        if (!loose.empty()) {
            try {
                BRep_Builder b;
                TopoDS_Shell sh;
                b.MakeShell(sh);
                for (const TopoDS_Face &f : loose)
                    b.Add(sh, f);
                /* A face closed in both parameters closes the shell by itself;
                 * BRep_Tool cannot tell, so say so explicitly. */
                Handle(ShapeFix_Shell) fs = new ShapeFix_Shell(sh);
                fs->SetPrecision(tol);
                fs->SetMaxTolerance(tol * 100);
                fs->Perform();
                if (!fs->Shell().IsNull())
                    sh = fs->Shell();
                BRepCheck_Analyzer ana(sh);
                if (loose.size() == 1) {
                    const TopoDS_Face &f = loose[0];
                    Handle(Geom_Surface) su = BRep_Tool::Surface(f);
                    const bool sphere =
                        !Handle(Geom_SphericalSurface)::DownCast(su).IsNull();
                    if (!su.IsNull() && su->IsUClosed() &&
                        (su->IsVClosed() || sphere)) {
                        /* A sphere's V runs pole to pole and reports "not
                         * closed", but the poles are degenerate points, not a
                         * boundary: the shell really is closed. */
                        sh.Closed(Standard_True);
                    }
                } else if (ana.IsValid()) {
                    BRepTools::Update(sh);
                }
                sewn = sh;
            } catch (const Standard_Failure &) {
            }
        }
    }

    return Solidify(sewn, rep);
}

/* Every closed shell becomes a solid; open ones are left as they are. A
 * compound of one solid is unwrapped, because the app's feature tree wants a
 * body, not a bag holding one. */
TopoDS_Shape Solidify(const TopoDS_Shape &sewn, Report &rep)
{
    std::vector<TopoDS_Solid> solids;
    std::vector<TopoDS_Shape> open;
    for (TopExp_Explorer ex(sewn, TopAbs_SHELL); ex.More(); ex.Next()) {
        TopoDS_Shell sh = TopoDS::Shell(ex.Current());
        rep.shells++;
        if (!sh.Closed() && ShellIsClosed(sh))
            sh.Closed(Standard_True);
        if (sh.Closed()) {
            try {
                BRepBuilderAPI_MakeSolid ms(sh);
                if (ms.IsDone()) {
                    solids.push_back(ms.Solid());
                    continue;
                }
            } catch (const Standard_Failure &) {
            }
        }
        open.push_back(sh);
    }
    rep.solids = static_cast<int>(solids.size());
    rep.closed = (!solids.empty() && open.empty()) ? 1 : 0;

    if (solids.size() == 1 && open.empty()) {
        /* Orient the solid so its volume is positive: a shell sewn from
         * inward-facing faces makes a valid solid describing the whole of
         * space minus the part, and nothing downstream survives that. */
        TopoDS_Solid s = solids[0];
        try {
            GProp_GProps g;
            BRepGProp::VolumeProperties(s, g);
            if (g.Mass() < 0)
                s.Reverse();
        } catch (const Standard_Failure &) {
        }
        return s;
    }
    if (solids.empty() && open.size() == 1)
        return open[0];

    BRep_Builder b;
    TopoDS_Compound c;
    b.MakeCompound(c);
    for (const TopoDS_Solid &s : solids)
        b.Add(c, s);
    for (const TopoDS_Shape &s : open)
        b.Add(c, s);
    return c;
}

} // namespace

namespace {

/* One B-Rep face per triangle, built as a shell that is ALREADY sewn.
 *
 * The whole of mode 0, and the safety net under mode 1: it recognises nothing,
 * but on a watertight mesh it cannot fail either.
 *
 * The obvious way — make each triangle its own face and hand the pile to
 * BRepBuilderAPI_Sewing — asks OCCT to rediscover by geometric search over
 * every face the adjacency this file computed exactly in BuildAdjacency, and
 * it charges about a millisecond per triangle to do it: 43 seconds for 40 000
 * triangles, which on an iPad is the app gone. Sharing ONE vertex per welded
 * mesh vertex and ONE edge per mesh edge makes the shell sewn by construction,
 * needs no healing afterwards (the edges are identical, not merely close), and
 * is linear. */
TopoDS_Shape FacetedShell(const Mesh &m, int &faceCount)
{
    faceCount = 0;
    BRep_Builder bb;
    std::vector<TopoDS_Vertex> vs(m.vertCount());
    for (int i = 0; i < m.vertCount(); ++i)
        vs[i] = BRepBuilderAPI_MakeVertex(P(m.pos[i]));

    std::unordered_map<long long, TopoDS_Edge> edges;
    edges.reserve(m.tri.size());
    const long long n = m.vertCount();
    auto edgeFor = [&](int a, int b) {
        const int lo = std::min(a, b), hi = std::max(a, b);
        const long long key = (long long)lo * n + hi;
        auto it = edges.find(key);
        if (it != edges.end())
            return it->second;
        const TopoDS_Edge e = BRepBuilderAPI_MakeEdge(vs[lo], vs[hi]);
        edges.emplace(key, e);
        return e;
    };

    TopoDS_Shell shell;
    bb.MakeShell(shell);
    for (int t = 0; t < m.triCount(); ++t) {
        if ((t & 255) == 0) {
            if (Cancelled())
                break;
            SetDone(t); /* every 256th: the store is cheap, the branch cheaper */
        }
        try {
            const int v[3] = {m.tri[t * 3], m.tri[t * 3 + 1], m.tri[t * 3 + 2]};
            TopoDS_Wire w;
            bb.MakeWire(w);
            for (int k = 0; k < 3; ++k) {
                const int a = v[k], b = v[(k + 1) % 3];
                const TopoDS_Edge e = edgeFor(a, b);
                /* The stored edge runs low id -> high id; a triangle that uses
                 * it the other way takes it REVERSED, which is what makes the
                 * two faces either side agree and the shell hold together. */
                bb.Add(w, TopoDS::Edge(e.Oriented(
                              a < b ? TopAbs_FORWARD : TopAbs_REVERSED)));
            }
            BRepBuilderAPI_MakeFace mf(w, Standard_True);
            if (!mf.IsDone())
                continue;
            TopoDS_Face f = mf.Face();
            /* MakeFace picks the plane by least squares and its normal is not
             * bound to the wire's winding, so half the faces come out facing
             * inward. Sewing used to hide that; a shell built directly has
             * nothing to hide it, and an inside-out face makes a solid whose
             * volume comes back zero or a tenth of the truth. The triangle
             * already knows which way it faces. */
            const Handle(Geom_Plane) pl =
                Handle(Geom_Plane)::DownCast(BRep_Tool::Surface(f));
            if (!pl.IsNull()) {
                const gp_Dir d = pl->Position().Direction();
                V3 nn(d.X(), d.Y(), d.Z());
                if (f.Orientation() == TopAbs_REVERSED)
                    nn = V3(-nn.x, -nn.y, -nn.z);
                if (Dot(nn, m.tnorm[t]) < 0)
                    f.Reverse();
            }
            bb.Add(shell, f);
            faceCount++;
        } catch (const Standard_Failure &) {
        }
    }
    if (faceCount == 0)
        return TopoDS_Shape();
    return shell;
}

TopoDS_Shape BuildFaceted(const Mesh &m, double tol, Report &rep)
{
    (void)tol;
    int built = 0;
    TopoDS_Shell shell;
    try {
        const TopoDS_Shape sh = FacetedShell(m, built);
        if (sh.IsNull() || Cancelled())
            return TopoDS_Shape();
        shell = TopoDS::Shell(sh);
    } catch (const Standard_Failure &) {
        return TopoDS_Shape();
    }
    /* Whether it closes is known exactly from the mesh, and asking OCCT to
     * work it out over a hundred thousand faces is not free. */
    if (rep.boundary_edges == 0 && rep.non_manifold_edges == 0)
        shell.Closed(Standard_True);
    rep.patches = 1;
    rep.faceted_patches = 1;
    rep.faces_built = built;
    SetStage(kStageSewing, 0);
    TopoDS_Shape out = Solidify(shell, rep);
    if (out.IsNull())
        return out;

    /* Coplanar triangles become one face — the only thing that makes a faceted
     * conversion usable at all, and about half its running time.
     *
     * Not skippable on the grounds that a curved model has nothing coplanar:
     * measured, a finely tessellated ellipsoid has 9 to 13 per cent of its
     * neighbouring pairs flat with each other to within a quarter of a degree,
     * and a coarser one a third of them. The merge earns its time there too. */
    if (Cancelled())
        return TopoDS_Shape();
    try {
        SetStage(kStageMerging, 0);
        /* The one step with no way in and no way out: OCCT offers
         * ShapeUpgrade_UnifySameDomain no progress range and no UserBreak, so
         * a cancellation arriving here is answered only when it returns. The
         * check above is what keeps that window to this call alone. */
        ShapeUpgrade_UnifySameDomain uni(out, Standard_True, Standard_True,
                                         Standard_False);
        uni.Build();
        if (!uni.Shape().IsNull())
            out = uni.Shape();
    } catch (const Standard_Failure &) {
    }
    return out;
}


/* ---- tessellating a reconstructed body so it has no holes ---------------- */

/* ---- mending a torn display mesh ---------------------------------------- */

/* Why any of this is needed.
 *
 * BRepMesh leaves part of a fitted face undrawn, and no setting fixes it.
 * Measured on the fine ellipsoid (66 faces from 12,430 source triangles): 833
 * of 18,218 face-boundary segments have no triangle at all, on 28 of the 66
 * faces. Every deflection from 0.03 to 3.0 leaves between 420 and 2,596 of
 * them; each of the 28 fails identically when meshed as the only face in a
 * shape, so it is deterministic and per-face, not a race; capping every
 * tolerance at 0.05 mm changes 833 to 797 and makes the shape invalid; the
 * Delabella triangulator instead of Watson gives 689; switching off the
 * surface-deflection control gives 661. None of them is zero.
 *
 * The cause is in the faces. All 28 that fail have a UV boundary loop that
 * CROSSES ITSELF, one to four times, and all 38 that succeed have one that
 * does not — no exceptions either way. A self-crossing boundary has no
 * inside, so the mesher's classification drops the triangles it cannot place,
 * which is exactly the ones along the rim.
 *
 * The loops are not merely badly projected: they close to 0.0e+00, and
 * re-deriving every UV by walking the loop and projecting each point from the
 * previous one's parameter — the standard cure for a pcurve that jumps —
 * removes none of the crossings and adds more (28 faces still crossing, one
 * going from 2 to 13). The two segments that cross in UV are 0.1 to 5.9 mm
 * apart in 3D. So the fitted surface really does fold back over its own
 * trimmed region, and no pcurve on it can be simple. Splitting those patches
 * until they stop folding would mean many more faces, which is the opposite
 * of what a converter is for.
 *
 * What is left is to mend the picture. A hole is bounded by nodes that are
 * already drawn and already shared with the face on the other side, so
 * closing it needs no new geometry and cannot open a crack: only triangles.
 *
 * Nothing here touches the B-Rep. The solid stays the one that was sewn and
 * checked; this adds triangles to the display mesh hanging off its faces. */

/* One drawn mesh, gathered across every face, in the winding the renderer
 * will use — a REVERSED face has its triangles flipped on the way out, so
 * they are flipped on the way in here. */
struct DrawnMesh
{
    std::vector<gp_Pnt> pos; /* node positions, world space */
    std::vector<int> ofFace; /* which face each node came from */
    std::vector<int> ofNode; /* its 1-based index inside that face */
    std::vector<int> tri;    /* three node indices per triangle */
    std::vector<int> triFace;
    std::vector<int> weld;   /* node -> the node standing for its position */
};

/* A hash grid over the drawn nodes. */
class NodeGrid
{
public:
    NodeGrid(const std::vector<gp_Pnt> &p, double cell) : pos_(p), cell_(cell)
    {
        for (size_t i = 0; i < p.size(); ++i)
            cells_[key(p[i])].push_back(static_cast<int>(i));
    }

    /* Every node within one cell of q. All 27 neighbours are searched: two
     * points either side of a cell boundary are as close as two inside one,
     * and a grid that only looks in its own cell is a snap, not a weld. */
    template <class F> void near(const gp_Pnt &q, F &&f) const
    {
        const long long i = at(q.X()), j = at(q.Y()), k = at(q.Z());
        for (long long a = i - 1; a <= i + 1; ++a)
            for (long long b = j - 1; b <= j + 1; ++b)
                for (long long c = k - 1; c <= k + 1; ++c) {
                    const auto it = cells_.find(hash(a, b, c));
                    if (it == cells_.end())
                        continue;
                    for (const int n : it->second)
                        if (pos_[n].SquareDistance(q) <= cell_ * cell_)
                            f(n);
                }
    }

private:
    long long at(double v) const
    {
        return static_cast<long long>(std::floor(v / cell_));
    }
    static long long hash(long long i, long long j, long long k)
    {
        return (i * 73856093LL) ^ (j * 19349663LL) ^ (k * 83492791LL);
    }
    long long key(const gp_Pnt &q) const
    {
        return hash(at(q.X()), at(q.Y()), at(q.Z()));
    }
    const std::vector<gp_Pnt> &pos_;
    double cell_;
    std::unordered_map<long long, std::vector<int>> cells_;
};

/* How close two drawn nodes must be to count as the same point.
 *
 * Nodes on a shared edge come from one discretisation of that edge and are
 * identical: measured index to index across a seam, 0.000000 mm. The holes
 * meanwhile survive a weld anywhere from 1e-6 to 1e-2 mm unchanged — 867 free
 * edges either way — so any tolerance in that range separates a tear from a
 * join. Scaled by the model, so a 2 mm part and a 2 m one behave alike. */
static double WeldTolerance(const TopoDS_Shape &s)
{
    Bnd_Box box;
    try {
        BRepBndLib::Add(s, box, Standard_False);
    } catch (const Standard_Failure &) {
    }
    if (box.IsVoid())
        return 1e-4;
    double x1, y1, z1, x2, y2, z2;
    box.Get(x1, y1, z1, x2, y2, z2);
    const double diag = gp_Pnt(x1, y1, z1).Distance(gp_Pnt(x2, y2, z2));
    return std::min(1e-3, std::max(1e-6, diag * 1e-6));
}

static bool GatherDrawn(const TopoDS_Shape &s, DrawnMesh &d)
{
    int fi = 0;
    for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next(), ++fi) {
        const TopoDS_Face f = TopoDS::Face(ex.Current());
        TopLoc_Location loc;
        const Handle(Poly_Triangulation) t = BRep_Tool::Triangulation(f, loc);
        if (t.IsNull() || t->NbTriangles() < 1)
            continue;
        const gp_Trsf &tr = loc.Transformation();
        const bool rev = (f.Orientation() == TopAbs_REVERSED);
        const int base = static_cast<int>(d.pos.size());
        for (int i = 1; i <= t->NbNodes(); ++i) {
            d.pos.push_back(t->Node(i).Transformed(tr));
            d.ofFace.push_back(fi);
            d.ofNode.push_back(i);
        }
        for (int i = 1; i <= t->NbTriangles(); ++i) {
            int a, b, c;
            t->Triangle(i).Get(a, b, c);
            if (rev)
                std::swap(b, c);
            d.tri.push_back(base + a - 1);
            d.tri.push_back(base + b - 1);
            d.tri.push_back(base + c - 1);
            d.triFace.push_back(fi);
        }
    }
    if (d.tri.empty())
        return false;
    NodeGrid grid(d.pos, WeldTolerance(s));
    d.weld.assign(d.pos.size(), -1);
    for (size_t v = 0; v < d.pos.size(); ++v) {
        int rep = static_cast<int>(v);
        grid.near(d.pos[v], [&](int n) {
            if (n < rep && d.weld[n] >= 0 && d.weld[n] < rep)
                rep = d.weld[n];
        });
        d.weld[v] = rep;
    }
    return true;
}

/* Cutting up a hole.
 *
 * The rim is a closed ring of points lying on one face, so it is near enough
 * planar to cut up in its own best-fit plane. Ear clipping needs no new
 * points and moves none of the ones it has — the rim is shared with the face
 * on the other side, and moving it is the crack this exists to avoid. */
static void EarClip(const std::vector<gp_Pnt> &pos,
                    const std::vector<int> &loop, std::vector<int> &out)
{
    const size_t n = loop.size();
    if (n < 3)
        return;
    /* Newell's normal, which is right for a rim that is not quite flat, and
     * which also settles the winding: in the basis built from it the ring
     * runs anticlockwise, so a clipped ear faces the way its neighbours do. */
    gp_XYZ nrm(0, 0, 0), mid(0, 0, 0);
    for (size_t i = 0; i < n; ++i) {
        const gp_Pnt &a = pos[loop[i]], &b = pos[loop[(i + 1) % n]];
        nrm += gp_XYZ((a.Y() - b.Y()) * (a.Z() + b.Z()),
                      (a.Z() - b.Z()) * (a.X() + b.X()),
                      (a.X() - b.X()) * (a.Y() + b.Y()));
        mid += a.XYZ();
    }
    if (nrm.Modulus() < 1e-24)
        return; /* a rim with no area encloses nothing */
    nrm.Normalize();
    mid /= static_cast<double>(n);
    const gp_Dir dn(nrm);
    gp_Dir seed(1, 0, 0);
    if (std::abs(dn.X()) > 0.9)
        seed = gp_Dir(0, 1, 0);
    const gp_Dir e1(seed.XYZ() - dn.XYZ() * (seed.XYZ() * dn.XYZ()));
    const gp_Dir e2 = dn.Crossed(e1);
    std::vector<double> u(n), v(n);
    for (size_t i = 0; i < n; ++i) {
        const gp_XYZ q = pos[loop[i]].XYZ() - mid;
        u[i] = q * e1.XYZ();
        v[i] = q * e2.XYZ();
    }
    std::vector<int> live(n);
    for (size_t i = 0; i < n; ++i)
        live[i] = static_cast<int>(i);
    auto cross = [&](int a, int b, int c) {
        return (u[b] - u[a]) * (v[c] - v[a]) - (v[b] - v[a]) * (u[c] - u[a]);
    };
    auto inside = [&](int a, int b, int c, int q) {
        return cross(a, b, q) > 0 && cross(b, c, q) > 0 && cross(c, a, q) > 0;
    };
    size_t guard = 0;
    while (live.size() > 3 && guard++ <= n * n + 16) {
        bool cut = false;
        for (size_t i = 0; i < live.size(); ++i) {
            const int a = live[(i + live.size() - 1) % live.size()];
            const int b = live[i];
            const int c = live[(i + 1) % live.size()];
            if (cross(a, b, c) <= 0)
                continue; /* reflex or degenerate: not an ear */
            bool clear = true;
            for (const int q : live)
                if (q != a && q != b && q != c && inside(a, b, c, q)) {
                    clear = false;
                    break;
                }
            if (!clear)
                continue;
            out.push_back(loop[a]);
            out.push_back(loop[b]);
            out.push_back(loop[c]);
            live.erase(live.begin() + static_cast<long>(i));
            cut = true;
            break;
        }
        if (!cut)
            break;
    }
    if (live.size() == 3) {
        out.push_back(loop[live[0]]);
        out.push_back(loop[live[1]]);
        out.push_back(loop[live[2]]);
        return;
    }
    /* Clipping stalls on a rim whose flattening crosses itself. A fan from
     * one corner still covers it and still invents no points; it may overlap
     * itself, which on a shaded solid is invisible, where a hole is not. */
    for (size_t i = 1; i + 1 < live.size(); ++i) {
        out.push_back(loop[live[0]]);
        out.push_back(loop[live[i]]);
        out.push_back(loop[live[i + 1]]);
    }
}

/* Where the shell legitimately stops.
 *
 * An open shell HAS a boundary, and filling it in would be a bug rather than
 * a mend. Its rim is the discretisation of the B-Rep edges only one face
 * uses; a closed solid has none of those and this returns empty. */
static void OpenRimNodes(const TopoDS_Shape &s, const DrawnMesh &d,
                         std::unordered_set<int> &out)
{
    TopTools_IndexedDataMapOfShapeListOfShape em;
    try {
        TopExp::MapShapesAndAncestors(s, TopAbs_EDGE, TopAbs_FACE, em);
    } catch (const Standard_Failure &) {
        return;
    }
    std::vector<gp_Pnt> rim;
    for (int i = 1; i <= em.Extent(); ++i) {
        const TopoDS_Edge &e = TopoDS::Edge(em.FindKey(i));
        if (BRep_Tool::Degenerated(e) || em(i).Extent() >= 2)
            continue;
        for (TopTools_ListIteratorOfListOfShape it(em(i)); it.More();
             it.Next()) {
            TopLoc_Location loc;
            const Handle(Poly_Triangulation) t =
                BRep_Tool::Triangulation(TopoDS::Face(it.Value()), loc);
            if (t.IsNull())
                continue;
            const Handle(Poly_PolygonOnTriangulation) pp =
                BRep_Tool::PolygonOnTriangulation(e, t, loc);
            if (pp.IsNull())
                continue;
            for (int a = pp->Nodes().Lower(); a <= pp->Nodes().Upper(); ++a)
                rim.push_back(
                    t->Node(pp->Nodes()(a)).Transformed(loc.Transformation()));
        }
    }
    if (rim.empty())
        return;
    NodeGrid grid(d.pos, WeldTolerance(s));
    for (const gp_Pnt &q : rim)
        grid.near(q, [&](int n) { out.insert(d.weld[n]); });
}

/* Somewhere to put the mended triangles.
 *
 * A triangulation can only name nodes of its own, so a rim node that came
 * from the neighbouring face is copied in — same position, so the two faces
 * still meet exactly. The nodes that were already there keep their indices,
 * which is what lets the edges' polygons-on-triangulation stay valid: they
 * hold indices into this very array. */
class FaceWriter
{
public:
    FaceWriter(const TopoDS_Face &f, const DrawnMesh &d, int face) : d_(d)
    {
        TopLoc_Location loc;
        tri_ = BRep_Tool::Triangulation(f, loc);
        if (tri_.IsNull())
            return;
        inv_ = loc.Transformation().Inverted();
        rev_ = (f.Orientation() == TopAbs_REVERSED);
        was_ = tri_->NbNodes();
        for (size_t v = 0; v < d.pos.size(); ++v)
            if (d.ofFace[v] == face)
                mine_.emplace(d.weld[v], d.ofNode[v]);
    }

    bool ok() const { return !tri_.IsNull() && !mine_.empty(); }

    /* The index this face knows a welded node by, copying it in if it does
     * not know it yet. */
    int nodeFor(int rep)
    {
        const auto it = mine_.find(rep);
        if (it != mine_.end())
            return it->second;
        const auto add = added_.find(rep);
        if (add != added_.end())
            return add->second;
        const int idx = was_ + static_cast<int>(fresh_.size()) + 1;
        fresh_.push_back(rep);
        added_.emplace(rep, idx);
        return idx;
    }

    void add(int a, int b, int c) { want_.push_back({a, b, c}); }

    /* Resize once, then write. Returns how many triangles were added. */
    int flush()
    {
        if (want_.empty() || tri_.IsNull())
            return 0;
        const bool uv = tri_->HasUVNodes();
        /* A stale normal array would survive the resize with nothing in its
         * new entries, and the renderer's ComputeNormals declines to touch a
         * triangulation that already claims to have them. */
        if (tri_->HasNormals())
            tri_->RemoveNormals();
        if (!fresh_.empty()) {
            tri_->ResizeNodes(was_ + static_cast<int>(fresh_.size()),
                              Standard_True);
            for (size_t i = 0; i < fresh_.size(); ++i) {
                const int idx = was_ + static_cast<int>(i) + 1;
                /* A welded node is named by the lowest-numbered node at its
                 * position, which is itself a node: no lookup needed. */
                const gp_Pnt p = d_.pos[fresh_[i]].Transformed(inv_);
                tri_->SetNode(idx, p);
                if (uv)
                    tri_->SetUVNode(idx, nearestUv(p));
            }
        }
        const int had = tri_->NbTriangles();
        tri_->ResizeTriangles(had + static_cast<int>(want_.size()),
                              Standard_True);
        for (size_t i = 0; i < want_.size(); ++i) {
            const int *t = want_[i].n;
            /* Stored the way this face stores triangles: a REVERSED face has
             * its winding flipped on the way to the renderer, so the mended
             * ones are pre-flipped to come out facing the same way. */
            tri_->SetTriangle(had + static_cast<int>(i) + 1,
                              rev_ ? Poly_Triangle(t[0], t[2], t[1])
                                   : Poly_Triangle(t[0], t[1], t[2]));
        }
        return static_cast<int>(want_.size());
    }

private:
    struct Tri
    {
        int n[3];
    };
    /* A copied-in node needs a UV of its own, because that is what the
     * renderer builds its normal from. It sits on this face's rim, so the
     * nearest node the face already has is at most one triangle away and its
     * parameter is the right neighbourhood to borrow. */
    gp_Pnt2d nearestUv(const gp_Pnt &p) const
    {
        double best = 1e300;
        gp_Pnt2d uv(0, 0);
        for (int i = 1; i <= was_; ++i) {
            const double dd = tri_->Node(i).SquareDistance(p);
            if (dd < best) {
                best = dd;
                uv = tri_->UVNode(i);
            }
        }
        return uv;
    }
    const DrawnMesh &d_;
    Handle(Poly_Triangulation) tri_;
    gp_Trsf inv_;
    bool rev_ = false;
    int was_ = 0;
    std::unordered_map<int, int> mine_;  /* welded node -> index in this face */
    std::unordered_map<int, int> added_; /* welded node -> index just made */
    std::vector<int> fresh_;
    std::vector<Tri> want_;
};

/* Is there anything to mend?
 *
 * Gathering and welding a whole model is not free — measured on a 1:1 import
 * of the whale, 82,573 faces and 83,140 triangles, it costs 500 to 1,000 ms —
 * and a faceted body never tears, so on that path it would be a tax for
 * nothing. This asks the same question per face, without a weld and without
 * leaving the face: a triangulation that covers its face uses each segment of
 * its own boundary exactly once and every other edge exactly twice. Anything
 * else is a hole or a fold. Returns at the first sign of one, so a body that
 * IS torn pays almost nothing to find out.
 *
 * Equivalent to counting the rims, not an approximation of it: the two faces
 * on an edge discretise it into the same nodes, so per-face bookkeeping that
 * balances everywhere balances globally too. */
static bool FacesLookWhole(const TopoDS_Shape &s)
{
    std::unordered_map<long long, int> edge;
    std::unordered_set<long long> onBoundary;
    for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next()) {
        const TopoDS_Face f = TopoDS::Face(ex.Current());
        TopLoc_Location loc;
        const Handle(Poly_Triangulation) t = BRep_Tool::Triangulation(f, loc);
        if (t.IsNull() || t->NbTriangles() < 1)
            return false; /* a face drawn as nothing at all */
        edge.clear();
        onBoundary.clear();
        const long long span = t->NbNodes() + 1;
        auto key = [span](int a, int b) {
            return static_cast<long long>(std::min(a, b)) * span +
                   std::max(a, b);
        };
        for (int i = 1; i <= t->NbTriangles(); ++i) {
            int n[3];
            t->Triangle(i).Get(n[0], n[1], n[2]);
            for (int k = 0; k < 3; ++k)
                if (n[k] != n[(k + 1) % 3])
                    ++edge[key(n[k], n[(k + 1) % 3])];
        }
        for (TopExp_Explorer ee(f, TopAbs_EDGE); ee.More(); ee.Next()) {
            const TopoDS_Edge e = TopoDS::Edge(ee.Current());
            if (BRep_Tool::Degenerated(e))
                continue;
            const Handle(Poly_PolygonOnTriangulation) pp =
                BRep_Tool::PolygonOnTriangulation(e, t, loc);
            if (pp.IsNull())
                return false; /* a boundary this face never laid down */
            const auto &nn = pp->Nodes();
            for (int a = nn.Lower(); a < nn.Upper(); ++a) {
                if (nn(a) == nn(a + 1))
                    continue;
                const long long k = key(nn(a), nn(a + 1));
                onBoundary.insert(k);
                const auto it = edge.find(k);
                if (it == edge.end() || it->second != 1)
                    return false; /* undrawn, or drawn from both sides */
            }
        }
        for (const auto &kv : edge)
            if (kv.second != 2 && !onBoundary.count(kv.first))
                return false; /* a fold, or a tear inside the face */
    }
    return true;
}

/* Close every hole in the drawn mesh. Returns the rim edges still open. */
static int MendTornFaces(const TopoDS_Shape &s, int *filled)
{
    if (filled)
        *filled = 0;
    if (FacesLookWhole(s))
        return 0;
    DrawnMesh d;
    if (!GatherDrawn(s, d))
        return 0;

    /* Where the drawn surface stops.
     *
     * Not "edges only one triangle uses". 133 edges of a single ellipsoid are
     * used by three or more — the mesher overlaps as well as tears — and an
     * edge used three times has an unmatched side just as an edge used once
     * does, while a rim assembled from the count alone comes out unbalanced
     * and strands the walk that follows it.
     *
     * So count DIRECTIONS. Every triangle traverses its three edges one way
     * round; a matched pair of triangles traverses their shared edge once
     * each way and cancels. What is left over — the net, per edge — is the
     * boundary of the drawn surface, and it is closed at every node whatever
     * the mesher did, because each triangle contributes as much arriving as
     * leaving. That is what makes the walk below unable to strand. */
    struct Use
    {
        int net = 0;  /* traversals low->high minus high->low */
        int face = -1;
    };
    std::unordered_map<long long, Use> use;
    const long long span = static_cast<long long>(d.pos.size()) + 1;
    for (size_t t = 0; t + 2 < d.tri.size(); t += 3)
        for (int k = 0; k < 3; ++k) {
            const int a = d.weld[d.tri[t + k]];
            const int b = d.weld[d.tri[t + (k + 1) % 3]];
            if (a == b)
                continue;
            Use &u = use[static_cast<long long>(std::min(a, b)) * span +
                         std::max(a, b)];
            u.net += (a < b) ? 1 : -1;
            if (u.face < 0)
                u.face = d.triFace[t / 3];
        }

    std::unordered_set<int> openRim;
    OpenRimNodes(s, d, openRim);

    /* A triangle walks its edge one way, so the hole beside it runs the
     * other. Following that direction keeps the mended triangles wound like
     * the ones they join. */
    struct Step
    {
        int to, face;
    };
    std::unordered_map<int, std::vector<Step>> next;
    int rim = 0;
    for (const auto &kv : use) {
        if (kv.second.net == 0)
            continue;
        const int lo = static_cast<int>(kv.first / span);
        const int hi = static_cast<int>(kv.first % span);
        if (openRim.count(lo) && openRim.count(hi))
            continue; /* the shell's own edge, not a tear */
        /* n traversals low->high unanswered means the hole beside them runs
         * high->low, and the other way about. */
        const int n = kv.second.net;
        for (int i = 0; i < std::abs(n); ++i) {
            if (n > 0)
                next[hi].push_back({lo, kv.second.face});
            else
                next[lo].push_back({hi, kv.second.face});
            ++rim;
        }
    }
    if (rim == 0)
        return 0;

    /* Walking the rims into loops.
     *
     * Not "follow until you get back where you started": several holes can
     * meet at one node, and a walk that guesses a branch there strands itself
     * — measured, 47 to 128 walks per pass ended nowhere and left between 199
     * and 1,846 rim edges unclosed. Every rim node has as many edges leaving
     * as arriving, so the rim graph is a union of cycles and needs no
     * guessing: walk anywhere, and the moment the path meets a node it has
     * already visited, cut the closed piece out and carry on from there. Each
     * edge is used once and nothing is stranded. */
    std::vector<std::vector<int>> loops;
    std::vector<int> loopFace;
    int stranded = 0;
    std::vector<int> path, faceOfStep;
    std::unordered_map<int, int> onPath;
    for (auto &start : next) {
        while (!start.second.empty()) {
            path.assign(1, start.first);
            faceOfStep.assign(1, -1);
            onPath.clear();
            onPath.emplace(start.first, 0);
            for (;;) {
                const auto it = next.find(path.back());
                if (it == next.end() || it->second.empty())
                    break;
                const Step step = it->second.back();
                it->second.pop_back();
                const auto seen = onPath.find(step.to);
                if (seen == onPath.end()) {
                    onPath.emplace(step.to, static_cast<int>(path.size()));
                    path.push_back(step.to);
                    faceOfStep.push_back(step.face);
                    continue;
                }
                /* Closed: everything from where it was seen to here. */
                const int k = seen->second;
                if (static_cast<int>(path.size()) - k >= 3) {
                    std::map<int, int> votes;
                    ++votes[step.face];
                    for (size_t i = static_cast<size_t>(k) + 1;
                         i < path.size(); ++i)
                        ++votes[faceOfStep[i]];
                    int best = -1, most = 0;
                    for (const auto &v : votes)
                        if (v.first >= 0 && v.second > most) {
                            most = v.second;
                            best = v.first;
                        }
                    loops.push_back(
                        std::vector<int>(path.begin() + k, path.end()));
                    loopFace.push_back(best);
                }
                for (size_t i = static_cast<size_t>(k) + 1; i < path.size();
                     ++i)
                    onPath.erase(path[i]);
                path.resize(static_cast<size_t>(k) + 1);
                faceOfStep.resize(static_cast<size_t>(k) + 1);
            }
            stranded += static_cast<int>(path.size()) - 1;
        }
    }
    MR_TRACE("      mend: %d rim edges -> %d loops, %d edges stranded\n", rim,
             (int)loops.size(), stranded);
    if (loops.empty())
        return rim;

    /* One writer per face, so each triangulation is resized once. */
    std::vector<TopoDS_Face> faces;
    for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next())
        faces.push_back(TopoDS::Face(ex.Current()));
    std::map<int, FaceWriter *> writers;
    int made = 0, left = rim;
    for (size_t i = 0; i < loops.size(); ++i) {
        const int fi = loopFace[i];
        if (fi < 0 || fi >= static_cast<int>(faces.size()))
            continue;
        std::vector<int> cut;
        EarClip(d.pos, loops[i], cut);
        if (cut.size() < 3)
            continue;
        auto it = writers.find(fi);
        if (it == writers.end())
            it = writers.emplace(fi, new FaceWriter(faces[fi], d, fi)).first;
        if (!it->second->ok())
            continue;
        for (size_t k = 0; k + 2 < cut.size(); k += 3)
            it->second->add(it->second->nodeFor(cut[k]),
                            it->second->nodeFor(cut[k + 1]),
                            it->second->nodeFor(cut[k + 2]));
        left -= static_cast<int>(loops[i].size());
    }
    for (auto &w : writers) {
        made += w.second->flush();
        delete w.second;
    }
    MR_TRACE("      mend: %d triangles added, %d rim edges left open\n", made,
             left);
    if (filled)
        *filled = made;
    return std::max(0, left);
}

/* The area a face's triangles actually cover. A face BRepMesh gave up on
 * covers a fraction of itself and reports success, so "has a triangulation" is
 * not the question; "how much of it is drawn" is. */
static double MeshedArea(const TopoDS_Face &f)
{
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
}

/* Spans an order of magnitude either side of what was asked for. A spread, not
 * a tuning: choosing the values to hit one model's lucky deflection would be
 * fitting a fixture rather than fixing a bug. 1.0 comes first so a shape that
 * meshes cleanly — which is nearly all of them — pays nothing at all. */
static const double kMeshLadder[] = {1.0, 1.37, 0.73, 2.11, 0.41,
                                     4.0, 0.19, 0.13, 0.09};
static const size_t kMeshRungs = sizeof(kMeshLadder) / sizeof(kMeshLadder[0]);

/* A face drawn to less than this much of itself is torn, not merely chorded. */
static const double kMeshCoverBar = 0.95;

/* How long the search for a working multiplier may take, in milliseconds.
 *
 * M336. The search is up to nine whole-shape tessellations, and the app calls
 * this on the thread it draws from, once per zoom. Measured on the whale at
 * the deflection the app asks for after the first zoom: one tessellation costs
 * 469 ms and the search costs 11,553 ms. The device froze, and it was this.
 *
 * The search now happens once per shape (see `factor`), which is the real fix;
 * this is the guarantee that does not depend on an argument. Because it is
 * paid once, at the first draw — which happens inside the import, behind the
 * wait card — it can afford to be generous: four seconds finds every fixture
 * measured its best rung (a tighter budget of 1.5 s cut the ellipsoid off at
 * the fourth rung and cost it five points of coverage), and still cannot be
 * talked into two minutes by a shape nobody has measured yet. */
const double kMeshSearchBudgetMs = 4000.0;

/* And the whole shape is done when it draws this much of its own area.
 *
 * The number to judge a pass on is AREA DRAWN, not the count of faces with no
 * triangles at all: a face BRepMesh renders at 1% of itself is a hole exactly
 * as big as the face, and counting it as present is how the first version of
 * this ladder settled for 94.6% coverage on an ellipsoid when a rung four
 * places further down drew 99.7%. Coverage already counts an empty face as
 * zero, so it is the one measure that sees both failures.
 *
 * 99.5% is above every healthy fixture measured — the broomholder and TOKA
 * report 100.12% at the first rung and stop there, paying nothing — and below
 * every defective one, so only a shape that really is missing something goes
 * looking. */
static const double kMeshDoneCover = 0.995;

} // namespace

int TessellateCovered(const TopoDS_Shape &s, double lin, double ang,
                      std::vector<double> &faceArea, double &factor)
{
    if (s.IsNull() || !(lin > 0))
        return 0;

    /* Areas are a property of the shape, which is immutable here, so they are
     * measured once; the tessellation is rebuilt on every zoom. Measured on the
     * whale, BRepGProp over 362 faces costs 150 ms and summing the triangles
     * costs 0.8 ms — the expensive half is paid once per shape, the cheap half
     * per remesh. */
    if (faceArea.empty()) {
        for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next()) {
            double a = 0;
            try {
                GProp_GProps g;
                BRepGProp::SurfaceProperties(TopoDS::Face(ex.Current()), g);
                a = g.Mass();
            } catch (const Standard_Failure &) {
            } catch (...) {
            }
            faceArea.push_back(a);
        }
    }

    /* `empty` is faces with no triangles at all — a hole. `torn` is faces
     * below the bar. A pass is judged on empty first and coverage second: a
     * whole face missing is a hole, a slightly under-covered one is a chord. */
    int empty = 0, torn = 0;
    double cover = 0;
    auto grade = [&]() {
        empty = torn = 0;
        double got = 0, tot = 0;
        size_t fi = 0;
        for (TopExp_Explorer ex(s, TopAbs_FACE); ex.More(); ex.Next(), ++fi) {
            const double want = fi < faceArea.size() ? faceArea[fi] : 0.0;
            if (!(want > 0))
                continue;
            const double have = MeshedArea(TopoDS::Face(ex.Current()));
            got += have;
            tot += want;
            if (have <= 0)
                ++empty;
            else if (have < want * kMeshCoverBar)
                ++torn;
        }
        cover = tot > 0 ? got / tot : 1.0;
    };

    /* Takes an ABSOLUTE deflection, not a multiple of the requested one — see
     * the note on what is remembered. */
    int rimsOpen = 0, mended = 0;
    auto meshAt = [&](double d) {
        try {
            BRepTools::Clean(s);
            BRepMesh_IncrementalMesh again(s, d, Standard_False, ang,
                                           Standard_True);
            (void)again;
        } catch (const Standard_Failure &) {
        } catch (...) {
        }
        /* Then close what it tore. `rimsOpen` is the count of drawn edges
         * with a triangle on one side only and nothing legitimate on the
         * other — zero on a body that draws as a closed surface, and the one
         * measure here that needs no reference area and cannot be argued
         * with. Per-face coverage, the measure this used to be judged on,
         * reads anywhere from 0.2% to 218% of the same trimmed B-spline. */
        rimsOpen = 0;
        mended = 0;
        try {
            rimsOpen = MendTornFaces(s, &mended);
        } catch (const Standard_Failure &) {
            rimsOpen = 0;
        } catch (...) {
            rimsOpen = 0;
        }
    };

    /* A shape that has already found a deflection that covers it REUSES it,
     * and does not go looking again.
     *
     * M336 — this is the freeze. The old code re-ran the whole search whenever
     * the shape did not reach the coverage bar, and the whale never reaches
     * it: BRepMesh gives up on one to four of its 305 faces at EVERY
     * deflection, so "did we reach the bar?" was false every time and the
     * ladder ran on every zoom. Nine whole-shape tessellations of an 83k
     * triangle model, on the thread the app draws from, is eleven and a half
     * seconds of a dead device — and the next gesture queues another.
     *
     * The multiplier describes the SHAPE's pathology, not the deflection, so
     * one search answers for all of them. First call pays; every zoom after it
     * costs exactly one tessellation, which is what it cost before any of this
     * existed. */
    /* What is remembered is an ABSOLUTE deflection, not a multiplier.
     *
     * A multiplier was the first attempt and it was far worse than the bug it
     * fixed: the whale settles on 0.13x at the coarse deflection the model is
     * first drawn at, and 0.13x of the deflection the app asks for when zoomed
     * right in is 0.00026 mm — 107,975 triangles and 127 SECONDS for one
     * re-tessellation. The pathology sits at a particular size relative to the
     * shape; it is not a ratio to be carried into every zoom.
     *
     * So: mesh at the requested deflection, or at the one already known to
     * cover this shape, whichever is FINER. A request finer than that needs no
     * help — it is already past the size BRepMesh was failing at — and it then
     * costs exactly what a plain tessellation costs, which is what a zoom cost
     * before any of this existed. */
    if (factor > 0) {
        meshAt(std::min(lin, factor));
        grade();
        return empty;
    }

    meshAt(lin);
    grade();
    /* Judged on the rims alone, not on empty faces.
     *
     * A face the mesher produced nothing for used to send this looking for a
     * coarser deflection, and finding one cost the WHOLE model its
     * resolution: the fine ellipsoid asked for 0.6, met one empty face, and
     * settled at 1.266 — 12,658 triangles where 0.6 gives 18,119, to flatten
     * one face of 235 mm out of 39,077. Since the mend fills an empty face's
     * outline along with every other hole, an empty face is no longer a hole
     * you can see through, and trading the model's fineness away to avoid one
     * is a bad bargain. It stays a tie-break below, not a reason to search. */
    if (rimsOpen == 0) {
        factor = lin;
        return empty;
    }

    {
        const std::chrono::steady_clock::time_point started =
            std::chrono::steady_clock::now();
        double bestLin = lin, bestCover = cover;
        int bestEmpty = empty, bestRims = rimsOpen;
        double lastTried = lin;
        for (size_t k = 0; k < kMeshRungs; ++k) {
            if (kMeshLadder[k] == 1.0)
                continue; /* measured already */
            /* Checked BEFORE the rung, not after: a budget that only stops
             * once it is already over is not a budget. */
            const double spent = std::chrono::duration<double, std::milli>(
                                     std::chrono::steady_clock::now() - started)
                                     .count();
            if (spent > kMeshSearchBudgetMs)
                break;
            meshAt(lin * kMeshLadder[k]);
            lastTried = lin * kMeshLadder[k];
            grade();
            /* Fewest rim edges the mend could not close, then fewest empty
             * faces, then most area drawn. The first two are counts of holes
             * and are exact; the per-face coverage behind `cover` is not — on
             * a trimmed B-spline it reads anywhere from 0.2% to 218% of the
             * same face — so it decides only between passes that tie on both
             * of the measures that mean something. */
            if (rimsOpen < bestRims ||
                (rimsOpen == bestRims && empty < bestEmpty) ||
                (rimsOpen == bestRims && empty == bestEmpty &&
                 cover > bestCover)) {
                bestEmpty = empty;
                bestRims = rimsOpen;
                bestCover = cover;
                bestLin = lin * kMeshLadder[k];
            }
            if (rimsOpen == 0)
                break;
        }
        if (lastTried != bestLin)
            meshAt(bestLin);
        factor = bestLin;
        grade();
    }
    return empty;
}


TopoDS_Shape Reconstruct(const double *xyz, int nv, const int *tri, int nt,
                         const Params &prm, Report &rep, std::string &err)
{
    ClearReport(rep);
    err.clear();
    if (!xyz || !tri) {
        err = "no mesh data";
        return TopoDS_Shape();
    }

    Mesh m;
    try {
        if (!BuildMesh(xyz, nv, tri, nt, prm, m, rep)) {
            err = "the mesh has no usable triangles";
            return TopoDS_Shape();
        }
        BuildAdjacency(m, rep);
        OrientMesh(m, rep);
    } catch (const std::bad_alloc &) {
        err = "the mesh is too large to load";
        return TopoDS_Shape();
    } catch (const Standard_Failure &f) {
        err = f.GetMessageString() ? f.GetMessageString()
                                   : "mesh preparation failed";
        return TopoDS_Shape();
    } catch (const std::exception &e) {
        err = e.what() ? e.what() : "mesh preparation failed";
        return TopoDS_Shape();
    } catch (...) {
        err = "mesh preparation failed";
        return TopoDS_Shape();
    }

    StageGuard stageGuard;
    g_sewFrom.store(800, std::memory_order_relaxed);
    g_sewTo.store(1000, std::memory_order_relaxed);
    SetStage(kStageWelding, 0);

    const double scale = m.diagonal;
    const double tol = std::max(scale * prm.tol_frac, 1e-9);

    /* The volume the caller's own triangles enclose. One pass, and it is the
     * only ground truth available for "is the answer still this part?" — see
     * the check at the end of this function. */
    double meshVolume = 0;
    for (int t = 0; t < m.triCount(); ++t) {
        const V3 &a = m.pos[m.tri[t * 3]];
        const V3 &b = m.pos[m.tri[t * 3 + 1]];
        const V3 &c = m.pos[m.tri[t * 3 + 2]];
        meshVolume += a.x * (b.y * c.z - b.z * c.y) -
                      a.y * (b.x * c.z - b.z * c.x) +
                      a.z * (b.x * c.y - b.y * c.x);
    }
    meshVolume = std::fabs(meshVolume / 6.0);
    std::vector<TopoDS_Face> faces;

    /* ---- faceted -------------------------------------------------- */
    if (prm.mode == 0) {
        if (m.triCount() > prm.max_faceted_triangles) {
            /* One B-Rep face per triangle is linear in the mesh and quadratic
             * in the misery: a 500k-triangle download becomes a 500k-face
             * shape that takes minutes to sew and that no later operation can
             * touch. Refuse it and say why rather than hang the app. */
            char buf[192];
            std::snprintf(buf, sizeof(buf),
                          "%d triangles is too many to convert face-by-face "
                          "(limit %d) — use the surface-fitting mode",
                          m.triCount(), prm.max_faceted_triangles);
            err = buf;
            return TopoDS_Shape();
        }
        SetStage(kStageFaceted, m.triCount());
        /* Which span sewing gets: it ends both paths and starts where the path
         * before it ended. */
        g_sewFrom.store(450, std::memory_order_relaxed);
        g_sewTo.store(610, std::memory_order_relaxed);
        TopoDS_Shape out = BuildFaceted(m, tol, rep);
        if (Cancelled()) {
            err = kCancelledMessage;
            return TopoDS_Shape();
        }
        if (out.IsNull())
            err = "the faces would not sew into a shell";
        return out;
    }

    /* ---- prismatic ------------------------------------------------ */
    std::vector<int> patchOf;
    int rawPatches = 0;
    std::vector<Patch> patches;
    std::unordered_set<int> freeform;
    try {
        MR_STAGE("start");
        SetStage(kStageSegmenting, 0);
        const double sharpDeg = FeatureAngleDeg(m, prm.sharp_deg);
        MR_TRACE("  feature angle: %.1f deg (default %.1f)\n", sharpDeg,
                 prm.sharp_deg);
        SmoothPatches(m, sharpDeg, patchOf, rawPatches);
        MR_STAGE("smooth patches");
        std::vector<std::vector<int>> byPatch(rawPatches);
        for (int t = 0; t < m.triCount(); ++t)
            byPatch[patchOf[t]].push_back(t);

        /* Counted in triangles, not in runs: see Retire. */
        SetStage(kStageFitting, m.triCount());
        RetireFrom(patches);
        for (int i = 0; i < rawPatches; ++i) {
            if (Cancelled())
                break;
            if (byPatch[i].empty())
                continue;
            /* A patch that fits nothing is several surfaces in one: met at a
             * crease too shallow for the global threshold, or met tangentially,
             * where no dihedral test will ever cut. SplitPatch tries the crease
             * first and the running fit after. */
            SplitPatch(m, byPatch[i], tol, scale, prm.min_patch_triangles, i, 0,
                       patches);
            Retire(patches);
        }
        if (Cancelled()) {
            err = kCancelledMessage;
            return TopoDS_Shape();
        }
        MR_STAGE("split");
#ifdef MESHRECON_TRACE
        {
            std::vector<int> own(m.triCount(), -1);
            for (size_t i = 0; i < patches.size(); ++i)
                for (int t : patches[i].tris)
                    own[t] = static_cast<int>(i);
            FILE *sf = std::fopen("segments_split.txt", "w");
            if (sf) {
                for (int t = 0; t < m.triCount(); ++t) {
                    const int i = own[t];
                    std::fprintf(sf, "%d %d %d %d\n", t, i,
                                 i >= 0 ? patches[i].origin : -1,
                                 i >= 0 ? (int)patches[i].fit.kind : 0);
                }
                std::fclose(sf);
            }
        }
#endif
        FreeformRuns(patches, m, tol, freeform);
        for (Patch &pa : patches)
            if (freeform.find(pa.origin) != freeform.end())
                pa.fit = Fit();
        MR_STAGE("freeform runs");
        MergeRegions(m, patches, tol, scale, 8, freeform);
        MR_STAGE("merge");
        TrimStrays(m, patches, tol, scale, prm.min_patch_triangles);
        MR_STAGE("trim strays");
        RefineBoundaries(m, patches, tol, scale, 6);
        MR_STAGE("refine boundaries");
        Regularise(patches, m, prm, tol, scale);
        MR_STAGE("regularise");
        /* Again, now that boundaries have settled and directions have been
         * snapped: a patch can be clean when it is first cut and gain a stray
         * from the neighbour it was refined against. */
        TrimStrays(m, patches, tol, scale, prm.min_patch_triangles);
        MR_STAGE("trim strays (2)");
        /* And merge again. Trimming makes new neighbours — the lower band of
         * the user's top-edge fillet was a six-facet strip that a cylinder of
         * radius 31 threads exactly, sitting right beside the r=1 cylinder
         * that actually explains it. Nothing about the strip alone refutes the
         * big cylinder; the company it keeps does. */
        MergeRegions(m, patches, tol, scale, 4, freeform);
        MR_STAGE("merge (2)");
        Consolidate(patches, m, prm, tol, scale);
        MR_STAGE("consolidate");
        /* And where two pieces of one run turn out to be one surface, let the
         * better-witnessed one have it — without refitting, which is the whole
         * point. See AdoptStronger. */
        AdoptStronger(m, patches, tol, scale);
        MR_STAGE("adopt stronger");
        /* No triangle is left out.
         *
         * The splitter can finish having placed a triangle in no piece at all,
         * and a triangle in no patch is a triangle in no FACE: a hole in the
         * shell exactly its own size and shape. One such facet sat at the
         * crossing of the boss blend and the top edge of the user's part and
         * left three free edges around it. Sweep the leftovers up by smooth
         * run and connected piece, so that at worst they arrive as facets and
         * at best DissolveUnexplained hands them to the surface they came
         * from. */
        {
            std::vector<int> own(m.triCount(), -1);
            for (size_t i = 0; i < patches.size(); ++i)
                for (int t : patches[i].tris)
                    own[t] = static_cast<int>(i);
            std::vector<char> seen(m.triCount(), 0);
            std::vector<int> stack;
            int swept = 0;
            for (int s = 0; s < m.triCount(); ++s) {
                if (own[s] >= 0 || seen[s])
                    continue;
                Patch pa;
                pa.origin = patchOf[s];
                seen[s] = 1;
                stack.assign(1, s);
                while (!stack.empty()) {
                    const int t = stack.back();
                    stack.pop_back();
                    pa.tris.push_back(t);
                    swept++;
                    for (int k = 0; k < 3; ++k) {
                        const int o = m.adj[t * 3 + k];
                        if (o >= 0 && own[o] < 0 && !seen[o] &&
                            patchOf[o] == patchOf[t]) {
                            seen[o] = 1;
                            stack.push_back(o);
                        }
                    }
                }
                patches.push_back(pa);
            }
            if (swept)
                MR_TRACE("  %d loose triangles swept into patches\n", swept);
        }
    } catch (const std::bad_alloc &) {
        err = "the mesh is too large to segment";
        return TopoDS_Shape();
    } catch (const Standard_Failure &f) {
        err =
            f.GetMessageString() ? f.GetMessageString() : "segmentation failed";
        return TopoDS_Shape();
    } catch (const std::exception &e) {
        err = e.what() ? e.what() : "segmentation failed";
        return TopoDS_Shape();
    } catch (...) {
        err = "segmentation failed";
        return TopoDS_Shape();
    }

    rep.patches = static_cast<int>(patches.size());

    /* patchOf has to be re-derived: SplitByFit renumbered everything. */
    patchOf.assign(m.triCount(), -1);
    for (size_t i = 0; i < patches.size(); ++i) {
        for (int t : patches[i].tris)
            patchOf[t] = static_cast<int>(i);
    }

    /* A patch keeps its surface only if the surface is evidence. The ones that
     * do not go to triangles INDIVIDUALLY — which is the whole difference
     * between a model whose holes are still circles and one that was thrown
     * away wholesale because its shell happened to be organic. */
    std::unordered_map<int, int> cutInto;
    for (const Patch &pa : patches)
        cutInto[pa.origin]++;
    for (size_t pi = 0; pi < patches.size(); ++pi) {
        Patch &pa = patches[pi];
        const bool frag = pa.origin < 0 || cutInto[pa.origin] > 1;
        bool tooSmallOnly = false;
        const bool keep = pa.fit.kind != kNone &&
                          Identifiable(pa, m, tol, frag, true, &tooSmallOnly);
        /* Keep the surface aside rather than throwing it away: the dissolve
         * below is a better judge of a two-facet plane than its size is. */
        if (!keep && tooSmallOnly)
            pa.shelved = pa.fit;
        MR_TRACE("  patch %3d origin %3d %5d tri  %-8s rms %.5f agree %.4f "
                 "(%.1f deg, allowed %.1f)  %s%s\n",
                 (int)pi, pa.origin, (int)pa.tris.size(),
                 KindName(pa.fit.kind), pa.fit.rms, pa.fit.agree,
                 std::acos(std::max(-1.0, std::min(1.0, pa.fit.agree))) *
                     180.0 / M_PI,
                 AgreementAllowed(pa, m) * 180.0 / M_PI,
                 keep ? "KEEP" : g_why, frag ? " (fragment)" : "");
        {
            V3 lo(1e300, 1e300, 1e300), hi(-1e300, -1e300, -1e300);
            for (int t : pa.tris)
                for (int k = 0; k < 3; ++k) {
                    const V3 &q = m.pos[m.tri[t * 3 + k]];
                    lo = V3(std::min(lo.x, q.x), std::min(lo.y, q.y),
                            std::min(lo.z, q.z));
                    hi = V3(std::max(hi.x, q.x), std::max(hi.y, q.y),
                            std::max(hi.z, q.z));
                }
            MR_TRACE("       box(%6.2f %6.2f %6.2f)-(%6.2f %6.2f %6.2f) "
                     "q[%.3f %.3f %.3f | %.3f %.3f %.3f | %.4f %.4f]\n",
                     lo.x, lo.y, lo.z, hi.x, hi.y, hi.z, pa.fit.q[0],
                     pa.fit.q[1], pa.fit.q[2], pa.fit.q[3], pa.fit.q[4],
                     pa.fit.q[5], pa.fit.q[6], pa.fit.q[7]);
        }
        if (!keep)
            pa.fit = Fit();
    }

    /* And again after merging, which changes what is explained. */
    {
        std::unordered_set<int> again;
        FreeformRuns(patches, m, tol, again);
        for (Patch &pa : patches)
            if (again.find(pa.origin) != again.end())
                pa.fit = Fit();
    }

    /* A tiny face alone in a sea of triangles is worth less than the triangles.
     *
     * A squashed ellipsoid throws off single facets whose three neighbours are
     * all across a sharp edge, so each becomes a smooth run of ONE triangle
     * that fits its own plane exactly. Nothing above rejects them and nothing
     * should: two triangles really is a box's face. What settles it is the
     * company they keep. A face among faces shares its edges with faces; a
     * face among triangles has to be stitched to a triangle strip along every
     * side, which is where a hybrid shell leaves its open seams — and here it
     * buys nothing at all, because the fitted plane IS the triangle. So let it
     * be the triangle. */
    {
        double totalArea = 0;
        for (int t = 0; t < m.triCount(); ++t)
            totalArea += m.tarea[t];
        std::vector<int> owner(m.triCount(), -1);
        for (size_t i = 0; i < patches.size(); ++i)
            for (int t : patches[i].tris)
                owner[t] = static_cast<int>(i);
        for (int pass = 0; pass < 3; ++pass) {
            bool again = false;
            for (size_t i = 0; i < patches.size(); ++i) {
                Patch &pa = patches[i];
                if (pa.fit.kind == kNone ||
                    static_cast<int>(pa.tris.size()) >= kFreeformPieceTriangles)
                    continue;
                /* Small in AREA, not merely in triangles.
                 *
                 * Triangle count says a six-facet strip is as slight as a
                 * single facet, and it is not: on the user's part that strip
                 * is a flat wall forty millimetres long, four percent of the
                 * model's surface, and demoting it started an avalanche —
                 * every fitted neighbour then had a faceted neighbour of its
                 * own. What this rule is for is the offcut a lumpy surface
                 * throws off, which is a thousandth of the part. */
                double area = 0;
                for (int t : pa.tris)
                    area += m.tarea[t];
                if (area > totalArea * kScrapAreaFraction)
                    continue;
                /* How much of its BOUNDARY faces triangles.
                 *
                 * "Has a fitted neighbour" is not enough: two one-triangle
                 * runs side by side are each other's fitted neighbour and both
                 * survive on that alone, which is how a lumpy blob kept
                 * twenty-six "faces" that are its own facets. Nor is "has a
                 * big fitted neighbour" — a box is six faces of two triangles
                 * and every neighbour of every one of them is just as small.
                 * What separates them is what lies along the edges: a box face
                 * meets faces on all four sides, a facet adrift in an organic
                 * shell meets triangles on most of its own. */
                int outward = 0, toTriangles = 0;
                for (int t : pa.tris) {
                    for (int k = 0; k < 3; ++k) {
                        const int o = m.adj[t * 3 + k];
                        if (o < 0)
                            continue;
                        const int j = owner[o];
                        if (j < 0 || j == static_cast<int>(i))
                            continue;
                        outward++;
                        if (patches[j].fit.kind == kNone)
                            toTriangles++;
                    }
                }
                if (outward > 0 && toTriangles * 2 > outward) {
                    pa.fit = Fit();
                    again = true;
                }
            }
            if (!again)
                break;
        }
    }

    /* A patch with no surface among patches that have one usually belongs to
     * them; see DissolveUnexplained. */
    {
        DissolveUnexplained(m, patches, tol, scale);
        patchOf.assign(m.triCount(), -1);
        for (size_t i = 0; i < patches.size(); ++i)
            for (int t : patches[i].tris)
                patchOf[t] = static_cast<int>(i);
        rep.patches = static_cast<int>(patches.size());
    }
    MR_STAGE("patch verdicts");

    /* Cover what fitted nothing in a few B-splines rather than in triangles. */
    {
        int madeFree = 0;
        try {
            SetStage(kStageFreeform, 0);
            FreeformSurfaces(m, patches, tol, madeFree);
        } catch (const Standard_Failure &) {
        } catch (const std::exception &) {
        } catch (...) {
        }
        if (madeFree > 0) {
            rep.patches = static_cast<int>(patches.size());
            patchOf.assign(m.triCount(), -1);
            for (size_t i = 0; i < patches.size(); ++i)
                for (int t : patches[i].tris)
                    patchOf[t] = static_cast<int>(i);
        }
        MR_STAGE("freeform surfaces");
    }
    if (Cancelled()) {
        err = kCancelledMessage;
        return TopoDS_Shape();
    }

    /* Nothing at all was recognised, AND nothing could be covered by a fitted
     * surface either: then this really is a mesh, and it should be built as
     * one piece rather than as a mosaic of faceted patches. The difference is
     * not cosmetic — each faceted patch is emitted with its own vertices, so
     * 183 of them meet along seams that sewing has to rediscover, and a
     * squashed ellipsoid came back 0.02% light where one faceted shell
     * reproduces the mesh's volume exactly.
     *
     * M333 — the test used to be "no patch fitted a PRIMITIVE", and it used to
     * be made here, before the freeform fit ran. That was right when it was
     * written and became wrong the moment there were freeform surfaces: a
     * smooth organic model has no plane, cylinder, cone, sphere or torus
     * anywhere in it, so the test passed on every one of them and the
     * conversion returned one B-Rep face per triangle without ever trying to
     * fit a surface. Measured: a tessellated ellipsoid 100x55x190 came back as
     * 12,420 faces from 12,430 triangles, and six other smooth fixtures the
     * same. The whale escaped only because the flat plate it is mounted on
     * gave it six planes and a cylinder.
     *
     * So the question is asked AFTER the freeform pass, and it asks what it
     * always meant: is there a surface reconstruction here worth having?
     *
     * The old test — is there any ANALYTIC surface? — is kept exactly as it
     * was, because it is still the right question about a part: one recognised
     * hole is a feature the faceted build would lose, whatever else happened.
     * What is added is the second way to answer yes, for the shapes that have
     * no such feature and never will: did the freeform fit carry the mesh?
     * That is measured in the one unit that matters — how much of it a fitted
     * surface holds — with the SAME number the fallback at the end uses, so
     * the two cannot disagree about what a reading is.
     *
     * Measured on the fixtures either side of the line: a coarse ellipsoid of
     * 594 triangles fits only 34.8% of itself and is better off as one faceted
     * shell, which is what it got before and still gets; a finely tessellated
     * one fits 99.8% and is not. */
    {
        bool anyAnalytic = false;
        int fittedTris = 0;
        for (const Patch &pa : patches) {
            if (pa.fit.kind == kNone)
                continue;
            fittedTris += static_cast<int>(pa.tris.size());
            if (pa.fit.kind != kFreeform)
                anyAnalytic = true;
        }
        const bool reading =
            m.triCount() > 0 &&
            fittedTris * 100 >= m.triCount() * kFittedIsReadingPercent;
        const bool anyFit = anyAnalytic || reading;
        if (!anyFit && m.triCount() <= prm.max_faceted_triangles) {
            Report fr;
            ClearReport(fr);
            fr.triangles_in = rep.triangles_in;
            fr.vertices_in = rep.vertices_in;
            fr.triangles_used = rep.triangles_used;
            fr.vertices_welded = rep.vertices_welded;
            fr.non_manifold_edges = rep.non_manifold_edges;
            fr.boundary_edges = rep.boundary_edges;
            fr.flipped_triangles = rep.flipped_triangles;
            fr.diagonal = rep.diagonal;
            fr.patches = rep.patches;
            TopoDS_Shape alt;
            try {
                alt = BuildFaceted(m, tol, fr);
            } catch (const Standard_Failure &) {
            } catch (const std::exception &) {
            } catch (...) {
            }
            if (!alt.IsNull()) {
                rep = fr;
                MR_STAGE("faceted (nothing recognised)");
                return alt;
            }
        }
    }

    /* The count of RECOGNISED surfaces, taken before anything is cut: two
     * halves of a barrel are one surface however many faces carry them. */
    const size_t recognisedPatches = patches.size();

#ifdef MESHRECON_TRACE
    /* One line per triangle: which patch, which smooth run, what kind was
     * kept. The development harness renders the mesh from this, which is the
     * only way to see WHAT a run that fitted nothing actually is. */
    {
        std::vector<int> ownerOf(m.triCount(), -1);
        for (size_t i = 0; i < patches.size(); ++i)
            for (int t : patches[i].tris)
                ownerOf[t] = static_cast<int>(i);
        FILE *sf = std::fopen("segments.txt", "w");
        if (sf) {
            for (int t = 0; t < m.triCount(); ++t) {
                const int i = ownerOf[t];
                std::fprintf(sf, "%d %d %d %d\n", t, i,
                             i >= 0 ? patches[i].origin : -1,
                             i >= 0 ? (int)patches[i].fit.kind : 0);
            }
            std::fclose(sf);
        }
    }
#endif

    /* Everything from surfaces to a sewn solid, so that it can be run twice.
     *
     * The first attempt keeps every recognised surface as ONE face, which is
     * what the part was drawn as and what a user wants to select and edit. A
     * patch that closes on itself is then trimmed from its own parameters and
     * its rim has to be sewn to its neighbour's by distance rather than by
     * identity — which the exact conics make good enough almost always, and
     * not always: where a rim is divided among several neighbours there is
     * nothing for the whole circle to be identified with, and the shell comes
     * out open.
     *
     * So try it whole; and only if that does not close, cut those patches in
     * half and try again, where every edge is shared by construction. The
     * model pays the extra face only where it must. */
    auto assemble = [&](const std::vector<Patch> &patches,
                        const std::vector<int> &patchOf, Report &rep,
                        std::string &err) -> TopoDS_Shape {
        std::vector<TopoDS_Face> faces;
        std::vector<Handle(Geom_Surface)> surfs(patches.size());
        double rmsNum = 0, rmsDen = 0;
        for (size_t i = 0; i < patches.size(); ++i) {
            surfs[i] = patches[i].fit.kind == kFreeform
                           ? patches[i].freeSurf
                           : MakeSurface(patches[i].fit);
            if (surfs[i].IsNull())
                continue;
            AlignSurfaceSeam(surfs[i], m, patches[i].tris);
            double area = 0;
            for (int t : patches[i].tris)
                area += m.tarea[t];
            rmsNum += patches[i].fit.rms * area;
            rmsDen += area;
            if (i >= recognisedPatches)
                continue; /* the far half of a cut barrel is the same surface */
            switch (patches[i].fit.kind) {
            case kPlane:
                rep.planes++;
                break;
            case kCylinder:
                rep.cylinders++;
                break;
            case kCone:
                rep.cones++;
                break;
            case kSphere:
                rep.spheres++;
                break;
            case kTorus:
                rep.tori++;
                break;
            case kFreeform:
                rep.freeform++;
                break;
            default:
                break;
            }
        }
        rep.fit_rms = rmsDen > 0 ? rmsNum / rmsDen : 0;

        BuildCtx ctx;
        ctx.m = &m;
        ctx.tol = tol;
        ctx.scale = scale;

        int facetedTriangles = 0;
        std::vector<std::vector<int>> deferred;
        SetStage(kStageBuilding, static_cast<int>(patches.size()));
        for (size_t i = 0; i < patches.size(); ++i) {
            if (Cancelled())
                break;
            SetDone(static_cast<int>(i));
            bool built = false;
            const size_t before = faces.size();
            if (!surfs[i].IsNull()) {
                try {
                    built =
                        BuildAnalyticFace(ctx, m, patches[i], static_cast<int>(i),
                                          patchOf, surfs, faces);
                } catch (const Standard_Failure &) {
                    built = false;
                } catch (const std::exception &) {
                    built = false;
                } catch (...) {
                    /* One patch that will not build goes faceted. It never stops
                     * the conversion, and it must never leave this loop. */
                    built = false;
                }
            }
            /* Read only by the trace below. */
            [[maybe_unused]] const char *why = "builder failed";
            if (built) {
                /* Checked HERE rather than inside the builder because the analytic
                 * path can also hand off to the parametric one, and a face that
                 * escaped its patch is worthless whichever built it. */
                /* A freeform face is not asked whether it escaped.
                 *
                 * FaceWithinPatch guards against a surface with more freedom
                 * than its patch — a torus threaded through a fillet, a sphere
                 * fitted to a corner — reaching somewhere the mesh never went.
                 * A freeform surface has no such freedom: it is a graph over
                 * the patch's own (u, v) box, fitted to the patch's own
                 * vertices and reaching a few per cent past them so that the
                 * boundary has somewhere to project. What the test
                 * actually measures on one is its POLES, and a B-spline's
                 * control net stands outside the surface it describes — the
                 * same overstatement the comment inside that function
                 * describes. On the whale it refused a face carrying 1,650
                 * triangles that was exactly right, and sent them back to
                 * being 1,650 triangles. FaceIsSound still applies. */
                const bool freeform = patches[i].fit.kind == kFreeform;
                for (size_t k = before; k < faces.size(); ++k) {
                    if (!freeform &&
                        !FaceWithinPatch(faces[k], m, patches[i].tris, tol)) {
                        built = false;
                        why = "face escaped its patch";
                        break;
                    }
                    if (!FaceIsSound(faces[k], m, patches[i].tris)) {
                        built = false;
                        why = "face folds through itself";
                        break;
                    }
                }
                if (!built)
                    faces.resize(before);
            }
            if (!built && !surfs[i].IsNull())
                MR_TRACE("      patch %3d NOT BUILT (%s, %d tri): %s\n", (int)i,
                         KindName(patches[i].fit.kind),
                         (int)patches[i].tris.size(), why);
            if (built) {
                rep.faces_built++;
            } else {
                faces.resize(before);
                if (!surfs[i].IsNull())
                    rep.faces_failed++;
                rep.faceted_patches++;
                facetedTriangles += static_cast<int>(patches[i].tris.size());
                deferred.push_back(patches[i].tris);
            }
        }

        if (facetedTriangles > prm.max_faceted_triangles) {
            char buf[224];
            std::snprintf(buf, sizeof(buf),
                          "only %d of %d patches became surfaces; the remaining "
                          "%d triangles are too many to keep face-by-face",
                          rep.faces_built, rep.patches, facetedTriangles);
            err = buf;
            return TopoDS_Shape();
        }
        MR_STAGE("build faces");
        for (const std::vector<int> &tris : deferred)
            EmitFacetedShared(ctx, m, tris, faces);
        MR_STAGE("emit faceted");

        rep.analytic_edges = ctx.analytic;
        rep.approximated_edges = ctx.approximated;

        if (faces.empty()) {
            err = "no faces could be built from that mesh";
            return TopoDS_Shape();
        }
        /* These faces were built sharing their edges, so try assembling them
         * as they are before handing them to a tool that would rebuild them. */
        TopoDS_Shape out;
        {
            const TopoDS_Shape direct = AssembleShell(faces);
            if (!direct.IsNull())
                out = Solidify(direct, rep);
        }
        if (out.IsNull()) {
            if (faces.size() <= static_cast<size_t>(kMaxSewFaces)) {
                out = SewAndSolidify(faces, tol, rep);
            } else {
                /* Too many to sew — see kMaxSewFaces. Hand back what was
                 * built, open, so the faceted build below can replace it. */
                MR_TRACE("  sewing skipped: %d faces\n", (int)faces.size());
                BRep_Builder cb;
                TopoDS_Compound c;
                cb.MakeCompound(c);
                for (const TopoDS_Face &f : faces)
                    cb.Add(c, f);
                rep.shells = rep.solids = rep.closed = 0;
                out = c;
            }
        }
        /* A hybrid shell — fitted faces beside triangles — can come out of sewing
         * with a handful of edges still open where the two kinds meet: 26 of 3032
         * on the model this was measured on, the seams round its four holes. They
         * are not gaps in the model, they are two descriptions of the same seam
         * that sewing declined to identify at the tolerance it was given. Ask
         * again, once, with room. */
        if (rep.closed != 1 && !faces.empty() &&
            faces.size() <= static_cast<size_t>(kMaxSewFaces)) {
            Report r2 = rep;
            r2.shells = r2.solids = r2.closed = 0;
            TopoDS_Shape again;
            try {
                again = SewAndSolidify(faces, tol * kSewRetryFactor, r2);
            } catch (const Standard_Failure &) {
            }
            if (!again.IsNull() && r2.closed == 1) {
                rep = r2;
                out = again;
            }
        }
        return out;
    };

    std::string err1 = err;
    Report rep1 = rep;
    TopoDS_Shape out = assemble(patches, patchOf, rep1, err1);
    /* Before the "did it close?" reasoning below, which would otherwise blame
     * an interrupted build for not closing and try the whole thing again. */
    if (Cancelled()) {
        err = kCancelledMessage;
        return TopoDS_Shape();
    }
    MR_TRACE("  whole: null=%d closed=%d shells=%d built=%d failed=%d "
             "faceted=%d\n",
             (int)out.IsNull(), rep1.closed, rep1.shells, rep1.faces_built,
             rep1.faces_failed, rep1.faceted_patches);
    if (!out.IsNull() && rep1.closed == 1) {
        rep = rep1;
    } else {
        /* Did not close whole: cut the wrapping patches and try once more. */
        std::vector<Patch> cut = patches;
        std::vector<int> cutOf = patchOf;
        int nsplit = 0;
        try {
            SplitFullWraps(m, cut, cutOf, nsplit);
        } catch (const Standard_Failure &) {
        }
        MR_STAGE("split full wraps");
        bool tookSecond = false;
        if (nsplit > 0) {
            Report rep2 = rep;
            std::string err2 = err;
            TopoDS_Shape alt = assemble(cut, cutOf, rep2, err2);
            MR_TRACE("  split: null=%d closed=%d shells=%d built=%d failed=%d "
                     "faceted=%d\n",
                     (int)alt.IsNull(), rep2.closed, rep2.shells,
                     rep2.faces_built, rep2.faces_failed,
                     rep2.faceted_patches);
            if (!alt.IsNull() && (rep2.closed == 1 || out.IsNull())) {
                out = alt;
                rep = rep2;
                err = err2;
                tookSecond = true;
            }
        }
        if (!tookSecond) {
            rep = rep1;
            err = err1;
        }
    }
    if (out.IsNull()) {
        if (err.empty())
            err = "the faces would not sew into a shell";
        return TopoDS_Shape();
    }
    /* A hole comes out as two half-barrels, and stays that way.
     *
     * SplitFullWraps cuts a patch that closes on itself in half so that every
     * edge of it can be shared with the faces around it, and a B-Rep of two
     * half-barrels is a perfectly good body — most kernels write a drilled
     * hole exactly that way. Rejoining them into one seamed face is a nicety,
     * ShapeUpgrade_UnifySameDomain is the tool for it, and it cannot be
     * trusted with the job: asked to merge the two halves of the user's 5 mm
     * hole it returned a face BRepCheck rejects, and on the same part one
     * revision later it ran for ten minutes on eighty faces without
     * finishing. A body that is right and arrives is worth more than one that
     * is tidier and may not. */

    /* A shell that will not close is not a body, and an ORGANIC model produces
     * exactly that.
     *
     * Surface fitting has nothing to recognise on a shape that is curved
     * everywhere and analytic nowhere: it shatters into one small patch per
     * handful of triangles, none of them meeting cleanly, and the result is an
     * open shell that cannot be filleted, cut or booleaned — the whole reason
     * for converting at all. One face per triangle recognises nothing either,
     * but on a watertight mesh it CANNOT fail, and a heavy solid the user can
     * actually work on beats a light shell they cannot.
     *
     * Decided by trying it rather than by predicting it: if the faceted build
     * closes where the fitted one did not, it wins; otherwise nothing is lost
     * but the attempt.
     *
     * Closing is not the only reason to prefer it. A mesh that is not
     * watertight — and downloaded ones often are not — closes under neither,
     * and then the question is which OPEN shell is worth having. A fitted one
     * that recognised the model is: it is lighter and its faces are real
     * surfaces. One that SHATTERED is not, and shattering is plain in the
     * numbers — the file this was found on came back as 179 patches for 1138
     * triangles, one face per six, which is not a reading of the shape but a
     * failure to read it. Below a floor the ratio means nothing (a cube with a
     * face missing is 5 patches for 10 triangles and perfectly recognised), so
     * it only applies to meshes big enough for it to say something. */
    const bool shattered =
        m.triCount() >= kShatterFloorTriangles &&
        rep.patches * kShatterTrianglesPerPatch > m.triCount();

    /* Whether anything CURVED was recognised, and survived the identifiability
     * test — a cylinder, cone, sphere or torus, not merely a plane.
     *
     * This is what decides whether the faceted build is allowed to replace the
     * fitted one, and it is the difference between a model whose holes are
     * holes and a bag of triangles. On a curved shell with four drilled holes
     * the fitted pass finds the four cylinders at radius exactly 2, 3, 4 and 5
     * and turns the shell itself into triangles, which is the right answer and
     * the one that was asked for; replacing all of it because the hybrid shell
     * did not close would throw the four holes away to gain a solid. A model
     * that recognised nothing has nothing to lose and takes the solid. */
    /* How many pieces each smooth patch was cut into. A feature of the DESIGN
     * — a hole, a boss, a fillet — arrives as a whole smooth patch, bounded by
     * its own sharp rim; SplitByFit never had to touch it. A cylinder that is
     * really a strip of a smooth shell is one of many pieces that patch was
     * broken into, and on a squashed sphere such a strip fits a cylinder to
     * better than a fiftieth of tolerance. The residual cannot separate those
     * two; where the patch CAME FROM can. */
    std::unordered_map<int, int> piecesOfOrigin;
    for (const Patch &pa : patches)
        piecesOfOrigin[pa.origin]++;

    bool recognisedFeatures = false;
    for (const Patch &pa : patches) {
        if (pa.fit.kind == kNone || pa.fit.kind == kPlane)
            continue;
        if (pa.origin >= 0 && piecesOfOrigin[pa.origin] != 1)
            continue; /* a shard of a smooth region, not a feature of the part */
        /* "Recognised" means EXACT, not merely allowed. A tessellation puts
         * its vertices on the surface they came from, so a real hole fits its
         * cylinder with a residual of nothing; the identifiability test
         * already refuses anything above a sixth of tolerance, but a coarse
         * organic shell can still throw up a sphere at a twentieth of it, and
         * three of those were enough to stop an ellipsoid taking the solid it
         * should have had. Only a feature that fits to the mesh's own
         * precision is worth keeping an open shell for. */
        if (pa.fit.rms <= tol * kExactFitFraction) {
            recognisedFeatures = true;
            break;
        }
    }
#ifdef MESHRECON_TRACE
    const bool noFallback = std::getenv("MR_NOFALLBACK") != nullptr;
#else
    const bool noFallback = false;
#endif
    /* Is the fitted result a reading of the shape, or the faceted one with
     * seams in it? See kFittedIsFacetedPercent. */
    int facetedTris = 0;
    for (const Patch &pa : patches)
        if (pa.fit.kind == kNone)
            facetedTris += static_cast<int>(pa.tris.size());
    const bool fittedIsFaceted =
        m.triCount() > 0 &&
        facetedTris * 100 >= m.triCount() * kFittedIsFacetedPercent;

    /* M333 — a freeform reconstruction is a feature of the part too.
     *
     * recognisedFeatures asks for an EXACT analytic fit. That is the right
     * question about a hole or a fillet and the wrong one about a smooth body:
     * a B-spline fitted to a flank has a residual near tolerance by
     * construction and never near zero, so a model with no plane, cylinder,
     * cone, sphere or torus anywhere in it — which is every organic model
     * there is — could not answer yes however well it had been reconstructed.
     *
     * Measured, before this: a tessellated ellipsoid 100x55x190 fitted 59
     * freeform surfaces covering all but 22 of its 12,428 triangles, missed
     * closing by 8 edges out of thousands, and was thrown away for 12,420
     * faceted faces. Six other smooth fixtures the same. The whale escaped
     * only because the flat plate it is mounted on gave it an exact plane.
     *
     * What the fallback protects against is a result that is the faceted build
     * wearing a fitted one's clothes, and fittedIsFaceted measures exactly
     * that, from the other side. So a reconstruction that covered the shape in
     * fitted surfaces is worth keeping even when it does not close, whether
     * those surfaces are analytic or not.
     *
     * The volume check is untouched and is what still catches a result that is
     * the wrong part: it fires on its own, whatever this says. */
    int freeformTris = 0;
    for (const Patch &pa : patches)
        if (pa.fit.kind == kFreeform)
            freeformTris += static_cast<int>(pa.tris.size());
    const bool fittedIsReading =
        m.triCount() > 0 &&
        (m.triCount() - facetedTris) * 100 >=
            m.triCount() * kFittedIsReadingPercent &&
        freeformTris > 0;

    /* What the open fitted shell is worth keeping FOR: a feature of the part
     * that the faceted build would lose. When the fitted result is itself one
     * face per triangle there is no such thing — the whale's lone eleven-facet
     * cylinder is 0.013% of it — and nothing is being protected. */
    const bool worthKeeping =
        (recognisedFeatures || fittedIsReading) && !fittedIsFaceted;

    /* And the ceiling exists so the faceted build cannot be an ESCALATION over
     * a light fitted result. Where the fitted result is already one face per
     * triangle it cannot be: the same faces have been built once already. */
    const bool affordable =
        m.triCount() <= prm.max_faceted_triangles &&
        (fittedIsFaceted || m.triCount() <= kMaxAutoFacetedTriangles);

    MR_TRACE("  fallback: closed=%d faceted %d of %d tri (%d%% bar) "
             "features=%d reading=%d worthKeeping=%d affordable=%d\n",
             rep.closed, facetedTris, m.triCount(), kFittedIsFacetedPercent,
             (int)recognisedFeatures, (int)fittedIsReading, (int)worthKeeping,
             (int)affordable);

    /* Is the answer still the part we were given?
     *
     * A 2 mm bookmark with 37 cut-outs, converted at the tolerance its 166 mm
     * diagonal implied, came back closed=1, thirty-nine solids, and 171% more
     * material than the mesh it was handed: every opening grown shut, and
     * nothing downstream with any reason to doubt it. A part that has
     * silently gained two thirds of its volume is the worst thing this
     * converter can do — worse than failing, because the user keeps it and
     * prints it.
     *
     * WHY that tolerance does it is not known, and three explanations have
     * been measured and ruled out, so do not assume one here:
     *   - not "wider than the gap between two walls": a synthetic plate with
     *     round openings 0.25 mm apart converts at 0.267 mm and comes back
     *     -0.93%;
     *   - not a gap that could be measured and bounded instead: every fixture
     *     here has two unconnected vertices within 0.03 mm, so any such
     *     anchor collapses to 0.0006 mm and nothing converts at all;
     *   - not the model's short edges: the bookmark fails with 6.9% of its
     *     edges under the tolerance, the broomholder converts with 33.2%.
     *
     * Which is the point of doing it this way. The cause does not have to be
     * understood for the result to be checked: build the solid, measure it
     * against the volume of the mesh that came in, and when they are not the
     * same object take the faceted build, which reproduces the mesh exactly.
     * That holds whatever the mechanism turns out to be. */
    bool volumeWrong = false;
    if (rep.closed == 1 && meshVolume > 0 && !out.IsNull()) {
        try {
            GProp_GProps vg;
            BRepGProp::VolumeProperties(out, vg);
            const double got = std::fabs(vg.Mass());
            const double off = std::fabs(got - meshVolume) / meshVolume;
            if (off > kVolumeDivergenceBar) {
                volumeWrong = true;
                MR_TRACE("  volume check: %.3f vs mesh %.3f (%+.2f%%) — "
                         "not the same part\n", got, meshVolume,
                         100.0 * (got - meshVolume) / meshVolume);
            }
        } catch (const Standard_Failure &) {
        } catch (...) {
        }
    }

    if ((rep.closed != 1 || volumeWrong) &&
        (volumeWrong || !worthKeeping) && !noFallback && affordable) {
        Report fr;
        ClearReport(fr);
        fr.triangles_in = rep.triangles_in;
        fr.vertices_in = rep.vertices_in;
        fr.triangles_used = rep.triangles_used;
        fr.vertices_welded = rep.vertices_welded;
        fr.non_manifold_edges = rep.non_manifold_edges;
        fr.boundary_edges = rep.boundary_edges;
        fr.flipped_triangles = rep.flipped_triangles;
        fr.diagonal = rep.diagonal;
        TopoDS_Shape alt;
        try {
            alt = BuildFaceted(m, tol, fr);
        } catch (const Standard_Failure &) {
        } catch (const std::exception &) {
        } catch (...) {
        }
        if (!alt.IsNull() && (fr.closed == 1 || shattered || volumeWrong)) {
            rep = fr;
            return alt;
        }
        if (volumeWrong) {
            /* Nothing sound to hand back. Say so with the numbers rather than
             * return a part that is not the one that was asked for. */
            char buf[224];
            std::snprintf(buf, sizeof(buf),
                          "the converted solid encloses a volume %.0f%% away "
                          "from the mesh's own — its tolerance (%.4f mm) is "
                          "wider than the gaps in the model, and its openings "
                          "have closed",
                          100.0 * kVolumeDivergenceBar, tol);
            err = buf;
            return TopoDS_Shape();
        }
    }
    if (volumeWrong) {
        char buf[224];
        std::snprintf(buf, sizeof(buf),
                      "the converted solid encloses a volume more than %.0f%% "
                      "away from the mesh's own — its tolerance (%.4f mm) is "
                      "wider than the gaps in the model, and its openings have "
                      "closed",
                      100.0 * kVolumeDivergenceBar, tol);
        err = buf;
        return TopoDS_Shape();
    }
    /* A run that was cancelled hands back nothing, however far it had got.
     * Checked last and in one place: every loop above breaks out on the flag,
     * so what is in `out` at this point is a body built from part of the mesh,
     * and a part of the model is the one answer worse than no answer — the
     * user would keep it. */
    if (Cancelled()) {
        err = kCancelledMessage;
        return TopoDS_Shape();
    }
    return out;
}


/* Shading across a seam.
 *
 * Vertices are emitted PER FACE so a B-Rep edge stays crisp, and that is right
 * for a box. It is wrong for a converted mesh: a whale comes back as 305
 * trimmed patches of one smooth animal, and the two patches along a seam get
 * one normal each, so every one of the 5,323 mm of seam is a hard shading break
 * however slightly the surfaces actually disagree. Measured on the whale at the
 * deflection the app draws with, over 5,964 shared nodes, the real kink between
 * the two faces is 6.3 degrees at the median. A six-degree kink is not an edge;
 * it is the same surface, cut up. Drawn as an edge it reads as a panel line,
 * and the model looks assembled out of scraps.
 *
 * So a node that two faces share gets ONE normal when they agree to within the
 * crease angle, and keeps two when they do not. This is what every CAD renderer
 * does, and it changes no geometry at all: same vertices, same triangles, same
 * B-Rep. Only the normals handed to the shader.
 *
 * Nothing is smoothed across a real edge: TOKA's box corners measure 90 degrees
 * at the median and stay exactly as crisp as they were, and the outline pass
 * regardless: the outline pass draws every B-Rep edge either way. */
const double kCreaseAngleDeg = 30.0;
const double kTangentAngleDeg = 8.0;

void ShareNormalsAcrossSeams(const std::vector<double> &verts,
                             const std::vector<unsigned char> &freeform,
                             std::vector<double> &norms)
{
    const size_t n = verts.size() / 3;
    if (n < 2 || norms.size() != verts.size())
        return;
    const bool haveKinds = (freeform.size() == n);
    /* A tolerance for "the same point". Nodes on a shared edge come from one
     * discretisation of that edge and are identical, so this only has to be
     * small enough not to merge neighbours. */
    double lo[3] = {1e300, 1e300, 1e300}, hi[3] = {-1e300, -1e300, -1e300};
    for (size_t v = 0; v < n; ++v)
        for (int k = 0; k < 3; ++k) {
            lo[k] = std::min(lo[k], verts[v * 3 + k]);
            hi[k] = std::max(hi[k], verts[v * 3 + k]);
        }
    double diag = 0;
    for (int k = 0; k < 3; ++k)
        diag += (hi[k] - lo[k]) * (hi[k] - lo[k]);
    diag = std::sqrt(diag);
    const double tol = std::min(1e-3, std::max(1e-7, diag * 1e-7));

    /* One bucket lookup per vertex, not twenty-seven: identical points quantise
     * identically. Two points a whisker apart can still land either side of a
     * boundary, and then they simply keep their own normals — which is what
     * they had before this existed, so the worst case is no change. */
    std::unordered_map<long long, std::vector<int>> at;
    at.reserve(n * 2);
    auto cell = [&](size_t v) {
        const long long i = (long long)std::llround(verts[v * 3] / tol);
        const long long j = (long long)std::llround(verts[v * 3 + 1] / tol);
        const long long k = (long long)std::llround(verts[v * 3 + 2] / tol);
        return (i * 73856093LL) ^ (j * 19349663LL) ^ (k * 83492791LL);
    };
    for (size_t v = 0; v < n; ++v)
        at[cell(v)].push_back((int)v);

    /* How much disagreement is "the same surface, cut up" depends on what the
     * two faces ARE.
     *
     * Between two freeform patches it is a lot: a converted whale is one
     * animal sliced into 305 of them, and they meet at 6.3 degrees at the
     * median with a long tail — nothing there is a designed edge, and drawing
     * any of it as one is what made the model look like scraps.
     *
     * Between anything else it is only tangency. A 25 degree chamfer between
     * two planes IS an edge and has to stay crisp, and so does a 20 degree
     * cone-to-plane. Those never had this problem to begin with — a modelled
     * solid's faces are few and its edges are meant — so they get the narrow
     * rule, which still gains them the one thing they were missing: a fillet
     * runs tangentially into its neighbour and stops being a shading break. */
    const double creaseFree = std::cos(kCreaseAngleDeg * M_PI / 180.0);
    const double creaseElse = std::cos(kTangentAngleDeg * M_PI / 180.0);
    std::vector<double> out(norms);
    std::vector<char> done;
    /* Grouping inside a bucket is quadratic in its size, which is fine for the
     * handful of faces that really do meet at a node and is not fine for a
     * bucket a hash collision has filled up. No vertex on a real body is shared
     * by anything like this many faces, so a bucket past it is a collision and
     * is left alone — those vertices simply keep the normals they arrived with. */
    const size_t kMaxAtOneNode = 96;
    for (auto &kv : at) {
        std::vector<int> &g = kv.second;
        if (g.size() < 2 || g.size() > kMaxAtOneNode)
            continue;
        done.assign(g.size(), 0);
        for (size_t a = 0; a < g.size(); ++a) {
            if (done[a])
                continue;
            double sum[3] = {norms[g[a] * 3], norms[g[a] * 3 + 1],
                             norms[g[a] * 3 + 2]};
            std::vector<int> grp(1, g[a]);
            done[a] = 1;
            for (size_t b = a + 1; b < g.size(); ++b) {
                if (done[b])
                    continue;
                /* The hash can collide; the position decides. */
                double d = 0;
                for (int k = 0; k < 3; ++k) {
                    const double t = verts[g[a] * 3 + k] - verts[g[b] * 3 + k];
                    d += t * t;
                }
                if (d > tol * tol)
                    continue;
                double dot = 0;
                for (int k = 0; k < 3; ++k)
                    dot += norms[g[a] * 3 + k] * norms[g[b] * 3 + k];
                const bool bothFree = haveKinds && freeform[g[a]] &&
                                      freeform[g[b]];
                if (dot < (bothFree ? creaseFree : creaseElse))
                    continue; /* a real edge: leave both alone */
                for (int k = 0; k < 3; ++k)
                    sum[k] += norms[g[b] * 3 + k];
                grp.push_back(g[b]);
                done[b] = 1;
            }
            if (grp.size() < 2)
                continue;
            const double len =
                std::sqrt(sum[0] * sum[0] + sum[1] * sum[1] + sum[2] * sum[2]);
            if (!(len > 1e-12))
                continue;
            for (const int v : grp)
                for (int k = 0; k < 3; ++k)
                    out[v * 3 + k] = sum[k] / len;
        }
    }
    norms.swap(out);
}

} // namespace meshrecon
