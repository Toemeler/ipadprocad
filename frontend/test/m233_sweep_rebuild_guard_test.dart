// M233 / S11 — the sweep does not rebuild when nothing about it changed.
//
// WHAT THIS PINS, AND WHY IT IS DIFFERENTIAL
// ------------------------------------------
// A user swept a 1218-segment profile. The same sweep ran THREE times — the
// preview, the commit, and `recomputeAllFeatures` folding the part afterwards
// — each producing `tris=91646`, together 310.75 s and 53 % of the session.
// The guard in `_recomputeSweep` removes the third.
//
// A guard that skips work is only safe if what it hands back is what the work
// would have produced. That claim is proved here the way
// `OPTIMIZATION_PLAN_2.md` §1.4 requires: **differentially**. The reference is
// the old behaviour — a genuine recomputation, obtained by clearing the guard's
// key and nothing else — and it is produced in THIS run, on THIS machine, and
// compared against what the guard serves. There is no recorded constant
// anywhere in this file, so there is nothing here that can pass on Linux and
// fail on macOS the way round one's four goldens did.
//
// THE FAKE HAS TO EARN THE COMPARISON
// -----------------------------------
// `SweepRecorder` in m131b returns a constant solid, so "the outputs match"
// would be true even if the guard served a solid built from different
// arguments. [_ArgSensitiveKernel] instead derives its result from the
// arguments themselves, so equal output IS the claim: same volume means the
// same profile points, the same placement, the same path and the same
// orientation/taper/twist reached the kernel.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// A kernel whose sweep result is a pure function of its arguments.
class _ArgSensitiveKernel implements PartKernel {
  int sweeps = 0;
  int extrudes = 0;
  /// S14 — what the last sweep was told its path MEANT.
  int lastPathMode = -1;

  @override
  bool get available => true;
  @override
  String get info => 'arg-sensitive fake';
  @override
  String get lastError => 'arg-sensitive fake failure';

