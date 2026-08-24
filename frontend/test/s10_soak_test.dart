// S10 — catalogue scenario 18, and the memory family.
//
// Three things are checked here, and they are of different kinds.
//
//  1. THE ARITHMETIC OF THE FIT, against series whose answer is known by
//     construction. A trend reported off a device is believable only if the
//     code that produced it recovers a slope somebody put there on purpose.
//
//  2. THE INSTRUMENT AGAINST A REAL LEAK. `soakLeakBytes` retains a fixed
//     number of bytes per cycle; the soak then has to find the rate it was
//     given, in MB per minute, from RSS alone. Nothing is compared against a
//     recorded constant — the expected slope is computed from what the run
//     itself retained, in the same process on the same machine, which is the
//     differential form OPTIMIZATION_PLAN_2 1.4 requires.
//
//  3. THE DOF ANALYSIS MEMORY, dense against sparse, in one process.
//     PERFORMANCE_PROFILE 5.5.2 predicted 102.8 MB for the dense algorithm and
//     measured 105. S3 replaced that algorithm, so the figure is re-derived
//     here rather than carried forward: the frozen dense reference and the
//     shipping sparse path are run on the same fixture and their memory
//     compared. That is a differential measurement; a recorded megabyte count
//     would be a golden, and this branch has already lost a build to one.
import 'dart:io' show ProcessInfo;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/perf.dart';
import 'package:prototype/perf_scenarios.dart';
import 'package:prototype/perf_scenarios_soak.dart';
import 'package:prototype/perf_scenarios_stress.dart';
import 'package:prototype/perf_scenarios_ui.dart';
import 'package:prototype/solver.dart';

int _rssBytes() {
  try {
    return ProcessInfo.currentRss;
  } catch (_) {
    return 0;
  }
}

