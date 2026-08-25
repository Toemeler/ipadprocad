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
#include "bench_sweep.h"

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

/* Facet edge length of a regular n-gon of circumradius r — what limits how
 * large a fillet the ladder's solids can hold. */
static double facetLength(int n, double r)
{
    return 2.0 * r * std::sin(M_PI / n);
}

/* The ladder's fillet radius, in model units. Fixed on purpose; see the note
 * at its use site. */
static constexpr double kLadderFilletRadius = 0.1;

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
    /* False when the operation FAILED at this rung. `t` is then a
     * time-to-failure, not a cost, and no fit may include it. The sweep
     * ladders need this: the 1200-segment rung on the device did not run
     * slowly, it ran for four minutes and produced nothing, and a report that
     * cannot say so would rank a failure as the fastest large rung. */
    bool ok = true;
    std::string note;
};

static std::vector<Measured> g_results;

struct RunOpts {
    std::vector<int> sizes{60, 120, 240, 480};
    int reps = 7;
    double budget_ms = 20000.0; /* per operation, per rung */
    bool validate = false;
    bool no_alloc = false;
    std::string json_path;
    std::string md_path;

    /* The sweep ladders (see runSweepLadders). Their default rungs are small
     * on purpose: this benchmark runs on every push to claude/perf-opt**, and
     * the device's own top rungs cost minutes EACH. --sweep-sizes reaches
     * them when that is what you want; --no-sweep turns the section off. */
    bool sweep = true;
    std::vector<int> sweep_sizes{32, 64, 128};
    std::vector<int> sweep_spans{1, 2, 4, 8, 16};
    int sweep_fixed_spans = 16;    /* the path for the segments ladder */
    int sweep_fixed_segments = 128; /* the profile for the spans ladder */
    int sweep_legacy_max = 128;     /* above this the v23 arm is skipped */
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
                          bool repeatable = false, int min_iters = 3)
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
         * for a full one.
         *
         * `min_iters` is 3 for everything the ladder and the fillet sweeps
         * measure, and that floor is deliberate — three samples is the fewest
         * that has a spread at all. The sweep ladders lower it to 2, because
         * one of THEIR rungs cost the device four minutes: three of those plus
         * a warm-up is sixteen minutes for one point, and the point is not
         * sixteen minutes more informative than it is at two. Where it is
         * lowered, `n` in the report says so. */
        if (spent > opts.budget_ms && iters >= min_iters)
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
        std::printf("\n[rung] profilePts=%d  edges=%d  faces=%d  facet=%.4f mm "
                    "(ladder fillet radius %.4f)\n",
                    n, edges, faces, facetLength(n, 40.0), kLadderFilletRadius);

        /*
         * THE FIXTURE IS PINNED HERE, not merely described in a comment.
         *
         * Every number this harness produces is comparable to §6.5 only
         * because the solid is the device's solid: ringProfile(n, 40) has
         * every bulge zero, so extruding it gives an n-gon prism — n lateral
         * faces plus two caps, and 3n edges (n on each cap, n vertical). The
         * device's own gauges agree: 120 profile points reported 360 edges and
         * 122 faces.
         *
         * If a kernel change ever merges coplanar faces, or the profile grows
         * a bulge, or someone "improves" ringProfile, the exponents would shift
         * and the calibration gate would fail — but it would fail pointing at
         * the exponent, and the next person would spend a day on the fit
         * before finding the fixture. This says so in one line instead.
         *
         * Loud, not fatal: a changed fixture still produces a self-consistent
         * ladder worth looking at, and the report carries the warning.
         */
        if (edges != 3 * n || faces != n + 2)
            std::printf("      WARNING: fixture is not the device fixture — "
                        "expected %d edges and %d faces for an n-gon prism, "
                        "got %d and %d. Comparisons to PERFORMANCE_PROFILE.md "
                        "§6.5 are NOT valid for this rung.\n",
                        3 * n, n + 2, edges, faces);

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

        /*
         * --- allEdgesBulk: the SAME enumeration through Session 2's single
         * bulk call, on the SAME solid, in the same run.
         *
         * Requested as `CROSS-SESSION.md` S2-1, and it is the number that
         * session cannot get any other way before the device run: two fitted
         * exponents on identical solids is the isolation §6.5 evidence 4 built,
         * and here it separates "the quadratic was the per-call whole-shape
         * work" from "the quadratic was something else" with no iPad involved.
         *
         * Guarded on the shim version rather than at configure time, so a bench
         * built against an older shim reports the op as absent instead of
         * failing to link (S2-1 item 3).
         */
        if (occt_shim_version() >= 21) {
            std::vector<double> buf(static_cast<size_t>(edges) * 12);
            int got = 0;
            stamp(measureOp(
                      opts, "allEdgesBulk", "edges", edges, noop,
                      [&]() {
                          got = occt_shape_edges_info(s, buf.data(), edges);
                      },
                      noop, true),
                  "the same enumeration through ONE occt_shape_edges_info call "
                  "(shim v21+) — compare its exponent against allEdges");
            if (got != edges)
                std::printf("      WARNING: bulk call returned %d records for "
                            "%d edges (%s)\n",
                            got, edges, occt_last_error());
        } else {
            std::printf("      allEdgesBulk: skipped, shim v%d has no "
                        "occt_shape_edges_info (needs v21)\n",
                        occt_shim_version());
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
         * The radius is a FIXED CONSTANT, not derived from the ladder. It was
         * derived from the ladder at first — a quarter of the smallest facet
         * the ladder reached — and that was wrong in a way worth recording:
         * it made the radius depend on --sizes, so a three-rung run and a
         * four-rung run measured different operations at the same rung and
         * their numbers could not be compared. A benchmark whose fixture moves
         * with its arguments cannot be used to compare two runs, which is the
         * only thing anyone wants a benchmark for.
         *
         * kLadderFilletRadius is small enough to fit inside the facet of every
         * rung the ladder can reach: a ring(n, 40) prism has facet length
         * 80*sin(pi/n), which is 0.209 mm at n = 1200, so 0.1 mm stays under
         * half a facet up to sizes far beyond anything measurable here. If a
         * future ladder goes past that, change the constant deliberately and
         * re-derive, rather than letting it drift. */
        {
            const double r = kLadderFilletRadius;
            const std::vector<int> ids = verticalEdges(s, 10.0, 1);
            if (!ids.empty()) {
                const double radii[1] = {r};
                occt_shape *out = nullptr;
                /* The _ex form reports what the plain form cannot: which input
                 * edges got no blend, and the relative size actually built
                 * (below 1.0 means the asked-for radius landed on a tangency
                 * and the shim retried a hair smaller — see occt_capi.h). A
                 * rung that quietly took the retry ladder would otherwise look
                 * like an unexplained cost, and the ladder HAS one such rung.
                 * Collecting the diagnostic the shim already offers costs
                 * nothing and turns "unexplained" into "explained or not". */
                int dropped = 0;
                double scale = 1.0;
                stamp(measureOp(
                          opts, "filletEx1", "edges", edges, noop,
                          [&]() {
                              out = occt_fillet_edges_ex(s, ids.data(), radii,
                                                         nullptr, 1, &dropped,
                                                         &scale);
                          },
                          [&]() {
                              occt_free_shape(out);
                              out = nullptr;
                          }),
                      "occt_fillet_edges_ex, ONE vertical corner edge, at a "
                      "radius fixed independently of the ladder");
                std::printf("      fillet report: dropped=%d scale=%.6f%s\n",
                            dropped, scale,
                            (dropped || scale < 1.0)
                                ? "  <-- NOT the plain case"
                                : "");
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

    /*
     * The CATASTROPHE GUARD, decomposed — `CROSS-SESSION.md` S2-2.
     *
     * Session 2 read occt_fillet_edges_ex and found six whole-shape operations
     * per call, none of them per-edge, of which three are the guard that keeps
     * a corrupt solid from reaching the mesher: solid_volume(base),
     * solid_volume(out), and BRepCheck_Analyzer(out).IsValid(). Session 2 did
     * not touch them — removing them would let corrupt solids through, which is
     * a behaviour change and out of scope for this branch — and asked instead
     * for the one number that decides whether a cheaper guard is worth
     * designing: WHAT FRACTION OF THE FLAT COST IS THE GUARD?
     *
     * Both halves are benchable through entry points that already exist.
     * `2 x volume + valid` on this same base solid bounds the guard FROM BELOW:
     * the shim's second volume integration runs on the RESULT, which carries
     * the blend and is a little larger than the base, so measuring it on the
     * base under-states it. A lower bound is what settles the question in the
     * direction it needs settling — if even the lower bound is large, the guard
     * matters.
     */
    {
        double v = 0.0;
        Measured m = measureOp(
            opts, "volume", "edges", edges, noop,
            [&]() { v = occt_shape_volume(s); }, noop, true);
        m.edges = edges;
        m.faces = faces;
        m.profile_pts = 24;
        record(std::move(m),
               "one occt_shape_volume — the guard runs TWO of these per fillet "
               "(S2-2)");
    }
    {
        int ok = 0;
        Measured m = measureOp(
            opts, "valid", "edges", edges, noop,
            [&]() { ok = occt_shape_valid(s); }, noop, true);
        m.edges = edges;
        m.faces = faces;
        m.profile_pts = 24;
        record(std::move(m),
               "one occt_shape_valid — BRepCheck_Analyzer, the third leg of the "
               "guard (S2-2)");
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

    /*
     * The answer S2-2 asked for, computed here rather than left for a reader to
     * do with a calculator, because a number nobody works out is a number
     * nobody reads.
     */
    {
        const Measured *vol = nullptr, *val = nullptr, *blend = nullptr;
        for (const Measured &m : g_results) {
            if (m.op == "volume")
                vol = &m;
            else if (m.op == "valid")
                val = &m;
            else if (m.op == "fillet.edges" && m.x == 1.0)
                blend = &m;
        }
        if (vol && val && blend && blend->t.mean > 0.0) {
            const double guard = 2.0 * vol->t.mean + val->t.mean;
            std::printf("\n  [S2-2] guard lower bound = 2 x volume (%.4f) + "
                        "valid (%.4f) = %.4f ms\n",
                        vol->t.mean, val->t.mean, guard);
            std::printf("         whole fillet call at one edge = %.4f ms\n",
                        blend->t.mean);
            std::printf("         => the guard is AT LEAST %.1f %% of it\n",
                        100.0 * guard / blend->t.mean);
        }
    }

    occt_free_shape(s);
}

/* ------------------------------------------------------------------------ */
/* The sweep ladders — the axis no tier measured until the device did         */
/* ------------------------------------------------------------------------ */

/*
 * WHAT THESE MEASURE, AND WHY THEY ARE HERE
 *
 * A device capture on 2026-08-24 (build cb1d183) ran S11's opt-in profile
 * tier. `profile.sweep.segments` — an N-segment ring swept along a 16-span
 * path — read 91 ms at N=32, 1 253 ms at N=128, 132 112 ms at N=512, and at
 * N=1200 it did not produce a solid at all: 231 085 ms and then
 * "occt_sweep_profile: BRep_API: command not done".
 *
 * `profile.sweep.spans` held the profile at 512 segments and varied the PATH,
 * and that is the measurement that says where to look: 94 ms with ONE span
 * (no interior corner at all), 79 306 ms with four. **843x for 4x the faces.**
 * Then 3 -> 15 corners costs only another 1.67x. The cost is a STEP that fires
 * at the first corner and is nearly flat in the corner count afterwards.
 *
 * Two ladders reproduce that here, plus a phase breakdown that says WHICH of
 * the five steps inside occt_sweep_profile the time is in, plus variants that
 * say what removes it. The variants are measured through bench_sweep.h's
 * replica of the pipeline; the ladders go through the shipped C entry point.
 * `sweep.replica` measures the same fixture both ways so the replica's
 * agreement with the original is a number in the report rather than a claim.
 *
 * The fixture is the device fixture: perf_scenarios_profile.dart sweeps
 * arcRing(segments, 6) along arcPath(spans + 1, 60).
 */

static const double kIdentity34[12] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0};

/* One sweep through the shipped entry point. Returns the shape or null, and
 * always fills `ms` — a failure has a duration too, and on the device it was
 * four minutes. */
static occt_shape *sweepOnce(int segments, int spans, double *ms,
                             int path_mode = OCCT_SWEEP_PATH_AUTO)
{
    const std::vector<double> prof = bench::arcRingXYB(segments, 6.0);
    const std::vector<double> path = bench::arcPathXYZ(spans + 1, 60.0);
    const int counts[1] = {segments};
    const auto t0 = std::chrono::steady_clock::now();
    occt_shape *s =
        occt_sweep_profile_ex(prof.data(), counts, 1, kIdentity34, path.data(),
                              spans + 1, 0, 0.0, 0.0, path_mode);
    const auto t1 = std::chrono::steady_clock::now();
    if (ms)
        *ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    return s;
}

/* The CONTROL, and it needs no new entry point: occt_coil_profile sweeps the
 * same kind of section along an EXACT HELIX — one analytic edge, no joints,
 * and it does not set a transition mode at all. Placing its axis 18 units from
 * the profile centroid and asking for a quarter turn rising 60 makes it the
 * same geometry arcPath(spans+1, 60) samples: a quarter turn of radius 18
 * climbing to z = 60. Same section, same path, same face count — the only
 * difference is that one spine is a curve and the other is a polyline sample
 * of that curve. If the polyline sweep is minutes and the coil is
 * milliseconds, the segments are not what is expensive. */
static occt_shape *coilOnce(int segments, double *ms)
{
    const std::vector<double> prof = bench::arcRingXYB(segments, 6.0);
    const int counts[1] = {segments};
    const auto t0 = std::chrono::steady_clock::now();
    occt_shape *s = occt_coil_profile(prof.data(), counts, 1, kIdentity34,
                                      -18.0, 0.0, 0.0, /* axis point */
                                      0.0, 0.0, 1.0,   /* axis direction */
                                      0.25, 60.0, 0.0, 0, 0, 0);
    const auto t1 = std::chrono::steady_clock::now();
    if (ms)
        *ms = std::chrono::duration<double, std::milli>(t1 - t0).count();
    return s;
}

/* Records one rung of a sweep ladder. A rung is PROBED once before it is
 * measured: at these sizes a failing rung costs minutes per attempt, and
 * measureOp would pay for it eight times over to learn what one attempt
 * already knows. The probe's own duration is what a failed rung reports. */
static void sweepRung(const RunOpts &opts, const char *op, const char *axis,
                      double x, int segments, int spans, const char *note,
                      bool coil = false,
                      int path_mode = OCCT_SWEEP_PATH_AUTO)
{
    const auto build = [&](double *ms) {
        return coil ? coilOnce(segments, ms)
                    : sweepOnce(segments, spans, ms, path_mode);
    };
    double probe_ms = 0.0;
    occt_shape *first = build(&probe_ms);
    if (!first) {
        Measured m;
        m.op = op;
        m.axis = axis;
        m.x = x;
        m.ok = false;
        m.t = bench::summarise({probe_ms});
        m.profile_pts = segments;
        m.rss_peak_mb = peakRssMb();
        std::printf("  %-22s x=%-10.4g  *** FAILED *** after %.1f ms : %s\n", op,
                    x, probe_ms, occt_last_error());
        std::fflush(stdout);
        m.note = std::string("FAILED after ") + std::to_string(probe_ms) +
                 " ms: " + occt_last_error() + " — the duration is a "
                 "time-to-failure, NOT a cost; no fit includes it";
        g_results.push_back(std::move(m));
        return;
    }
    int faces = 0, edges = 0, verts = 0;
    occt_shape_counts(first, &faces, &edges, &verts);
    const double vol = occt_shape_volume(first);
    occt_free_shape(first);

    occt_shape *out = nullptr;
    Measured m = measureOp(
        opts, op, axis, x, []() {},
        [&]() { out = build(nullptr); },
        [&]() {
            if (out)
                occt_free_shape(out);
            out = nullptr;
        },
        false, 2);
    m.faces = faces;
    m.edges = edges;
    m.profile_pts = segments;
    char buf[320];
    if (coil)
        std::snprintf(buf, sizeof buf,
                      "%s — %d segments, %d faces, volume %.4f", note, segments,
                      faces, vol);
    else
        std::snprintf(buf, sizeof buf,
                      "%s — %d segments x %d spans, %d faces, volume %.4f",
                      note, segments, spans, faces, vol);
    record(std::move(m), buf);
}

/* Runs the replica `reps` times and records every phase as its own row, so
 * the phase table carries the same sd/p95 discipline as the ladder. */
static void sweepPhases(const RunOpts &opts, const char *prefix,
                        const char *axis, double x, int segments, int spans,
                        bench::Corner corner, bench::Spine spine, bool unify,
                        double angminRad, const char *note)
{
    std::vector<double> wire, sp, build, solid, uni, total;
    bench::SweepPhases last;
    double spent = 0.0;
    for (int i = 0; i < opts.reps; ++i) {
        last = bench::sweepReplica(segments, spans, corner, spine, unify,
                                   angminRad);
        spent += last.total;
        if (last.ok) {
            wire.push_back(last.wire);
            sp.push_back(last.spine);
            build.push_back(last.build);
            solid.push_back(last.solid);
            uni.push_back(last.unify);
        }
        total.push_back(last.total);
        if (!last.ok)
            break;
        if (spent > opts.budget_ms && i >= 1)
            break;
    }

    char buf[320];
    if (!last.ok) {
        Measured m;
        m.op = std::string(prefix) + ".total";
        m.axis = axis;
        m.x = x;
        m.ok = false;
        m.t = bench::summarise(total);
        m.profile_pts = segments;
        m.rss_peak_mb = peakRssMb();
        std::snprintf(buf, sizeof buf,
                      "%s — FAILED after %.1f ms in the replica: %s (a "
                      "time-to-failure, not a cost)",
                      note, last.total, last.err.c_str());
        m.note = buf;
        std::printf("  %-22s x=%-10.4g  *** FAILED *** after %.1f ms : %s\n",
                    m.op.c_str(), x, last.total, last.err.c_str());
        std::fflush(stdout);
        g_results.push_back(std::move(m));
        return;
    }

    struct { const char *suffix; std::vector<double> *v; } rows[] = {
        {".wire", &wire}, {".spine", &sp},     {".build", &build},
        {".solid", &solid}, {".unify", &uni},  {".total", &total},
    };
    for (const auto &r : rows) {
        Measured m;
        m.op = std::string(prefix) + r.suffix;
        m.axis = axis;
        m.x = x;
        m.t = bench::summarise(*r.v);
        m.faces = last.faces;
        m.profile_pts = segments;
        m.rss_peak_mb = peakRssMb();
        std::snprintf(buf, sizeof buf,
                      "%s — %d seg x %d spans, %d faces, spine edges %d, "
                      "volume %.6f, %s",
                      note, segments, spans, last.faces, last.spineEdges,
                      last.volume, last.valid ? "valid" : "INVALID");
        record(std::move(m), buf);
    }
}

/* One variant, at one rung, reported next to the shipped pipeline's geometry.
 * Cost is only half of what a variant has to answer; the other half is what
 * it does to the SHAPE, so volume, face count and validity travel with it. */
static void sweepVariant(const RunOpts &opts, const char *name, int segments,
                         int spans, bench::Corner corner, bench::Spine spine,
                         bool unify, double angminRad, double refVolume,
                         const char *note)
{
    std::vector<double> total;
    bench::SweepPhases last;
    double spent = 0.0;
    for (int i = 0; i < opts.reps; ++i) {
        last = bench::sweepReplica(segments, spans, corner, spine, unify,
                                   angminRad);
        total.push_back(last.total);
        spent += last.total;
        if (!last.ok)
            break;
        if (spent > opts.budget_ms && i >= 1)
            break;
    }
    Measured m;
    m.op = std::string("sweep.var.") + name;
    m.axis = "segments";
    m.x = segments;
    m.ok = last.ok;
    m.t = bench::summarise(total);
    m.faces = last.faces;
    m.profile_pts = segments;
    m.rss_peak_mb = peakRssMb();
    char buf[400];
    if (!last.ok) {
        std::snprintf(buf, sizeof buf,
                      "%s — FAILED after %.1f ms: %s (time-to-failure)", note,
                      last.total, last.err.c_str());
        std::printf("  %-22s x=%-10d  *** FAILED *** after %.1f ms : %s\n",
                    m.op.c_str(), segments, last.total, last.err.c_str());
        std::fflush(stdout);
        m.note = buf;
        g_results.push_back(std::move(m));
        return;
    }
    const double dv = refVolume > 0.0
                          ? 100.0 * (last.volume - refVolume) / refVolume
                          : 0.0;
    std::snprintf(buf, sizeof buf,
                  "%s — %d faces, spine edges %d, volume %.6f (%+.4f %% vs the "
                  "v23 pipeline), %s",
                  note, last.faces, last.spineEdges, last.volume, dv,
                  last.valid ? "valid" : "INVALID");
    record(std::move(m), buf);
}

static void runSweepLadders(const RunOpts &opts)
{
    if (!opts.sweep)
        return;

    std::printf("\n[sweep ladders] fixture: arcRing(segments, 6) swept along "
                "arcPath(spans+1, 60)\n");
    std::printf("  path geometry (the axis that separates corner COUNT from "
                "total TURNING):\n");
    for (int spans : opts.sweep_spans) {
        const std::vector<double> p = bench::arcPathXYZ(spans + 1, 60.0);
        std::printf("    spans=%-4d corners=%-4d totalTurn=%7.3f deg  "
                    "maxCorner=%6.3f deg\n",
                    spans, spans - 1, bench::pathTurnDeg(p),
                    bench::pathMaxCornerDeg(p));
    }

    /* Ladder 1 — the device's profile.sweep.segments. */
    std::printf("\n  -- sweep.segments (spans fixed at %d) --\n",
                opts.sweep_fixed_spans);
    for (int n : opts.sweep_sizes)
        sweepRung(opts, "sweep.segments", "segments", n, n,
                  opts.sweep_fixed_spans,
                  "occt_sweep_profile against profile segment count");

    /*
     * The LEGACY arm — old against new, one run, one machine, which is what
     * OPTIMIZATION_PLAN_2.md §1.4 requires of an equivalence claim and what a
     * recorded constant cannot give. OCCT_SWEEP_PATH_POLY is v23 bit for bit.
     *
     * It is CAPPED, and the cap is the point: at 512 segments the legacy path
     * is 447 seconds on the machine this was written on, and at 1200 it does
     * not finish at all — it fails after 742 seconds. A benchmark that runs on
     * every push cannot climb that ladder, so the legacy arm stops where it is
     * still affordable and `--sweep-legacy-max` moves the line for anyone who
     * wants to watch it break.
     */
    std::printf("\n  -- sweep.legacy (OCCT_SWEEP_PATH_POLY — the v23 spine, "
                "capped at %d segments) --\n", opts.sweep_legacy_max);
    for (int n : opts.sweep_sizes) {
        if (n > opts.sweep_legacy_max) {
            std::printf("  sweep.legacy           x=%-10d skipped (above "
                        "--sweep-legacy-max %d; v23 costs 447 s at 512 and "
                        "FAILS at 1200)\n", n, opts.sweep_legacy_max);
            continue;
        }
        sweepRung(opts, "sweep.legacy", "segments", n, n,
                  opts.sweep_fixed_spans,
                  "occt_sweep_profile_ex with OCCT_SWEEP_PATH_POLY — the v23 "
                  "polyline spine, every joint mitered",
                  false, OCCT_SWEEP_PATH_POLY);
    }

    /* The control: the same geometry through a spine that is a CURVE. */
    std::printf("\n  -- sweep.coil (the same quarter turn, as an exact helix) --\n");
    for (int n : opts.sweep_sizes)
        sweepRung(opts, "sweep.coil", "segments", n, n, opts.sweep_fixed_spans,
                  "occt_coil_profile — same section, same quarter turn of "
                  "radius 18 rising 60, but the spine is one analytic helix "
                  "edge instead of a polyline sample of it",
                  true);

    /* Ladder 2 — the device's profile.sweep.spans, the one that localises the
     * cost to the corner. */
    std::printf("\n  -- sweep.spans (profile fixed at %d segments) --\n",
                opts.sweep_fixed_segments);
    for (int spans : opts.sweep_spans)
        sweepRung(opts, "sweep.spans", "spans", spans, opts.sweep_fixed_segments,
                  spans, "occt_sweep_profile against path span count");

    /* The phase breakdown, at the rung the variants are compared on. */
    const int pn = opts.sweep_fixed_segments;
    const int ps = opts.sweep_fixed_spans;
    std::printf("\n  -- sweep.ph.* : where the time goes inside one call "
                "(%d seg x %d spans) --\n", pn, ps);
    sweepPhases(opts, "sweep.ph", "segments", pn, pn, ps,
                bench::Corner::RightCorner, bench::Spine::Polyline, true, 1.0e-2,
                "the v23 pipeline, phase by phase");

    /* And the same breakdown across the segment ladder, because a phase that
     * is 1 % at one size can be 40 % at another. */
    for (int n : opts.sweep_sizes) {
        if (n == pn || n > opts.sweep_legacy_max)
            continue; /* the phase breakdown IS the v23 pipeline — same cap */
        sweepPhases(opts, "sweep.ph", "segments", n, n, ps,
                    bench::Corner::RightCorner, bench::Spine::Polyline, true,
                    1.0e-2, "the v23 pipeline, phase by phase");
    }

    /* The replica against the original, on the same fixture, in the same run.
     * Read the phase table only if this ratio is near 1. */
    {
        double shim_ms = -1.0, rep_ms = -1.0;
        for (const Measured &m : g_results) {
            if (m.op == "sweep.legacy" && m.axis == "segments" &&
                m.x == pn && m.ok)
                shim_ms = m.t.mean;
            if (m.op == "sweep.ph.total" && m.axis == "segments" &&
                m.x == pn && m.ok)
                rep_ms = m.t.mean;
        }
        if (shim_ms > 0.0 && rep_ms > 0.0)
            std::printf("\n  replica check: shim (POLY) %.2f ms vs replica "
                        "%.2f ms  "
                        "ratio %.3f  (read the phase table only if this is "
                        "near 1)\n",
                        shim_ms, rep_ms, rep_ms / shim_ms);
        else
            std::printf("\n  replica check: NOT AVAILABLE at %d seg x %d spans "
                        "(one of the two did not build)\n", pn, ps);
    }

    /* The variants. What removes the cost, and what it does to the shape. */
    std::printf("\n  -- sweep.var.* : the levers, at %d seg x %d spans --\n",
                pn, ps);
    double ref = 0.0;
    {
        const bench::SweepPhases r = bench::sweepReplica(
            pn, ps, bench::Corner::RightCorner, bench::Spine::Polyline, true,
            1.0e-2);
        ref = r.ok ? r.volume : 0.0;
        std::printf("  reference volume %.6f (%s)\n", ref,
                    r.ok ? "v23 pipeline" : "v23 pipeline FAILED");
    }
    sweepVariant(opts, "v23poly", pn, ps, bench::Corner::RightCorner,
                 bench::Spine::Polyline, true, 1.0e-2, ref,
                 "RightCorner, polyline spine, UnifySameDomain — the v23 "
                 "pipeline, which is what OCCT_SWEEP_PATH_POLY still selects");
    sweepVariant(opts, "noUnify", pn, ps, bench::Corner::RightCorner,
                 bench::Spine::Polyline, false, 1.0e-2, ref,
                 "the v23 pipeline WITHOUT the closing UnifySameDomain");
    sweepVariant(opts, "transformed", pn, ps, bench::Corner::Transformed,
                 bench::Spine::Polyline, true, 1.0e-2, ref,
                 "BRepBuilderAPI_Transformed — no corner trimming at all");
    sweepVariant(opts, "deadband", pn, ps, bench::Corner::RightCorner,
                 bench::Spine::Polyline, true, 5.0 * M_PI / 180.0, ref,
                 "RightCorner with OCCT's own angmin deadband raised to 5 deg, "
                 "so shallow joints are not treated as corners");
    sweepVariant(opts, "smoothSpine", pn, ps, bench::Corner::RightCorner,
                 bench::Spine::Smooth, true, 1.0e-2, ref,
                 "a C2 B-spline interpolated through the same path points — "
                 "one spine edge, so no joints to treat");
}

/* ------------------------------------------------------------------------ */
/* S18 — the DRAWN corner                                                     */
/* ------------------------------------------------------------------------ */
/*
 * Lane C had no corner axis: sweep.segments, sweep.legacy and sweep.spans all
 * vary the SAMPLED arc, which v24 made cheap. A joint somebody drew is what is
 * left, and this is its ladder.
 *
 * Two things are measured here and they are not the same thing:
 *   - correctness: the two closed forms of S18-corners.md 1.1 against the
 *     kernel, on the analytic square fixture. These are pins, not timings; a
 *     disagreement is a refuted derivation.
 *   - cost: an N-segment ring over a 3-corner drawn path, which is the shape
 *     of the device's 79-second rung.
 */

static void cornerRow(const char *tag, double thetaDeg,
                      const std::vector<double> &legs,
                      const std::vector<double> &turn, double w)
{
    const double wantM = bench::cornerMiterVolume(legs, turn, w);
    const double wantT = bench::cornerTransformedVolume(legs, turn, w);
    const bench::CornerRun m =
        bench::cornerReplica(legs, turn, w, bench::Corner::RightCorner, 1.0e-2);
    const bench::CornerRun t =
        bench::cornerReplica(legs, turn, w, bench::Corner::Transformed, 1.0e-2);
    auto rel = [](double got, double want) {
        const double d = std::fabs(want) > 1e-12 ? std::fabs(want) : 1.0;
        return (got - want) / d;
    };
    std::printf("  %-10s th=%9.4f | mitre %13.6f (I) %13.6f %+9.2e %-7s"
                " | trans %13.6f (II) %13.6f %+9.2e %-7s\n",
                tag, thetaDeg, m.ok ? m.volume : 0.0, wantM,
                m.ok ? rel(m.volume, wantM) : 0.0,
                m.ok ? (m.valid ? "valid" : "INVALID") : "FAILED",
                t.ok ? t.volume : 0.0, wantT,
                t.ok ? rel(t.volume, wantT) : 0.0,
                t.ok ? (t.valid ? "valid" : "INVALID") : "FAILED");
    std::fflush(stdout);
}

static void runCornerLadders(const RunOpts &opts)
{
    if (!opts.sweep)
        return;

    const double w = 10.0;
    const double A = bench::cornerSectionArea(w);
    const double ct = bench::cornerSectionTurnOffset(w);

    std::printf("\n[drawn corner] fixture: smoke [30]'s %gx%g square on an "
                "L path, joint angle as the axis\n", w, w);
    std::printf("  A = %g, centroid offset along the turn c_t = %g\n", A, ct);

    /* P1 + P2 — the two closed forms against the kernel. */
    std::printf("\n  -- corner.closedform : (I) A*L - 2*A*c_t*tan(t/2) and "
                "(II) A*L1 + A*L2*cos t --\n");
    const std::vector<double> legs{40.0, 30.0};
    for (double th : {0.5, 2.0, 5.625, 15.0, 19.4712206, 45.0, 90.0})
        cornerRow("L(40,30)", th, legs, std::vector<double>{th}, w);

    /* P3 — is Transformed's error the corner, or a fraction of it that shrinks?
     * The denominator is the corner's own first-order effect A*c_t*theta. */
    std::printf("\n  -- corner.errshare : |V_trans - V_mitre| as a fraction of "
                "the corner's own effect A*c_t*theta --\n");
    std::printf("  (OCCT's own angmin deadband is 1.0e-2 rad = %.4f deg; "
                "below it RightCorner does not mitre either)\n",
                1.0e-2 * 180.0 / M_PI);
    for (double th : {0.4, 0.5, 0.6, 1.0, 2.0, 5.625, 15.0}) {
        const std::vector<double> turn{th};
        const bench::CornerRun m = bench::cornerReplica(
            legs, turn, w, bench::Corner::RightCorner, 1.0e-2);
        const bench::CornerRun t = bench::cornerReplica(
            legs, turn, w, bench::Corner::Transformed, 1.0e-2);
        if (!m.ok || !t.ok) {
            std::printf("  th=%8.4f  one of the two did not build\n", th);
            continue;
        }
        const double wedge = A * ct * th * M_PI / 180.0;
        std::printf("  th=%8.4f  V_trans-V_mitre=%+12.6f  A*c_t*th=%11.6f  "
                    "share=%6.3f  %-8s %s / %s\n",
                    th, t.volume - m.volume, wedge,
                    std::fabs(t.volume - m.volume) / wedge,
                    th * M_PI / 180.0 > 1.0e-2 ? "mitred" : "DEADBAND",
                    m.valid ? "valid" : "INVALID",
                    t.valid ? "valid" : "INVALID");
        std::fflush(stdout);
    }

    /* P4 — the crossover, bisected on the MEASURED difference, at three second
     * leg lengths. (III) says asin(2*c_t/L2) and contains nothing about the
     * corner treatment. */
    std::printf("\n  -- corner.crossover : where V_trans - V_mitre changes "
                "sign, measured, against asin(2*c_t/L2) --\n");
    for (double L2 : {15.0, 30.0, 60.0}) {
        const double want = std::asin(2.0 * ct / L2) * 180.0 / M_PI;
        const double got =
            bench::cornerCrossoverDeg(40.0, L2, w, 1.0, 89.0, 0.001, 1.0e-2);
        if (got < 0.0)
            std::printf("  L2=%5.1f  predicted %8.4f deg  measured: no sign "
                        "change bracketed in [0.25, 89]\n", L2, want);
        else
            std::printf("  L2=%5.1f  predicted %8.4f deg  measured %8.4f deg  "
                        "delta %+.4f deg\n", L2, want, got, got - want);
        std::fflush(stdout);
    }

    /* P5 — two joints, same sense. Does Transformed's tilt compound? */
    std::printf("\n  -- corner.staircase : 3 legs, 2 joints of 15 deg, the "
                "same way --\n");
    {
        const std::vector<double> l3{40.0, 30.0, 30.0};
        const std::vector<double> t3{15.0, 15.0};
        const double th = 15.0 * M_PI / 180.0;
        const double compounding =
            A * (40.0 + 30.0 * std::cos(th) + 30.0 * std::cos(2.0 * th));
        const double perJoint =
            A * (40.0 + 30.0 * std::cos(th) + 30.0 * std::cos(th));
        const bench::CornerRun m =
            bench::cornerReplica(l3, t3, w, bench::Corner::RightCorner, 1.0e-2);
        const bench::CornerRun t =
            bench::cornerReplica(l3, t3, w, bench::Corner::Transformed, 1.0e-2);
        std::printf("  mitre       %14.6f  (I) %14.6f  %s\n",
                    m.ok ? m.volume : 0.0,
                    bench::cornerMiterVolume(l3, t3, w),
                    m.ok ? (m.valid ? "valid" : "INVALID") : "FAILED");
        std::printf("  transformed %14.6f  compounding %14.6f  per-joint "
                    "%14.6f  %s\n",
                    t.ok ? t.volume : 0.0, compounding, perJoint,
                    t.ok ? (t.valid ? "valid" : "INVALID") : "FAILED");
        std::fflush(stdout);
    }

    /* P6 — S14 2.8's identity. A ring CENTRED on the spine has c_t = 0, so by
     * (I) the mitre has no wedge at any span count and the volume should be the
     * section's area times the path's RISE. Both candidate forms are printed
     * against the measurement rather than one of them being asserted. */
    std::printf("\n  -- corner.cavalieri : S14 2.8's identity, A*dz against "
                "A*L_poly*cos(tilt) --\n");
    {
        const int n = 128;
        const double R = 6.0;
        const double Aring = 0.5 * n * R * R * std::sin(2.0 * M_PI / n);
        /* The helix rises 60 over an arc length of 66.328259, and its pitch
         * angle is constant, so cos(tilt) = 60/66.328259 exactly. */
        const double cosTilt = 60.0 / 66.328259;
        for (int spans : {2, 4, 16}) {
            const bench::SweepPhases r =
                bench::sweepReplica(n, spans, bench::Corner::RightCorner,
                                    bench::Spine::Polyline, true, 1.0e-2);
            const std::vector<double> p = bench::arcPathXYZ(spans + 1, 60.0);
            double lpoly = 0.0;
            for (int i = 0; i < spans; ++i) {
                const double dx = p[3 * (i + 1)] - p[3 * i];
                const double dy = p[3 * (i + 1) + 1] - p[3 * i + 1];
                const double dz = p[3 * (i + 1) + 2] - p[3 * i + 2];
                lpoly += std::sqrt(dx * dx + dy * dy + dz * dz);
            }
            const double dz = p[3 * spans + 2] - p[2];
            const double vdz = Aring * dz;
            const double vlp = Aring * lpoly * cosTilt;
            std::printf("  spans=%-3d measured %14.6f | A*dz %14.6f %+9.2e | "
                        "A*L_poly*cos %14.6f %+9.2e | L_poly %.6f\n",
                        spans, r.ok ? r.volume : 0.0, vdz,
                        r.ok ? (r.volume - vdz) / vdz : 0.0, vlp,
                        r.ok ? (r.volume - vlp) / vlp : 0.0, lpoly);
            std::fflush(stdout);
        }
    }

    /* The COST ladder — the thing the bar is about. An N-segment ring over a
     * path with three drawn 90-degree corners, which is the shape of the
     * device's 512-segment / 79-second rung. */
    std::printf("\n  -- sweep.corners : an N-segment ring over a path with 3 "
                "DRAWN 90 deg corners --\n");
    for (int n : opts.sweep_sizes) {
        const std::vector<double> l4{30.0, 25.0, 25.0, 30.0};
        /* ALTERNATING turns. Three 90 deg turns the same way close a rectangle
         * and the tube runs back through its own first leg — a self-crossing
         * fixture whose volume GProp double-counts and whose invalidity
         * BRepCheck_Analyzer does not look for. A staircase does not fold. */
        const std::vector<double> t4{90.0, -90.0, 90.0};
        std::vector<double> total;
        bench::CornerRun last;
        double spent = 0.0;
        for (int i = 0; i < opts.reps; ++i) {
            last = bench::cornerReplica(l4, t4, 6.0,
                                        bench::Corner::RightCorner, 1.0e-2, n);
            total.push_back(last.ms);
            spent += last.ms;
            if (!last.ok || (spent > opts.budget_ms && i >= 1))
                break;
        }
        Measured m;
        m.op = "sweep.corners";
        m.axis = "segments";
        m.x = n;
        m.ok = last.ok;
        m.t = bench::summarise(total);
        m.faces = last.faces;
        m.profile_pts = n;
        m.rss_peak_mb = peakRssMb();
        char buf[400];
        if (!last.ok) {
            std::snprintf(buf, sizeof buf,
                          "3 drawn 90 deg corners - FAILED after %.1f ms: %s",
                          last.ms, last.err.c_str());
            std::printf("  %-22s x=%-10d  *** FAILED *** after %.1f ms : %s\n",
                        m.op.c_str(), n, last.ms, last.err.c_str());
            std::fflush(stdout);
            m.note = buf;
            g_results.push_back(std::move(m));
            continue;
        }
        std::snprintf(buf, sizeof buf,
                      "3 drawn 90 deg corners - %d faces, spine edges %d, "
                      "volume %.6f, %s",
                      last.faces, last.spineEdges, last.volume,
                      last.valid ? "valid" : "INVALID");
        record(std::move(m), buf);
    }
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
        if (m.op == op && m.axis == axis && m.t.n > 0 && m.ok)
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

/* Notes reach the JSON now (they carry the failure reason, which is the only
 * place a failed rung says WHY). They are written by this program, but they
 * quote occt_last_error(), so they are escaped rather than trusted. */
static std::string jsonEscape(const std::string &in)
{
    std::string out;
    out.reserve(in.size() + 8);
    for (const char c : in) {
        switch (c) {
        case '"': out += "\\\""; break;
        case '\\': out += "\\\\"; break;
        case '\n': out += "\\n"; break;
        case '\r': out += "\\r"; break;
        case '\t': out += "\\t"; break;
        default:
            if (static_cast<unsigned char>(c) < 0x20) {
                char buf[8];
                std::snprintf(buf, sizeof buf, "\\u%04x", c);
                out += buf;
            } else {
                out += c;
            }
        }
    }
    return out;
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
    /* kernel-bench/2 adds "ok" to every measurement. A row with ok=false is a
     * FAILURE whose mean_ms is a time-to-failure; reading it as a cost would
     * rank the sweep's broken 1200-segment rung as its fastest large one. The
     * schema is bumped rather than extended in place so no reader can miss
     * that distinction. */
    std::fprintf(f, "  \"schema\": \"kernel-bench/2\",\n");
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
                     "\"ok\": %s, \"note\": \"%s\", "
                     "\"profilePts\": %d, \"edges\": %d, \"faces\": %d, "
                     "\"n\": %d, \"inner\": %d, "
                     "\"mean_ms\": %.9f, \"sd_ms\": %.9f, "
                     "\"p50_ms\": %.9f, \"p95_ms\": %.9f, \"min_ms\": %.9f, "
                     "\"max_ms\": %.9f, \"cv\": %.6f, "
                     "\"alloc_available\": %s, \"alloc_calls\": %.1f, "
                     "\"alloc_bytes\": %.1f, \"live_bytes\": %.1f, "
                     "\"rss_peak_mb\": %.3f, \"rss_delta_mb\": %.3f}%s\n",
                     m.op.c_str(), m.axis.c_str(), m.x,
                     m.ok ? "true" : "false", jsonEscape(m.note).c_str(),
                     m.profile_pts, m.edges,
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
        const std::string op = m.ok ? "`" + m.op + "`"
                                    : "`" + m.op + "` **FAILED**";
        if (m.alloc_ok)
            std::fprintf(f,
                         "| %s | %s | %.4g | %d | %d | %d | %.5f | %.5f | "
                         "%.5f | %.1f %% | %.0f | %.0f | %+.0f | %.1f |\n",
                         op.c_str(), m.axis.c_str(), m.x, m.edges, m.t.n,
                         m.inner, m.t.mean, m.t.sd, m.t.p95, m.t.cv * 100.0,
                         m.alloc_calls, m.alloc_bytes, m.live_bytes,
                         m.rss_peak_mb);
        else
            std::fprintf(f,
                         "| %s | %s | %.4g | %d | %d | %d | %.5f | %.5f | "
                         "%.5f | %.1f %% | n/a | n/a | n/a | %.1f |\n",
                         op.c_str(), m.axis.c_str(), m.x, m.edges, m.t.n,
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
        "  --no-alloc        skip allocation accounting. It costs three atomic\n"
        "                    increments per malloc, and allEdges makes tens of\n"
        "                    millions of them — use this when comparing the\n"
        "                    RELATIVE cost of allocation-heavy against\n"
        "                    allocation-light operations\n"
        "  --quick           a fast shape-only run (sizes 60,120,240, reps 3)\n"
        "\n"
        "  --sweep-sizes A,B  profile-segment rungs for the sweep ladder\n"
        "                    (default 32,64,128; the device ran 32,128,512,\n"
        "                    1200 and the 1200 rung FAILED)\n"
        "  --sweep-spans A,B  path-span rungs for the sweep ladder\n"
        "                    (default 1,2,4,8,16)\n"
        "  --sweep-profile N  profile segments the spans ladder holds fixed\n"
        "                    (default 128; the device held 512)\n"
        "  --sweep-path N     path spans the segments ladder holds fixed\n"
        "                    (default 16, which is what the device used)\n"
        "  --sweep-legacy-max N  highest segment rung the v23 (POLY) arm is\n"
        "                    run at (default 128). v23 costs 447 s at 512 and\n"
        "                    FAILS at 1200 on the machine this was written on\n"
        "  --no-sweep         skip the sweep ladders entirely\n"
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

/* parseSizes refuses anything below 3, which is right for a profile-point
 * rung — a 2-gon is not a profile. It is exactly wrong for a span count: the
 * ONE-span rung, the path with no interior corner at all, is the rung the
 * whole spans ladder exists to compare against. */
static std::vector<int> parseSpans(const char *s)
{
    std::vector<int> out;
    const char *p = s;
    while (*p) {
        char *end = nullptr;
        const long v = std::strtol(p, &end, 10);
        if (end == p)
            break;
        if (v >= 1)
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
        else if (a == "--no-alloc")
            opts.no_alloc = true;
        else if (a == "--sweep-sizes")
            opts.sweep_sizes = parseSizes(next("--sweep-sizes"));
        else if (a == "--sweep-spans")
            opts.sweep_spans = parseSpans(next("--sweep-spans"));
        else if (a == "--sweep-profile")
            opts.sweep_fixed_segments = std::atoi(next("--sweep-profile"));
        else if (a == "--sweep-path")
            opts.sweep_fixed_spans = std::atoi(next("--sweep-path"));
        else if (a == "--sweep-legacy-max")
            opts.sweep_legacy_max = std::atoi(next("--sweep-legacy-max"));
        else if (a == "--no-sweep")
            opts.sweep = false;
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

    /*
     * The allocation counters are proved before they are used, never after — a
     * column of silent zeroes is the failure mode this guards against.
     *
     * They are not free. Every malloc gains three relaxed atomic increments,
     * and `allEdges` at the top rung makes them by the hundred million, so an
     * allocation-heavy operation is penalised relative to an allocation-light
     * one. It does NOT move an exponent — a constant cost per allocation, on a
     * quantity that grows with the same exponent as the time, is a change of
     * constant — but it does distort cost RATIOS between operations. Use
     * --no-alloc when the ratio is what you are reading.
     */
    if (opts.no_alloc)
        std::printf("alloc  : disabled (--no-alloc)\n");
    else {
        bench::allocSelfTest();
        std::printf("alloc  : %s\n", bench::allocCountingMechanism());
    }
    std::printf("rungs  :");
    for (int n : opts.sizes)
        std::printf(" %d", n);
    std::printf("  (profile points; edges are 3x)\n");
    std::printf("reps   : %d, budget %.0f ms per op per rung\n", opts.reps,
                opts.budget_ms);

    runLadder(opts);
    runFilletSweeps(opts);
    runSweepLadders(opts);
    runCornerLadders(opts);

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
    for (const char *op : {"build", "edgeInfo1", "allEdges", "allEdgesBulk",
                           "buildOnly", "counts", "bbox", "mesh", "fuse", "cut",
                           "rayHits", "filletEx1"}) {
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
    /* The sweep axes. `sweep.spans` is fitted for completeness only: a step
     * function is not a power law, and a k drawn through a 1-span rung with no
     * corners and a 16-span rung with fifteen describes nothing. Read the
     * rungs, not the exponent. */
    for (const char *op : {"sweep.segments", "sweep.legacy", "sweep.coil",
                           "sweep.corners",
                           "sweep.ph.build", "sweep.ph.unify",
                           "sweep.ph.total"}) {
        FitRow r;
        r.op = op;
        r.axis = "segments";
        r.fit = fitOp(op, "segments");
        if (r.fit.ok)
            fits.push_back(r);
    }
    {
        FitRow r;
        r.op = "sweep.spans";
        r.axis = "spans";
        r.fit = fitOp("sweep.spans", "spans");
        if (r.fit.ok)
            fits.push_back(r);
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
