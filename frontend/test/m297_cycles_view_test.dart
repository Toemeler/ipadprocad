// M297 — the camera the Cycles render is given is the camera on screen.
//
// The renderer is C++ that first compiles in CI and first runs on a device.
// The arithmetic in front of it is not, and it is where the first render is
// most likely to go wrong: a camera matrix is twelve doubles and a convention,
// and the classic error — taking Z as -dir instead of +dir — renders the model
// from BEHIND, which on a symmetric part is a picture that looks almost right.
//
// So the test is not "these twelve numbers equal those twelve numbers". It is
// the property that actually matters: a world point projected THROUGH the
// matrix lands where Cam3.project puts it. If the two agree, the render frames
// what the viewport frames, and no convention has been guessed.
import 'dart:math' as math;

import 'dart:typed_data';

import 'package:flutter/painting.dart' show Size;
import 'package:prototype/ffi/occt_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_view.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';

const _size = Size(400, 300);

Cam3 _cam({double az = 0.7, double pol = 0.9, double halfH = 30,
    double ox = 0, double oy = 0, double roll = 0}) =>
    Cam3(PartCamera(az: az, pol: pol, halfH: halfH, ox: ox, oy: oy, roll: roll),
        _size);

/// The app's own projection, in the same normalised [-1, 1] the matrix path
/// produces — Cam3.project goes on to map that into pixels.
(double, double) _appProject(Cam3 c, Vec3 w) {
  final px = c.project(w);
  return (
    (px.dx / _size.width) * 2 - 1,
    -((px.dy / _size.height) * 2 - 1),
  );
}

void main() {
  group('the matrix agrees with the viewport', () {
    test('on every camera, for points all over the model', () {
      // The whole verification. Four cameras that differ in every degree of
      // freedom the app has — direction, zoom, pan and roll — against points
      // spread through a 40 mm box.
      final cams = [
        _cam(),
        _cam(az: -2.1, pol: 0.3, halfH: 12),
        _cam(az: 1.1, pol: 2.4, halfH: 55, ox: 7, oy: -4),
        _cam(az: 0.2, pol: 1.4, halfH: 20, roll: 1.0),
      ];
      final points = [
        const Vec3(0, 0, 0),
        const Vec3(20, 0, 0),
        const Vec3(0, 20, 0),
        const Vec3(0, 0, 20),
        const Vec3(-13, 7, 19),
        const Vec3(11, -18, -6),
      ];
      for (final c in cams) {
        final m = cyclesCameraMatrix(c, 40);
        final (halfW, halfH) = cyclesViewplane(c);
        for (final p in points) {
          final (ax, ay) = _appProject(c, p);
          final (cx, cy) = cyclesProject(m, halfW, halfH, p);
          expect(cx, closeTo(ax, 1e-9), reason: 'x for $p');
          expect(cy, closeTo(ay, 1e-9), reason: 'y for $p');
        }
      }
    });
  });

  group('the matrix is a camera', () {
    test('its basis is orthonormal, and LEFT-handed as Cycles expects', () {
      // Cycles applies it as a rigid transform, so a basis that is not
      // orthonormal skews the image. The handedness is not a free choice and
      // not a bug: Blender builds this matrix as `tfm * scale(1, 1, -1)`
      // (intern/cycles/blender/camera.cpp), which reflects a right-handed
      // object matrix. Asserting right-handedness here is what let M297 ship
      // a camera pointing the wrong way for four builds.
      final m = cyclesCameraMatrix(_cam(), 40);
      final x = Vec3(m[0], m[4], m[8]);
      final y = Vec3(m[1], m[5], m[9]);
      final z = Vec3(m[2], m[6], m[10]);
      for (final v in [x, y, z]) {
        expect(math.sqrt(v.dot(v)), closeTo(1, 1e-9));
      }
      expect(x.dot(y).abs(), lessThan(1e-9));
      expect(y.dot(z).abs(), lessThan(1e-9));
      expect(z.dot(x).abs(), lessThan(1e-9));
      final cross = x.cross(y);
      expect(cross.x, closeTo(-z.x, 1e-9));
      expect(cross.y, closeTo(-z.y, 1e-9));
      expect(cross.z, closeTo(-z.z, 1e-9));
    });

    test('Z is the direction the camera LOOKS, which is -dir', () {
      // The error this test exists for, and the one it originally asserted.
      //
      // Cam3.dir points from the model TOWARDS the eye. Cycles' third column
      // is the forward direction: the kernel shoots orthographic rays along
      // +Z of this matrix (kernel/camera/camera.h, D = (0,0,1)) and
      // projection_orthographic() contains no flip to undo it.
      //
      // Getting this backwards does not render the far side of the model, as
      // the first version of this test claimed. It renders NO model: every ray
      // leaves the eye going away from the scene and terminates on the world,
      // and the result is a frame of perfectly uniform background that looks
      // like a display bug rather than a camera bug.
      final c = _cam();
      final m = cyclesCameraMatrix(c, 40);
      final z = Vec3(m[2], m[6], m[10]);
      final d = c.dir;
      final n = math.sqrt(d.dot(d));
      expect(z.dot(Vec3(d.x / n, d.y / n, d.z / n)), closeTo(-1, 1e-9),
          reason: 'Z must be -dir; +dir points every ray away from the model');
    });

    test('the eye is outside the model, whichever way it is turned', () {
      // An orthographic camera's position does not change the framing, but
      // Cycles clips what is behind it. Nothing of a model of the given reach
      // may end up behind the eye.
      const reach = 40.0;
      for (final c in [
        _cam(),
        _cam(az: -2.1, pol: 0.3),
        _cam(az: 1.1, pol: 2.4),
        _cam(az: 3.0, pol: 1.6),
      ]) {
        final m = cyclesCameraMatrix(c, reach);
        final eye = Vec3(m[3], m[7], m[11]);
        expect(math.sqrt(eye.dot(eye)), greaterThan(reach),
            reason: 'the eye sits inside a model of reach $reach');
      }
    });

    test('the pan moves the eye, not the viewplane', () {
      // The app pans by moving ox/oy, which slides what is at the centre of
      // the view. Cycles has no pan: it has to come out in the camera's
      // position, or the render would ignore it and frame the origin.
      final a = cyclesCameraMatrix(_cam(ox: 0, oy: 0), 40);
      final b = cyclesCameraMatrix(_cam(ox: 9, oy: -5), 40);
      expect(Vec3(b[3] - a[3], b[7] - a[7], b[11] - a[11]).dot(
          Vec3(b[3] - a[3], b[7] - a[7], b[11] - a[11])),
          greaterThan(1e-6));
      // ...and the viewplane is untouched by it.
      final (aw, ah) = cyclesViewplane(_cam(ox: 0, oy: 0));
      final (bw, bh) = cyclesViewplane(_cam(ox: 9, oy: -5));
      expect(aw, bw);
      expect(ah, bh);
    });
  });

  group('the viewplane is the zoom', () {
    test('half-height is halfH and half-width follows the aspect', () {
      final c = _cam(halfH: 27);
      final (w, h) = cyclesViewplane(c);
      expect(h, 27);
      expect(w, closeTo(27 * (400 / 300), 1e-12));
    });

    test('zooming in shrinks it', () {
      final (w1, h1) = cyclesViewplane(_cam(halfH: 40));
      final (w2, h2) = cyclesViewplane(_cam(halfH: 10));
      expect(h2, lessThan(h1));
      expect(w2, lessThan(w1));
    });
  });

  _sceneTests();

  group('the reach', () {
    test('is the furthest point from the origin', () {
      expect(cyclesReach([const Vec3(3, 4, 0), const Vec3(1, 1, 1)]),
          closeTo(5, 1e-12));
      expect(cyclesReach(const []), 0);
    });

    test('a degenerate reach still puts the eye somewhere sane', () {
      // An empty document, or one whose geometry is all at the origin.
      final m = cyclesCameraMatrix(_cam(), 0);
      final eye = Vec3(m[3], m[7], m[11]);
      expect(math.sqrt(eye.dot(eye)), greaterThan(0));
      for (final v in m) {
        expect(v.isFinite, isTrue);
      }
    });
  });
}

