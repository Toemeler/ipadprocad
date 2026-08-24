// Catalogue scenario 18 — the thirty-minute session, and where the footprint
// goes.
//
// WHY THIS EXISTS
// ---------------
// Every other tier in this suite answers "what does one operation cost". None
// of them can answer "what happens over an hour", because none of them runs
// for one. The longest capture this branch has taken is 293 seconds
// (PERFORMANCE_PROFILE 3.4), and 293 seconds of a leak that costs 4 KB per
// rebuild is 4 KB per rebuild times not-very-many — invisible. Thirty minutes
// of it is not.
//
// That matters more here than in most applications, because the one crash this
// project has from the field was a `phys_footprint` kill, and every device run
// since has had 3.4-3.9 GB of headroom. The suite has therefore never observed
// the failure mode it was built to explain. Low Power Mode, the proxy this
// branch uses for weaker hardware, says nothing about memory at all, and 3.5
// established that it UNDER-represents the penalty on memory-bound paths.
// Duration is the one axis left that can be driven from inside the app.
//
// THE SLOPE IS THE RESULT
// -----------------------
// No single footprint reading means anything. 1233 MB after a suite and
// 1325 MB before it (8.5) are the same measurement of two different moments.
// What a leak is, is a TREND: a quantity that rises with time under work that
// does not change. So this tier runs one fixed cycle of work over and over,
// samples the machine at a fixed cadence, and fits a line. The reported
// numbers are slopes and their uncertainty, and the raw series ships beside
// them so a reader can re-fit it.
//
// AND THE FLOOR IS PART OF THE RESULT
// -----------------------------------
// "No leak detected" is not a finding unless it comes with the smallest leak
// that WOULD have been detected. Every trend here is published with the
// half-width of its own 95% interval, in the same units, as
// `*.floorKBPerHour`: a slope below its floor is indistinguishable from zero
// on this run, and a run whose floor is 200 MB/h has proved nothing about a
// 50 MB/h leak. Both numbers or neither.
//
// THE INSTRUMENT IS CALIBRATED AGAINST A KNOWN LEAK
// -------------------------------------------------
// A leak detector that has never seen a leak is an assertion. [soakLeakBytes]
// makes one to order: the soak retains a fixed number of bytes per cycle, the
// fit has to recover the rate it was given, and `s10_soak_test.dart` checks
// that it does. That is a differential check in the sense of
// OPTIMIZATION_PLAN_2 1.4 — the claim is proved in the same process on the
// same machine, against no recorded constant at all.
//
// WHAT IT DOES NOT DO
// -------------------
// It does not decide whether a rise is a leak. A footprint that rises and then
// gives the memory back at the end of the run is a heap reaching its working
// size; one that does not is a leak. The tier therefore ends with a SETTLE
// phase — the same sampling with no work at all — and publishes what came
// back. The rule is written down in the report; the adjudication is the
// reader's.
//
// OPT-IN ONLY, AND MORE SO THAN THE STRESS TIER
// ---------------------------------------------
// Thirty minutes. Type `soak` in the bug description. `memory`, separately,
// runs the short memory-attribution family without the wait.
import 'dart:io' show File, ProcessInfo;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'ffi/occt_engine.dart';
import 'gear.dart';
import 'log.dart';
import 'perf.dart';
import 'perf_scenarios.dart'
    show PerfScenario, constraintFixture, gearFixture, ringProfile,
        sketchFixture;
import 'perf_scenarios_kernel.dart' show arcRing;
import 'solver.dart';

// ---------------------------------------------------------------------------
// The fit
// ---------------------------------------------------------------------------

/// Ordinary least squares of y on x, with the uncertainty of the slope.
///
/// Linear, not log-log: the ramp tier fits exponents because a COST curve's
/// shape is the question there; here the question is a RATE, and a rate is a
/// slope in the units it is measured in.
///
/// [se] is the standard error of [slope]; [halfWidth] is 1.96 times it, which
/// is what `ci/perf_profile.py` uses for every interval in the profile. Keeping
/// the same convention means an interval printed here and an interval printed
/// there mean the same thing.
@immutable
class SoakTrend {
  const SoakTrend(this.n, this.slope, this.intercept, this.r2, this.se);

  /// The empty fit — fewer than two points, or no spread in x.
  static const none = SoakTrend(0, 0, 0, 0, 0);

  final int n;

  /// Units of y per unit of x.
  final double slope;
  final double intercept;

  /// Coefficient of determination, or 0 when y never varied.
  final double r2;

  /// Standard error of [slope]. Zero when N < 3 or the fit is exact.
  final double se;

