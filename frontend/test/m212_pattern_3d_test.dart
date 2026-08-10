// M212 — the PART patterns: Rectangular, Circular, Sketch Driven, Mirror.
//
// Three layers, and the split is deliberate:
//
//  * the PLACEMENT arithmetic (patternOccurrences and friends) is pure, so
//    every corner that has historically gone wrong in a pattern — the 360°
//    wrap putting two occurrences in one place, a midplane row that forgets
//    the original is already there, a "fitted" span divided by the wrong
//    number — is pinned down here rather than on the device.
//  * the FEATURE (JSON round trip, signature, what it depends on).
//  * the BUILD, against a recording kernel: which solids get placed, with
//    which boolean, and — just as important — which refusals are honest
//    instead of silent.
//
// What is NOT covered here, deliberately: the real OCCT mirror and placement.
// Those need the linked kernel, and they are gated by the shim smoke test
// ([13] rigid transform, [13b] mirror) and then by the device.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_pick.dart';

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

KernelSolid _stub([double volume = 1000]) => KernelSolid(
    OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
        Int32List.fromList(const [0]), Float64List(0)),
    volume,
    null);

/// A kernel that records what a pattern asks it to do. It cannot produce real
/// geometry (no OCCT on host), so every result is a stub solid — which is
/// exactly enough to assert the SEQUENCE of operations, and nothing more.
class PatternRecorder implements PartKernel {
  final placements = <List<double>>[];
  final mirrors = <(Vec3, Vec3)>[];
  final booleans = <String>[];
  bool canMirror = true;
  bool canPlace = true;
  int extrudes = 0;