  KernelSolid _mk(double v) => KernelSolid(
      OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList(const [0]), Float64List(0)),
      v,
      null);

  /// Folds every argument into one number. Any change to any of them moves it,
  /// so two equal volumes mean two identical argument lists.
  static double _fold(List<List<List<Offset>>> groups, List<double> mat34,
      List<double> pathPts, int orientation, double taperDeg, double twistDeg,
      int pathMode) {
    var acc = 17.0;
    void mix(double x) => acc = (acc * 31.0 + x) % 1000000007.0;
    for (final g in groups) {
      for (final loop in g) {
        for (final p in loop) {
          mix(p.dx);
          mix(p.dy);
        }
        mix(-1);
      }
      mix(-2);
    }
    for (final m in mat34) {
      mix(m);
    }
    for (final p in pathPts) {
      mix(p);
    }
    mix(orientation.toDouble());
    mix(taperDeg);
    mix(twistDeg);
    // S14 — the path MODE is an argument now, so it has to be in the fold or
    // "equal output means equal arguments" stops being true of it.
    mix(pathMode.toDouble());
    return acc;
  }

  @override
  KernelSolid? extrude(
      List<List<List<Offset>>> g, double h, double t, List<double> m) {
    extrudes++;
    return _mk(h);
  }

  @override
  KernelSolid? sweep(List<List<List<Offset>>> groups, List<double> mat34,
      List<double> pathPts,
      {int orientation = 0,
       double taperDeg = 0,
       double twistDeg = 0,
       int pathMode = SweepPathMode.auto}) {
    sweeps++;
    lastPathMode = pathMode;
    return _mk(_fold(
        groups, mat34, pathPts, orientation, taperDeg, twistDeg, pathMode));
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void _rect(SketchModel s, String layer, double x0, double y0, double x1,
    double y1) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

/// A part with one XY sketch: a 20x10 rectangle, and TWO candidate path lines
/// (geometry indices 4 and 5) so a path change can be expressed.
Future<AppState> _appWithSketch(_ArgSensitiveKernel k) async {
  final app = AppState()..partKernel = k;
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m233_');
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  final sm = app.activeChild!;
  _rect(sm, app.editingLayer!, 0, 0, 20, 10);
  sm.engine.addLine(30, 0, 30, 40); // index 4 — the path
  sm.engine.addLine(50, 0, 50, 70); // index 5 — a DIFFERENT path
  // index 6 — an ARC. S14: sketchCurve samples it with arcSamples: 64, so
  // every joint in the resolved polyline is an artefact of that sampling and
  // the path mode must come out `smooth`.
  sm.engine.addArc(80, 0, 25, 0, 1.2);
  // index 7 — a POLYLINE somebody drew, with a bend in it. Its vertices are
  // design features however shallow, so its mode must be `polyline`.
  sm.engine.addPolyline([0, 50, 10, 60, 20, 50]);
  sm.refresh();
  app.finishPartSketch();
  return app;
}

const int kPathGeo = 4;
const int kArcGeo = 6;
const int kPolyGeo = 7;

/// Commits a sweep and returns (app, the committed feature).
Future<(AppState, SweepFeature)> _sweptPart(_ArgSensitiveKernel k) async {
  final app = await _appWithSketch(k);
  app.openSweep();
  final sk = app.currentPart!.childSketches.single.model.name;
  app.sweepPathPicked(sk, kPathGeo);
  final ok = await app.applyExtrude();
  expect(ok, isTrue,
      reason: 'the fixture must commit before anything is pinned');
  final f = app.currentPart!.features.whereType<SweepFeature>().single;
  return (app, f);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the sweep rebuild guard', () {
    test('an unchanged rebuild does not reach the kernel', () async {
      final k = _ArgSensitiveKernel();
      final (app, f) = await _sweptPart(k);
      final part = app.currentPart!;

      // The state the fold sees right after a commit: a solid built through
      // the single-feature entry point, which never sets builtSig. Nulling it
      // is what makes this test reach the guard at all — with builtSig set,
      // recomputeAllFeatures short-circuits on its OWN key and never calls
      // down into _recomputeSweep, so the thing being pinned would not run.
      //
      // INTEGRATOR (2026-08-21): this used to null builtSig and then assert
      // that a recomputeFeature call still reached the kernel ("the commit
      // itself must still compute"). It does not, and should not: the sweep
      // guard keys on `sweptFrom`, not on `builtSig`, and every other test in
      // this file clears `sweptFrom` when it wants a genuine recomputation —
      // see the REFERENCE in the next test, which says so in as many words.
      // The commit inside _sweptPart already performed that computation; it IS
      // the second of the three identical runs, and staging a fourth to stand
      // in for it only asserted that the optimisation does not work.
      //
      // What the test exists to pin is the THIRD run, and that is below.
      f.builtSig = null;

      final afterCommit = k.sweeps;
      expect(recomputeAllFeatures(part, k), isTrue);
      expect(k.sweeps, afterCommit,
          reason: 'the fold must reuse the solid the commit just built — this '
              'is the third of the three identical runs');
    });

    test('what the guard serves equals what a recomputation produces',
        () async {
      final k = _ArgSensitiveKernel();
      final (app, f) = await _sweptPart(k);
      final part = app.currentPart!;

      // REFERENCE — the old behaviour. Clearing sweptFrom defeats the guard
      // and nothing else, so this is a genuine recomputation of the same
      // feature from the same sketches.
      f.sweptFrom = null;
      expect(recomputeFeature(part, f, k), isTrue);
      final reference = f.solid!.volume;
      final afterReference = k.sweeps;

      // NEW — the guard serves it.
      expect(recomputeFeature(part, f, k), isTrue);
      expect(k.sweeps, afterReference, reason: 'the guard must have fired');
      expect(f.solid!.volume, reference,
          reason: 'the reused solid must be the one a recomputation would '
              'have produced, argument for argument');
    });

    test('a changed orientation rebuilds, and changes the result', () async {
      final k = _ArgSensitiveKernel();
      final (app, f) = await _sweptPart(k);
      final part = app.currentPart!;
      expect(recomputeFeature(part, f, k), isTrue);
      final before = f.solid!.volume;
      final n = k.sweeps;

      f.orientation = f.orientation == 0 ? 1 : 0;
      expect(recomputeFeature(part, f, k), isTrue);
      expect(k.sweeps, n + 1, reason: 'orientation is a kernel argument');
      expect(f.solid!.volume, isNot(before));
    });

    test('a changed taper rebuilds', () async {
      final k = _ArgSensitiveKernel();
      final (app, f) = await _sweptPart(k);
      final part = app.currentPart!;
      expect(recomputeFeature(part, f, k), isTrue);
      final n = k.sweeps;

      f.taperDeg = f.taperDeg + 2.5;
      expect(recomputeFeature(part, f, k), isTrue);
      expect(k.sweeps, n + 1);
    });

    test('a changed PATH rebuilds — the guard reads the resolved geometry, '
        'not just the feature fields', () async {
      final k = _ArgSensitiveKernel();
      final (app, f) = await _sweptPart(k);
      final part = app.currentPart!;
      expect(recomputeFeature(part, f, k), isTrue);
      final before = f.solid!.volume;
      final n = k.sweeps;

      // Point the feature at the other line. resolvePath re-scores every
      // candidate curve, so this changes the POINTS handed to the kernel.
      final sk = f.path!.sketchName;
      f.path = CurveSel(sk, 5, 50, 0, 50, 70, 70);
      expect(recomputeFeature(part, f, k), isTrue);
      expect(k.sweeps, n + 1, reason: 'a different path is a different sweep');
      expect(f.solid!.volume, isNot(before));
    });

    // ---- S14: the path KIND is an argument now ------------------------
    //
    // The shim used to infer whether a path's joints were sampling artefacts
    // from a 5.625-degree threshold. The caller knows, so it says: an arc is
    // smooth WHATEVER its joint angle, and a drawn vertex is a design feature
    // HOWEVER shallow. These pin that the classification comes from the
    // entity and survives the whole chain into the kernel.
    //
    // WHAT IS NOT PINNED HERE, said plainly: that a mode change ALONE forces
    // a rebuild. That needs two entity kinds resolving to identical points
    // under different modes, and no such pair exists — a line and a two-point
    // straight polyline both classify `polyline`, and everything else samples
    // differently. The mode is written into _sweepArgSig's key beside
    // `orientation`; that is argued from the code, not from a test here.

    test('an ARC path is declared smooth, a drawn one is not', () async {
      final k = _ArgSensitiveKernel();
      final (app, f) = await _sweptPart(k);
      final part = app.currentPart!;
      final sk = f.path!.sketchName;

      // the fixture's own path is a LINE: two points somebody drew
      f.sweptFrom = null;
      expect(recomputeFeature(part, f, k), isTrue);
      expect(k.lastPathMode, SweepPathMode.polyline,
          reason: 'a line is two drawn points, not a sampled curve');

      // an ARC — sampleEntity splits it into 64 equal steps, so every joint
      // in the resolved polyline is an artefact of that sampling
      f.path = CurveSel(sk, kArcGeo, 105, 0, 89.05898, 23.30097, 30);
      expect(recomputeFeature(part, f, k), isTrue);
      expect(k.lastPathMode, SweepPathMode.smooth,
          reason: 'an arc is smooth whatever its sampled joint angle');

      // a POLYLINE the user drew, bend and all
      f.path = CurveSel(sk, kPolyGeo, 0, 50, 20, 50, 28.284271);
      expect(recomputeFeature(part, f, k), isTrue);
      expect(k.lastPathMode, SweepPathMode.polyline,
          reason: 'a drawn vertex is a design feature however shallow');
    });

    test('the guard serves what a recomputation produces, with an ARC path',
        () async {
      final k = _ArgSensitiveKernel();
      final (app, f) = await _sweptPart(k);
      final part = app.currentPart!;
      f.path = CurveSel(f.path!.sketchName, kArcGeo, 105, 0, 89.05898,
          23.30097, 30);

      // REFERENCE — a genuine recomputation, this run, this machine.
      f.sweptFrom = null;
      expect(recomputeFeature(part, f, k), isTrue);
      final reference = f.solid!.volume;
      final afterReference = k.sweeps;
      expect(k.lastPathMode, SweepPathMode.smooth);

      // NEW — the guard serves it, and the mode is among the arguments the
      // fake folded into that volume.
      expect(recomputeFeature(part, f, k), isTrue);
      expect(k.sweeps, afterReference, reason: 'the guard must have fired');
      expect(f.solid!.volume, reference,
          reason: 'the reused solid must be the one a recomputation would '
              'have produced, argument for argument — path mode included');
    });

    test('disposing the solid forces a rebuild', () async {
      final k = _ArgSensitiveKernel();
      final (app, f) = await _sweptPart(k);
      final part = app.currentPart!;
      expect(recomputeFeature(part, f, k), isTrue);
      final n = k.sweeps;

      f.disposeSolid();
      expect(f.sweptFrom, isNull,
          reason: 'a disposed solid must not look "already swept"');
      expect(recomputeFeature(part, f, k), isTrue);
      expect(k.sweeps, n + 1);
    });

    test('a sweep that cannot resolve its path goes SICK, as before', () async {
      // The M182 contract the shared dispose used to provide. _recomputeSweep
      // now owns its own disposal, so this is the test that says it still does.
      final k = _ArgSensitiveKernel();
      final (app, f) = await _sweptPart(k);
      final part = app.currentPart!;
      expect(recomputeFeature(part, f, k), isTrue);
      expect(f.solid, isNotNull);

      f.path = null; // no path selected
      expect(recomputeFeature(part, f, k), isFalse);
      expect(f.solid, isNull,
          reason: 'a failed recompute must leave no solid behind');
      expect(f.sweptFrom, isNull);
      expect(f.computeError, isNotNull);
    });
  });
}
