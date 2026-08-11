#!/usr/bin/env python3
"""Turn a perf bundle into ranked findings.

WHY THIS EXISTS
---------------
The self-driving suite now emits ~73 scenarios, each with a span table, a
counter table and a gauge table. That is the right amount of data and the wrong
amount of reading: every device run so far has been analysed by hand-writing a
throwaway script to answer the same four questions. This is that script, kept.

WHAT IT ANSWERS, in the order the answers matter
------------------------------------------------
1. DID THE MEASUREMENT MEAN ANYTHING? Failure counters, null-result counters,
   and the thermal state at both ends of the run. A suite that ran while the
   iPad was throttling produces real numbers about a machine nobody has —
   that has to be the first thing on the page, not a footnote.
2. WHAT IS THE SHAPE OF EACH COST CURVE? Every sweep family (scenarios named
   `foo.8` / `foo.24` / `foo.64`) is fitted to n^k from its own gauges. The
   exponent is the property that survives a change of chip; the milliseconds
   are not.
3. WHERE DID THE TIME GO? Total, ranked, with each span's share.
4. WHAT CHANGED? Against a baseline, if one is given.

USAGE
    ci/perf_report.py <bundle.zip | directory | perf_suite.json> [...]
    ci/perf_report.py <new-bundle> --baseline <old-bundle>

Reads a bug bundle zip directly, so the file the device produces is the file
this takes. No dependencies outside the standard library — this has to run on
whatever is at hand.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
import zipfile

# Members a bundle may carry. Missing ones are skipped, never fatal: a bundle
# from an older build is still worth reading.
SUITE_MEMBERS = ("perf_suite.json", "perf_suite_ui.json",
                 "perf_suite_stress.json")
SNAPSHOT_MEMBER = "perf_snapshot.json"

# Counter suffixes that mean "this scenario did not measure its subject".
# See PERF_ANALYSIS.md sections 8 and 10.4 — a null result is a fast zero, and
# a fast zero is indistinguishable from a fast operation in a timing report.
DEAD_SUFFIXES = (".fail", ".throw", ".null", ".tooFewEdges")

THERMAL_NAMES = {0: "nominal", 1: "fair", 2: "serious", 3: "critical"}


# ---------------------------------------------------------------------------
# loading
# ---------------------------------------------------------------------------

def load(path: str) -> dict:
    """Returns {'suites': [...], 'snapshot': {...}, 'label': str}."""
    out = {"suites": [], "snapshot": {}, "label": os.path.basename(path.rstrip("/"))}
    if path.endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            names = set(z.namelist())
            for m in SUITE_MEMBERS:
                if m in names:
                    out["suites"].append(_json(z.read(m)))
            if SNAPSHOT_MEMBER in names:
                out["snapshot"] = _json(z.read(SNAPSHOT_MEMBER)) or {}
    elif os.path.isdir(path):
        for m in SUITE_MEMBERS:
            p = os.path.join(path, m)
            if os.path.exists(p):
                out["suites"].append(_json(open(p, "rb").read()))
        p = os.path.join(path, SNAPSHOT_MEMBER)
        if os.path.exists(p):
            out["snapshot"] = _json(open(p, "rb").read()) or {}
    else:
        out["suites"].append(_json(open(path, "rb").read()))
    out["suites"] = [s for s in out["suites"] if s]
    return out


def _json(raw: bytes):
    """A suite that failed is stored as a plain error STRING, not JSON. That is
    deliberate on the app side (the bundle keeps the reason), so tolerate it
    here rather than crashing on the one bundle that most needs reading."""
    try:
        v = json.loads(raw)
        return v if isinstance(v, dict) else None
    except Exception:
        return None


def scenarios(data: dict):
    for suite in data["suites"]:
        for s in suite.get("scenarios", []):
            yield s


# ---------------------------------------------------------------------------
# 1. did the measurement mean anything?
# ---------------------------------------------------------------------------

def section_validity(data: dict) -> list[str]:
    out = []
    nat = data["snapshot"].get("native") or {}

    pre = nat.get("preSuite.thermalOrdinal")
    post = nat.get("postSuite.thermalOrdinal")
    if pre is None and post is None:
        out.append("  thermal      : NOT CAPTURED — build predates the native "
                   "probe, or the plugin was absent. Cross-chip comparisons "
                   "from this run are unverifiable.")
    else:
        p0 = THERMAL_NAMES.get(pre, str(pre))
        p1 = THERMAL_NAMES.get(post, str(post))
        if isinstance(pre, int) and isinstance(post, int) and post > pre:
            out.append(f"  thermal      : ROSE {p0} -> {p1}  ** the device "
                       "throttled DURING the run; numbers from its second half "
                       "are not comparable with the first **")
        elif isinstance(post, int) and post >= 2:
            out.append(f"  thermal      : {p1}  ** already throttling; every "
                       "duration here is a throttled duration **")
        else:
            out.append(f"  thermal      : {p0} -> {p1}  (no throttling)")

    fp0, fp1 = nat.get("preSuite.footprintMB"), nat.get("postSuite.footprintMB")
    if fp0 is not None:
        av = nat.get("postSuite.availableMB")
        tail = f", {av} MB headroom left" if av is not None else ""
        out.append(f"  footprint    : {fp0} -> {fp1} MB{tail}")
        if isinstance(av, int) and av < 200:
            out.append("                 ** under 200 MB of headroom — this "
                       "process is close to being killed **")
    if nat.get("preSuite.lowPowerMode"):
        out.append("  power        : LOW POWER MODE ON — the CPU is capped; "
                   "these numbers are not the device's best case")

    # scenarios that recorded nothing
    dead = {}
    for s in scenarios(data):
        for k, v in (s.get("counters") or {}).items():
            if k.endswith(DEAD_SUFFIXES):
                dead[k] = dead.get(k, 0) + v
    if dead:
        out.append("  DEAD MEASUREMENTS — these produced a fast zero rather "
                   "than a fast operation:")
        for k, v in sorted(dead.items(), key=lambda kv: -kv[1]):
            out.append(f"      {k:52s} {v}")
        # M221 — and WHY, when the shim recorded a reason. A counter says a
        # call produced nothing; it cannot say what the kernel objected to,
        # and until notes existed that reason was written to the event log
        # AFTER the log had already been captured, so no bundle ever carried
        # one. Printed directly beneath the counter it explains.
        reasons = {}
        for s2 in scenarios(data):
            for k, v in (s2.get("notes") or {}).items():
                if k.endswith(".fail.reason"):
                    reasons.setdefault(k, v)
        if reasons:
            out.append("      —— reasons recorded by the shim ——")
            for k, v in sorted(reasons.items()):
                out.append(f"      {k:52s} {v}")
    else:
        out.append("  dead probes  : none — every scenario reached its subject")

    errs = [s["scenario"] for s in scenarios(data) if s.get("error")]
    if errs:
        out.append(f"  THREW        : {', '.join(errs)}")
    return out


# ---------------------------------------------------------------------------
# 2. the shape of each cost curve
# ---------------------------------------------------------------------------

SWEEP_RE = re.compile(r"^(.*)\.(\d+)$")

# Families whose swept axis is the size of the INPUT a fixed unit of work has
# to traverse, rather than the amount of work asked for. For these, k ≈ 1 means
# "one call is O(input)" — the finding, not the absence of one. Kept as an
# explicit list because nothing in the data distinguishes the two kinds of
# sweep, and a reader who does not know the difference will read the verdict
# backwards.
CONSTANT_WORK_FAMILIES = {
    "kernel.query.edgeInfoScale",
}


def section_curves(data: dict) -> list[str]:
    """Groups `foo.8` / `foo.24` / `foo.64` and fits an exponent.

    The exponent — not the millisecond — is the number that survives a change
    of chip, so it is what a report about "will this run on an A-series" has to
    lead with.
    """
    fams: dict[str, list[tuple[int, float]]] = {}
    for s in scenarios(data):
        m = SWEEP_RE.match(s.get("scenario", ""))
        if not m:
            continue
        fams.setdefault(m.group(1), []).append((int(m.group(2)), _wall(s)))

    rows = []
    for fam, pts in fams.items():
        pts.sort()
        if len(pts) < 2:
            continue
        k = _exponent(pts)
        rows.append((k if k is not None else -1, fam, pts, k))
    if not rows:
        return ["  (no sweep families found)"]

    rows.sort(reverse=True)
    out = [f"  {'family':34s} {'sizes -> ms':38s} {'n^k':>6s}  verdict"]
    for _, fam, pts, k in rows:
        sizes = "  ".join(f"{n}:{ms:.2f}" for n, ms in pts)
        if k is None:
            verdict, ks = "flat/unmeasurable", "   -- "
        else:
            ks = f"{k:6.2f}"
            if fam in CONSTANT_WORK_FAMILIES:
                # The swept axis here is the size of the ENVIRONMENT, not the
                # amount of work requested: the scenario asks for one fixed
                # unit of work on progressively larger input. Linear is
                # therefore the DAMNING result, not the reassuring one, and
                # labelling it "linear" alongside families whose axis is the
                # workload invites exactly the wrong conclusion.
                verdict = ("** per-call cost scales with input size **"
                           if k >= 0.8 else "flat — cost independent of input")
            elif k >= 2.5:
                verdict = "** CUBIC-ISH — this is the one that breaks **"
            elif k >= 1.6:
                verdict = "** superlinear **"
            elif k >= 0.8:
                verdict = "linear"
            else:
                verdict = "sublinear / dominated by fixed cost"
        out.append(f"  {fam:34s} {sizes:38s} {ks}  {verdict}")
    return out


def _wall(s: dict) -> float:
    """Prefer the measured span total over wall time: wall includes fixture
    setup, and for the bigger sweeps that setup is not free."""
    spans = s.get("spans") or {}
    if spans:
        return max(v.get("totalMs", 0.0) for v in spans.values())
    return float(s.get("wallMs") or 0.0)


def _exponent(pts):
    """Least-squares slope of log(ms) against log(n) — the growth exponent.

    Two points give the exact ratio; three or more average out one bad sample.
    Returns None when a duration is too small to take a log of, which is the
    honest answer for something that measured 0.000 ms.
    """
    xs, ys = [], []
    for n, ms in pts:
        if n > 0 and ms > 1e-6:
            xs.append(math.log(n))
            ys.append(math.log(ms))
    if len(xs) < 2:
        return None
    mx, my = sum(xs) / len(xs), sum(ys) / len(ys)
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den = sum((x - mx) ** 2 for x in xs)
    return None if den < 1e-12 else num / den


# ---------------------------------------------------------------------------
# 3. where the time went
# ---------------------------------------------------------------------------

def section_costs(data: dict, top: int) -> list[str]:
    agg: dict[str, dict] = {}
    for s in scenarios(data):
        for name, v in (s.get("spans") or {}).items():
            a = agg.setdefault(name, {"n": 0, "totalMs": 0.0, "worstMs": 0.0})
            a["n"] += v.get("n", 0)
            a["totalMs"] += v.get("totalMs", 0.0)
            a["worstMs"] = max(a["worstMs"], v.get("worstMs", 0.0))
    if not agg:
        return ["  (no spans recorded)"]

    total = sum(a["totalMs"] for a in agg.values())
    rows = sorted(agg.items(), key=lambda kv: -kv[1]["totalMs"])[:top]
    out = [f"  {'span':40s} {'n':>7s} {'total ms':>10s} {'avg ms':>9s} "
           f"{'worst ms':>9s} {'share':>7s}"]
    for name, a in rows:
        avg = a["totalMs"] / a["n"] if a["n"] else 0.0
        share = 100 * a["totalMs"] / total if total else 0
        out.append(f"  {name:40s} {a['n']:7d} {a['totalMs']:10.2f} "
                   f"{avg:9.4f} {a['worstMs']:9.3f} {share:6.1f}%")
    return out


def section_session(data: dict, top: int) -> list[str]:
    """The spans recorded during ACTUAL USE, not by the suite.

    Two things live here and nowhere else. First, whatever the person was
    doing before they pressed the button — the suite has fixed inputs by
    design, so only this half reflects a real document. Second, the native
    RealityKit table: it is drained into the session at capture time, not
    inside a scenario, so a reader that only walked the scenarios would show
    nothing for the one boundary that used to be unmeasurable.
    """
    spans = (data["snapshot"].get("spans") or {})
    if not spans:
        return ["  (no session snapshot in this bundle)"]
    rows = sorted(spans.items(), key=lambda kv: -kv[1].get("totalMs", 0.0))
    out = [f"  {'span':40s} {'n':>7s} {'total ms':>10s} {'avg ms':>9s} "
           f"{'p95 ms':>9s} {'worst ms':>9s}"]
    for name, v in rows[:top]:
        out.append(f"  {name:40s} {v.get('n', 0):7d} {v.get('totalMs', 0):10.2f} "
                   f"{v.get('avgMs', 0):9.4f} {v.get('p95Ms', 0):9.3f} "
                   f"{v.get('worstMs', 0):9.3f}")

    # The native block, called out rather than left to be spotted in the list:
    # it is the answer to "is the 3D view heavy", and until M215 it did not
    # exist at all.
    nat = {k: v for k, v in spans.items() if k.startswith("rv.native.")}
    if nat:
        gauges = data["snapshot"].get("gauges") or {}
        out.append("")
        out.append("  PAST THE PLATFORM-VIEW BOUNDARY (native RealityKit):")
        for name, v in sorted(nat.items(), key=lambda kv: -kv[1].get("totalMs", 0)):
            worst_us = gauges.get(f"{name}.worstUs")
            tail = f"   worst {worst_us / 1000:.2f} ms" if worst_us else ""
            out.append(f"      {name:36s} n={v.get('n', 0):5d} "
                       f"{v.get('totalMs', 0):9.2f} ms total{tail}")
    return out



def section_stress(data: dict) -> list[str]:
    """The ladders: how far each probe climbed before it blew its budget.

    `maxSize` is the answer, not the durations. A ladder that stopped is not a
    failed measurement — the rung it stopped at IS the measurement, and it is
    the only honest way to ask "how big a part still works" without hanging the
    app on the question.
    """
    g = {}
    for s in scenarios(data):
        for k, v in (s.get("gauges") or {}).items():
            if k.startswith("stress."):
                g[k] = v
    if not g:
        return ["  (no stress tier in this bundle — type `stress` in the bug "
                "description to include it)"]
    fams = sorted({k.split(".")[1] for k in g if k.endswith(".maxSize")})
    out = [f"  {'ladder':16s} {'reached':>9s} {'rss delta':>10s}   rungs (ms)"]
    for f in fams:
        rungs = []
        for s in scenarios(data):
            for k, v in (s.get("spans") or {}).items():
                if k.startswith(f"stress.{f}."):
                    try:
                        rungs.append((int(k.rsplit(".", 1)[1]), v.get("totalMs", 0)))
                    except ValueError:
                        pass
        rungs.sort()
        shown = "  ".join(f"{n}:{ms:.0f}" for n, ms in rungs)
        extra = [f"{k.split('.')[-1]}={v}" for k, v in g.items()
                 if k.startswith(f"stress.{f}.")
                 and not k.endswith(("maxSize", "rssDeltaMB"))]
        out.append(f"  {f:16s} {g.get(f'stress.{f}.maxSize', 0):9d} "
                   f"{g.get(f'stress.{f}.rssDeltaMB', 0):9d} MB   {shown}")
        if extra:
            out.append(f"  {'':16s} {' '.join(extra)}")
    return out


# ---------------------------------------------------------------------------
# 5. what changed
# ---------------------------------------------------------------------------

def section_diff(new: dict, old: dict, top: int) -> list[str]:
    def totals(d):
        agg = {}
        for s in scenarios(d):
            for name, v in (s.get("spans") or {}).items():
                e = agg.setdefault(name, [0, 0.0])
                e[0] += v.get("n", 0)
                e[1] += v.get("totalMs", 0.0)
        return {k: (v[1] / v[0] if v[0] else 0.0) for k, v in agg.items()}

    a, b = totals(old), totals(new)
    rows = []
    for k in sorted(set(a) | set(b)):
        oldv, newv = a.get(k), b.get(k)
        if oldv is None:
            rows.append((0.0, k, None, newv, "NEW"))
        elif newv is None:
            rows.append((0.0, k, oldv, None, "GONE"))
        elif oldv > 1e-6:
            rows.append(((newv - oldv) / oldv, k, oldv, newv, ""))
    moved = [r for r in rows if r[4] == "" and abs(r[0]) >= 0.15]
    moved.sort(key=lambda r: -abs(r[0]))
    out = [f"  {'span':40s} {'was':>10s} {'now':>10s} {'change':>9s}"]
    if not moved:
        out.append("  (nothing moved by more than 15%)")
    for pct, k, oldv, newv, _ in moved[:top]:
        arrow = "SLOWER" if pct > 0 else "faster"
        out.append(f"  {k:40s} {oldv:10.4f} {newv:10.4f} "
                   f"{pct * 100:+8.1f}%  {arrow}")
    fresh = [r[1] for r in rows if r[4] == "NEW"]
    gone = [r[1] for r in rows if r[4] == "GONE"]
    if fresh:
        out.append(f"  new spans  : {', '.join(fresh[:12])}"
                   f"{' …' if len(fresh) > 12 else ''}")
    if gone:
        out.append(f"  vanished   : {', '.join(gone[:12])}"
                   f"{' …' if len(gone) > 12 else ''}")
    return out


# ---------------------------------------------------------------------------

def header(data: dict) -> list[str]:
    out = []
    for suite in data["suites"]:
        out.append(f"  {suite.get('suite', '?'):24s} "
                   f"build {suite.get('build', '?')}  "
                   f"{suite.get('at', '')}  "
                   f"wall {suite.get('wallMs', '?')} ms  "
                   f"occt={suite.get('occtAvailable', '?')}")
    snap = data["snapshot"]
    fr = snap.get("frames") or {}
    if fr.get("n"):
        out.append(f"  session: {fr['n']} frames, "
                   f"{fr.get('fps', 0):.1f} fps, {fr.get('jank33', 0)} jank")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("bundle", help="bug bundle zip, directory, or perf_suite.json")
    ap.add_argument("--baseline", help="an earlier bundle to diff against")
    ap.add_argument("--top", type=int, default=25, help="rows per table")
    args = ap.parse_args()

    if not os.path.exists(args.bundle):
        print(f"no such bundle: {args.bundle}", file=sys.stderr)
        return 2
    data = load(args.bundle)
    if not data["suites"]:
        print("no perf suite found in this bundle — it predates the "
              "self-driving suite, or the capture failed (check the bundle "
              "for perf_suite.json holding an error string)", file=sys.stderr)
        return 1

    def banner(t):
        print("\n" + "=" * 78)
        print(t)
        print("=" * 78)

    banner(f"PERF REPORT — {data['label']}")
    print("\n".join(header(data)))

    banner("1. IS THIS RUN TRUSTWORTHY?")
    print("\n".join(section_validity(data)))

    banner("2. HOW FAR IT GOES — the stress ladders, if this bundle has them")
    print("\n".join(section_stress(data)))

    banner("3. COST CURVES — the exponent is what survives a change of chip")
    print("\n".join(section_curves(data)))

    banner("4. WHERE THE TIME WENT — the suite")
    print("\n".join(section_costs(data, args.top)))

    banner("4b. THE LIVE SESSION — what the person was actually doing")
    print("\n".join(section_session(data, args.top)))

    if args.baseline:
        if not os.path.exists(args.baseline):
            print(f"\nbaseline not found: {args.baseline}", file=sys.stderr)
            return 2
        old = load(args.baseline)
        banner(f"5. WHAT CHANGED vs {old['label']}")
        print("\n".join(section_diff(data, old, args.top)))
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