  @override
  bool get available => true;
  @override
  String get info => 'pattern recorder';
  @override
  String get lastError => 'pattern recorder failure';

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    extrudes++;
    return _stub(height * 100);
  }

  @override
  KernelSolid? placeSolid(KernelSolid s, List<double> mat34) {
    if (!canPlace) return null;
    placements.add(List.of(mat34));
    return _stub(s.volume);
  }

  @override
  KernelSolid? mirrorSolid(KernelSolid s, Vec3 p, Vec3 n) {
    if (!canMirror) return null;
    mirrors.add((p, n));
    return _stub(s.volume);
  }

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) {
    booleans.add('join');
    return _stub(a.volume + b.volume);
  }

  @override
  KernelSolid? cutSolids(KernelSolid a, KernelSolid b) {
    booleans.add('cut');
    return _stub(a.volume - b.volume);
  }

  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) {
    booleans.add('intersect');
    return _stub(a.volume);
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

/// An AppState holding a part with one real sketch and one extrusion of it.
Future<AppState> appWithPart(PartKernel k) async {
  final app = AppState()..partKernel = k;
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m212_');
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  _rect(app.activeChild!, app.editingLayer!, 0, 0, 20, 10);
  app.finishPartSketch();
  final p = app.currentPart!;
  final sk = p.childSketches.single.model.name;
  final f = ExtrudeFeature(
      name: 'Extrusion1',
      bodyName: 'Solid1',
      sketchName: sk,
      profiles: [ProfileSel(10, 5, 200)])
    ..output = 'new'
    ..seq = p.nextSeq();
  p.features.add(f);
  recomputeAllFeatures(p, app.partKernel, force: true);
  return app;
}

PatternFeature _rectPattern({
  int count = 3,
  double distance = 10,
  PatternDistribution dist = PatternDistribution.spacing,
  bool midplane = false,
  bool flip = false,
}) =>
    PatternFeature(
      name: 'RectangularPattern1',
      bodyName: 'Solid1',
      mode: PatternKind.rectangular,
      sources: const ['Extrusion1'],
      dirA: AxisRef(0, 0, 0, 1, 0, 0, 'X Axis'),
      countA: count,
      distanceA: distance,
      distributionA: dist,
      midplaneA: midplane,
      flipA: flip,
    );

Vec3 _translationOf(List<double> m) => Vec3(m[3], m[7], m[11]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // -------------------------------------------------------------------------
  group('rectangular placement', () {
    test('spacing is the step BETWEEN occurrences, and the original is not '
        'one of them', () {
      final occ = patternOccurrences(_rectPattern(count: 3, distance: 10));
      expect(occ.length, 2, reason: '3 occurrences = the original + 2 copies');
      expect(_translationOf(occ[0].mat34!).x, closeTo(10, 1e-9));
      expect(_translationOf(occ[1].mat34!).x, closeTo(20, 1e-9));
      expect(occ.map((o) => o.index), [2, 3],
          reason: "Inventor numbers the original 1");
    });

    test('distance is the TOTAL span, divided by the gaps', () {
      final occ = patternOccurrences(_rectPattern(
          count: 3, distance: 30, dist: PatternDistribution.distance));
      expect(_translationOf(occ[0].mat34!).x, closeTo(15, 1e-9));
      expect(_translationOf(occ[1].mat34!).x, closeTo(30, 1e-9));
    });

    test('flip reverses the direction', () {
      final occ = patternOccurrences(_rectPattern(count: 2, flip: true));
      expect(_translationOf(occ.single.mat34!).x, closeTo(-10, 1e-9));
    });

    test('midplane centres the span and drops the occurrence that would land '
        'on the original', () {
      final occ =
          patternOccurrences(_rectPattern(count: 3, midplane: true));
      expect(occ.length, 2, reason: 'the middle one IS the original');
      expect(_translationOf(occ[0].mat34!).x, closeTo(-10, 1e-9));
      expect(_translationOf(occ[1].mat34!).x, closeTo(10, 1e-9));
    });

    test('a second direction makes a grid, indexed row by row', () {
      final f = _rectPattern(count: 3, distance: 10)
        ..dirB = AxisRef(0, 0, 0, 0, 1, 0, 'Y Axis')
        ..countB = 2
        ..distanceB = 5;
      final occ = patternOccurrences(f);
      expect(occ.length, 5, reason: '3 x 2 = 6 places, minus the original');
      final ds = [for (final o in occ) _translationOf(o.mat34!)];
      expect(ds.any((d) => (d.x - 20).abs() < 1e-9 && d.y.abs() < 1e-9), isTrue);
      expect(ds.any((d) => d.x.abs() < 1e-9 && (d.y - 5).abs() < 1e-9), isTrue);
      expect(ds.any((d) => (d.x - 20).abs() < 1e-9 && (d.y - 5).abs() < 1e-9),
          isTrue);
    });

    test('with no direction there are no occurrences at all', () {
      final f = _rectPattern()..dirA = null;
      expect(patternOccurrences(f), isEmpty);
    });

    test('a count of one is a pattern of nothing', () {
      expect(patternOccurrences(_rectPattern(count: 1)), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('circular placement', () {
    PatternFeature circ(
            {int count = 6,
            double angle = 360,
            PatternDistribution d = PatternDistribution.distance,
            PatternOrient o = PatternOrient.rotational,
            bool flip = false}) =>
        PatternFeature(
          name: 'CircularPattern1',
          bodyName: 'Solid1',
          mode: PatternKind.circular,
          sources: const ['Extrusion1'],
          axis: AxisRef(0, 0, 0, 0, 0, 1, 'Z Axis'),
          countC: count,
          angleC: angle,
          distributionC: d,
          orientation: o,
          flipC: flip,
        );

    test('a full turn divides by the COUNT, so no two occurrences coincide',
        () {
      final occ = patternOccurrences(circ());
      expect(occ.length, 5);
      // 60 deg steps: the second copy sits at 120 deg
      final m = occ[1].mat34!;
      expect(m[0], closeTo(-0.5, 1e-9), reason: 'cos 120');
      expect(m[4], closeTo(0.8660254, 1e-6), reason: 'sin 120');
    });

    test('a partial fitted angle divides by the gaps', () {
      final occ = patternOccurrences(circ(count: 3, angle: 90));
      final m = occ[0].mat34!;
      expect(m[0], closeTo(0.7071068, 1e-6), reason: '45 deg, not 30');
    });

    test('incremental treats the angle as the step', () {
      final occ = patternOccurrences(
          circ(count: 3, angle: 90, d: PatternDistribution.spacing));
      expect(occ[1].mat34![0], closeTo(-1, 1e-9), reason: '2 x 90 deg');
    });

    test('flip turns the other way', () {
      final a = patternOccurrences(circ(count: 4))[0].mat34!;
      final b = patternOccurrences(circ(count: 4, flip: true))[0].mat34!;
      expect(a[4], closeTo(-b[4], 1e-9), reason: 'sin changes sign');
    });

    test('fixed orientation carries the copy round WITHOUT turning it', () {
      final occ = patternOccurrences(
          circ(count: 4, o: PatternOrient.fixed),
          refPoint: const Vec3(10, 0, 0));
      final m = occ[0].mat34!;
      // rotation part is the identity...
      expect(m[0], closeTo(1, 1e-9));
      expect(m[1], closeTo(0, 1e-9));
      expect(m[4], closeTo(0, 1e-9));
      expect(m[5], closeTo(1, 1e-9));
      // ...and the translation takes the reference point where the rotation
      // would have put it: (10,0,0) turned 90 deg is (0,10,0).
      expect(_translationOf(m).x, closeTo(-10, 1e-9));
      expect(_translationOf(m).y, closeTo(10, 1e-9));
    });

    test('an axis off the origin turns about ITSELF, not about the origin',
        () {
      final f = circ(count: 4)
        ..axis = AxisRef(5, 5, 0, 0, 0, 1, 'Edge');
      final m = patternOccurrences(f)[0].mat34!;
      // the axis point must be a fixed point of the placement
      final p = Vec3(
        m[0] * 5 + m[1] * 5 + m[3],
        m[4] * 5 + m[5] * 5 + m[7],
        m[8] * 5 + m[9] * 5 + m[11],
      );
      expect(p.x, closeTo(5, 1e-9));
      expect(p.y, closeTo(5, 1e-9));
    });
  });

  // -------------------------------------------------------------------------
  group('sketch driven and mirror placement', () {
    test('one occurrence per point, measured from the reference point', () {
      final f = PatternFeature(
          name: 'SketchDrivenPattern1',
          bodyName: 'Solid1',
          mode: PatternKind.sketchDriven,
          sources: const ['Extrusion1'],
          pointSketch: 'Sketch1');
      final occ = patternOccurrences(f,
          refPoint: const Vec3(1, 1, 0),
          points: const [Vec3(1, 1, 0), Vec3(4, 1, 0), Vec3(1, 6, 0)]);
      expect(occ.length, 2,
          reason: 'the point the original already sits on gets no copy');
      expect(_translationOf(occ[0].mat34!).x, closeTo(3, 1e-9));
      expect(_translationOf(occ[1].mat34!).y, closeTo(5, 1e-9));
    });

    test('a picked base point is the FIRST point and receives no copy', () {
      final f = PatternFeature(
          name: 'SketchDrivenPattern1',
          bodyName: 'Solid1',
          mode: PatternKind.sketchDriven,
          sources: const ['Extrusion1'],
          pointSketch: 'Sketch1',
          basePicked: true);
      final occ = patternOccurrences(f,
          refPoint: Vec3.zero,
          points: const [Vec3(2, 0, 0), Vec3(7, 0, 0)]);
      expect(occ.length, 1);
      expect(_translationOf(occ.single.mat34!).x, closeTo(5, 1e-9),
          reason: 'measured from the base point, not from the origin');
    });

    test('a mirror is exactly one occurrence, and it is not a placement', () {
      final f = PatternFeature(
        name: 'Mirror1',
        bodyName: 'Solid1',
        mode: PatternKind.mirror,
        sources: const ['Extrusion1'],
        mirrorPlane: PlaneRef(0, 0, 0, 1, 0, 0, 'YZ Plane'),
      );
      final occ = patternOccurrences(f);
      expect(occ.single.mirror, isTrue);
      expect(occ.single.mat34, isNull,
          reason: 'a reflection has determinant -1 and is not a rigid motion');
    });

    test('no plane, no mirror', () {
      final f = PatternFeature(
          name: 'Mirror1', bodyName: 'Solid1', mode: PatternKind.mirror);
      expect(patternOccurrences(f), isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('placement frames (Adjust)', () {
    test('a placed frame moves its origin and turns its axes', () {
      final f = planeFrame('xy');
      final moved = placedFrame(f, translationMat34(const Vec3(0, 0, 7)));
      expect(moved.origin.z, closeTo(f.origin.z + 7, 1e-9));
      expect(moved.n.x, closeTo(f.n.x, 1e-9));
      expect(moved.n.y, closeTo(f.n.y, 1e-9));
      expect(moved.n.z, closeTo(f.n.z, 1e-9));
    });

    test('a mirrored frame stays RIGHT-handed', () {
      final f = planeFrame('xy');
      final m = mirroredFrame(f, const Vec3(5, 0, 0), const Vec3(1, 0, 0));
      final cross = m.u.cross(m.v);
      expect(cross.x, closeTo(m.n.x, 1e-9));
      expect(cross.y, closeTo(m.n.y, 1e-9));
      expect(cross.z, closeTo(m.n.z, 1e-9),
          reason: 'u x v = n, or no kernel will accept the placement');
    });

    test('a mirrored frame reflects its origin about the plane', () {
      final f = PlaneFrame('face', const Vec3(1, 0, 0), const Vec3(0, 1, 0),
          const Vec3(0, 0, 1), const Vec3(2, 0, 0));
      final m = mirroredFrame(f, const Vec3(5, 0, 0), const Vec3(1, 0, 0));
      expect(m.origin.x, closeTo(8, 1e-9));
    });
  });

  // -------------------------------------------------------------------------
  group('the feature', () {
    test('it modifies a body, like a fillet does', () {
      final f = _rectPattern();
      expect(f.modifiesBody, isTrue);
      expect(f.output, 'modify');
      expect(f.kind, 'pattern');
      expect(f.typeLabel, 'RectangularPattern');
    });

    test('only a sketch-driven pattern depends on a sketch', () {
      expect(_rectPattern().sketchNames, isEmpty);
      final f = PatternFeature(
          name: 'p',
          bodyName: 'Solid1',
          mode: PatternKind.sketchDriven,
          pointSketch: 'Sketch3');
      expect(f.sketchNames, ['Sketch3'],
          reason: 'moving a point there has to rebuild the pattern');
    });

    test('the signature changes with every input that changes the geometry',
        () {
      final a = _rectPattern();
      final b = _rectPattern(count: 4);
      expect(a.ownSig(), isNot(b.ownSig()));
      final c = _rectPattern()..suppressed.add(2);
      expect(a.ownSig(), isNot(c.ownSig()));
      final d = _rectPattern()..compute = PatternCompute.adjust;
      expect(a.ownSig(), isNot(d.ownSig()));
    });

    test('every mode survives a JSON round trip', () {
      for (final f in [
        _rectPattern(count: 4, midplane: true)
          ..dirB = AxisRef(1, 2, 3, 0, 1, 0, 'Edge')
          ..countB = 3
          ..compute = PatternCompute.adjust
          ..suppressed.addAll([2, 5]),
        PatternFeature(
            name: 'CircularPattern1',
            bodyName: 'Solid1',
            mode: PatternKind.circular,
            axis: AxisRef(0, 0, 0, 0, 0, 1, 'Z Axis'),
            countC: 8,
            angleC: 180,
            orientation: PatternOrient.fixed,
            distributionC: PatternDistribution.spacing),
        PatternFeature(
            name: 'SketchDrivenPattern1',
            bodyName: 'Solid1',
            mode: PatternKind.sketchDriven,
            pointSketch: 'Sketch2',
            basePicked: true,
            baseX: 3,
            baseY: -4),
        PatternFeature(
            name: 'Mirror1',
            bodyName: 'Solid1',
            mode: PatternKind.mirror,
            patternSolid: true,
            removeOriginal: true,
            mirrorPlane: PlaneRef(1, 0, 0, 0, 1, 0, 'XZ Plane')),
      ]) {
        final back = PartFeature.fromJson(f.toJson());
        expect(back, isA<PatternFeature>(), reason: 'kind dispatch');
        expect((back as PatternFeature).ownSig(), f.ownSig(),
            reason: '${f.name} did not survive the round trip');
        expect(back.name, f.name);
        expect(back.patternSolid, f.patternSolid);
        expect(back.sources, f.sources);
      }
    });

    test('the occurrence count is Inventor\'s, including the original', () {
      expect(_rectPattern(count: 3).occurrenceCount, 3);
      final grid = _rectPattern(count: 3)
        ..dirB = AxisRef(0, 0, 0, 0, 1, 0, 'Y Axis')
        ..countB = 2;
      expect(grid.occurrenceCount, 6);
      expect((_rectPattern(count: 3)..countB = 2).occurrenceCount, 3,
          reason: 'a second direction that was never picked is not a row');
      expect(
          PatternFeature(
                  name: 'm', bodyName: 'Solid1', mode: PatternKind.mirror)
              .occurrenceCount,
          2);
    });
  });

  // -------------------------------------------------------------------------
  group('building', () {
    test('with no body before it, the pattern fails honestly', () {
      final part = PartModel('P');
      final f = _rectPattern();
      expect(recomputeFeature(part, f, PatternRecorder(), base: null), isFalse);
      expect(f.computeError, contains('no solid before this feature'));
      expect(f.solid, isNull, reason: 'a sick feature holds no geometry');
    });

    test('a solid pattern places the body and joins every copy', () async {
      final k = PatternRecorder();
      final app = await appWithPart(k);
      final p = app.currentPart!;
      final f = _rectPattern(count: 3)
        ..patternSolid = true
        ..sources.clear();
      k.placements.clear();
      k.booleans.clear();
      final base = _stub();
      expect(recomputeFeature(p, f, k, base: base), isTrue);
      expect(k.placements.length, 2);
      expect(k.booleans, ['join', 'join']);
      expect(f.solid, isNotNull);
    });

    test('a feature pattern rebuilds the source and repeats ITS boolean',
        () async {
      final k = PatternRecorder();
      final app = await appWithPart(k);
      final p = app.currentPart!;
      p.features.first.output = 'cut'; // a hole, patterned
      final f = _rectPattern(count: 4);
      k.placements.clear();
      k.booleans.clear();
      k.extrudes = 0;
      expect(recomputeFeature(p, f, k, base: _stub()), isTrue);
      expect(k.extrudes, 1,
          reason: 'Identical builds the tool ONCE and copies it');
      expect(k.placements.length, 3);
      expect(k.booleans, ['cut', 'cut', 'cut'],
          reason: "an occurrence of a cut cuts");
    });

    test('a suppressed occurrence is not built', () async {
      final k = PatternRecorder();
      final app = await appWithPart(k);
      final f = _rectPattern(count: 4)..suppressed.add(3);
      k.placements.clear();
      expect(recomputeFeature(app.currentPart!, f, k, base: _stub()), isTrue);
      expect(k.placements.length, 2);
    });

    test('suppressing every occurrence leaves the body alone — and does NOT '
        'hand on the base solid itself', () async {
      final k = PatternRecorder();
      final app = await appWithPart(k);
      final f = _rectPattern(count: 3)..suppressed.addAll([2, 3]);
      final base = _stub();
      expect(recomputeFeature(app.currentPart!, f, k, base: base), isTrue);
      expect(f.solid, isNotNull);
      expect(identical(f.solid, base), isFalse,
          reason: 'two features sharing one solid is a double free');
    });

    test('a source that no longer exists is reported by NAME', () async {
      final k = PatternRecorder();
      final app = await appWithPart(k);
      final f = _rectPattern()..sources[0] = 'Extrusion9';
      expect(recomputeFeature(app.currentPart!, f, k, base: _stub()), isFalse);
      expect(f.computeError, contains('Extrusion9'));
    });

    test('a fillet cannot be patterned, and the message says what to do '
        'instead', () async {
      final k = PatternRecorder();
      final app = await appWithPart(k);
      final p = app.currentPart!;
      p.features.add(FilletFeature(
          name: 'Fillet1',
          bodyName: 'Solid1',
          edges: [EdgeSel(0, 0, 0, 5, 1, 0)],
          radii: const [2]));
      final f = _rectPattern()..sources[0] = 'Fillet1';
      expect(recomputeFeature(p, f, k, base: _stub()), isFalse);
      expect(f.computeError, contains('cannot be patterned'));
    });

    test('a source BELOW the pattern is refused — that would be a cycle',
        () async {
      final k = PatternRecorder();
      final app = await appWithPart(k);
      final p = app.currentPart!;
      final f = _rectPattern()..sources[0] = 'Extrusion2';
      p.features.add(f);
      p.features.add(ExtrudeFeature(
          name: 'Extrusion2',
          bodyName: 'Solid1',
          sketchName: p.childSketches.single.model.name,
          profiles: [ProfileSel(10, 5, 200)]));
      expect(recomputeFeature(p, f, k, base: _stub()), isFalse);
      expect(f.computeError, contains('Extrusion2'));
    });

    test('a mirror asks the kernel to REFLECT, about the picked plane',
        () async {
      final k = PatternRecorder();
      final app = await appWithPart(k);
      final f = PatternFeature(
        name: 'Mirror1',
        bodyName: 'Solid1',
        mode: PatternKind.mirror,
        sources: const ['Extrusion1'],
        mirrorPlane: PlaneRef(0, 0, 0, 1, 0, 0, 'YZ Plane'),
      );
      expect(recomputeFeature(app.currentPart!, f, k, base: _stub()), isTrue);
      expect(k.mirrors.length, 1);
      expect(k.mirrors.single.$2.x, closeTo(1, 1e-9));
      expect(k.placements, isEmpty,
          reason: 'a mirror is never smuggled through as a matrix');
    });

    test('a kernel that cannot mirror fails the feature instead of placing '
        'the original twice', () async {
      final k = PatternRecorder()..canMirror = false;
      final app = await appWithPart(k);
      final f = PatternFeature(
        name: 'Mirror1',
        bodyName: 'Solid1',
        mode: PatternKind.mirror,
        sources: const ['Extrusion1'],
        mirrorPlane: PlaneRef(0, 0, 0, 1, 0, 0, 'YZ Plane'),
      );
      expect(recomputeFeature(app.currentPart!, f, k, base: _stub()), isFalse);
      expect(f.computeError, isNotNull);
      expect(f.solid, isNull);
    });

    test('Remove Original keeps only the mirrored half', () async {
      final k = PatternRecorder();
      final app = await appWithPart(k);
      final f = PatternFeature(
        name: 'Mirror1',
        bodyName: 'Solid1',
        mode: PatternKind.mirror,
        patternSolid: true,
        removeOriginal: true,
        mirrorPlane: PlaneRef(0, 0, 0, 1, 0, 0, 'YZ Plane'),
      );
      k.booleans.clear();
      expect(recomputeFeature(app.currentPart!, f, k, base: _stub()), isTrue);
      expect(k.mirrors.length, 1);
      expect(k.booleans, isEmpty,
          reason: 'there is nothing to join the mirrored half onto');
    });

    test('Adjust falls back to the copy for a plain Distance extent — there '
        'is nothing to re-measure', () async {
      final k = PatternRecorder();
      final app = await appWithPart(k);
      final f = _rectPattern(count: 3)..compute = PatternCompute.adjust;
      k.placements.clear();
      k.extrudes = 0;
      expect(recomputeFeature(app.currentPart!, f, k, base: _stub()), isTrue);
      expect(k.placements.length, 2);
      expect(k.extrudes, 1, reason: 'the tool is still built exactly once');
    });

    test('a sketch-driven pattern needs points, and says so when there are '
        'none', () async {
      final k = PatternRecorder();
      final app = await appWithPart(k);
      final p = app.currentPart!;
      final f = PatternFeature(
        name: 'SketchDrivenPattern1',
        bodyName: 'Solid1',
        mode: PatternKind.sketchDriven,
        sources: const ['Extrusion1'],
        pointSketch: p.childSketches.single.model.name,
      );
      expect(recomputeFeature(p, f, k, base: _stub()), isFalse);
      expect(f.computeError, contains('point'));
    });
  });

  // -------------------------------------------------------------------------
  group('the panel', () {
    test('opening needs a feature to copy', () async {
      final app = AppState()..partKernel = PatternRecorder();
      app.docsDirForTest = Directory.systemTemp.createTempSync('m212_open_');
      await app.createNamedPart('P');
      app.openRectPattern();
      expect(app.patternSession, isNull,
          reason: 'an empty part has nothing to pattern');
    });

    test('the same command twice closes it; another one switches', () async {
      final app = await appWithPart(PatternRecorder());
      app.openRectPattern();
      expect(app.patternKind, PatternKind.rectangular);
      app.openRectPattern();
      expect(app.patternSession, isNull);
      app.openCircPattern();
      app.openMirror();
      expect(app.patternKind, PatternKind.mirror);
    });

    test('opening a pattern closes the extrude panel and vice versa',
        () async {
      final app = await appWithPart(PatternRecorder());
      app.openExtrude();
      expect(app.extrudeSession, isNotNull);
      app.openRectPattern();
      expect(app.extrudeSession, isNull);
      app.openExtrude();
      expect(app.patternSession, isNull);
    });

    test('the rail switches command and KEEPS the feature selection',
        () async {
      final app = await appWithPart(PatternRecorder());
      app.openRectPattern();
      // The panel opens with the Feature selector already armed, which is
      // where all four commands start.
      expect(app.patternSession!.active, PatternField.features);
      app.patternToggleFeature(app.currentPart!.features.first);
      app.switchPattern(PatternKind.circular);
      expect(app.patternKind, PatternKind.circular);
      expect(app.patternSession!.features, ['Extrusion1']);
    });

    test('picking a feature toggles it', () async {
      final app = await appWithPart(PatternRecorder());
      app.openRectPattern();
      final f = app.currentPart!.features.first;
      expect(app.patternToggleFeature(f), isTrue);
      expect(app.patternHasFeature('Extrusion1'), isTrue);
      app.patternToggleFeature(f);
      expect(app.patternHasFeature('Extrusion1'), isFalse);
    });

    test('a browser tap is NOT swallowed when the panel is not asking for '
        'features', () async {
      final app = await appWithPart(PatternRecorder());
      app.openRectPattern();
      app.patternPick(PatternField.dirA);
      expect(app.patternToggleFeature(app.currentPart!.features.first), isFalse,
          reason: 'the row must still open its own editor');
    });

    test('a picked axis is stored as geometry, with its label', () async {
      final app = await appWithPart(PatternRecorder());
      app.openRectPattern();
      app.patternPick(PatternField.dirA);
      app.patternAxisPicked(Vec3.zero, const Vec3(0, 1, 0), 'Y Axis');
      final s = app.patternSession!;
      expect(s.dirA!.dy, closeTo(1, 1e-9));
      expect(s.dirA!.label, 'Y Axis');
      expect(s.active, PatternField.none,
          reason: 'one pick, one field — the selector disarms itself');
    });

    test('OK refuses a pattern with no features and says why', () async {
      final app = await appWithPart(PatternRecorder());
      app.openRectPattern();
      expect(await app.applyPattern(), isFalse);
      expect(app.currentPart!.features.length, 1);
    });

    test('OK refuses a rectangular pattern with no direction', () async {
      final app = await appWithPart(PatternRecorder());
      app.openRectPattern();
      app.patternToggleFeature(app.currentPart!.features.first);
      expect(app.patternSession!.previewError, contains('Direction A'));
      expect(await app.applyPattern(), isFalse);
    });

    test('OK creates the feature, with what the panel showed', () async {
      final app = await appWithPart(PatternRecorder());
      app.openRectPattern();
      app.patternToggleFeature(app.currentPart!.features.first);
      app.patternPick(PatternField.dirA);
      app.patternAxisPicked(Vec3.zero, const Vec3(1, 0, 0), 'X Axis');
      app.patternSession!.exprCountA = '4';
      app.patternSession!.exprDistanceA = '12 mm';
      app.patternChanged();
      expect(await app.applyPattern(), isTrue);
      final f = app.currentPart!.features.last as PatternFeature;
      expect(f.name, 'RectangularPattern1');
      expect(f.countA, 4);
      expect(f.distanceA, closeTo(12, 1e-9));
      expect(f.sources, ['Extrusion1']);
      expect(app.patternSession, isNull, reason: 'the panel closes on OK');
    });

    test('a count field takes an expression but refuses a fraction',
        () async {
      final app = await appWithPart(PatternRecorder());
      app.openRectPattern();
      app.patternToggleFeature(app.currentPart!.features.first);
      app.patternPick(PatternField.dirA);
      app.patternAxisPicked(Vec3.zero, const Vec3(1, 0, 0), 'X Axis');
      app.patternSession!.exprCountA = '2 * 3';
      app.patternChanged();
      expect(app.patternSession!.previewError, isNull);
      app.patternSession!.exprCountA = '2.5';
      app.patternChanged();
      expect(app.patternSession!.previewError, contains('Number'));
    });

    test('editing an existing pattern seeds the panel from it', () async {
      final app = await appWithPart(PatternRecorder());
      final p = app.currentPart!;
      final f = _rectPattern(count: 5)
        ..exprCountA = '5'
        ..compute = PatternCompute.adjust;
      f.seq = p.nextSeq();
      p.features.add(f);
      app.editFeature(f);
      final s = app.patternSession!;
      expect(s.mode, PatternKind.rectangular);
      expect(s.editing, same(f));
      expect(s.exprCountA, '5');
      expect(s.compute, PatternCompute.adjust);
      expect(s.features, ['Extrusion1']);
    });

    test('a sketch row feeds the sketch-driven pattern, and only then',
        () async {
      final app = await appWithPart(PatternRecorder());
      final cs = app.currentPart!.childSketches.single;
      app.openSketchPattern();
      // ...not while the panel is asking for FEATURES
      expect(app.patternToggleSketch(cs), isFalse);
      app.patternPick(PatternField.pointSketch);
      // the sketch holds no POINTS, so it is refused rather than accepted
      expect(app.patternToggleSketch(cs), isTrue);
      expect(app.patternSession!.pointSketch, isEmpty);
    });

    test('the solid mode switch moves the pick to the body selector',
        () async {
      final app = await appWithPart(PatternRecorder());
      app.openRectPattern();
      app.patternSetSolidMode(true);
      expect(app.patternSession!.patternSolid, isTrue);
      expect(app.patternSession!.active, PatternField.solid);
      app.patternSetSolidMode(false);
      expect(app.patternSession!.active, PatternField.features);
    });

    test('Esc backs out of the PICK first, then closes the panel', () async {
      final app = await appWithPart(PatternRecorder());
      app.openRectPattern();
      app.patternPick(PatternField.dirA);
      app.escape3D();
      expect(app.patternSession, isNotNull);
      expect(app.patternSession!.active, PatternField.none);
      app.escape3D();
      expect(app.patternSession, isNull);
    });

    test('suppressing occurrence 1 is refused — the original is not the '
        "pattern's to remove", () async {
      final app = await appWithPart(PatternRecorder());
      final p = app.currentPart!;
      final f = _rectPattern(count: 3);
      p.features.add(f);
      app.patternSuppressOccurrence(f, 1, true);
      expect(f.suppressed, isEmpty);
      app.patternSuppressOccurrence(f, 2, true);
      expect(f.suppressed, {2});
      app.patternSuppressOccurrence(f, 2, false);
      expect(f.suppressed, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('the direction an edge stands for', () {
    OcctMeshData meshWithCurve(List<double> record) => OcctMeshData(
        Float64List(0),
        Float64List(0),
        Int32List(0),
        Int32List.fromList(const [0]),
        Float64List(0),
        edgeCurves: Float64List.fromList(record));

    test('a line gives its own direction', () {
      final m = meshWithCurve([
        1, 0, 0, 0, 0, 10, 0, //
        0, 0, 0, 0, 0, 0, 0, 0, 0
      ]);
      final ax = edgeAxis(m, 0);
      expect(ax, isNotNull);
      expect(ax!.$2.y, closeTo(1, 1e-9));
    });

    test('a circle gives its AXIS, not a chord', () {
      // centre (5,5,0), x dir +x, y dir +y  ->  axis +z
      final m = meshWithCurve([
        2, 5, 5, 0, 1, 0, 0, //
        0, 1, 0, 3, 0, 6.28, 0, 0, 0
      ]);
      final ax = edgeAxis(m, 0);
      expect(ax, isNotNull);
      expect(ax!.$1.x, closeTo(5, 1e-9));
      expect(ax.$2.z, closeTo(1, 1e-9));
    });

    test('a spline defines no single line, and says so', () {
      final m = meshWithCurve(List<double>.filled(16, 0));
      expect(edgeAxis(m, 0), isNull);
    });

    test('a mesh without curve records answers null rather than guessing', () {
      final m = OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList(const [0]), Float64List(0));
      expect(edgeAxis(m, 0), isNull);
    });
  });
}
