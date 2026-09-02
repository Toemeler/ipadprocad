// M290 — the ribbon band on its edge, and the whole rest of the app in what is
// left.
//
// This is the entire placement rule, and it is one switch because it is one
// idea rather than seven:
//
//   "On the right left and bottom you need to make sure its on the left side
//    of the Modell browser, on the right side of the toolbar and under the
//    bottom bar."
//
// The band is the OUTERMOST chrome, so it takes a real row (or column) of the
// content area and the stage gets the remainder. Everything the user listed —
// the model browser, the quick-tool rail, the tab bar, and the ViewCube, the
// triad, the modeless dialogs and the toasts besides — lives inside the stage,
// so each of them ends up on the inner side of the band without being told
// about it, and a panel added tomorrow cannot forget to be.
//
// M284 did it the other way round: the band floated over the stage, published
// its measured thickness into a notifier one frame after layout, and seven
// panels each subtracted the edge that concerned them. See the header of
// ribbon_chrome.dart for what that protocol cost, on a device, twice.
//
// ---------------------------------------------------------------------------
// M350 — AND THE DOCUMENT RUNS UNDER THE BAND, WITHOUT ANY OF THAT COMING BACK
// ---------------------------------------------------------------------------
//
// "Make the ribbon background fully liquid glass. Not solid background."
//
// A UIGlassEffect blurs what is BEHIND it. Since M290 the only thing behind
// the band was the app's ground colour, and blurred ground colour is ground
// colour — which is why the band read as a painted panel however good the
// material was. M346 changed that ground from the panel's tone to the
// viewport's, which was closer and still not glass, because the thing a
// viewport's tone is not is the MODEL.
//
// So the layer that goes under the band is the DOCUMENT, and only the
// document. The split is what makes this safe:
//
//   [bleed]  the viewport (2D canvas, 3D part, assembly, gallery). Edge to
//            edge, under the band. It is the thing the glass refracts.
//   [stage]  everything that floats over it — browser, tab bar, quick tools,
//            the modeless dialogues. Laid out in the box that EXCLUDES the
//            band, exactly as M290 left it.
//
// M284's protocol is what this is not: nothing measures the band, nothing
// publishes a thickness, nothing subtracts an inset, and no panel has to know
// the ribbon exists. The Column that gives the band its row is what gives the
// stage the remainder — one layout pass, no frame of lag, and a panel added
// tomorrow lands in the stage and is right by construction.
//
// WHY IT IS GATED ON THE GLASS. Without the native material the band is a
// painted surface (see [RibbonSurface]), and a painted surface with the model
// running under it would be an opaque strip over live geometry — worse than
// today, for no gain. So off iOS the layout is exactly what M290 built: the
// document is laid out INSIDE the stage's box and nothing runs under the band.
// `RibbonSurface.glassOverride` lets a test drive the other branch.
//
// Its own widget rather than a helper in main.dart for one reason: this is the
// claim of the milestone, and a private closure inside a 500-line build method
// cannot be asserted. m290_ribbon_dock_test.dart measures the boxes.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ribbon_dock.dart';
import 'ribbon.dart';
import 'ribbon_chrome.dart';

class RibbonDockLayout extends StatelessWidget {
  final AppState app;

  /// The document: the viewport, the gallery. Runs under the band where the
  /// band is glass.
  final Widget bleed;

  /// Everything that floats over the document: the model browser, the tab bar,
  /// the quick tools, the modeless dialogues.
  final Widget stage;

  const RibbonDockLayout({
    super.key,
    required this.app,
    required this.stage,
    this.bleed = const SizedBox.shrink(),
  });

  /// True when the band floats over the document rather than taking a row of
  /// the layout away from it.
  ///
  /// One question, one answer: [RibbonSurface.isGlass]. A test drives the
  /// other branch through `RibbonSurface.glassOverride`, so the band then
  /// paints what the device paints as well as laying out how the device lays
  /// out — and the difference between those two surfaces is a hit test.
  static bool get floats => RibbonSurface.isGlass;

  @override
  Widget build(BuildContext context) {
    // No band on the home gallery: the "+" in the gallery header is the only
    // new-document affordance there. Both layers come straight back, so the
    // question of clearing a band that is not drawn cannot arise — which is
    // exactly the question that had to be special-cased before.
    if (app.isHome) return _layered();
    // M350 — the band SWALLOWS pointers.
    //
    // Floating, its empty space sits over the viewport, and a Stack lets a hit
    // fall through whatever does not claim it: a tap on the ribbon's
    // background would otherwise orbit the model behind it. The glass itself
    // cannot take the hit (it is a platform view with interaction switched
    // off, deliberately — see GlassPanelView), so the swallow goes here.
    final band = Listener(
      behavior: HitTestBehavior.opaque,
      child: Ribbon(app: app),
    );
    // M346 — CrossAxisAlignment.stretch, and it is the whole of the "the
    // ribbon on the right does not go over the full height" report.
    //
    // A Row and a Column both CENTRE their children on the cross axis by
    // default, and the band sizes itself to its content: its scroll view
    // shrink-wraps (a viewport is `constraints.constrain(child.size)`), so a
    // rail whose panels come to 500 pt sat as a 500 pt slab in the middle of a
    // 1000 pt screen with the scaffold's ground above and below it. Stretch
    // makes the cross-axis constraint TIGHT, so the band fills its edge, the
    // glass covers it, and the scroll view is a scroll view rather than a
    // shrink-wrapped block.
    //
    // The two horizontal docks have the same latent bug on the width axis. It
    // never showed because a ribbon is nearly always wider than the screen —
    // which is exactly the kind of thing that surfaces the day someone opens a
    // document with three panels in it.
    final Widget rows = switch (RibbonDock.current) {
      RibbonPosition.top => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [band, Expanded(child: _inner())]),
      RibbonPosition.bottom => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [Expanded(child: _inner()), band]),
      RibbonPosition.left => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: RibbonMetrics.railWidth, child: band),
            Expanded(child: _inner()),
          ]),
      RibbonPosition.right => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _inner()),
            SizedBox(width: RibbonMetrics.railWidth, child: band),
          ]),
    };
    if (!floats) return rows;
    // The document first, at full size, and the band's row over it. The stage
    // is inside [rows], so it still gets the box that excludes the band.
    return Stack(children: [Positioned.fill(child: bleed), rows]);
  }

  /// What goes in the row the band does NOT take: both layers when the band
  /// is docked, the floating chrome alone when it floats (the document is
  /// then behind everything, at full size).
  Widget _inner() => floats ? stage : _layered();

  Widget _layered() => Stack(children: [
        Positioned.fill(child: bleed),
        Positioned.fill(child: stage),
      ]);
}
