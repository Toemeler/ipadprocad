/*
 * Lane C — a headless kernel benchmark for the OCCT C-ABI shim.
 *
 * PERFORMANCE_PROFILE.md §15.5 specified this instrument and it was never
 * built; OPTIMIZATION_PLAN.md §5 Session 1 is the order to build it. It exists
 * because of the constraint in that plan's §2: the device suite runs on one
 * physical iPad, driven by a human, and nobody optimising the kernel can
 * measure their own work between one capture and the next. The C++ under
 * backend/ needs no iOS, no Flutter and no device — so this loop runs in
 * minutes and the kernel work stops flying blind.
 *
 * ------------------------------------------------------------------------
 * WHAT THESE NUMBERS MAY AND MAY NOT BE USED FOR  (§13.3, and it is binding)
 * ------------------------------------------------------------------------
 *   May be read : RELATIVE cost between operations; EXPONENTS and their
 *                 confidence intervals; allocation and RSS behaviour;
 *                 structural change ("does it still call this per edge?").
 *   May NOT     : any absolute millisecond as an iPad millisecond. A desktop
 *                 runs at a higher clock with no thermal ceiling, and quoting
 *                 its milliseconds as device milliseconds is the M75 error in
 *                 new clothing. The report repeats this on every output.
 *
 * ------------------------------------------------------------------------
 * WHAT MAKES IT TRUSTWORTHY
 * ------------------------------------------------------------------------
 * A benchmark nobody has checked is an opinion. This one is calibrated: §6.5
 * of the profile establishes two exponents on the device, over four lines of
 * evidence, reproduced across two clock arms —
 *
 *     one occt_shape_edge_info against a GROWING shape   k = 0.985  [0.97, 1.01]
 *     the full per-edge enumeration                      k = 2.012  [1.910, 2.113]
 *
 * — and the harness must reproduce BOTH before anything it says about an
 * optimisation may be believed. If it does not, the harness is wrong, not the
 * device (OPTIMIZATION_PLAN.md §5, Session 1). --validate turns that check
 * into the exit code.
 *
 * THE FIXTURE IS THE DEVICE FIXTURE. `stress.kernel.allEdges` builds
 * extrudeProfileArcs(ringProfile(n, 40), 10.0) at n = 120/240/480 profile
 * points; ringProfile is a regular n-gon of radius 40 with every bulge zero
 * (frontend/lib/perf_scenarios.dart:151), so the solid is an n-gon prism with
 * 3n edges and n+2 faces. This file rebuilds exactly that, in C, and sweeps
 * the same rungs. Comparability to §6.5 rests on it, so do not "improve" the
 * fixture without re-deriving the calibration.
 */

#include <algorithm>
#include <cmath>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <functional>
#include <string>
#include <vector>

#include <sys/resource.h>

#include "bench_alloc.h"
#include "bench_stats.h"

extern "C" {
#include "occt_capi.h"
}

using bench::AllocSnapshot;
using bench::Fit;
using bench::Stats;

/* ------------------------------------------------------------------------ */
/* Calibration constants — the device values this harness is checked against */
/* ------------------------------------------------------------------------ */

namespace ref {
/* PERFORMANCE_PROFILE.md §6.5 evidence 2 (kernel.query.edgeInfoScale, N = 4).
 * The compositional-closure paragraph of the same section quotes 0.985 for the
 * same fit; 0.99 is what the evidence table prints, and refitting its four
 * published points reproduces 0.9887 exactly. Any of the three is the same
 * number to the precision that matters here. */
constexpr double kEdgeInfoK = 0.99;
constexpr double kEdgeInfoLo = 0.97;
constexpr double kEdgeInfoHi = 1.01;
constexpr const char *kEdgeInfoWhere =
    "PERFORMANCE_PROFILE.md §6.5 evidence 2 (kernel.query.edgeInfoScale)";

/* PERFORMANCE_PROFILE.md §6.5 evidence 4, reference (uncapped) arm, N = 3. */
constexpr double kAllEdgesK = 2.012;
constexpr double kAllEdgesLo = 1.910;
constexpr double kAllEdgesHi = 2.113;
/*
 * The SECOND interval, and why it is here.
 *
 * Refitting evidence 4's three published rungs (360/720/1440 edges against
 * 616/2508/10017 ms) reproduces k = 2.0117 and se = 0.00799 exactly — but the
 * printed interval [1.910, 2.113] is k +/- 12.706 * se, the Student-t interval
 * at one degree of freedom. Evidence 1 (N = 7) and evidence 2 (N = 4) in the
 * same section both print k +/- 1.96 * se, which is what ci/perf_profile.py's
 * fit_cell() computes. Two conventions, one section; see
 * perf/findings/CROSS-SESSION.md, entry S1-1. Nobody's file to fix.
 *
 * It matters here because the published interval is 6.4x wider than the
 * tooling's, so gating on it alone would be a lenient test wearing a strict
 * test's clothes. The harness therefore reports BOTH: the published interval
 * decides pass/fail, because "agrees with §6.5" can only mean what §6.5
 * prints, and the tool-convention interval is reported beside it so nobody
 * can be accused of having picked the comfortable one.
 */
constexpr double kAllEdgesStrictLo = 1.996;
constexpr double kAllEdgesStrictHi = 2.027;
constexpr const char *kAllEdgesWhere =
    "PERFORMANCE_PROFILE.md §6.5 evidence 4 (stress.kernel.allEdges, LPM off)";

/* The control. Not part of the pass/fail gate — a linear control is what
 * makes the quadratic a statement about exponents rather than constants, and
 * it is reported alongside so a reader can see the separation. */
constexpr double kBuildOnlyK = 1.063;
constexpr double kBuildOnlyLo = 0.959;
constexpr double kBuildOnlyHi = 1.167;
} /* namespace ref */

/* ------------------------------------------------------------------------ */
/* Fixture                                                                   */
/* ------------------------------------------------------------------------ */

/* frontend/lib/perf_scenarios.dart:151 — n points on a circle of radius r,
 * bulge 0 on every one. Three doubles per vertex, as occt_extrude_profile_arcs
 * wants them. */
static std::vector<double> ringProfile(int n, double r)
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

static occt_shape *buildRing(int n, double r, double h)
{
    const std::vector<double> xyb = ringProfile(n, r);
    const int counts[1] = {n};
    return occt_extrude_profile_arcs(xyb.data(), counts, 1, h, 0.0);
}

