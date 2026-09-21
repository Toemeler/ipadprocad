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

import 'support/shape_fixtures.dart';

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
