"""SampleSet -> a trace Perfetto can open, plus a folded-stack text form.

Two output formats, for two different readers.

**The trace** is the Chrome/Catapult JSON Trace Event Format, which
`ui.perfetto.dev` and `trace_processor` both ingest natively. It is chosen over
hand-encoding Perfetto's protobuf for one reason that outweighs fidelity: this
file has to be right, and a JSON document can be checked by a unit test that
reads it back, while a hand-rolled protobuf can only be checked by the tool
that is supposed to be under test.

Sampled stacks are converted to slices by FOLDING: consecutive samples sharing
a stack prefix become one slice per common frame, and a slice ends when the
frame leaves the stack. That is the standard reading of a sampled profile as a
flame chart, and it is an interpretation rather than a recording — the VM did
not observe the entry and exit times, it observed the stack every `period`
microseconds. `maxGapUs` exists so the interpretation stays honest: a stack
that reappears after a long silence starts a NEW slice instead of one long one
spanning time nobody sampled.

**The folded form** is `root;middle;leaf <count>`, one line per distinct stack.
It is what survives being read out of a git branch with `grep` — §13.1's lesson
is that a capture nobody can open is not a capture, and a text file with one
number per line can be opened anywhere.
"""

from __future__ import annotations

import json

from samples import SampleSet


def _tid_of(s, tid_map: dict[tuple[str, int], int]) -> int:
    """Namespace thread ids by isolate.

    Two isolates can report the same OS thread id, and Perfetto would draw them
    as one track. Remapping to a dense private range keeps them apart and keeps
    the ids small enough to read.
    """
    key = (s.isolate, s.tid)
    if key not in tid_map:
        tid_map[key] = len(tid_map) + 1
    return tid_map[key]


def to_trace_events(ss: SampleSet, *, max_gap_us: int | None = None) -> list[dict]:
    period = ss.sample_period_us or 1000
    max_gap = max_gap_us if max_gap_us is not None else max(4 * period, 4000)
    pid = ss.pid or 1
    tid_map: dict[tuple[str, int], int] = {}
    events: list[dict] = []

    events.append({"ph": "M", "pid": pid, "tid": 0, "name": "process_name",
                   "args": {"name": "Dart VM (pid %d)" % pid}})

    by_track: dict[tuple[str, int], list] = {}
    for s in ss.samples:
        by_track.setdefault((s.isolate, s.tid), []).append(s)

    for (iso, raw_tid), group in sorted(by_track.items()):
        group.sort(key=lambda s: s.timestamp)
        tid = _tid_of(group[0], tid_map)
        iso_name = ss.isolate_names.get(iso, iso)
        events.append({"ph": "M", "pid": pid, "tid": tid, "name": "thread_name",
                       "args": {"name": f"{iso_name} (tid {raw_tid})"}})

        # open[i] = (frame index, start ts)
        open_stack: list[tuple[int, int]] = []
        prev_ts: int | None = None

        def close_to(depth: int, end_ts: int) -> None:
            while len(open_stack) > depth:
                fi, start = open_stack.pop()
                f = ss.frames[fi]
                events.append({
                    "ph": "X", "pid": pid, "tid": tid,
                    "ts": start, "dur": max(end_ts - start, 1),
                    "name": f.qualified,
                    "cat": f.kind or "Dart",
                    "args": {"url": f.url, "line": f.line, "site": f.site},
                })

        for s in group:
            ts = s.timestamp
            if prev_ts is not None and ts - prev_ts > max_gap:
                close_to(0, prev_ts + period)
            want = list(reversed(s.stack))          # root -> leaf
            common = 0
            while (common < len(open_stack) and common < len(want)
                   and open_stack[common][0] == want[common]):
                common += 1
            close_to(common, ts)
            for fi in want[common:]:
                open_stack.append((fi, ts))
            prev_ts = ts

        if prev_ts is not None:
            close_to(0, prev_ts + period)

    events.sort(key=lambda e: (e.get("ts", -1), -len(str(e.get("name", "")))))
    return events


def to_trace(ss: SampleSet, *, max_gap_us: int | None = None) -> dict:
    return {
        "displayTimeUnit": "ms",
        "traceEvents": to_trace_events(ss, max_gap_us=max_gap_us),
        "otherData": {
            "producer": "tools/profiler (ipadprocad)",
            "source": "Dart VM Service getCpuSamples",
            "samplePeriodUs": str(ss.sample_period_us),
            "sampleCount": str(len(ss.samples)),
            "maxStackDepth": str(ss.max_stack_depth),
            "note": ("slices are FOLDED SAMPLES, not observed call boundaries; "
                     "a slice's duration is the span over which its frame was "
                     "seen on the stack"),
            **{f"meta.{k}": json.dumps(v) if not isinstance(v, str) else v
               for k, v in ss.meta.items()},
        },
    }


def to_folded(ss: SampleSet, *, sep: str = ";") -> str:
    """`root;middle;leaf <count>` — one line per distinct stack, sorted."""
    counts: dict[str, int] = {}
    for s in ss.samples:
        path = sep.join(ss.frames[i].qualified for i in reversed(s.stack))
        counts[path] = counts.get(path, 0) + 1
    return "".join(f"{k} {v}\n" for k, v in
                   sorted(counts.items(), key=lambda kv: (-kv[1], kv[0])))


def write_trace(ss: SampleSet, path: str, *, gzip_it: bool = True,
                max_gap_us: int | None = None) -> str:
    import gzip as _gzip
    payload = json.dumps(to_trace(ss, max_gap_us=max_gap_us),
                         separators=(",", ":")).encode("utf-8")
    if gzip_it:
        if not path.endswith(".gz"):
            path += ".gz"
        with _gzip.open(path, "wb", compresslevel=9) as fh:
            fh.write(payload)
    else:
        with open(path, "wb") as fh:
            fh.write(payload)
    return path
