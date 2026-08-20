"""Drive the VM's CPU sampler over the service protocol and normalise what
comes back.

`getCpuSamples` hands out a *per-call* function table: the integers in
`CpuSample.stack` index that call's `functions` list and nothing else. A
profiler that polls — and it must poll, because the VM's sample buffer is a
ring and a long scenario overruns it — therefore has to re-key every batch onto
a table of its own. That is most of what this module does.

The other half is turning a `@Function` into something a person can act on.
The VM's sampler resolves to a FUNCTION, never to a statement inside one, so
"which line" here means the line the function is DECLARED on, recovered from
the script's `tokenPosTable`. That is the same granularity
`PERFORMANCE_PROFILE.md` already speaks in when it cites `solver.dart:2517`,
and stating the limit is cheaper than having a reader assume otherwise.
"""

from __future__ import annotations

import bisect
import time
from dataclasses import dataclass, field

from vmservice import VmService, VmServiceError


@dataclass(frozen=True)
class Frame:
    """One resolved entry in the profiler's global function table."""
    key: str            # stable identity across polls
    name: str           # display name, e.g. "_rankAndPivots"
    owner: str          # class or library that owns it, "" when top-level
    kind: str           # Dart / Native / Stub / Tag / Collected
    url: str            # resolved script url, "" for native and stubs
    line: int           # declaration line, 0 when unknown

    @property
    def qualified(self) -> str:
        return f"{self.owner}.{self.name}" if self.owner else self.name

    @property
    def site(self) -> str:
        if not self.url:
            return ""
        short = self.url.rsplit("/", 1)[-1]
        return f"{short}:{self.line}" if self.line else short

    @property
    def label(self) -> str:
        return f"{self.qualified} ({self.site})" if self.site else self.qualified


@dataclass
class Sample:
    tid: int
    timestamp: int          # microseconds, VM monotonic clock
    isolate: str
    stack: tuple[int, ...]  # indices into SampleSet.frames, LEAF FIRST
    vm_tag: str = ""
    user_tag: str = ""
    truncated: bool = False


