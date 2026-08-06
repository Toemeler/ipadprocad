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
import 'package:prototype/constraints.dart';
import 'package:prototype/gear.dart';
import 'package:prototype/perf.dart';
import 'package:prototype/perf_scenarios.dart';
import 'package:prototype/perf_scenarios_ui.dart';
import 'package:prototype/solver.dart';

void main() {
  setUp(Perf.resetForTest);
  _uiSuite();

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

    // M212 — the first version of this group asserted the TAG and the tooth
    // count and stopped there, so it passed while `gear.curve` measured 0.000
    // ms. Two separate things have to hold for that scenario to mean anything:
    // the parameters must actually VALIDATE (an invalid gear returns its two
    // raw vertices instead of throwing, which is indistinguishable from a fast
    // one in a timing report), and the memo has to be defeatable (an identical
    // fixture hits the cache on every call after the first).
    test('the gear fixture generates a real outline, not the fallback', () {
      final pts = gearCurve(gearFixture(teeth: 20));
      expect(pts.length, greaterThan(2),
          reason: 'two points is gearCurve\'s invalid-parameter fallback — a '
              'scenario measuring that measures nothing');
      expect(gearParams(gearFixture(teeth: 20))!.valid, isTrue);
    });

    test('tooth count drives outline size, so the gear sweep really sweeps',
        () {
      clearGearCurveCache();
      final small = gearCurve(gearFixture(teeth: 10)).length;
      final big = gearCurve(gearFixture(teeth: 40)).length;
      expect(big, greaterThan(small * 2));
    });

    test('clearing the memo makes the cold cost measurable again', () {
      clearGearCurveCache();
      final g = gearFixture(teeth: 20);
      final first = gearCurve(g);
      expect(identical(gearCurve(g), first), isTrue,
          reason: 'the memo is what made the scenario measure 0.000 ms');
      clearGearCurveCache();
      expect(identical(gearCurve(g), first), isFalse,
          reason: 'without this the cold path is unreachable from the suite');
    });

    test('ringProfile emits (x, y, bulge) triplets', () {
      expect(ringProfile(12, 40).length, 36);
    });
  });

  // M212 — the second fixture gap. `2d.paint.ent.dofColour` was 85% of all
  // painting on the device and ~0 in the suite, because the fixture had almost
  // no constraints and no analysis at all: the painter's colouring branch is
  // guarded by `hasAnalysis` and short-circuited on every entity.
  group('the constraint fixture has the density a real sketch has', () {
    test('roughly 1.5 constraints per entity, as the device sketch had', () {
      final gs = sketchFixture(24), cs = constraintFixture(24);
      expect(gs.length, 48);
      // 23 equal + 48 coincident + fix + dimension = 73 over 48 entities
      expect(cs.length / gs.length, greaterThan(1.2));
    });

    test('the entities are COUPLED, not independent', () {
      // Every line is bound to the circles at both of its ends. Without this
      // the solver can decompose the sketch into n tiny systems and the cost
      // curve is a lie.
      final cs = constraintFixture(24);
      expect(cs.where((c) => c.type == CType.coincident).length, 48);
    });

    test('it is grounded, so the analysis reports a finite DOF', () {
      expect(constraintFixture(24).any((c) => c.type == CType.fix), isTrue);
    });

    test('the analysis it produces really constrains SOME carriers', () {
      // The number that matters: `carrierFixed` has to return a MIX. All-true
      // or all-false and the painter takes one branch for every entity, which
      // is the degenerate case the old fixture was stuck in.
      final gs = sketchFixture(12), cs = constraintFixture(12);
      final a = analyzeSketch(gs, cs);
      final fixed = [
        for (var i = 0; i < gs.length; i++)
          if (a.carrierFixed(i)) i
      ];
      expect(fixed, isNotEmpty,
          reason: 'nothing constrained means nothing to colour');
      expect(fixed.length, lessThan(gs.length),
          reason: 'everything constrained is equally degenerate');
    });

    test('the constraints are satisfied by the geometry as built', () {
      // A fixture that starts violated measures the solver digging itself out
      // of a hole, not the solver doing a sketch's ordinary work.
      final gs = sketchFixture(12), cs = constraintFixture(12);
      expect(solveConstraints([...gs], cs, iterations: 25), isTrue);
    });
  }, timeout: const Timeout(Duration(minutes: 2)));

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
    // Run it ONCE for the whole group. The suite is a benchmark: since M212
    // its drag scenario really moves a grip and its analysis sweep really
    // differentiates a 448-parameter system, so running it per test would
    // spend minutes proving the same thing repeatedly.
    late final Map<String, dynamic> report;
    setUpAll(() => report = runPerfSuite(warmup: false));

    test('every scenario produces a result, with or without OCCT', () {
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

    test('the DOF analysis is swept too — it was unmeasured entirely', () {
      final names = buildScenarios().map((s) => s.name).toSet();
      expect(names, containsAll(
          ['analysis.sweep.8', 'analysis.sweep.24', 'analysis.sweep.64']));
    });

    test('the gear scenario measures a generated outline, not a cache hit', () {
      Perf.resetForTest();
      final g = buildScenarios().firstWhere((s) => s.name == 'gear.curve.20');
      final r = Perf.scenario(g.name, g.run);
      final spans = r['spans'] as Map<String, dynamic>;
      // 20 COLD builds — one per iteration, each after the memo was cleared.
      expect((spans['gear.curve'] as Map)['n'], 20,
          reason: 'a memo hit is not a measurement of generating a gear');
      expect((spans['gear.curve.cached'] as Map)['n'], 200);
      expect(Perf.gauges['gear.curve.points'] ?? 0, greaterThan(100),
          reason: 'a two-point result is the invalid-parameter fallback');
    });

    test('report carries the identity needed to compare two devices', () {
      expect(report.keys, containsAll(['suite', 'at', 'build', 'os', 'wallMs',
          'occtAvailable', 'scenarios']));
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}

// The UI half. These need a binding, which `flutter test` provides.
void _uiSuite() {
  group('ui scenarios', () {
    testWidgets('the drag scenario actually solves', (tester) async {
      Perf.resetForTest();
      final drag = buildUiScenarios().firstWhere((s) => s.name == 'ui.drag60');
      Perf.scenario(drag.name, drag.run);
      // The point of the test: displayGeometry returns early unless BOTH
      // dragGrip and dragPos are set. If the scenario ever stops setting the
      // grip it would still "pass" while measuring nothing, so pin the counter
      // that proves a solve happened.
      final solves = Perf.counters['2d.displayGeometry.solves'] ?? 0;
      expect(solves, greaterThan(0),
          reason: 'a drag scenario that never solves measures nothing');
    });

    testWidgets('paint scenarios record the painter phases', (tester) async {
      Perf.resetForTest();
      final p = buildUiScenarios().firstWhere((s) => s.name == 'ui.paint.sweep.8');
      Perf.scenario(p.name, p.run);
      expect(Perf.stats.containsKey('2d.paint'), isTrue,
          reason: 'the real painter must have run, not a stand-in');
    });

    // M212 — the fixture used to paint an unconstrained sketch with a null
    // analysis, so the painter's DOF-colour branch short-circuited on every
    // entity. The gauge is what a reader of the report checks; pin it so the
    // fixture cannot quietly lose its constraints again.
    testWidgets('paint scenarios paint a CONSTRAINED sketch', (tester) async {
      Perf.resetForTest();
      resetUiFixturesForTest();
      final p =
          buildUiScenarios().firstWhere((s) => s.name == 'ui.paint.sweep.8');
      Perf.scenario(p.name, p.run);
      expect(Perf.gauges['ui.paint.constraints'] ?? 0, greaterThan(8),
          reason: 'an unconstrained sketch skips the phase that was 85% of '
              'painting on the device');
    });

    // M212 — the third gap. `ui.snapHover` drove `setHover`, which does not
    // route through the snap path at all, so `2d.snap` was absent from every
    // report the suite has ever produced.
    testWidgets('the snap scenario actually snaps', (tester) async {
      Perf.resetForTest();
      final s =
          buildUiScenarios().firstWhere((sc) => sc.name == 'ui.snapHover');
      Perf.scenario(s.name, s.run);
      expect(Perf.stats.containsKey('2d.snap'), isTrue,
          reason: 'a snap scenario that never snaps measures pickEntity');
      expect(Perf.stats['2d.snap']!.count, 120,
          reason: 'one snap per pointer-move event, as the viewport does');
    });

    testWidgets('ui scenario names are unique and non-empty', (tester) async {
      final names = buildUiScenarios().map((s) => s.name).toList();
      expect(names.toSet().length, names.length);
      expect(names.every((n) => n.startsWith('ui.')), isTrue);
    });
  }, timeout: const Timeout(Duration(minutes: 5)));
}