  /// Half the 95% interval, in the units of [slope].
  double get halfWidth => 1.96 * se;

  /// True when the interval excludes zero — i.e. this run can tell the slope
  /// apart from no slope at all. A false here is NOT evidence of no trend; it
  /// is evidence that [halfWidth] is the smallest trend this run could see.
  bool get resolved => se > 0 && slope.abs() > halfWidth;

  Map<String, Object?> toJson() => {
        'n': n,
        'slope': slope,
        'intercept': intercept,
        'r2': r2,
        'se': se,
        'halfWidth': halfWidth,
        'resolved': resolved,
      };
}

/// Fits [ys] against [xs]. Pairs where either value is non-finite are dropped,
/// which is how a sample taken on a platform with no native probe (-1, by
/// convention here) is kept out of the fit rather than dragging it.
SoakTrend fitSoakTrend(List<double> xs, List<double> ys) {
  final px = <double>[], py = <double>[];
  for (var i = 0; i < xs.length && i < ys.length; i++) {
    if (!xs[i].isFinite || !ys[i].isFinite) continue;
    px.add(xs[i]);
    py.add(ys[i]);
  }
  final n = px.length;
  if (n < 2) return SoakTrend.none;
  var mx = 0.0, my = 0.0;
  for (var i = 0; i < n; i++) {
    mx += px[i];
    my += py[i];
  }
  mx /= n;
  my /= n;
  var sxx = 0.0, sxy = 0.0;
  for (var i = 0; i < n; i++) {
    sxx += (px[i] - mx) * (px[i] - mx);
    sxy += (px[i] - mx) * (py[i] - my);
  }
  if (sxx <= 0) return SoakTrend.none;
  final k = sxy / sxx;
  final b = my - k * mx;
  var ssRes = 0.0, ssTot = 0.0;
  for (var i = 0; i < n; i++) {
    final e = py[i] - (k * px[i] + b);
    ssRes += e * e;
    ssTot += (py[i] - my) * (py[i] - my);
  }
  final r2 = ssTot > 0 ? 1 - ssRes / ssTot : 0.0;
  final se = (n > 2 && ssRes > 0) ? math.sqrt(ssRes / (n - 2) / sxx) : 0.0;
  return SoakTrend(n, k, b, r2, se);
}

// ---------------------------------------------------------------------------
// One probe point
// ---------------------------------------------------------------------------

/// Absent, for every integer field below. Chosen over null so the series is a
/// rectangle in JSON and so [fitSoakTrend] can drop it by one rule.
const int soakAbsent = -1;

/// The machine, and the app, at one moment of the soak.
@immutable
class SoakSample {
  const SoakSample({
    required this.phase,
    required this.minutes,
    required this.cycles,
    required this.dartRssMB,
    required this.footprintMB,
    required this.residentMB,
    required this.availableMB,
    required this.internalMB,
    required this.compressedMB,
    required this.deviceMB,
    required this.externalMB,
    required this.thermal,
    required this.frames,
    required this.jank,
    required this.lagP95Ms,
    required this.logKB,
  });

  /// `work` or `settle` — the settle samples are fitted separately, because
  /// their whole purpose is to be a different regime.
  final String phase;
  final double minutes;
  final int cycles;

  /// `ProcessInfo.currentRss`, which is what Dart can see anywhere.
  final int dartRssMB;

  /// `phys_footprint` — the quantity iOS terminates on. [soakAbsent] off iOS.
  final int footprintMB;
  final int residentMB;
  final int availableMB;

  /// The footprint decomposition (see `PerfProbe.swift`): dirty anonymous
  /// pages, the compressor's share of them, IOKit/device mappings, and
  /// file-backed pages. [soakAbsent] where the kernel did not supply them.
  final int internalMB, compressedMB, deviceMB, externalMB;

  /// 0 nominal .. 3 critical.
  final int thermal;

  /// Cumulative frame counters at this moment, from [Perf]. They advance only
  /// while something is actually rendering.
  final int frames, jank;

  /// 95th percentile of how late this window's event-loop wakeups were. Always
  /// available, including headless, which is why it exists next to [jank].
  final double lagP95Ms;

  /// Size of the event log on disk. Sampled because the app logs per solve,
  /// and a half-hour session therefore writes a file that grows all run: it is
  /// worth knowing how big, and worth being able to show that its pages are
  /// file-backed (`externalMB`) and so are NOT charged to the footprint.
  final int logKB;

  double get footprintOverRss =>
      (footprintMB > 0 && residentMB > 0) ? footprintMB / residentMB : double.nan;

