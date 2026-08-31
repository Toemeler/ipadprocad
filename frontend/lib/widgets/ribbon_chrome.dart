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
  /// Wide enough that a small row (icon + German label) does not clip its text.
  static const double railWidth = 168;

  /// Gap between the band and whatever floats beside it. Kept because the
  /// floating panels still space themselves off each other by it.
  static const double gap = 10;
}

/// The ribbon's background surface: the same glass as the model browser, but
/// flush (square corners, no shadow).
class RibbonSurface extends StatelessWidget {
  const RibbonSurface({super.key});

  /// True when the native glass is available.
  ///
  /// It no longer decides whether the ribbon floats — since M290 the band
  /// always takes a row of the layout — only what the band is painted with.
  /// Worth a look on the device: a docked band has the scaffold behind it
  /// rather than the model, and M146's own argument for the platform view was
  /// that glass with nothing behind it to refract reads as painted grey. If it
  /// does, this is one line.
  static bool get isGlass => GlassPanel.isSupported;

  @override
  Widget build(BuildContext context) {
    if (!isGlass) return ColoredBox(color: T.panel);
    return const GlassPanel(cornerRadius: RibbonMetrics.radius);
  }
}
