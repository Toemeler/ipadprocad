// M304 — the render actually starts, at a sane size, of the right geometry.
//
// The four things that stand between a state machine and a picture on screen,
// each of which fails silently rather than loudly:
//
//   * the IMAGE SIZE. A path tracer costs pixels times samples, and the
//     viewport at native iPad resolution is 5.6 megapixels. Getting this wrong
//     does not throw; it renders for two minutes.
//   * an ASSEMBLY's placements. The solids are in their own part's
//     coordinates, and a render that ignores that draws every component
//     stacked on the origin — which on a symmetric assembly looks like one
//     component rather than like a bug.
//   * the COST of asking. `offer` is called from build, on every frame of
//     every drag, and building a scene copies every vertex in the model. If it
//     builds one per frame the drag stutters and nothing says why.
//   * and since M344, WHICH OF THE TWO PUSHES a change earns. A camera move
//     that re-uploads the geometry renders exactly the right picture and
//     spends a whole frame budget doing it, which is the hardest kind of
//     regression to notice.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_live.dart';
import 'package:prototype/cycles_render.dart';
import 'package:prototype/cycles_session.dart';
import 'package:prototype/cycles_view.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart' show KernelSolid, Vec3;
import 'package:prototype/quat.dart';

/// A renderer the test drives by hand: it records what it was told and hands
/// back frames on demand.
class _FakeDriver implements CyclesDriver {
  int scenes = 0;
  int views = 0;
  int opens = 0;
  int closes = 0;
  List<CyclesMesh>? lastMeshes;
  CyclesEnv? lastEnv;
  int? lastWidth;
  int? lastHeight;
  int? lastSamples;
  List<double>? lastMatrix;

  void Function(CyclesLiveFrame)? _frame;
  void Function(String, bool)? _note;

  @override
  set onFrame(void Function(CyclesLiveFrame) fn) => _frame = fn;
  @override
  set onNote(void Function(String, bool) fn) => _note = fn;

  @override
  void open() => opens++;

  @override
  void close() => closes++;

  int lastEpoch = 0;

  @override
  void setScene(List<CyclesMesh> meshes, CyclesEnv env, int epoch) {
    scenes++;
    lastMeshes = meshes;
    lastEnv = env;
    lastEpoch = epoch;
  }

  @override
  void setView({
    required List<double> matrix,
    required double halfWidth,
    required double halfHeight,
    required int width,
    required int height,
    required int samples,
  }) {
    views++;
    lastMatrix = matrix;
    lastWidth = width;
    lastHeight = height;
    lastSamples = samples;
  }

  /// Deliver a frame as the render isolate would, stamped with whichever
  /// scene it was last given unless the caller names an older one.
  void land(
          {int samples = 8,
          bool done = false,
          int w = 4,
          int h = 4,
          int? epoch}) =>
      _frame?.call(CyclesLiveFrame(
        rgba: Uint8List(w * h * 4),
        width: w,
        height: h,
        samples: samples,
        target: kCyclesSamples,
        done: done,
        denoised: !done,
        epoch: epoch ?? lastEpoch,
      ));

  void say(String text, {bool failed = false}) => _note?.call(text, failed);
}

CyclesScene _scene() => CyclesScene(
      meshes: cyclesMeshes([_tri()]),
      env: const CyclesEnv(),
      reach: 10,
    );

CyclesViewParams _view(CyclesScene s) => CyclesViewParams(
      matrix: List<double>.filled(12, 0),
      halfWidth: 10,
      halfHeight: 8,
    );

