// M442 — the digest, tested against geometry whose answers are known by hand.
//
// These are arithmetic tests, deliberately. A box 60 x 40 x 10 has a surface
// area of 6800 mm^2 and six planar faces, and if the digest says anything else
// the digest is wrong — there is no modelling judgement involved and no kernel
// needed. That is the whole point of computing shape facts rather than asking
// a model to estimate them.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/shape_digest.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// A closed box as the shim would hand it over: 6 planar faces, 2 triangles
/// each, with the 15-double analytic record per face that `faceInfos` carries.
OcctMeshData boxMesh(double dx, double dy, double dz) {
  final pos = <double>[], nor = <double>[], idx = <int>[], tri = <int>[];
  final info = <double>[];
  // (origin, u, v, outward normal) per face.
  final faces = <(List<double>, List<double>, List<double>, List<double>)>[
    ([0, 0, 0], [dx, 0, 0], [0, dy, 0], [0, 0, -1]),
    ([0, 0, dz], [dx, 0, 0], [0, dy, 0], [0, 0, 1]),
    ([0, 0, 0], [dx, 0, 0], [0, 0, dz], [0, -1, 0]),
    ([0, dy, 0], [dx, 0, 0], [0, 0, dz], [0, 1, 0]),
    ([0, 0, 0], [0, dy, 0], [0, 0, dz], [-1, 0, 0]),
    ([dx, 0, 0], [0, dy, 0], [0, 0, dz], [1, 0, 0]),
  ];
  for (var f = 0; f < faces.length; f++) {
    var (o, u, v, n) = faces[f];
    // OCCT winds every triangle counter-clockwise seen from OUTSIDE, and the
    // digest's projected-area sum reads that winding. Half of the face frames
    // above span the wrong way round, so swap them rather than hand the code
    // a mesh no kernel would ever produce.
    final cross = [
      u[1] * v[2] - u[2] * v[1],
      u[2] * v[0] - u[0] * v[2],
      u[0] * v[1] - u[1] * v[0],
    ];
    if (cross[0] * n[0] + cross[1] * n[1] + cross[2] * n[2] < 0) {
      final t = u;
      u = v;
      v = t;
    }
    final base = pos.length ~/ 3;
    for (final c in [
      [0.0, 0.0],
      [1.0, 0.0],
      [1.0, 1.0],
      [0.0, 1.0]
    ]) {
      for (var k = 0; k < 3; k++) {
        pos.add(o[k] + u[k] * c[0] + v[k] * c[1]);
        nor.add(n[k]);
      }
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
    tri.addAll([f, f]);
    // type 0 (plane), a point on it, its normal, then the fields the digest
    // does not read — radius sits at [10].
    info.addAll([
      0,
      o[0] + (u[0] + v[0]) / 2,
      o[1] + (u[1] + v[1]) / 2,
      o[2] + (u[2] + v[2]) / 2,
      n[0], n[1], n[2],
      0, 0, 0, 0, 0, 0, 0, 0,
    ]);
  }
  return OcctMeshData(
    Float64List.fromList(pos),
    Float64List.fromList(nor),
    Int32List.fromList(idx),
    Int32List.fromList([0]),
    Float64List(0),
    triFaces: Int32List.fromList(tri),
    faceInfos: Float64List.fromList(info),
    faceIds: Int32List.fromList([for (var f = 0; f < faces.length; f++) f + 1]),
  );
}

/// The same box, with every face's surface type relabelled as a free-form
/// surface — which is what an imported organic body actually looks like.
OcctMeshData freeFormMesh(double dx, double dy, double dz) {
  final m = boxMesh(dx, dy, dz);
  final info = Float64List.fromList(m.faceInfos);
  for (var f = 0; f * 15 < info.length; f++) {
    info[f * 15] = 5; // kFaceOther
  }
  return OcctMeshData(m.positions, m.normals, m.indices, m.edgeStarts,
      m.edgePoints,
      triFaces: m.triFaces, faceInfos: info, faceIds: m.faceIds);
}

KernelSolid solidOf(OcctMeshData m, double volume) =>
    KernelSolid(m, volume, null);

void main() {
  group('a box, whose answers are arithmetic', () {
    final digest = computeShapeDigest(
        solidOf(boxMesh(60, 40, 10), 24000),
        body: 'Solid1');

    test('measures the bounding box and the volume it was given', () {
      expect(digest.size.x, closeTo(60, 1e-9));
      expect(digest.size.y, closeTo(40, 1e-9));
      expect(digest.size.z, closeTo(10, 1e-9));
      expect(digest.volume, 24000);
      // A solid box fills its own bounding box exactly.
      expect(digest.fill, closeTo(1.0, 1e-9));
    });

    test('sums the surface area from the triangles', () {
      // 2*(60*40) + 2*(60*10) + 2*(40*10)
      expect(digest.surfaceArea, closeTo(6800, 1e-6));
    });

    test('finds six planar faces and nothing else', () {
      expect(digest.faces, hasLength(6));
      expect(digest.typeCounts, {0: 6});
      expect(digest.analyticCoverage, closeTo(1.0, 1e-9));
      expect(digest.isFreeForm, isFalse);
    });

    test('names the two largest faces as notable, largest first', () {
      expect(digest.notable.first.area, closeTo(2400, 1e-6));
      expect(digest.notable.map((f) => f.area),
          [closeTo(2400, 1e-6), closeTo(2400, 1e-6), closeTo(600, 1e-6)]);
    });

    test('a box is symmetric about all three principal planes', () {
      expect(digest.mirrors, containsAll(['YZ', 'XZ', 'XY']));
    });

    test('reports the projected area of each face pair', () {
      // Looking down X you see 40 x 10; down Y, 60 x 10; down Z, 60 x 40.
      expect(digest.frontAreas[0], closeTo(400, 1e-6));
      expect(digest.frontAreas[1], closeTo(600, 1e-6));
      expect(digest.frontAreas[2], closeTo(2400, 1e-6));
    });

    test('claims no wall thickness without a B-Rep to cast a ray through', () {
      // The honest answer with no kernel is "not measured", never a number.
      expect(digest.minWall, isNull);
      expect(digest.exact, isFalse);
    });

    test('an analytic part needs no cross-sections', () {
      expect(digest.sections, isEmpty);
    });
  });

  group('the digest text', () {
    final text = computeShapeDigest(solidOf(boxMesh(60, 40, 10), 24000),
            body: 'Solid1')
        .toText();

    test('states the shape in a few lines, not a few hundred', () {
      expect(text.split('\n').length, lessThan(14));
      // The budget the plan sets is 400 tokens; 4 chars/token is the usual
      // rule of thumb, so this is the ceiling with room to spare.
      expect(text.length, lessThan(1600));
    });

    test('leads with what the thing is', () {
      expect(text, startsWith('SHAPE Solid1'));
      expect(text, contains('60.00 × 40.00 × 10.00 mm'));
      expect(text, contains('6 plane'));
      expect(text, contains('fill 100%'));
    });

    test('says what it did not measure rather than staying silent', () {
      expect(text, contains('mesh-only (no kernel linked)'));
      expect(text, contains('No mass, strength, clearance'));
    });

    test('is deterministic', () {
      final again = computeShapeDigest(solidOf(boxMesh(60, 40, 10), 24000),
              body: 'Solid1')
          .toText();
      expect(again, text);
    });
  });

  group('a free-form body knows it cannot describe itself', () {
    final digest = computeShapeDigest(
        solidOf(freeFormMesh(60, 40, 10), 24000),
        body: 'Solid1');

    test('reports low analytic coverage and says so in its own text', () {
      expect(digest.analyticCoverage, 0);
      expect(digest.isFreeForm, isTrue);
      expect(digest.toText(), contains('FREE-FORM'));
      expect(digest.toText(), contains('Ask for a section'));
    });

    test('falls back to cross-sections, which carry the form instead', () {
      expect(digest.sections, isNotEmpty);
      expect(digest.sectionAxis, 'X'); // 60 is the longest side
      // Every station through a prism is the same 40 x 10 rectangle.
      for (final p in digest.sections) {
        expect(p.width, closeTo(40, 1e-6));
        expect(p.height, closeTo(10, 1e-6));
        expect(p.area, closeTo(400, 1e-6));
        expect(p.loops, 1);
      }
    });

    test('the sections are stated as approximate, because they are', () {
      expect(digest.toText(), contains('mesh, ±0.1 mm'));
    });
  });

  group('sectioning is plain geometry', () {
    test('a plane through a box gives its rectangle', () {
      final m = boxMesh(20, 10, 4);
      final profiles =
          sectionProfiles(m, 0, const Vec3(0, 0, 0), const Vec3(20, 10, 4));
      expect(profiles, hasLength(kSectionStations));
      expect(profiles.first.width, closeTo(10, 1e-6));
      expect(profiles.first.height, closeTo(4, 1e-6));
    });

    test('front areas of a closed box are its face pairs', () {
      final areas = frontAreas(boxMesh(2, 3, 5));
      expect(areas[0], closeTo(15, 1e-9));
      expect(areas[1], closeTo(10, 1e-9));
      expect(areas[2], closeTo(6, 1e-9));
    });
  });

  group('an empty or degenerate body does not throw', () {
    test('a mesh with no triangles still produces a digest', () {
      final empty = OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList([0]), Float64List(0));
      final digest = computeShapeDigest(solidOf(empty, 0));
      expect(digest.faces, isEmpty);
      expect(digest.surfaceArea, 0);
      expect(digest.fill, 0);
      expect(digest.toText(), contains('SHAPE'));
    });
  });
}
