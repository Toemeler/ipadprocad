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
//
// M419 — AND THEY ASK ABOUT THE RIGHT BOX. "the extrude dialog spawns behind
// stuff and in front of other stuff and part of it is out of the screen. it
// should spawn a bit more on the left and up so that it is directly fully
// cleared" (#42).
//
// Every one of these dialogs measured `MediaQuery.sizeOf(context)` — the
// WINDOW — and was then laid out by RibbonDockLayout in the STAGE, which is
// the window minus the ribbon band and, on Windows, minus the caption row as
// well. The parking spot was therefore computed in one coordinate space and
// used in a smaller one: centred against a height it did not have it hung off
// the bottom, and docked against a width it did not have it slid under the
// quick-tool bar. All three halves of that report are the same arithmetic —
// too far down, too far right, and so partly underneath things.
//
// [DialogDockScope] carries the box the dialogs are ACTUALLY laid out in,
// published once by the stage. Asking through [DialogDock.viewport] rather
// than at each call site is the discipline the rest of this file exists for:
// twelve dialogs answering the same question twelve ways is how they drifted
// apart the first time.
import 'package:flutter/widgets.dart';

import 'quick_tools.dart';

/// The box the floating dialogs are laid out in, published by the stage.
class DialogDockScope extends InheritedWidget {
  final Size size;
  const DialogDockScope({required this.size, required super.child, super.key});

  @override
  bool updateShouldNotify(DialogDockScope old) => old.size != size;
}

class DialogDock {
  DialogDock._();

  /// The box a floating dialog should park itself in.
  ///
  /// The stage's box where one is published, and the window otherwise — a
  /// dialog pumped on its own in a test still gets a sane answer rather than
  /// a zero.
  static Size viewport(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DialogDockScope>()?.size ??
      MediaQuery.sizeOf(context);

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

  /// Top edge, for a dialog that hangs from the top.
  ///
  /// M290 — just [gap]. It used to add the ribbon's measured thickness,
  /// because the band floated over this coordinate space; the band takes a row
  /// of the layout now, so the top of this box already IS the top of the
  /// content area.
  static double top() => gap;

  /// Top edge for a TALL dialog: vertically centred in what is left below the
  /// ribbon, and never pushed off the top by its own height.
  static double middle(Size viewport, double height) {
    final t = top();
    final free = viewport.height - t - gap;
    return t + ((free - height) / 2).clamp(0.0, double.infinity);
  }

  /// M419 — [middle], but never leaving a dialog hanging off the bottom of a
  /// box it would otherwise fit in.
  ///
  /// Centring is right and is not sufficient: a panel a few points taller than
  /// the free space is pushed to the top by [middle]'s clamp and still
  /// overflows, and the report this is named for is exactly that shape. Where
  /// even the top edge is not enough — a window too short for the panel at all
  /// — the top wins, because a dialog whose title bar is off screen cannot be
  /// dragged back.
  static double topFor(Size viewport, double height) {
    final t = top();
    final lowest = viewport.height - gap - height;
    final centred = middle(viewport, height);
    if (centred <= lowest) return centred;
    return lowest < t ? t : lowest;
  }

  /// The whole parking offset in one call.
  static Offset spot(Size viewport, Size dialog) =>
      Offset(left(viewport, dialog.width), topFor(viewport, dialog.height));
}