void main() {
  group('the image size', () {
    test('a small viewport renders at its own device pixels', () {
      expect(cyclesImageSize(400, 300, 2.0), (800, 600));
    });

    test('a big one renders 1:1 too — M353 removed the cap', () {
      // The cap existed to bound denoiser memory. There is no denoiser, so a
      // settled frame is exactly the pixels it will be drawn into and nothing
      // is resampled on the way to the screen.
      expect(cyclesImageSize(1366, 1024, 2.0), (2732, 2048));
    });

    test('a portrait viewport is 1:1 as well', () {
      expect(cyclesImageSize(1024, 1366, 2.0), (2048, 2732));
    });

    test('the guard is above anything a real viewport asks for', () {
      // kCyclesMaxSide is an allocation guard, not a quality knob: it must not
      // bind on the largest iPad, and it must still stop a nonsense size.
      expect(cyclesImageSize(1366, 1024, 2.0).$1, lessThan(kCyclesMaxSide));
      expect(cyclesImageSize(9000, 9000, 3.0).$1, kCyclesMaxSide);
    });

    // M347 — the cap is what decides how sharp a settled render can ever be,
    // and 900 made an iPad Pro viewport a half-resolution image at every sample
    // count. Nailed down so a future "let's make it cheaper" has to argue with
    // the pixel it is giving away.
    test('a settled render covers an iPad Pro viewport EXACTLY 1:1', () {
      // The part viewport with the ribbon docked at the left, in points.
      // M347 got this to four fifths of the viewport; M353 gets the last
      // fifth, which is the difference between a soft image at every sample
      // count and a sharp one.
      final (w, h) = cyclesImageSize(897, 774, 2.0);
      expect(w, (897 * 2.0).round());
      expect(h, (774 * 2.0).round());
    });

    test('an orbit still renders small — that half did not change', () {
      final (mw, _) = cyclesImageSize(897, 774, 2.0, moving: true);
      expect(mw, kCyclesMovingSide);
      // And the gap between the two is now the whole point: a moving frame is
      // a fraction of a settled one, where before it was under a third.
      final (sw, sh) = cyclesImageSize(897, 774, 2.0);
      final (_, mh) = cyclesImageSize(897, 774, 2.0, moving: true);
      expect(mw * mh * 8, lessThan(sw * sh));
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
      final (v, _, _, _) = m!;
      expect(v[0], closeTo(5, 1e-6));
      expect(v[3], closeTo(15, 1e-6));
    });

    test('carries its normals rotated, not translated', () {
      // A quarter turn about X takes +Z to -Y... and whichever way the
      // convention runs, the point is that the normal is a UNIT vector that
      // did not pick up the translation.
      final rot = Quat.axisAngle(const Vec3(1, 0, 0), 1.5707963267948966);
      final m = cyclesMeshAt(_tri(), Placement(rot, const Vec3(100, 100, 100)));
      final (_, n, _, _) = m!;
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
    test('builds the scene once, not once per frame', () {
      var built = 0;
      final d = _FakeDriver();
      final s = CyclesSession(available: true, driver: d);
      bool offer(String camera) => s.offer(
            wanted: true,
            scene: 'sig',
            camera: camera,
            width: 100,
            height: 80,
            buildScene: () {
              built++;
              return _scene();
            },
            buildView: _view,
          );

      expect(offer('cam-a'), isTrue);
      expect(built, 1);
      expect(d.scenes, 1);
      expect(d.views, 1, reason: 'a scene with no camera renders nothing');

      // The same scene, every frame of a viewport that is simply sitting there.
      for (var i = 0; i < 30; i++) {
        expect(offer('cam-a'), isFalse);
      }
      expect(built, 1, reason: 'a still viewport must not rebuild the scene');
      expect(d.views, 1, reason: 'nor re-push a camera that has not moved');
    });

    test('an ORBIT pushes views and never rebuilds the scene', () {
      // The whole performance argument of M344, as one assertion. Thirty
      // camera positions is half a second of dragging.
      var built = 0;
      final d = _FakeDriver();
      final s = CyclesSession(available: true, driver: d);
      for (var i = 0; i < 30; i++) {
        s.offer(
          wanted: true,
          scene: 'sig',
          camera: 'cam-$i',
          width: 100,
          height: 80,
          buildScene: () {
            built++;
            return _scene();
          },
          buildView: _view,
        );
      }
      expect(built, 1, reason: 'the model did not change');
      expect(d.scenes, 1);
      expect(d.views, 30);
    });

    test('a model change rebuilds the scene and re-aims the camera', () {
      var built = 0;
      final d = _FakeDriver();
      final s = CyclesSession(available: true, driver: d);
      void offer(String scene) => s.offer(
            wanted: true,
            scene: scene,
            camera: 'cam',
            width: 100,
            height: 80,
            buildScene: () {
              built++;
              return _scene();
            },
            buildView: _view,
          );
      offer('sig-a');
      offer('sig-b');
      expect(built, 2);
      expect(d.scenes, 2);
      expect(d.views, 2, reason: 'a new scene needs a camera with it');
    });

    test('the view carries the size and the sample target', () {
      final d = _FakeDriver();
      final s = CyclesSession(available: true, driver: d, samples: 64);
      s.offer(
          wanted: true,
          scene: 'sig',
          camera: 'cam',
          width: 640,
          height: 400,
          buildScene: _scene,
          buildView: _view);
      expect(d.lastWidth, 640);
      expect(d.lastHeight, 400);
      expect(d.lastSamples, 64);
    });

    test('does nothing whatsoever without a renderer linked', () {
      var built = 0;
      final d = _FakeDriver();
      final s = CyclesSession(available: false, driver: d);
      final changed = s.offer(
        wanted: true,
        scene: 'sig',
        camera: 'cam',
        width: 100,
        height: 80,
        buildScene: () {
          built++;
          return _scene();
        },
        buildView: _view,
      );
      expect(changed, isFalse);
      expect(built, 0);
      expect(d.scenes, 0);
      expect(d.views, 0);
      expect(s.render.image, isNull);
    });

    test('leaving rendered mode shuts the renderer down', () {
      final d = _FakeDriver();
      final s = CyclesSession(available: true, driver: d);
      s.offer(
          wanted: true,
          scene: 'sig',
          camera: 'cam',
          width: 4,
          height: 4,
          buildScene: _scene,
          buildView: _view);
      expect(s.scene, isNotNull);
      s.offer(
          wanted: false,
          scene: 'sig',
          camera: 'cam',
          width: 4,
          height: 4,
          buildScene: _scene,
          buildView: _view);
      expect(s.scene, isNull);
      expect(s.render.phase, CyclesPhase.idle);
      expect(d.closes, 1);
      // And not once per frame afterwards: `offer` runs from build.
      for (var i = 0; i < 10; i++) {
        s.offer(
            wanted: false,
            scene: 'sig',
            camera: 'cam',
            width: 4,
            height: 4,
            buildScene: _scene,
            buildView: _view);
      }
      expect(d.closes, 1);
    });

    test('a zero-size viewport is not a render request', () {
      final d = _FakeDriver();
      final s = CyclesSession(available: true, driver: d);
      expect(
          s.offer(
              wanted: true,
              scene: 'sig',
              camera: 'cam',
              width: 0,
              height: 0,
              buildScene: _scene,
              buildView: _view),
          isFalse);
      expect(s.render.phase, CyclesPhase.idle);
      expect(d.scenes, 0);
    });
  });

  group('frames coming back', () {
    test('each one is shown and the viewport is told', () {
      var repaints = 0;
      final d = _FakeDriver();
      final s = CyclesSession(available: true, driver: d)
        ..addListener(() => repaints++);
      s.offer(
          wanted: true,
          scene: 'sig',
          camera: 'cam',
          width: 4,
          height: 4,
          buildScene: _scene,
          buildView: _view);

      d.land(samples: 4);
      expect(repaints, 1);
      expect(s.render.image!.samples, 4);
      expect(s.render.phase, CyclesPhase.rendering);

      d.land(samples: 64);
      expect(repaints, 2);
      expect(s.render.image!.samples, 64);

      d.land(samples: kCyclesSamples, done: true);
      expect(s.render.phase, CyclesPhase.shown);
    });

    test('a frame of the PREVIOUS model is dropped, not shown as this one', () {
      // The window is one turn of the worker's event loop: a poll that was
      // already queued when the scene message arrived answers with the old
      // picture, and the UI has by then adopted the new key. A frame of the
      // previous CAMERA is what a frame is and is shown; a frame of the
      // previous MODEL is the wrong answer at any frame rate.
      final d = _FakeDriver();
      final s = CyclesSession(available: true, driver: d);
      void offer(String scene) => s.offer(
            wanted: true,
            scene: scene,
            camera: 'cam',
            width: 4,
            height: 4,
            buildScene: _scene,
            buildView: _view,
          );
      offer('sig-a');
      final stale = d.lastEpoch;
      d.land(samples: 8);
      expect(s.render.image, isNotNull);

      offer('sig-b');
      expect(s.render.image, isNull, reason: 'the model changed');
      d.land(samples: 8, epoch: stale);
      expect(s.render.image, isNull,
          reason: 'a frame of sig-a must not come back as sig-b');

      d.land(samples: 8);
      expect(s.render.image, isNotNull);
    });

    test('what the renderer said about itself is kept', () {
      final d = _FakeDriver();
      final s = CyclesSession(available: true, driver: d);
      s.offer(
          wanted: true,
          scene: 's',
          camera: 'c',
          width: 4,
          height: 4,
          buildScene: _scene,
          buildView: _view);
      d.say('Apple M4 (GPU)');
      expect(s.note, 'Apple M4 (GPU)');
      expect(s.render.phase, CyclesPhase.rendering,
          reason: 'naming the device is not a failure');

      d.say('no Metal device', failed: true);
      expect(s.note, 'no Metal device');
      expect(s.render.phase, CyclesPhase.failed);
      expect(s.render.error, 'no Metal device');
    });
  });
}

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