  Map<String, Object?> toJson() => {
        'phase': phase,
        'minutes': minutes,
        'cycles': cycles,
        'dartRssMB': dartRssMB,
        'footprintMB': footprintMB,
        'residentMB': residentMB,
        'availableMB': availableMB,
        'internalMB': internalMB,
        'compressedMB': compressedMB,
        'deviceMB': deviceMB,
        'externalMB': externalMB,
        'thermal': thermal,
        'frames': frames,
        'jank': jank,
        'lagP95Ms': lagP95Ms,
        'logKB': logKB,
      };
}

int _rssMB() {
  try {
    return ProcessInfo.currentRss ~/ (1024 * 1024);
  } catch (_) {
    return soakAbsent;
  }
}

int _mb(Object? v) => v is int ? v : soakAbsent;

int _logKB() {
  try {
    final p = Log.path;
    if (p.isEmpty || p.startsWith('(')) return soakAbsent;
    final f = File(p);
    return f.existsSync() ? f.lengthSync() ~/ 1024 : soakAbsent;
  } catch (_) {
    return soakAbsent;
  }
}

// ---------------------------------------------------------------------------
// The work cycle
// ---------------------------------------------------------------------------

/// What a CAD session does, small enough to repeat thousands of times.
///
/// Sized so one cycle is tens of milliseconds rather than seconds: the tier
/// needs MANY identical repetitions, not big ones — the stress tier already
/// owns "how big before it breaks". Every allocator the app has is touched:
/// the Dart heap (solver, analysis, gear outlines), the memo tables, and the
/// native OCCT heap, which is the one where a missing `dispose` is invisible
/// to `ProcessInfo.currentRss` on some platforms and fatal on iOS.
///
/// Everything it builds, it drops. That is the property the whole tier rests
/// on: if the work is conservative and the footprint is not, the difference
/// is the finding.
class SoakCycle {
  SoakCycle(this._occt);

  final OcctFfi? _occt;

  int solves = 0, analyses = 0, gears = 0, solids = 0, edges = 0, triangles = 0;

  void runOnce() {
    _sketch();
    _gear();
    _kernel();
  }

  void _sketch() {
    final gs = sketchFixture(12);
    final cs = constraintFixture(12);
    final base = gs[1].data[0];
    for (var f = 0; f < 5; f++) {
      final d = List<double>.from(gs[1].data);
      d[0] = base + f * 0.5;
      gs[1] = gs[1].withData(d);
      Perf.span('soak.solve', () {
        solveConstraints(gs, cs, dragged: {(1, 0)}, iterations: 25);
      });
      solves++;
    }
    final a = Perf.span('soak.analyze', () => analyzeSketch(gs, cs));
    // Reached its subject, or the timing above is a measurement of nothing —
    // 12.5's fourth conclusion, which cost a whole device run to learn.
    if (a.freePoints.isNotEmpty || a.dof > 0) analyses++;
  }

  void _gear() {
    final g = gearFixture(teeth: 12);
    // COLD: the memo is what a leak would live in, so the interesting call is
    // the one that fills it, not the one that reads it.
    clearGearCurveCache();
    final pts = Perf.span('soak.gear', () => gearCurve(g));
    if (pts.length > 2) gears++;
  }

  void _kernel() {
    final occt = _occt;
    if (occt == null) return;
    final s = Perf.span(
        'soak.build', () => occt.extrudeProfileArcs([arcRing(24, 20)], 8.0));
    if (s == null) {
      Perf.count('soak.build.failed');
      return;
    }
    try {
      final m = Perf.span('soak.mesh', () => s.mesh(linDeflection: 0.2));
      if (m != null) triangles += m.triangleCount;
      final es = Perf.span('soak.edges', s.allEdges);
      edges += es.length;
      final box = occt.makeBox(10, 10, 10);
      if (box != null) {
        try {
          Perf.span('soak.fuse', () => occt.fuse(s, box))?.dispose();
        } finally {
          box.dispose();
        }
      }
      solids++;
    } finally {
      // The whole point. A cycle that forgets this is the leak the tier is
      // looking for, so it is written where it cannot be skipped.
      s.dispose();
    }
  }
}

// ---------------------------------------------------------------------------
// The positive control
// ---------------------------------------------------------------------------

/// Bytes deliberately retained per cycle, to prove the fit can see a leak of a
/// known size. Production never sets it; `s10_soak_test.dart` does, and then
/// checks that the recovered slope is the rate it injected.
@visibleForTesting
int soakLeakBytes = 0;

/// Nothing retained past this, whatever [soakLeakBytes] says. A calibration
/// knob that can terminate the app is not a calibration knob.
const int soakLeakCapBytes = 128 * 1024 * 1024;

