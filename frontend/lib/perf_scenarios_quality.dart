// The measurements that make the OTHER measurements usable.
//
// Everything else in this suite answers "what does X cost". These four answer
// questions that decide whether those answers can be acted on at all.
//
// 1. IS A NUMBER REPEATABLE? (`quality.variance.*`)
//    The whole baseline-diff idea rests on an unexamined assumption: that
//    running the same scenario twice gives the same answer. If a scenario
//    varies 40% between runs then a 30% "regression" in a diff is noise, and
//    chasing it wastes exactly the time this suite exists to save. Nothing has
//    ever checked. This measures the spread directly and publishes it, so a
//    reader knows how big a change has to be before it means anything.
//
// 2. WHAT DOES A DOCUMENT COST IN MEMORY? (`quality.memPer*`)
//    The device died with the app at 839 MB of RSS, and the honest answer to
//    "how big a file fits" has been a shrug. Bytes per sketch entity and bytes
//    per solid turn that into arithmetic.
//
// 3. WHERE IS THE FRAME BUDGET ACTUALLY SPENT? (`quality.budget.*`)
//    A duration is not actionable; a duration against a budget is. These
//    report the largest sketch that still solves inside one 120 Hz frame, and
//    the largest that fits 60 Hz — the numbers a person can design around.
//
// 4. DO THE CACHES WORK? (`quality.cache.*`)
//    The gear memo was found doing its job (200 hits, unmeasurable). Nothing
//    else with a cache has been checked, and a cache that silently stops
//    hitting is a regression that no duration in isolation reveals.
import 'dart:io' show ProcessInfo;
import 'dart:ui' show Offset;
import 'dart:math' as math;

import 'ffi/occt_engine.dart';
import 'ffi/qcad_engine.dart';
import 'gear.dart';
import 'perf.dart';
import 'perf_scenarios.dart'
    show PerfScenario, sketchFixture, constraintFixture, gearFixture, ringProfile;
import 'solver.dart';
import 'spline.dart';
import 'tools.dart' show buildToolGeometry;
import 'app_state.dart' show Tool;

/// Runs [body] [reps] times and publishes the SPREAD.
///
/// Reports, as gauges scaled to keep them integers:
///   `quality.variance.<name>.medianUs`  — the middle sample
///   `quality.variance.<name>.spreadPct` — (max-min)/median, as a percentage
///   `quality.variance.<name>.iqrPct`    — the middle-50% spread, which is the
///                                          honest one: a single unlucky
///                                          sample inflates max-min and says
///                                          nothing about typical behaviour.
///
/// The IQR is the number a reader should use as the noise floor of a diff.
void _variance(String name, int reps, void Function() body) {
  final samples = <double>[];
  for (var i = 0; i < reps; i++) {
    final sw = Stopwatch()..start();
    body();
    sw.stop();
    samples.add(sw.elapsedMicroseconds.toDouble());
  }
  if (samples.isEmpty) return;
  samples.sort();
  final median = samples[samples.length ~/ 2];
  if (median <= 0) return;
  final q1 = samples[(samples.length * 0.25).floor()];
  final q3 = samples[math.min((samples.length * 0.75).floor(), samples.length - 1)];
  Perf.gauge('quality.variance.$name.medianUs', median.round());
  Perf.gauge('quality.variance.$name.spreadPct',
      (100 * (samples.last - samples.first) / median).round());
  Perf.gauge('quality.variance.$name.iqrPct', (100 * (q3 - q1) / median).round());
}

int _rssBytes() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return -1;
  }
}