/* Facet edge length of a regular n-gon of circumradius r. The ladder's fillet
 * radius has to fit inside the smallest facet on the LARGEST rung, or the
 * blend fails there and the sweep loses its top point. */
static double facetLength(int n, double r)
{
    return 2.0 * r * std::sin(M_PI / n);
}

/* ------------------------------------------------------------------------ */
/* Process memory                                                            */
/* ------------------------------------------------------------------------ */

/* ru_maxrss is kilobytes on Linux and BYTES on Darwin — a difference that
 * silently multiplies every macOS memory number by 1024 if you forget it. */
static double peakRssMb()
{
    struct rusage ru;
    if (getrusage(RUSAGE_SELF, &ru) != 0)
        return 0.0;
#if defined(__APPLE__)
    return static_cast<double>(ru.ru_maxrss) / (1024.0 * 1024.0);
#else
    return static_cast<double>(ru.ru_maxrss) / 1024.0;
#endif
}

/* ------------------------------------------------------------------------ */
/* One measured operation                                                    */
/* ------------------------------------------------------------------------ */

struct Measured {
    std::string op;
    std::string axis;    /* the swept quantity's name, "" when not on a ladder */
    double x = 0.0;      /* its value — edges, edge count filleted, radius */
    int profile_pts = 0; /* 0 when the fixture is not a ring rung */
    int edges = 0;
    int faces = 0;
    Stats t;
    int inner = 1; /* body invocations per timed sample; t is already divided */
    bool alloc_ok = false;
    double alloc_calls = 0.0; /* per iteration */
    double alloc_bytes = 0.0; /* per iteration, bytes REQUESTED */
    double live_bytes = 0.0;  /* per iteration, requested minus released */
    double rss_peak_mb = 0.0;
    double rss_delta_mb = 0.0;
    std::string note;
};

static std::vector<Measured> g_results;

struct RunOpts {
    std::vector<int> sizes{60, 120, 240, 480};
    int reps = 7;
    double budget_ms = 20000.0; /* per operation, per rung */
    bool validate = false;
    std::string json_path;
    std::string md_path;
};

/* Below this, one sample is mostly clock noise: steady_clock resolves to
 * nanoseconds but the call pair around the body costs tens of them, and a
 * 50 us `counts()` measured once is dominated by scheduling. Repeatable
 * operations are therefore run in an inner loop long enough to clear this,
 * and the per-call figure is the interval divided by the loop count. Compare
 * §1.2 of the profile, which does the same reasoning for the device's 1 us
 * quantum. */
static constexpr double kMinSampleMs = 2.0;
static constexpr int kMaxInner = 1 << 20;

/*
 * Runs `body` reps times, timing only the body. `setup`/`teardown` bracket
 * every iteration and are excluded — building a 1440-edge solid costs more
 * than several of the operations measured on it, so folding it in would swamp
 * them. One warm-up iteration is discarded, matching the device suite's
 * convention (§1.3: scenario scope excludes the warm-up pass).
 *
 * `repeatable` says the body may be invoked many times between one setup and
 * one teardown — true for a pure query (edgeInfo, counts, bbox, a ray cast),
 * false for anything that produces a shape the teardown must free. When it is
 * true the loop count is calibrated up front so every sample clears
 * kMinSampleMs, which is what makes the cheap end of the ladder fittable at
 * all: an exponent drawn through three points each measured at the clock's
 * noise floor is a fit through noise.
 */
static Measured measureOp(const RunOpts &opts, const std::string &op,
                          const std::string &axis, double x,
                          const std::function<void()> &setup,
                          const std::function<void()> &body,
                          const std::function<void()> &teardown,
                          bool repeatable = false)
{
    using clock = std::chrono::steady_clock;

    /* Warm-up: first touch of a code path pays for page faults, lazy
     * initialisation inside OCCT and a cold instruction cache. */
    setup();
    body();
    teardown();

    int inner = 1;
    if (repeatable) {
        /* Doubling, not a rate estimate: an estimate from one noisy sample can
         * overshoot by orders of magnitude and spend a minute on a rung. */
        for (;;) {
            setup();
            const auto t0 = clock::now();
            for (int j = 0; j < inner; ++j)
                body();
            const auto t1 = clock::now();
            teardown();
            const double ms =
                std::chrono::duration<double, std::milli>(t1 - t0).count();
            if (ms >= kMinSampleMs || inner >= kMaxInner)
                break;
            /* Guard against a zero reading making this loop pointless. */
            inner *= 2;
        }
    }

    std::vector<double> samples;
    samples.reserve(static_cast<size_t>(opts.reps));

    const double rss_before = peakRssMb();
    const AllocSnapshot a0 = bench::allocSnapshot();
    double spent = 0.0;
    int iters = 0;

    for (int i = 0; i < opts.reps; ++i) {
        setup();
        const auto t0 = clock::now();
        for (int j = 0; j < inner; ++j)
            body();
        const auto t1 = clock::now();
        teardown();
        const double ms =
            std::chrono::duration<double, std::milli>(t1 - t0).count();
        samples.push_back(ms / inner);
        spent += ms;
        ++iters;
        /* A rung that costs seconds does not get seven of them. Stopping on a
         * wall budget keeps the top of the ladder reachable; the report always
         * prints the n actually achieved, so a short sample cannot be mistaken
         * for a full one. */
        if (spent > opts.budget_ms && iters >= 3)
            break;
    }

    const AllocSnapshot a1 = bench::allocSnapshot();

    Measured m;
    m.op = op;
    m.axis = axis;
    m.x = x;
    m.inner = inner;
    m.t = bench::summarise(samples);
    m.rss_peak_mb = peakRssMb();
    m.rss_delta_mb = m.rss_peak_mb - rss_before;
    m.alloc_ok = bench::allocCountingAvailable();
    if (m.alloc_ok && iters > 0) {
        /* setup/teardown allocate too, and they are inside the counted window
         * because the counters cannot be paused. The columns are therefore
         * "allocation traffic of one iteration INCLUDING its fixture churn" —
         * stated here rather than left for a reader to discover. For the ops
         * whose setup is empty (edgeInfo1, allEdges, counts, bbox, rayHits)
         * they are the operation's own traffic exactly, and those are the ones
         * the mechanism claim rests on. */
        const double denom = static_cast<double>(iters) * inner;
        m.alloc_calls = static_cast<double>(a1.calls - a0.calls) / denom;
        m.alloc_bytes = static_cast<double>(a1.bytes - a0.bytes) / denom;
        m.live_bytes =
            static_cast<double>(a1.live_bytes - a0.live_bytes) / denom;
    }
    return m;
}

