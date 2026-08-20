#!/usr/bin/env python3
"""tools/profiler — the sampling profiler, plan item A4.

    PERFORMANCE_PROFILE.md §15.5:
      "The sampling profiler (VM Service `getCpuSamples` -> Perfetto), plan
       item A4. The suite says which *operation* costs what; a profiler says
       which *line*. ... Still the largest unbuilt piece of apparatus."

Three subcommands:

  capture   attach to a VM Service, sample it, write a trace and an attribution
  report    re-read a capture and re-print the attribution (no VM needed)
  validate  run a capture and check it against a KNOWN attribution

`validate` is the one that decides whether anything else here is worth reading.
An instrument that cannot reproduce a cost split somebody already measured by
other means cannot be trusted on a split nobody has measured — so the known
splits live in `expectations/` as data, and every capture can be checked
against them by a command that exits non-zero when it disagrees.

Everything is stdlib Python: `ci/` has no dependency file and no runner here
installs one.
"""

from __future__ import annotations

import argparse
import gzip
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import attribution as attrib          # noqa: E402
import perfetto                        # noqa: E402
import samples as sampling             # noqa: E402
import targets as tgt                  # noqa: E402
from samples import SampleSet          # noqa: E402
from vmservice import VmService, ws_url_from  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))


# ---------------------------------------------------------------------------
# scenario materialisation
# ---------------------------------------------------------------------------

def materialise(project: str, scenario: str, n: int, repeats: int,
                warmups: int, warmup_n: int, timeout_min: int,
                linger_ms: int) -> str:
    """Write the driver into the Flutter package's gitignored build tree.

    It has to live inside the package for `package:prototype/...` to resolve,
    and it must not live in `test/` — a file there would join every
    contributor's `flutter test` run and add half a minute to it. `build/` is
    already ignored by frontend/.gitignore, so nothing generated here can be
    committed by accident.
    """
    tmpl = open(os.path.join(HERE, "scenarios", "host_scenario.dart.tmpl")).read()
    src = (tmpl
           .replace("{{SCENARIO}}", scenario)
           .replace("{{N}}", str(n))
           .replace("{{REPEATS}}", str(repeats))
           .replace("{{WARMUPS}}", str(warmups))
           .replace("{{WARMUP_N}}", str(warmup_n))
           .replace("{{TIMEOUT_MIN}}", str(timeout_min))
           .replace("{{LINGER_MS}}", str(linger_ms)))
    outdir = os.path.join(project, "build", "profiler")
    os.makedirs(outdir, exist_ok=True)
    path = os.path.join(outdir, f"{scenario}_{n}_test.dart")
    with open(path, "w") as fh:
        fh.write(src)
    return path


# ---------------------------------------------------------------------------
# capture
# ---------------------------------------------------------------------------

def build_target(args) -> tgt.Target:
    if args.target == "attach":
        if not args.uri:
            raise SystemExit("--target attach needs --uri")
        return tgt.AttachTarget(args.uri)
    if args.target == "flutter-test":
        project = os.path.abspath(args.project)
        dart_file = args.dart_file
        if not dart_file:
            if not args.scenario:
                raise SystemExit("--target flutter-test needs --scenario or --dart-file")
            dart_file = materialise(project, args.scenario, args.n, args.repeats,
                                    args.warmups, args.warmup_n, args.timeout_min,
                                    args.linger_ms)
        rel = os.path.relpath(os.path.abspath(dart_file), project)
        return tgt.FlutterTestTarget(project, rel, flutter=args.flutter_bin)
    if args.target == "simulator":
        if not (args.udid and args.bundle_id):
            raise SystemExit("--target simulator needs --udid and --bundle-id")
        return tgt.SimulatorTarget(args.udid, args.bundle_id,
                                   args=args.app_args or [])
    if args.target == "dart":
        dart_file = args.dart_file
        if not dart_file and args.scenario:
            dart_file = os.path.join(HERE, "scenarios", f"{args.scenario}.dart")
        if not dart_file:
            raise SystemExit("--target dart needs --dart-file or --scenario")
        return tgt.DartTarget(dart_file, cwd=args.project,
                              dart=args.dart_bin or "dart",
                              args=[str(a) for a in (args.dart_args or [])])
    raise SystemExit(f"unknown target {args.target}")


