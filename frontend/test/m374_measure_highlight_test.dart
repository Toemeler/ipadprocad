// M374 — what a measurement LOOKS like it has selected.
//
// "I dont have a highlight what i selected or what i hover over."
//
// Two claims, and this file pins both:
//
//   * A FACE highlights as a face. Before this the halo could only trace a
//     [MeasureRef.samples] polyline, and a face has none, so it fell through
//     to a nine-point ring at the tap — which highlights the TAP, not the
//     face. The picker now hands over the face's own triangles and boundary
//     loops in [MeasureRef.shape].
//
//   * The shape is DRAWN AND NEVER MEASURED. That separation is the whole
//     safety argument for putting the tessellation on a ref whose readings
//     are analytic, so it is asserted rather than assumed: the same pick with
//     and without a shape must produce byte-identical readings.
//
// The prehighlight's rules are here too, on [MeasureSession.hover]: it is not
// a pick, it never survives becoming one, and it costs a repaint only when it
// actually changes.
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/measure.dart';
import 'package:prototype/measure_pick.dart';
import 'package:prototype/measure_paint.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart' show Cam3;

import 'm371_measure_pick_test.dart' show squareFaceMesh, topDownCam;

/// The identity placement's world map, for [faceShape].
Vec3 same(Vec3 v) => v;

/// A square of [side], two triangles, whose shared DIAGONAL is reached through
/// two different pairs of indices holding identical coordinates.
///
/// This is a cylinder's seam in miniature: index 0 and index 4 are the same
/// point, as are 2 and 5, so the diagonal is one segment geometrically and two
/// segments by index. A boundary count that keys on indices calls both of them
/// used-once and puts the diagonal in the outline.
OcctMeshData seamedSquare(double side) {
  final p = <double>[
    0, 0, 0, side, 0, 0, side, side, 0, 0, side, 0, //
    0, 0, 0, side, side, 0, // the duplicates
  ];
  final n = <double>[for (var i = 0; i < 6; i++) ...[0, 0, 1]];
  final idx = <int>[0, 1, 2, 4, 5, 3];
  return OcctMeshData(
    Float64List.fromList(p),
    Float64List.fromList(n),
    Int32List.fromList(idx),
    Int32List.fromList(const [0]),
    Float64List.fromList(const []),
    triFaces: Int32List.fromList(const [0, 0]),
    faceInfos: Float64List.fromList(
        <double>[0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, side, 0, side]),
  );
}