static void record(Measured m, const std::string &note = std::string())
{
    m.note = note;
    std::printf("  %-22s x=%-10.4g n=%-3d x%-7d mean=%10.5f ms  sd=%8.5f  "
                "p95=%10.5f  cv=%5.1f%%\n",
                m.op.c_str(), m.x, m.t.n, m.inner, m.t.mean, m.t.sd, m.t.p95,
                m.t.cv * 100.0);
    std::fflush(stdout);
    g_results.push_back(std::move(m));
}

/* ------------------------------------------------------------------------ */
/* The ladder                                                                */
/* ------------------------------------------------------------------------ */

/* First edge of the shape a fillet can actually be applied to: OCCT indices
 * are 1-based, and a degenerate or free-boundary edge cannot be blended
 * (occt_capi.h, out12[9] == 2 is the manifold test that
 * OcctEdgeInfo.filletable uses in Dart). */
static std::vector<int> filletableEdges(const occt_shape *s, int want)
{
    std::vector<int> ids;
    const int n = occt_shape_edge_count(s);
    double info[12];
    for (int i = 1; i <= n && static_cast<int>(ids.size()) < want; ++i) {
        if (!occt_shape_edge_info(s, i, info))
            continue;
        if (info[0] != 0.0 && info[7] > 0.0 && info[9] == 2.0)
            ids.push_back(i);
    }
    return ids;
}

/*
 * The ladder needs the SAME GEOMETRIC SITUATION on every rung, and index order
 * does not give it: which kind of edge lands at index 1 varies with n, so a
 * ladder built on "the first filletable edge" was measuring a cap edge on one
 * rung and a vertical corner on the next, and its cost went DOWN as the shape
 * grew. A prism's vertical corner edges are the n edges whose arc length is
 * exactly the extrusion height; blending one of those is one comparable
 * operation at every size. `height` is the fixture's own extrusion height.
 */
static std::vector<int> verticalEdges(const occt_shape *s, double height,
                                      int want)
{
    std::vector<int> ids;
    const int n = occt_shape_edge_count(s);
    double info[12];
    for (int i = 1; i <= n && static_cast<int>(ids.size()) < want; ++i) {
        if (!occt_shape_edge_info(s, i, info))
            continue;
        if (info[0] != 0.0 && info[9] == 2.0 &&
            std::fabs(info[7] - height) < 1.0e-9)
            ids.push_back(i);
    }
    return ids;
}

static void runLadder(const RunOpts &opts)
{
    for (int n : opts.sizes) {
        occt_shape *s = buildRing(n, 40.0, 10.0);
        if (!s) {
            std::printf("  [rung %d] BUILD FAILED: %s\n", n, occt_last_error());
            continue;
        }
        int faces = 0, edges = 0, verts = 0;
        occt_shape_counts(s, &faces, &edges, &verts);
        std::printf("\n[rung] profilePts=%d  edges=%d  faces=%d\n", n, edges,
                    faces);

        auto stamp = [&](Measured m, const char *note) {
            m.profile_pts = n;
            m.edges = edges;
            m.faces = faces;
            record(std::move(m), note);
        };

        const auto noop = []() {};

        /* --- build: the fixture's own cost, and the profile's ramp.kernel.build */
        {
            occt_shape *built = nullptr;
            stamp(measureOp(
                      opts, "build", "edges", edges, noop,
                      [&]() { built = buildRing(n, 40.0, 10.0); },
                      [&]() {
                          occt_free_shape(built);
                          built = nullptr;
                      }),
                  "occt_extrude_profile_arcs — the fixture itself");
        }

        /* --- edgeInfo1: ONE query against a growing shape.
         * §6.5 evidence 2. The requested work is held constant and only the
         * surrounding shape varies, so the exponent here is the per-call cost's
         * dependence on shape size — the term that, plus one call per edge,
         * composes into allEdges. This is half the calibration. */
        {
            double info[12];
            stamp(measureOp(
                      opts, "edgeInfo1", "edges", edges, noop,
                      [&]() { occt_shape_edge_info(s, 1, info); }, noop, true),
                  "one occt_shape_edge_info, index 1, against a growing shape");
        }

        /* --- allEdges: the enumeration Dart's OcctShape.allEdges() performs,
         * reproduced natively so the FFI boundary is out of the picture
         * entirely (§6.5 evidence 3 puts the boundary at 8.1 % of the cost).
         * The other half of the calibration. */
        {
            double info[12];
            stamp(measureOp(
                      opts, "allEdges", "edges", edges, noop,
                      [&]() {
                          const int cnt = occt_shape_edge_count(s);
                          for (int i = 1; i <= cnt; ++i)
                              occt_shape_edge_info(s, i, info);
                      },
                      noop, true),
                  "per-edge enumeration — the quadratic");
        }

        /* --- buildOnly: the CONTROL, and it does strictly MORE work than the
         * subject (build + counts + full tessellation). §6.5 evidence 4. */
        {
            occt_shape *built = nullptr;
            stamp(measureOp(
                      opts, "buildOnly", "edges", edges, noop,
                      [&]() {
                          built = buildRing(n, 40.0, 10.0);
                          if (!built)
                              return;
                          int f = 0, e = 0, v = 0;
                          occt_shape_counts(built, &f, &e, &v);
                          occt_mesh *m = occt_mesh_create(built, 0.2, 0.35);
                          occt_free_mesh(m);
                      },
                      [&]() {
                          occt_free_shape(built);
                          built = nullptr;
                      }),
                  "CONTROL: build + counts + full mesh, never enumerated");
        }

        /* --- the cheap controls of §6.5 evidence 3 */
        {
            int f = 0, e = 0, v = 0;
            stamp(measureOp(
                      opts, "counts", "edges", edges, noop,
                      [&]() { occt_shape_counts(s, &f, &e, &v); }, noop, true),
                  "control: touching the shape is cheap");
        }
        {
            double box[6];
            stamp(measureOp(
                      opts, "bbox", "edges", edges, noop,
                      [&]() { occt_bbox(s, box); }, noop, true),
                  "control: touching the shape is cheap");
        }

        /* --- mesh: tessellation on its own, the profile's §6.4 */
        {
            occt_mesh *m = nullptr;
            stamp(measureOp(
                      opts, "mesh", "edges", edges, noop,
                      [&]() { m = occt_mesh_create(s, 0.2, 0.35); },
                      [&]() {
                          occt_free_mesh(m);
                          m = nullptr;
                      }),
                  "occt_mesh_create at the app's linDeflection 0.2 / ang 0.35");
        }

        /* --- booleans, on operands of the rung's complexity (§6.2, and the
         * profile's ramp.kernel.boolean uses exactly this pair). */
        {
            occt_shape *a = buildRing(n, 40.0, 10.0);
            occt_shape *b = buildRing(n, 25.0, 20.0);
            if (a && b) {
                occt_shape *r = nullptr;
                stamp(measureOp(
                          opts, "fuse", "edges", edges, noop,
                          [&]() { r = occt_fuse(a, b); },
                          [&]() {
                              occt_free_shape(r);
                              r = nullptr;
                          }),
                      "occt_fuse of two ring prisms at this rung's complexity");
                stamp(measureOp(
                          opts, "cut", "edges", edges, noop,
                          [&]() { r = occt_cut(a, b); },
                          [&]() {
                              occt_free_shape(r);
                              r = nullptr;
                          }),
                      "occt_cut of the same pair");
            } else {
                std::printf("  [rung %d] boolean operands failed: %s\n", n,
                            occt_last_error());
            }
            occt_free_shape(a);
            occt_free_shape(b);
        }

        /* --- ray casting: the 3D pick path (§6.7). One ray per iteration,
         * along +X through the solid's waist, as kernel.rayHits does. */
        {
            double hits[32];
            stamp(measureOp(
                      opts, "rayHits", "edges", edges, noop,
                      [&]() {
                          occt_ray_hits(s, -100.0, 0.0, 5.0, 1.0, 0.0, 0.0,
                                        hits, 32);
                      },
                      noop, true),
                  "one ray through the solid — the 3D pick path");
        }

        /* --- fillet against SHAPE SIZE.
         * The radius is held constant across the whole ladder at a quarter of
         * the SMALLEST facet the ladder reaches, so one geometric size is
         * feasible on every rung. A radius that varied with n would confound
         * the sweep: the exponent would then mix shape size with blend size,
         * and §6.3's separate radius sweep below exists precisely because
         * those two are not the same axis. */
        {
            int largest_n = n;
            for (int cand : opts.sizes)
                largest_n = std::max(largest_n, cand);
            /* The largest rung has the SMALLEST facet, so sizing the radius
             * from it keeps one geometric size feasible everywhere. */
            const double r = 0.25 * facetLength(largest_n, 40.0);
            const std::vector<int> ids = verticalEdges(s, 10.0, 1);
            if (!ids.empty()) {
                const double radii[1] = {r};
                occt_shape *out = nullptr;
                stamp(measureOp(
                          opts, "filletEx1", "edges", edges, noop,
                          [&]() {
                              out = occt_fillet_edges_ex(s, ids.data(), radii,
                                                         nullptr, 1, nullptr,
                                                         nullptr);
                          },
                          [&]() {
                              occt_free_shape(out);
                              out = nullptr;
                          }),
                      "occt_fillet_edges_ex, ONE vertical corner edge, radius "
                      "constant across the whole ladder");
            } else {
                std::printf("  [rung %d] no vertical corner edge found\n", n);
            }
        }

        occt_free_shape(s);
    }
}

