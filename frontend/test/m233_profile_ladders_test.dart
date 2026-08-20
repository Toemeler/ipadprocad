// M233 / S11 — the profile-complexity tier, and the determination it settles.
//
// The suite measured `ffi.occt.sweepProfile` at 81.9 ms and a real profile
// reached 102 244 ms. The gap was not a measurement error: no tier anywhere
// sweeps a profile of more than a few dozen segments, so the operation had no
// instrument pointed at it at any size a real drawing reaches.
// `perf_scenarios_profile.dart` is that instrument. This file pins the two
// properties that make it trustworthy — that it stays OUT of the ordinary
// suite, and that its fixtures are what they claim to be.
//
// The self-intersection group is more than a fixture check. It is the evidence
// for S11 §1.2: the field sketch reported 116 loops, 110 of them with an area
// printing as 0.00, and the question was whether those were real crossings of
// its 1200-vertex polyline or artefacts of node snapping. Euler says a closed
// curve with k transversal self-crossings bounds exactly k + 1 faces. Planting
// a known k and counting is how that stops being an assumption.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/qcad_engine.dart' show Geo;
import 'package:prototype/part_model.dart';
import 'package:prototype/perf.dart';
import 'package:prototype/perf_scenarios.dart';
import 'package:prototype/perf_scenarios_profile.dart';
import 'package:prototype/perf_scenarios_ui.dart';

Geo _closed(List<double> pts) =>
    Geo(Geo.polyline, [1.0, (pts.length ~/ 2).toDouble(), ...pts]);

ProfileInput _input(List<Geo> g) =>
    ProfileInput(g, const <String>[], const <String>{}, 0);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the profile tier is opt-in', () {
    test('no profile scenario is in the ordinary suite', () {
      // One rung of profile.sweep.segments reproduces the field's
      // 1200-segment sweep, and that sweep cost 102 seconds. Firing it from an
      // ordinary bug report would make the app look broken while diagnosing
      // it — the same reason the stress tier is opt-in, only more so.
      final ordinary = [
        ...buildScenarios().map((s) => s.name),
        ...buildUiScenarios().map((s) => s.name),
      ];
      expect(ordinary.where((n) => n.startsWith('profile.')), isEmpty);
    });

    test('every profile scenario is named and explained', () {
      for (final s in buildProfileScenarios()) {
        expect(s.name, startsWith('profile.'));
        expect(s.note.length, greaterThan(20));
      }
    });

    test('names are unique', () {
      final names = buildProfileScenarios().map((s) => s.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('the 2D ladders exist even without a kernel', () {
      // Same reasoning as the stress tier: the sweep ladders need OCCT and are
      // skipped on a host without it, but the arrangement ladders must run on
      // CI or a break in them waits for a device.
      final names = buildProfileScenarios().map((s) => s.name).toSet();
      expect(
          names,
          containsAll([
            'profile.loops.segments',
            'profile.loops.count',
            'profile.loops.selfIntersect',
          ]));
    });
  });

  group('the fixtures are what they claim', () {
    test('a convex polygon is exactly one loop, at every size on the ladder',
        () {
      for (final n in const [32, 128, 512]) {
        final pts = convexLoop(n, 60);
        expect(pts.length, n * 2);
        expect(profileLoopCount(_input([_closed(pts)])), 1,
            reason: 'a simple closed curve bounds one face, whatever its '
                'segment count — if this ever fails the ladder is measuring '
                'the arrangement misbehaving, not the arrangement');
      }
    });

    test('squareGrid gives one loop per square, four segments each', () {
      for (final n in const [8, 32, 128]) {
        final geo = squareGrid(n);
        expect(geo.length, n);
        expect(profileLoopCount(_input(geo)), n);
      }
    });

    test('subdivision changes the vertex count and nothing else', () {
      // This is what lets the fixture carry the field's SHAPE — ~1200
      // vertices — while holding the crossing count at ~110.
      final plain = starLoop(9, 60);
      final fine = starLoop(9, 60, subdiv: 20);
      expect(plain.length, 9 * 2);
      expect(fine.length, 9 * 20 * 2);
      expect(profileLoopCount(_input([_closed(plain)])),
          profileLoopCount(_input([_closed(fine)])));
    });
  });

  group('the phantoms are crossings — S11 section 1.2', () {
    // {n/2} with n odd crosses itself exactly n times, so the expected loop
    // count is n + 1: Euler's F = E - V + 2 with V = n + k and E = n + 2k,
    // less the unbounded face.
    for (final k in const [9, 65, 111]) {
      test('star{$k/2} bounds ${k + 1} faces', () {
        final pts = starLoop(k, 60);
        expect(profileLoopCount(_input([_closed(pts)])), k + 1,
            reason: 'bounded faces must equal crossings + 1; if this does not '
                'hold, the field sketch\'s 110 near-zero loops cannot be '
                'attributed to self-intersection and S11 section 1.2 is wrong');
      });
    }

    test('~1200 vertices carrying 111 crossings — the field\'s shape', () {
      // The case the whole determination is about: a polyline of the field's
      // vertex count whose self-crossings are known by construction.
      final pts = starLoop(111, 60, subdiv: 11);
      expect(pts.length ~/ 2, 1221);
      expect(profileLoopCount(_input([_closed(pts)])), 112);
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('snapping-scale detail does NOT manufacture loops', () {
      // The competing hypothesis. nodeOf snaps within 1e-6 and the arrangement
      // drops faces at 1e-9, so perturbations at that scale must produce no
      // extra loop at all — which is why the 110 survivors could not have come
      // from snapping.
      final pts = convexLoop(256, 60);
      for (var i = 0; i < pts.length; i += 2) {
        pts[i] += (i % 4 == 0) ? 1e-9 : -1e-9;
      }
      expect(profileLoopCount(_input([_closed(pts)])), 1);
    });
  });

  group('the ladders record the rung they reached', () {
    test('profile.loops.segments reports maxSize', () {
      Perf.resetForTest();
      final s = buildProfileScenarios()
          .firstWhere((sc) => sc.name == 'profile.loops.segments');
      Perf.scenario(s.name, s.run);
      expect(Perf.gauges.containsKey('profile.loops.segments.maxSize'), isTrue);
      expect(Perf.gauges['profile.loops.segments.maxSize'], greaterThan(0),
          reason: 'a ladder that cleared no rung measured nothing');
    }, timeout: const Timeout(Duration(minutes: 5)));

    test('the self-intersection scenario flags a mismatch rather than passing '
        'silently', () {
      Perf.resetForTest();
      final s = buildProfileScenarios()
          .firstWhere((sc) => sc.name == 'profile.loops.selfIntersect');
      Perf.scenario(s.name, s.run);
      expect(Perf.counters['profile.selfIntersect.mismatch'] ?? 0, 0,
          reason: 'loops == crossings + 1 held for every planted rung');
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