// ---------------------------------------------------------------------------
// M300 — the scene handed over, and the key that decides when it is stale.
// ---------------------------------------------------------------------------

KernelSolid _tri({bool normals = true}) {
  final pos = Float64List.fromList([0, 0, 0, 10, 0, 0, 0, 10, 0]);
  final nor = Float64List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1]);
  return KernelSolid(
      OcctMeshData(
        pos,
        normals ? nor : Float64List(0),
        Int32List.fromList([0, 1, 2]),
        Int32List.fromList([0]),
        Float64List(0),
        triFaces: Int32List.fromList([0]),
      ),
      1,
      null);
}

void _sceneTests() {
  group('the meshes handed to Cycles', () {
    test('narrow to 32-bit once, here, and keep their shape', () {
      final out = cyclesMeshes([_tri()]);
      expect(out.length, 1);
      final (v, n, t) = out.first;
      expect(v, isA<Float32List>());
      expect(v.length, 9);
      expect(v[3], closeTo(10, 1e-6));
      expect(n, isNotNull);
      expect(n!.length, 9);
      expect(t, isA<Int32List>());
      expect(t, [0, 1, 2]);
    });

    test('a solid with no normals travels without them', () {
      // Partial or absent normals are not made up: Cycles would smooth-shade
      // some triangles and not others, and the seam reads as a modelling
      // error. The shim flat-shades when normals is null.
      final (_, n, _) = cyclesMeshes([_tri(normals: false)]).first;
      expect(n, isNull);
    });

    test('a degenerate solid is skipped, not sent as garbage', () {
      final empty = KernelSolid(
          OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
              Int32List.fromList([0]), Float64List(0)),
          0,
          null);
      expect(cyclesMeshes([empty]), isEmpty);
    });
  });

  group('the camera key', () {
    test('changes when the view changes, and only then', () {
      final a = cyclesCameraKey(_cam());
      expect(cyclesCameraKey(_cam()), a, reason: 'same camera, same key');
      expect(cyclesCameraKey(_cam(az: 0.71)), isNot(a));
      expect(cyclesCameraKey(_cam(halfH: 31)), isNot(a));
      expect(cyclesCameraKey(_cam(ox: 1)), isNot(a));
      expect(cyclesCameraKey(_cam(roll: 0.1)), isNot(a),
          reason: 'roll turns the image even though dir is unchanged');
    });
  });
}
