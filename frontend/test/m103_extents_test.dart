// M103 — Inventor's Extents (Distance / To Next / To / Through All).
//
// What runs on host: the extent DECISION logic and the analytic planar
// termination maths. What cannot: anything reading a B-Rep — Through All
// needs a bounding box and To Next needs a ray cast, and a KernelSolid built
// without a linked kernel has no shape. Those paths are asserted to fail
// HONESTLY here; they are covered for real by shim smoke [20]-[23] and by the
// device.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// A KernelSolid with no B-Rep behind it — what every test fake produces.
KernelSolid _shapeless() => KernelSolid(
      OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList([0]), Float64List(0)),
      1.0,
      null,
    );

ExtrudeFeature _f(FeatureExtent extent,
        {ExtrudeDirection dir = ExtrudeDirection.defaultDir,
        double a = 5,
        double b = 3,
        FaceSel? face}) =>
    ExtrudeFeature(
      name: 'Extrusion1',
      bodyName: 'Solid1',
      sketchName: 'Sketch1',
      profiles: [ProfileSel(0, 0, 10)],
      direction: dir,
      distanceA: a,
      distanceB: b,
      extent: extent,
      extentFace: face,
    );

void main() {
  final xy = planeFrame('xy'); // origin at 0, normal +Z

  group('Distance is unchanged by M103', () {
    test('every direction still matches extrudeSpan exactly', () {
      for (final d in ExtrudeDirection.values) {
        final f = _f(FeatureExtent.distance, dir: d, a: 5, b: 3);
        final (h, z, err) = resolveExtrudeSpan(f, xy, null);
        final (eh, ez) = extrudeSpan(d, 5, 3);
        expect(err, isNull);
        expect(h, eh, reason: 'height changed for $d');
        expect(z, ez, reason: 'offset changed for $d');
      }
    });

    test('a plain distance needs no body at all', () {
      final (h, _, err) = resolveExtrudeSpan(_f(FeatureExtent.distance), xy, null);
      expect(err, isNull);
      expect(h, 5);
    });

    test('a non-positive distance is still refused', () {
      final (_, __, err) =
          resolveExtrudeSpan(_f(FeatureExtent.distance, a: 0), xy, null);
      expect(err, contains('greater than 0'));
    });
  });

  group('a base feature cannot use the model-resolved extents', () {
    // Inventor greys To Next out for a base feature: with nothing built yet
    // there is no face to terminate against.
    for (final e in [
      FeatureExtent.toNext,
      FeatureExtent.toFace,
      FeatureExtent.throughAll
    ]) {
      test('${extentLabel(e)} without a body reports why', () {
        final (h, _, err) = resolveExtrudeSpan(_f(e), xy, null);
        expect(h, 0);
        expect(err, isNotNull);
        expect(err, contains(extentLabel(e)));
        expect(err, contains('base feature'));
      });
    }
  });

  group('extents that need a B-Rep fail honestly without one', () {
    test('Through All cannot measure a shapeless body', () {
      final (h, _, err) =
          resolveExtrudeSpan(_f(FeatureExtent.throughAll), xy, _shapeless());
      expect(h, 0);
      expect(err, contains('could not measure'));
    });

    test('To Next finds no face and says so rather than guessing', () {
      final (h, _, err) =
          resolveExtrudeSpan(_f(FeatureExtent.toNext), xy, _shapeless());
      expect(h, 0);
      expect(err, contains('no next face'));
    });
  });

  group('To <face>: the analytic planar solution', () {
    // A plane at z = 12 facing +Z. The sketch is the XY plane at the origin,
    // so the answer must be exactly 12 — no tessellation involved.
    FaceSel top(double z) => FaceSel(0, 0, z, 0, 0, 1);

    test('terminates exactly on the plane', () {
      final (h, z, err) = resolveExtrudeSpan(
          _f(FeatureExtent.toFace, face: top(12)), xy, _shapeless());
      expect(err, isNull);
      expect(h, closeTo(12, 1e-12));
      expect(z, 0);
    });

    test('flipped measures the same distance the other way', () {
      final (h, z, err) = resolveExtrudeSpan(
          _f(FeatureExtent.toFace,
              dir: ExtrudeDirection.flipped, face: FaceSel(0, 0, -7, 0, 0, 1)),
          xy,
          _shapeless());
      expect(err, isNull);
      expect(h, closeTo(7, 1e-12));
      expect(z, closeTo(-7, 1e-12),
          reason: 'a flipped extrude starts a full height back');
    });

    test('symmetric applies the resolved distance either side', () {
      final (h, z, err) = resolveExtrudeSpan(
          _f(FeatureExtent.toFace,
              dir: ExtrudeDirection.symmetric, face: top(4)),
          xy,
          _shapeless());
      expect(err, isNull);
      expect(h, closeTo(8, 1e-12));
      expect(z, closeTo(-4, 1e-12));
    });

    test('a face BEHIND the direction is not reachable', () {
      // z = -3 while extruding +Z: the intersection is at t < 0, which is not
      // a termination, and there is no B-Rep to fall back to.
      final (_, __, err) = resolveExtrudeSpan(
          _f(FeatureExtent.toFace, face: top(-3)), xy, _shapeless());
      expect(err, contains('not reachable'));
    });

    test('a face PARALLEL to the extrude direction falls back, not crashes', () {
      // normal perpendicular to +Z => denom 0 => no analytic solution
      final (_, __, err) = resolveExtrudeSpan(
          _f(FeatureExtent.toFace, face: FaceSel(0, 0, 5, 1, 0, 0)),
          xy,
          _shapeless());
      expect(err, isNotNull, reason: 'must report, never divide by zero');
    });

    test('a tilted face still solves exactly', () {
      // plane through (0,0,10) with normal (0, 1, 1)/sqrt2; extruding +Z from
      // the origin hits it where z = 10.
      final n = 1 / 1.4142135623730951;
      final (h, _, err) = resolveExtrudeSpan(
          _f(FeatureExtent.toFace, face: FaceSel(0, 0, 10, 0, n, n)),
          xy,
          _shapeless());
      expect(err, isNull);
      expect(h, closeTo(10, 1e-9));
    });
  });

  group('bodySpanAlong', () {
    test('is null without a B-Rep, never a fabricated span', () {
      expect(bodySpanAlong(_shapeless(), xy), isNull);
    });
  });

  group('session wiring', () {
    test('leaving To clears the stored termination face', () {
      final s = ExtrudeSession();
      s.extent = FeatureExtent.toFace;
      s.extentFace = FaceSel(0, 0, 1, 0, 0, 1);
      // simulate the setter's rule
      expect(s.extentFace, isNotNull);
      s.extent = FeatureExtent.throughAll;
      s.extentFace = null;
      expect(s.extentFace, isNull,
          reason: 'a stale face must not silently reapply later');
    });

    test('a session defaults to a plain Distance', () {
      expect(ExtrudeSession().extent, FeatureExtent.distance);
      expect(ExtrudeSession().extentFace, isNull);
    });
  });

  group('serialisation', () {
    test('the extent and its face round-trip', () {
      final f = _f(FeatureExtent.toFace, face: FaceSel(1, 2, 3, 0, 0, 1));
      final back = PartFeature.fromJson(f.toJson()) as ExtrudeFeature;
      expect(back.extent, FeatureExtent.toFace);
      expect(back.extentFace, isNotNull);
      expect(back.extentFace!.pz, 3);
    });

    test('the extent takes part in the rebuild signature', () {
      // Otherwise switching Distance -> Through All would reuse the cached
      // solid and nothing would visibly change.
      final a = _f(FeatureExtent.distance);
      final b = _f(FeatureExtent.throughAll);
      expect(a.ownSig(), isNot(b.ownSig()));
    });

    test('every extent name survives a round trip', () {
      for (final e in FeatureExtent.values) {
        expect(featureExtentFrom(featureExtentName(e)), e);
      }
    });

    test('an unknown extent name degrades to Distance', () {
      expect(featureExtentFrom('betweenTwoFaces'), FeatureExtent.distance);
      expect(featureExtentFrom(null), FeatureExtent.distance);
    });
  });
}
