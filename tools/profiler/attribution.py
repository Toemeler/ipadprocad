"""Turn a `SampleSet` into an attribution: who spent the time, with an interval.

A sampling profiler measures a *proportion*, and a proportion estimated from N
draws has an uncertainty whether or not anybody prints it. `PERFORMANCE_PROFILE.md`
§1.2 refuses to print digits the instrument cannot support; the same discipline
applies here, and the relevant interval is binomial rather than quantization.
Every share below therefore carries a 95 % Wilson score interval on the
underlying proportion, and the Wilson form is chosen over the textbook Wald one
because the shares that matter here are near 0 and near 1, which is exactly
where Wald produces intervals that run off the end of the scale.

What a share is a share OF is stated in every table, because that was the
source of two errors in an earlier draft of the report it feeds (§1.3).
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass

from samples import Frame, Sample, SampleSet

_Z = 1.959963984540054  # two-sided 95 %


def wilson(k: int, n: int, z: float = _Z) -> tuple[float, float]:
    """95 % Wilson score interval for k successes in n trials, as fractions."""
    if n <= 0:
        return (0.0, 0.0)
    p = k / n
    d = 1.0 + z * z / n
    centre = (p + z * z / (2 * n)) / d
    half = (z / d) * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return (max(0.0, centre - half), min(1.0, centre + half))


@dataclass
class Row:
    label: str
    self_n: int
    total_n: int
    frame: Frame | None = None

    def share(self, denom: int) -> float:
        return self.total_n / denom if denom else 0.0


def _matcher(pattern: str):
    """Patterns are plain substrings unless they start with `re:`.

    Substrings are what a reader reaches for (`_rankAndPivots`); a regex is
    what a bucket definition sometimes needs (`re:^_(jacobian|residuals)$`).
    """
    if pattern.startswith("re:"):
        rx = re.compile(pattern[3:])
        return lambda f: bool(rx.search(f.qualified)) or bool(rx.search(f.label))
    p = pattern
    return lambda f: p in f.qualified or p in f.label


DART_KINDS = ("Dart", "Stub", "Collected")


def has_dart(ss: SampleSet, s: Sample) -> bool:
    return any(ss.frames[i].kind in DART_KINDS for i in s.stack)


def select(ss: SampleSet, *, isolate: str | None = None,
           tid: int | None = None, tag: str | None = None,
           dart_only: bool = False) -> list[Sample]:
    """Narrow the sample set to the view a table is about to describe.

    `dart_only` deserves the explanation. A Dart VM process runs more threads
    than the one executing Dart — an IO thread, GC helpers, the platform
    thread — and the sampler samples all of them, including while they sit in
    `pthread_cond_timedwait` doing nothing. On the host lane those idle threads
    were 63 % of the samples in the first capture taken with this tool. Leaving
    them in makes every share a share of "samples the profiler took", which is
    not a quantity anybody wants; taking them out makes it a share of samples
    in which Dart was on the stack, which is.

    Nothing is lost by it: the trace and the folded stacks are written from the
    unfiltered set, so the native side stays inspectable. Only the ATTRIBUTION
    tables are narrowed, and every table says how many samples it covers.
    """
    out = ss.samples
    if isolate:
        out = [s for s in out if s.isolate == isolate or
               ss.isolate_names.get(s.isolate, "") == isolate]
    if tid is not None:
        out = [s for s in out if s.tid == tid]
    if tag:
        out = [s for s in out if s.user_tag == tag or s.vm_tag == tag]
    if dart_only:
        out = [s for s in out if has_dart(ss, s)]
    return list(out)


def census(ss: SampleSet, samples: list[Sample] | None = None) -> dict:
    """What the sampler actually caught, before anybody reads a share of it."""
    samples = ss.samples if samples is None else samples
    by_tid: dict[tuple[str, int], int] = {}
    by_vmtag: dict[str, int] = {}
    by_usertag: dict[str, int] = {}
    dart = 0
    truncated = 0
    for s in samples:
        by_tid[(s.isolate, s.tid)] = by_tid.get((s.isolate, s.tid), 0) + 1
        by_vmtag[s.vm_tag or "-"] = by_vmtag.get(s.vm_tag or "-", 0) + 1
        by_usertag[s.user_tag or "-"] = by_usertag.get(s.user_tag or "-", 0) + 1
        if has_dart(ss, s):
            dart += 1
        if s.truncated:
            truncated += 1
    return {
        "samples": len(samples),
        "withDartFrames": dart,
        "nativeOnly": len(samples) - dart,
        "truncatedStacks": truncated,
        "byThread": {f"{ss.isolate_names.get(i, i)}#{t}": n
                     for (i, t), n in sorted(by_tid.items(), key=lambda kv: -kv[1])},
        "byVmTag": dict(sorted(by_vmtag.items(), key=lambda kv: -kv[1])),
        "byUserTag": dict(sorted(by_usertag.items(), key=lambda kv: -kv[1])),
    }


def census_markdown(c: dict) -> str:
    lines = ["### Census — what the sampler caught", "",
             f"* samples in this view: **{c['samples']}**",
             f"* with at least one Dart frame: **{c['withDartFrames']}** "
             f"({100.0*c['withDartFrames']/c['samples'] if c['samples'] else 0:.1f} %)",
             f"* native-only stacks (idle threads, GC helpers, the engine's own "
             f"threads): {c['nativeOnly']}",
             f"* stacks truncated at the depth limit: {c['truncatedStacks']}", ""]
    lines.append("| thread | samples |")
    lines.append("| :--- | ---: |")
    for k, v in list(c["byThread"].items())[:8]:
        lines.append(f"| `{k}` | {v} |")
    lines.append("")
    lines.append("VM tags: " + ", ".join(f"`{k}` {v}" for k, v in
                                         list(c["byVmTag"].items())[:8]))
    lines.append("")
    return "\n".join(lines)


def flat(ss: SampleSet, samples: list[Sample] | None = None) -> list[Row]:
    """Self and total sample counts per function, sorted by self, descending.

    `total` counts a function once per sample in which it appears at any depth.
    Recursion therefore contributes one, not one per activation — otherwise a
    recursive function's inclusive share can exceed the number of samples,
    which is not a share of anything.
    """
    samples = ss.samples if samples is None else samples
    self_n: dict[int, int] = {}
    total_n: dict[int, int] = {}
    for s in samples:
        if s.stack:
            self_n[s.stack[0]] = self_n.get(s.stack[0], 0) + 1
        for fi in set(s.stack):
            total_n[fi] = total_n.get(fi, 0) + 1
    rows = [Row(label=ss.frames[i].label, self_n=self_n.get(i, 0),
                total_n=total_n.get(i, 0), frame=ss.frames[i])
            for i in sorted(set(list(self_n) + list(total_n)))]
    rows.sort(key=lambda r: (-r.self_n, -r.total_n, r.label))
    return rows


def containing(ss: SampleSet, pattern: str,
               samples: list[Sample] | None = None) -> list[tuple[Sample, int]]:
    """Samples whose stack contains `pattern`, paired with that frame's depth.

    Depth is the index into `Sample.stack`, which is LEAF FIRST — so a larger
    depth is further from the leaf, closer to the root. The OUTERMOST match is
    returned, which is what "inside analyzeSketch" has to mean when the routine
    is reentrant.
    """
    samples = ss.samples if samples is None else samples
    match = _matcher(pattern)
    hits: list[tuple[Sample, int]] = []
    for s in samples:
        found = -1
        for depth in range(len(s.stack) - 1, -1, -1):
            if match(ss.frames[s.stack[depth]]):
                found = depth
                break
        if found >= 0:
            hits.append((s, found))
    return hits


def within(ss: SampleSet, root_pattern: str, buckets: list[tuple[str, list[str]]],
           samples: list[Sample] | None = None) -> dict:
    """Split the time spent inside `root_pattern` into named buckets.

    This is the primitive the validation rests on. For each sample that is
    inside the root, walk from the root TOWARD THE LEAF and assign the sample
    to the first bucket any frame on that path matches. Walking outside-in
    rather than leaf-first matters: `_residuals` appears under both the
    Jacobian construction and the elimination in some builds, and the question
    "which phase is this sample in" is answered by the outer phase, not by
    whichever leaf the sampler happened to catch.

    A sample inside the root that matches no bucket lands in `other`, and
    `other` is reported rather than hidden — a large `other` means the buckets
    do not describe the routine and the split must not be quoted.
    """
    hits = containing(ss, root_pattern, samples)
    order = [(name, [_matcher(p) for p in pats]) for name, pats in buckets]
    counts = {name: 0 for name, _ in buckets}
    counts["other"] = 0
    examples: dict[str, str] = {}
    for s, depth in hits:
        assigned = None
        for d in range(depth, -1, -1):        # root -> leaf
            f = ss.frames[s.stack[d]]
            for name, ms in order:
                if any(m(f) for m in ms):
                    assigned = name
                    break
            if assigned:
                break
        if assigned is None:
            assigned = "other"
            leaf = ss.frames[s.stack[0]].label if s.stack else "<empty>"
            examples.setdefault(leaf, leaf)
        counts[assigned] += 1

    n = len(hits)
    out = {
        "root": root_pattern,
        "samplesInRoot": n,
        "samplesTotal": len(ss.samples if samples is None else samples),
        "buckets": {},
        "otherLeaves": sorted(examples)[:12],
    }
    for name in list(counts):
        k = counts[name]
        lo, hi = wilson(k, n)
        out["buckets"][name] = {
            "samples": k,
            "share": (k / n) if n else 0.0,
            "ci95": [lo, hi],
        }
    return out


def ms_of(ss: SampleSet, n_samples: int) -> float:
    """Sample count -> milliseconds, at the period the VM reported.

    This is an ESTIMATE and is labelled as one everywhere it is printed. The
    sampler misses time the VM spends where it cannot walk a stack, and the
    period is nominal rather than guaranteed; the count is the measurement and
    the millisecond is a convenience.
    """
    return n_samples * ss.sample_period_us / 1000.0


def markdown(ss: SampleSet, *, top: int = 25,
             samples: list[Sample] | None = None, title: str = "") -> str:
    samples = ss.samples if samples is None else samples
    n = len(samples)
    rows = flat(ss, samples)
    lines: list[str] = []
    if title:
        lines.append(f"### {title}")
        lines.append("")
    lines.append(f"Samples: **{n}**, period {ss.sample_period_us} us "
                 f"(~{ms_of(ss, n):.1f} ms of sampled CPU time). "
                 f"Shares are of these {n} samples.")
    lines.append("")
    lines.append("| # | self | self % | 95 % CI | total | total % | function |")
    lines.append("| ---: | ---: | ---: | :--- | ---: | ---: | :--- |")
    for i, r in enumerate(rows[:top], 1):
        slo, shi = wilson(r.self_n, n)
        lines.append(
            f"| {i} | {r.self_n} | {100.0 * r.self_n / n if n else 0:.2f} | "
            f"[{100*slo:.2f}, {100*shi:.2f}] | {r.total_n} | "
            f"{100.0 * r.total_n / n if n else 0:.2f} | `{r.label}` |")
    lines.append("")
    return "\n".join(lines)


def within_markdown(res: dict, ss: SampleSet, title: str = "") -> str:
    n = res["samplesInRoot"]
    lines: list[str] = []
    if title:
        lines.append(f"### {title}")
        lines.append("")
    lines.append(f"Root `{res['root']}`: **{n}** samples of "
                 f"{res['samplesTotal']} "
                 f"(~{ms_of(ss, n):.1f} ms). Shares below are of those {n}.")
    lines.append("")
    lines.append("| phase | samples | share | 95 % CI | est. ms |")
    lines.append("| :--- | ---: | ---: | :--- | ---: |")
    for name, b in res["buckets"].items():
        lo, hi = b["ci95"]
        lines.append(f"| {name} | {b['samples']} | {100*b['share']:.2f} % | "
                     f"[{100*lo:.2f}, {100*hi:.2f}] | {ms_of(ss, b['samples']):.1f} |")
    lines.append("")
    if res["buckets"].get("other", {}).get("samples"):
        lines.append("Leaves seen in `other` (up to 12): " +
                     ", ".join(f"`{x}`" for x in res["otherLeaves"]))
        lines.append("")
    return "\n".join(lines)
