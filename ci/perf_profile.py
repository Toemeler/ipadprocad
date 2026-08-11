#!/usr/bin/env python3
"""Emit the COMPLETE data appendix of a perf bundle as Markdown.

WHY THIS EXISTS, SEPARATELY FROM perf_report.py
-----------------------------------------------
`perf_report.py` answers "what should I look at" — it ranks, it fits, it
truncates to the top N. That is the right shape for reading a run.

It is the wrong shape for a reference document. A profile that quotes a
selection of numbers cannot be audited against the bundle, and the selection
is exactly where bias enters: the spans nobody printed are the spans nobody
questioned. This script prints EVERYTHING — every span, every counter, every
gauge, every scenario — so the appendix of PERFORMANCE_PROFILE.md is generated
rather than transcribed, and regenerating it after the next device run is one
command instead of a day of copying.

Two rules it enforces that hand-transcription kept breaking:

  * RESOLUTION. Perf.span records elapsedMicroseconds, so every observation is
    an integer multiple of 1 us. A mean below the quantization floor is not a
    measurement of a small number, it is the absence of one. Such values are
    printed as "< 1 us" and never as digits.

  * SCOPE. perf_suite*.json counts one scenario, measured pass only;
    perf_snapshot.json counts the process lifetime and therefore includes the
    warm-up pass, making its counts ~2x larger. Totals and shares are only
    meaningful within one scope. Each table below states which it is.

Usage:
    python3 ci/perf_profile.py <bundle.zip> [--label TEXT] > appendix.md
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
import zipfile
from collections import defaultdict

Q_MS = 0.001  # one microsecond, the timer's quantum


# ---------------------------------------------------------------------------
# loading
# ---------------------------------------------------------------------------

def load(path: str) -> dict:
    """Returns {snapshot, runners:[(name, data)], bundle}."""
    out = {"snapshot": {}, "runners": [], "bundle": path.split("/")[-1]}
    with zipfile.ZipFile(path) as z:
        names = set(z.namelist())
        if "perf_snapshot.json" in names:
            out["snapshot"] = json.loads(z.read("perf_snapshot.json"))
        for n in ("perf_suite.json", "perf_suite_ui.json"):
            if n in names:
                out["runners"].append((n, json.loads(z.read(n))))
    return out


# ---------------------------------------------------------------------------
# statistics
# ---------------------------------------------------------------------------

def se_q(n: int) -> float:
    """Standard error of a mean contributed by 1 us quantization alone."""
    return Q_MS / math.sqrt(12 * n) if n > 0 else float("inf")


def resolution(mean_ms: float, n: int) -> tuple[str, float]:
    """(class, SNR). See the module docstring."""
    se = se_q(n)
    snr = mean_ms / se if se > 0 else 0.0
    if snr < 3:
        return "unresolved", snr
    if snr < 10:
        return "marginal", snr
    return "resolved", snr


def ms(v: float, n: int = 1) -> str:
    """Format a MEAN, refusing to print below the quantization floor."""
    if v is None:
        return "—"
    cls, _ = resolution(v, n)
    if cls == "unresolved":
        return "< 1 µs"
    if v >= 100:
        return f"{v:.1f}"
    if v >= 10:
        return f"{v:.2f}"
    if v >= 1:
        return f"{v:.3f}"
    return f"{v:.4f}"


def obs(v: float) -> str:
    """Format a SINGLE OBSERVATION (p50, p95, max).

    A percentile is one recorded value, not an average of many, so the
    quantization floor applies to it directly: below one tick there is
    nothing to report. Using the mean's standard error here would wrongly
    suppress legitimate small percentiles on large samples.
    """
    if v is None:
        return "—"
    if v < Q_MS:
        return "< 1 µs"
    if v >= 100:
        return f"{v:.1f}"
    if v >= 10:
        return f"{v:.2f}"
    if v >= 1:
        return f"{v:.3f}"
    return f"{v:.4f}"


def fit(points: list[tuple[float, float]]) -> dict | None:
    """OLS on log-log. Returns k, r2, se, n, and a CI when N > 2."""
    pts = sorted((x, y) for x, y in points if x > 0 and y > 0)
    if len(pts) < 2:
        return None
    xs = [math.log(x) for x, _ in pts]
    ys = [math.log(y) for _, y in pts]
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    if sxx <= 0:
        return None
    k = sum((x - mx) * (y - my) for x, y in zip(xs, ys)) / sxx
    b = my - k * mx
    ss_res = sum((y - (k * x + b)) ** 2 for x, y in zip(xs, ys))
    ss_tot = sum((y - my) ** 2 for y in ys)
    r2 = 1 - ss_res / ss_tot if ss_tot > 0 else float("nan")
    se = math.sqrt(ss_res / (n - 2) / sxx) if n > 2 and ss_res > 0 else None
    return {"k": k, "b": b, "r2": r2, "se": se, "n": n, "pts": pts}


def fit_cell(f: dict | None) -> tuple[str, str, str]:
    """(k, R2, CI) as display strings, honouring the N=2 rule."""
    if not f:
        return "—", "—", "—"
    k = f"{f['k']:.2f}"
    if f["n"] == 2:
        return k, "—", "slope only (N=2)"
    r2 = f"{f['r2']:.4f}"
    if f["se"] is None or f["se"] == 0:
        return k, r2, "exact"
    lo, hi = f["k"] - 1.96 * f["se"], f["k"] + 1.96 * f["se"]
    return k, r2, f"[{lo:.2f}, {hi:.2f}]"


# ---------------------------------------------------------------------------
# grouping
# ---------------------------------------------------------------------------

# Maps a span-name prefix onto the subsystem a reader thinks in. Anything
# unmatched lands in "other" rather than being dropped — a span nobody
# classified must still appear, or the appendix stops being complete.
SUBSYSTEMS: list[tuple[str, str]] = [
    ("2d.paint", "2D — painter phases"),
    ("2d.", "2D — interaction"),
    ("solve.", "Constraint solver"),
    ("ffi.slvs", "Constraint solver (native)"),
    ("sketch.", "Sketch analysis and rebuild"),
    ("constraints.", "Constraints"),
    ("tool.build.", "Drawing tools"),
    ("tools.", "Drawing tools (composite)"),
    ("spline.", "Splines"),
    ("ellipse.", "Ellipses"),
    ("freehand.", "Freehand"),
    ("gear.", "Gears"),
    ("modify.", "Modify operations"),
    ("ffi.occt.", "3D kernel — OCCT entry points"),
    ("kernel.", "3D kernel — scenarios"),
    ("part.", "3D — feature rebuild"),
    ("provenance.", "3D — face provenance"),
    ("pattern.", "Patterns"),
    ("project.", "Projection"),
    ("3d.", "3D — scene push"),
    ("rv.native", "RealityKit (native, past the boundary)"),
    ("rv.", "RealityKit (Dart side)"),
    ("ffi.qcad.", "2D kernel — qcad entry points"),
    ("io.", "Document I/O"),
    ("app.", "Application paths"),
    ("ui.", "UI runner"),
    ("menu.", "UI shell"),
    ("browser.", "UI shell"),
    ("toolbar.", "UI shell"),
    ("tabbar.", "UI shell"),
    ("step.", "Startup steps"),
    ("launch.", "Startup"),
    ("ramp.", "Ramps (fine-grained sweeps)"),
    ("quality.", "Quality / calibration"),
    ("stress.", "Stress ladders"),
]


def subsystem_of(name: str) -> str:
    for prefix, label in SUBSYSTEMS:
        if name.startswith(prefix):
            return label
    return "Other"


def grouped(names) -> dict[str, list[str]]:
    out: dict[str, list[str]] = defaultdict(list)
    for n in names:
        out[subsystem_of(n)].append(n)
    return {k: sorted(v) for k, v in sorted(out.items())}


# ---------------------------------------------------------------------------
# sections
# ---------------------------------------------------------------------------

def section_spans(snap: dict) -> list[str]:
    spans = snap.get("spans") or {}
    if not spans:
        return ["_(no spans in this bundle)_"]
    counts = defaultdict(int)
    for name, v in spans.items():
        cls, _ = resolution(v.get("avgMs", 0.0), v.get("n", 0))
        counts[cls] += 1
    out = [
        f"Complete inventory: **{len(spans)} spans**, session scope (includes "
        f"the warm-up pass). Resolution classes: "
        f"**{counts['resolved']} resolved**, {counts['marginal']} marginal, "
        f"**{counts['unresolved']} unresolved** (mean below the 1 µs "
        f"quantization floor — printed as `< 1 µs`, never as digits).",
        "",
        "**Two different windows in one row.** `n`, `total` and `mean` cover "
        "every observation. `p50`, `p95` and `max` are computed over a "
        "**128-sample ring buffer** (`perf.dart:41`), i.e. the most recent "
        "≤128 observations only. Where a span ran more than 128 times under "
        "changing conditions the two disagree legitimately — `2d.paint` has a "
        "mean of 0.3362 ms and a p50 of 0.6400 ms because its last 128 paints "
        "were drag frames while the earlier ones were static. Neither figure "
        "is wrong; they answer different questions, and comparing them across "
        "spans without noticing the window is an error.",
        "",
    ]
    for label, names in grouped(spans).items():
        out += [f"#### {label}", "",
                "| span | n | total ms | mean ms | p50 | p95 | max | class |",
                "| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |"]
        for name in sorted(names,
                           key=lambda x: -spans[x].get("totalMs", 0.0)):
            v = spans[name]
            n = v.get("n", 0)
            cls, _ = resolution(v.get("avgMs", 0.0), n)
            out.append(
                f"| `{name}` | {n} | {v.get('totalMs', 0.0):.2f} | "
                f"{ms(v.get('avgMs'), n)} | {obs(v.get('p50Ms'))} | "
                f"{obs(v.get('p95Ms'))} | {obs(v.get('worstMs'))} | {cls} |")
        out.append("")
    return out


def section_counters(snap: dict) -> list[str]:
    c = snap.get("counters") or {}
    if not c:
        return ["_(no counters)_"]
    out = [
        f"**{len(c)} counters**, session scope. Counters are exact integers "
        "and carry no timing uncertainty; where a counter and a duration "
        "answer the same question, the counter is the stronger evidence and "
        "is invariant under a change of processor.",
        "",
    ]
    for label, names in grouped(c).items():
        out += [f"#### {label}", "", "| counter | value |", "| --- | ---: |"]
        for n in names:
            out.append(f"| `{n}` | {c[n]} |")
        out.append("")
    return out


def section_gauges(snap: dict) -> list[str]:
    g = snap.get("gauges") or {}
    if not g:
        return ["_(no gauges)_"]
    native = {k: v for k, v in g.items() if k.startswith("native.")}
    rest = {k: v for k, v in g.items() if not k.startswith("native.")}
    out = [
        f"**{len(g)} gauges** ({len(rest)} application, {len(native)} machine). "
        "Gauges are exact last-written values describing the size of the input "
        "a measurement ran against — the axis a duration is meaningless "
        "without.",
        "",
    ]
    for label, names in grouped(rest).items():
        out += [f"#### {label}", "", "| gauge | value |", "| --- | ---: |"]
        for n in names:
            out.append(f"| `{n}` | {rest[n]} |")
        out.append("")
    if native:
        out += ["#### Machine state (native probe)", "",
                "These describe the machine, not the application. They are "
                "deliberately a separate table: mixing them is how "
                "\"the code got slower\" stops being distinguishable from "
                "\"the iPad got hot\".", "",
                "| probe | value |", "| --- | ---: |"]
        for n in sorted(native):
            out.append(f"| `{n}` | {native[n]} |")
        out.append("")
    return out


def section_scenarios(runners) -> list[str]:
    rows = []
    for fname, data in runners:
        for s in data.get("scenarios", []):
            spans = s.get("spans") or {}
            dom, dom_ms = "—", 0.0
            for k, v in spans.items():
                if v.get("totalMs", 0.0) > dom_ms:
                    dom, dom_ms = k, v["totalMs"]
            rows.append((s.get("scenario", "?"), fname, s.get("wallMs", 0.0),
                         dom, dom_ms, len(spans), s.get("note", "")))
    if not rows:
        return ["_(no scenarios)_"]
    out = [
        f"**{len(rows)} scenario executions** across "
        f"{len(runners)} runners, scenario scope (measured pass only). "
        "`dominant span` is the largest single span inside the scenario — the "
        "quantity the cost-model fits use, because it excludes fixture "
        "construction.",
        "",
        "| scenario | runner | wall ms | dominant span | dominant ms | spans |",
        "| --- | --- | ---: | --- | ---: | ---: |",
    ]
    for name, fname, wall, dom, dom_ms, nspans, _ in sorted(rows):
        runner = "ui" if "ui" in fname else "headless"
        out.append(f"| `{name}` | {runner} | {wall:.3f} | `{dom}` | "
                   f"{dom_ms:.3f} | {nspans} |")
    out.append("")
    return out


def section_ramps(snap: dict) -> list[str]:
    spans = snap.get("spans") or {}
    fams: dict[str, list[tuple[int, float]]] = defaultdict(list)
    for k, v in spans.items():
        m = re.match(r"^(ramp\.[A-Za-z]+)\.(\d+)$", k)
        if m:
            fams[m.group(1)].append((int(m.group(2)), v.get("avgMs", 0.0)))
    if not fams:
        return ["_(no ramp families)_"]
    out = [
        "Ramps use fine steps so a **knee** is visible. A fit through three "
        "points assumes the curve *is* a power law and averages away anything "
        "that is not one; the local exponent between neighbouring rungs does "
        "not. A constant local exponent means a clean power law; a jump means "
        "a threshold, and the rung it jumps at is the size that matters.",
        "",
    ]
    for fam in sorted(fams):
        pts = sorted(set(fams[fam]))
        f = fit(pts)
        k, r2, ci = fit_cell(f)
        out += [f"#### `{fam}` — overall k = {k}, R² = {r2}, CI {ci}", "",
                "| size | mean ms | local exponent vs previous |",
                "| ---: | ---: | ---: |"]
        prev = None
        for n, v in pts:
            loc = "—"
            if prev and prev[1] > 0 and v > 0 and prev[0] > 0 and n != prev[0]:
                loc = f"{math.log(v / prev[1]) / math.log(n / prev[0]):.2f}"
            out.append(f"| {n} | {v:.4f} | {loc} |")
            prev = (n, v)
        out.append("")
    return out


def section_fits(runners) -> list[str]:
    fams: dict[str, list[tuple[int, float]]] = defaultdict(list)
    for _, data in runners:
        for s in data.get("scenarios", []):
            m = re.match(r"^(.*)\.(\d+)$", s.get("scenario", ""))
            if not m:
                continue
            spans = s.get("spans") or {}
            dom = max((v.get("totalMs", 0.0) for v in spans.values()),
                      default=s.get("wallMs", 0.0))
            fams[m.group(1)].append((int(m.group(2)), dom))
    rows = []
    for fam, pts in fams.items():
        f = fit(sorted(set(pts)))
        if f:
            rows.append((f["k"], fam, f))
    if not rows:
        return ["_(no sweep families)_"]
    out = [
        f"**{len(rows)} sweep families.** Dependent variable: dominant span "
        "total. Families with N = 2 yield a slope with zero residual degrees "
        "of freedom — R² is 1.000 by construction and no confidence interval "
        "exists, so they support **no scaling claim**.",
        "",
        "| family | N | k | R² | 95 % CI | range ms |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for _, fam, f in sorted(rows, reverse=True):
        k, r2, ci = fit_cell(f)
        lo = min(v for _, v in f["pts"])
        hi = max(v for _, v in f["pts"])
        out.append(f"| `{fam}` | {f['n']} | {k} | {r2} | {ci} | "
                   f"{lo:.3f}–{hi:.3f} |")
    out.append("")
    return out


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("bundle")
    ap.add_argument("--label", default="")
    a = ap.parse_args()

    d = load(a.bundle)
    snap, runners = d["snapshot"], d["runners"]
    build = snap.get("build", "?")
    at = snap.get("at", "?")

    print(f"<!-- generated by ci/perf_profile.py from {d['bundle']} -->")
    print()
    print(f"Source bundle `{d['bundle']}`, build `{build}`, captured {at}"
          + (f" — {a.label}" if a.label else "") + ".")
    print()
    print("Every number below is printed verbatim from the bundle. Nothing is "
          "selected, ranked away or rounded beyond the instrument's "
          "resolution.")
    print()

    for title, body in (
        ("A. Complete span inventory", section_spans(snap)),
        ("B. Complete counter inventory", section_counters(snap)),
        ("C. Complete gauge inventory", section_gauges(snap)),
        ("D. Complete scenario inventory", section_scenarios(runners)),
        ("E. Ramp families with local exponents", section_ramps(snap)),
        ("F. All fitted cost models", section_fits(runners)),
    ):
        print(f"### {title}")
        print()
        print("\n".join(body))
        print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