/* ------------------------------------------------------------------------ */
/* The fixed-solid sweeps — §6.3's two fillet findings                       */
/* ------------------------------------------------------------------------ */

/*
 * Both use ringProfile(24, 40) extruded 10, which is the device fixture for
 * kernel.fillet.edges.N and kernel.fillet.radius.
 *
 * THREE OPERATIONS, NOT TWO, AND THE REASON MATTERS. The device's fillet
 * scenario does two things inside one span: it enumerates the solid's edges to
 * find blend candidates, and then it blends. Reading them apart is the
 * difference between two opposite conclusions —
 *
 *   §6.3's table   `filletEdges` alone   10.1 / 20.8 / 46.7 ms at 1 / 4 / 12
 *                                        edges: k ~ 0.62, plainly per-edge
 *   §10.2's row    "kernel.fillet.edges" 25.54 / 25.57 / 25.83, k = 0.00
 *
 * — and the appendix (§16, `kernel.chamfer.edges.*`) settles it: those 25.5 ms
 * are the row's `ffi.occt.allEdges` column, i.e. the CANDIDATE SEARCH, whose
 * flatness is trivial because it enumerates the same solid however many edges
 * you then blend. See perf/findings/CROSS-SESSION.md S1-4.
 *
 * So the harness measures all three separately — search, blend, and the
 * scenario that is their sum — and nobody has to guess which one a number
 * refers to again.
 */