final List<Uint8List> _leaked = <Uint8List>[];
int _leakedBytes = 0;

void _leakOnce() {
  final n = soakLeakBytes;
  if (n <= 0 || _leakedBytes + n > soakLeakCapBytes) return;
  // Written to, not merely allocated: an untouched allocation may never
  // become a dirty page, and a leak that does not cost a page is not the leak
  // being calibrated for.
  final b = Uint8List(n);
  for (var i = 0; i < n; i += 4096) {
    b[i] = 1;
  }
  _leaked.add(b);
  _leakedBytes += n;
}

/// Drops whatever [soakLeakBytes] retained. Called at the end of every soak so
/// a calibration run cannot poison the process it ran in.
@visibleForTesting
void resetSoakLeakForTest() {
  _leaked.clear();
  _leakedBytes = 0;
  soakLeakBytes = 0;
}

// ---------------------------------------------------------------------------
// The soak
// ---------------------------------------------------------------------------

/// Takes one OS snapshot. Returns `{}` where there is no native probe, which
/// is every non-iOS host — the soak still runs, on Dart's RSS alone.
typedef SoakProbe = Future<Map<String, Object?>> Function();

Future<Map<String, Object?>> _noProbe() async => const {};

/// Runs catalogue scenario 18.
///
/// [duration] is the WORK phase; [settle] is the quiet phase that follows it,
/// during which nothing is built and the only question is how much memory
/// comes back. [sampleEvery] sets the cadence of the series that both phases
/// are fitted from — 30 minutes at 20 seconds is 90 work points, which is
/// enough for the standard error of the slope to be worth printing.
///
/// [requestFrame] is called once per cycle where the caller has a render
/// pipeline to drive. Without it the frame counters stay flat — an idle
/// Flutter app produces no frames, and a jank trend fitted through no frames
/// at all would be a fabrication. [lagP95Ms] is measured either way.
Future<Map<String, dynamic>> runSoakSuite({
  Duration duration = const Duration(minutes: 30),
  Duration settle = const Duration(seconds: 60),
  Duration sampleEvery = const Duration(seconds: 20),
  Duration yieldEvery = const Duration(milliseconds: 16),
  SoakProbe? probe,
  void Function()? requestFrame,
}) async {
  final takeProbe = probe ?? _noProbe;
  final occt = OcctFfi.instance();
  final cycle = SoakCycle(occt);
  final samples = <SoakSample>[];
  final wall = Stopwatch()..start();
  var threw = 0;
  var cycles = 0;
  var lastSampleMs = 0;
  final lag = <double>[];

  Future<void> takeSample(String phase) async {
    Map<String, Object?> p = const {};
    try {
      p = await takeProbe();
    } catch (e) {
      Log.w('perf', 'soak: native probe failed: $e');
    }
    lag.sort();
    final p95 = lag.isEmpty
        ? 0.0
        : lag[math.min(lag.length - 1, ((lag.length - 1) * 0.95).floor())];
    samples.add(SoakSample(
      phase: phase,
      minutes: wall.elapsedMilliseconds / 60000.0,
      cycles: cycles,
      dartRssMB: _rssMB(),
      footprintMB: _mb(p['footprintMB']),
      residentMB: _mb(p['residentMB']),
      availableMB: _mb(p['availableMB']),
      internalMB: _mb(p['internalMB']),
      compressedMB: _mb(p['compressedMB']),
      deviceMB: _mb(p['deviceMB']),
      externalMB: _mb(p['externalMB']),
      thermal: _mb(p['thermalOrdinal']),
      frames: Perf.totalFrames,
      jank: Perf.jankFrames,
      lagP95Ms: p95,
      logKB: _logKB(),
    ));
    lag.clear();
    lastSampleMs = wall.elapsedMilliseconds;
    Log.i(
        'perf',
        'soak $phase ${(wall.elapsedMilliseconds / 1000).round()}s: '
            'rss ${samples.last.dartRssMB} MB, '
            'footprint ${samples.last.footprintMB} MB, '
            'thermal ${samples.last.thermal}');
  }

  /// One yield, timed. The lateness IS the responsiveness measurement: the
  /// event loop cannot come back to us until whatever is on it has finished.
  Future<void> yieldAndTime() async {
    final sw = Stopwatch()..start();
    await Future<void>.delayed(yieldEvery);
    final lateness =
        sw.elapsedMicroseconds / 1000.0 - yieldEvery.inMicroseconds / 1000.0;
    lag.add(lateness > 0 ? lateness : 0.0);
  }

  await takeSample('work');
  while (wall.elapsedMilliseconds < duration.inMilliseconds) {
    try {
      cycle.runOnce();
      _leakOnce();
      cycles++;
    } catch (e) {
      threw++;
      Perf.count('soak.cycle.threw');
      if (threw <= 3) Log.w('perf', 'soak cycle threw: $e');
    }
    requestFrame?.call();
    await yieldAndTime();
    if (wall.elapsedMilliseconds - lastSampleMs >= sampleEvery.inMilliseconds) {
      await takeSample('work');
    }
  }
  // A final work sample, unless one was just taken — two points a fraction of
  // a second apart carry no information about a half-hour trend and drag the
  // fit toward whatever the last cycle happened to do.
  if (wall.elapsedMilliseconds - lastSampleMs >= sampleEvery.inMilliseconds ~/ 4) {
    await takeSample('work');
  }

  // The settle phase. Same sampling, no work: what a heap that had merely
  // reached its working size gives back, and a leak does not.
  //
  // Nudged once at the top, so what is measured is "what comes back when the
  // collector is given the chance" rather than "what the OS happened to
  // reclaim in sixty idle seconds". The nudge churns small objects and cannot
  // clear old space (see [_gcNudge]) — so a settle figure is a LOWER bound on
  // what would eventually be returned, never an upper one.
  _gcNudge();
  final settleEnd = wall.elapsedMilliseconds + settle.inMilliseconds;
  while (wall.elapsedMilliseconds < settleEnd) {
    requestFrame?.call();
    await yieldAndTime();
    if (wall.elapsedMilliseconds - lastSampleMs >= sampleEvery.inMilliseconds) {
      await takeSample('settle');
    }
  }
  if (settle > Duration.zero) await takeSample('settle');
  wall.stop();

  final report = summariseSoak(samples,
      cycles: cycles, threw: threw, cycle: cycle, wallMs: wall.elapsedMilliseconds);
  resetSoakLeakForTest();
  return report;
}

