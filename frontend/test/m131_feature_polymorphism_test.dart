// M131 — PartFeature polymorphism, EdgeSel topological naming, and the
// revolve/fillet/chamfer parameter maths.
//
// Everything here is pure Dart and runs on host. What it deliberately does
// NOT cover: anything that needs the linked OCCT kernel (the actual revolve,
// the actual fillet). Those are gated by the shim smoke test [20]-[23] and,
// after that, by the device.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

OcctEdgeInfo _edge(int index,
        {int kind = 1,
        double x = 0,
        double y = 0,
        double z = 0,
        double length = 10,
        double radius = 0,
        int faces = 2}) =>
    OcctEdgeInfo(index, kind, x, y, z, 1, 0, 0, length, radius, faces);

/// Minimal kernel that can do nothing at all — enough to prove a feature
/// fails HONESTLY rather than crashing or inventing a solid.
class _DeadKernel implements PartKernel {
  @override
  bool get available => false;
  @override
  String get info => 'dead';
  @override
  String get lastError => 'no 3D kernel';
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

void main() {
  group('EdgeSel re-matching', () {
    test('finds the nearest live edge and re-anchors onto it', () {
      final sel = EdgeSel(10, 0, 0, 20, 1, 0);
      // the edge moved slightly and got a little shorter, as a neighbouring
      // fillet would do to it
      final live = [
        _edge(1, x: 10.4, length: 19.2),
        _edge(2, x: 50, length: 20),
      ];
      final m = sel.bestMatch(live);
      expect(m, isNotNull);
      expect(m!.index, 1);
      sel.reanchor(m);
      expect(sel.mx, closeTo(10.4, 1e-9),
          reason: 'the fingerprint must track the model, not drift from it');
      expect(sel.length, closeTo(19.2, 1e-9));
    });

    test('a type change disqualifies the edge', () {
      final sel = EdgeSel(0, 0, 0, 10, 1, 0); // was a line
      final live = [_edge(1, kind: 2, radius: 3)]; // now an arc, same place
      expect(sel.bestMatch(live), isNull,
          reason: 'a line that became an arc is not the same edge');
    });

    test('a free boundary is never filletable', () {
      final sel = EdgeSel(0, 0, 0, 10, 1, 0);
      expect(sel.bestMatch([_edge(1, faces: 1)]), isNull);
    });

    test('nothing close enough returns null rather than the least-bad', () {
      final sel = EdgeSel(0, 0, 0, 10, 1, 0);
      expect(sel.bestMatch([_edge(1, x: 500)]), isNull);
    });

    test('tolerance scales with the edge', () {
      // 2 mm off is fine for a 200 mm edge, not for a 1 mm one
      expect(EdgeSel(0, 0, 0, 200, 1, 0).bestMatch([_edge(1, x: 2, length: 200)]),
          isNotNull);
      expect(EdgeSel(0, 0, 0, 1, 1, 0).bestMatch([_edge(1, x: 2, length: 1)]),
          isNull);
    });
  });

  group('BodyModifyFeature.resolveEdges', () {
    test('one live edge can only serve one selection', () {
      // Two picks that both drifted toward the SAME survivor. Without the
      // taken-set this silently becomes a double-radius fillet on one edge.
      final f = FilletFeature(
        name: 'Fillet1',
        bodyName: 'Solid1',
        edges: [EdgeSel(0, 0, 0, 10, 1, 0), EdgeSel(0.1, 0, 0, 10, 1, 0)],
        radii: [1, 2],
      );
      final (ids, src, lost) = f.resolveEdges([_edge(7)]);
      expect(ids, [7]);
      expect(src, [0], reason: 'the SECOND pick is the one that was lost');
      expect(lost, 1);
    });

    test('surviving edges keep being filleted when one is lost', () {
      final f = FilletFeature(
        name: 'Fillet1',
        bodyName: 'Solid1',
        edges: [EdgeSel(0, 0, 0, 10, 1, 0), EdgeSel(999, 0, 0, 10, 1, 0)],
        radii: [1, 2],
      );
      final (ids, src, lost) = f.resolveEdges([_edge(3)]);
      expect(ids, [3], reason: 'Inventor keeps the fillet on what remains');
      expect(src, [0], reason: 'and radii index through this, not position');
      expect(lost, 1);
    });
  });

  group('RevolveFeature angles', () {
    RevolveFeature r(ExtrudeDirection d,
            {double a = 90, double b = 30, bool full = false}) =>
        RevolveFeature(
            name: 'Revolution1',
            bodyName: 'Solid1',
            sketchName: 'Sketch1',
            profiles: const [],
            direction: d,
            angleA: a,
            angleB: b,
            full: full);

    test('Full wins over the typed angle', () {
      expect(r(ExtrudeDirection.defaultDir, a: 12, full: true).sweepDeg, 360);
      expect(
          r(ExtrudeDirection.defaultDir, a: 12, full: true).startOffsetDeg, 0);
    });

    test('default starts at the profile', () {
      final f = r(ExtrudeDirection.defaultDir);
      expect(f.sweepDeg, 90);
      expect(f.startOffsetDeg, 0);
    });

    test('flipped sweeps the same amount the other way', () {
      final f = r(ExtrudeDirection.flipped);
      expect(f.sweepDeg, 90);
      expect(f.startOffsetDeg, -90);
    });

    test('symmetric splits Angle A in half either side', () {
      final f = r(ExtrudeDirection.symmetric);
      expect(f.sweepDeg, 90);
      expect(f.startOffsetDeg, -45);
    });

    test('asymmetric adds A and B and starts at -B', () {
      final f = r(ExtrudeDirection.asymmetric);
      expect(f.sweepDeg, 120);
      expect(f.startOffsetDeg, -30);
    });

    test('sweep is clamped to a full turn', () {
      expect(r(ExtrudeDirection.asymmetric, a: 300, b: 300).sweepDeg, 360);
    });
  });

  group('ChamferFeature.kernelParams', () {
    ChamferFeature c(int mode, {bool flip = false}) => ChamferFeature(
        name: 'Chamfer1',
        bodyName: 'Solid1',
        edges: const [],
        mode: mode,
        distance1: 2,
        distance2: 5,
        angleDeg: 30,
        flip: flip);

    test('equal distance ignores d2 and the angle', () {
      expect(c(0).kernelParams, (2.0, 0.0, 0.0));
    });

    test('two distances, and flip swaps which face gets which', () {
      expect(c(1).kernelParams, (2.0, 5.0, 0.0));
      expect(c(1, flip: true).kernelParams, (5.0, 2.0, 0.0));
    });

    test('distance and angle, flip takes the complement', () {
      expect(c(2).kernelParams, (2.0, 0.0, 30.0));
      expect(c(2, flip: true).kernelParams, (2.0, 0.0, 60.0),
          reason: 'the other face sees 90 - angle');
    });
  });

  group('serialisation', () {
    test('every kind round-trips through JSON', () {
      final feats = <PartFeature>[
        ExtrudeFeature(
            name: 'Extrusion1',
            bodyName: 'Solid1',
            sketchName: 'Sketch1',
            profiles: [ProfileSel(1, 2, 30)],
            distanceA: 7,
            extent: FeatureExtent.throughAll),
        RevolveFeature(
            name: 'Revolution1',
            bodyName: 'Solid1',
            sketchName: 'Sketch1',
            profiles: [ProfileSel(3, 4, 50)],
            axPx: 1,
            axDy: 1,
            angleA: 120,
            full: false),
        FilletFeature(
            name: 'Fillet1',
            bodyName: 'Solid1',
            edges: [EdgeSel(1, 2, 3, 10, 1, 0)],
            radii: [2.5]),
        ChamferFeature(
            name: 'Chamfer1',
            bodyName: 'Solid1',
            edges: [EdgeSel(4, 5, 6, 8, 2, 3)],
            mode: 2,
            angleDeg: 60),
      ];
      for (final f in feats) {
        f.seq = 9;
        final back = PartFeature.fromJson(f.toJson());
        expect(back, isNotNull, reason: '${f.kind} did not load');
        expect(back!.kind, f.kind);
        expect(back.name, f.name);
        expect(back.bodyName, f.bodyName);
        expect(back.seq, 9, reason: '${f.kind} lost its timeline position');
        expect(back.ownSig(), f.ownSig(),
            reason: '${f.kind} did not survive the round trip identically');
      }
    });

    test('an unknown kind is dropped, not guessed at', () {
      // 'loft' used to stand in for "unknown" here; it is a real feature as
      // of M131b, so this needs a kind that genuinely does not exist.
      expect(PartFeature.fromJson({'kind': 'emboss', 'name': 'Emboss1'}),
          isNull);
    });

    test('a pre-M103 extrude has no extent and loads as a plain distance', () {
      final j = {
        'kind': 'extrude',
        'name': 'Extrusion1',
        'body': 'Solid1',
        'sketch': 'Sketch1',
        'a': 5.0,
      };
      final f = PartFeature.fromJson(j) as ExtrudeFeature;
      expect(f.extent, FeatureExtent.distance);
      expect(f.extentFace, isNull);
    });

    test('a fillet with more edges than radii still pairs them up', () {
      final j = {
        'kind': 'fillet',
        'name': 'Fillet1',
        'body': 'Solid1',
        'edges': [
          EdgeSel(0, 0, 0, 1, 1, 0).toJson(),
          EdgeSel(1, 0, 0, 1, 1, 0).toJson(),
        ],
        'radii': [3.0],
      };
      final f = PartFeature.fromJson(j) as FilletFeature;
      expect(f.radii.length, f.edges.length,
          reason: 'downstream loops index the two lists together');
      expect(f.radii, [3.0, 3.0]);
    });
  });

  group('feature naming', () {
    test('each type is numbered separately, like Inventor', () {
      final p = PartModel('Part1');
      expect(p.nextFeatureName(), 'Extrusion1');
      expect(p.nextFeatureName('Fillet'), 'Fillet1');
      p.features.add(FilletFeature(
          name: 'Fillet1', bodyName: 'Solid1', edges: const [], radii: const []));
      expect(p.nextFeatureName('Fillet'), 'Fillet2');
      expect(p.nextFeatureName('Revolution'), 'Revolution1');
    });
  });

  group('body-modifying features', () {
    test('a fillet with nothing before it fails honestly', () {
      final p = PartModel('Part1');
      final f = FilletFeature(
          name: 'Fillet1',
          bodyName: 'Solid1',
          edges: [EdgeSel(0, 0, 0, 1, 1, 0)],
          radii: [1]);
      p.features.add(f);
      expect(recomputeFeature(p, f, _DeadKernel(), base: null), isFalse);
      expect(f.computeError, contains('nothing to modify'));
      expect(f.solid, isNull, reason: 'never invent a solid');
    });

    test('a fillet with no edges says so', () {
      final p = PartModel('Part1');
      final f = FilletFeature(
          name: 'Fillet1', bodyName: 'Solid1', edges: const [], radii: const []);
      final base = KernelSolid(
          OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
              Int32List.fromList([0]), Float64List(0)),
          1.0,
          null);
      expect(recomputeFeature(p, f, _DeadKernel(), base: base), isFalse);
      expect(f.computeError, contains('no edges selected'));
    });

    test('fillet and chamfer declare themselves body-modifying', () {
      expect(
          FilletFeature(
                  name: 'F', bodyName: 'S', edges: const [], radii: const [])
              .modifiesBody,
          isTrue);
      expect(
          ChamferFeature(name: 'C', bodyName: 'S', edges: const [])
              .modifiesBody,
          isTrue);
      expect(
          ExtrudeFeature(
                  name: 'E',
                  bodyName: 'S',
                  sketchName: 'Sketch1',
                  profiles: const [])
              .modifiesBody,
          isFalse);
    });

    test('a body-modifying feature consumes no sketch', () {
      final f =
          ChamferFeature(name: 'C', bodyName: 'S', edges: const []);
      expect(f.sketchName, '');
      final p = PartModel('Part1');
      p.features.add(f);
      expect(consumersOf(p, 'Sketch1'), isEmpty,
          reason: 'a chamfer must not appear to consume a sketch');
    });
  });

