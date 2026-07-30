// M128 — End of Part, rebuilt so the invariant is enforced rather than
// remembered.
//
// This feature has been reworked seven times (M91, M100, M102, M113, M121,
// M122 and now this). Every one of those bugs was the same shape: `eopAfter`
// (a row position) and `rolledBack` (a per-node flag) are two representations
// of one fact, and they drifted apart. So these tests are written against the
// INVARIANTS, not the arithmetic:
//
//   I1. rolledBack always reflects eopAfter — after any mutation, without the
//       caller having to remember to re-apply.
//   I2. A suppressed feature holds no solid and does not touch the join chain.
//   I3. "At the end" stays at the end as features are added.
//   I4. A feature the user just created is never born suppressed.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// Hands out a distinct solid per call so identity comparisons are meaningful.
class StubKernel implements PartKernel {
  int extrudes = 0;

  @override
  bool get available => true;
  @override
  String get info => 'stub';
  @override
  String get lastError => 'stub failure';

  KernelSolid _mk(double v) => KernelSolid(
      OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList(const [0]), Float64List(0)),
      v,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    extrudes++;
    return _mk(height);
  }

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) => _mk(3);
  @override
  KernelSolid? cutSolids(KernelSolid a, KernelSolid b) => _mk(4);
  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) => _mk(5);
  @override
  KernelSolid? filletEdges(KernelSolid base, List<int> e, List<double> r,
          {List<double> radii2 = const []}) =>
      _mk(6);
  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) =>
      [OcctEdgeInfo(1, 1, 0, 0, 0, 1, 0, 0, 5, 0, 2, 90, 1)];

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

/// Features must reference a REAL sketch or the fold cannot build them, and
/// then every assertion about solids is vacuous. [sketchName] is filled in by
/// the helpers below.
late String _sk;

ExtrudeFeature _ex(String name, String body) => ExtrudeFeature(
    name: name,
    bodyName: body,
    sketchName: _sk,
    profiles: [ProfileSel(10, 5, 200)]);

void _addRect(SketchModel s, String layer) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(0, 0, 20, 0);
  s.engine.addLine(20, 0, 20, 10);
  s.engine.addLine(20, 10, 0, 10);
  s.engine.addLine(0, 10, 0, 0);
  s.refresh();
}