/// Turns the series into the numbers the tier exists to produce.
///
/// Separated from the loop so the arithmetic can be tested against a series
/// constructed to have a known answer, which is the only way to know that a
/// trend reported off a device is the trend that was there.
Map<String, dynamic> summariseSoak(
  List<SoakSample> samples, {
  required int cycles,
  required int threw,
  required SoakCycle cycle,
  required int wallMs,
}) {
  final work = samples.where((s) => s.phase == 'work').toList();
  final rest = samples.where((s) => s.phase == 'settle').toList();

  // The first work sample is taken before any work at all, and the second
  // carries every one-time cost the process has — first FFI resolution, the
  // first OCCT arena, the memo tables filling. Fitting through those measures
  // the warm-up, not the trend. Both fits are published; the stable one is the
  // headline, and a reader who disagrees has the raw series.
  final stable = work.length > 4 ? work.sublist(2) : work;

  List<double> xs(List<SoakSample> ss) => [for (final s in ss) s.minutes];
  List<double> ys(List<SoakSample> ss, int Function(SoakSample) f) => [
        for (final s in ss)
          f(s) == soakAbsent ? double.nan : f(s).toDouble(),
      ];

  final footprint = fitSoakTrend(xs(stable), ys(stable, (s) => s.footprintMB));
  final footprintAll = fitSoakTrend(xs(work), ys(work, (s) => s.footprintMB));
  final rss = fitSoakTrend(xs(stable), ys(stable, (s) => s.dartRssMB));
  final rssAll = fitSoakTrend(xs(work), ys(work, (s) => s.dartRssMB));
  final resident = fitSoakTrend(xs(stable), ys(stable, (s) => s.residentMB));
  final available = fitSoakTrend(xs(stable), ys(stable, (s) => s.availableMB));
  final compressed = fitSoakTrend(xs(stable), ys(stable, (s) => s.compressedMB));
  final internal = fitSoakTrend(xs(stable), ys(stable, (s) => s.internalMB));
  final device = fitSoakTrend(xs(stable), ys(stable, (s) => s.deviceMB));
  final lag = fitSoakTrend(
      xs(stable), [for (final s in stable) s.lagP95Ms]);
  final logGrowth = fitSoakTrend(xs(stable), ys(stable, (s) => s.logKB));

  // Jank as a RATE over each interval, not as the running total: the total is
  // monotone by construction and its slope would be the average jank rate,
  // which is not the question. The question is whether the rate is rising.
  final jankX = <double>[], jankY = <double>[];
  for (var i = 1; i < stable.length; i++) {
    final df = stable[i].frames - stable[i - 1].frames;
    if (df <= 0) continue;
    final dj = stable[i].jank - stable[i - 1].jank;
    jankX.add(stable[i].minutes);
    jankY.add(1000.0 * dj / df);
  }
  final jank = fitSoakTrend(jankX, jankY);

  int perHourKB(SoakTrend t) => (t.slope * 60 * 1024).round();
  int floorKB(SoakTrend t) => (t.halfWidth * 60 * 1024).round();

  Perf.gauge('soak.minutes', (wallMs / 60000).round());
  Perf.gauge('soak.cycles', cycles);
  Perf.gauge('soak.samples', samples.length);
  Perf.gauge('soak.cycleThrew', threw);
  // What the cycles actually did. A soak whose work silently stopped after
  // minute two would otherwise report a beautifully flat footprint.
  Perf.gauge('soak.did.solves', cycle.solves);
  Perf.gauge('soak.did.analyses', cycle.analyses);
  Perf.gauge('soak.did.gears', cycle.gears);
  Perf.gauge('soak.did.solids', cycle.solids);
  Perf.gauge('soak.did.edges', cycle.edges);
  Perf.gauge('soak.did.triangles', cycle.triangles);

  Perf.gauge('soak.footprintSlopeKBPerHour', perHourKB(footprint));
  Perf.gauge('soak.footprintFloorKBPerHour', floorKB(footprint));
  Perf.gauge('soak.footprintR2Pct', (100 * footprint.r2).round());
  Perf.gauge('soak.rssSlopeKBPerHour', perHourKB(rss));
  Perf.gauge('soak.rssFloorKBPerHour', floorKB(rss));
  Perf.gauge('soak.rssR2Pct', (100 * rss.r2).round());
  Perf.gauge('soak.residentSlopeKBPerHour', perHourKB(resident));
  Perf.gauge('soak.availableSlopeKBPerHour', perHourKB(available));
  Perf.gauge('soak.compressedSlopeKBPerHour', perHourKB(compressed));
  Perf.gauge('soak.internalSlopeKBPerHour', perHourKB(internal));
  Perf.gauge('soak.deviceSlopeKBPerHour', perHourKB(device));

  // Jank and lag: per hour, in the units each is measured in.
  Perf.gauge('soak.jankSlopePerKFramePerHour', (jank.slope * 60).round());
  Perf.gauge('soak.jankFloorPerKFramePerHour', (jank.halfWidth * 60).round());
  Perf.gauge('soak.lagSlopeUsPerHour', (lag.slope * 60 * 1000).round());
  Perf.gauge('soak.lagFloorUsPerHour', (lag.halfWidth * 60 * 1000).round());
  Perf.gauge('soak.logSlopeKBPerHour', (logGrowth.slope * 60).round());

  final thermals = [for (final s in samples) s.thermal]
      .where((t) => t != soakAbsent)
      .toList();
  Perf.gauge('soak.thermalStart', thermals.isEmpty ? soakAbsent : thermals.first);
  Perf.gauge('soak.thermalEnd', thermals.isEmpty ? soakAbsent : thermals.last);
  Perf.gauge('soak.thermalMax',
      thermals.isEmpty ? soakAbsent : thermals.reduce(math.max));

  // What the settle phase gave back, in the two currencies. Positive means the
  // memory came back; a leak cannot.
  final peakWorkFootprint = work
      .map((s) => s.footprintMB)
      .where((v) => v != soakAbsent)
      .fold<int>(soakAbsent, math.max);
  final settledFootprint =
      rest.isEmpty ? soakAbsent : rest.last.footprintMB;
  Perf.gauge(
      'soak.settleReturnedFootprintMB',
      (peakWorkFootprint == soakAbsent || settledFootprint == soakAbsent)
          ? soakAbsent
          : peakWorkFootprint - settledFootprint);
  final peakWorkRss =
      work.map((s) => s.dartRssMB).fold<int>(soakAbsent, math.max);
  Perf.gauge('soak.settleReturnedRssMB',
      rest.isEmpty ? soakAbsent : peakWorkRss - rest.last.dartRssMB);

  // The ratio 8.5 left open, measured over time rather than at four moments.
  final ratios = [
    for (final s in samples)
      if (s.footprintOverRss.isFinite) s.footprintOverRss,
  ];
  if (ratios.isNotEmpty) {
    Perf.gauge('soak.footprintOverRssMinPct',
        (100 * ratios.reduce(math.min)).round());
    Perf.gauge('soak.footprintOverRssMaxPct',
        (100 * ratios.reduce(math.max)).round());
  }

  Perf.note(
      'soak.rule',
      'a slope is a leak only if it exceeds its own floor AND the settle '
      'phase did not give it back; otherwise it is a heap reaching its '
      'working size, or noise');

  return {
    'suite': 'perf_scenarios_soak/v1',
    'at': DateTime.now().toIso8601String(),
    'build': Log.build,
    'wallMs': wallMs,
    'occtAvailable': OcctFfi.available,
    'cycles': cycles,
    'cycleThrew': threw,
    'did': {
      'solves': cycle.solves,
      'analyses': cycle.analyses,
      'gears': cycle.gears,
      'solids': cycle.solids,
      'edges': cycle.edges,
      'triangles': cycle.triangles,
    },
    'trends': {
      'footprintMBPerMin': footprint.toJson(),
      'footprintMBPerMinAll': footprintAll.toJson(),
      'dartRssMBPerMin': rss.toJson(),
      'dartRssMBPerMinAll': rssAll.toJson(),
      'residentMBPerMin': resident.toJson(),
      'availableMBPerMin': available.toJson(),
      'compressedMBPerMin': compressed.toJson(),
      'internalMBPerMin': internal.toJson(),
      'deviceMBPerMin': device.toJson(),
      'jankPerKFramePerMin': jank.toJson(),
      'lagP95MsPerMin': lag.toJson(),
      'logKBPerMin': logGrowth.toJson(),
    },
    // The series itself. Every fit above is re-derivable from this, which is
    // the difference between a report and a claim.
    'samples': [for (final s in samples) s.toJson()],
    'gauges': Map<String, int>.of(Perf.gauges),
  };
}

