// M354 — while the camera moves, the viewport is RealityKit.
//
// THE REPORT, after three milestones of making a moving frame cheaper: "while
// orbiting it is still absolutely buggy slow and not good. Can you just show
// RealityKit while orbiting."
//
// The three attempts were each right on their own terms and none of them
// worked. M344 cut the pixels of a moving frame; M347 cut its samples too,
// because a tracer aiming at the settled target never finishes a frame of a
// moving camera and so never idles; M353 took out the a-trous filter, which
// cost 51 ms of CPU on every frame handed to the display. The orbit was still
// not smooth.
//
// The reason is upstream of all three, and it is not about how much work the
// tracer does. Flutter's compositor needs a slice of the GPU every eight
// milliseconds; a path tracer that is RUNNING is one it queues behind,
// however little it has been asked to do. Cheap is not the same as absent.
//
// So the tracer stops. What these tests pin down are the two ways stopping it
// can itself be expensive, because both would show up as a stutter rather
// than as a wrong picture — which is the hardest kind of bug to attribute:
//
//   * STOPPING MUST NOT COST THE GEOMETRY. Telling the session it is not
//     wanted closes the driver, and the next standstill would re-upload every
//     vertex and rebuild the BVH — once per gesture. The tracer is parked
//     instead: pushed a view it can finish at once, which cancels the render
//     in flight and leaves the scene where it is.
//
//   * PARKING MUST BE ONE PUSH PER GESTURE, not one per frame. Every push is
//     a Session::reset, which blocks until the render in flight has been
//     cancelled. Sixty of those a second is its own stall, so the parked
//     request has to be CONSTANT for the length of the drag — which is why it
//     names the camera the drag started from rather than the live one.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_live.dart';
import 'package:prototype/cycles_session.dart';
import 'package:prototype/cycles_view.dart';
import 'package:prototype/render_samples.dart';

class _Rec implements CyclesDriver {
  final List<int> viewSamples = [];
  final List<(int, int)> viewSizes = [];
  int scenes = 0;
  int closes = 0;

  @override
  set onFrame(void Function(CyclesLiveFrame) fn) {}
  @override
  set onNote(void Function(String, bool) fn) {}
  @override
  void open() {}

  // M355 — recorded rather than ignored: a pause that never reaches the
  // driver is indistinguishable from one that did, and the whole point of
  // it is that the GPU is actually given up.
  final List<bool> pauses = [];
  @override
  void setPaused(bool paused) => pauses.add(paused);
  @override
  void close() => closes++;

  @override
  void setScene(List<CyclesMesh> meshes, CyclesEnv env, int epoch) => scenes++;

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
}

CyclesScene _scene() =>
    const CyclesScene(meshes: [], env: CyclesEnv(), reach: 10);

CyclesViewParams _view(CyclesScene s) => CyclesViewParams(
      matrix: List<double>.filled(12, 0),
      halfWidth: 10,
      halfHeight: 8,
    );

