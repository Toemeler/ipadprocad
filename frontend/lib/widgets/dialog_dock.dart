// M206 — where a floating dialog parks, in ONE place.
//
// TWO REPORTS, ONE MISSING RULE
// -----------------------------
// "The gear dialog should spawn at the right like the extrude panel and all
// other dialogs. Now it spawns under the Modell browser."
//
// "Also other Dialogs spawn under the fast toolbar on the right but they
// should spawn a bit more to the left right next to the toolbar."
//
// Between them those two describe the whole rule, and the app had it written
// down nowhere: every dialog picked its own corner. The Pattern and Fillet
// windows were already inset past the quick-tool bar (M192) because that bug
// was found once and fixed once, at those two call sites. The Extrude and Edge
// panels used a bare `width - w - 18` and therefore ran underneath the bar.
// The Gear, Parameters, Freehand and Text windows opened at a hard-coded
// `Offset(60, 60)` — top left, which is exactly where the model browser is.
//
// So: the right-hand edge of the CONTENT area is the parking spot. Not the
// right edge of the screen — the quick-tool bar owns that, and a dialog that
// starts underneath it hides its own buttons behind a bar the screenshot
// cannot even show (the bar is a platform view; on the Flutter side that
// corner looks empty, which is why this survived four milestones).
//
// Every window that floats over the viewport asks here now. They stay
// DRAGGABLE — this decides only where they open.
import 'package:flutter/widgets.dart';

import 'quick_tools.dart';
import 'ribbon_chrome.dart';

class DialogDock {
  DialogDock._();

  /// Breathing room between a docked dialog and whatever chrome is beside it.
  static const double gap = 12;

  /// Space on the right that belongs to something else: the quick-tool bar and
  /// its own margin.
  static double get rightChrome => QuickToolsBar.occupiedWidth;

  /// Left edge for a dialog [width] wide, parked against the right-hand edge
  /// of the content area — beside the quick-tool bar, never under it.
  static double left(Size viewport, double width) =>
      (viewport.width - width - gap - rightChrome)
          .clamp(gap, (viewport.width - gap).clamp(gap, double.infinity));

  /// Top edge just under the ribbon, for a dialog that hangs from the top.
  static double top() => gap + RibbonMetrics.contentTop;

  /// Top edge for a TALL dialog: vertically centred in what is left below the
  /// ribbon, and never pushed off the top by its own height.
  static double middle(Size viewport, double height) {
    final t = top();
    final free = viewport.height - t - gap;
    return t + ((free - height) / 2).clamp(0.0, double.infinity);
  }

  /// The whole parking offset in one call.
  static Offset spot(Size viewport, Size dialog) =>
      Offset(left(viewport, dialog.width), middle(viewport, dialog.height));
}
