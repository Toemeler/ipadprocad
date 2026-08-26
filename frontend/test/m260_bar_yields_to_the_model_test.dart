// M260 — the bottom bar folds down while the model is under a finger.
//
// The request was to stop the bar being one liquid-glass slab, and the answer
// that came back from reading what iOS 26 actually shipped was that the
// material was never the problem: Apple's own tab bar became a floating
// capsule with a separate circular island beside it, and it MINIMISES while
// the view underneath it scrolls.
//
// A CAD viewport does not scroll. The gesture that means the same thing here
// is the one that covers the model: orbiting, panning or zooming it. This
// tests the latch that carries that signal, because the latch is the part
// with rules — the Swift side just draws whatever it is told.
//
// Two properties matter and they fail apart, so they are pinned apart:
//
//   * It is an EDGE. An orbit sends one of these per frame and the whole app
//     rebuilds on a notify. Sixty notifications a second while the camera is
//     already moving is the version of this feature that makes the app worse.
//   * It LINGERS. The gap between two orbit events of one drag is ~16 ms, and
//     a bar that unfolded in those gaps would strobe rather than yield.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';

void main() {
  final linger = AppState.engageLinger;
  tearDown(() => AppState.engageLinger = linger);

  group('M260 — the engagement latch', () {
    test('starts down: nothing is folded until something moves', () {
      expect(AppState().viewEngaged, isFalse);
    });

    test('one notify on the way up, however many moves arrive', () {
      final app = AppState();
      var notified = 0;
      app.addListener(() => notified++);

      app.engageView();
      expect(app.viewEngaged, isTrue);
      expect(notified, 1);

      // A one-second orbit at 60 fps. None of these may reach the tree.
      for (var i = 0; i < 60; i++) {
        app.engageView();
      }
      expect(app.viewEngaged, isTrue);
      expect(notified, 1,
          reason: 'the latch is an edge — an orbit that rebuilds the app once '
              'per frame costs more than the fold is worth');

      app.endViewEngagement();
    });

    test('one notify on the way down, and only when it was up', () {
      final app = AppState();
      app.engageView();
      var notified = 0;
      app.addListener(() => notified++);

      app.endViewEngagement();
      expect(app.viewEngaged, isFalse);
      expect(notified, 1);

      app.endViewEngagement();
      expect(notified, 1, reason: 'already down — nothing changed, so nothing '
          'may rebuild');
    });

    test('lingers, then drops on its own', () async {
      AppState.engageLinger = const Duration(milliseconds: 20);
      final app = AppState();
      app.engageView();
      expect(app.viewEngaged, isTrue);

      // Still up part-way through: this is the gap between two orbit events,
      // and a bar that unfolded here would strobe.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(app.viewEngaged, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(app.viewEngaged, isFalse,
          reason: 'the finger came off and nothing said so — the linger is '
              'the only thing that ends the fold');
    });

    test('a later move restarts the linger rather than shortening it',
        () async {
      AppState.engageLinger = const Duration(milliseconds: 30);
      final app = AppState();
      app.engageView();

      await Future<void>.delayed(const Duration(milliseconds: 20));
      app.engageView(); // still orbiting
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(app.viewEngaged, isTrue,
          reason: '40 ms in, but only 20 ms since the last move');

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(app.viewEngaged, isFalse);
    });

    test('dispose leaves no timer running', () {
      AppState.engageLinger = const Duration(seconds: 30);
      final app = AppState();
      app.engageView();
      app.dispose();
      // A pending timer here is a widget-test failure at the end of whatever
      // test happened to build a viewport, and a fold that fires against a
      // tree that is gone.
      expect(app.viewEngaged, isTrue,
          reason: 'dispose cancels the timer; it does not pretend the gesture '
              'ended');
    });
  });
}
