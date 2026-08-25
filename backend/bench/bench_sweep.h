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

/* ---- S18: the DRAWN corner -------------------------------------------------
 *
 * Everything above sweeps a ring along a SAMPLED arc, which is the fixture the
 * device capture uses and the one v24 made cheap. A joint somebody DREW is a
 * different fixture and S14 never gave it a ladder: it is smoke scenario [30]'s
 * L-path — a 10x10 square, up then across — and its joint angle is the axis
 * that matters.
 *
 * `cornerReplica` builds exactly that, with the joint angle, the leg lengths
 * and the number of joints as parameters, through the same BRepFill_PipeShell
 * the rest of this file drives. RightCorner + angminRad = 1e-2 is the shipped
 * shim; BRepFill_Modified is the lever S14 measured at 17.5x and did not pull.
 *
 * The two closed forms below are DERIVED in perf/findings/S18-corners.md §1.1
 * from OCCT's own two transform functions, not fitted to a measurement. They
 * are what the replica is checked against, so a run that disagrees with them
 * is a result and not a tolerance to widen. */

/* The square section every corner fixture uses: [0,w] x [0,w] in the z = 0
 * plane, so area = w*w and the centroid's offset ALONG THE TURN is w/2. */
double cornerSectionArea(double w);
double cornerSectionTurnOffset(double w);

struct CornerRun {
    double ms = 0.0;
    bool ok = false;
    std::string err;
    /* only meaningful when ok */
    int faces = 0;
    int spineEdges = 0;
    double volume = 0.0;
    bool valid = false;
};

/* legs[i] is the i-th straight run; turnDeg[i] the joint between legs i and
 * i+1, so turnDeg is one shorter than legs. Every turn is in the XZ plane and
 * in the same sense, which is what makes the compounding of P5 visible. */
/* ringSegments <= 0 selects the analytic square section above. A positive
 * value sweeps arcRing(ringSegments, w) instead — a regular polygon CENTRED on
 * the spine, which has c_t = 0 and therefore no mitre wedge at all, and is
 * there for the COST ladder rather than for the closed forms. */
CornerRun cornerReplica(const std::vector<double> &legs,
                        const std::vector<double> &turnDeg, double w,
                        Corner corner, double angminRad,
                        int ringSegments = 0);

/* (I): A*sum(legs) - 2*A*c_t*sum(tan(theta_i/2)) — the mitre, which cuts each
 * joint at its bisector plane. */
double cornerMiterVolume(const std::vector<double> &legs,
                         const std::vector<double> &turnDeg, double w);

/* (II): A*sum(legs[i]*cos(phi_i)) with phi_i the ACCUMULATED turn before leg i
 * — Transformed, which never reorients the section at all, so leg i is an
 * oblique prism tilted by everything the path has turned so far. */
double cornerTransformedVolume(const std::vector<double> &legs,
                               const std::vector<double> &turnDeg, double w);

/* The joint angle at which the two closed forms cross, by bisection on the
 * MEASURED volumes rather than on the formulae — so that (III)'s
 * asin(2*c_t/L2) is checked against the kernel and not against itself.
 * Returns a negative number if no sign change was bracketed. */
double cornerCrossoverDeg(double L1, double L2, double w, double loDeg,
                          double hiDeg, double tolDeg, double angminRad);

} // namespace bench

#endif /* BENCH_SWEEP_H */