def capture(args) -> tuple[SampleSet, tgt.Target]:
    target = build_target(args)
    target.start()
    print(f"[profiler] target: {target.name}", flush=True)
    uri = target.uri(args.connect_timeout)
    ws = ws_url_from(uri)
    print(f"[profiler] vm service: {ws}", flush=True)

    svc = VmService(ws, timeout=args.rpc_timeout)
    try:
        ss = sampling.collect(
            svc,
            duration_s=args.duration,
            poll_interval_s=args.poll_interval,
            period_us=args.period_us,
            until=_stop_predicate(args, target),
            verbose=args.verbose,
            resume=not args.no_resume,
            profile_vm=args.profile_vm,
            buffer_seconds=args.buffer_seconds,
            max_wall_s=args.max_wall,
        )
    finally:
        try:
            svc.close()
        except Exception:                              # noqa: BLE001
            pass
        if args.target != "attach":
            target.stop()

    ss.meta["target"] = target.name
    ss.meta["targetReturnCode"] = target.returncode
    ss.meta["capturedAtUtc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    ss.meta["gitSha"] = _git("rev-parse", "HEAD")
    ss.meta["gitRef"] = _git("rev-parse", "--abbrev-ref", "HEAD")
    for line in target.log.splitlines():
        if line.startswith("PROFILER_SCENARIO_RESULT"):
            ss.meta["scenarioResult"] = line.strip()
            fields: dict[str, float | str] = {}
            for tok in line.split()[1:]:
                if "=" not in tok:
                    continue
                k, v = tok.split("=", 1)
                try:
                    fields[k] = float(v)
                except ValueError:
                    fields[k] = v
            ss.meta["scenarioFields"] = fields
    return ss, target


def _stop_predicate(args, target: tgt.Target):
    """When to stop sampling.

    A target that prints `PROFILER_SCENARIO_RESULT` has told us the measured
    region is over, and that is a better stop signal than process exit: it
    happens while the VM is still alive, so the final full-window sweep still
    has somebody to ask. Process exit remains the backstop.
    """
    if args.target in ("attach", "simulator"):
        return None

    def done() -> bool:
        if "PROFILER_SCENARIO_RESULT" in target.log:
            return True
        return target.finished()

    return done


def _git(*a: str) -> str:
    try:
        return subprocess.check_output(["git", *a], cwd=REPO,
                                       text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:                                   # noqa: BLE001
        return ""


# ---------------------------------------------------------------------------
# output
# ---------------------------------------------------------------------------

def _load_buckets(spec: list[str] | None) -> list[tuple[str, list[str]]]:
    """`--bucket name=pat1,pat2` repeated, in the order given."""
    out: list[tuple[str, list[str]]] = []
    for s in spec or []:
        if "=" not in s:
            raise SystemExit(f"--bucket wants name=patterns, got {s!r}")
        name, pats = s.split("=", 1)
        out.append((name, [p for p in pats.split(",") if p]))
    return out


def write_outputs(ss: SampleSet, outdir: str, args, target_log: str = "") -> dict:
    os.makedirs(outdir, exist_ok=True)

    with gzip.open(os.path.join(outdir, "samples.json.gz"), "wt",
                   compresslevel=9) as fh:
        json.dump(ss.to_json(), fh, separators=(",", ":"))
    trace_path = perfetto.write_trace(ss, os.path.join(outdir, "trace.json"),
                                      gzip_it=True)
    with open(os.path.join(outdir, "stacks.folded.txt"), "w") as fh:
        fh.write(perfetto.to_folded(ss))
    if target_log:
        with open(os.path.join(outdir, "capture.log"), "w") as fh:
            fh.write(target_log)

    dart_only = not getattr(args, "include_native_only", False)
    sel = attrib.select(ss, tag=args.tag, dart_only=dart_only)
    if args.tag and not sel:
        print(f"[profiler] WARNING: no samples carry userTag {args.tag!r}; "
              f"falling back to every sample with a Dart frame", flush=True)
        sel = attrib.select(ss, dart_only=dart_only)
    cen = attrib.census(ss, attrib.select(ss, tag=args.tag) if args.tag
                        else ss.samples)

    report: list[str] = []
    report.append("# CPU sample attribution")
    report.append("")
    report.append(f"* capture: `{ss.meta.get('capturedAtUtc','')}` "
                  f"target `{ss.meta.get('target','')}` "
                  f"sha `{(ss.meta.get('gitSha') or '')[:12]}`")
    report.append(f"* sample period: **{ss.sample_period_us} us**, "
                  f"max stack depth {ss.max_stack_depth}, "
                  f"total samples {len(ss.samples)} "
                  f"(duplicates merged away: {ss.dropped_duplicates})")
    if args.tag:
        report.append(f"* selection: userTag `{args.tag}` -> **{len(sel)}** samples")
    if ss.meta.get("scenarioResult"):
        report.append(f"* scenario: `{ss.meta['scenarioResult']}`")
    flags = ss.meta.get("profilerFlags", {})
    if flags:
        report.append(
            f"* VM profiler: `profiler={flags.get('profiler')}` "
            f"`profile_period={flags.get('profile_period')}` "
            f"`profile_vm={flags.get('profile_vm')}` "
            f"`sample_buffer_duration={flags.get('sample_buffer_duration')}` "
            f"`max_profile_depth={flags.get('max_profile_depth')}`")
        if str(flags.get("profile_vm", "")).lower() == "true":
            report.append("* **WARNING: `profile_vm=true`.** The profiler is "
                          "collecting native stacks; on an engine built "
                          "without frame pointers most samples come back one "
                          "frame deep and cannot be attributed to any Dart "
                          "function. Shares below are not trustworthy.")
    report.append("")
    report.append("A sampling profiler measures a **share**, not a duration. "
                  "Milliseconds below are `samples x period` and are an "
                  "estimate; the sample counts are the measurement.")
    cov = ss.coverage()
    report.append(
        f"* coverage: the sampler observed **{100*cov['observedFraction']:.1f} %** "
        f"of the {cov['spanUs']/1e6:.2f} s it was attached for "
        f"({cov['gaps']} gaps wider than 3 periods, "
        f"{cov['unobservedUs']/1e6:.2f} s unobserved); "
        f"effective period {cov['effectivePeriodUs']} us against a nominal "
        f"{cov['nominalPeriodUs']} us")
    if cov["observedFraction"] < 0.75:
        report.append("* **WARNING: under a quarter of the elapsed time is "
                      "missing from this capture.** Poll more often "
                      "(`--poll-interval`); the VM's sample ring is dropping "
                      "samples between calls and the shares below are shares "
                      "of what survived, not of what ran.")
    report.append("")
    report.append(attrib.census_markdown(cen))
    report.append(attrib.markdown(
        ss, top=args.top, samples=sel,
        title=("Flat profile — samples with a Dart frame" if dart_only
               else "Flat profile — every sample")))

    machine: dict = {"meta": ss.meta, "samplesSelected": len(sel),
                     "samplePeriodUs": ss.sample_period_us,
                     "census": cen, "dartOnly": dart_only,
                     "coverage": cov}
    buckets = _load_buckets(args.bucket)
    if args.root:
        res = attrib.within(ss, args.root, buckets, sel)
        report.append(attrib.within_markdown(
            res, ss, title=f"Inside `{args.root}`"))
        machine["within"] = res
    machine["flat"] = [
        {"label": r.label, "self": r.self_n, "total": r.total_n,
         "url": r.frame.url if r.frame else "", "line": r.frame.line if r.frame else 0}
        for r in attrib.flat(ss, sel)[:max(args.top, 60)]
    ]

    with open(os.path.join(outdir, "attribution.md"), "w") as fh:
        fh.write("\n".join(report) + "\n")
    with open(os.path.join(outdir, "attribution.json"), "w") as fh:
        json.dump(machine, fh, indent=2, sort_keys=True)

    with open(os.path.join(outdir, "RUN.txt"), "w") as fh:
        fh.write(
            f"produced_by: tools/profiler/profile.py\n"
            f"captured:    {ss.meta.get('capturedAtUtc','')}\n"
            f"sha:         {ss.meta.get('gitSha','')}\n"
            f"ref:         {ss.meta.get('gitRef','')}\n"
            f"target:      {ss.meta.get('target','')}\n"
            f"samples:     {len(ss.samples)}\n"
            f"period_us:   {ss.sample_period_us}\n"
            f"trace:       {os.path.basename(trace_path)} "
            f"(Chrome JSON trace format; open at ui.perfetto.dev)\n")

    print("\n".join(report))
    print(f"[profiler] wrote {outdir}/: samples.json.gz trace.json.gz "
          f"stacks.folded.txt attribution.md attribution.json RUN.txt",
          flush=True)
    return machine


# ---------------------------------------------------------------------------
# validate
# ---------------------------------------------------------------------------

def run_validate(args) -> int:
    spec = json.load(open(args.expectation))
    print(f"[profiler] expectation: {spec['name']}")
    print(f"[profiler] source of truth: {spec['source']}")

    ok = True
    results = []
    for case in spec["cases"]:
        cargs = argparse.Namespace(**vars(args))
        for k, v in case.get("capture", {}).items():
            # `$VAR` in a capture override is expanded from the environment, so
            # one expectation file can name two working trees (the code before
            # a change and the code after it) without hard-coding either path.
            setattr(cargs, k, os.path.expandvars(v) if isinstance(v, str) else v)
        cargs.tag = case.get("tag", args.tag)
        cargs.root = case["root"]
        cargs.bucket = [f"{k}={','.join(v)}"
                        for k, v in case["buckets"].items()]
        outdir = os.path.join(args.out, case["id"])
        print(f"\n[profiler] === case {case['id']}: {case['what']}")

        ss, target = capture(cargs)
        machine = write_outputs(ss, outdir, cargs, target.log)
        within = machine.get("within", {})
        n_root = within.get("samplesInRoot", 0)

        case_ok = True
        checks = []
        if n_root < case.get("minSamples", 200):
            case_ok = False
            checks.append({
                "check": "sample count", "ok": False,
                "detail": f"{n_root} samples inside {case['root']}, "
                          f"need >= {case.get('minSamples', 200)}"})
        else:
            checks.append({"check": "sample count", "ok": True,
                           "detail": f"{n_root} samples inside {case['root']}"})

        # The ground truth the profiled run printed for itself.
        measured = ss.meta.get("scenarioFields", {})
        if "maxOther" in case:
            ob = within.get("buckets", {}).get("other", {})
            oshare = ob.get("share", 1.0)
            good = oshare <= float(case["maxOther"])
            case_ok = case_ok and good
            checks.append({
                "check": "unattributed share", "ok": good,
                "detail": (f"`other` is {100*oshare:.2f} % of the root "
                           f"(cap {100*float(case['maxOther']):.0f} %) — a split "
                           f"is not quotable from a capture with a large "
                           f"unattributed remainder")})

        for name, exp in case.get("expectMeasured", {}).items():
            b = within.get("buckets", {}).get(name)
            field = exp["field"]
            if b is None or field not in measured:
                case_ok = False
                checks.append({"check": f"{name} vs measured {field}",
                               "ok": False,
                               "detail": "bucket or ground-truth field missing"})
                continue
            truth = float(measured[field])
            got = b["share"]
            # A ground truth stated as "elimination as a fraction of the two
            # timed phases" has to be compared against the same fraction, not
            # against a share of every sample in the root — the root also holds
            # the fixture's own setup, which neither Stopwatch was running for.
            norm = exp.get("normaliseAgainst")
            if norm:
                denom = sum(within["buckets"].get(x, {}).get("samples", 0)
                            for x in norm)
                got = (b["samples"] / denom) if denom else 0.0
            tol = float(exp.get("absTolerance", 0.05))
            good = abs(got - truth) <= tol
            case_ok = case_ok and good
            checks.append({
                "check": f"{name} vs measured {field}", "ok": good,
                "detail": (f"profiler {100*got:.2f} % "
                           f"[{100*b['ci95'][0]:.2f}, {100*b['ci95'][1]:.2f}] "
                           f"vs the run's own Stopwatch {100*truth:.2f} % "
                           f"(|delta| {100*abs(got-truth):.2f} pp, "
                           f"tolerance {100*tol:.1f} pp)")})

        for name, exp in case.get("expect", {}).items():
            b = within.get("buckets", {}).get(name)
            if b is None:
                case_ok = False
                checks.append({"check": name, "ok": False,
                               "detail": "bucket missing from the capture"})
                continue
            lo, hi = exp["shareRange"]
            got = b["share"]
            good = lo <= got <= hi
            case_ok = case_ok and good
            checks.append({
                "check": name, "ok": good,
                "detail": (f"share {100*got:.2f} % "
                           f"[{100*b['ci95'][0]:.2f}, {100*b['ci95'][1]:.2f}] "
                           f"vs registered [{100*lo:.1f}, {100*hi:.1f}] %"
                           f"  (known: {exp.get('known','')})")})

        for c in checks:
            print(f"    [{'PASS' if c['ok'] else 'FAIL'}] {c['check']}: {c['detail']}")
        ok = ok and case_ok
        results.append({"id": case["id"], "ok": case_ok, "checks": checks,
                        "within": within})

    summary = {"name": spec["name"], "source": spec["source"],
               "ok": ok, "cases": results,
               "at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
               "sha": _git("rev-parse", "HEAD")}
    os.makedirs(args.out, exist_ok=True)
    with open(os.path.join(args.out, "validation.json"), "w") as fh:
        json.dump(summary, fh, indent=2, sort_keys=True)
    with open(os.path.join(args.out, "validation.md"), "w") as fh:
        fh.write(_validation_md(summary, spec))

    print(f"\n[profiler] VALIDATION: {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


def _validation_md(summary: dict, spec: dict) -> str:
    out = [f"# Profiler validation — {summary['name']}", "",
           f"**{'PASS' if summary['ok'] else 'FAIL'}** at "
           f"`{summary['sha'][:12]}`, {summary['at']}", "",
           f"Source of truth: {spec['source']}", "",
           spec.get("why", ""), ""]
    for c in summary["cases"]:
        out.append(f"## {c['id']} — {'PASS' if c['ok'] else 'FAIL'}")
        out.append("")
        out.append("| check | verdict | detail |")
        out.append("| :--- | :--- | :--- |")
        for ch in c["checks"]:
            out.append(f"| {ch['check']} | {'PASS' if ch['ok'] else 'FAIL'} | "
                       f"{ch['detail']} |")
        out.append("")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# cli
# ---------------------------------------------------------------------------

def add_capture_args(p: argparse.ArgumentParser) -> None:
    p.add_argument("--target", default="flutter-test",
                   choices=["flutter-test", "attach", "simulator", "dart"])
    p.add_argument("--uri", help="VM Service URI for --target attach")
    p.add_argument("--project", default=os.path.join(REPO, "frontend"))
    p.add_argument("--dart-file")
    p.add_argument("--scenario",
                   choices=["analyze", "solve", "known_split"])
    p.add_argument("--n", type=int, default=1024)
    p.add_argument("--repeats", type=int, default=1)
    p.add_argument("--warmups", type=int, default=2)
    p.add_argument("--warmup-n", type=int, default=128)
    p.add_argument("--timeout-min", type=int, default=30)
    p.add_argument("--linger-ms", type=int, default=4000,
                   help="how long the generated driver stays alive after the "
                        "measured region, so the final sweep has a live VM")
    p.add_argument("--flutter-bin")
    p.add_argument("--dart-bin")
    p.add_argument("--dart-args", nargs="*",
                   help="arguments passed to the --target dart script")
    p.add_argument("--udid", help="simulator UDID for --target simulator")
    p.add_argument("--bundle-id")
    p.add_argument("--app-args", nargs="*")
    p.add_argument("--duration", type=float, default=None,
                   help="seconds; ceiling for a self-terminating target, "
                        "and the whole capture for one that is not")
    p.add_argument("--poll-interval", type=float, default=0.2,
                   help="seconds between getCpuSamples calls. The VM's sample "
                        "ring is small and cannot be resized at runtime, so a "
                        "slow poll loses whole seconds — see SampleSet.coverage")
    p.add_argument("--period-us", type=int, default=250,
                   help="requested VM profile_period; the VM may refuse")
    p.add_argument("--connect-timeout", type=float, default=240.0)
    p.add_argument("--rpc-timeout", type=float, default=180.0)
    p.add_argument("--no-resume", action="store_true")
    p.add_argument("--profile-vm", action="store_true",
                   help="collect NATIVE stacks instead of Dart ones. Off by "
                        "default and it should stay off on any engine built "
                        "without frame pointers — see samples.py's note.")
    p.add_argument("--max-wall", type=float, default=1800.0,
                   help="hard ceiling on a capture, in seconds")
    p.add_argument("--buffer-seconds", type=int, default=60,
                   help="seconds of samples the VM keeps (sample_buffer_duration)")
    p.add_argument("--tag", default="profiler.measure",
                   help="restrict attribution to samples carrying this userTag")
    p.add_argument("--root", help="attribute the time spent inside this function")
    p.add_argument("--bucket", action="append",
                   help="name=pattern[,pattern...] — repeatable, order matters")
    p.add_argument("--top", type=int, default=25)
    p.add_argument("--include-native-only", action="store_true",
                   help="keep samples with no Dart frame in the attribution "
                        "tables (they are always kept in the trace)")
    p.add_argument("--verbose", action="store_true")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="profile.py", description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("capture", help="sample a VM and write a trace")
    add_capture_args(c)
    c.add_argument("--out", required=True)

    r = sub.add_parser("report", help="re-print an attribution from a capture")
    r.add_argument("samples", help="samples.json or samples.json.gz")
    r.add_argument("--tag", default=None)
    r.add_argument("--root")
    r.add_argument("--bucket", action="append")
    r.add_argument("--top", type=int, default=25)
    r.add_argument("--include-native-only", action="store_true")
    r.add_argument("--out")

    v = sub.add_parser("validate", help="check a capture against a known split")
    add_capture_args(v)
    v.add_argument("--expectation", required=True)
    v.add_argument("--out", required=True)

    args = ap.parse_args(argv)

    if args.cmd == "capture":
        ss, target = capture(args)
        write_outputs(ss, args.out, args, target.log)
        return 0

    if args.cmd == "report":
        opener = gzip.open if args.samples.endswith(".gz") else open
        with opener(args.samples, "rt") as fh:
            ss = SampleSet.from_json(json.load(fh))
        sel = attrib.select(ss, tag=args.tag,
                            dart_only=not args.include_native_only)
        print(attrib.census_markdown(attrib.census(ss)))
        print(attrib.markdown(ss, top=args.top, samples=sel, title="Flat profile"))
        if args.root:
            res = attrib.within(ss, args.root, _load_buckets(args.bucket), sel)
            print(attrib.within_markdown(res, ss, title=f"Inside `{args.root}`"))
        if args.out:
            write_outputs(ss, args.out, args)
        return 0

    if args.cmd == "validate":
        return run_validate(args)

    return 2


if __name__ == "__main__":
    sys.exit(main())
