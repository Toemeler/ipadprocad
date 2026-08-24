#ifndef BENCH_SWEEP_H
#define BENCH_SWEEP_H

/*
 * Lane C — the sweep's INTERNAL phase breakdown, and the variants that
 * decide where its cost lives.
 *
 * Why this file exists, and what it may be trusted for
 * ----------------------------------------------------
 * `occt_sweep_profile` is one C call. The device capture of 2026-08-24 says
 * that call costs 132 s at 512 profile segments over a 16-span path and FAILS
 * at 1200 segments, and no instrument anywhere can say which of its five
 * internal steps that is. This file rebuilds the shim's pipeline out of the
 * same OCCT classes so each step can be timed on its own, and so the two
 * levers that might remove the cost — the corner-transition treatment and the
 * shape of the spine — can be varied without editing the shipped shim.
 *
 * It is a REPLICA, and a replica is only worth what its agreement with the
 * original is worth. `sweep.replica` and `sweep.segments` measure the same
 * fixture through the two paths, and the benchmark prints their ratio; read
 * the phase table only if that ratio is near 1. That check is the point of
 * the pairing and it is reported whichever way it comes out.
 *
 * One deliberate difference from the shim, and it is the reason this exists:
 * BRepOffsetAPI_MakePipeShell is a thin wrapper over BRepFill_PipeShell whose
 * SetTransitionMode() hard-codes OCCT's `angmin` corner deadband at 1.0e-2 rad
 * (0.573 deg). The replica drives BRepFill_PipeShell directly so angmin is a
 * parameter. With Corner::RightCorner and angminRad = 1.0e-2 it is the shipped
 * pipeline; nothing else about it differs.
 */

#include <string>
#include <vector>

namespace bench {

/* How the pipe shell treats a joint between two spine segments. */
enum class Corner { RightCorner, Transformed, RoundCorner };

/* What the spine is. Polyline is what spine_from_points builds today; Smooth
 * interpolates a C2 B-spline through the same points, which has no joints at
 * all and therefore no corner treatment to pay for. */
enum class Spine { Polyline, Smooth };

struct SweepPhases {
    /* milliseconds; on failure the phases reached before it are still filled */
    double wire = 0.0;
    double spine = 0.0;
    double build = 0.0;
    double solid = 0.0;
    double unify = 0.0;
    double total = 0.0;
    bool ok = false;
    std::string err;
    /* only meaningful when ok */
    int faces = 0;
    int spineEdges = 0;
    double volume = 0.0;
    bool valid = false;
};

/* The device fixture, rebuilt in C++: frontend/lib/perf_scenarios_profile.dart
 * sweeps arcRing(segments, 6) along arcPath(spans + 1, 60). */
std::vector<double> arcRingXYB(int n, double r);
std::vector<double> arcPathXYZ(int n, double r);

/* Total turning of a polyline through those points, in degrees — the quantity
 * the spans ladder holds nearly constant while it varies the corner COUNT, and
 * therefore the one that separates "per corner" from "per degree turned". */
double pathTurnDeg(const std::vector<double> &xyz);
double pathMaxCornerDeg(const std::vector<double> &xyz);

SweepPhases sweepReplica(int segments, int spans, Corner corner, Spine spine,
                         bool unify, double angminRad);

} // namespace bench

#endif /* BENCH_SWEEP_H */