void main() {
  group('a face highlights as a face', () {
    test('the shape carries the face\'s own triangles', () {
      final s = faceShape(squareFaceMesh(10), 0, same);
      // Two triangles, corner-major: six points.
      expect(s.triangleCount, 2);
      expect(s.patch.length, 6);
    });

    test('and its boundary loop, closed and in order', () {
      final s = faceShape(squareFaceMesh(10), 0, same);
      expect(s.loops.length, 1);
      final loop = s.loops.single;
      // Four corners, walked round and back to the start.
      expect(loop.length, 5);
      expect((loop.first - loop.last).length, lessThan(1e-9));
      // Every step is an EDGE of the square, never the diagonal the
      // triangulation runs through its middle: the diagonal is used twice and
      // so is interior.
      for (var i = 1; i < loop.length; i++) {
        expect((loop[i] - loop[i - 1]).length, closeTo(10, 1e-9));
      }
    });

    test('the loop encloses the face\'s area', () {
      final s = faceShape(squareFaceMesh(10), 0, same);
      expect(planarLoopArea(s.loops.single, const Vec3(0, 0, 1)).abs(),
          closeTo(100, 1e-9));
    });

    test('the world map is applied to both halves', () {
      Vec3 shifted(Vec3 v) => v + const Vec3(100, 0, 0);
      final s = faceShape(squareFaceMesh(10), 0, shifted);
      for (final p in s.patch) {
        expect(p.x, greaterThanOrEqualTo(100 - 1e-9));
      }
      for (final p in s.loops.single) {
        expect(p.x, greaterThanOrEqualTo(100 - 1e-9));
      }
    });

    test('a face that is not in the mesh has no shape', () {
      expect(faceShape(squareFaceMesh(10), 7, same).isEmpty, isTrue);
    });

    test('past the triangle cap the wash is dropped and the loops are kept',
        () {
      // The cap exists for imported meshes, where one face can be an entire
      // scanned surface: the wash is the expensive half and the loops are
      // what says which face, so that is the half that survives.
      final s = faceShape(squareFaceMesh(10), 0, same, cap: 1);
      expect(s.patch, isEmpty);
      expect(s.loops, isNotEmpty);
    });

    test('a seam with DUPLICATED vertices is not drawn as a boundary', () {
      // The reason the boundary count is geometric rather than index-keyed.
      // OCCT triangulates a cylinder with the vertices along its seam
      // duplicated, so the seam appears as two index-distinct segments that
      // each look used-once — and an index-keyed walk draws a bright line
      // straight down the middle of every highlighted bore.
      //
      // [seamedSquare] is that failure in the smallest form that has it: one
      // square, two triangles, and the shared diagonal reached through two
      // different pairs of indices holding identical coordinates.
      final s = faceShape(seamedSquare(10), 0, same);
      expect(s.loops.length, 1);
      final loop = s.loops.single;
      expect(loop.length, 5, reason: 'four sides, closed');
      for (var i = 1; i < loop.length; i++) {
        expect((loop[i] - loop[i - 1]).length, closeTo(10, 1e-9),
            reason: 'a step of 14.14 is the diagonal, i.e. the seam');
      }
    });
  });

  group('the shape is drawn and never measured', () {
    // The pick with the real shape on it, and the same pick with the shape
    // stripped off. Every reading either produces must agree exactly.
    final m = squareFaceMesh(10);
    final cam = topDownCam(const Size(400, 400), halfH: 15);
    final withShape =
        measurePickMesh(m, cam, const Offset(240, 160), owner: 'b')!.ref;
    final without = withShape.withShape(null);

    test('the fixture really does carry a shape', () {
      expect(withShape.shape, isNotNull);
      expect(withShape.shape!.patch, isNotEmpty);
      expect(without.shape, isNull);
    });

    test('a single pick reads the same either way', () {
      final a = measure([withShape])!, b = measure([without])!;
      expect(a.values.length, b.values.length);
      for (var i = 0; i < a.values.length; i++) {
        expect(a.values[i].role, b.values[i].role);
        expect(a.values[i].value, b.values[i].value);
      }
    });

    test('a distance to it reads the same either way', () {
      final p = MeasureRef.point(const Vec3(3, 3, 25));
      final a = measure([withShape, p])!, b = measure([without, p])!;
      expect(a.primary.role, b.primary.role);
      expect(a.primary.value, b.primary.value);
    });

    test('an angle against it reads the same either way', () {
      final q = MeasureRef.plane(const Vec3(0, 0, 0), const Vec3(1, 0, 0),
          oriented: true);
      final a = measure([withShape, q])!, b = measure([without, q])!;
      expect(a.primary.role, b.primary.role);
      expect(a.primary.value, b.primary.value);
    });

    test('the shape does not change what counts as the same pick', () {
      expect(withShape.sameAs(without), isTrue);
    });
  });

  group('the ink actually lands on the canvas', () {
    // The claim under all of it, tested the only way that cannot be satisfied
    // by a field being set: RASTERISE the overlay and look at the pixels.
    // "the shape is attached" is not the bug report; "I dont have a highlight"
    // is, and only the image answers that.
    const size = Size(400, 400);
    final cam = topDownCam(size, halfH: 15);

    /// The overlay for [s], rendered, as its pixel bytes (RGBA, row-major).
    Future<ByteData> render(MeasureSession s) async {
      final rec = PictureRecorder();
      final canvas = Canvas(rec, Offset.zero & size);
      paintMeasureOverlay(canvas, s, cam.project, size);
      final img = await rec
          .endRecording()
          .toImage(size.width.round(), size.height.round());
      return (await img.toByteData())!;
    }

    /// How many pixels of [bytes] are not fully transparent.
    int inked(ByteData bytes) {
      var n = 0;
      for (var i = 3; i < bytes.lengthInBytes; i += 4) {
        if (bytes.getUint8(i) != 0) n++;
      }
      return n;
    }

    /// The alpha at (x, y).
    int alphaAt(ByteData bytes, int x, int y) =>
        bytes.getUint8(((y * size.width.round()) + x) * 4 + 3);

    MeasureRef facePick() =>
        measurePickMesh(squareFaceMesh(10), cam, const Offset(240, 160),
                owner: 'b')!
            .ref;

    test('an empty session draws nothing', () async {
      expect(inked(await render(MeasureSession())), 0);
    });

    test('a picked face inks the FACE, not a dot at the tap', () async {
      final s = MeasureSession()..add(facePick());
      final n = inked(await render(s));
      // The square is 10 mm on a 400 px / 30 mm camera: 133 px a side, so
      // ~17 700 px of face. A ring at the tap is under 400. Anything above a
      // few thousand can only be the face itself.
      expect(n, greaterThan(5000),
          reason: 'a nine-point ring at the tap would be a few hundred');
    });

    test('the ink is where the face is, and not where it is not', () async {
      final s = MeasureSession()..add(facePick());
      final b = await render(s);
      // The square spans world (0,0) to (10,10); the camera puts world (0,0)
      // at the centre of the canvas, so the face occupies the upper-right
      // quadrant and the lower-left is empty.
      expect(alphaAt(b, 240, 160), greaterThan(0), reason: 'inside the face');
      expect(alphaAt(b, 60, 340), 0, reason: 'well outside it');
    });

    test('a prehighlighted face inks it too, and more faintly', () async {
      final picked = MeasureSession()..add(facePick());
      final hovered = MeasureSession()..setHover(facePick());
      final a = await render(picked), b = await render(hovered);
      expect(inked(b), greaterThan(5000), reason: 'the hover is drawn at all');
      // Same face, same area, dimmer ink.
      expect(alphaAt(b, 240, 160), lessThan(alphaAt(a, 240, 160)));
      expect(alphaAt(b, 240, 160), greaterThan(0));
    });

    test('a hover on something already picked draws once, not twice',
        () async {
      final s = MeasureSession()..add(facePick());
      final before = alphaAt(await render(s), 240, 160);
      s.setHover(facePick()); // refused: it is already lit
      expect(alphaAt(await render(s), 240, 160), before);
    });

    test('the wash does not double where a surface folds over itself',
        () async {
      // A body projects all of itself onto itself. Drawn triangle by
      // translucent triangle the overlap comes out twice as dark, which reads
      // as shading that is not there; the layer is what makes it uniform.
      final tris = <Vec3>[
        // two coincident triangles, i.e. the worst possible overlap
        for (var k = 0; k < 2; k++) ...[
          const Vec3(-5, -5, 0),
          const Vec3(5, -5, 0),
          const Vec3(0, 5, 0),
        ],
      ];
      final one = MeasureSession()
        ..add(MeasureRef.solid(const Vec3(-5, -5, 0), const Vec3(5, 5, 0),
            component: false,
            mesh: MeasureMesh(tris.sublist(0, 3), const [],
                const Vec3(-5, -5, 0), const Vec3(5, 5, 0))));
      final two = MeasureSession()
        ..add(MeasureRef.solid(const Vec3(-5, -5, 0), const Vec3(5, 5, 0),
            component: false,
            mesh: MeasureMesh(
                tris, const [], const Vec3(-5, -5, 0), const Vec3(5, 5, 0))));
      final a = await render(one), b = await render(two);
      expect(alphaAt(b, 200, 200), alphaAt(a, 200, 200));
    });
  });

  group('the prehighlight', () {
    MeasureRef refA() => MeasureRef.point(const Vec3(0, 0, 0));
    MeasureRef refB() => MeasureRef.point(const Vec3(10, 0, 0));

    test('setting it the first time is a change', () {
      final s = MeasureSession();
      expect(s.setHover(refA()), isTrue);
      expect(s.hover, isNotNull);
    });

    test('setting the same thing again is not', () {
      final s = MeasureSession()..setHover(refA());
      expect(s.setHover(refA()), isFalse);
    });

    test('moving to something else is', () {
      final s = MeasureSession()..setHover(refA());
      expect(s.setHover(refB()), isTrue);
    });

    test('clearing it is a change once, then not', () {
      final s = MeasureSession()..setHover(refA());
      expect(s.setHover(null), isTrue);
      expect(s.setHover(null), isFalse);
    });

    test('something already PICKED never prehighlights', () {
      final s = MeasureSession()..add(refA());
      expect(s.setHover(refA()), isFalse);
      expect(s.hover, isNull);
    });

    test('a pick clears the prehighlight that led to it', () {
      final s = MeasureSession()..setHover(refA());
      s.add(refA());
      expect(s.hover, isNull);
      expect(s.picks.length, 1);
    });

    test('deselecting frees the thing to prehighlight again', () {
      final s = MeasureSession()..add(refA());
      s.add(refA()); // the same tap again: deselect
      expect(s.picks, isEmpty);
      expect(s.setHover(refA()), isTrue);
    });

    test('Restart takes the prehighlight with it', () {
      final s = MeasureSession()..add(refA());
      s.setHover(refB());
      s.clearPicks();
      expect(s.hover, isNull);
    });

    test('it is never a pick and never reaches the reading', () {
      final s = MeasureSession()..add(refA());
      s.setHover(refB());
      // One point picked and one hovered is not two points measured.
      expect(s.picks.length, 1);
      expect(s.reading?.primary.role, isNot(MeasureRole.distance));
    });
  });
}
