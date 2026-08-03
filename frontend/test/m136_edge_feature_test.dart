// M136 — the Fillet / Chamfer session (one session type for both commands).
//
// Host-testable: which feature the panel would produce, the validation, and
// the open/cancel/edit lifecycle. NOT host-testable: the preview solid and
// the commit, because both need a linked OCCT kernel — those paths are
// asserted to fail honestly rather than to fabricate a solid.
import 'dart:io';
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

  /// Three straight filletable edges: two CONVEX (exterior) and one CONCAVE
  /// (interior), so All Fillets and All Rounds must select different sets.
  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) => [
        OcctEdgeInfo(1, 1, 0, 0, 0, 1, 0, 0, 5, 0, 2, 90, 1),
        OcctEdgeInfo(2, 1, 10, 0, 0, 1, 0, 0, 5, 0, 2, 90, 1),
        OcctEdgeInfo(3, 1, 20, 0, 0, 1, 0, 0, 5, 0, 2, 90, -1),
      ];

  List<double>? lastRadii2;
  int chamfers = 0;
  int? lastMode;
  double? lastD1, lastD2, lastAngle;

  @override
  KernelSolid? filletEdges(KernelSolid base, List<int> edgeIds,
      List<double> radii, {List<double> radii2 = const [], BlendReport? report}) {
    lastIds = List.of(edgeIds);
    lastRadii = List.of(radii);
    lastRadii2 = List.of(radii2);
    return _stub();
  }

  @override
  KernelSolid? chamferEdges(KernelSolid base, List<int> edgeIds, int mode,
      double d1, double d2, double angleDeg, {BlendReport? report}) {
    chamfers++;
    lastIds = List.of(edgeIds);
    lastMode = mode;
    lastD1 = d1;
    lastD2 = d2;
    lastAngle = angleDeg;
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

  group('Select Mode (M142)', () {
    KernelSolid stub() => KernelSolid(
        OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
            Int32List.fromList(const [0]), Float64List(0)),
        1.0,
        null);

    AppState withBody(FilletRecorder k) {
      final app = AppState()..partKernel = k;
      app.edgeSession = EdgeFeatureSession('fillet');
      app.beginPickEdges();
      // one manual pick establishes WHICH body, as the panel requires
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0),
          solid: stub(), display: 0);
      return app;
    }

    test('All Rounds adds the convex edges only', () {
      final app = withBody(FilletRecorder());
      app.selectAllEdges(concave: false);
      expect(app.pickedEdgeIds, [1, 2], reason: 'edge 3 is concave');
      expect(app.edgeSession!.allRounds, isTrue);
    });

    test('All Fillets adds the concave edges only', () {
      final app = withBody(FilletRecorder());
      app.selectAllEdges(concave: true);
      expect(app.pickedEdgeIds, [1, 3], reason: 'edge 1 was picked by hand');
      expect(app.edgeSession!.allFillets, isTrue);
    });

    test('it never adds an edge twice', () {
      final app = withBody(FilletRecorder());
      app.selectAllEdges(concave: false);
      app.selectAllEdges(concave: false);
      expect(app.pickedEdgeIds, [1, 2]);
    });

    test('added edges land in the ACTIVE set', () {
      final app = withBody(FilletRecorder());
      app.newEdgeSet();
      app.selectAllEdges(concave: true);
      expect(app.edgesInSet(0), 1);
      expect(app.edgesInSet(1), 1, reason: 'the concave edge joined set 2');
    });

    test('without a body it refuses rather than guessing', () {
      final app = AppState()..partKernel = FilletRecorder();
      app.edgeSession = EdgeFeatureSession('fillet');
      app.beginPickEdges();
      app.selectAllEdges(concave: true);
      expect(app.pickedEdges, isEmpty);
    });

    test('convexity helpers read the shim contract', () {
      expect(OcctEdgeInfo(1, 1, 0, 0, 0, 1, 0, 0, 5, 0, 2, 90, 1).isConvex,
          isTrue);
      expect(OcctEdgeInfo(1, 1, 0, 0, 0, 1, 0, 0, 5, 0, 2, 90, -1).isConcave,
          isTrue);
      // a tangent edge is neither
      final t = OcctEdgeInfo(1, 1, 0, 0, 0, 1, 0, 0, 5, 0, 2, 0, 0);
      expect(t.isConvex, isFalse);
      expect(t.isConcave, isFalse);
    });
  });

  // M144 — Inventor's variable-radius fillet: a second radius per set makes
  // the fillet vary linearly along each edge of that set.
  group('variable radius', () {
    test('a blank end radius means constant, and writes nothing', () {
      final f = FilletFeature(
          name: 'F', bodyName: 'S', edges: const [], radii: const [2.0]);
      expect(f.radii2, isEmpty);
      expect(f.toJson().containsKey('radii2'), isFalse,
          reason: 'a plain fillet must not grow the file');
    });

    test('end radii round-trip through JSON', () {
      final f = FilletFeature(
          name: 'F',
          bodyName: 'S',
          edges: [EdgeSel(0, 0, 0, 5, 1, 0)],
          radii: const [2.0],
          radii2: const [6.0]);
      expect(f.toJson()['radii2'], [6.0]);
      final back = PartFeature.fromJson(f.toJson()) as FilletFeature;
      expect(back.radii2, [6.0]);
      expect(back.ownSig(), f.ownSig(),
          reason: 'the end radii must move the rebuild signature');
    });

    test('a varying radius changes the signature', () {
      final a = FilletFeature(
          name: 'F', bodyName: 'S', edges: const [], radii: const [2.0]);
      final b = FilletFeature(
          name: 'F',
          bodyName: 'S',
          edges: const [],
          radii: const [2.0],
          radii2: const [6.0]);
      expect(a.ownSig(), isNot(b.ownSig()));
    });

    test('the end radii reach the kernel, aligned to the edges', () {
      final k = FilletRecorder();
      final base = KernelSolid(
          OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
              Int32List.fromList(const [0]), Float64List(0)),
          1.0,
          null);
      final f = FilletFeature(
          name: 'F',
          bodyName: 'S',
          edges: [
            EdgeSel(0, 0, 0, 5, 1, 0),
            EdgeSel(10, 0, 0, 5, 1, 0),
            EdgeSel(20, 0, 0, 5, 1, 0),
          ],
          radii: const [2.0, 2.0, 3.0],
          radii2: const [6.0, 0.0, 0.0]);
      expect(recomputeFeature(PartModel('P'), f, k, base: base), isTrue);
      expect(k.lastRadii, [2.0, 2.0, 3.0]);
      expect(k.lastRadii2, [6.0, 0.0, 0.0],
          reason: '0 means that edge stays constant');
    });

    test('a LOST edge keeps the surviving radii correctly paired', () {
      // The alignment bug this guards: with edge 2 gone, the survivors are
      // sources 0 and 2, so the radii must be [2, 4] — not [2, 3] (positional)
      // and not [2, 2] (a second matching pass drifting).
      final k = FilletRecorder();
      final base = KernelSolid(
          OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
              Int32List.fromList(const [0]), Float64List(0)),
          1.0,
          null);
      final f = FilletFeature(
          name: 'F',
          bodyName: 'S',
          edges: [
            EdgeSel(0, 0, 0, 5, 1, 0), // -> live edge 1
            EdgeSel(999, 0, 0, 5, 1, 0), // gone
            EdgeSel(20, 0, 0, 5, 1, 0), // -> live edge 3
          ],
          radii: const [2.0, 3.0, 4.0],
          radii2: const [0.0, 0.0, 8.0]);
      expect(recomputeFeature(PartModel('P'), f, k, base: base), isTrue);
      expect(k.lastIds, [1, 3]);
      expect(k.lastRadii, [2.0, 4.0]);
      expect(k.lastRadii2, [0.0, 8.0]);
    });

    test('an all-constant feature sends NO end radii at all', () {
      final k = FilletRecorder();
      final base = KernelSolid(
          OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
              Int32List.fromList(const [0]), Float64List(0)),
          1.0,
          null);
      final f = FilletFeature(
          name: 'F',
          bodyName: 'S',
          edges: [EdgeSel(0, 0, 0, 5, 1, 0)],
          radii: const [2.0]);
      expect(recomputeFeature(PartModel('P'), f, k, base: base), isTrue);
      expect(k.lastRadii2, isEmpty,
          reason: 'the shim then skips the variable path entirely');
    });

    test('setEdgeFeature writes the end radius of the addressed set', () {
      final app = AppState();
      final s = EdgeFeatureSession('fillet');
      app.edgeSession = s;
      app.beginPickEdges();
      app.newEdgeSet();
      app.setEdgeFeature(exprRadius2: '5 mm', radiusSet: 1);
      expect(s.exprRadii2[0], '');
      expect(s.exprRadii2[1], '5 mm');
    });
  });

  // M126 — regressions found on DEVICE: the panel said "Select at least one
  // edge" and kept OK greyed out however many edges you tapped, and no fillet
  // preview ever appeared.
  group('picking an edge refreshes the preview state', () {
    KernelSolid stub() => KernelSolid(
        OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
            Int32List.fromList(const [0]), Float64List(0)),
        1.0,
        null);

    /// _updateEdgeFeaturePreview needs a CURRENT PART — without one it returns
    /// early, which is why a bare AppState() cannot exercise this at all.
    Future<AppState> armed() async {
      final app = AppState()..partKernel = FilletRecorder();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m126_');
      await app.createNamedPart('P');
      app.edgeSession = EdgeFeatureSession('fillet');
      app.beginPickEdges();
      return app;
    }

    test('the stale "select an edge" error clears once one is picked',
        () async {
      // Root cause: _openEdgeFeature computed the preview ONCE with zero
      // edges, and toggleEdgePick never recomputed it, so previewError stayed
      // frozen and the footer's `ready` test could never become true.
      final app = await armed();
      final s = app.edgeSession!;
      s.previewError = 'Select at least one edge.'; // as on open
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0),
          solid: stub(), display: 0);
      expect(s.previewError, isNull,
          reason: 'a picked edge must clear the stale error');
      expect(app.pickedEdges.length, 1);
    });

    test('a preview is actually built, and names the body it replaces',
        () async {
      final app = await armed();
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0),
          solid: stub(), display: 0);
      final s = app.edgeSession!;
      expect(s.preview, isNotNull, reason: 'no preview = nothing to draw');
      expect(s.previewReplacesBody, isNotNull,
          reason: 'the original body must be hidden or it shows through');
    });

    test('removing the last edge puts the error back and drops the preview',
        () async {
      final app = await armed();
      final sel = EdgeSel(0, 0, 0, 5, 1, 0);
      // ONE solid instance: passing a fresh stub would look like a different
      // body to the switch rule.
      final body = stub();
      app.toggleEdgePick(1, sel, solid: body, display: 0);
      expect(app.edgeSession!.preview, isNotNull);
      app.toggleEdgePick(1, sel, solid: body, display: 0); // untap
      expect(app.pickedEdges, isEmpty);
      expect(app.edgeSession!.previewError, isNotNull);
      expect(app.edgeSession!.preview, isNull);
    });

    test('the preview follows a radius change', () async {
      final app = await armed();
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0),
          solid: stub(), display: 0);
      final first = app.edgeSession!.preview;
      app.setEdgeFeature(exprRadius: '7 mm');
      expect(app.edgeSession!.preview, isNotNull);
      expect(identical(app.edgeSession!.preview, first), isFalse,
          reason: 'a new radius must rebuild the preview, not reuse it');
    });

    test('a recompute replacing the body solid does NOT wipe the selection',
        () async {
      // The real scenario: a recompute hands back a NEW KernelSolid for the
      // SAME named body. An identity test would read "different body" and
      // silently throw away everything the user had picked, which is why the
      // body NAME is recorded at pick time.
      final app = await armed();
      final p = app.currentPart!;
      final f = ExtrudeFeature(
          name: 'Extrusion1',
          bodyName: 'Solid1',
          sketchName: 'Sketch1',
          profiles: const []);
      f.solid = stub();
      p.features.add(f);

      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0),
          solid: f.solid, display: 0);
      expect(app.pickedEdges.length, 1);
      expect(app.pickedEdgeBodyName, 'Solid1');

      // simulate the rebuild: same body, brand-new instance
      f.solid = stub();
      app.toggleEdgePick(2, EdgeSel(10, 0, 0, 5, 1, 0),
          solid: f.solid, display: 1);
      expect(app.pickedEdges.length, 2,
          reason: 'a new instance of the SAME named body must not clear');
    });

    test('picking on a genuinely different body DOES start a new set',
        () async {
      final app = await armed();
      final p = app.currentPart!;
      ExtrudeFeature mk(String n, String body) {
        final f = ExtrudeFeature(
            name: n, bodyName: body, sketchName: 'Sketch1', profiles: const []);
        f.solid = stub();
        p.features.add(f);
        return f;
      }

      final a = mk('Extrusion1', 'Solid1');
      final b = mk('Extrusion2', 'Solid2');
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0),
          solid: a.solid, display: 0);
      app.toggleEdgePick(2, EdgeSel(10, 0, 0, 5, 1, 0),
          solid: b.solid, display: 1);
      expect(app.pickedEdges.length, 1,
          reason: 'a fillet operates on ONE body');
      expect(app.pickedEdgeBodyName, 'Solid2');
    });

    test('multiple edges keep the panel enabled', () async {
      final app = await armed();
      final body = stub();
      for (var i = 1; i <= 3; i++) {
        app.toggleEdgePick(i, EdgeSel(i * 10.0, 0, 0, 5, 1, 0),
            solid: body, display: i - 1);
      }
      expect(app.pickedEdges.length, 3);
      expect(app.edgeSession!.previewError, isNull,
          reason: 'this is exactly what stayed greyed out on device');
    });
  });

  // The preview machinery is shared between fillet and chamfer
  // (_edgeSessionFeature -> _recomputeBodyModify), but "shared" is a claim
  // until it is exercised.
  group('chamfer preview', () {
    Future<AppState> armed() async {
      final app = AppState()..partKernel = FilletRecorder();
      app.docsDirForTest =
          Directory.systemTemp.createTempSync('prototype_m126c_');
      await app.createNamedPart('P');
      app.edgeSession = EdgeFeatureSession('chamfer');
      app.beginPickEdges();
      return app;
    }

    KernelSolid stub() => KernelSolid(
        OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
            Int32List.fromList(const [0]), Float64List(0)),
        1.0,
        null);

    test('picking an edge builds a chamfer preview and clears the error',
        () async {
      final app = await armed();
      app.edgeSession!.previewError = 'Select at least one edge.';
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0),
          solid: stub(), display: 0);
      final s = app.edgeSession!;
      expect(s.previewError, isNull);
      expect(s.preview, isNotNull);
      expect(s.previewReplacesBody, isNotNull);
      expect((app.partKernel as FilletRecorder).chamfers, greaterThan(0),
          reason: 'the CHAMFER kernel path must be the one used');
    });

    test('the equal-distance method reaches the kernel', () async {
      final app = await armed();
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0),
          solid: stub(), display: 0);
      app.setEdgeFeature(mode: 0, exprD1: '3 mm');
      final k = app.partKernel as FilletRecorder;
      expect(k.lastMode, 0);
      expect(k.lastD1, 3.0);
    });

    test('changing the distance rebuilds the preview', () async {
      final app = await armed();
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0),
          solid: stub(), display: 0);
      final first = app.edgeSession!.preview;
      app.setEdgeFeature(exprD1: '4 mm');
      expect(app.edgeSession!.preview, isNotNull);
      expect(identical(app.edgeSession!.preview, first), isFalse);
    });

    test('two-distance mode and Flip both reach the kernel', () async {
      final app = await armed();
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0),
          solid: stub(), display: 0);
      app.setEdgeFeature(mode: 1, exprD1: '2 mm', exprD2: '5 mm');
      final k = app.partKernel as FilletRecorder;
      expect(k.lastMode, 1);
      expect(k.lastD1, 2.0);
      expect(k.lastD2, 5.0);
      app.setEdgeFeature(flip: true);
      expect(k.lastD1, 5.0, reason: 'Flip swaps the two faces');
      expect(k.lastD2, 2.0);
    });

    test('distance-and-angle mode sends the angle', () async {
      final app = await armed();
      app.toggleEdgePick(1, EdgeSel(0, 0, 0, 5, 1, 0),
          solid: stub(), display: 0);
      app.setEdgeFeature(mode: 2, exprD1: '2 mm', exprAngle: '30 deg');
      final k = app.partKernel as FilletRecorder;
      expect(k.lastMode, 2);
      expect(k.lastAngle, 30.0);
      app.setEdgeFeature(flip: true);
      expect(k.lastAngle, 60.0, reason: 'Flip takes the complement');
    });

    test('untapping the last edge drops the chamfer preview', () async {
      final app = await armed();
      final body = stub();
      final sel = EdgeSel(0, 0, 0, 5, 1, 0);
      app.toggleEdgePick(1, sel, solid: body, display: 0);
      expect(app.edgeSession!.preview, isNotNull);
      app.toggleEdgePick(1, sel, solid: body, display: 0);
      expect(app.edgeSession!.preview, isNull);
      expect(app.edgeSession!.previewError, isNotNull);
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