List<PerfScenario> buildQualityScenarios() {
  final out = <PerfScenario>[];

  // ---- 1. repeatability --------------------------------------------------
  out.add(PerfScenario(
    'quality.variance',
    () {
      _variance('solve', 15, () {
        final gs = sketchFixture(24);
        solveConstraints(gs, constraintFixture(24), iterations: 25);
      });
      _variance('analyze', 9, () {
        analyzeSketch(sketchFixture(24), constraintFixture(24));
      });
      _variance('splineEval', 15, () {
        final g = buildToolGeometry(Tool.splineCV, [
          for (var i = 0; i < 16; i++)
            Offset(30 * math.cos(i * 1.7), 30 * math.sin(i * 1.7))
        ])?.first;
        if (g != null) splineCurveFor(g);
      });
      final occt = OcctFfi.instance();
      if (occt != null) {
        _variance('extrude', 9, () {
          occt.extrudeProfileArcs([ringProfile(48, 40)], 10.0)?.dispose();
        });
      }
    },
    note: 'THE NOISE FLOOR. Run the same work 9-15 times and publish the '
        'spread. `iqrPct` is how much a number moves for no reason at all — '
        'any diff smaller than that is noise, and chasing it wastes the time '
        'this suite exists to save. Nothing had ever checked this',
  ));

  // ---- 2. memory per unit ------------------------------------------------
  out.add(PerfScenario(
    'quality.memoryPerEntity',
    () {
      // Held simultaneously: the question is what a DOCUMENT costs, not what
      // one allocation costs, and a list that is freed as it grows measures
      // the allocator instead of the document.
      const n = 4000;
      final before = _rssBytes();
      final held = <List<Geo>>[];
      for (var i = 0; i < 20; i++) {
        held.add(sketchFixture(n ~/ 40));
      }
      final after = _rssBytes();
      var total = 0;
      for (final l in held) {
        total += l.length;
      }
      if (before > 0 && after > before && total > 0) {
        Perf.gauge('quality.memPerEntityBytes', (after - before) ~/ total);
        Perf.gauge('quality.memEntitiesHeld', total);
      }
      held.clear();
    },
    note: 'bytes of RSS per sketch entity, from 4000 entities held at once. '
        'Multiply by a real sketch size to predict what a document costs — '
        'the device that crashed was at 839 MB and nobody could say why',
  ));

  final occt = OcctFfi.instance();
  if (occt != null) {
    out.add(PerfScenario(
      'quality.memoryPerSolid',
      () {
        final before = _rssBytes();
        final held = <OcctShape>[];
        var tris = 0;
        for (var i = 0; i < 12; i++) {
          final s = occt.extrudeProfileArcs([ringProfile(48, 20 + i * 2.0)], 10.0);
          if (s == null) continue;
          held.add(s);
          final m = s.mesh(linDeflection: 0.2);
          if (m != null) tris += m.triangleCount;
        }
        final after = _rssBytes();
        if (before > 0 && after > before && held.isNotEmpty) {
          Perf.gauge('quality.memPerSolidKB', (after - before) ~/ held.length ~/ 1024);
          if (tris > 0) {
            Perf.gauge('quality.memPerTriangleBytes', (after - before) ~/ tris);
          }
        }
        for (final s in held) {
          s.dispose();
        }
      },
      note: 'kilobytes of RSS per solid, and bytes per triangle, from twelve '
          'solids held alive with their meshes. This is the arithmetic behind '
          '"how many bodies fit before the OS kills us"',
    ));
  }

  // ---- 3. frame budgets --------------------------------------------------
  out.add(PerfScenario(
    'quality.frameBudget',
    () {
      // Climb until one solve exceeds the budget, then report the size. This
      // is a translation, not a new measurement: the ramp already has the
      // durations, but "the largest sketch that still solves inside a frame"
      // is the form a person can actually design against.
      const budget120 = 8.3, budget60 = 16.7;
      var last120 = 0, last60 = 0;
      for (final n in const [16, 32, 64, 96, 128, 192, 256, 384]) {
        final gs = sketchFixture(n ~/ 2);
        final cs = constraintFixture(n ~/ 2);
        final sw = Stopwatch()..start();
        solveConstraints(gs, cs, iterations: 25);
        sw.stop();
        final ms = sw.elapsedMicroseconds / 1000.0;
        // TWO solves per painted frame — that is what the painter actually
        // does today (viewport.dart:2088 and :2683), so a budget computed on
        // one solve would be optimistic by exactly a factor of two.
        final perFrame = ms * 2;
        if (perFrame <= budget120) last120 = n;
        if (perFrame <= budget60) last60 = n;
        if (perFrame > budget60 * 4) break;
      }
      Perf.gauge('quality.budget.entitiesAt120Hz', last120);
      Perf.gauge('quality.budget.entitiesAt60Hz', last60);
    },
    note: 'the largest sketch that still solves inside one frame, counting the '
        'TWO solves per frame the painter really does. These two numbers are '
        'the design limit: past them, dragging cannot be smooth however good '
        'the rest of the frame is',
  ));

  // ---- 4. caches ---------------------------------------------------------
  out.add(PerfScenario(
    'quality.caches',
    () {
      // The gear memo, measured as a RATIO rather than as two durations. A
      // ratio survives a change of chip and a change of power mode; the two
      // durations do not, which is why the earlier low-power run made every
      // absolute number in the report incomparable.
      final g = gearFixture(teeth: 20);
      clearGearCurveCache();
      final cold = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        clearGearCurveCache();
        gearCurve(g);
      }
      cold.stop();
      gearCurve(g); // prime
      final warm = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        gearCurve(g);
      }
      warm.stop();
      final c = cold.elapsedMicroseconds, w = warm.elapsedMicroseconds;
      if (w > 0) Perf.gauge('quality.cache.gearSpeedup', c ~/ math.max(w, 1));
      Perf.gauge('quality.cache.gearColdUs', c ~/ 10);
      Perf.gauge('quality.cache.gearWarmUs', w ~/ 10);
    },
    note: 'cache effectiveness as a RATIO (cold/warm), which survives a change '
        'of chip and of power mode where absolute durations do not. A speedup '
        'that collapses between two builds is a cache that stopped working — '
        'invisible in any single duration',
  ));

  return out;
}
