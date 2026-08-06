// M211 — the self-driving perf suite.
//
// The suite exists so the app can measure itself with fixed inputs instead of
// relying on someone tapping the same way twice. These tests do not check
// TIMINGS — a CI runner's milliseconds mean nothing — they check the two
// properties that make the timings trustworthy when they are collected on a
// device:
//
//   1. Every scenario runs and produces a delta, on a host with no OCCT.
//   2. The delta is ISOLATED: a scenario's numbers describe that scenario and
//      do not carry the session's history with them.
//
// Property 2 is the one worth pinning. Without it the first scenario looks
// expensive and the rest look free, which is exactly the kind of plausible
// wrong number that sends optimisation into the wrong layer (M75).
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/perf.dart';
import 'package:prototype/perf_scenarios.dart';

void main() {
  setUp(Perf.resetForTest);

  group('fixtures are deterministic', () {
    test('the same size yields identical geometry every time', () {
      final a = sketchFixture(24), b = sketchFixture(24);
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].data, b[i].data,
            reason: 'a fixture that varies makes two runs incomparable');
      }
    });

    test('size drives entity count, so a sweep really sweeps', () {
      expect(sketchFixture(8).length, 16);
      expect(sketchFixture(24).length, 48);
      expect(sketchFixture(64).length, 128);
    });

    test('the gear fixture carries the parameter block the app expects', () {
      final g = gearFixture(teeth: 20);
      expect(g.isGear, isTrue);
      // teeth live at the packed offset the app reads them from
      expect(g.data[7], 20.0);
    });

    test('ringProfile emits (x, y, bulge) triplets', () {
      expect(ringProfile(12, 40).length, 36);
    });
  });

  group('scenario isolation', () {
    test('a delta reports only what happened inside it', () {
      Perf.record('unit.before', 100);
      Perf.count('unit.beforeCount', 5);

      final r = Perf.scenario('unit.s', () {
        Perf.record('unit.inside', 3);
        Perf.count('unit.insideCount', 2);
      });

      final spans = r['spans'] as Map<String, dynamic>;
      final ctr = r['counters'] as Map<String, dynamic>;
      expect(spans.containsKey('unit.inside'), isTrue);
      expect(spans.containsKey('unit.before'), isFalse,
          reason: 'history must not leak into a scenario delta');
      expect(ctr['unit.insideCount'], 2);
      expect(ctr.containsKey('unit.beforeCount'), isFalse);
    });

    test('a repeated span reports the delta, not the running total', () {
      Perf.record('unit.rep', 10); // history
      final r = Perf.scenario('unit.s2', () {
        Perf.record('unit.rep', 4);
        Perf.record('unit.rep', 6);
      });
      final s = (r['spans'] as Map<String, dynamic>)['unit.rep'] as Map;
      expect(s['n'], 2, reason: 'two calls happened inside, not three');
      expect(s['totalMs'], closeTo(10, 1e-9));
      expect(s['avgMs'], closeTo(5, 1e-9));
    });

    test('a throwing scenario is recorded, not propagated', () {
      final r = Perf.scenario('unit.boom', () => throw StateError('x'));
      expect(r['error'], contains('x'));
      expect(r['wallMs'], isNotNull);
    });

    test('session totals survive a scenario', () {
      Perf.record('unit.keep', 7);
      Perf.scenario('unit.s3', () => Perf.record('unit.keep', 3));
      expect(Perf.stats['unit.keep']!.count, 2,
          reason: 'scenarios take deltas; they must not reset the session');
    });
  });

  group('the suite runs headless', () {
    test('every scenario produces a result, with or without OCCT', () {
      final report = runPerfSuite(warmup: false);
      final scen = report['scenarios'] as List;
      expect(scen, isNotEmpty);
      for (final s in scen.cast<Map<String, dynamic>>()) {
        expect(s['scenario'], isA<String>());
        expect(s['wallMs'], isA<num>());
        expect(s['note'], isNotEmpty,
            reason: 'a number nobody can interpret is not worth collecting');
      }
    });

    test('scenario names are unique — a baseline diffs on them', () {
      final names = buildScenarios().map((s) => s.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('the solver sweep really is a sweep of three sizes', () {
      final names = buildScenarios().map((s) => s.name).toSet();
      expect(names, containsAll(['solve.sweep.8', 'solve.sweep.24',
          'solve.sweep.64']));
    });

    test('report carries the identity needed to compare two devices', () {
      final r = runPerfSuite(warmup: false);
      expect(r.keys, containsAll(['suite', 'at', 'build', 'os', 'wallMs',
          'occtAvailable', 'scenarios']));
    });
  });
}