static void runFilletSweeps(const RunOpts &opts)
{
    occt_shape *s = buildRing(24, 40.0, 10.0);
    if (!s) {
        std::printf("\n[fillet] base solid failed: %s\n", occt_last_error());
        return;
    }
    int faces = 0, edges = 0, verts = 0;
    occt_shape_counts(s, &faces, &edges, &verts);
    std::printf("\n[fillet sweeps] base = ring(24, 40) x 10  edges=%d faces=%d\n",
                edges, faces);

    const auto noop = []() {};

    /* The candidate search itself: what a UI does before it can offer a set of
     * edges to blend. §6.3 says this is 4.9x the cost of the blend at one edge,
     * which points straight back at §6.5 — it IS an enumeration. */
    {
        std::vector<int> got;
        Measured m = measureOp(
            opts, "filletCandidateSearch", "edges", edges, noop,
            [&]() { got = filletableEdges(s, 1 << 30); }, noop, true);
        m.edges = edges;
        m.faces = faces;
        m.profile_pts = 24;
        record(std::move(m),
               "enumerate every filletable edge — what a UI does before it can "
               "offer a blend set");
    }

    for (int k : {1, 4, 12}) {
        const std::vector<int> ids = filletableEdges(s, k);
        if (static_cast<int>(ids.size()) < k) {
            std::printf("  fillet.edges.%d: too few filletable edges\n", k);
            continue;
        }
        const std::vector<double> radii(ids.size(), 1.0);
        occt_shape *out = nullptr;
        Measured m = measureOp(
            opts, "fillet.edges", "edgesBlended", static_cast<double>(k), noop,
            [&]() {
                out = occt_fillet_edges_ex(s, ids.data(), radii.data(), nullptr,
                                           k, nullptr, nullptr);
            },
            [&]() {
                occt_free_shape(out);
                out = nullptr;
            });
        m.edges = edges;
        m.faces = faces;
        m.profile_pts = 24;
        record(std::move(m),
               "the BLEND alone. §6.3's table measured 10.1 / 20.8 / 46.7 ms "
               "at 1 / 4 / 12 on the device — per-edge, not flat");
    }

    /* The SCENARIO: what the device's kernel.fillet.edges.N span covers —
     * candidate search plus blend, in one timed body. Reported beside the two
     * halves so the flat reading and the per-edge reading can both be seen to
     * come from the same run. */
    for (int k : {1, 4, 12}) {
        const std::vector<int> ids = filletableEdges(s, k);
        if (static_cast<int>(ids.size()) < k)
            continue;
        const std::vector<double> radii(ids.size(), 1.0);
        occt_shape *out = nullptr;
        std::vector<int> cands;
        Measured m = measureOp(
            opts, "fillet.scenario", "edgesBlended", static_cast<double>(k),
            noop,
            [&]() {
                cands = filletableEdges(s, 1 << 30);
                out = occt_fillet_edges_ex(s, ids.data(), radii.data(), nullptr,
                                           k, nullptr, nullptr);
            },
            [&]() {
                occt_free_shape(out);
                out = nullptr;
            });
        m.edges = edges;
        m.faces = faces;
        m.profile_pts = 24;
        record(std::move(m),
               "search + blend, as the device scenario span covers them — this "
               "is the one §10.2's flat row describes");
    }

    for (double r : {0.5, 1.0, 2.0, 4.0}) {
        const std::vector<int> ids = filletableEdges(s, 4);
        if (ids.size() < 4)
            break;
        const std::vector<double> radii(ids.size(), r);
        occt_shape *out = nullptr;
        Measured m = measureOp(
            opts, "fillet.radius", "radius", r, noop,
            [&]() {
                out = occt_fillet_edges_ex(s, ids.data(), radii.data(), nullptr,
                                           4, nullptr, nullptr);
            },
            [&]() {
                occt_free_shape(out);
                out = nullptr;
            });
        m.edges = edges;
        m.faces = faces;
        m.profile_pts = 24;
        record(std::move(m),
               "§6.3: 10 ms at r=1.0 against 658 ms at r=4.0 on the device — a "
               "65x discontinuity, and it may be OCCT's own behaviour");
    }

    occt_free_shape(s);
}

/* ------------------------------------------------------------------------ */
/* Fits and the calibration verdict                                          */
/* ------------------------------------------------------------------------ */

struct FitRow {
    std::string op;
    std::string axis;
    Fit fit;
};

static Fit fitOp(const std::string &op, const std::string &axis)
{
    std::vector<std::pair<double, double>> pts;
    for (const auto &m : g_results)
        if (m.op == op && m.axis == axis && m.t.n > 0)
            pts.emplace_back(m.x, m.t.mean);
    return bench::fitPowerLaw(pts);
}

struct Check {
    std::string op;
    std::string where;
    double dev_k = 0.0, dev_lo = 0.0, dev_hi = 0.0;
    /* The same device fit under ci/perf_profile.py's 1.96 convention, where
     * that differs from what the profile printed. Reported, never gating —
     * see the note on ref::kAllEdgesStrictLo. */
    bool has_strict = false;
    double strict_lo = 0.0, strict_hi = 0.0;
    bool strict_overlap = false;
    Fit fit;
    bool gating = false;
    bool overlap = false;
    bool point_in_device = false;
    bool pass = false;
};

static Check makeCheck(const char *op, const char *where, double k, double lo,
                       double hi, bool gating)
{
    Check c;
    c.op = op;
    c.where = where;
    c.dev_k = k;
    c.dev_lo = lo;
    c.dev_hi = hi;
    c.gating = gating;
    c.fit = fitOp(op, "edges");
    if (c.fit.ok) {
        c.point_in_device = (c.fit.k >= lo && c.fit.k <= hi);
        c.overlap = c.fit.have_se
                        ? bench::intervalsOverlap(c.fit.lo, c.fit.hi, lo, hi)
                        : c.point_in_device;
        /* "Agrees within their confidence intervals" means the intervals
         * intersect. Requiring the point estimate to land inside the device
         * interval as well would be a stricter test than the profile's own
         * evidence supports — its two independent arms differ in the third
         * decimal (2.012 against 2.015) and neither is "the" value. */
        c.pass = c.overlap;
    }
    return c;
}

static void addStrict(Check *c, double lo, double hi)
{
    c->has_strict = true;
    c->strict_lo = lo;
    c->strict_hi = hi;
    if (c->fit.ok)
        c->strict_overlap =
            c->fit.have_se ? bench::intervalsOverlap(c->fit.lo, c->fit.hi, lo, hi)
                           : (c->fit.k >= lo && c->fit.k <= hi);
}

/* ------------------------------------------------------------------------ */
/* Reporting                                                                 */
/* ------------------------------------------------------------------------ */

static const char *kDisclaimer =
    "RELATIVE costs, exponents, allocation and RSS may be read from this "
    "table.\nABSOLUTE milliseconds may NOT be quoted as iPad milliseconds "
    "(PERFORMANCE_PROFILE.md §13.3).";

static std::string isoNow()
{
    std::time_t t = std::time(nullptr);
    char buf[32];
    std::strftime(buf, sizeof buf, "%Y-%m-%dT%H:%M:%SZ", std::gmtime(&t));
    return buf;
}

static const char *hostOs()
{
#if defined(__APPLE__)
    return "Darwin";
#elif defined(__linux__)
    return "Linux";
#else
    return "unknown";
#endif
}

static const char *hostArch()
{
#if defined(__aarch64__) || defined(__arm64__)
    return "arm64";
#elif defined(__x86_64__)
    return "x86_64";
#else
    return "unknown";
#endif
}

