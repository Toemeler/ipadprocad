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
// Its own widget rather than a helper in main.dart for one reason: this is the
// claim of the milestone, and a private closure inside a 500-line build method
// cannot be asserted. m290_ribbon_dock_test.dart measures the two boxes.
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../ribbon_dock.dart';
import 'ribbon.dart';
import 'ribbon_chrome.dart';

class RibbonDockLayout extends StatelessWidget {
  final AppState app;

  /// Everything that is not the ribbon: the viewport, the model browser, the
  /// tab bar, the quick tools and every floating panel over them.
  final Widget stage;

  const RibbonDockLayout({super.key, required this.app, required this.stage});

  @override
  Widget build(BuildContext context) {
    // No band on the home gallery: the "+" in the gallery header is the only
    // new-document affordance there. The stage comes straight back, so the
    // question of clearing a band that is not drawn cannot arise — which is
    // exactly the question that had to be special-cased before.
    if (app.isHome) return stage;
    final band = Ribbon(app: app);
    return switch (RibbonDock.current) {
      RibbonPosition.top => Column(children: [band, Expanded(child: stage)]),
      RibbonPosition.bottom => Column(children: [Expanded(child: stage), band]),
      RibbonPosition.left => Row(children: [
          SizedBox(width: RibbonMetrics.railWidth, child: band),
          Expanded(child: stage),
        ]),
      RibbonPosition.right => Row(children: [
          Expanded(child: stage),
          SizedBox(width: RibbonMetrics.railWidth, child: band),
        ]),
    };
  }
}
