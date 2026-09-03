// M371 — what a TAP means, on the host.
//
// The companion to m371_measure_test.dart, which pins the arithmetic. This
// one pins the half that turns a pixel into a [MeasureRef]: the 2D sketcher's
// snap-then-entity order, and the 3D pass over a real tessellation — the same
// synthetic cylinder the render tests use, so the geometry under the finger is
// the geometry the shim would actually have produced.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/measure.dart';
import 'package:prototype/measure_pick.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart' show Cam3;
import 'package:prototype/quat.dart';

import 'synth_mesh.dart';

const double eps = 1e-9;

/// A camera looking straight down -Z at a [size] window, centred on the
/// origin. [halfH] is half the world height it shows, so the scale is
/// `size.height / (2 * halfH)` pixels per millimetre.
///
/// The scale matters to these tests and is worth stating: the pick
/// tolerances are in PIXELS, so a camera zoomed far enough out puts a
/// vertex twelve pixels from a tap that was plainly meant for the face in
/// the middle of the part. That is correct behaviour on glass and a
/// misleading fixture here, so the cameras below are set at a working zoom.
Cam3 topDownCam(Size size, {double halfH = 15}) => Cam3.basis(
      dir: const Vec3(0, 0, 1),
      s: const Vec3(1, 0, 0),
      u: const Vec3(0, 1, 0),
      halfH: halfH,
      ox: 0,
      oy: 0,
      size: size,
    );

/// Looking down -Y at the barrel of an upright cylinder.
Cam3 frontCam(Size size, {double halfH = 30}) => Cam3.basis(
      dir: const Vec3(0, -1, 0),
      s: const Vec3(1, 0, 0),
      u: const Vec3(0, 0, 1),
      halfH: halfH,
      ox: 0,
      oy: 0,
      size: size,
    );