static void writeJson(const RunOpts &opts, const std::vector<Check> &checks,
                      const std::vector<FitRow> &fits, bool validated)
{
    if (opts.json_path.empty())
        return;
    FILE *f = std::fopen(opts.json_path.c_str(), "w");
    if (!f) {
        std::printf("WARN: cannot write %s\n", opts.json_path.c_str());
        return;
    }
    auto num = [](double v) {
        /* JSON has no NaN or Infinity. A fit with ss_tot == 0 produces one, and
         * emitting it would make the file unparseable for every consumer. */
        return std::isfinite(v) ? v : 0.0;
    };

    std::fprintf(f, "{\n");
    std::fprintf(f, "  \"schema\": \"kernel-bench/1\",\n");
    std::fprintf(f, "  \"generated\": \"%s\",\n", isoNow().c_str());
    std::fprintf(f, "  \"disclaimer\": \"absolute milliseconds are NOT iPad "
                    "milliseconds; see PERFORMANCE_PROFILE.md 13.3\",\n");
    std::fprintf(f,
                 "  \"host\": {\"os\": \"%s\", \"arch\": \"%s\"},\n", hostOs(),
                 hostArch());
    std::fprintf(f, "  \"occt\": {\"version\": \"%s\", \"shim\": %d},\n",
                 occt_version(), occt_shim_version());
    std::fprintf(f,
                 "  \"alloc\": {\"available\": %s, \"mechanism\": \"%s\"},\n",
                 bench::allocCountingAvailable() ? "true" : "false",
                 bench::allocCountingMechanism());
    std::fprintf(f, "  \"config\": {\"reps\": %d, \"budget_ms\": %.1f, "
                    "\"sizes\": [",
                 opts.reps, opts.budget_ms);
    for (size_t i = 0; i < opts.sizes.size(); ++i)
        std::fprintf(f, "%s%d", i ? ", " : "", opts.sizes[i]);
    std::fprintf(f, "]},\n");

    std::fprintf(f, "  \"measurements\": [\n");
    for (size_t i = 0; i < g_results.size(); ++i) {
        const Measured &m = g_results[i];
        std::fprintf(f,
                     "    {\"op\": \"%s\", \"axis\": \"%s\", \"x\": %.6g, "
                     "\"profilePts\": %d, \"edges\": %d, \"faces\": %d, "
                     "\"n\": %d, \"inner\": %d, "
                     "\"mean_ms\": %.9f, \"sd_ms\": %.9f, "
                     "\"p50_ms\": %.9f, \"p95_ms\": %.9f, \"min_ms\": %.9f, "
                     "\"max_ms\": %.9f, \"cv\": %.6f, "
                     "\"alloc_available\": %s, \"alloc_calls\": %.1f, "
                     "\"alloc_bytes\": %.1f, \"live_bytes\": %.1f, "
                     "\"rss_peak_mb\": %.3f, \"rss_delta_mb\": %.3f}%s\n",
                     m.op.c_str(), m.axis.c_str(), m.x, m.profile_pts, m.edges,
                     m.faces, m.t.n, m.inner, num(m.t.mean), num(m.t.sd),
                     num(m.t.p50),
                     num(m.t.p95), num(m.t.min), num(m.t.max), num(m.t.cv),
                     m.alloc_ok ? "true" : "false", m.alloc_calls,
                     m.alloc_bytes, m.live_bytes, m.rss_peak_mb,
                     m.rss_delta_mb,
                     i + 1 < g_results.size() ? "," : "");
    }
    std::fprintf(f, "  ],\n");

    std::fprintf(f, "  \"fits\": [\n");
    for (size_t i = 0; i < fits.size(); ++i) {
        const FitRow &r = fits[i];
        std::fprintf(f,
                     "    {\"op\": \"%s\", \"axis\": \"%s\", \"n\": %d, "
                     "\"k\": %.4f, \"r2\": %.6f, \"have_ci\": %s, "
                     "\"ci\": [%.4f, %.4f]}%s\n",
                     r.op.c_str(), r.axis.c_str(), r.fit.n, num(r.fit.k),
                     num(r.fit.r2), r.fit.have_se ? "true" : "false",
                     num(r.fit.lo), num(r.fit.hi),
                     i + 1 < fits.size() ? "," : "");
    }
    std::fprintf(f, "  ],\n");

    std::fprintf(f, "  \"calibration\": [\n");
    for (size_t i = 0; i < checks.size(); ++i) {
        const Check &c = checks[i];
        char strict_buf[64];
        std::string strict_ci = "null";
        if (c.has_strict) {
            std::snprintf(strict_buf, sizeof strict_buf, "[%.4f, %.4f]",
                          c.strict_lo, c.strict_hi);
            strict_ci = strict_buf;
        }
        std::fprintf(f,
                     "    {\"op\": \"%s\", \"reference\": \"%s\", "
                     "\"device_k\": %.4f, \"device_ci\": [%.4f, %.4f], "
                     "\"bench_k\": %.4f, \"bench_ci\": [%.4f, %.4f], "
                     "\"bench_r2\": %.6f, \"gating\": %s, \"overlap\": %s, "
                     "\"device_ci_tool_convention\": %s, "
                     "\"overlap_tool_convention\": %s, "
                     "\"verdict\": \"%s\"}%s\n",
                     c.op.c_str(), c.where.c_str(), c.dev_k, c.dev_lo, c.dev_hi,
                     num(c.fit.k), num(c.fit.lo), num(c.fit.hi), num(c.fit.r2),
                     c.gating ? "true" : "false", c.overlap ? "true" : "false",
                     strict_ci.c_str(),
                     c.has_strict ? (c.strict_overlap ? "true" : "false")
                                  : "null",
                     c.pass ? "AGREES" : "DISAGREES",
                     i + 1 < checks.size() ? "," : "");
    }
    std::fprintf(f, "  ],\n");
    std::fprintf(f, "  \"validated\": %s\n", validated ? "true" : "false");
    std::fprintf(f, "}\n");
    std::fclose(f);
    std::printf("wrote %s\n", opts.json_path.c_str());
}

