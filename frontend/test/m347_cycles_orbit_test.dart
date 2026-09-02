// M347 — the two things a path-traced viewport has to stop doing.
//
// The report this milestone came from was one screenshot and two sentences:
// the orbit is "insanely laggy and stuttery" with Cycles on, and the picture
// "always looks like shit, it won't get better than this". The badge in that
// screenshot said "Cycles · 256 spp · Apple M4 GPU" over an image whose
// background — a flat colour and a diffuse floor, which cannot be noisy at any
// real sample count — measured about a quarter of its own value in noise. Two
// separate failures wearing the same face:
//
//   THE VIEWPORT LATCHED. A frame stamped with the wrong view generation
//   carried a `finished` flag from the render before it, the worker stopped
//   polling on it, and the mode ended there — a mid-orbit frame on screen and
//   a badge reporting the target sample count for an image that never reached
//   it. That half is in the shim (restart(), and the sample count it reports)
//   and in the worker's poll, and it cannot be reached from a host test; what
//   IS testable here is the policy that made it survivable, and the shape of
//   the key that decides what gets pushed at all.
//
//   THE ORBIT HAD ONLY HALF A BUDGET. Fewer pixels while moving, and the same
//   256-sample target as a standstill. A tracer aiming at 256 never finishes a
//   frame of a moving camera and so never idles, the GPU stays pinned for the
//   whole gesture, and Flutter's compositor queues behind it for the slice it
//   needs every eight milliseconds. That is what these tests are mostly about:
//   both halves of the budget move together, and a change to either one
//   reaches the renderer.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/cycles_live.dart';
import 'package:prototype/cycles_render.dart';
import 'package:prototype/cycles_session.dart';
import 'package:prototype/cycles_view.dart';
import 'package:prototype/part_model.dart' show PartCamera;
import 'package:prototype/part_render.dart' show Cam3;
import 'package:prototype/widgets/cycles_layer.dart';

/// A driver that records what it was asked for. The session above it needs no
/// renderer, no isolate and no GPU to be wrong in the ways this file checks.
class _Rec implements CyclesDriver {
  final List<int> viewSamples = [];
  final List<(int, int)> viewSizes = [];
  int scenes = 0;

  void Function(CyclesLiveFrame)? _frame;

  @override
  set onFrame(void Function(CyclesLiveFrame) fn) => _frame = fn;
  @override
  set onNote(void Function(String, bool) fn) {}

  @override
  void open() {}
  @override
  void close() {}

  @override
  void setScene(List<CyclesMesh> meshes, CyclesEnv env, int epoch) {
    scenes++;
    _epoch = epoch;
  }

  int _epoch = 0;

  @override
  void setView({
    required List<double> matrix,
    required double halfWidth,
    required double halfHeight,
    required int width,
    required int height,
    required int samples,
  }) {
    viewSamples.add(samples);
    viewSizes.add((width, height));
  }

  void land({required int samples, required int target, bool done = false}) =>
      _frame?.call(CyclesLiveFrame(
        rgba: Uint8List(4 * 4 * 4),
        width: 4,
        height: 4,
        samples: samples,
        target: target,
        done: done,
        denoised: false,
        epoch: _epoch,
      ));
}

CyclesScene _scene() =>
    const CyclesScene(meshes: [], env: CyclesEnv(), reach: 10);

CyclesViewParams _view(CyclesScene s) => CyclesViewParams(
      matrix: List<double>.filled(12, 0),
      halfWidth: 10,
      halfHeight: 8,
    );

