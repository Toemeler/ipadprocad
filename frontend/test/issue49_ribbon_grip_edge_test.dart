// #49 — "if the ribbon is retracted on ios there shouldnt be this Vertical
// bar. and it should only come expand when I swipe right from the left edge
// with a clean native Apple style animation".
//
// The retract grip (M405, ribbon_dock_layout.dart) is an 18 pt strip on the
// band's inner edge that both TAPS and SWIPES (M244's convention, already
// wired through onHorizontalDragEnd/onVerticalDragEnd) can pull the ribbon
// back out with — that gesture already matched what the report asked for.
// What did not match: retracted, the strip stayed painted as a solid coloured
// bar with a chevron on it, for as long as the ribbon stayed away — which on
// a phone, where the ribbon retracts by default (M405/#38), is most of the
// app's life. `ribbonGripPaintsBar` is the one switch that decision runs
// through; before this fix it did not exist and the bar painted
// unconditionally.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/widgets/ribbon_dock_layout.dart';

void main() {
  test('retracted — the strip paints nothing', () {
    expect(ribbonGripPaintsBar(true), isFalse);
  });

  test('pulled out — the strip is still the visible handle to put it away',
      () {
    expect(ribbonGripPaintsBar(false), isTrue);
  });
}
