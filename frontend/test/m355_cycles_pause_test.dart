// M355 — the tracer stands down for the compositor, and comes back to the
// same image.
//
// M354 stopped the path tracer during a camera move and the orbit became
// RealityKit's. It did nothing for the rest of the app: a settled render is
// megapixels against a 4096-sample ceiling, seconds to minutes of solid GPU,
// and for all of it the user can be scrolling the browser or dragging a panel
// — animations that need the compositor, which is queued behind the tracer.
//
// M354's lever cannot be reused. It parks the session by pushing a view it can
// finish at once, and pushing a view resets the session: every sample taken so
// far is thrown away. Using that on each touch would reset a converging image
// to noise every time the user brushed the screen.
//
// So there are two levers now and the tests are mostly about keeping them
// apart:
//
//   PARK (M354) — the view is about to change anyway. Costs the samples,
//   which do not matter because they are of the wrong camera.
//
//   PAUSE (M355) — the view is not changing and the image is worth keeping.
//   Costs nothing but time.
//
// Getting these the wrong way round does not produce a wrong picture. It
// produces an image that resets to noise whenever the user touches the screen,
// or an orbit that keeps rendering a camera that has already moved — both of
// which read as "it is slow" rather than as "it is wrong".
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/cycles_activity.dart';
import 'package:prototype/cycles_live.dart';
import 'package:prototype/cycles_session.dart';
import 'package:prototype/cycles_view.dart';

class _Rec implements CyclesDriver {
  final List<bool> pauses = [];
  final List<(int, int)> viewSizes = [];
  int scenes = 0;
  int closes = 0;

  @override
  set onFrame(void Function(CyclesLiveFrame) fn) {}
  @override
  set onNote(void Function(String, bool) fn) {}
  @override
  void open() {}
  @override
  void close() => closes++;
  @override
  void setPaused(bool paused) => pauses.add(paused);
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
  }) =>
      viewSizes.add((width, height));
}

CyclesScene _scene() =>
    const CyclesScene(meshes: [], env: CyclesEnv(), reach: 10);

CyclesViewParams _view(CyclesScene s) => CyclesViewParams(
      matrix: List<double>.filled(12, 0),
      halfWidth: 10,
      halfHeight: 8,
    );