static void writeMarkdown(const RunOpts &opts, const std::vector<Check> &checks,
                          const std::vector<FitRow> &fits, bool validated)
{
    if (opts.md_path.empty())
        return;
    FILE *f = std::fopen(opts.md_path.c_str(), "w");
    if (!f) {
        std::printf("WARN: cannot write %s\n", opts.md_path.c_str());
        return;
    }
    std::fprintf(f, "# Lane C — headless kernel benchmark\n\n");
    std::fprintf(f, "%s\n\n", kDisclaimer);
    std::fprintf(f, "| | |\n| --- | --- |\n");
    std::fprintf(f, "| generated | %s |\n", isoNow().c_str());
    std::fprintf(f, "| host | %s / %s |\n", hostOs(), hostArch());
    std::fprintf(f, "| kernel | %s (shim v%d) |\n", occt_version(),
                 occt_shim_version());
    std::fprintf(f, "| allocation counting | %s |\n",
                 bench::allocCountingMechanism());
    std::fprintf(f, "| reps / budget | %d / %.0f ms |\n", opts.reps,
                 opts.budget_ms);

    std::fprintf(f, "\n## Calibration against the device\n\n");
    std::fprintf(f,
                 "The harness is believable only where it reproduces the "
                 "SHAPE of the device finding. Agreement is interval "
                 "overlap.\n\n");
    std::fprintf(f, "| op | device k | device CI (as printed) | bench k | "
                    "bench CI | R² | gating | verdict | vs tool-convention CI |"
                    "\n");
    std::fprintf(f, "| --- | ---: | --- | ---: | --- | ---: | :-: | --- | --- |"
                    "\n");
    for (const Check &c : checks) {
        char bci[64] = "—";
        if (c.fit.have_se)
            std::snprintf(bci, sizeof bci, "[%.3f, %.3f]", c.fit.lo, c.fit.hi);
        char strict[96] = "same convention";
        if (c.has_strict)
            std::snprintf(strict, sizeof strict, "[%.3f, %.3f] → %s",
                          c.strict_lo, c.strict_hi,
                          c.strict_overlap ? "AGREES" : "DISAGREES");
        std::fprintf(f, "| `%s` | %.3f | [%.3f, %.3f] | %.3f | %s | %.4f | %s | "
                        "**%s** | %s |\n",
                     c.op.c_str(), c.dev_k, c.dev_lo, c.dev_hi, c.fit.k, bci,
                     c.fit.r2, c.gating ? "yes" : "no",
                     c.pass ? "AGREES" : "DISAGREES", strict);
    }
    std::fprintf(f, "\n**Harness verdict: %s**\n",
                 validated ? "VALIDATED" : "NOT VALIDATED");

    std::fprintf(f, "\n## Fitted exponents\n\n");
    std::fprintf(f, "| op | axis | N | k | R² | 95 %% CI |\n");
    std::fprintf(f, "| --- | --- | ---: | ---: | ---: | --- |\n");
    for (const FitRow &r : fits) {
        if (!r.fit.ok)
            continue;
        if (r.fit.have_se)
            std::fprintf(f, "| `%s` | %s | %d | %.3f | %.4f | [%.3f, %.3f] |\n",
                         r.op.c_str(), r.axis.c_str(), r.fit.n, r.fit.k,
                         r.fit.r2, r.fit.lo, r.fit.hi);
        else
            std::fprintf(f, "| `%s` | %s | %d | %.3f | — | slope only |\n",
                         r.op.c_str(), r.axis.c_str(), r.fit.n, r.fit.k);
    }

    std::fprintf(f, "\n## Measurements\n\n");
    std::fprintf(f, "| op | axis | x | edges | n | ×inner | mean ms | sd | "
                    "p95 | CV | alloc/call | bytes/call | live Δ | "
                    "RSS peak MB |\n");
    std::fprintf(f, "| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | "
                    "---: | ---: | ---: | ---: | ---: | ---: |\n");
    for (const Measured &m : g_results) {
        if (m.alloc_ok)
            std::fprintf(f,
                         "| `%s` | %s | %.4g | %d | %d | %d | %.5f | %.5f | "
                         "%.5f | %.1f %% | %.0f | %.0f | %+.0f | %.1f |\n",
                         m.op.c_str(), m.axis.c_str(), m.x, m.edges, m.t.n,
                         m.inner, m.t.mean, m.t.sd, m.t.p95, m.t.cv * 100.0,
                         m.alloc_calls, m.alloc_bytes, m.live_bytes,
                         m.rss_peak_mb);
        else
            std::fprintf(f,
                         "| `%s` | %s | %.4g | %d | %d | %d | %.5f | %.5f | "
                         "%.5f | %.1f %% | n/a | n/a | n/a | %.1f |\n",
                         m.op.c_str(), m.axis.c_str(), m.x, m.edges, m.t.n,
                         m.inner, m.t.mean, m.t.sd, m.t.p95, m.t.cv * 100.0,
                         m.rss_peak_mb);
    }
    std::fprintf(f, "\n### Notes\n\n");
    for (const Measured &m : g_results)
        if (!m.note.empty())
            std::fprintf(f, "- `%s` (x=%.4g): %s\n", m.op.c_str(), m.x,
                         m.note.c_str());
    std::fclose(f);
    std::printf("wrote %s\n", opts.md_path.c_str());
}

/* ------------------------------------------------------------------------ */
/* main                                                                      */
/* ------------------------------------------------------------------------ */

static void usage()
{
    std::printf(
        "occt_bench — Lane C headless kernel benchmark\n"
        "\n"
        "  --sizes A,B,C     ring profile-point rungs (default 60,120,240,480)\n"
        "  --reps N          repetitions per operation (default 7)\n"
        "  --budget-ms MS    wall budget per operation per rung (default 20000)\n"
        "  --json PATH       write the machine-readable report\n"
        "  --md PATH         write the human-readable report\n"
        "  --validate        exit non-zero unless the gating exponents agree\n"
        "                    with PERFORMANCE_PROFILE.md §6.5\n"
        "  --quick           a fast shape-only run (sizes 60,120,240, reps 3)\n"
        "  --help\n");
}

static std::vector<int> parseSizes(const char *s)
{
    std::vector<int> out;
    const char *p = s;
    while (*p) {
        char *end = nullptr;
        const long v = std::strtol(p, &end, 10);
        if (end == p)
            break;
        if (v > 2)
            out.push_back(static_cast<int>(v));
        p = end;
        while (*p == ',' || *p == ' ')
            ++p;
    }
    return out;
}

