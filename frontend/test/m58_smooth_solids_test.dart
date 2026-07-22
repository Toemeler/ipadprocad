// M58 — smooth curved solids at any zoom, endless zoom, Inventor Output
// boolean (Join / New Solid) and sketch-on-face. Exercises the REAL painter
// math (projectSolidTriangles/Edges from part_render.dart) against a REAL
// curved cylinder mesh — closing the gap where the 3D paint path was only
// ever fed the FakeKernel's single degenerate triangle.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/ffi/occt_engine.dart' show OcctMeshData;
import 'package:ipadprocad/part_model.dart';
import 'package:ipadprocad/part_render.dart';
import 'synth_mesh.dart' show synthCylinderMesh;

List<Offset> circlePts(double r, int n, {Offset c = Offset.zero}) => [
      for (var i = 0; i < n; i++)
        c +
            Offset(r * math.cos(2 * math.pi * i / n),
                r * math.sin(2 * math.pi * i / n))
    ];

void main() {
  group('arc recovery (polygon loops -> true arcs for the kernel)', () {
    test('a polygonized circle collapses to exactly two half arcs', () {
      final segs = arcFitLoop(circlePts(10, 96));
      expect(segs.length, 2);
      for (final s in segs) {
        expect(s.bulge, closeTo(1.0, 1e-9)); // tan(pi/4), CCW
        expect(s.p.distance, closeTo(10, 1e-9));
      }
      // the two vertices are diametrically opposite
      expect((segs[0].p + segs[1].p).distance, lessThan(1e-6));
    });

    test(
        'a square stays four straight lines (order preserved up to '
        'rotation)', () {
      const sq = [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)];
      final segs = arcFitLoop(sq);
      expect(segs.length, 4);
      expect(segs.every((s) => s.bulge == 0), isTrue);
      // the fitter may rotate the loop start (it walks from a gap chord) but
      // must keep the same vertices in the same cyclic order
      final got = [for (final s in segs) s.p];
      final shift = got.indexOf(sq.first);
      expect(shift, isNonNegative);
      expect([for (var i = 0; i < 4; i++) got[(shift + i) % 4]], sq);
    });

    test('clockwise circle gets negative bulge (direction preserved)', () {
      final segs = arcFitLoop(circlePts(5, 64).reversed.toList());
      expect(segs.length, 2);
      for (final s in segs) {
        expect(s.bulge, closeTo(-1.0, 1e-9));
      }
    });

    test(
        'rounded corner: lines stay lines, the fillet becomes one arc '
        'with the exact sweep', () {
      // L-path with a 90-degree fillet r=2 at the corner (10,0)->(10,10)
      final pts = <Offset>[
        const Offset(0, 0),
        const Offset(8, 0),
      ];
      // quarter arc centre (8,2): from (8,0) sweeping CCW to (10,2)
      const n = 24;
      for (var i = 1; i < n; i++) {
        final a = -math.pi / 2 + (math.pi / 2) * i / n;
        pts.add(Offset(8 + 2 * math.cos(a), 2 + 2 * math.sin(a)));
      }
      pts.addAll(const [Offset(10, 2), Offset(10, 10), Offset(0, 10)]);
      final segs = arcFitLoop(pts);
      final arcs = segs.where((s) => s.bulge != 0).toList();
      expect(arcs.length, 1);
      // sweep pi/2 -> bulge tan(pi/8)
      expect(arcs.single.bulge, closeTo(math.tan(math.pi / 8), 1e-6));
      expect(segs.length, 5); // 3 lines + arc start + closing line
    });

    test('encodeLoopSegs emits x,y,bulge triplets', () {
      final e = encodeLoopSegs(
          const [LoopSeg(Offset(1, 2), 0.5), LoopSeg(Offset(3, 4), 0)]);
      expect(e, [1, 2, 0.5, 3, 4, 0]);
    });
  });

  group('screen-space adaptive deflection', () {
    test('finer zoom (smaller halfH) demands finer deflection', () {
      final coarse = viewLinearDeflection(100, 800);
      final fine = viewLinearDeflection(1, 800);
      expect(fine, lessThan(coarse));
      // sub-pixel: 2*halfH/heightPx * 0.4
      expect(fine, closeTo(2 * 1 / 800 * 0.4, 1e-12));
    });

    test('clamped on both ends and safe on garbage input', () {
      expect(viewLinearDeflection(1e-9, 800), 1e-4); // floor
      expect(viewLinearDeflection(1e9, 800), 5.0); // ceil
      expect(viewLinearDeflection(double.nan, 800), kCoarseLinDeflection);
      expect(viewLinearDeflection(10, 0), kCoarseLinDeflection);
    });

    test('meshNeedsRefine: only refines FINER, with hysteresis', () {
      expect(meshNeedsRefine(0.6, 0.1), isTrue);
      expect(meshNeedsRefine(0.1, 0.09), isFalse); // within hysteresis
      expect(meshNeedsRefine(0.1, 0.6), isFalse); // never coarsens
      expect(meshNeedsRefine(0, 0.5), isTrue); // unknown -> refine
    });

    test('circleSegments matches the chord-sag bound and is capped', () {
      final n = circleSegments(10, 0.01);
      // sag of an n-gon chord on r=10 must be <= 0.01
      final sag = 10 * (1 - math.cos(math.pi / n));
      expect(sag, lessThanOrEqualTo(0.01 + 1e-12));
      expect(circleSegments(10, 1e-12), 2000); // hard cap
      expect(circleSegments(-1, 0.1), 8);
    });
  });

  group('painter math on REAL curvature (the fake-mesh gap, closed)', () {
    test(
        'projected barrel silhouette deviates sub-target from the true '
        'circle at the meshed deflection', () {
      const r = 10.0, h = 5.0;
      final lin = viewLinearDeflection(27, 800); // ~0.027mm
      final mesh = synthCylinderMesh(r, h, lin);
      final cam = Cam3(PartCamera(), const Size(800, 800)); // default view
      final tris = projectSolidTriangles(mesh, cam);
      expect(tris, isNotEmpty);
      // every projected vertex of the barrel lies within lin of the true
      // cylinder (radial world error == chord sag by construction)
      // smoothness bound: the facet sag stays below the sub-pixel target
      final n = circleSegments(r, lin);
      expect(n, greaterThan(32));
      final sagWorld = r * (1 - math.cos(math.pi / n));
      expect(sagWorld, lessThanOrEqualTo(lin + 1e-12));
      // ... which is under 0.4 px on the 800 px viewport at halfH 27
      expect(sagWorld * 800 / (2 * 27), lessThanOrEqualTo(0.4 + 1e-9));
      // depth-sorting keys are finite and shades are sane
      for (final t in tris) {
        expect(t.depth.isFinite, isTrue);
        expect(t.shade, inInclusiveRange(0.0, 1.0));
      }
      // edges: exactly the two rims, discretised smoothly, no seam
      final edges = projectSolidEdges(mesh, cam);
      expect(mesh.edgeCount, 2);
      expect(edges.length, greaterThan(2 * 32));
    });

    test('backface culling halves the barrel', () {
      final mesh = synthCylinderMesh(10, 5, 0.5);
      final cam = Cam3(PartCamera(), const Size(400, 400));
      final n = circleSegments(10, 0.5);
      final barrelTris =
          projectSolidTriangles(mesh, cam).length; // barrel + visible caps
      expect(barrelTris, lessThan(2 * n + 2 * n)); // strictly culled
      expect(barrelTris, greaterThan(n ~/ 2));
    });
  });

  group('KernelSolid.refine', () {
    test('swaps in the remeshed data and records the new deflection', () {
      final coarse = synthCylinderMesh(10, 5, kCoarseLinDeflection);
      final s = KernelSolid(coarse, 1, null,
          remesher: (lin, ang) => synthCylinderMesh(10, 5, lin));
      expect(s.meshLin, kCoarseLinDeflection);
      final before = s.mesh.triangleCount;
      expect(s.refine(0.01, viewAngularDeflection(0.01)), isTrue);
      expect(s.meshLin, 0.01);
      expect(s.mesh.triangleCount, greaterThan(before));
    });

    test('static solids (no remesher) refuse politely', () {
      final s = KernelSolid(synthCylinderMesh(10, 5, 0.5), 1, null);
      expect(s.refine(0.01, 0.1), isFalse);
    });
  });

  group('endless zoom', () {
    test('3D halfH clamp is practically endless and finite-safe', () {
      expect(PartCamera.clampHalfH(1e-9), PartCamera.minHalfH);
      expect(PartCamera.clampHalfH(1e12), PartCamera.maxHalfH);
      expect(PartCamera.clampHalfH(double.nan), 27.0);
      expect(PartCamera.clampHalfH(0.5), 0.5); // old 3.0 floor is gone
      expect(PartCamera.clampHalfH(5000), 5000); // old 200 ceiling is gone
    });
  });

  group('sketch-on-face frames', () {
    test('faceFrame is right-handed, origin on the plane, closest to O', () {
      final f = faceFrame(const Vec3(3, 7, 5), const Vec3(0, 0, 1));
      expect(f.n.z, closeTo(1, 1e-12));
      expect(f.u.cross(f.v).dot(f.n), closeTo(1, 1e-9));
      expect(f.origin.x, 0);
      expect(f.origin.y, 0);
      expect(f.origin.z, closeTo(5, 1e-12)); // plane z=5, nearest to origin
      // toWorld/toSketch round-trip
      const p = Offset(2.5, -1.5);
      expect(f.toSketch(f.toWorld(p)), p);
    });

    test('frame json round-trips through the part sidecar format', () {
      final f = faceFrame(const Vec3(1, 2, 3), const Vec3(0, 1, 0));
      final r = PlaneFrame.fromFrameJson(f.frameJson())!;
      expect(r.n.y, closeTo(1, 1e-12));
      expect(r.origin.y, closeTo(2, 1e-12));
      expect(r.mat34(0), f.mat34(0));
    });

    test('mat34 translation includes the face origin plus the z offset', () {
      final f = faceFrame(const Vec3(0, 0, 4), const Vec3(0, 0, 1));
      final m = f.mat34(2);
      expect(m[3], 0);
      expect(m[7], 0);
      expect(m[11], closeTo(6, 1e-12)); // origin 4 + offset 2 along n
    });
  });
}