// ---------------------------------------------------------------------------
// The memory-attribution family — 8.5's open question, without the wait
// ---------------------------------------------------------------------------

/// Nudges the collector, by churning SMALL short-lived objects.
///
/// Two things this is not. It is not a forced collection — Dart exposes none
/// outside the VM service, and a major collection is what would be needed to
/// return the large old-space blocks a dense matrix occupies. And it is not
/// allowed to be a large allocation itself: the obvious version of this
/// function asks for a few dozen megabytes and drops them, which GROWS the
/// resident set of the very measurement it is supposed to clean up. The first
/// version here did exactly that with 48 MB rounds and made every settled
/// figure it produced meaningless.
///
/// So: many small objects, a low peak, several new-space cycles. Enough to
/// clear the scavenger; honest about not clearing anything else.
void _gcNudge({int rounds = 8}) {
  var sink = 0;
  for (var r = 0; r < rounds; r++) {
    for (var i = 0; i < 40000; i++) {
      sink ^= <int>[i][0];
    }
  }
  // The sink exists so the loop is not dead code; the branch never fires.
  if (sink == 0x7fffffff) Log.w('perf', 'gc nudge sink');
}

List<PerfScenario> buildMemoryScenarios() {
  final out = <PerfScenario>[];

  // ---- the DOF analysis, re-derived ------------------------------------
  //
  // PERFORMANCE_PROFILE 5.5.2 predicted the memory of a 1024-entity DOF
  // analysis from the dimensions of the two DENSE structures the algorithm
  // built — a 2562 x 3584 Jacobian and a 1022 x 3584 null-space basis, 102.8 MB
  // together — and the measured 105 MB agreed to 2.2%. S3 then made both
  // sparse. The prediction was a property of code that no longer exists, so
  // the figure has to be taken again rather than carried forward.
  //
  // This is a LADDER, not a point: what survives a change of device is the
  // exponent, and the question that matters is whether the structural cost is
  // still O(n^2).
  for (final n in const [64, 128, 256]) {
    out.add(PerfScenario(
      'mem.analyze.$n',
      () {
        final gs = sketchFixture(n ~/ 2);
        final cs = constraintFixture(n ~/ 2);
        // The system's dimensions, so the arithmetic can be closed the way
        // 5.5.2 closed it — a fixture that is not producing the system the
        // model assumes invalidates every byte figure derived from it.
        final (rank, m, total) = debugRank(gs, cs);
        Perf.gauge('mem.analyze.$n.params', total);
        Perf.gauge('mem.analyze.$n.residuals', m);
        Perf.gauge('mem.analyze.$n.rank', rank);
        Perf.gauge('mem.analyze.$n.dof', total - rank);
        // The transient side, which is the part 5.5.2 never counted because
        // the dense structures dwarfed it: one full residual vector is
        // allocated per parameter and dropped, `total` times. A growable
        // List<double> in the Dart VM costs a pointer slot per element plus a
        // boxed double per distinct value, so m doubles cost m*(8+16) bytes,
        // not m*8. Derived, not measured — and labelled as such.
        Perf.gauge('mem.analyze.$n.churnMB', (total * m * 24) ~/ (1024 * 1024));

        _gcNudge();
        final before = _rssMB();
        final a = analyzeSketch(gs, cs);
        final after = _rssMB();
        Perf.gauge('mem.analyze.$n.rssDeltaMB', after - before);
        // ...and again after a nudge. Neither of these is an allocation
        // figure: RSS is what the kernel has GIVEN the process, so a heap with
        // spare capacity absorbs the whole analysis without asking for a page,
        // and a collector that compacts mid-call returns pages and makes the
        // delta negative. Both were observed while building this. They are
        // published because they are what this tier can measure in situ; the
        // number here that is exact is churnMB, and it is exact because it is
        // arithmetic. The decisive comparison lives in a cold process, in
        // `s10_analyze_memory_test.dart`.
        _gcNudge();
        Perf.gauge('mem.analyze.$n.settledDeltaMB', _rssMB() - before);
        Perf.gauge('mem.analyze.$n.freePoints', a.freePoints.length);
      },
      note: 'memory of ONE DOF analysis, at three sizes — the family that '
          'replaces PERFORMANCE_PROFILE 5.5.2s 105 MB, which was a property '
          'of the DENSE algorithm S3 replaced. READ churnMB FIRST: it is '
          'exact, because it is arithmetic — params x residuals x 24 B, the '
          'residual vectors the finite-difference Jacobian allocates and '
          'drops once per parameter. S3 did not change that loop; it removed '
          'the dense matrices that used to dwarf it, so it is now the only '
          'superlinear allocation on this path. rssDeltaMB and '
          'settledDeltaMB are what RSS did around the call, and RSS is a '
          'coarse instrument for one call: a warm heap absorbs the analysis '
          'without asking the kernel for a page, and a collector that '
          'compacts mid-call makes the delta NEGATIVE. Do not read either as '
          'an allocation figure. params/residuals/rank/dof are exact and are '
          'there so the fixture arithmetic can be closed the way 5.5.2 closed '
          'it at 1024 entities',
    ));
  }

  // ---- what the footprint is made of -------------------------------------
  //
  // 8.5 records the footprint-to-RSS ratio at four probe points — 3.60, 2.52,
  // 4.00, 2.47 — and closes with the honest admission that WHAT ALLOCATES THE
  // FOOTPRINT IS UNKNOWN. It cannot be answered from Dart: `currentRss` is the
  // resident set, and the whole difficulty is that iOS terminates on a
  // quantity the resident set is not. It is answered by the native probe's
  // decomposition, so this scenario's job is to move a KNOWN number of bytes
  // and leave a marker in the series either side of it.
  final occt = OcctFfi.instance();
  if (occt != null) {
    out.add(PerfScenario(
      'mem.footprint.mesh',
      () {
        _gcNudge();
        final before = _rssMB();
        final held = <OcctShape>[];
        var tris = 0;
        try {
          for (var i = 0; i < 12; i++) {
            final s = occt.extrudeProfileArcs([ringProfile(64, 20 + i * 2.0)], 10.0);
            if (s == null) continue;
            held.add(s);
            final m = s.mesh(linDeflection: 0.05);
            if (m != null) tris += m.triangleCount;
          }
          Perf.gauge('mem.footprint.solids', held.length);
          Perf.gauge('mem.footprint.tris', tris);
          Perf.gauge('mem.footprint.heldRssDeltaMB', _rssMB() - before);
        } finally {
          for (final s in held) {
            s.dispose();
          }
        }
        _gcNudge();
        Perf.gauge('mem.footprint.releasedRssDeltaMB', _rssMB() - before);
      },
      note: 'twelve meshed solids held at once and then released, as a marker '
          'the native probe can be read against: mem.footprint.tris says how '
          'many triangles moved, heldRssDeltaMB what Dart saw, and the '
          'native.footprintMB gauges either side of the suite say what iOS '
          'charged for it. The gap between those two is 8.5 open question',
    ));
  }

  return out;
}

/// Runs the memory family. Short — no soak, no ladders past 256 entities.
Map<String, dynamic> runMemorySuite() {
  final results = <Map<String, dynamic>>[];
  final sw = Stopwatch()..start();
  for (final s in buildMemoryScenarios()) {
    Log.i('perf', 'memory scenario ${s.name}');
    // No warmup: these are memory measurements, and a warmup pass leaves the
    // heap in the state the measured pass is trying to observe from cold.
    final r = Perf.scenario(s.name, s.run);
    r['note'] = s.note;
    results.add(r);
  }
  sw.stop();
  return {
    'suite': 'perf_scenarios_memory/v1',
    'at': DateTime.now().toIso8601String(),
    'build': Log.build,
    'wallMs': sw.elapsedMilliseconds,
    'occtAvailable': OcctFfi.available,
    'scenarios': results,
  };
}
