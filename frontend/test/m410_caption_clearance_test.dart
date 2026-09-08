// M410 — #33: "the top right corner is somehow under the minimise close or
// maximise buttons on windows."
//
// The ViewCube and its Home button sit at the top right of the VIEWPORT, and
// the viewport is the layer that bleeds. M389 moved Windows' caption strip out
// of the outer Column and into the stage so the ribbon rail could reach the
// window's top edge — the report before this one — and from then on the
// document ran edge to edge underneath the strip. Everything in the STAGE (the
// model browser, the quick tools) was laid out below it and was fine. The cube
// is not in the stage. It kept the corner, and the corner now had three window
// buttons standing in it.
//
// So the document layer has to clear the strip where the strip is over it, and
// nowhere else. The two arrangements that put the caption ABOVE the document
// need no clearance and must not get any, or the cube drops 32 points into
// open space:
//
//   * TOP dock — the strip takes the outer row (a full-width ribbon would
//     otherwise strand close and maximise under itself);
//   * a DOCKED band — `_inner()` hands back the layered document, which is
//     inside the stage and therefore already below the strip.
//
// The rule is one getter, and this is every branch of it.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';
import 'package:prototype/widgets/window_titlebar.dart';

void main() {
  setUp(RibbonDock.resetForTest);
  tearDown(() {
    RibbonDock.resetForTest();
    debugWindowChromeIsCustom = null;
    RibbonSurface.glassOverride = null;
  });

  test('off Windows there is no strip and nothing to clear', () {
    debugWindowChromeIsCustom = false;
    RibbonSurface.glassOverride = true;
    for (final d in RibbonPosition.values) {
      RibbonDock.set(d);
      expect(windowCaptionOverlap, 0, reason: '$d');
    }
  });

  group('on Windows, with the band floating over the document', () {
    setUp(() {
      debugWindowChromeIsCustom = true;
      RibbonSurface.glassOverride = true;
    });

    test('THE REPORT: a side or bottom dock clears the strip', () {
      for (final d in [
        RibbonPosition.left,
        RibbonPosition.right,
        RibbonPosition.bottom,
      ]) {
        RibbonDock.set(d);
        expect(windowCaptionOverlap, WindowTitleBar.height,
            reason: '$d: the cube shared the corner with the window buttons');
      }
    });

    test('the top dock does not — the strip is above the document there', () {
      RibbonDock.set(RibbonPosition.top);
      expect(windowCaptionOverlap, 0);
    });
  });

  test('a DOCKED band puts the document below the strip already', () {
    // `_inner()` is `floats ? stage : _layered()`, and `_staged` wraps that in
    // the caption's Column — so the document is inside the stage and clearing
    // the strip a second time would push the cube into open space.
    debugWindowChromeIsCustom = true;
    RibbonSurface.glassOverride = false;
    for (final d in RibbonPosition.values) {
      RibbonDock.set(d);
      expect(windowCaptionOverlap, 0, reason: '$d');
    }
  });

  test('the clearance is the strip\'s own height, not a number beside it', () {
    // If the strip is ever retuned, the cube follows it. A literal 32 here
    // would be a second place to change and the first one to be forgotten.
    debugWindowChromeIsCustom = true;
    RibbonSurface.glassOverride = true;
    RibbonDock.set(RibbonPosition.left);
    expect(windowCaptionOverlap, WindowTitleBar.height);
  });
}