@dataclass
class SampleSet:
    """Everything one profiling session collected, in one place."""
    frames: list[Frame] = field(default_factory=list)
    samples: list[Sample] = field(default_factory=list)
    sample_period_us: int = 0
    max_stack_depth: int = 0
    pid: int = 0
    isolate_names: dict[str, str] = field(default_factory=dict)
    dropped_duplicates: int = 0
    meta: dict = field(default_factory=dict)

    def coverage(self, samples: list["Sample"] | None = None,
                 gap_factor: float = 3.0) -> dict:
        """How much of the elapsed time the sampler actually observed.

        A sampling profiler is only unbiased over the intervals it sampled. The
        VM keeps its samples in a ring whose size is fixed at startup
        (`sample_buffer_duration` cannot be changed at runtime), so a caller
        that polls too slowly loses whole seconds between polls — and loses
        them silently, because what comes back still looks like a profile.

        This measures it: any gap larger than `gap_factor` sample periods is
        counted as unobserved. The first capture taken with this tool had
        **19.8 s of a 31.0 s span** with no samples in it at all, and nothing in
        the output said so. It says so now, and `report`/`capture` print it
        above every table.
        """
        samples = self.samples if samples is None else samples
        by_track: dict[tuple[str, int], list[int]] = {}
        for s in samples:
            by_track.setdefault((s.isolate, s.tid), []).append(s.timestamp)
        period = self.sample_period_us or 1000
        span = 0
        gapped = 0
        gaps = 0
        eff: list[int] = []
        for ts in by_track.values():
            if len(ts) < 2:
                continue
            ts.sort()
            span += ts[-1] - ts[0]
            for a, b in zip(ts, ts[1:]):
                g = b - a
                if g > gap_factor * period:
                    gapped += g
                    gaps += 1
                else:
                    eff.append(g)
        eff.sort()
        return {
            "spanUs": span,
            "unobservedUs": gapped,
            "gaps": gaps,
            "observedFraction": (span - gapped) / span if span else 0.0,
            "effectivePeriodUs": eff[len(eff) // 2] if eff else 0,
            "nominalPeriodUs": period,
        }

    def sorted_samples(self) -> list[Sample]:
        return sorted(self.samples, key=lambda s: (s.isolate, s.tid, s.timestamp))

    def to_json(self) -> dict:
        return {
            "samplePeriodUs": self.sample_period_us,
            "maxStackDepth": self.max_stack_depth,
            "pid": self.pid,
            "sampleCount": len(self.samples),
            "droppedDuplicates": self.dropped_duplicates,
            "isolates": self.isolate_names,
            "meta": self.meta,
            "frames": [
                {"key": f.key, "name": f.name, "owner": f.owner, "kind": f.kind,
                 "url": f.url, "line": f.line}
                for f in self.frames
            ],
            "samples": [
                {"tid": s.tid, "ts": s.timestamp, "isolate": s.isolate,
                 "stack": list(s.stack), "vmTag": s.vm_tag,
                 "userTag": s.user_tag, "truncated": s.truncated}
                for s in self.sorted_samples()
            ],
        }

    @staticmethod
    def from_json(d: dict) -> "SampleSet":
        out = SampleSet(
            sample_period_us=d.get("samplePeriodUs", 0),
            max_stack_depth=d.get("maxStackDepth", 0),
            pid=d.get("pid", 0),
            isolate_names=d.get("isolates", {}),
            dropped_duplicates=d.get("droppedDuplicates", 0),
            meta=d.get("meta", {}),
        )
        out.frames = [Frame(key=f["key"], name=f["name"], owner=f.get("owner", ""),
                            kind=f.get("kind", ""), url=f.get("url", ""),
                            line=f.get("line", 0))
                      for f in d.get("frames", [])]
        out.samples = [Sample(tid=s["tid"], timestamp=s["ts"],
                              isolate=s.get("isolate", ""),
                              stack=tuple(s["stack"]), vm_tag=s.get("vmTag", ""),
                              user_tag=s.get("userTag", ""),
                              truncated=s.get("truncated", False))
                       for s in d.get("samples", [])]
        return out


class _ScriptLines:
    """tokenPos -> line, from a Script's `tokenPosTable`.

    The table is a list of `[line, tokenPos, column, tokenPos, column, ...]`.
    Flattening it once and bisecting is O(log n) per lookup instead of a scan
    per frame, which matters: a 25-second capture resolves tens of thousands of
    frames against a handful of scripts.
    """

    def __init__(self, table: list[list[int]]):
        pairs: list[tuple[int, int]] = []
        for row in table or []:
            if not row:
                continue
            line = row[0]
            for i in range(1, len(row) - 1, 2):
                pairs.append((row[i], line))
        pairs.sort()
        self._pos = [p for p, _ in pairs]
        self._line = [ln for _, ln in pairs]

    def line_for(self, token_pos: int) -> int:
        if not self._pos or token_pos is None or token_pos < 0:
            return 0
        i = bisect.bisect_right(self._pos, token_pos) - 1
        return self._line[i] if i >= 0 else 0


class Profiler:
    """One profiling session against one VM Service connection."""

    def __init__(self, service: VmService, *, verbose: bool = False):
        self.vm = service
        self.verbose = verbose
        self.set = SampleSet()
        self._frame_index: dict[str, int] = {}
        self._seen: set[tuple[str, int, int]] = set()
        self._scripts: dict[tuple[str, str], _ScriptLines] = {}
        self._script_uri: dict[tuple[str, str], str] = {}

    # -- setup ------------------------------------------------------------
    def isolates(self) -> list[dict]:
        vm = self.vm.call("getVM")
        out = list(vm.get("isolates", []))
        for iso in out:
            self.set.isolate_names[iso["id"]] = iso.get("name", iso["id"])
        self.set.pid = vm.get("pid", 0)
        self.set.meta.setdefault("vm", {
            "version": vm.get("version", ""),
            "hostCPU": vm.get("hostCPU", ""),
            "targetCPU": vm.get("targetCPU", ""),
            "operatingSystem": vm.get("operatingSystem", ""),
        })
        return out

    def flags(self) -> dict[str, str]:
        try:
            fl = self.vm.call("getFlagList")
        except VmServiceError:
            return {}
        return {f.get("name", ""): f.get("valueAsString", "")
                for f in fl.get("flags", [])}

    # Three VM flags decide whether a capture is worth anything, and two of
    # them are wrong by default under `flutter test`. This was found the hard
    # way — see perf/findings/S7-profiler.md §4 — and it is the single most
    # important thing in this file.
    #
    #   profile_vm            Flutter's test harness starts the VM with
    #                         --profile-vm, which makes the profiler collect
    #                         NATIVE stacks. The engine is built without frame
    #                         pointers, so the native unwinder gives up after
    #                         one frame: 47 % of the samples in the first real
    #                         capture came back as depth-1 `[Native]` stacks
    #                         with no Dart frame at all, and every one of them
    #                         was time the routine under test had actually
    #                         spent. Setting it false makes the profiler walk
    #                         the DART stack, which is the one being asked
    #                         about.
    #   profile_period        microseconds between samples.
    #   sample_buffer_duration  seconds of samples the VM keeps. It defaults to
    #                         0, which means a fixed small ring: a scenario
    #                         that runs for 30 s at 250 us overruns it between
    #                         polls and the capture silently loses most of what
    #                         it sampled.
    def configure(self, period_us: int | None, *, profile_vm: bool = False,
                  buffer_seconds: int | None = 60) -> dict:
        """Report the profiler's state, and set it up for a usable capture.

        `profiler` itself is usually not settable at runtime, so a VM started
        with the profiler off is a hard failure that must be reported rather
        than worked around. A capture taken with the sampler disabled is not a
        slow capture, it is an empty one.
        """
        before = self.flags()
        applied: dict[str, str] = {}
        refused: dict[str, str] = {}
        wanted = [("profile_vm", "true" if profile_vm else "false")]
        if period_us:
            wanted.append(("profile_period", str(int(period_us))))
        if buffer_seconds:
            wanted.append(("sample_buffer_duration", str(int(buffer_seconds))))
        for name, value in wanted:
            if before.get(name) == value:
                applied[name] = value
                continue
            try:
                # setFlag answers a REFUSAL with a successful RPC carrying an
                # Error object, not with a JSON-RPC error. Reading only the
                # transport result therefore reports every refusal as a
                # success, which is how the first two captures taken with this
                # tool came out believing they had turned profile_vm off.
                res = self.vm.call("setFlag", {"name": name, "value": value})
                if str(res.get("type", "")) == "Success":
                    applied[name] = value
                else:
                    refused[name] = str(res.get("message", res))
            except VmServiceError as exc:
                refused[name] = str(exc)
        after = self.flags()
        state = {
            "profiler": after.get("profiler", "unknown"),
            "profile_period": after.get("profile_period", "unknown"),
            "profile_vm": after.get("profile_vm", "unknown"),
            "sample_buffer_duration": after.get("sample_buffer_duration",
                                                "unknown"),
            "max_profile_depth": after.get("max_profile_depth", "unknown"),
            "requested": dict(wanted),
            "applied": applied,
            "refused": refused,
            "before": {k: before.get(k, "unknown") for k, _ in wanted},
        }
        self.set.meta["profilerFlags"] = state
        return state

    def clear(self, isolate_ids: list[str]) -> None:
        for iid in isolate_ids:
            try:
                self.vm.call("clearCpuSamples", {"isolateId": iid})
            except VmServiceError as exc:
                if self.verbose:
                    print(f"[profiler] clearCpuSamples({iid}): {exc}")

    def now_micros(self) -> int:
        return self.vm.call("getVMTimelineMicros").get("timestamp", 0)

    def wait_runnable(self, isolate_ids: list[str], timeout_s: float = 60.0) -> list[str]:
        """Block until each isolate is RUNNABLE, then hand the ids back.

        A VM started with `--pause-isolates-on-start` answers `getVM` with
        isolates that exist but are not yet runnable, and every request against
        one of those — `clearCpuSamples`, `resume` — comes back
        "Isolate must be runnable before this request is made". The resume
        therefore never lands, the program never starts, and the capture waits
        for a scenario that is not running. Poll `getIsolate().runnable` first.
        """
        deadline = time.monotonic() + timeout_s
        ready: list[str] = []
        pending = list(isolate_ids)
        while pending and time.monotonic() < deadline:
            still: list[str] = []
            for iid in pending:
                try:
                    iso = self.vm.call("getIsolate", {"isolateId": iid})
                except VmServiceError:
                    continue          # gone; nothing to wait for
                if iso.get("runnable"):
                    ready.append(iid)
                else:
                    still.append(iid)
            pending = still
            if pending:
                time.sleep(0.05)
        if pending and self.verbose:
            print(f"[profiler] isolates never became runnable: {pending}")
        return ready + pending

    def resume_all(self, isolate_ids: list[str]) -> None:
        """Resume anything sitting at a pause, which is how `--start-paused`
        hands the process over. Isolates that are not paused answer with an
        error that means 'nothing to do' — not a failure."""
        for iid in isolate_ids:
            try:
                self.vm.call("resume", {"isolateId": iid})
            except VmServiceError as exc:
                if self.verbose:
                    print(f"[profiler] resume({iid}): {exc}")

    # -- collection -------------------------------------------------------
    def poll(self, isolate_ids: list[str], origin_us: int, extent_us: int) -> int:
        """Fetch one window and merge it. Returns the number of NEW samples."""
        added = 0
        for iid in isolate_ids:
            try:
                res = self.vm.call("getCpuSamples", {
                    "isolateId": iid,
                    "timeOriginMicros": int(origin_us),
                    "timeExtentMicros": int(max(0, extent_us)),
                }, timeout=120.0)
            except VmServiceError as exc:
                msg = str(exc)
                if "Collected" in msg or "Sentinel" in msg or "expired" in msg:
                    continue          # isolate has gone away; not an error here
                if "profiler" in msg.lower() and "disabled" in msg.lower():
                    raise
                if self.verbose:
                    print(f"[profiler] getCpuSamples({iid}): {exc}")
                continue
            added += self._merge(iid, res)
        return added

    def _merge(self, isolate_id: str, res: dict) -> int:
        if res.get("samplePeriod"):
            self.set.sample_period_us = res["samplePeriod"]
        if res.get("maxStackDepth"):
            self.set.max_stack_depth = res["maxStackDepth"]
        if res.get("pid"):
            self.set.pid = res["pid"]

        local = [self._resolve(isolate_id, pf) for pf in res.get("functions", [])]
        added = 0
        for s in res.get("samples", []):
            stack = tuple(local[i] for i in s.get("stack", [])
                          if 0 <= i < len(local))
            # Identity is (isolate, thread, timestamp) and NOTHING ELSE.
            #
            # The stack must not be part of the key. Re-fetching a window that
            # has already been fetched can return the SAME sample with a WORSE
            # stack: a code object that has since been deoptimised or collected
            # comes back as `<unknown Dart function>` (kind `Collected`), and a
            # key that included the stack would admit that degraded copy as a
            # second, independent sample. It happened — 2257 samples in one
            # calibration run — and it moved a measured share by tens of points
            # in a direction that looked like unattributable overhead.
            #
            # First fetch wins, because the earliest fetch is the one taken
            # closest in time to the sample, when the VM still knew what the
            # code was.
            key = (isolate_id, s.get("tid", -1), s.get("timestamp", -1))
            if key in self._seen:
                self.set.dropped_duplicates += 1
                continue
            self._seen.add(key)
            self.set.samples.append(Sample(
                tid=s.get("tid", -1),
                timestamp=s.get("timestamp", -1),
                isolate=isolate_id,
                stack=stack,
                vm_tag=s.get("vmTag", "") or "",
                user_tag=s.get("userTag", "") or "",
                truncated=bool(s.get("truncated", False)),
            ))
            added += 1
        return added

    # -- function resolution ----------------------------------------------
    def _resolve(self, isolate_id: str, pf: dict) -> int:
        fn = pf.get("function") or {}
        name = fn.get("name") or "<unknown>"
        owner = ""
        o = fn.get("owner")
        if isinstance(o, dict):
            if o.get("type") in ("@Class", "Class"):
                owner = o.get("name", "") or ""
            elif o.get("type") in ("@Function", "Function"):
                owner = o.get("name", "") or ""
        kind = pf.get("kind") or fn.get("type") or ""
        url = pf.get("resolvedUrl") or ""
        line = 0
        loc = fn.get("location")
        if isinstance(loc, dict):
            script = loc.get("script") or {}
            sid = script.get("id")
            if sid:
                line = self._line_of(isolate_id, sid, loc.get("tokenPos", -1))
                if not url:
                    url = script.get("uri", "") or ""

        key = f"{kind}|{owner}|{name}|{url}|{line}"
        idx = self._frame_index.get(key)
        if idx is None:
            idx = len(self.set.frames)
            self._frame_index[key] = idx
            self.set.frames.append(
                Frame(key=key, name=name, owner=owner, kind=kind, url=url,
                      line=line))
        return idx

    def _line_of(self, isolate_id: str, script_id: str, token_pos: int) -> int:
        ck = (isolate_id, script_id)
        tbl = self._scripts.get(ck)
        if tbl is None:
            try:
                obj = self.vm.call("getObject", {"isolateId": isolate_id,
                                                 "objectId": script_id})
                tbl = _ScriptLines(obj.get("tokenPosTable", []))
                self._script_uri[ck] = obj.get("uri", "")
            except VmServiceError:
                tbl = _ScriptLines([])
            self._scripts[ck] = tbl
        return tbl.line_for(token_pos)


def collect(service: VmService, *, duration_s: float | None,
            poll_interval_s: float = 1.0, period_us: int | None = None,
            until=None, verbose: bool = False, resume: bool = True,
            profile_vm: bool = False, buffer_seconds: int | None = 60,
            max_wall_s: float = 1800.0) -> SampleSet:
    """Run one capture.

    `until` is a zero-argument predicate; when it returns True the capture
    stops. That is how a target that finishes on its own (a test process, an
    app that exits) ends the capture at the right moment instead of at an
    arbitrary wall-clock deadline. `duration_s` is the ceiling in either case.
    """
    p = Profiler(service, verbose=verbose)
    isolates = p.isolates()
    ids = [i["id"] for i in isolates]
    state = p.configure(period_us, profile_vm=profile_vm,
                        buffer_seconds=buffer_seconds)
    if str(state.get("profiler", "")).lower() in ("false", "0"):
        raise VmServiceError(
            "the VM's CPU profiler is DISABLED (--no-profiler). Nothing can be "
            "sampled from this process; relaunch it with the profiler on.")

    if resume:
        ids = p.wait_runnable(ids)
    p.clear(ids)
    t0 = p.now_micros()
    p.set.meta["captureStartMicros"] = t0
    if resume:
        p.resume_all(ids)

    started = time.monotonic()
    last_origin = t0
    overlap_us = int(poll_interval_s * 2 * 1_000_000)
    reason = "duration"
    while True:
        time.sleep(poll_interval_s)
        try:
            # Re-read the isolate list every poll: `flutter test` spawns the
            # test's isolate AFTER the service comes up, so a list taken once
            # at connect time misses the only isolate anybody wants to profile.
            ids = [i["id"] for i in p.isolates()]
            now = p.now_micros()
            origin = max(t0, last_origin - overlap_us)
            p.poll(ids, origin, now - origin + 1)
            last_origin = now
        except VmServiceError as exc:
            # The target went away mid-capture. That is a normal end for a
            # process that finishes on its own, and it must NOT throw away the
            # samples already merged — a profiler that loses its capture at the
            # finish line is the failure mode this whole session exists to
            # avoid (PERFORMANCE_PROFILE.md §13.1).
            p.set.meta["connectionEnded"] = str(exc)
            reason = "connection-closed"
            break

        done = bool(until and until())
        elapsed = time.monotonic() - started
        # A hard ceiling even when neither a duration nor a predicate fires.
        # Without one, a target that never announces and never exits leaves the
        # capture spinning until something outside kills it, and the samples
        # already merged are lost with it.
        if elapsed >= max_wall_s:
            reason = "max-wall"
            break
        if done or (duration_s is not None and elapsed >= duration_s):
            # One last INCREMENTAL sweep. The final poll is the one that
            # matters most — it holds the tail of the scenario — but it must
            # cover only what the previous poll could not reach: re-fetching
            # the whole run at the end would pull back thousands of samples
            # whose code objects have since been collected, and the merge is
            # right to reject them but should not have to.
            try:
                now = p.now_micros()
                origin = max(t0, last_origin - overlap_us)
                p.poll(ids, origin, now - origin + 1)
                p.set.meta["captureEndMicros"] = now
            except VmServiceError:
                pass
            reason = "target-finished" if done else "duration"
            break

    p.set.meta["captureWallSeconds"] = round(time.monotonic() - started, 3)
    p.set.meta["stoppedBecause"] = reason
    return p.set
