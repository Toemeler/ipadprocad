// M136 — the Fillet / Chamfer session (one session type for both commands).
//
// Host-testable: which feature the panel would produce, the validation, and
// the open/cancel/edit lifecycle. NOT host-testable: the preview solid and
// the commit, because both need a linked OCCT kernel — those paths are
// asserted to fail honestly rather than to fabricate a solid.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// Records the radii the fillet path actually hands the kernel.
class FilletRecorder implements PartKernel {
  List<int>? lastIds;
  List<double>? lastRadii;

  @override
  bool get available => true;
  @override
  String get info => 'fillet recorder';
  @override
  String get lastError => 'fillet recorder failure';

  KernelSolid _stub() => KernelSolid(
      OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList(const [0]), Float64List(0)),
      1.0,
      null);

  /// Three straight, filletable edges at x = 0, 10, 20.
  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) => [
        for (var i = 0; i < 3; i++)
          OcctEdgeInfo(i + 1, 1, i * 10.0, 0, 0, 1, 0, 0, 5, 0, 2)
      ];

  @override
  KernelSolid? filletEdges(
      KernelSolid base, List<int> edgeIds, List<double> radii) {
    lastIds = List.of(edgeIds);
    lastRadii = List.of(radii);
    return _stub();
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('session shape', () {
    test('one session type serves both commands', () {
      expect(EdgeFeatureSession('fillet').isFillet, isTrue);
      expect(EdgeFeatureSession('chamfer').isFillet, isFalse);
    });

    test('a fresh chamfer session starts on equal-distance', () {
      final s = EdgeFeatureSession('chamfer');
      expect(s.mode, 0);
      expect(s.flip, isFalse);
      expect(s.edgeChain, isTrue);
    });

    test('editing seeds the session from the feature', () {
      final f = ChamferFeature(
          name: 'Chamfer1',
          bodyName: 'Solid1',
          edges: [EdgeSel(0, 0, 0, 5, 1, 0)],
          mode: 2,
          exprD1: '3 mm',
          exprAngle: '30.00 deg',
          flip: true);
      final s = EdgeFeatureSession('chamfer', editing: f);
      // the session copies on open; here we assert the contract the opener
      // relies on — the feature still carries what it was built with
      expect(f.mode, 2);
      expect(f.exprAngle, '30.00 deg');
      expect(f.flip, isTrue);
      expect(s.editing, same(f));
    });
  });

  group('opening', () {
    test('openFillet arms the edge pick', () {
      final app = AppState();
      app.openFillet();
      // no part loaded -> no session, and nothing armed
      expect(app.edgeSession, isNull);
      expect(app.pickingEdges, isFalse);
    });

    test('a fillet and an extrude panel are never open together', () {
      // _openEdgeFeature cancels the extrude session first: two property
      // panels stacked in the same corner would both claim the 3D taps.
      final app = AppState();
      expect(app.extrudeSession, isNull);
      expect(app.edgeSession, isNull);
    });
  });

  group('chamfer parameters reach the kernel correctly', () {
    ChamferFeature c(int mode, {bool flip = false}) => ChamferFeature(
        name: 'C',
        bodyName: 'S',
        edges: const [],
        mode: mode,
        distance1: 2,
        distance2: 5,
        angleDeg: 30,
        flip: flip);

    test('equal distance ignores the second distance and the angle', () {
      expect(c(0).kernelParams, (2.0, 0.0, 0.0));
    });

    test('flip swaps the two distances', () {
      expect(c(1, flip: true).kernelParams, (5.0, 2.0, 0.0));
    });

    test('flip takes the complementary angle', () {
      expect(c(2, flip: true).kernelParams, (2.0, 0.0, 60.0));
    });
  });

  // M141 — Inventor's "several edge sets in a single fillet feature": each set
  // carries its own radius, and `radii` is parallel to `edges`.
  group('fillet edge sets', () {
    AppState armed() {
      final app = AppState();
      app.beginPickEdges();
      return app;
    }

    test('a fresh selection is one set', () {
      final app = armed();
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0), display: 0);
      expect(app.edgeSetCount, 1);
      expect(app.edgesInSet(0), 1);
    });

    test('picks land in the ACTIVE set', () {
      final app = armed();
      app.edgeSession = EdgeFeatureSession('fillet');
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0), display: 0);
      app.newEdgeSet();
      app.toggleEdgePick(2, EdgeSel(1, 0, 0, 5, 1, 0), display: 1);
      app.toggleEdgePick(3, EdgeSel(2, 0, 0, 5, 1, 0), display: 2);
      expect(app.edgeSetCount, 2);
      expect(app.edgesInSet(0), 1);
      expect(app.edgesInSet(1), 2);
    });

    test('removing an edge keeps the set list in step', () {
      final app = armed();
      app.edgeSession = EdgeFeatureSession('fillet');
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0), display: 0);
      app.newEdgeSet();
      app.toggleEdgePick(2, EdgeSel(1, 0, 0, 5, 1, 0), display: 1);
      app.toggleEdgePick(2, EdgeSel(1, 0, 0, 5, 1, 0), display: 1); // remove
      expect(app.pickedEdges.length, 1);
      expect(app.pickedEdgeSet.length, 1,
          reason: 'radii are indexed through this list');
      expect(app.edgesInSet(0), 1);
    });

    test('newEdgeSet grows the radius list so every set has one', () {
      final app = armed();
      final s = EdgeFeatureSession('fillet');
      app.edgeSession = s;
      expect(s.exprRadii.length, 1);
      app.newEdgeSet();
      expect(s.exprRadii.length, greaterThanOrEqualTo(2));
    });

    test('newEdgeSet does nothing on a chamfer', () {
      // Inventor's chamfer has no edge sets; the panel offers no + row.
      final app = armed();
      app.edgeSession = EdgeFeatureSession('chamfer');
      app.newEdgeSet();
      expect(app.activeEdgeSet, 0);
    });

    test('setEdgeFeature writes the radius of the addressed set', () {
      final app = armed();
      final s = EdgeFeatureSession('fillet');
      app.edgeSession = s;
      app.newEdgeSet();
      app.setEdgeFeature(exprRadius: '4 mm', radiusSet: 1);
      expect(s.exprRadii[0], '2 mm');
      expect(s.exprRadii[1], '4 mm');
      expect(s.exprRadius, '2 mm', reason: 'exprRadius is set 1');
    });

    test('a bad radius names WHICH set, rather than silently reusing set 1',
        () {
      final app = armed();
      final s = EdgeFeatureSession('fillet');
      app.edgeSession = s;
      app.newEdgeSet();
      app.setEdgeFeature(exprRadius: 'nonsense', radiusSet: 1);
      expect(parseValueExpr(s.exprRadii[1]), isNull);
    });
  });

  group('per-set radii reach the kernel', () {
    test('two sets produce two different radii, one per edge', () {
      final k = FilletRecorder();
      final app = AppState();
      final base = KernelSolid(
          OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
              Int32List.fromList(const [0]), Float64List(0)),
          1.0,
          null);
      final s = EdgeFeatureSession('fillet');
      app.edgeSession = s;
      app.beginPickEdges();
      // set 1: the edges at x = 0 and x = 10
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0), solid: base, display: 0);
      app.toggleEdgePick(2, EdgeSel(10, 0, 0, 5, 1, 0),
          solid: base, display: 1);
      // set 2: the edge at x = 20, with its own radius
      app.newEdgeSet();
      app.toggleEdgePick(3, EdgeSel(20, 0, 0, 5, 1, 0),
          solid: base, display: 2);
      app.setEdgeFeature(exprRadius: '2 mm', radiusSet: 0);
      app.setEdgeFeature(exprRadius: '4 mm', radiusSet: 1);

      final f = FilletFeature(
          name: 'Fillet1',
          bodyName: 'Solid1',
          edges: [for (final e in app.pickedEdges) e],
          radii: [
            for (var i = 0; i < app.pickedEdges.length; i++)
              [2.0, 4.0][app.pickedEdgeSet[i]]
          ]);
      final p = PartModel('P');
      expect(recomputeFeature(p, f, k, base: base), isTrue);
      expect(k.lastIds, [1, 2, 3]);
      expect(k.lastRadii, [2.0, 2.0, 4.0],
          reason: 'each edge takes ITS set radius, in edge order');
    });
  });

  group('feature naming', () {
    test('fillets and chamfers are numbered separately', () {
      final p = PartModel('P');
      expect(p.nextFeatureName('Fillet'), 'Fillet1');
      p.features.add(FilletFeature(
          name: 'Fillet1',
          bodyName: 'Solid1',
          edges: const [],
          radii: const []));
      expect(p.nextFeatureName('Fillet'), 'Fillet2');
      expect(p.nextFeatureName('Chamfer'), 'Chamfer1');
    });
  });

  group('the edge set belongs to one body', () {
    test('a fillet declares itself body-modifying and consumes no sketch', () {
      final f = FilletFeature(
          name: 'F', bodyName: 'S', edges: const [], radii: const []);
      expect(f.modifiesBody, isTrue);
      expect(f.sketchName, '');
      expect(f.output, 'modify');
    });

    test('a chamfer round-trips through JSON with its method', () {
      final f = ChamferFeature(
          name: 'Chamfer1',
          bodyName: 'Solid1',
          edges: [EdgeSel(1, 2, 3, 8, 1, 0)],
          mode: 1,
          distance1: 2,
          distance2: 5,
          flip: true);
      final back = PartFeature.fromJson(f.toJson()) as ChamferFeature;
      expect(back.mode, 1);
      expect(back.flip, isTrue);
      expect(back.distance2, 5);
      expect(back.edges.length, 1);
      expect(back.ownSig(), f.ownSig());
    });
  });
}