void main() {
  late _Rec d;
  late CyclesSession s;

  setUp(() {
    d = _Rec();
    s = CyclesSession(available: true, driver: d);
  });

  // Exactly what the layer does, so the test exercises the policy rather than
  // a paraphrase of it: a standstill asks for the viewport's own pixels and
  // the settled target; a drag asks for one sample of a parked frame of the
  // camera the drag began from.
  bool still(String camera, int w, int h) => s.offer(
        wanted: true,
        scene: 'sig',
        camera: camera,
        width: w,
        height: h,
        buildScene: _scene,
        buildView: _view,
        samples: kCyclesSamples,
      );

  bool parked(String parkCamera) => s.offer(
        wanted: true,
        scene: 'sig',
        camera: parkCamera,
        width: kCyclesParkedSide,
        height: kCyclesParkedSide,
        buildScene: _scene,
        buildView: _view,
        samples: 1,
      );

  group('parking the tracer', () {
    test('a whole gesture is ONE push, however many frames it has', () {
      still('cam-a', 1794, 1548);
      expect(d.viewSamples.length, 1);

      // Sixty frames of a drag. The camera is moving on every one of them and
      // the parked request names the camera it started from, so it does not
      // change and the session has nothing to push.
      for (var i = 0; i < 60; i++) {
        parked('cam-a');
      }
      expect(d.viewSamples.length, 2,
          reason: 'one push to park, and then nothing for the whole drag');
      expect(d.viewSamples.last, 1);
      expect(d.viewSizes.last, (kCyclesParkedSide, kCyclesParkedSide));
    });

    test('parking never costs the geometry', () {
      // The whole reason it is a parked view and not `wanted: false`. Closing
      // the driver would drop the scene, and every gesture would end in a
      // re-upload of every vertex and a BVH rebuild.
      still('cam-a', 1794, 1548);
      for (var i = 0; i < 10; i++) {
        parked('cam-a');
      }
      still('cam-b', 1794, 1548);

      expect(d.scenes, 1, reason: 'one upload for the whole session');
      expect(d.closes, 0, reason: 'the session is never closed by a drag');
    });

    test('coming out of the park is a view push, not a rebuild', () {
      still('cam-a', 1794, 1548);
      parked('cam-a');
      still('cam-b', 1794, 1548);

      expect(d.scenes, 1);
      expect(d.viewSamples, [kCyclesSamples, 1, kCyclesSamples]);
      expect(d.viewSizes.last, (1794, 1548));
    });

    test('the parked frame is small enough to be free', () {
      // It exists to be finished, not to be looked at: pushing it is what
      // cancels the render in flight, and the tracer has to get through it in
      // microseconds or the cancel has just bought a different stall.
      expect(kCyclesParkedSide * kCyclesParkedSide, lessThan(10000));
      // And a real settled frame is orders of magnitude bigger, so the two can
      // never be confused for one another by a size check.
      final (w, h) = cyclesImageSize(897, 774, 2.0);
      expect(kCyclesParkedSide * kCyclesParkedSide * 100, lessThan(w * h));
    });
  });

  group('what the standstill asks for', () {
    test('the viewport 1:1 and the full sample ceiling', () {
      still('cam-a', 1794, 1548);
      expect(d.viewSizes.single, (1794, 1548));
      expect(d.viewSamples.single, kCyclesSamples);
      // M367 — 128, and it is a DEFAULT rather than the constant it used to
      // be: the ceiling is a setting now ([RenderSamples]) and the finished
      // frame is denoised, so the samples only have to get the image close
      // enough for the denoiser rather than bury the noise on their own. The
      // 4096 this replaced was Blender's final-render default and is still
      // the top of the ladder for anyone who wants it.
      expect(kCyclesSamples, 128);
      expect(kCyclesSamples, kRenderSamplesDefault);
    });

    test('a repeated standstill pushes nothing', () {
      // `offer` runs from build, on every frame. An idle rendered viewport
      // must not be re-pushing a view it is already rendering.
      still('cam-a', 1794, 1548);
      still('cam-a', 1794, 1548);
      still('cam-a', 1794, 1548);
      expect(d.viewSamples.length, 1);
    });
  });

  group('the ways parking can latch', () {
    // Both of these are states a viewport is not allowed to have: the mode is
    // on, the surface is up, and nothing will ever render. Neither is reachable
    // from the session alone — they live in the layer's flag — so what is
    // pinned here is the arithmetic the layer depends on, and the layer's own
    // comment carries the rest.

    test('a parked request and a settled one are never the same key', () {
      // If they collided, coming out of a park would push nothing and the
      // tracer would sit on the thumbnail forever.
      final (w, h) = cyclesImageSize(897, 774, 2.0);
      expect((kCyclesParkedSide, kCyclesParkedSide) == (w, h), isFalse);
      expect(1 == kCyclesSamples, isFalse);
    });

    test('a park followed by the SAME camera still re-renders it', () {
      // Letting go without having moved anywhere — a tap that registered as a
      // drag, or a gesture that returned to where it started. The size and the
      // sample target changed even though the camera did not, so the key
      // changed, so the standstill is pushed. Without that this would be the
      // commonest way to end up looking at a surface that never renders.
      still('cam-a', 1794, 1548);
      parked('cam-a');
      still('cam-a', 1794, 1548);
      expect(d.viewSamples, [kCyclesSamples, 1, kCyclesSamples]);
      expect(d.viewSizes.last, (1794, 1548));
    });
  });

  group('a resize is a move', () {
    test('every frame of a rotation does not push a full-resolution view', () {
      // Rotating the iPad changes the viewport size on every frame of the
      // animation, and a settled render follows the viewport 1:1. Pushing each
      // one would reallocate Cycles' buffers for a couple of megapixels sixty
      // times a second while the compositor is animating. The layer arms the
      // settle on a size change for exactly this reason; here is what that
      // saves.
      still('cam-a', 1794, 1548);
      final before = d.viewSizes.length;
      // The animation, parked throughout: one push, then nothing.
      for (var i = 0; i < 40; i++) {
        parked('cam-a');
      }
      expect(d.viewSizes.length, before + 1);
      // And one full-resolution push when it lands on its final size.
      still('cam-a', 1548, 1794);
      expect(d.viewSizes.last, (1548, 1794));
      expect(d.viewSizes.length, before + 2);
    });
  });

  group('the frame that is shown', () {
    test('a parked frame is not a picture of where the camera is now', () {
      // The layer will not draw it, and this is the fact it relies on: the
      // image carries the key it was accepted under, so a frame from the park
      // is stamped with the camera the drag began from and can be told apart
      // from a frame of the camera the user has stopped at.
      still('cam-a', 1794, 1548);
      parked('cam-a');
      still('cam-b', 1794, 1548);
      expect(s.render.wanted?.camera, 'cam-b');
      // Nothing has landed for cam-b yet, so there is no image of it — which
      // is why RealityKit keeps the viewport until one arrives rather than the
      // pre-drag texture going back up at the wrong angle.
      expect(s.render.image, isNull);
    });
  });
}