/// A single flat SQUARE face, two triangles, four straight display edges —
/// the fixture for the claim that a planar area is exact rather than
/// converging.
OcctMeshData squareFaceMesh(double side) {
  final p = <double>[
    0, 0, 0, side, 0, 0, side, side, 0, 0, side, 0, //
  ];
  final n = <double>[for (var i = 0; i < 4; i++) ...[0, 0, 1]];
  final idx = <int>[0, 1, 2, 0, 2, 3];
  final ep = <double>[
    0, 0, 0, side, 0, 0, //
    side, 0, 0, side, side, 0, //
    side, side, 0, 0, side, 0, //
    0, side, 0, 0, 0, 0, //
  ];
  return OcctMeshData(
    Float64List.fromList(p),
    Float64List.fromList(n),
    Int32List.fromList(idx),
    Int32List.fromList(const [0, 2, 4, 6, 8]),
    Float64List.fromList(ep),
    triFaces: Int32List.fromList(const [0, 0]),
    faceInfos: Float64List.fromList(
        <double>[0, 0, 0, 0, 0, 0, 1, 1, 0, 0, 0, 0, side, 0, side]),
    edgeCurves: Float64List.fromList(<double>[
      for (final e in [
        [0.0, 0.0, 0.0, side, 0.0, 0.0],
        [side, 0.0, 0.0, side, side, 0.0],
        [side, side, 0.0, 0.0, side, 0.0],
        [0.0, side, 0.0, 0.0, 0.0, 0.0],
      ])
        ...[1, e[0], e[1], e[2], e[3], e[4], e[5], 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ]),
  );
}

void main() {
  // =========================================================================
  group('2D — the sketcher', () {
    test('a tap on a line answers with the line, and its length', () {
      final geos = [
        const Geo(Geo.line, [0, 0, 10, 0]),
      ];
      // Well away from either endpoint AND from the midpoint at x = 5, so
      // no snap point takes the tap first.
      final r = measurePickSketch(geos, const Offset(3, 0.1), 0.5)!;
      expect(r.kind, MeasureRefKind.line);
      expect(measureSingle(r)!.primary.value, closeTo(10, eps));
    });

    test('a tap on an ENDPOINT answers with the point, not the line', () {
      final geos = [
        const Geo(Geo.line, [0, 0, 10, 0]),
      ];
      final r = measurePickSketch(geos, const Offset(0.1, 0.1), 1.0)!;
      expect(r.kind, MeasureRefKind.point);
      expect(r.point!.x, closeTo(0, eps));
    });

    test('a tap on a MIDPOINT answers with the midpoint', () {
      final geos = [
        const Geo(Geo.line, [0, 0, 10, 0]),
      ];
      final r = measurePickSketch(geos, const Offset(5.05, 0.05), 0.5)!;
      expect(r.kind, MeasureRefKind.point);
      expect(r.point!.x, closeTo(5, eps));
    });

    test('a tap on a circle CENTRE answers with the centre', () {
      final geos = [
        const Geo(Geo.circle, [3, 4, 5]),
      ];
      final r = measurePickSketch(geos, const Offset(3.05, 4.05), 0.5)!;
      expect(r.kind, MeasureRefKind.point);
      expect(r.point!.x, closeTo(3, eps));
      expect(r.point!.y, closeTo(4, eps));
    });

    test('a tap on the RIM answers with the circle and its diameter', () {
      final geos = [
        const Geo(Geo.circle, [0, 0, 5]),
      ];
      // On the rim, but a long way from any quadrant point.
      final at = Offset(5 * math.cos(0.7), 5 * math.sin(0.7));
      final r = measurePickSketch(geos, at, 0.5)!;
      expect(r.kind, MeasureRefKind.circle);
      final reading = measureSingle(r)!;
      expect(reading.primary.role, MeasureRole.diameter);
      expect(reading.primary.value, closeTo(10, eps));
      expect(reading.valueOf(MeasureRole.area)!.value,
          closeTo(math.pi * 25, eps));
    });

    test('a sketch POINT is a point, never a tiny circle', () {
      // M209's carrier: a circle tagged pointTag. Measuring its radius would
      // be measuring a drawing detail.
      const g = Geo(Geo.circle, [2, 2, 0.4], spline: Geo.pointTag);
      final r = measurePickSketch([g], const Offset(2, 2), 1.0)!;
      expect(r.kind, MeasureRefKind.point);
    });

    test('an arc answers with its arc length and its swept angle', () {
      // Quarter arc, radius 4, from 0 to pi/2.
      final g = Geo(Geo.arc, [0, 0, 4, 0, math.pi / 2, 0]);
      final at = Offset(4 * math.cos(0.6), 4 * math.sin(0.6));
      final r = measurePickSketch([g], at, 0.5)!;
      expect(r.kind, MeasureRefKind.arc);
      final reading = measureSingle(r)!;
      expect(reading.primary.value, closeTo(4 * math.pi / 2, 1e-6));
      expect(reading.valueOf(MeasureRole.includedAngle)!.value * 180 / math.pi,
          closeTo(90, 1e-6));
    });

    test('a REVERSED arc reports the same length as the one it draws', () {
      // The reversed flag is read exactly as sampleEntity reads it, so the
      // number and the curve on screen can never disagree.
      final fwd = Geo(Geo.arc, [0, 0, 4, 0, math.pi / 2, 0]);
      final rev = Geo(Geo.arc, [0, 0, 4, math.pi / 2, 0, 1]);
      final a = measureRefOfGeo(fwd)!, b = measureRefOfGeo(rev)!;
      expect(a.length!, closeTo(b.length!, 1e-9));
      expect(a.length!, closeTo(4 * math.pi / 2, 1e-9));
    });

    test('a closed polyline reports perimeter and enclosed area', () {
      // rect 4 x 3, closed flag set
      const g = Geo(Geo.polyline, [1, 4, 0, 0, 4, 0, 4, 3, 0, 3]);
      final r = measureRefOfGeo(g)!;
      expect(r.closed, isTrue);
      final reading = measureSingle(r)!;
      expect(reading.primary.value, closeTo(14, eps));
      expect(reading.valueOf(MeasureRole.area)!.value, closeTo(12, eps));
    });

    test('an OPEN polyline reports a length and no area', () {
      const g = Geo(Geo.polyline, [0, 3, 0, 0, 4, 0, 4, 3]);
      final r = measureRefOfGeo(g)!;
      expect(r.closed, isFalse);
      expect(measureSingle(r)!.valueOf(MeasureRole.area), isNull);
    });

    test('an ellipse reads its two half-axes off its three grips', () {
      // centre (0,0), major vertex (6,0), minor vertex (0,2)
      const g = Geo(Geo.polyline, [0, 3, 0, 0, 6, 0, 0, 2],
          spline: Geo.ellipseTag);
      final r = measureRefOfGeo(g)!;
      expect(r.kind, MeasureRefKind.ellipse);
      expect(r.radius, closeTo(6, eps));
      expect(r.minorRadius, closeTo(2, eps));
      expect(measureSingle(r)!.valueOf(MeasureRole.area)!.value,
          closeTo(math.pi * 12, eps));
    });

    test('a tap on nothing measures nothing', () {
      final geos = [const Geo(Geo.line, [0, 0, 10, 0])];
      expect(measurePickSketch(geos, const Offset(50, 50), 1.0), isNull);
    });

    test('two sketch picks measure exactly as their 3D equivalents do', () {
      // The whole point of embedding the sketch at z = 0: this is the same
      // solver the part viewport runs.
      final geos = [
        const Geo(Geo.line, [0, 0, 10, 0]),
        const Geo(Geo.line, [0, 6, 10, 6]),
      ];
      final a = measurePickSketch(geos, const Offset(5, 0.1), 0.3)!;
      final b = measurePickSketch(geos, const Offset(5, 6.1), 0.3)!;
      final r = measurePair(a, b)!;
      expect(r.primary.role, MeasureRole.distance);
      expect(r.primary.value, closeTo(6, eps));
    });
  });

  // =========================================================================
  group('3D — a tessellated cylinder', () {
    const r = 10.0, h = 40.0;
    final mesh = synthCylinderMesh(r, h, 0.05);

    test('a tap in the middle of the top cap answers with a PLANE', () {
      // Straight down onto the disc at z = h, well inside the rim.
      final cam = topDownCam(const Size(200, 200));
      final px = cam.project(const Vec3(2, 2, h));
      final pick = measurePickMesh(mesh, cam, px)!;
      expect(pick.ref.kind, MeasureRefKind.plane);
      // The cap's area is pi r^2 within the tessellation's own error.
      expect(pick.ref.area!, closeTo(math.pi * r * r, math.pi * r * r * 0.01));
    });

    test('the top cap reports the outward normal, so dihedrals come out '
        'right', () {
      final cam = topDownCam(const Size(200, 200));
      final pick = measurePickMesh(mesh, cam, cam.project(const Vec3(2, 2, h)))!;
      expect(pick.ref.planeIsOriented, isTrue);
      expect(pick.ref.planeNormal!.z, closeTo(1, 1e-9));
    });

    test('a tap on the barrel answers with a CYLINDER, its diameter and its '
        'height', () {
      final cam = frontCam(const Size(200, 200));
      // Halfway up the front of the barrel.
      final px = cam.project(Vec3(0, -r, h / 2));
      final pick = measurePickMesh(mesh, cam, px)!;
      expect(pick.ref.kind, MeasureRefKind.cylinder);
      final reading = measureSingle(pick.ref)!;
      expect(reading.primary.role, MeasureRole.diameter);
      expect(reading.primary.value, closeTo(2 * r, 1e-9));
      expect(reading.valueOf(MeasureRole.height)!.value, closeTo(h, 1e-9));
    });

    test('the barrel does NOT report its seam as part of the loop length', () {
      // A full cylinder's boundary is its two rims. The tessellation
      // duplicates the vertices along the seam, so an index-keyed boundary
      // count would have added 2 h to this — see faceLoopLength.
      final loop = faceLoopLength(mesh, synthBarrelFace);
      expect(loop, closeTo(2 * (2 * math.pi * r), 2 * math.pi * r * 0.02));
    });

    test('a face bounded by a CURVE converges as the deflection tightens', () {
      // The cap is a disc, and its triangulation is an inscribed n-gon: the
      // area is under the true one and climbs towards it as n grows. This is
      // the reading that gets marked approximate.
      final coarse = faceArea(synthCylinderMesh(r, h, 0.4), synthTopFace);
      final fine = faceArea(synthCylinderMesh(r, h, 0.005), synthTopFace);
      expect(coarse, lessThan(fine));
      expect(fine, lessThan(math.pi * r * r));
      expect(fine, closeTo(math.pi * r * r, math.pi * r * r * 0.01));
    });

    test('a face bounded by STRAIGHT edges is exact', () {
      // A polygon's triangulation has the polygon's area exactly, whatever
      // the deflection — which is why a planar face's area is not marked
      // approximate.
      expect(faceArea(squareFaceMesh(7), 0), closeTo(49, 1e-12));
    });

    test('a straight-edged face reports its perimeter exactly too', () {
      expect(faceLoopLength(squareFaceMesh(7), 0), closeTo(28, 1e-12));
    });

    test('a tap on the rim answers with the CIRCLE, from its analytic '
        'record', () {
      final cam = topDownCam(const Size(400, 400));
      // On the rim of the top cap, away from anything else.
      final on = Vec3(r * math.cos(0.7), r * math.sin(0.7), h);
      final pick = measurePickMesh(mesh, cam, cam.project(on))!;
      expect(pick.ref.kind, MeasureRefKind.circle);
      // Read from the curve record, so it is EXACT rather than the
      // tessellation's inscribed radius.
      expect(pick.ref.radius, closeTo(r, 1e-12));
      expect(pick.ref.point!.z, closeTo(h, 1e-12));
    });

    test('the analytic radius does not move when the deflection does', () {
      final cam = topDownCam(const Size(400, 400));
      final on = Vec3(r * math.cos(0.7), r * math.sin(0.7), h);
      for (final lin in [0.4, 0.05, 0.005]) {
        final m = synthCylinderMesh(r, h, lin);
        final pick = measurePickMesh(m, cam, cam.project(on));
        expect(pick, isNotNull, reason: 'nothing picked at deflection $lin');
        expect(pick!.ref.radius, closeTo(r, 1e-12));
      }
    });

    test('a tap on nothing measures nothing', () {
      final cam = topDownCam(const Size(200, 200));
      expect(measurePickMesh(mesh, cam, const Offset(2, 2)), isNull);
    });

    test('two rims of the same cylinder measure the height between them', () {
      final cam = topDownCam(const Size(400, 400));
      final top = measurePickMesh(mesh, cam,
              cam.project(Vec3(r * math.cos(0.7), r * math.sin(0.7), h)))!
          .ref;
      // The bottom rim, built straight from the record rather than picked —
      // it is hidden behind the top one from this camera, which is the
      // depth rule working.
      final bottom = MeasureRef.circle(Vec3.zero, const Vec3(0, 0, 1), r);
      final reading =
          measurePair(top, bottom, mode: MeasureDistanceMode.centre)!;
      expect(reading.primary.value, closeTo(h, 1e-9));
    });

    test('a mesh with no v4 metadata still measures its edges', () {
      // A fake or legacy mesh: no face records, no curve records. The edge
      // polyline is still an honest length, and the pick must not crash or
      // return nothing.
      final legacy = synthCylinderMesh(r, h, 0.05, v4: false);
      final cam = topDownCam(const Size(400, 400));
      final on = Vec3(r * math.cos(0.7), r * math.sin(0.7), h);
      final pick = measurePickMesh(legacy, cam, cam.project(on));
      expect(pick, isNotNull);
      expect(pick!.ref.kind, MeasureRefKind.curve);
      expect(pick.ref.length!, closeTo(2 * math.pi * r, 2 * math.pi * r * 0.02));
    });
  });

  // =========================================================================
  group('3D — vertices win over the edges they end', () {
    test('a tap on the end of an edge answers with the vertex', () {
      // A single straight edge, as a mesh with nothing else in it.
      final m = _twoPointEdgeMesh(const Vec3(0, 0, 0), const Vec3(50, 0, 0));
      final cam = topDownCam(const Size(200, 200));
      final atEnd = measurePickMesh(m, cam, cam.project(const Vec3(50, 0, 0)))!;
      expect(atEnd.ref.kind, MeasureRefKind.point);
      expect(atEnd.ref.point!.x, closeTo(50, eps));
    });

    test('a tap in the MIDDLE of the same edge answers with the edge', () {
      final m = _twoPointEdgeMesh(const Vec3(0, 0, 0), const Vec3(50, 0, 0));
      final cam = topDownCam(const Size(200, 200));
      final mid = measurePickMesh(m, cam, cam.project(const Vec3(25, 0, 0)))!;
      expect(mid.ref.kind, MeasureRefKind.curve,
          reason: 'no curve record on this fixture, so it reads as a curve');
      expect(mid.ref.length!, closeTo(50, eps));
    });
  });

  // =========================================================================
  group('bodies', () {
    test('a solid carries its kernel volume, not one guessed from the mesh',
        () {
      final solid = KernelSolid(synthCylinderMesh(10, 40, 0.05), 12566.37, null);
      final ref = measureRefOfSolid(solid);
      expect(ref.kind, MeasureRefKind.body);
      expect(measureSingle(ref)!.primary.value, closeTo(12566.37, 1e-6));
    });

    test('a solid with no kernel volume reports its extents instead of a '
        'zero', () {
      final solid = KernelSolid(synthCylinderMesh(10, 40, 0.05), 0, null);
      final reading = measureSingle(measureRefOfSolid(solid))!;
      expect(reading.valueOf(MeasureRole.volume), isNull);
      expect(reading.valueOf(MeasureRole.extentZ)!.value, closeTo(40, 1e-6));
    });

    test('a placed solid is measured where it was placed', () {
      final solid = KernelSolid(synthCylinderMesh(10, 40, 0.05), 100, null);
      final ref = measureRefOfSolid(solid,
          at: const Placement(Quat.identity, Vec3(100, 0, 0)));
      expect(ref.boxLo!.x, closeTo(90, 1e-6));
      expect(ref.boxHi!.x, closeTo(110, 1e-6));
    });
  });
}

/// A mesh holding ONE straight display edge and no triangles — the smallest
/// fixture that exercises the vertex-beats-edge rule.
OcctMeshData _twoPointEdgeMesh(Vec3 a, Vec3 b) => OcctMeshData(
      Float64List.fromList(const []),
      Float64List.fromList(const []),
      Int32List.fromList(const []),
      Int32List.fromList(const [0, 2]),
      Float64List.fromList([a.x, a.y, a.z, b.x, b.y, b.z]),
    );
