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
  _floorTests();
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
  _materialTests();

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
      final (v, n, t, _) = out.first;
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
      final (_, n, _, _) = cyclesMeshes([_tri(normals: false)]).first;
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

// ---------------------------------------------------------------------------
// M323 — the body's appearance reaches the renderer.
// ---------------------------------------------------------------------------

void _materialTests() {
  group('materials', () {
    test('sRGB becomes linear, because a path tracer integrates linear light',
        () {
      // Handing sRGB straight to a renderer makes everything too bright in a
      // way that reads as a lighting bug rather than a colour-space one.
      expect(cyclesLinear(0), closeTo(0.0, 1e-9));
      expect(cyclesLinear(255), closeTo(1.0, 1e-9));
      // Mid grey is the case that gives it away: 0.5 sRGB is 0.21 linear.
      expect(cyclesLinear(128), closeTo(0.2158, 1e-3));
      expect(cyclesLinear(128), lessThan(128 / 255));
    });

    test('steel is the absence of a material, not a grey one', () {
      // materialArgb returns null for steel so the renderer keeps its own
      // default surface — a body with "no tint" and one tinted steel-coloured
      // are different things on the wire.
      expect(cyclesMaterial(null, null), isNull);
      expect(cyclesMaterial('steel', null), isNull);
    });

    test('a painted body carries its colour, converted', () {
      // brass, 0xFFC2A462
      final m = cyclesMaterial('brass', 0xFFC2A462)!;
      expect(m.r, closeTo(cyclesLinear(0xC2), 1e-9));
      expect(m.g, closeTo(cyclesLinear(0xA4), 1e-9));
      expect(m.b, closeTo(cyclesLinear(0x62), 1e-9));
      expect(m.r, greaterThan(m.g));
      expect(m.g, greaterThan(m.b));
    });

    test('with nothing to reflect, a metal is still only a trace of one', () {
      // M332's rule, unchanged, and it is the fallback every build without the
      // optional HDRI renders under: a surface at metallic 1.0 takes its
      // colour from what it reflects, and four lights and a dim room are not
      // enough to carry brass. The metals are told apart by FINISH here.
      final brass = cyclesMaterial('brass', 0xFFC2A462)!;
      final red = cyclesMaterial('red', 0xFFC05B54)!;
      expect(brass.roughness, lessThan(red.roughness));
      expect(brass.metallic, kCyclesMetallicNoEnvironment);
      // A trace, not a metal: past about a third the base colour stops
      // carrying the surface.
      expect(kCyclesMetallicNoEnvironment, greaterThan(0.0));
      expect(kCyclesMetallicNoEnvironment, lessThan(0.35));
    });

    test('with an HDRI to reflect, a metal becomes a metal', () {
      // M344 — the change the environment map exists to make. The old rule was
      // an argument about the SCENE, not about the material: brass held at
      // 0.15 because there was nothing for it to be metallic against. There is
      // now.
      final brass = cyclesMaterial('brass', 0xFFC2A462, environment: true)!;
      final red = cyclesMaterial('red', 0xFFC05B54, environment: true)!;
      expect(brass.metallic, 1.0);
      // A pigment is not a metal whatever the environment is. What makes it
      // read as paint is the clear coat, not a trace of metal.
      expect(red.metallic, 0.0);
      expect(red.coat, greaterThan(0.0));
      // And the reflectance is lifted to something a metal actually returns:
      // the palette's brass is a screen colour, and handed to a metal as-is it
      // is brass in deep shade.
      final peak = math.max(brass.r, math.max(brass.g, brass.b));
      expect(peak, closeTo(kCyclesMetalReflectance, 1e-6));
      // With its hue intact — it is still brass, not white.
      expect(brass.r, greaterThan(brass.b * 2));
    });

    test('steel is a metal too, and the roughest of them', () {
      // The commonest body in any assembly, and the reason an unpainted part
      // stopped looking like clay. Machined, not polished.
      final steel = cyclesSteel(environment: true);
      final copper = cyclesMaterial('copper', 0xFFB87A5A, environment: true)!;
      expect(steel.metallic, 1.0);
      expect(steel.roughness, greaterThan(copper.roughness));
      expect(steel.coat, 0.0);
    });

    test('a mesh carries the material it was built with', () {
      final mat = cyclesMaterial('blue', 0xFF5D82AF);
      final m = cyclesMeshAt(_tri(), null, material: mat);
      expect(m!.$4, mat);
      expect(cyclesMeshAt(_tri(), null)!.$4, isNull);
      // Two meshes built with the same appearance carry EQUAL materials, which
      // is what lets the FFI layer collapse them into one table row and the
      // shim into one Shader. Identity would not do: cyclesMaterial builds a
      // fresh one per body.
      final again = cyclesMaterial('blue', 0xFF5D82AF);
      expect(again, mat);
      expect(again.hashCode, mat.hashCode);
    });
  });
}