  group('PlaneFrame.mat34Rotated', () {
    List<double> m(double ang) =>
        planeFrame('xy').mat34Rotated(0, 0, 0, 1, ang);

    test('zero rotation is exactly the unrotated placement', () {
      expect(m(0), planeFrame('xy').mat34(0));
    });

    test('the rotation part stays orthonormal with det +1', () {
      // occt_transform REFUSES anything that is not a pure rotation, so a
      // composition slip here would fail every non-default revolve on device.
      final r = m(37.0);
      final cols = [
        [r[0], r[4], r[8]],
        [r[1], r[5], r[9]],
        [r[2], r[6], r[10]],
      ];
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 3; j++) {
          final d = cols[i][0] * cols[j][0] +
              cols[i][1] * cols[j][1] +
              cols[i][2] * cols[j][2];
          expect(d, closeTo(i == j ? 1.0 : 0.0, 1e-12));
        }
      }
      final det = cols[0][0] *
              (cols[1][1] * cols[2][2] - cols[1][2] * cols[2][1]) -
          cols[1][0] * (cols[0][1] * cols[2][2] - cols[0][2] * cols[2][1]) +
          cols[2][0] * (cols[0][1] * cols[1][2] - cols[0][2] * cols[1][1]);
      expect(det, closeTo(1.0, 1e-12));
    });

    test('a point on the axis does not move', () {
      final r = planeFrame('xy').mat34Rotated(3, 0, 0, 1, 51.0);
      // sketch (3, 5) lies on the axis x = 3
      final x = r[0] * 3 + r[1] * 5 + r[3];
      final y = r[4] * 3 + r[5] * 5 + r[7];
      final z = r[8] * 3 + r[9] * 5 + r[11];
      expect(x, closeTo(3, 1e-9));
      expect(y, closeTo(5, 1e-9));
      expect(z, closeTo(0, 1e-9));
    });
  });
}
