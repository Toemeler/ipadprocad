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
import 'package:flutter/scheduler.dart';
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
  /// 84: a compact rail is TWO [compactCell] columns and their [compactGap]
  /// (74) inside the 4 pt a side that [panelPad] gives a nameless panel (8),
  /// which is 82 — plus two points so a rounding error is not an overflow.
  /// Every panel in the rail wraps to those two columns (see `_wrap` in
  /// ribbon.dart), so this is the width of the whole band, not of its widest
  /// member, and it is still narrower than the 88 M351 needed for cells that
  /// were smaller than these.
  static const double railWidthCompact = 84;

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
  // M352 — 28, up from M351's 24: "I think the icons could be bigger."
  //
  // The size is bounded from above by the TOP band, whose height is the
  // constraint grid's two rows plus the panel's chrome: every point on the
  // glyph is two on the band, and at 28 the band is 94 pt against the named
  // band's 112. It is bounded from below by the fact that this is now the
  // ONLY thing a compact button shows — there is no word under it to carry
  // the meaning, so the drawing has to.
  static const double bigIconNamed = 34;
  static const double smallIconNamed = 18;
  static const double compactIcon = 28;

  static double get bigIcon =>
      RibbonLabels.on ? bigIconNamed : compactIcon;

  static double get smallIcon =>
      RibbonLabels.on ? smallIconNamed : compactIcon;

  /// M352 — the CELL. One square, for every control in a band that writes no
  /// names: a create button, a small row, a constraint, an appearance
  /// dropdown. On the device they were none of those sizes — a big button was
  /// as wide as its 46 pt flyout pill, a small row as wide as its glyph plus a
  /// chip, an appearance control 32 — so a rail of them lined up on nothing
  /// ("they are not aligned and are very weird").
  ///
  /// 36: a 28 pt glyph with four points of air on each side.
  ///
  /// The number is set by the HORIZONTAL band, not by the rail. On a top dock
  /// the tallest panel is the constraint grid, so the band is two of these
  /// plus their gap plus the panel's chrome — 94 pt at 36, against the named
  /// band's 112. The first cut of M352 reached 118 pt at this same size, and
  /// the cell was not what was wrong: three panels still stacked their small
  /// rows three deep instead of reflowing with the band (see `smallStack`).
  /// Fixing those, rather than shrinking the cell, is what bought the height
  /// back — which is worth remembering the next time this number looks like
  /// the one to tune.
  ///
  /// It is also what sets [railWidthCompact]: two cells and a gap is 74, and
  /// a compact panel's padding is 4 a side.
  static const double compactCell = 36;

  /// Between two cells, in both directions.
  static const double compactGap = 2;

  /// The box one compact icon sits in — the same for every control in the
  /// band, so a row of them lines up whatever they are.
  static const double compactButton = compactCell;

  /// The padding a panel puts around its content. Tighter with no names,
  /// because two cells and their gap have to fit [railWidthCompact].
  static EdgeInsets get panelPad => RibbonLabels.on
      ? const EdgeInsets.fromLTRB(10, 6, 10, 2)
      // 4 a side rather than 10: the cell draws its own air (a 28 pt glyph in
      // a 36 pt box), so the panel need not draw it again, and every point
      // saved here is a point off the rail's width.
      : const EdgeInsets.fromLTRB(4, 4, 4, 2);
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

/// M357 — how much of the DOCUMENT the floating band covers.
///
/// This is the one number M290 said would not come back, so it is worth being
/// precise about what it is and what it is not.
///
/// M290 made the band a ROW of the layout: the stage gets the remainder, so
/// every floating panel clears the band without being told, and nothing
/// measures anything. M350 then split the document out of the stage and ran it
/// edge to edge UNDER the glass — because a UIGlassEffect blurs what is behind
/// it, and what was behind it was the app's ground colour.
///
/// That split left one thing on the wrong side of the line. The coordinate
/// triad, the ViewCube and the message toast are drawn INSIDE the viewport, in
/// the document's coordinate space, and they are not the model: they float
/// over it exactly like the browser and the tab bar do. So they went under the
/// band with the geometry — "the triad is behind the ribbon now".
///
/// The right endgame is to hoist those three into the stage, where the box is
/// already correct and no number is needed. It is not this change: the
/// ViewCube's animation drives the viewport's own repaint (and on iOS the
/// RealityKit push that runs from its build), so moving it needs a repaint
/// channel through a path that cannot be exercised off the device. Publishing
/// the edge is the small, testable half of the fix.
///
/// WHY THIS IS NOT M284's PROTOCOL. M284 published a thickness that SEVEN
/// panels each subtracted, one frame after layout, and its failures were about
/// that arithmetic being spread out: a new panel that forgot to subtract, the
/// gallery clearing a band that was not drawn, chrome visibly misplaced after
/// every dock change. Here:
///
///   * there is ONE subscriber, the viewport's floating chrome, and it applies
///     the inset as a single [Padding] around all of it;
///   * a panel added tomorrow still goes in the stage and is still right by
///     construction — this value is not part of how panels are laid out;
///   * the value is zero unless the band actually FLOATS (no glass, or the
///     gallery, means the document is inside the stage already), so "clearing
///     a band that is not drawn" is not expressible;
///   * and the one frame of lag lands on a triad after a dock change or a
///     names toggle, not on the layout of the app.
class RibbonBleed {
  RibbonBleed._();

  /// The edge the band covers, as an inset into the document layer. Zero
  /// whenever the band is docked rather than floating.
  static final ValueNotifier<EdgeInsets> inset =
      ValueNotifier<EdgeInsets>(EdgeInsets.zero);

  /// Called from the layout once the band has been measured. Deferred, because
  /// it runs from layout and a notifier fired mid-layout would mark a subtree
  /// dirty that has already been laid out this frame — the same rule
  /// NativeModelBrowser.\_publishWidth follows.
  static void publish(EdgeInsets v) {
    if (inset.value == v) return;
    final b = WidgetsBinding.instance;
    if (b.schedulerPhase == SchedulerPhase.idle ||
        b.schedulerPhase == SchedulerPhase.postFrameCallbacks) {
      inset.value = v;
      return;
    }
    b.addPostFrameCallback((_) {
      if (inset.value != v) inset.value = v;
    });
  }

  @visibleForTesting
  static void resetForTest() => inset.value = EdgeInsets.zero;
}