int main(int argc, char **argv)
{
    RunOpts opts;
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        auto next = [&](const char *what) -> const char * {
            if (i + 1 >= argc) {
                std::printf("missing value for %s\n", what);
                std::exit(2);
            }
            return argv[++i];
        };
        if (a == "--sizes")
            opts.sizes = parseSizes(next("--sizes"));
        else if (a == "--reps")
            opts.reps = std::atoi(next("--reps"));
        else if (a == "--budget-ms")
            opts.budget_ms = std::atof(next("--budget-ms"));
        else if (a == "--json")
            opts.json_path = next("--json");
        else if (a == "--md")
            opts.md_path = next("--md");
        else if (a == "--validate")
            opts.validate = true;
        else if (a == "--quick") {
            opts.sizes = {60, 120, 240};
            opts.reps = 3;
        } else if (a == "--help" || a == "-h") {
            usage();
            return 0;
        } else {
            std::printf("unknown argument: %s\n", a.c_str());
            usage();
            return 2;
        }
    }
    if (opts.sizes.size() < 3) {
        std::printf("FAIL: at least three rungs are needed for a fit with a "
                    "confidence interval (got %zu)\n",
                    opts.sizes.size());
        return 2;
    }
    if (opts.reps < 2) {
        std::printf("FAIL: --reps must be at least 2\n");
        return 2;
    }

    std::printf("=== Lane C kernel bench ===\n");
    std::printf("%s\n\n", kDisclaimer);
    std::printf("kernel : %s (shim v%d)\n", occt_version(), occt_shim_version());
    std::printf("host   : %s / %s\n", hostOs(), hostArch());

    /* The allocation counters are proved before they are used, never after —
     * a column of silent zeroes is the failure mode this guards against. */
    bench::allocSelfTest();
    std::printf("alloc  : %s\n", bench::allocCountingMechanism());
    std::printf("rungs  :");
    for (int n : opts.sizes)
        std::printf(" %d", n);
    std::printf("  (profile points; edges are 3x)\n");
    std::printf("reps   : %d, budget %.0f ms per op per rung\n", opts.reps,
                opts.budget_ms);

    runLadder(opts);
    runFilletSweeps(opts);

    /*
     * End-to-end check on the allocation counters, and it is not the same
     * check the self-test performs. The self-test proves THIS program's
     * allocations are seen; it cannot prove that the statically linked
     * kernel's are, because symbol redirection reaches only what our link line
     * resolved. Building and tessellating a solid allocates, unavoidably and
     * heavily — so if not one operation moved the counters, the interposition
     * missed OCCT and every memory column is a lie of omission. Report nothing
     * rather than zeroes (the §13.1 rule: a number nobody can trust is worse
     * than an absent one).
     */
    if (bench::allocCountingAvailable()) {
        double seen = 0.0;
        for (const Measured &m : g_results)
            seen = std::max(seen, m.alloc_calls);
        if (seen <= 0.0) {
            std::printf("\nWARN: allocation counters never moved during "
                        "kernel work — the interposition does not reach OCCT "
                        "on this toolchain. Memory columns are reported as "
                        "n/a.\n");
            bench::allocMarkIneffective();
            for (Measured &m : g_results) {
                m.alloc_ok = false;
                m.alloc_calls = m.alloc_bytes = m.live_bytes = 0.0;
            }
        }
    }

    /* ---- fits ---- */
    std::vector<FitRow> fits;
    for (const char *op : {"build", "edgeInfo1", "allEdges", "buildOnly",
                           "counts", "bbox", "mesh", "fuse", "cut", "rayHits",
                           "filletEx1"}) {
        FitRow r;
        r.op = op;
        r.axis = "edges";
        r.fit = fitOp(op, "edges");
        if (r.fit.ok)
            fits.push_back(r);
    }
    {
        for (const char *op : {"fillet.edges", "fillet.scenario"}) {
            FitRow r;
            r.op = op;
            r.axis = "edgesBlended";
            r.fit = fitOp(op, "edgesBlended");
            if (r.fit.ok)
                fits.push_back(r);
        }
        FitRow r2;
        r2.op = "fillet.radius";
        r2.axis = "radius";
        r2.fit = fitOp("fillet.radius", "radius");
        if (r2.fit.ok)
            fits.push_back(r2);
    }

    /* ---- calibration ---- */
    std::vector<Check> checks;
    checks.push_back(makeCheck("edgeInfo1", ref::kEdgeInfoWhere, ref::kEdgeInfoK,
                               ref::kEdgeInfoLo, ref::kEdgeInfoHi, true));
    checks.push_back(makeCheck("allEdges", ref::kAllEdgesWhere, ref::kAllEdgesK,
                               ref::kAllEdgesLo, ref::kAllEdgesHi, true));
    addStrict(&checks.back(), ref::kAllEdgesStrictLo, ref::kAllEdgesStrictHi);
    checks.push_back(makeCheck("buildOnly",
                               "PERFORMANCE_PROFILE.md §6.5 evidence 4 (control)",
                               ref::kBuildOnlyK, ref::kBuildOnlyLo,
                               ref::kBuildOnlyHi, false));

    bool validated = true;
    std::printf("\n=== Calibration against PERFORMANCE_PROFILE.md §6.5 ===\n");
    for (const Check &c : checks) {
        char bci[64] = "(no interval)";
        if (c.fit.have_se)
            std::snprintf(bci, sizeof bci, "[%.3f, %.3f]", c.fit.lo, c.fit.hi);
        std::printf("  %-12s device k=%.3f [%.3f, %.3f]  bench k=%.3f %s  "
                    "R2=%.4f  %s%s\n",
                    c.op.c_str(), c.dev_k, c.dev_lo, c.dev_hi, c.fit.k, bci,
                    c.fit.r2, c.pass ? "AGREES" : "DISAGREES",
                    c.gating ? "" : "  (informational)");
        if (c.has_strict)
            std::printf("  %-12s   also vs the tool-convention interval "
                        "[%.3f, %.3f] (ci/perf_profile.py's 1.96): %s"
                        "  (informational — see CROSS-SESSION.md S1-1)\n",
                        "", c.strict_lo, c.strict_hi,
                        c.strict_overlap ? "AGREES" : "DISAGREES");
        if (c.gating && !c.pass)
            validated = false;
    }

    /* A control that does NOT separate from the subject would mean the fixture
     * is not exercising what §6.5 exercised, whatever the exponents say. */
    {
        const Fit sub = fitOp("allEdges", "edges");
        const Fit ctl = fitOp("buildOnly", "edges");
        if (sub.ok && ctl.ok)
            std::printf("  separation : allEdges k=%.3f vs buildOnly k=%.3f "
                        "(device: 2.012 vs 1.063)\n",
                        sub.k, ctl.k);
    }

    std::printf("\nHARNESS: %s\n", validated ? "VALIDATED" : "NOT VALIDATED");

    writeJson(opts, checks, fits, validated);
    writeMarkdown(opts, checks, fits, validated);

    if (opts.validate && !validated) {
        std::printf("\nLANE C: FAIL (a gating exponent does not agree with "
                    "§6.5 — the harness is wrong, not the device)\n");
        return 1;
    }
    std::printf("\nLANE C: PASS\n");
    return 0;
}