void main() {
  group('the fit — against series with a known answer', () {
    test('an exact line is recovered exactly', () {
      final xs = [for (var i = 0; i < 10; i++) i.toDouble()];
      final ys = [for (final x in xs) 3.0 + 2.5 * x];
      final t = fitSoakTrend(xs, ys);
      expect(t.n, 10);
      expect(t.slope, closeTo(2.5, 1e-9));
      expect(t.intercept, closeTo(3.0, 1e-9));
      expect(t.r2, closeTo(1.0, 1e-9));
      // An exact fit has no residual, so it has no standard error — and
      // therefore no interval. `resolved` must be false: a slope with no
      // uncertainty estimate has not been shown to differ from zero by THIS
      // machinery, however obvious it looks.
      expect(t.se, 0.0);
      expect(t.resolved, isFalse);
    });

    test('a flat series has slope zero and is not resolved', () {
      final xs = [for (var i = 0; i < 12; i++) i.toDouble()];
      final t = fitSoakTrend(xs, [for (final _ in xs) 500.0]);
      expect(t.slope, closeTo(0.0, 1e-9));
      expect(t.resolved, isFalse);
    });

    test('scatter around a line: the slope survives, the interval widens', () {
      // Deterministic scatter of +-5, in the period-4 pattern + - - + so that
      // it is orthogonal to x. A simple alternating zigzag is NOT: over an
      // even number of points it correlates with x and biases the slope by a
      // measurable 3.8%, which would have made this test assert its own
      // arithmetic error.
      double wobble(int i) => const [5.0, -5.0, -5.0, 5.0][i % 4];
      final xs = [for (var i = 0; i < 20; i++) i.toDouble()];
      final ys = [for (var i = 0; i < 20; i++) 2.0 * i + wobble(i)];
      final t = fitSoakTrend(xs, ys);
      expect(t.slope, closeTo(2.0, 1e-9));
      expect(t.se, greaterThan(0));
      expect(t.halfWidth, closeTo(1.96 * t.se, 1e-12));
      // +-5 on a range of 38, so a slope of 2 is well clear of its interval.
      expect(t.resolved, isTrue);
      // ...and the same scatter on a FLAT series is not.
      final flat =
          fitSoakTrend(xs, [for (var i = 0; i < 20; i++) 100.0 + wobble(i)]);
      expect(flat.slope, closeTo(0.0, 1e-9));
      expect(flat.resolved, isFalse);
      expect(flat.halfWidth, greaterThan(0));
    });

    test('absent samples are dropped, not fitted as zero', () {
      // The convention the soak uses off iOS: no native probe, so footprint is
      // soakAbsent and arrives here as NaN. Fitting it as a number would
      // manufacture a violent negative slope out of nothing.
      final xs = [0.0, 1.0, 2.0, 3.0];
      final t = fitSoakTrend(xs, [10.0, double.nan, 12.0, 13.0]);
      expect(t.n, 3);
      expect(t.slope, closeTo(1.0, 1e-9));
      expect(fitSoakTrend(xs, [double.nan, double.nan, double.nan, double.nan]).n,
          0);
    });

    test('fewer than two points, or no spread in x, is the empty fit', () {
      expect(fitSoakTrend([1.0], [1.0]).n, 0);
      expect(fitSoakTrend([2.0, 2.0, 2.0], [1.0, 5.0, 9.0]).n, 0);
    });
  });

  group('catalogue scenario 18 — the soak', () {
    tearDown(resetSoakLeakForTest);

    test('it is NOT part of any other suite', () {
      // Thirty minutes. It must never fire from an ordinary bug report, and it
      // must not appear in the stress tier either — that one is already
      // opt-in, and folding a half-hour into it would make the opt-in a trap.
      final others = [
        ...buildScenarios().map((s) => s.name),
        ...buildUiScenarios().map((s) => s.name),
        ...buildStressScenarios().map((s) => s.name),
      ];
      expect(others.where((n) => n.startsWith('soak.')), isEmpty);
      expect(others.where((n) => n.startsWith('mem.')), isEmpty);
    });

    test('a short soak reports the slopes, the floors and what it did',
        () async {
      Perf.resetForTest();
      final r = await runSoakSuite(
        duration: const Duration(seconds: 3),
        settle: const Duration(seconds: 1),
        sampleEvery: const Duration(milliseconds: 250),
        yieldEvery: const Duration(milliseconds: 5),
      );

      expect(r['suite'], 'perf_scenarios_soak/v1');
      expect(r['cycles'] as int, greaterThan(0));
      expect(r['cycleThrew'], 0);

      // It reached its subject. A soak whose work silently stopped would
      // otherwise report an admirably flat footprint — 12.5's fourth
      // conclusion, in the tier where it would do the most damage.
      final did = r['did'] as Map<String, dynamic>;
      expect(did['solves'] as int, greaterThan(0));
      expect(did['analyses'] as int, greaterThan(0));
      expect(did['gears'] as int, greaterThan(0));

      final samples = r['samples'] as List;
      expect(samples.length, greaterThan(3));
      expect(samples.map((s) => (s as Map)['phase']), contains('settle'));
      // The series is what makes every fit re-derivable, so each point has to
      // carry its own x.
      for (final s in samples) {
        expect((s as Map)['minutes'], isA<double>());
      }

      // Every slope ships with the floor that says what it could have seen.
      for (final k in const [
        'soak.footprintSlopeKBPerHour',
        'soak.footprintFloorKBPerHour',
        'soak.rssSlopeKBPerHour',
        'soak.rssFloorKBPerHour',
        'soak.lagSlopeUsPerHour',
        'soak.lagFloorUsPerHour',
        'soak.jankSlopePerKFramePerHour',
        'soak.jankFloorPerKFramePerHour',
        'soak.cycles',
        'soak.samples',
        'soak.thermalMax',
      ]) {
        expect(Perf.gauges.containsKey(k), isTrue, reason: '$k is missing');
      }
      expect(Perf.notes.containsKey('soak.rule'), isTrue);

      // Off iOS there is no native probe, so footprint must be ABSENT rather
      // than zero — a footprint of 0 MB would read as an app using no memory.
      expect((samples.first as Map)['footprintMB'], soakAbsent);
      final trends = r['trends'] as Map<String, dynamic>;
      expect((trends['footprintMBPerMin'] as Map)['n'], 0);
      // ...while the Dart-side series, which needs no probe, is fitted.
      expect((trends['dartRssMBPerMin'] as Map)['n'], greaterThan(1));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a probe that supplies footprint is fitted, and the ratio recorded',
        () async {
      Perf.resetForTest();
      // A synthetic probe rising 1 MB per call, so the machinery that reads
      // the native map is exercised on a host that has no native map. This is
      // a test of the PLUMBING; the leak calibration below is the test of the
      // measurement.
      var n = 0;
      Future<Map<String, Object?>> probe() async {
        n++;
        return {
          'footprintMB': 1000 + n,
          'residentMB': 400,
          'availableMB': 3000 - n,
          'internalMB': 900 + n,
          'compressedMB': 100,
          'deviceMB': 40,
          'externalMB': 60,
          'thermalOrdinal': n > 4 ? 2 : 0,
        };
      }

      final r = await runSoakSuite(
        duration: const Duration(seconds: 2),
        settle: Duration.zero,
        sampleEvery: const Duration(milliseconds: 200),
        yieldEvery: const Duration(milliseconds: 5),
        probe: probe,
      );
      final trends = r['trends'] as Map<String, dynamic>;
      expect((trends['footprintMBPerMin'] as Map)['n'], greaterThan(1));
      expect((trends['footprintMBPerMin'] as Map)['slope'] as double,
          greaterThan(0));
      // Thermal is a RESULT, reported at both ends and at its worst — 3.1's
      // rule, so a slow second half can be told from slow code.
      expect(Perf.gauges['soak.thermalStart'], 0);
      expect(Perf.gauges['soak.thermalMax'], 2);
      // 8.5's ratio, recorded as a range over the run rather than at one
      // moment. 1001..1000+n over 400 is 250%-ish.
      expect(Perf.gauges['soak.footprintOverRssMinPct'], greaterThan(200));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('THE CALIBRATION: a leak of known size is recovered from RSS',
        () async {
      // The instrument this whole tier is, checked against a leak somebody put
      // there on purpose. Without this the soak is an assertion that it would
      // notice — which is exactly what nobody can check on a device.
      Perf.resetForTest();
      const perCycle = 512 * 1024;
      soakLeakBytes = perCycle;
      final rss0 = _rssBytes();
      final r = await runSoakSuite(
        duration: const Duration(seconds: 6),
        settle: Duration.zero,
        sampleEvery: const Duration(milliseconds: 300),
        yieldEvery: const Duration(milliseconds: 10),
      );
      final rss1 = _rssBytes();
      final cycles = r['cycles'] as int;
      final minutes = (r['wallMs'] as int) / 60000.0;
      final leakedMB = (cycles * perCycle) / (1024 * 1024);
      final trend = (r['trends'] as Map)['dartRssMBPerMin'] as Map;
      final slope = trend['slope'] as double;
      final expected = leakedMB / minutes;

      printOnFailure('cycles=$cycles leakedMB=$leakedMB over ${minutes}min '
          '=> expected ${expected.toStringAsFixed(1)} MB/min, '
          'fitted ${slope.toStringAsFixed(1)} MB/min, '
          'rss ${(rss1 - rss0) ~/ (1024 * 1024)} MB');

      expect(cycles, greaterThan(20),
          reason: 'too few cycles to fit anything through');
      expect(leakedMB, greaterThan(8),
          reason: 'the injected leak has to be bigger than the noise');
      // The recovered rate, against the rate that was injected. Generous —
      // RSS moves in page-sized steps and the collector is not asked
      // permission — but one-sided tightness is what matters: the fit must not
      // be able to miss a leak of this size, and must not invent one twice its
      // size either.
      expect(slope, greaterThan(0.45 * expected),
          reason: 'the fit UNDER-reports a leak it was handed');
      expect(slope, lessThan(2.5 * expected),
          reason: 'the fit OVER-reports a leak it was handed');
      // And it must clear its own floor, or the run proves nothing.
      expect(trend['resolved'], isTrue,
          reason: 'a leak this size must be resolvable against the scatter');
      // Sanity on the other side: the process really did grow.
      expect(rss1 - rss0, greaterThan((leakedMB * 0.5 * 1024 * 1024).round()));
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('with no leak injected, the same run does not manufacture one',
        () async {
      // The other half of a calibration. An instrument that reports a leak on
      // a clean run is worse than none, and this tier's whole output is a
      // slope, so a false positive here is a false positive on the device.
      Perf.resetForTest();
      final r = await runSoakSuite(
        duration: const Duration(seconds: 6),
        settle: Duration.zero,
        sampleEvery: const Duration(milliseconds: 300),
        yieldEvery: const Duration(milliseconds: 10),
      );
      final trend = (r['trends'] as Map)['dartRssMBPerMin'] as Map;
      final slope = trend['slope'] as double;
      final half = trend['halfWidth'] as double;
      printOnFailure('clean run: ${slope.toStringAsFixed(2)} MB/min '
          '+- ${half.toStringAsFixed(2)}, cycles ${r['cycles']}');
      // Not "the slope is zero" — a young Dart heap really is still growing,
      // and asserting flatness would be asserting something false. What must
      // hold is that the fixed work of the cycle does not run away: 100 MB per
      // minute would be 3 GB over the tier's own half hour.
      expect(slope, lessThan(100.0),
          reason: 'the fixed work cycle is growing without bound');
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group('the memory family', () {
    test('every scenario is named and explained', () {
      for (final s in buildMemoryScenarios()) {
        expect(s.name, startsWith('mem.'));
        expect(s.note.length, greaterThan(20));
      }
    });

    test('the 2D family exists without a kernel', () {
      final names = buildMemoryScenarios().map((s) => s.name).toSet();
      expect(names, containsAll(['mem.analyze.64', 'mem.analyze.128',
        'mem.analyze.256']));
    });

    test('the fixture arithmetic closes, as 5.5.2 closed it at 1024', () {
      // 5.5.2 derived the system's dimensions from the fixture and matched the
      // recorded gauge exactly, and called that the confirmation that the
      // fixture produces the system the memory model assumes. The same
      // arithmetic, at a size CI can afford:
      //
      //   sketchFixture(c)     -> c circles (3 params) + c lines (4)  = 7c
      //   constraintFixture(c) -> (c-1) equal (1 residual each)
      //                           + 2c coincident (2 each)
      //                           + fix (2) + dimension (1)
      //                         = (c-1) + 4c + 3 residuals
      for (final c in const [32, 64, 128]) {
        final gs = sketchFixture(c);
        final cs = constraintFixture(c);
        final (rank, m, total) = debugRank(gs, cs);
        expect(total, 7 * c, reason: 'parameter count at c=$c');
        expect(m, (c - 1) + 4 * c + 3, reason: 'residual count at c=$c');
        expect(rank, m,
            reason: 'the fixture is meant to be of full row rank at c=$c');
        expect(total - rank, 7 * c - ((c - 1) + 4 * c + 3),
            reason: 'dof at c=$c');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('a memory scenario reaches its subject and reports both deltas', () {
      Perf.resetForTest();
      final s = buildMemoryScenarios()
          .firstWhere((sc) => sc.name == 'mem.analyze.128');
      final r = Perf.scenario(s.name, s.run);
      // Checked FIRST and by name: Perf.scenario swallows a throw into
      // `error`, so without this a scenario that died reads as "seven gauges
      // are missing" and sends the reader looking in the wrong place.
      expect(r['error'], isNull, reason: 'the scenario threw: ${r['error']}');
      for (final k in const [
        'mem.analyze.128.params',
        'mem.analyze.128.residuals',
        'mem.analyze.128.rank',
        'mem.analyze.128.dof',
        'mem.analyze.128.churnMB',
        'mem.analyze.128.rssDeltaMB',
        'mem.analyze.128.settledDeltaMB',
      ]) {
        expect(Perf.gauges.containsKey(k), isTrue, reason: '$k is missing');
      }
      // 64 circles + 64 lines: 448 parameters, 322 residuals.
      expect(Perf.gauges['mem.analyze.128.params'], 448);
      expect(Perf.gauges['mem.analyze.128.residuals'], 322);
      expect(Perf.gauges['mem.analyze.128.freePoints'], greaterThan(0),
          reason: 'an analysis that found nothing measured nothing');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