// M333 — the rendered view's floor, as geometry.
void _floorTests() {
  group('the floor', () {
    List<CyclesMesh> box(double lowY) {
      final v = Float32List.fromList([
        -5, lowY, -5, //
        5, lowY, -5, //
        5, lowY + 10, 5, //
      ]);
      return [(v, null, Int32List.fromList([0, 1, 2]), null)];
    }

    test('sits just under the lowest point of the model, not under the origin',
        () {
      // M276's fix on the RealityKit side, and the same reasoning: a floor at
      // -sceneRadius sits well below anything and the shadow comes out spread
      // wide and detached, reading as a stain rather than as contact.
      final f = cyclesFloorMesh(box(20), argb: 0xFF808080, lookingDown: true)!;
      final ys = [for (var i = 1; i < f.$1.length; i += 3) f.$1[i]];
      expect(ys.every((y) => y == ys.first), isTrue,
          reason: 'the floor is level');
      expect(ys.first, lessThan(20.0));
      expect(ys.first, greaterThan(19.9), reason: 'just under, not far under');
    });

    test('its normal points UP', () {
      // A floor wound the other way is lit from underneath and renders black.
      // Checked as the actual cross product rather than by reading the winding
      // back off the vertex list, because the winding is the thing under test.
      final f = cyclesFloorMesh(box(0), argb: 0xFF808080, lookingDown: true)!;
      final v = f.$1;
      final t = f.$3;
      double px(int i, int c) => v[t[i] * 3 + c];
      final ax = px(1, 0) - px(0, 0),
          ay = px(1, 1) - px(0, 1),
          az = px(1, 2) - px(0, 2);
      final bx = px(2, 0) - px(0, 0),
          by = px(2, 1) - px(0, 1),
          bz = px(2, 2) - px(0, 2);
      final ny = az * bx - ax * bz;
      expect(ny, greaterThan(0.0));
      // And flat: no x or z component.
      expect(ay * bz - az * by, closeTo(0, 1e-6));
      expect(ax * by - ay * bx, closeTo(0, 1e-6));
    });

    test('is far wider than the part, and does not depend on the zoom', () {
      // M277 — a floor sized from the scene alone is smaller than the frame
      // the moment you zoom out past the part, and its edge walking into view
      // takes the shadow with it. M333 answered that with the viewplane;
      // M344 cannot, because a floor whose size depends on the camera is
      // geometry re-uploaded on every frame of a pinch. So it is sized
      // generously from the model instead — past any zoom at which the part is
      // still recognisable.
      double span(List<CyclesMesh> m) {
        final f = cyclesFloorMesh(m, argb: 0xFF808080, lookingDown: true)!;
        final xs = [for (var i = 0; i < f.$1.length; i += 3) f.$1[i]];
        return xs.reduce(math.max) - xs.reduce(math.min);
      }

      final radius = cyclesMeshReach(box(0));
      expect(span(box(0)), greaterThan(radius * 10));
      // And it grows with the MODEL, which is the half that was always right.
      expect(span(box(0)), lessThan(span(box(200))));
    });

    test('is fully rough and not metallic, like the RealityKit ground', () {
      final f = cyclesFloorMesh(box(0), argb: 0xFF808080, lookingDown: true)!;
      expect(f.$4!.roughness, 1.0);
      expect(f.$4!.metallic, 0.0);
      // And it carries the palette's colour, converted like every other one.
      expect(f.$4!.r, closeTo(cyclesLinear(0x80), 1e-9));
    });

    test('is not drawn when the camera looks UP at it', () {
      // A Cycles triangle is double-sided; RealityKit's plane is not. Orbiting
      // under the model there shows the part through an undrawn floor, and
      // here it would fill the frame with floor colour instead — a flat tone
      // for a reason that has nothing to do with the model.
      expect(cyclesFloorMesh(box(0), argb: 0xFF808080, lookingDown: false),
          isNull);
      expect(cyclesFloorMesh(box(0), argb: 0xFF808080, lookingDown: true),
          isNotNull);
    });

    test('the world colour is the palette, converted, not a constant', () {
      // M336 — nobody was setting it, so every render used the shim's
      // fallback 0.8 grey whatever the scheme was: a bright rectangle in the
      // middle of a charcoal viewport. The same trap setViewportColor and
      // setFloorColor exist to avoid.
      final w = cyclesWorld(0xFF2A2E33);
      expect(w.length, 3);
      expect(w[0], closeTo(cyclesLinear(0x2A), 1e-9));
      expect(w[1], closeTo(cyclesLinear(0x2E), 1e-9));
      expect(w[2], closeTo(cyclesLinear(0x33), 1e-9));
      // Linear, not the sRGB bytes: a dark charcoal is far darker in linear.
      expect(w[0], lessThan(0x2A / 255));
    });

    test('an empty scene has nothing to stand on', () {
      expect(cyclesFloorMesh(const [], argb: 0xFF808080, lookingDown: true),
          isNull);
      expect(cyclesMeshLowY(const []), isNull);
    });
  });
}