void main() {
  group('the frame budget', () {
    test('a moving camera cuts BOTH the pixels and the samples', () {
      // The one assertion this milestone exists for. Either half alone leaves
      // the GPU saturated for the whole gesture: all the pixels at few samples
      // is a slow frame, few pixels at all the samples is a frame that never
      // finishes and therefore never lets go of the device.
      final still = cyclesFrameBudget(900, 780, 2.0, moving: false);
      final moving = cyclesFrameBudget(900, 780, 2.0, moving: true);

      expect(moving.width, lessThan(still.width));
      expect(moving.samples, lessThan(still.samples));
      expect(still.samples, kCyclesSamples);
      expect(moving.samples, kCyclesMovingSamples);
    });

    test('the moving frame is a small fraction of the settled one', () {
      final still = cyclesFrameBudget(900, 780, 2.0, moving: false);
      final moving = cyclesFrameBudget(900, 780, 2.0, moving: true);
      // Pixels times samples is what a path tracer actually costs. An orbit
      // frame that is within a factor of a few of a settled one is not a
      // budget, it is a rounding error.
      final stillCost = still.width * still.height * still.samples;
      final movingCost = moving.width * moving.height * moving.samples;
      expect(movingCost * 20, lessThan(stillCost));
    });

    test('the moving target stays inside the denoiser full-strength band', () {
      // cycles_denoise.h fades the a-trous filter out from kDenoiseFull (32)
      // samples upwards. An orbit target above that would be filtered at
      // partial strength — the noisiest frames getting the least help, which
      // is the arrangement M346 shipped by tying the strength to the target
      // rather than to the sample count.
      expect(kCyclesMovingSamples, lessThanOrEqualTo(32));
      expect(kCyclesMovingSamples, greaterThan(1));
    });

    test('a settled render is most of an iPad Pro viewport, not half of it', () {
      // 900 on the long side put a half-resolution image under a viewport that
      // is about 1800 device pixels across, and no sample count sharpens that.
      final b = cyclesFrameBudget(897, 774, 2.0, moving: false);
      expect(b.width / (897 * 2.0), greaterThan(0.75));
    });
  });

  group('the render key', () {
    test('carries the sample target, so a change of target is a push', () {
      // The two always travel together today — the settle changes the size and
      // the target on the same frame — so leaving samples out of the key would
      // work by accident until somebody varied one without the other.
      const a = CyclesKey('s', 'c', 480, 400, kCyclesMovingSamples);
      const b = CyclesKey('s', 'c', 480, 400, kCyclesSamples);
      expect(a == b, isFalse);
      expect(a == const CyclesKey('s', 'c', 480, 400, kCyclesMovingSamples),
          isTrue);
      // And a target change is still the SAME model, so the picture on screen
      // survives it rather than blinking out.
      expect(a.sameScene(b), isTrue);
    });

    test('a target change alone re-pushes the view and not the scene', () {
      final r = CyclesRender();
      expect(r.request(const CyclesKey('s', 'c', 480, 400, 24)).$1,
          CyclesPush.scene);
      expect(r.request(const CyclesKey('s', 'c', 480, 400, 256)).$1,
          CyclesPush.view);
    });
  });

  group('the session', () {
    test('pushes the target it was offered, not its own', () {
      final d = _Rec();
      final s = CyclesSession(available: true, driver: d);
      bool offer(String camera, int samples) => s.offer(
            wanted: true,
            scene: 'sig',
            camera: camera,
            width: 480,
            height: 400,
            buildScene: _scene,
            buildView: _view,
            samples: samples,
          );

      offer('cam-a', kCyclesMovingSamples);
      offer('cam-b', kCyclesMovingSamples);
      offer('cam-b', kCyclesSamples);

      expect(d.scenes, 1, reason: 'a camera or a target is never a rebuild');
      expect(d.viewSamples,
          [kCyclesMovingSamples, kCyclesMovingSamples, kCyclesSamples]);
      expect(s.target, kCyclesSamples);
    });

    test('falls back to its own target when the caller has no opinion', () {
      final d = _Rec();
      final s = CyclesSession(available: true, driver: d, samples: 64);
      s.offer(
        wanted: true,
        scene: 'sig',
        camera: 'cam',
        width: 100,
        height: 80,
        buildScene: _scene,
        buildView: _view,
      );
      expect(d.viewSamples, [64]);
    });

    test('reports the sample count a frame actually has', () {
      // The shim used to substitute the TARGET for the count whenever a frame
      // came back finished, which is how "256 spp" ended up under an image
      // that had a dozen — and it removed the one number that could have said
      // the render had stopped early. The session must not reintroduce it.
      final d = _Rec();
      final s = CyclesSession(available: true, driver: d);
      s.offer(
        wanted: true,
        scene: 'sig',
        camera: 'cam',
        width: 4,
        height: 4,
        buildScene: _scene,
        buildView: _view,
      );
      d.land(samples: 12, target: kCyclesSamples, done: true);
      expect(s.render.image!.samples, 12);
      expect(s.render.image!.done, isTrue);
      expect(s.render.phase, CyclesPhase.shown);
    });
  });

  group('covering the RealityKit surface', () {
    // The pause exists so the surface below stops rendering full-resolution
    // frames nobody sees while a path-traced image is over it. Its one
    // dangerous failure is the reverse: a surface left paused with nothing
    // over it is a blank viewport, so the layer has to say "not covering"
    // through every path it can leave by — including the one it takes on every
    // host test and on every build with no renderer linked, which returns
    // before it has looked at anything.
    testWidgets('a layer with no renderer reports that it covers nothing',
        (tester) async {
      final seen = <bool>[];
      await tester.pumpWidget(MaterialApp(
        home: CyclesLayer(
          app: AppState(),
          cam: Cam3(PartCamera(), const Size(800, 600)),
          size: const Size(800, 600),
          onCover: seen.add,
        ),
      ));
      expect(seen, isNotEmpty, reason: 'silence leaves the surface as it was');
      expect(seen.every((v) => v == false), isTrue);
    });

    testWidgets('and says so again on the way out', (tester) async {
      final seen = <bool>[];
      Widget layer() => MaterialApp(
            home: CyclesLayer(
              app: AppState(),
              cam: Cam3(PartCamera(), const Size(800, 600)),
              size: const Size(800, 600),
              onCover: seen.add,
            ),
          );
      await tester.pumpWidget(layer());
      seen.clear();
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(seen, [false],
          reason: 'a widget that goes away must not leave the surface paused');
    });
  });

  group('the idle poll', () {
    test('a finished render slows down rather than stopping', () {
      // A viewport must not have a state it cannot leave. The fast cadence is
      // a display refresh; the idle one has to be slow enough to cost nothing
      // and fast enough that a frame arriving after a `done` is seen rather
      // than lost for good.
      expect(kCyclesIdlePoll, greaterThan(kCyclesPoll));
      expect(kCyclesIdlePoll.inMilliseconds, lessThanOrEqualTo(500));
    });
  });
}