/// An AppState holding a part with one real sketch and [n] extrusions of it,
/// all built, marker at the end.
Future<AppState> appWith(int n, {PartKernel? kernel}) async {
  final app = AppState()..partKernel = kernel ?? StubKernel();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m128_');
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  _addRect(app.activeChild!, app.editingLayer!);
  app.finishPartSketch();
  final p = app.currentPart!;
  _sk = p.childSketches.single.model.name;
  for (var i = 1; i <= n; i++) {
    final f = _ex('Extrusion$i', 'Solid1');
    f.output = i == 1 ? 'new' : 'join';
    f.seq = p.nextSeq();
    p.appendFeature(f);
  }
  recomputeAllFeatures(p, app.partKernel);
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('I1 — the flags always follow the marker', () {
    test('a fresh part suppresses nothing', () async {
      final p = (await appWith(3)).currentPart!;
      expect(p.features.every((f) => !f.rolledBack), isTrue);
    });

    test('the fold re-derives the flags even if nobody called apply', () async {
      // This is the class of bug that kept recurring: the marker was moved (or
      // the list changed) without applyEndOfPart, and geometry was then built
      // from stale flags.
      final p = (await appWith(3)).currentPart!;
      p.eopAfter = 1; // moved WITHOUT applyEndOfPart, as a stale path would
      recomputeAllFeatures(p, StubKernel());
      expect(p.features[0].rolledBack, isFalse);
      expect(p.features[1].rolledBack, isTrue);
      expect(p.features[2].rolledBack, isTrue);
    });

    test('deleting a feature cannot leave a flag stranded', () async {
      final p = (await appWith(4)).currentPart!;
      p.eopAfter = 3;
      recomputeAllFeatures(p, StubKernel());
      expect(p.features[3].rolledBack, isTrue);
      p.features.removeAt(0); // list shrinks under the cut
      recomputeAllFeatures(p, StubKernel());
      // 3 rows, cut at 3 -> nothing suppressed
      expect(p.features.every((f) => !f.rolledBack), isTrue);
    });

    test('an out-of-range marker is clamped, not trusted', () async {
      final p = (await appWith(2)).currentPart!;
      p.eopAfter = -5;
      recomputeAllFeatures(p, StubKernel());
      expect(p.features.every((f) => f.rolledBack), isTrue,
          reason: 'a negative cut suppresses everything, it does not crash');
      p.eopAfter = 9999;
      recomputeAllFeatures(p, StubKernel());
      expect(p.features.every((f) => !f.rolledBack), isTrue);
    });
  });

  group('I2 — a suppressed feature is truly absent', () {
    test('it holds no solid', () async {
      final p = (await appWith(3)).currentPart!;
      recomputeAllFeatures(p, StubKernel());
      expect(p.features[2].solid, isNotNull);
      p.eopAfter = 2;
      recomputeAllFeatures(p, StubKernel());
      expect(p.features[2].solid, isNull,
          reason: 'stale geometry must not survive to leak into the scene');
    });

    test('it does not consume the feature below it', () async {
      // The actual cause of the vanishing body: a suppressed feature still ran
      // and still marked its predecessor consumedByJoin, so BOTH disappeared —
      // one suppressed, the other "folded into" something not being drawn.
      final p = (await appWith(2)).currentPart!;
      p.eopAfter = 1;
      recomputeAllFeatures(p, StubKernel());
      expect(p.features[1].rolledBack, isTrue);
      expect(p.features[0].consumedByJoin, isFalse,
          reason: 'the surviving feature must still be drawable');
      expect(p.features[0].solid, isNotNull);
    });

    test('the body is still visible with the marker mid-list', () async {
      final p = (await appWith(3)).currentPart!;
      p.eopAfter = 1;
      recomputeAllFeatures(p, StubKernel());
      final drawable = p.features
          .where((f) => !f.rolledBack && !f.consumedByJoin && f.solid != null);
      expect(drawable.length, 1, reason: 'exactly the first extrusion');
      expect(drawable.first.name, 'Extrusion1');
    });

    test('suppressed features cost no kernel work', () async {
      // force: true defeats the feature cache, so the call count is
      // meaningful: only the one surviving feature may reach the kernel.
      final k = StubKernel();
      final app = await appWith(3, kernel: k);
      final p = app.currentPart!;
      p.eopAfter = 1;
      k.extrudes = 0;
      recomputeAllFeatures(p, k, force: true);
      expect(k.extrudes, 1, reason: 'the two suppressed ones must not build');
    });

    test('rolling the marker back out restores the body', () async {
      final p = (await appWith(3)).currentPart!;
      final k = StubKernel();
      p.eopAfter = 0;
      recomputeAllFeatures(p, k);
      expect(p.features.every((f) => f.solid == null), isTrue);
      p.eopAfter = kEopAtEnd;
      recomputeAllFeatures(p, k);
      expect(p.features.every((f) => f.solid != null), isTrue);
    });
  });

  group('I3/I4 — the marker stays where it means, not where it counted', () {
    test('"at end" survives adding a feature', () async {
      final p = (await appWith(2)).currentPart!;
      expect(p.eopAtEnd, isTrue);
      p.appendFeature(_ex('Extrusion3', 'Solid1'));
      recomputeAllFeatures(p, StubKernel());
      expect(p.features.last.rolledBack, isFalse,
          reason: 'a new feature under an end-marker must be built');
    });

    test('a feature created with the marker mid-list is NOT born suppressed',
        () async {
      final p = (await appWith(3)).currentPart!;
      p.eopAfter = 1; // marker above Extrusion2
      final f = _ex('Extrusion4', 'Solid1');
      p.appendFeature(f);
      recomputeAllFeatures(p, StubKernel());
      expect(f.rolledBack, isFalse,
          reason: 'Inventor builds what you just made');
      expect(p.features[1].rolledBack, isTrue,
          reason: 'and the ones that were suppressed stay suppressed');
    });

    test('the marker ends up immediately after the new feature', () async {
      final p = (await appWith(3)).currentPart!;
      p.eopAfter = 1;
      final f = _ex('Extrusion4', 'Solid1');
      p.appendFeature(f);
      final rows = partTimeline(p);
      final idx = rows.indexWhere((r) => r.isFeature && identical(r.feature, f));
      expect(p.eopAfter, idx + 1);
    });
  });

  group('setEndOfPart is the single entry point', () {
    test('dropping on the last row stores the sentinel, not the count',
        () async {
      // Otherwise the marker stops being "at the end" and every feature made
      // afterwards is born suppressed.
      final app = await appWith(3);
      final p = app.currentPart!;
      app.setEndOfPart(1);
      expect(p.eopAfter, 1);
      app.setEndOfPart(partTimeline(p).length);
      expect(p.eopAfter, kEopAtEnd);
      expect(p.eopAtEnd, isTrue);
      // and a feature added now is built
      p.appendFeature(_ex('Extrusion9', 'Solid1'));
      recomputeAllFeatures(p, app.partKernel);
      expect(p.features.last.rolledBack, isFalse);
    });

    test('it clamps out-of-range input', () async {
      final app = await appWith(2);
      final p = app.currentPart!;
      app.setEndOfPart(-10);
      expect(p.eopAfter, 0);
      app.setEndOfPart(10000);
      expect(p.eopAfter, kEopAtEnd);
    });

    test('setting the same position twice is a no-op', () async {
      final app = await appWith(3);
      final p = app.currentPart!;
      app.setEndOfPart(1);
      final before = p.eopAfter;
      app.setEndOfPart(1);
      expect(p.eopAfter, before);
    });

    test('moving the marker rebuilds the chain, so nothing vanishes', () async {
      // M122's symptom, now covered by the invariant rather than by a
      // hand-placed recompute call.
      final app = await appWith(3);
      final p = app.currentPart!;
      app.setEndOfPart(1);
      final drawable = p.features
          .where((f) => !f.rolledBack && !f.consumedByJoin && f.solid != null);
      expect(drawable.length, 1);
      expect(drawable.first.name, 'Extrusion1');
    });
  });

  group('a fillet under the marker', () {
    test('is not applied, and leaves the body it would modify visible',
        () async {
      // Straight from the device screenshot: Fillet1 sat below End of Part yet
      // the body looked filleted.
      final app = await appWith(1);
      final p = app.currentPart!;
      final base = p.features.single;
      final fil = FilletFeature(
          name: 'Fillet1',
          bodyName: 'Solid1',
          edges: [EdgeSel(0, 0, 0, 5, 1, 0)],
          radii: const [2]);
      fil.seq = p.nextSeq();
      p.appendFeature(fil);
      recomputeAllFeatures(p, app.partKernel);
      expect(fil.solid, isNotNull, reason: 'built while above the marker');
      expect(base.consumedByJoin, isTrue, reason: 'the fillet replaced it');

      // now roll the marker above the fillet
      p.eopAfter = 1;
      recomputeAllFeatures(p, app.partKernel);
      expect(fil.rolledBack, isTrue);
      expect(fil.solid, isNull, reason: 'the filleted solid must be gone');
      expect(base.consumedByJoin, isFalse,
          reason: 'the unfilleted body must still be drawn');
      expect(base.solid, isNotNull);
    });
  });
}
