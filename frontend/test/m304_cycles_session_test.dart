// M304 — the render actually starts, at a sane size, of the right geometry.
//
// The three things that stood between M299's state machine and a picture on
// screen, each of which fails silently rather than loudly:
//
//   * the IMAGE SIZE. A path tracer costs pixels times samples, and the
//     viewport at native iPad resolution is 5.6 megapixels. Getting this wrong
//     does not throw; it renders for two minutes.
//   * an ASSEMBLY's placements. The solids are in their own part's
//     coordinates, and a render that ignores that draws every component
//     stacked on the origin — which on a symmetric assembly looks like one
//     component rather than like a bug.
//   * the COST of asking. `offer` is called from build, on every frame of
//     every drag, and building a job copies every vertex in the model. If it
//     builds one per frame the drag stutters and nothing says why.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_render.dart';
import 'package:prototype/cycles_session.dart';
import 'package:prototype/cycles_view.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart' show KernelSolid, Vec3;
import 'package:prototype/quat.dart';

void main() {
  group('the image size', () {
    test('a small viewport renders at its own device pixels', () {
      expect(cyclesImageSize(400, 300, 2.0), (800, 600));
    });

    test('a big one is capped on the long side and keeps its aspect', () {
      final (w, h) = cyclesImageSize(1366, 1024, 2.0);
      expect(w, kCyclesMaxSide);
      // 2732x2048 scaled by 900/2732.
      expect(h, 675);
      expect(w / h, closeTo(1366 / 1024, 0.01));
    });

    test('a portrait viewport is capped on ITS long side', () {
      final (w, h) = cyclesImageSize(1024, 1366, 2.0);
      expect(h, kCyclesMaxSide);
      expect(w, 675);
    });

    test('a degenerate size never asks for a zero-pixel image', () {
      // A render of 0x0 is not slow, it is a buffer nobody allocated.
      expect(cyclesImageSize(0, 0, 2.0), (1, 1));
      expect(cyclesImageSize(double.nan, 100, 2.0), (1, 1));
      expect(cyclesImageSize(1, 1, 0.4), (1, 1));
    });
  });

  group('a placed mesh', () {
    test('is moved into world coordinates', () {
      final m = cyclesMeshAt(_tri(), const Placement(Quat.identity, Vec3(5, 0, 0)));
      expect(m, isNotNull);
      final (v, _, _) = m!;
      expect(v[0], closeTo(5, 1e-6));
      expect(v[3], closeTo(15, 1e-6));
    });

    test('carries its normals rotated, not translated', () {
      // A quarter turn about X takes +Z to -Y... and whichever way the
      // convention runs, the point is that the normal is a UNIT vector that
      // did not pick up the translation.
      final rot = Quat.axisAngle(const Vec3(1, 0, 0), 1.5707963267948966);
      final m = cyclesMeshAt(_tri(), Placement(rot, const Vec3(100, 100, 100)));
      final (_, n, _) = m!;
      expect(n, isNotNull);
      final len = math.sqrt(n![0] * n[0] + n[1] * n[1] + n[2] * n[2]);
      expect(len, closeTo(1.0, 1e-5));
      expect(n[2].abs(), lessThan(1e-5), reason: '+Z should have turned away');
    });

    test('reverses winding when the placement is a reflection', () {
      // Cycles derives the geometric normal from the winding, and that decides
      // which side of a face a ray considers front. A mirrored component whose
      // winding was not reversed is inside-out, not merely mirrored.
      final plain = cyclesMeshAt(_tri(), Placement.identity)!;
      final flipped = cyclesMeshAt(
          _tri(), const Placement(Quat.identity, Vec3.zero, Vec3(1, 0, 0)))!;
      expect(plain.$3, [0, 1, 2]);
      expect(flipped.$3, [0, 2, 1]);
    });

    test('a solid with nothing in it produces no mesh at all', () {
      final empty = KernelSolid(
          OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
              Int32List.fromList([0]), Float64List(0)),
          1,
          null);
      expect(cyclesMeshAt(empty, null), isNull);
    });
  });

  group('the reach', () {
    test('is measured in world space, after placement', () {
      // The reason it is taken from the converted meshes: a 10 mm part a metre
      // from the assembly origin reaches a metre, and an eye placed for a
      // 10 mm reach would sit inside the rest of the assembly.
      final far = cyclesMeshAt(
          _tri(), const Placement(Quat.identity, Vec3(1000, 0, 0)))!;
      expect(cyclesMeshReach([far]), closeTo(1010, 1e-3));
    });
  });

  group('offering a scene', () {
    test('builds the job once, not once per frame', () {
      var built = 0;
      final s = CyclesSession(
          available: true, runner: (_) async => Uint8List(4));
      bool offer(String camera) => s.offer(
            wanted: true,
            scene: 'sig',
            camera: camera,
            width: 100,
            height: 80,
            buildJob: () {
              built++;
              return _job();
            },
          );

      expect(offer('cam-a'), isTrue);
      expect(built, 1);
      // The same scene, every frame of a viewport that is simply sitting there.
      for (var i = 0; i < 30; i++) {
        expect(offer('cam-a'), isFalse);
      }
      expect(built, 1, reason: 'a still viewport must not rebuild the scene');

      expect(offer('cam-b'), isTrue);
      expect(built, 2);
    });

    test('does nothing whatsoever without a renderer linked', () {
      var built = 0;
      final s = CyclesSession(available: false, runner: (_) async => null);
      final changed = s.offer(
        wanted: true,
        scene: 'sig',
        camera: 'cam',
        width: 100,
        height: 80,
        buildJob: () {
          built++;
          return _job();
        },
      );
      expect(changed, isFalse);
      expect(built, 0);
      expect(s.pump(), isNull);
      expect(s.render.image, isNull);
    });

    test('leaving rendered mode drops the queued job as well as the image',
        () {
      final s =
          CyclesSession(available: true, runner: (_) async => Uint8List(4));
      s.offer(
          wanted: true,
          scene: 'sig',
          camera: 'cam',
          width: 4,
          height: 4,
          buildJob: _job);
      expect(s.job, isNotNull);
      s.offer(
          wanted: false,
          scene: 'sig',
          camera: 'cam',
          width: 4,
          height: 4,
          buildJob: _job);
      expect(s.job, isNull);
      expect(s.render.phase, CyclesPhase.idle);
      expect(s.pump(), isNull);
    });

    test('a zero-size viewport is not a render request', () {
      final s =
          CyclesSession(available: true, runner: (_) async => Uint8List(4));
      expect(
          s.offer(
              wanted: true,
              scene: 'sig',
              camera: 'cam',
              width: 0,
              height: 0,
              buildJob: _job),
          isFalse);
      expect(s.render.phase, CyclesPhase.idle);
    });
  });

  group('pumping', () {
    test('runs the job and shows what comes back', () async {
      CyclesJob? ran;
      final s = CyclesSession(
        available: true,
        runner: (j) async {
          ran = j;
          return Uint8List.fromList(List.filled(4 * 4 * 4, 200));
        },
      );
      s.offer(
          wanted: true,
          scene: 'sig',
          camera: 'cam',
          width: 4,
          height: 4,
          buildJob: _job);
      await s.pump();
      expect(ran, isNotNull);
      expect(ran!.triangles, 1);
      expect(s.render.phase, CyclesPhase.shown);
      expect(s.render.image!.rgba.length, 4 * 4 * 4);
      expect(s.render.image!.samples, kCyclesSamples);
    });

    test('a renderer that returns nothing is a failure, not a blank picture',
        () async {
      final s = CyclesSession(available: true, runner: (_) async => null);
      s.offer(
          wanted: true,
          scene: 'sig',
          camera: 'cam',
          width: 4,
          height: 4,
          buildJob: _job);
      await s.pump();
      expect(s.render.phase, CyclesPhase.failed);
      expect(s.render.image, isNull);
    });

    test('nothing to pump when nothing was offered', () {
      final s = CyclesSession(available: true, runner: (_) async => null);
      expect(s.pump(), isNull);
    });
  });
}

CyclesJob _job() => CyclesJob(
      meshes: cyclesMeshes([_tri()]),
      matrix: List<double>.filled(12, 0),
      halfWidth: 10,
      halfHeight: 8,
      width: 4,
      height: 4,
      samples: kCyclesSamples,
    );

KernelSolid _tri() {
  return KernelSolid(
      OcctMeshData(
        Float64List.fromList([0, 0, 0, 10, 0, 0, 0, 10, 0]),
        Float64List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1]),
        Int32List.fromList([0, 1, 2]),
        Int32List.fromList([0]),
        Float64List(0),
        triFaces: Int32List.fromList([0]),
      ),
      1,
      null);
}