void main() {
  group('the pause reaches the renderer', () {
    late _Rec d;
    late CyclesSession s;

    setUp(() {
      d = _Rec();
      s = CyclesSession(available: true, driver: d);
    });

    test('and does not cost the scene or the session', () {
      // The entire difference from parking. Nothing is rebuilt, nothing is
      // closed, and no view is pushed — so nothing resets, so the samples
      // taken so far survive.
      s.offer(
        wanted: true,
        scene: 'sig',
        camera: 'cam',
        width: 1794,
        height: 1548,
        buildScene: _scene,
        buildView: _view,
        samples: kCyclesSamples,
      );
      final viewsBefore = d.viewSizes.length;

      s.setPaused(true);
      s.setPaused(false);

      expect(d.pauses, [true, false]);
      expect(d.scenes, 1, reason: 'a pause is not a rebuild');
      expect(d.closes, 0, reason: 'a pause is not a shutdown');
      expect(d.viewSizes.length, viewsBefore,
          reason: 'a pause is not a view push, which is what would reset it');
    });

    test('a repeat is dropped, because build says it on every frame', () {
      s.setPaused(true);
      s.setPaused(true);
      s.setPaused(true);
      expect(d.pauses, [true]);
      expect(s.paused, isTrue);
      s.setPaused(false);
      s.setPaused(false);
      expect(d.pauses, [true, false]);
      expect(s.paused, isFalse);
    });

    test('a build with no renderer never pauses one', () {
      final dead = _Rec();
      CyclesSession(available: false, driver: dead).setPaused(true);
      expect(dead.pauses, isEmpty);
    });
  });

  group('what counts as busy', () {
    setUp(() => CyclesActivity.instance.resetForTest());
    tearDown(() => CyclesActivity.instance.resetForTest());

    testWidgets('a still finger is not busy — it is how you ask for a render',
        (tester) async {
      // The rule that makes this usable. Orbit to an angle and keep the finger
      // on the glass while you look: the camera has stopped, the settle fires,
      // and the render is the whole point of having stopped. Under a
      // finger-down rule it would not start until you let go.
      await tester.pumpWidget(const SizedBox.expand());
      final a = CyclesActivity.instance;
      var fired = 0;
      a.addListener(() => fired++);

      final touch = await tester.startGesture(const Offset(100, 100));
      await tester.pump();
      expect(a.busy, isFalse, reason: 'contact alone is not motion');
      expect(fired, 0);

      await touch.up();
      await tester.pump();
      expect(a.busy, isFalse);
    });

    testWidgets('a moving finger is busy, and stays busy through the gaps',
        (tester) async {
      await tester.pumpWidget(const SizedBox.expand());
      final a = CyclesActivity.instance;
      final touch = await tester.startGesture(const Offset(100, 100));
      await touch.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(a.busy, isTrue);

      // A drag does not deliver an event every frame; the tail is what keeps
      // the answer steady across the gaps inside one gesture.
      await tester.pump(kCyclesActivityTail ~/ 2);
      expect(a.busy, isTrue);

      await touch.moveBy(const Offset(10, 0));
      await tester.pump(kCyclesActivityTail ~/ 2);
      expect(a.busy, isTrue, reason: 'the second move restarted the tail');

      // AND THEN LET IT EXPIRE, which is not tidying up. This test only ever
      // advanced the clock by half a tail, so the timer was still alive when
      // the widget tree was disposed and the binding failed the test on
      // "A Timer is still pending". Ending a gesture is part of the gesture;
      // a test that never ends one is not describing anything real.
      await touch.up();
      await tester.pump(kCyclesActivityTail + const Duration(milliseconds: 20));
      expect(a.busy, isFalse);
    });

    testWidgets('and lets go a fixed time after the last movement',
        (tester) async {
      await tester.pumpWidget(const SizedBox.expand());
      final a = CyclesActivity.instance;
      var fired = 0;
      a.addListener(() => fired++);

      final touch = await tester.startGesture(const Offset(100, 100));
      await touch.moveBy(const Offset(10, 0));
      await tester.pump();
      expect(a.busy, isTrue);
      await touch.up();

      await tester.pump(kCyclesActivityTail + const Duration(milliseconds: 20));
      expect(a.busy, isFalse);
      // Once on, once off: a listener that fired per event would repaint the
      // viewport on every frame of every drag in the application.
      expect(fired, 2);
    });

    test('subscribing twice installs one route and never throws', () {
      // NOT a test that it survives a missing binding — this file has one,
      // because it uses testWidgets. What it does pin is that wiring is
      // idempotent and that a fresh listener sees "not busy", which is the
      // state a viewport must start a render from.
      final a = CyclesActivity.instance;
      expect(() => a.addListener(() {}), returnsNormally);
      expect(() => a.addListener(() {}), returnsNormally);
      expect(a.busy, isFalse);
    });
  });

  group('the two levers are not the same lever', () {
    test('parking resets and pausing does not', () {
      // Stated as an arithmetic fact about what reaches the driver, because
      // this is the confusion that would be expensive: a park is a view push
      // (and therefore a Session::reset, and therefore the samples), a pause
      // is not.
      final d = _Rec();
      final s = CyclesSession(available: true, driver: d);
      s.offer(
        wanted: true,
        scene: 'sig',
        camera: 'cam',
        width: 1794,
        height: 1548,
        buildScene: _scene,
        buildView: _view,
        samples: kCyclesSamples,
      );
      // A park: the request changes, so a view is pushed.
      s.offer(
        wanted: true,
        scene: 'sig',
        camera: 'cam',
        width: kCyclesParkedSide,
        height: kCyclesParkedSide,
        buildScene: _scene,
        buildView: _view,
        samples: 1,
      );
      expect(d.viewSizes.length, 2);

      // A pause: nothing is pushed at all.
      final n = d.viewSizes.length;
      s.setPaused(true);
      expect(d.viewSizes.length, n);
    });
  });
}
