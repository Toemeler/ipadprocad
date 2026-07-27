// M64 — the gallery still comes from the SAME engine as the 3D viewport, from
// a fixed TOP-FRONT-RIGHT corner.
//
// What the host suite can honestly pin (no RealityKit here — the plugin's
// isSupported is false off-iOS, so RealityThumbnailer.render returns null and
// the CPU fallback is what actually runs in these tests):
//
//   * the camera handed to BOTH engines is the exact isometric corner, with a
//     direction whose three components are equal and positive — i.e. the
//     camera sits on +X (right), +Y (up/top), +Z (front) in this Y-up world.
//   * that camera is FIXED: two parts differing only in where the live camera
//     was left produce the same orientation; only pan/zoom adapt to the
//     silhouette.
//   * the framing leaves the intended margin (silhouette fills kThumbFill).
//   * the payload the RealityKit path would send carries the real meshes and
//     the same camera doubles — the wire format the Swift PartRenderer reads.
//   * the thumbnail scene is geometry-only: no planes/axes/cp/sketches/preview
//     leak onto a gallery card.
//   * RealityThumbnailer.render never throws off-iOS; it returns null so the
//     caller falls back.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/reality_payload.dart';
import 'package:reality_view/reality_view.dart';

/// A unit cube spanning 0..10 mm on every axis, as a mesh the payload can
/// carry and the fitter can measure.
KernelSolid _cube({double s = 10}) {
  final pos = <double>[];
  final nor = <double>[];
  final idx = <int>[];
  void quad(List<List<double>> p, List<double> n) {
    final base = pos.length ~/ 3;
    for (final v in p) {
      pos.addAll(v);
      nor.addAll(n);
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }

  quad([
    [0, 0, s],
    [s, 0, s],
    [s, s, s],
    [0, s, s]
  ], [
    0,
    0,
    1
  ]);
  quad([
    [0, s, 0],
    [s, s, 0],
    [s, s, s],
    [0, s, s]
  ], [
    0,
    1,
    0
  ]);
  quad([
    [s, 0, 0],
    [s, s, 0],
    [s, s, s],
    [s, 0, s]
  ], [
    1,
    0,
    0
  ]);
  final mesh = OcctMeshData(
    Float64List.fromList(pos),
    Float64List.fromList(nor),
    Int32List.fromList(idx),
    Int32List.fromList([0]),
    Float64List(0),
    triFaces: Int32List.fromList(List<int>.filled(idx.length ~/ 3, 0)),
  );
  return KernelSolid(mesh, s * s * s, null);
}

void main() {
  const size = Size(380, 240);

  group('fixed top-front-right corner', () {
    test('view direction is the exact isometric corner, all components +equal',
        () {
      final d = thumbCameraDir;
      // +X = right, +Y = up (world is Y-up: the XZ plane carries normal +Y),
      // +Z = front. The camera sits at dir*D, so a positive triple means it
      // looks at the model's top-front-right corner.
      expect(d.x, greaterThan(0));
      expect(d.y, greaterThan(0));
      expect(d.z, greaterThan(0));
      expect(d.x, closeTo(d.y, 1e-12));
      expect(d.y, closeTo(d.z, 1e-12));
      expect(d.x, closeTo(1 / math.sqrt(3), 1e-12));
      // The old literal 0.955 was a rounded stand-in; the named constant is
      // exact, so the three components agree to machine precision.
      expect(kThumbPol, closeTo(math.acos(1 / math.sqrt(3)), 1e-15));
      expect(kThumbAz, closeTo(math.pi / 4, 1e-15));
    });

    test('orientation is independent of the part and of any live camera', () {
      final a = fitThumbCamera([_cube(s: 10)], size);
      final b = fitThumbCamera([_cube(s: 250)], size);
      expect(a.az, b.az);
      expect(a.pol, b.pol);
      expect(a.roll, 0); // no roll in the canonical view
      expect(b.roll, 0);
      // Only the framing adapts.
      expect(b.halfH, greaterThan(a.halfH));
    });

    test('frames the silhouette with the intended margin', () {
      final solid = _cube(s: 10);
      final cam = fitThumbCamera([solid], size);
      final c3 = Cam3(cam, size);
      final pos = solid.mesh.positions;
      double minX = 1e30, maxX = -1e30, minY = 1e30, maxY = -1e30;
      for (var i = 0; i + 2 < pos.length; i += 3) {
        final p = c3.project(Vec3(pos[i], pos[i + 1], pos[i + 2]));
        minX = math.min(minX, p.dx);
        maxX = math.max(maxX, p.dx);
        minY = math.min(minY, p.dy);
        maxY = math.max(maxY, p.dy);
      }
      // Everything on screen…
      expect(minX, greaterThanOrEqualTo(-0.5));
      expect(maxX, lessThanOrEqualTo(size.width + 0.5));
      expect(minY, greaterThanOrEqualTo(-0.5));
      expect(maxY, lessThanOrEqualTo(size.height + 0.5));
      // …and the tight axis filling kThumbFill of the frame, centred.
      final fillY = (maxY - minY) / size.height;
      final fillX = (maxX - minX) / size.width;
      expect(math.max(fillX, fillY), closeTo(kThumbFill, 1e-6));
      expect((minX + maxX) / 2, closeTo(size.width / 2, 1e-6));
      expect((minY + maxY) / 2, closeTo(size.height / 2, 1e-6));
    });
  });

  group('RealityKit payload for the still', () {
    test('carries the real meshes, geometry-only', () {
      final solid = _cube();
      final scene = buildThumbScenePayload([('Extrusion1', solid)]);
      final solids = scene['solids'] as List;
      expect(solids, hasLength(1));
      final s0 = solids.first as Map<String, dynamic>;
      expect(s0['id'], 'Extrusion1');
      expect(s0['material'], kMatSteel);
      // Buffers travel by reference in the Float32 wire format (M74).
      expect(s0['positions'], isA<Float32List>());
      expect((s0['positions'] as Float32List).length,
          solid.mesh.positions.length);
      expect(s0['indices'], isA<Int32List>());
      // A card shows the MODEL, not the editing scaffolding.
      for (final k in ['planes', 'axes', 'cp', 'sketches', 'preview',
        'highlight', 'selSketch']) {
        expect(scene.containsKey(k), isFalse, reason: '$k must not be sent');
      }
    });

    test('camera payload is the same fixed corner the CPU path uses', () {
      final cam = fitThumbCamera([_cube()], size);
      final p = cameraPayload(cam, size);
      expect(p['az'], kThumbAz);
      expect(p['pol'], kThumbPol);
      expect(p['roll'], 0);
      expect(p['w'], size.width);
      expect(p['h'], size.height);
      expect(p['halfH'], cam.halfH);
      expect(p['ox'], cam.ox);
      expect(p['oy'], cam.oy);
    });
  });

  test('off-iOS the thumbnailer declines instead of throwing', () async {
    expect(RealityThumbnailer.isSupported, isFalse);
    final png = await RealityThumbnailer.render(
      scene: buildThumbScenePayload([('Extrusion1', _cube())]),
      camera: cameraPayload(fitThumbCamera([_cube()], size), size),
      width: 380,
      height: 240,
    );
    // null = "no picture" => AppState._writePartPreview keeps its CPU fallback.
    expect(png, isNull);
  });
}
