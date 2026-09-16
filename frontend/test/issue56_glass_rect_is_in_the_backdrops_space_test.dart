// #56 — "i get this really weird white artifacts on the modell browser", and
// then, on the build that fixed the white: "this looks just false and it is".
//
// TWO FAULTS, ONE CAUSE. The white slabs were the rim's own runaway — the glow
// is exp(-edge / falloff) and `edge` goes positive outside the rect, so 38 px
// out on a 4 px falloff is exp(9.5) — and 7b4e4d5 bounded the material to its
// rectangle, which removed the white. What it could not remove is WHY a
// fragment was 38 px outside a rectangle the panel is clipped to.
//
// Measured off three bundles, two window sizes and two card heights:
//
//   the panel's own dark contour     x=97 and x=348   -> the card, 250 wide
//   the selected row's teal border   x=98 and x=347   -> the card, again
//   the material's right rim         x=309            -> 212 wide
//
// A COMPLETE rim at 309, not a cut-off one. A clip cuts a rim; it does not
// draw one. So the shader was not clipped short — it was TOLD the panel ended
// there, and it believed the same wrong thing on both windows, by the same
// constant 38 px, while every measurement on the Dart side said the rect it
// was handed was the card's to the pixel.
//
// Both are true, and that is the whole of it: `uRect` is right, and it is
// right about the WRONG SPACE. It is measured through `localToGlobal`, so it
// is in the WINDOW's device pixels; `FlutterFragCoord()` is in the BACKDROP's.
// Those agree only while the backdrop is the window, and nothing promises
// that — this material is always under a clip, because GlassPanel clips it to
// the panel, and a clipped backdrop filter may be handed a texture covering
// the clipped region alone.
//
// `uSize` is what settles it, and the shader already had it: the engine writes
// the backdrop's size into the first uniform. A backdrop no larger than the
// panel in BOTH axes cannot be the window.
//
// This file is that rule, in the numbers the device produced. The shader
// itself cannot run here — the host has no Impeller, which is the same reason
// the glass branch went unmeasured for so long — so what is pinned is the
// arithmetic, mirrored from the five lines at the top of the shader's main().
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/liquid_glass.dart' show glassRectInBackdrop;

/// The reporter's window, from env.txt: 1376x1032 logical at 1x.
const Size kWindow = Size(1376, 1032);

/// The model browser's card in that window, from the pixels: x 98..348,
/// y 12..1020 (`cardInsetV` top and bottom).
final Rect kCard = Rect.fromLTRB(98, 12, 348, 1020);

void main() {
  group('THE REPORT: the panel measured in the space it is drawn in', () {
    test('a backdrop clipped to the panel puts the panel at the origin', () {
      // What the shader was doing: evaluating a rect that starts at 98 against
      // fragments that start at 0. 250 - 38 is 212, which is where the rim
      // came out.
      final r = glassRectInBackdrop(kCard, kCard.size);
      expect(r.left, 0);
      expect(r.top, 0);
      expect(r.width, kCard.width);
      expect(r.height, kCard.height);
    });

    test('and the rim then lands on the card, not 38 pt inside it', () {
      // The number from the bundle, stated as the property it is: the right
      // edge the shader measures is the card's own width, whatever the card's
      // position on screen.
      final r = glassRectInBackdrop(kCard, kCard.size);
      expect(r.right - r.left, 250);
      expect(r.right - r.left - (kCard.width - 38), 38,
          reason: '38 = cardInsetLeft (14) + the retract strip (24), which is '
              'what the material was short by in every bundle');
    });
  });

  group('and every surface that renders correctly is left alone', () {
    // The band, both tab-bar pills and the quick tools were correct on every
    // edge in the SAME frames the browser was wrong in. Whatever this rule
    // does, it must not reach them.
    test('a full-window backdrop is the window, so nothing moves', () {
      final r = glassRectInBackdrop(kCard, kWindow);
      expect(r, kCard);
    });

    test('the ribbon band: full width, short, over the whole window', () {
      // Full width means the width test passes on its own. The height is what
      // says the backdrop is still the window.
      final band = Rect.fromLTRB(0, 0, 1376, 46);
      expect(glassRectInBackdrop(band, kWindow), band);
    });

    test('a tab-bar pill, small and far from the origin', () {
      final pill = Rect.fromLTRB(59, 980, 111, 1020);
      expect(glassRectInBackdrop(pill, kWindow), pill);
    });
  });

  group('the edges of the rule itself', () {
    test('a panel that IS the window is unchanged either way', () {
      // Both branches agree here, which is what makes the rule safe: a
      // full-screen surface already starts at the origin.
      final full = Offset.zero & kWindow;
      expect(glassRectInBackdrop(full, kWindow), full);
    });

    test('one pixel of slack, because a device ratio rounds', () {
      // The backdrop is sized in whole device pixels and the rect is not, so
      // the two can differ by a fraction on the same box. A strict `<=` would
      // make the rule fire or not fire on a rounding.
      final r = glassRectInBackdrop(kCard, Size(kCard.width + 1, kCard.height + 1));
      expect(r.left, 0, reason: 'still the panel, one pixel of rounding aside');
    });

    test('a backdrop wider but not taller is not the panel', () {
      // Only both axes together can mean "this is the panel's own texture".
      final r = glassRectInBackdrop(kCard, Size(kWindow.width, kCard.height));
      expect(r, kCard);
    });
  });
}
