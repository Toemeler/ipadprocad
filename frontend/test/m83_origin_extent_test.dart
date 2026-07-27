// M83 — origin planes/axes FRAME the part instead of being a fixed 20 mm
// square.
//
// What is pinned here:
//   * an empty part is unchanged (the planes are all there is to pick, so the
//     old fixed size stays the default).
//   * a plane's width/height ARE the part's extent along that plane's own u/v
//     axes, plus padding — asymmetric, so a part sketched from the origin
//     outwards does not get a plane twice its size.
//   * sketches count as content, since they exist before the first solid.
//   * the origin always stays inside, so a part modelled far off-origin does
//     not push its own origin planes away from the axes lying on them.
//   * the payload sent to RealityKit carries that same rectangle, and still
//     carries `ext` so an older native build degrades instead of breaking.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// A solid whose mesh is a single triangle at the given world corners — enough
/// for the bounds walk, which only reads positions.
KernelSolid _tri(List<double> pts) => KernelSolid(
      OcctMeshData(
        Float64List.fromList(pts),
        Float64List.fromList(List<double>.filled(pts.length, 0)),
        Int32List.fromList([0, 1, 2]),
        Int32List.fromList([0]),
        Float64List(0),
      ),
      1,
      null,
    );

PartModel _partWith(KernelSolid s) {
  final p = PartModel('P');
  p.features.add(ExtrudeFeature(
    name: 'Extrusion1',
    bodyName: 'Solid1',
    sketchName: 'Sketch1',
    profiles: const [],
  )..solid = s);
  return p;
}

void main() {
  group('empty part is unchanged', () {
    test('falls back to the old fixed square', () {
      final p = PartModel('P');
      expect(partContentBounds(p), isNull);
      for (final key in kPlaneKeys) {
        final (uMin, uMax, vMin, vMax) = originPlaneRect(p, key);
        expect(uMin, -kOriginExtentDefault);
        expect(uMax, kOriginExtentDefault);
        expect(vMin, -kOriginExtentDefault);
        expect(vMax, kOriginExtentDefault);
      }
    });
  });

  group('planes take the part width and height', () {
    test('xy plane spans x and y of the part, plus padding', () {
      // A part occupying x 0..60, y 0..40, z 0..5.
      final p = _partWith(_tri([0, 0, 0, 60, 0, 5, 60, 40, 5]));
      final (uMin, uMax, vMin, vMax) = originPlaneRect(p, 'xy');
      // xy frame: u = +X, v = +Y.
      final padX = 60 * kOriginExtentPadFrac, padY = 40 * kOriginExtentPadFrac;
      expect(uMax - uMin, closeTo(60 + 2 * padX, 1e-9));
      expect(vMax - vMin, closeTo(40 + 2 * padY, 1e-9));
      // Asymmetric: the part starts AT the origin, so the plane does not
      // stretch an equal amount into -x.
      expect(uMin, closeTo(-padX, 1e-9));
      expect(uMax, closeTo(60 + padX, 1e-9));
    });

    test('each plane uses its OWN axes, not one shared size', () {
      final p = _partWith(_tri([0, 0, 0, 60, 0, 5, 60, 40, 5]));
      final xy = originPlaneRect(p, 'xy'); // u=+X, v=+Y  -> 60 x 40
      final xz = originPlaneRect(p, 'xz'); // u=+X, v=-Z  -> 60 x 5
      expect(xy.$2 - xy.$1, greaterThan(xz.$4 - xz.$3));
      expect(xz.$2 - xz.$1, closeTo(xy.$2 - xy.$1, 1e-9)); // both span x
    });

    test('padding has a floor so a flat part still gets a margin', () {
      // Zero thickness in z.
      final p = _partWith(_tri([0, 0, 0, 60, 0, 0, 60, 40, 0]));
      final (_, _, vMin, vMax) = originPlaneRect(p, 'xz'); // v = -Z
      expect(vMax - vMin, closeTo(2 * kOriginExtentPadMin, 1e-9));
    });

    test('the origin stays inside a part modelled far away', () {
      final p = _partWith(_tri([500, 500, 500, 560, 500, 505, 560, 540, 505]));
      final (uMin, uMax, vMin, vMax) = originPlaneRect(p, 'xy');
      expect(uMin, lessThanOrEqualTo(0));
      expect(uMax, greaterThanOrEqualTo(0));
      expect(vMin, lessThanOrEqualTo(0));
      expect(vMax, greaterThanOrEqualTo(0));
    });

    test('an invisible or consumed feature does not inflate the planes', () {
      final p = _partWith(_tri([0, 0, 0, 10, 0, 0, 10, 10, 0]));
      final small = originPlaneRect(p, 'xy');
      p.features.add(ExtrudeFeature(
        name: 'Extrusion2',
        bodyName: 'Solid2',
        sketchName: 'Sketch2',
        profiles: const [],
      )
        ..solid = _tri([0, 0, 0, 900, 0, 0, 900, 900, 0])
        ..visible = false);
      expect(originPlaneRect(p, 'xy'), small);
    });
  });

  group('memo', _memoTests);

  group('axes span the same box', () {
    test('an axis reaches the padded bounds, not a fixed 10', () {
      final p = _partWith(_tri([0, 0, 0, 60, 0, 5, 60, 40, 5]));
      final (lo, hi) = originAxisSpan(p, const Vec3(1, 0, 0));
      final (uMin, uMax, _, _) = originPlaneRect(p, 'xy');
      expect(lo, closeTo(uMin, 1e-9));
      expect(hi, closeTo(uMax, 1e-9));
    });
  });
}

// ---------------------------------------------------------------------------
// The memo (M83). partContentBounds is on the per-frame and per-pointer-move
// path and tessellates sketch curves, so it must not recompute on every call.
// ---------------------------------------------------------------------------
void _memoTests() {
  test('repeated calls reuse the cache, a real change invalidates it', () {
    final p = _partWith(_tri([0, 0, 0, 60, 0, 5, 60, 40, 5]));
    final first = partContentBounds(p);
    final sig = p.extentSig;
    expect(sig, isNotNull);
    // Same inputs -> same signature, cache reused (identical record value).
    expect(partContentBounds(p), first);
    expect(p.extentSig, sig);
    // A new solid must invalidate.
    p.features.first.solid = _tri([0, 0, 0, 600, 0, 5, 600, 400, 5]);
    final grown = partContentBounds(p);
    expect(p.extentSig, isNot(sig));
    expect(grown!.$2.x, greaterThan(first!.$2.x));
  });
}
