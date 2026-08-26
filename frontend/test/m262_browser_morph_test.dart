// M262 — the model browser morphs between its retracted and open shapes.
//
// The animation was taken away in M204, and for a reason that has not gone
// anywhere: the card is a UiKitView. Resizing one is not a layout change on
// the Dart side — RenderUiKitView hands the new size to the platform-view
// controller and AWAITS the native resize, and the widget goes on reporting
// the old geometry until that returns. Animating the width fires that round
// trip once per frame of the curve, so a dozen resizes are in flight at once
// and the last one to LAND wins whether or not it was the last one sent.
// Flutter keeps painting the view's texture at the widget's size, so a stale
// native frame is invisible: you see icons where the touch interceptor no
// longer is, and the taps go nowhere.
//
//     "when its retracted i cant use the icons"
//
// M262 puts the animation back on the other side of that boundary — UIKit
// animates its own contents, which costs no round trip — and keeps M204's
// guarantee intact by holding the CARD at its wide size for the length of the
// morph, whichever way it is going. One resize per toggle, and it lands on a
// still panel with nothing in flight.
//
// That guarantee is arithmetic, so it is pinned here rather than left to a
// comment. The animation itself is Swift's and cannot be tested from the host;
// this is the invariant that makes the animation safe to have.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/widgets/native_browser_host.dart';

void main() {
  const wide = NativeModelBrowser.occupiedWidth; // 264 + 24
  const narrow = 56.0 + 24;

  group('M262 — what the card occupies', () {
    test('settled, it is the state it is in', () {
      expect(
          NativeModelBrowser.occupancy(collapsed: false, morphing: false), wide);
      expect(NativeModelBrowser.occupancy(collapsed: true, morphing: false),
          narrow);
    });

    test('closing, it stays WIDE until the morph has played', () {
      expect(NativeModelBrowser.occupancy(collapsed: true, morphing: true), wide,
          reason: 'the panel draws itself down to the glyph column first; the '
              'bounds follow once nothing is moving. Shrinking them up front '
              'is the resize landing mid-animation, which is M204');
    });

    test('opening, it is wide from the first frame', () {
      expect(
          NativeModelBrowser.occupancy(collapsed: false, morphing: true), wide,
          reason: 'the content has to have somewhere to grow into');
    });

    test('THE INVARIANT: never narrow while anything is moving', () {
      for (final collapsed in [true, false]) {
        expect(
            NativeModelBrowser.occupancy(collapsed: collapsed, morphing: true),
            wide,
            reason: 'a resize while the panel is animating is a resize that '
                'races the platform view, whichever direction it is going');
      }
    });

    test('exactly one width change per toggle', () {
      // A collapse, frame by frame: the toggle, the morph, the settle. The
      // width may change ONCE across the three, and it is the last step.
      final closing = [
        NativeModelBrowser.occupancy(collapsed: false, morphing: false), // before
        NativeModelBrowser.occupancy(collapsed: true, morphing: true), // toggle
        NativeModelBrowser.occupancy(collapsed: true, morphing: false), // settle
      ];
      expect(closing, [wide, wide, narrow]);

      final opening = [
        NativeModelBrowser.occupancy(collapsed: true, morphing: false),
        NativeModelBrowser.occupancy(collapsed: false, morphing: true),
        NativeModelBrowser.occupancy(collapsed: false, morphing: false),
      ];
      expect(opening, [narrow, wide, wide]);

      for (final steps in [closing, opening]) {
        final changes =
            [for (var i = 1; i < steps.length; i++) steps[i] != steps[i - 1]]
                .where((c) => c)
                .length;
        expect(changes, 1,
            reason: 'two resizes in one toggle is two round trips racing each '
                'other, which is the whole of M204');
      }
    });
  });
}
