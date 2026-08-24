#!/usr/bin/env python3
"""The regression gate.

Every number in PERFORMANCE_PROFILE.md is a snapshot. Nothing in the repository
currently *detects* a regression: the tooling can compare two bundles when a
human points it at both, and that is not a gate. This is the gate.

    ci/perf_gate.py --record <bundle.zip>          # write perf/baseline.json
    ci/perf_gate.py <bundle.zip>                   # compare, exit 1 if worse
    ci/perf_gate.py <bundle.zip> --baseline <path>

WHY THIS DOES NOT DO WHAT THE ORIGINAL PLAN SAID
------------------------------------------------
The measurement plan's gate item ("B4", the plan itself now retired — see
PERFORMANCE_PROFILE §15.5) specified "one entry per scenario with p50/p95, red
at >10 % worse". The measurements taken since show all three would misfire, so
each is replaced with the thing the data supports. Stated here rather than
buried, because a gate nobody trusts gets switched off:

1. **Not p50/p95.** Those come from a 128-sample ring buffer (`perf.dart:41`)
   while n/total/mean cover every observation. For a span that ran more than
   128 times the two describe different windows, and for the `rv.native.*`
   spans the percentiles are computed over synthesised copies of a mean
   (`bug_capture.dart:328`) and mean nothing at all. This gate uses n, total
   and mean, which are exact.

2. **Not a flat 10 %.** The suite measures its own noise floor every run
   (`quality.variance.*.spreadPct`). On the reference run that floor is 4 %
   for extrude but 29 % for solve and 200 % for splineEval — a 10 % gate
   would miss real extrude regressions and fire constantly on solve. The
   threshold is therefore read from the run itself, per family, and a span
   whose baseline mean is unresolved (SNR < 10, see PERFORMANCE_PROFILE §1.2)
   is not gated on at all.

3. **Not durations first.** PERFORMANCE_PROFILE §1.1: where a count and a
   duration answer the same question, the count is the stronger evidence —
   it is exact and invariant under a change of processor. So counters and
   gauges are gated *hard* (any change is a finding, zero false positives
   from noise) and durations are gated softly, against the measured floor.

THE ONE THING THAT MATTERS MOST
-------------------------------
Low Power Mode scales this app by 1.9253 [1.8979, 1.9531], and not uniformly:
1.62 for memory-bound work, 1.91 native, 2.27 Dart compute
(PERFORMANCE_PROFILE §3.5). Comparing a capped run against an uncapped
baseline would report a ~93 % regression in everything. The gate therefore
REFUSES to compare durations across clock states rather than silently
correcting them, and says so. Counters and gauges are still compared, because
they are clock-invariant — which is exactly why they are the primary tier.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from perf_report import load  # noqa: E402

SCHEMA = 1
DEFAULT_BASELINE = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "perf", "baseline.json")

# Exit codes. 2 is not a regression — it means the question could not be asked.
EXIT_OK, EXIT_REGRESSION, EXIT_REFUSED = 0, 1, 2

# A span must clear this to be gated on at all. Below it the quantization floor
# (1 µs, PERFORMANCE_PROFILE §1.2) is a large fraction of the value and a ratio
# between two such numbers is noise. 0.05 ms = 50 ticks.
MIN_GATED_MEAN_MS = 0.05

# At low n, a PERCENTAGE is the wrong instrument, and an ABSOLUTE floor is the
# right one.
#
# Round two's only regression was `constraints.add.coincident`, +23.6 %, over
# the 21 % family floor — and n was 1 on both sides. In absolute terms the
# whole finding was 0.2590 -> 0.3200 ms: **61 microseconds.** That is the scale
# of one context switch or one minor page fault, and at n = 1 there is no
# second observation to average it away.
#
# The first fix I wrote for this exempted every span with n < 3 from failing.
# `test_a_regression_in_one_scenario_survives_aggregation` immediately caught
# that it was wrong, and it was right to: that test injects a real 40 %
# regression into `kernel.allEdges.sweep.120::ffi.occt.allEdges`, which has
# n = 1 in the actual capture and a mean of 600 ms. Moving 240 ms is not a
# scheduling hiccup at any n. Exempting low n would have traded round two's
# false positive for a false negative on exactly the class of regression this
# gate exists to catch.
#
# So the rule is absolute, not statistical, and its size comes from the
# machine rather than from the data: below this, a single-observation
# difference is indistinguishable from the operating system looking away.
# 61 us fails it; 240 ms clears it by a factor of 480.
#
# Spans with enough observations keep the percentage floor alone — averaging
# is what n buys, and this rule stops applying once you have it.
MIN_GATED_DELTA_MS = 0.5
LOW_N = 3

# WHICH GAUGES MAY BE GATED HARD
#
# The hard tier treats a changed gauge as "the fixture changed size, so the
# durations are not measuring the same work". That is only true of gauges that
# record an exact property of a scripted fixture. Plenty of gauges are not that
# — some are measurements in disguise, some describe the open document, some
# are cumulative — and gating on those produces noise that gets the whole gate
# switched off.
#
# The exclusions below are not guesses; they were derived, not chosen. The two
# arms of the paired run (2026-08-18) executed IDENTICAL fixtures on the SAME
# build, so a gauge that differs between them cannot be describing fixture size.
# 125 differ. Classifying all 125 gives exactly the four rules below — 57
# fitted exponents, 48 cumulative counters, 9 native-drain worsts, 5 derived
# quality results, 4 open-document gauges — and leaves exactly two gateable:
# `stress.allEdges.maxSize` and `.edges`, which differ because the ladder
# genuinely did not reach as far. That is the regression this gate exists to
# catch, and gating the capped arm against the uncapped baseline reports those
# two and nothing else.
#
# The classes are pinned by test_measurements_disguised_as_gauges_are_not_gated;
# the bundles themselves are not in the repository, so that test names one real
# example from each class rather than re-deriving the census.
GAUGE_SKIP_PREFIXES = (
    "native.",              # thermal, footprint, uptime — machine state
    "quality.",             # derived results: the noise floor itself, frame
                            # budgets, cache speed-ups. Measurements, not sizes.
)
GAUGE_SKIP_SUFFIXES = (
    ".rssDeltaMB",          # GC scheduling, not allocation: the SAME 1024-entity
                            # analysis recorded +105 MB on one arm and +315 MB
                            # on the other (PERFORMANCE_PROFILE 5.5.2)
    ".rssMB",               # whole-process resident, depends on session history
    ".worstUs",             # published by the native drain, which resets it
                            # every capture (bug_capture.dart:338)
)
GAUGE_SKIP_CONTAINS = (
    ".k.",                  # `ramp.<family>.k.<size>` is a FITTED LOCAL
                            # EXPONENT x100 — a measurement with its own
                            # dispersion, not an input size. 57 of the 125.
    ".path.slvs.",          # cumulative solver-path counters, so they carry
    ".path.lm.",            # everything the session did before. 48 of the 125.
)
# The open document — what the person had on screen — rather than the suite's
# own fixtures. The suite runs the same scripted inputs regardless of these.
GAUGE_SKIP_EXACT = frozenset({
    "features", "solids", "triangles", "sceneTris", "sketchEntities",
    "sketchProjections", "part.features", "remeshCount",
})

# Ladder ceilings: falling is a regression, rising is an improvement.
GAUGE_HIGHER_IS_BETTER_SUFFIX = ".maxSize"

# Which measured noise floor applies to which span. The floor is read from the
# bundle (`quality.variance.<op>.spreadPct`), not hardcoded.
NOISE_FAMILY = (
    ("sketch.analyze", "analyze"),
    ("analysis.", "analyze"),
    ("solve.", "solve"),
    ("ffi.slvs.", "solve"),
    ("constraints.", "solve"),
    ("tools.spline", "splineEval"),
    ("ffi.occt.", "extrude"),
    ("kernel.", "extrude"),
    ("ramp.", "extrude"),
)
# Used where no family matches, and as a floor under every family: even a
# perfectly repeatable operation is not worth waking someone for below this.
FLOOR_PCT = 0.10


# --------------------------------------------------------------------------
# reading a bundle down to the things worth gating on

def _conditions(data: dict) -> dict:
    """The run's own description of itself. A comparison is only sound between
    two runs whose conditions agree, so they are recorded and checked."""
    snap = data["snapshot"]
    nat = snap.get("native") or {}
    suites = data["suites"]
    return {
        "build": (suites[0].get("build") if suites else None),
        "capturedAt": snap.get("at"),
        "lowPowerMode": bool(nat.get("preSuite.lowPowerMode")),
        "thermalPre": nat.get("preSuite.thermalState"),
        "thermalPost": nat.get("postSuite.thermalState"),
        "activeProcessorCount": nat.get("preSuite.activeProcessorCount"),
        "physicalMemoryMB": nat.get("preSuite.physicalMemoryMB"),
        "runners": sorted(s.get("suite", "?") for s in suites),
    }


def _ordered_scenarios(data: dict):
    """Scenarios in the order they actually executed.

    Order matters here in a way it does not for the other tools, and getting it
    wrong quietly breaks the gate — see the gauge reduction below. The three
    runners execute in sequence and each stamps its own `at`, so sorting the
    suites by that reproduces the true chronology.
    """
    for suite in sorted(data["suites"], key=lambda s: s.get("at") or ""):
        for s in suite.get("scenarios", []):
            yield s


def _scenario_scope(data: dict):
    """Spans, counters and gauges from SCENARIO scope — the measured pass only.

    Session scope is excluded on purpose: it includes the warm-up pass and
    whatever the person happened to do before pressing the button, so it is not
    reproducible between runs and cannot be gated on.

    The three reductions are NOT the same, because the three channels are not
    recorded the same way (`perf.dart:658-685`):

    * **spans** are per-scenario deltas (`count - before`), so they SUM;
    * **counters** are per-scenario deltas (`value - before`), so they SUM;
    * **gauges** are a full snapshot of the global map at each scenario's end
      (`Map.of(gauges)`), so they are LAST-WRITE-WINS in execution order.

    Reducing gauges with max() instead — the obvious-looking choice — is wrong
    twice over. The gauge map is not cleared between suite executions, so early
    scenarios carry values left over from a previous pass: in the reference
    bundle `quality.variance.extrude.spreadPct` reads 15 in the scenarios
    before `quality.variance` ran and 4 from there on, and max() would adopt
    the stale 15. Worse, on a ladder ceiling max() would take the HIGHER of a
    stale and a current `maxSize` and so hide exactly the regression this gate
    exists to catch.
    """
    spans, per_scenario, counters, gauges = {}, {}, {}, {}
    for s in _ordered_scenarios(data):
        scen = s.get("scenario") or "?"
        for name, v in (s.get("spans") or {}).items():
            n, tot = v.get("n", 0), v.get("totalMs", 0.0)
            e = spans.setdefault(name, {"n": 0, "totalMs": 0.0})
            e["n"] += n
            e["totalMs"] += tot
            if n:
                per_scenario[f"{scen}::{name}"] = {
                    "n": n, "meanMs": tot / n}
        for name, v in (s.get("counters") or {}).items():
            counters[name] = counters.get(name, 0) + int(v)
        for name, v in (s.get("gauges") or {}).items():
            if isinstance(v, bool) or not isinstance(v, (int, float)):
                continue
            gauges[name] = v          # last write wins — see the docstring
    for e in spans.values():
        e["meanMs"] = e["totalMs"] / e["n"] if e["n"] else 0.0
    return spans, per_scenario, counters, gauges


def _noise_floor(gauges: dict) -> dict:
    """The run's measured dispersion, as a fraction, from the final gauge state.

    Read per run because it is not a constant: the reference run gives
    4/29/24/200 % where the run of 11 Aug gave 3/18/17/67 %.
    """
    out = {}
    for k, v in gauges.items():
        if k.startswith("quality.variance.") and k.endswith(".spreadPct"):
            out[k[len("quality.variance."):-len(".spreadPct")]] = float(v) / 100
    return out


def _gateable_gauges(gauges: dict) -> dict:
    """Only the gauges that record an exact property of a scripted fixture.
    See the exclusion table above for why each class is dropped."""
    return {
        k: v for k, v in gauges.items()
        if not k.startswith(GAUGE_SKIP_PREFIXES)
        and not k.endswith(GAUGE_SKIP_SUFFIXES)
        and not any(frag in k for frag in GAUGE_SKIP_CONTAINS)
        and k not in GAUGE_SKIP_EXACT
    }


def extract(data: dict) -> dict:
    spans, per_scenario, counters, gauges = _scenario_scope(data)
    return {
        "schema": SCHEMA,
        "conditions": _conditions(data),
        "noiseFloor": _noise_floor(gauges),
        "counters": counters,
        "gauges": _gateable_gauges(gauges),
        "spans": {k: {"n": v["n"], "meanMs": round(v["meanMs"], 6)}
                  for k, v in sorted(spans.items())},
        # Per scenario as well as per span, because the aggregate DILUTES.
        # `ffi.occt.allEdges` runs inside ramps, stress ladders and the blend
        # pattern; a 40 % regression confined to one of them moves the
        # whole-app mean by 7 % and slips under any sane floor. This is the one
        # part of the plan's "one entry per scenario" that was right.
        # Entries below the resolution floor are dropped rather than stored:
        # they could never be gated on anyway (see MIN_GATED_MEAN_MS).
        "scenarioSpans": {
            k: {"n": v["n"], "meanMs": round(v["meanMs"], 6)}
            for k, v in sorted(per_scenario.items())
            if v["meanMs"] >= MIN_GATED_MEAN_MS},
    }


# --------------------------------------------------------------------------
# comparison

def threshold_for(span: str, floors: dict) -> float:
    for prefix, op in NOISE_FAMILY:
        if span.startswith(prefix):
            return max(floors.get(op, 0.0), FLOOR_PCT)
    return max(max(floors.values()) if floors else 0.0, FLOOR_PCT)


class Findings:
    def __init__(self) -> None:
        self.fail: list[str] = []
        self.note: list[str] = []
        self.skipped: list[str] = []
        # Over the percentage floor, but too small in absolute terms to tell
        # from the scheduler at this n. Reported, never fatal.
        self.unresolved: list[str] = []


def compare(new: dict, base: dict, allow_clock_mismatch: bool = False
            ) -> tuple[Findings, bool]:
    """Returns the findings and whether durations were actually compared."""
    f = Findings()
    nc, bc = new["conditions"], base["conditions"]

    # --- tier 0: is the comparison sound at all? --------------------------
    if nc["thermalPre"] != "nominal" or nc["thermalPost"] != "nominal":
        f.note.append(
            f"thermal state was {nc['thermalPre']} -> {nc['thermalPost']}, not "
            f"nominal at both ends: this run was throttled and its durations "
            f"describe a machine nobody has")

    clock_matches = nc["lowPowerMode"] == bc["lowPowerMode"]
    gate_durations = clock_matches or allow_clock_mismatch
    if not clock_matches:
        msg = (f"Low Power Mode differs: baseline {bc['lowPowerMode']}, "
               f"this run {nc['lowPowerMode']}. Durations are NOT comparable "
               f"(the cap scales this app by ~1.93x, and not uniformly across "
               f"subsystems — PERFORMANCE_PROFILE 3.5).")
        if allow_clock_mismatch:
            f.note.append(msg + " Compared anyway on request; read with care.")
        else:
            f.skipped.append(msg + " Counters and gauges are still checked, "
                             "because those are clock-invariant.")

    # --- tier 1: counters. Exact, processor-invariant, zero noise. --------
    for k in sorted(set(new["counters"]) | set(base["counters"])):
        nv, bv = new["counters"].get(k), base["counters"].get(k)
        if bv is None:
            f.note.append(f"new counter   {k} = {nv}")
        elif nv is None:
            f.note.append(f"counter gone  {k} (was {bv})")
        elif nv != bv:
            f.fail.append(
                f"COUNTER  {k}: {bv} -> {nv}  "
                f"({'+' if nv > bv else ''}{nv - bv}) — the amount of work "
                f"changed, not merely its speed")

    # --- tier 2: gauges. Exact input sizes and ladder ceilings. -----------
    for k in sorted(set(new["gauges"]) | set(base["gauges"])):
        nv, bv = new["gauges"].get(k), base["gauges"].get(k)
        if bv is None:
            f.note.append(f"new gauge     {k} = {nv}")
        elif nv is None:
            f.note.append(f"gauge gone    {k} (was {bv})")
        elif nv == bv:
            continue
        elif k.endswith(GAUGE_HIGHER_IS_BETTER_SUFFIX):
            if nv < bv:
                f.fail.append(
                    f"CEILING  {k}: {bv} -> {nv} — the ladder does not reach "
                    f"as far as it did")
            else:
                f.note.append(f"ceiling up    {k}: {bv} -> {nv} (improvement)")
        else:
            f.fail.append(
                f"GAUGE    {k}: {bv} -> {nv} — the fixture changed size, so "
                f"the durations below are not measuring the same work")

    # --- tier 3: durations, against the measured floor -------------------
    if gate_durations:
        floors = dict(base.get("noiseFloor") or {})
        for op, v in (new.get("noiseFloor") or {}).items():
            floors[op] = max(floors.get(op, 0.0), v)   # the noisier of the two

        def durations(key: str, label: str) -> None:
            nb, nn = base.get(key) or {}, new.get(key) or {}
            for k in sorted(set(nb) & set(nn)):
                bs, ns = nb[k], nn[k]
                if bs["meanMs"] < MIN_GATED_MEAN_MS:
                    continue                 # unresolved; see the docstring
                if bs["n"] != ns["n"]:
                    f.fail.append(
                        f"CALLS    {label}{k}: n {bs['n']} -> {ns['n']} — "
                        f"called a different number of times, so the means "
                        f"are not comparable")
                    continue
                if bs["meanMs"] <= 0:
                    continue
                delta = (ns["meanMs"] - bs["meanMs"]) / bs["meanMs"]
                # The span name is what carries the family, whichever level
                # this is: "scenario::span" ends with the span.
                thr = threshold_for(k.split("::")[-1], floors)
                if delta > thr:
                    absMs = ns["meanMs"] - bs["meanMs"]
                    line = (f"{label}{k}: {bs['meanMs']:.4f} -> "
                            f"{ns['meanMs']:.4f} ms "
                            f"({delta * 100:+.1f}%, floor {thr * 100:.0f}%)")
                    # n is equal on both sides here — the CALLS check above
                    # returned on any span where it is not.
                    if ns["n"] < LOW_N and absMs < MIN_GATED_DELTA_MS:
                        f.unresolved.append(
                            f"n={ns['n']}  +{absMs * 1000:.0f} us  {line}")
                    else:
                        f.fail.append(f"SLOWER   {line}")
                elif delta < -thr:
                    f.note.append(
                        f"faster        {label}{k}: {bs['meanMs']:.4f} -> "
                        f"{ns['meanMs']:.4f} ms ({delta * 100:+.1f}%)")

        durations("scenarioSpans", "")
        durations("spans", "[all] ")
        missing = sorted(set(base["spans"]) - set(new["spans"]))
        if missing:
            f.note.append(
                f"{len(missing)} baseline spans absent from this run "
                f"(a tier not requested?): {', '.join(missing[:6])}"
                f"{' …' if len(missing) > 6 else ''}")
    return f, gate_durations


# --------------------------------------------------------------------------

def render(f: Findings, new: dict, base: dict, gated: bool) -> list[str]:
    nc, bc = new["conditions"], base["conditions"]
    out = [
        "=" * 78,
        "PERF GATE",
        "=" * 78,
        f"  baseline : build {bc['build']}  {bc['capturedAt']}  "
        f"lowPowerMode={bc['lowPowerMode']}",
        f"  this run : build {nc['build']}  {nc['capturedAt']}  "
        f"lowPowerMode={nc['lowPowerMode']}",
        f"  durations: {'compared' if gated else 'NOT COMPARED'}",
        "",
    ]
    if f.skipped:
        out.append("WHAT WAS NOT ASKED")
        out += [f"  - {s}" for s in f.skipped]
        out.append("")
    if f.fail:
        out.append(f"REGRESSIONS ({len(f.fail)})")
        out += [f"  {s}" for s in f.fail]
        out.append("")
    else:
        out.append("No regression against the baseline.")
        out.append("")
    if f.unresolved:
        out.append(f"UNRESOLVED ({len(f.unresolved)}) — over the floor in "
                   f"percent, under it in microseconds")
        out.append(f"  At n < {LOW_N} a difference below "
                   f"{MIN_GATED_DELTA_MS * 1000:.0f} us is not "
                   f"distinguishable from the scheduler.")
        out.append("  These are NOT failures and NOT clean bills of health.")
        out += [f"  {s}" for s in f.unresolved]
        out.append("")
    if f.note:
        out.append(f"NOTES ({len(f.note)}) — not failures")
        out += [f"  {s}" for s in f.note[:40]]
        if len(f.note) > 40:
            out.append(f"  … and {len(f.note) - 40} more")
    return out


def record(bundle: str, out_path: str) -> int:
    data = load(bundle)
    b = extract(data)
    b["source"] = os.path.basename(bundle)
    b["note"] = (
        "Recorded by ci/perf_gate.py --record. Scenario scope only (the "
        "measured pass); session scope is excluded because it depends on what "
        "the person did before pressing the button. Re-record deliberately, "
        "never to silence a failure you have not explained.")
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w") as fh:
        json.dump(b, fh, indent=2, sort_keys=True)
        fh.write("\n")
    c = b["conditions"]
    print(f"wrote {out_path}")
    print(f"  build {c['build']}  {c['capturedAt']}")
    print(f"  lowPowerMode={c['lowPowerMode']}  thermal "
          f"{c['thermalPre']}->{c['thermalPost']}")
    print(f"  runners: {', '.join(c['runners'])}")
    print(f"  {len(b['spans'])} spans, "
          f"{len(b['scenarioSpans'])} scenario-spans, "
          f"{len(b['counters'])} counters, {len(b['gauges'])} gauges")
    print(f"  noise floor: " + ", ".join(
        f"{k} {v * 100:.0f}%" for k, v in sorted(b["noiseFloor"].items())))
    return EXIT_OK


def main_for_test(bundle: str, baseline: str, allow_clock_mismatch: bool = False
                  ) -> tuple[int, str]:
    if not os.path.exists(baseline):
        return EXIT_REFUSED, (
            f"no baseline at {baseline} — record one with "
            f"ci/perf_gate.py --record <bundle.zip>")
    with open(baseline) as fh:
        base = json.load(fh)
    if base.get("schema") != SCHEMA:
        return EXIT_REFUSED, (
            f"baseline schema {base.get('schema')} != {SCHEMA}; re-record it")
    new = extract(load(bundle))
    f, gated = compare(new, base, allow_clock_mismatch)
    text = "\n".join(render(f, new, base, gated))
    return (EXIT_REGRESSION if f.fail else EXIT_OK), text


def main() -> int:  # pragma: no cover - argv plumbing
    ap = argparse.ArgumentParser(description="perf regression gate")
    ap.add_argument("bundle", help="bug-report zip to check")
    ap.add_argument("--record", action="store_true",
                    help="write this bundle as the baseline instead")
    ap.add_argument("--baseline", default=DEFAULT_BASELINE)
    ap.add_argument("--allow-clock-mismatch", action="store_true",
                    help="compare durations even across Low Power Mode states "
                         "(they are not comparable; see the module docstring)")
    a = ap.parse_args()
    if not os.path.exists(a.bundle):
        print(f"no such bundle: {a.bundle}", file=sys.stderr)
        return EXIT_REFUSED
    if a.record:
        return record(a.bundle, a.baseline)
    code, text = main_for_test(a.bundle, a.baseline, a.allow_clock_mismatch)
    print(text)
    return code


if __name__ == "__main__":  # pragma: no cover
    try:
        sys.exit(main())
    except BrokenPipeError:
        sys.exit(0)
