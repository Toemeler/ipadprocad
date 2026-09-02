// Prototype — the ribbon's SURFACE, and nothing else.
//
// The ribbon was an opaque `T.panel` strip with two flat blue borders, sitting
// in the main Column so the viewport began below it. It became a FLOATING
// Liquid Glass card (M146), built to the model browser's recipe: same
// `GlassPanel` platform view, same 18 pt continuous corners, same 28 pt side
// inset, and — the part that actually mattered on the device — the same DARK
// trait environment.
//
// M284 (surface A) de-floated it: no side inset, no corner radius, no shadow,
// one hairline seam on the edge that faces the viewport, dockable to any of
// the four edges. That won back the ~28 pt of panel width the two side insets
// were giving away.
//
// ---------------------------------------------------------------------------
// M290 — AND THE BAND IS NOW A ROW OF THE LAYOUT, NOT AN OVERLAY OVER IT.
// ---------------------------------------------------------------------------
//
// M284 kept the band as a `Positioned` inside the content Stack and taught
// every other floating panel to move out of its way: it measured its own
// thickness after layout, published it, and the model browser, the tab bar,
// the quick-tool rail, the ViewCube, the triad, the offset field and the
// modeless dialogs each subtracted the right edge of it. That is a protocol,
// and a protocol has a cost this file no longer pays:
//
//   * the thickness arrived ONE FRAME LATE (a post-frame callback), so every
//     dock change and every tab whose ribbon is a different height put the
//     chrome briefly in the wrong place;
//   * seven consumers each had to remember to subtract, and forgetting was
//     silent — bugfix #3 ("gallery chrome no longer clears an absent ribbon
//     band") and M284's own "inset the tab bar for side-docked bands" are both
//     that failure, found on a device;
//   * the published values outlived the band: on the gallery there IS no
//     ribbon, so the insets had to be special-cased against whether it was
//     drawn at all.
//
// Giving the band a real row (or column) of the layout deletes all three at
// once. The stage's box IS the content area minus the band, so nothing
// measures, nothing subtracts, nothing goes stale, and a consumer cannot
// forget. It is also exactly the placement rule that was asked for —
//
//   "On the right left and bottom you need to make sure its on the left side
//    of the Modell browser, on the right side of the toolbar and under the
//    bottom bar."
//
// — as one statement instead of seven: the band takes the outermost band of
// its edge, and everything else is laid out inside what is left. The browser
// is right of a left band, the quick tools are left of a right band and the
// tab bar rests above a bottom band because they are all children of a box
// that no longer includes it. See main.dart.
//
// Only the SURFACE is native. Icons, labels, buttons, flyouts and the scroll
// stay the Flutter tree they were, and the dock position itself is a value in
// ribbon_dock.dart rather than a widget concern.
import 'package:flutter/material.dart';
import 'package:native_menu/native_menu.dart';

import '../ribbon_dock.dart';
import '../theme.dart';

/// The band's own measurements.
///
/// M290 — what is NOT here any more is the inset protocol: [contentTop] and
/// its three siblings, the measured [RibbonMeasure] extent behind them, and
/// the `contentInsetsFor(ribbonDrawn)` special case. Nothing floats over the
/// band, so nothing has to be told where it ends.
class RibbonMetrics {
  RibbonMetrics._();

  /// Surface A: the band is FLUSH, so it keeps no inset from the edge and no
  /// corner radius. The old floating card used 14 pt of side inset and an
  /// 18 pt radius (and the tab bar still uses its own floating geometry).
  static const double side = 0;
  static const double radius = 0;

  /// Flush band: no padding between the band's outer edge and the screen. The
  /// floating card used [EdgeInsets.fromLTRB(14, 8, 14, 0)].
  static const EdgeInsets pad = EdgeInsets.zero;

  /// Width of the band when docked left or right (surface C's rail width).
  ///
  /// M349 — two widths, because the rail holds two different things. With
  /// names on it has to fit a small row's icon AND its German label without
  /// clipping (168, the measured value since M290). With names off the widest
  /// thing in it is a big button's flyout chip (46) beside a 34 pt glyph
  /// inside the panel's 20 pt of padding — 76 clears that with room, and the
  /// rail is less than half of what it was.
  static const double railWidthNamed = 168;
  /// 88: the constraint grid reflows to two 30 pt columns in a compact rail
  /// (see _ConGrid), and 61 + the panel's 20 pt of padding is what has to fit.
  static const double railWidthCompact = 88;

  static double get railWidth =>
      RibbonLabels.on ? railWidthNamed : railWidthCompact;

  /// Gap between the band and whatever floats beside it. Kept because the
  /// floating panels still space themselves off each other by it.
  static const double gap = 10;

  // ---- M351: ONE icon size, once the names are gone ----------------------
  //
  // With names on the band draws two sizes, and they mean something: 34 pt is
  // a Create button with a word under it, 18 pt is a row in a list of them.
  // With the words gone that distinction has nothing left to carry — what is
  // left is a grid of pictures, and a grid of pictures in two sizes reads as a
  // mistake ("when the names are hidden every icon should be the same size").
  //
  // 24 is the size that costs neither: the big buttons lose ten points of
  // height each (the band gets thinner again for it) and the small rows gain
  // six, which their 26 pt row already had room for.
  static const double bigIconNamed = 34;
  static const double smallIconNamed = 18;
  static const double compactIcon = 24;

  static double get bigIcon =>
      RibbonLabels.on ? bigIconNamed : compactIcon;

  static double get smallIcon =>
      RibbonLabels.on ? smallIconNamed : compactIcon;

  /// The box one compact icon sits in — the same for every control in the
  /// band, so a row of them lines up whatever they are.
  static const double compactButton = 32;
}

/// The ribbon's background surface: the same glass as the model browser, but
/// flush (square corners, no shadow).
class RibbonSurface extends StatelessWidget {
  const RibbonSurface({super.key});

  /// True when the native glass is available.
  ///
  /// M350 — it decides two things now: what the band is painted with, and
  /// whether the document runs UNDER it (see RibbonDockLayout). The two are
  /// one question — glass wants something to refract, paint must not cover
  /// live geometry — so they are answered in one place.
  static bool get isGlass => glassOverride ?? GlassPanel.isSupported;

  /// Tests only: pretend the native material is (or is not) there.
  ///
  /// Worth the seam. The painted fallback is a [ColoredBox], which SWALLOWS a
  /// hit; the real glass is a platform view with interaction switched off,
  /// which does not. A host test that only ever sees the fallback therefore
  /// proves nothing about the band's own background on the device — which is
  /// exactly the class of bug this repository keeps finding on the
  /// Flutter/UIKit boundary.
  @visibleForTesting
  static bool? glassOverride;

  @override
  Widget build(BuildContext context) {
    // No native material: a painted band is the honest fallback. Glass with
    // nothing to refract is a lie about the surface, not a cheaper version of
    // it, so the platforms without it get a panel and say so.
    if (!isGlass) return ColoredBox(color: T.panel);
    // M346/M350 — and the glass is GLASS, because there is finally something
    // behind it to refract: the DOCUMENT runs edge to edge under the band
    // (RibbonDockLayout), and the app's ground behind that is the viewport's
    // own tone rather than a slab of T.panel (main.dart). The seam is what
    // draws the band's edge; without it a band over the canvas would have no
    // boundary at all.
    return const GlassPanel(cornerRadius: RibbonMetrics.radius);
  }
}
