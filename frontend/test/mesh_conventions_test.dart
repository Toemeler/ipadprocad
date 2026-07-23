// M60 — the MEASURED mesh conventions, pinned so a regression fails in CI
// instead of on the iPad.
//
// Every fact asserted here was established by a device round, not derived from
// the code. If one of these tests goes red, either the kernel's output changed
// or someone "fixed" the renderer against a convention that is not the real
// one — both are worth a build failure.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/ffi/occt_engine.dart' show OcctMeshData;
import 'package:ipadprocad/part_model.dart' show PartCamera, Vec3;
import 'package:ipadprocad/reality_scene.dart';

import 'synth_mesh.dart';

/// Parses `key=value` tokens out of the one-line self-report.
Map<String, String> fields(String report) {
  final out = <String, String>{};
  for (final tok in report.split(' ')) {
    final i = tok.indexOf('=');
    if (i > 0) out[tok.substring(0, i)] = tok.substring(i + 1);
  }
  return out;
}

void main() {
  group('mesh self-report', () {
    test('a proper OCCT-style solid: winding follows normals, outward, '
        'watertight, no inward faces', () {
      final m = synthCylinderMesh(10, 40, 0.2);
      final f = fields(meshSelfReport('cyl', m));

      // Device measurement: wind_agrees_normal = 1.00 throughout.
      expect(f['wind'], '1.00');
      // Simple convex body: normals point away from the centroid.
      expect(f['out'], '1.00');
      // The kernel builds closed shells; a non-zero count means the defect is
      // in the geometry, not in the renderer.
      expect(f['edges'], '0(0=watertight)');
      expect(f['inward'], 'none');
      expect(int.parse(f['faces']!), 3); // barrel + two caps
    });

    test('a single inverted face is NAMED, not just averaged away', () {
      final src = synthCylinderMesh(10, 40, 0.2);
      final nor = Float64List.fromList(src.normals);
      // Flip the normals of every vertex used by the top cap only.
      // Per VERTEX, not per triangle reference: the cap's centre vertex is
      // shared by all n triangles and each ring vertex by two, so flipping
      // inside the triangle loop would flip them an even number of times and
      // change nothing at all. (This test failed on exactly that first.)
      final nTri = src.indices.length ~/ 3;
      final seen = <int>{};
      for (var t = 0; t < nTri; t++) {
        if (src.triFaces[t] != synthTopFace) continue;
        for (var k = 0; k < 3; k++) {
          final v = src.indices[t * 3 + k];
          if (!seen.add(v)) continue;
          for (var c = 0; c < 3; c++) {
            nor[v * 3 + c] = -nor[v * 3 + c];
          }
        }
      }
      final m = OcctMeshData(
          src.positions, nor, src.indices, src.edgeStarts, src.edgePoints,
          triFaces: src.triFaces,
          faceInfos: src.faceInfos,
          edgeCurves: src.edgeCurves);
      final f = fields(meshSelfReport('cyl', m));

      // The global ratio only sags a little — which is exactly why the
      // per-face list exists (device: normal_outward fell to 0.82 / 0.63 on
      // joined bodies without saying WHICH faces were at fault).
      expect(double.parse(f['out']!), lessThan(1.0));
      expect(f['inward'], contains('f$synthTopFace'));
      // Geometry untouched -> still watertight.
      expect(f['edges'], '0(0=watertight)');
    });

    test('legacy meshes without v4 metadata report inward=n/a, not a crash',
        () {
      final m = synthCylinderMesh(10, 40, 0.2, v4: false);
      final f = fields(meshSelfReport('legacy', m));
      expect(f['inward'], 'n/a');
      expect(f['wind'], '1.00');
    });

    test('an open shell is reported as such', () {
      final src = synthCylinderMesh(10, 40, 0.2);
      // Drop the last triangle -> its three edges lose their partner.
      final idx = Int32List.fromList(
          src.indices.sublist(0, src.indices.length - 3));
      final m = OcctMeshData(
          src.positions, src.normals, idx, src.edgeStarts, src.edgePoints,
          triFaces: Int32List.fromList(
              src.triFaces.sublist(0, src.triFaces.length - 1)),
          faceInfos: src.faceInfos,
          edgeCurves: src.edgeCurves);
      expect(fields(meshSelfReport('open', m))['edges'], isNot('0(0=watertight)'));
    });

    test('empty mesh does not throw', () {
      final m = OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList([0]), Float64List(0));
      expect(meshSelfReport('empty', m), contains('EMPTY'));
    });
  });

  group('camera convention (measured on device — do not re-derive)', () {
    // Cam3.dir points FROM the origin TOWARDS the camera; a visible face
    // satisfies n.dir > 0. facePicked relies on exactly this to choose which
    // SIDE of a picked face to look from.
    test('a face is faced from the side the camera is already on', () {
      // Camera above (pol ~ 0 -> dir ~ (0,1,0)), top face normal +Y.
      final cam = PartCamera(az: 0.3, pol: 0.4, halfH: 27, ox: 0, oy: 0);
      expect(cam.dir.y, greaterThan(0), reason: 'dir points to the camera');

      final topN = const Vec3(0, 1, 0);
      final chosen = topN.dot(cam.dir) >= 0 ? topN : topN * -1;
      cam.orientToDir(chosen);
      // Camera must end up ABOVE the face: pol ~ 0, i.e. the TOP view.
      // pol ~ pi would be the Bottom view — the reported symptom.
      expect(cam.pol, lessThan(0.1),
          reason: 'clicking the top face must give the TOP view');
    });

    test('the same face picked from below gives the bottom view', () {
      final cam = PartCamera(az: 0.3, pol: 3.0, halfH: 27, ox: 0, oy: 0);
      final topN = const Vec3(0, 1, 0);
      final chosen = topN.dot(cam.dir) >= 0 ? topN : topN * -1;
      cam.orientToDir(chosen);
      expect(cam.pol, greaterThan(3.0));
    });
  });
}
