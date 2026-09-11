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
import 'package:flutter/rendering.dart';

import '../app_state.dart';
import '../device_class.dart' show isPhoneDevice;
import '../l10n/l.dart';
import '../ribbon_dock.dart';
import '../theme.dart';
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

  /// M389 — Windows' stand-in caption strip, which takes a row of the STAGE
  /// rather than a row of the window.
  ///
  /// "The ribbon should on Windows go all the way up, not stop on the top
  /// bar." It stopped because main.dart put [WindowTitleBar] above this whole
  /// widget: a 32-point row across the full width, so the left-hand rail began
  /// 32 points down and the window had a bare strip over it that exists on no
  /// other platform. The iPad has no such row and the band starts at the top
  /// of the screen; this is what makes Windows do the same.
  ///
  /// It goes in with the STAGE, on the far side of the band, for every dock
  /// but [RibbonPosition.top]:
  ///
  ///   * the band gets the window's real top edge, which is the whole request;
  ///   * nothing else moves. The model browser, the quick tools and the
  ///     gallery are laid out UNDER this row exactly as they were under the
  ///     old one, so no panel gains a 32-point strip of window buttons over
  ///     its head and no hit test changes;
  ///   * the document, where it bleeds, runs edge to edge behind it — the
  ///     strip is transparent apart from its three buttons, so the model
  ///     reaches y=0 as it does on the iPad instead of stopping at a band of
  ///     ground colour.
  ///
  /// TOP DOCK IS THE ONE EXCEPTION and keeps the row above the band. A
  /// top-docked ribbon spans the full width, so there is no corner left for
  /// the window buttons that is not ribbon — putting the strip inside the
  /// stage would leave close and maximise stranded UNDER the ribbon, which
  /// is worse than the 32 points it saves.
  ///
  /// Null everywhere but Windows: see `windowChromeIsCustom`.
  final Widget? caption;

  const RibbonDockLayout({
    super.key,
    required this.app,
    required this.stage,
    this.bleed = const SizedBox.shrink(),
    this.caption,
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
    // No band drawn, so nothing of the document is covered. Published rather
    // than left stale: switching to the gallery must not leave the last
    // document's inset behind (which is precisely the shape of bug M290 lists
    // against M284 — "the gallery clearing a band that was not drawn").
    if (app.isHome) {
      RibbonBleed.publish(EdgeInsets.zero);
      return _withCaption(_layered());
    }
    // M350 — the band SWALLOWS pointers.
    //
    // Floating, its empty space sits over the viewport, and a Stack lets a hit
    // fall through whatever does not claim it: a tap on the ribbon's
    // background would otherwise orbit the model behind it. The glass itself
    // cannot take the hit (it is a platform view with interaction switched
    // off, deliberately — see GlassPanelView), so the swallow goes here.
    // M405 — the band retracts on a PHONE, and only there (#38).
    //
    // The handle is drawn only where the retract is offered, so on an iPad and
    // on every desktop this is exactly the layout it has always been: no
    // strip, no extra row, nothing to lay out differently. See RibbonRetract.
    final canRetract = isPhoneDevice();
    final retracted = canRetract && RibbonRetract.on;
    final Widget band = _Bleed(
      dock: RibbonDock.current,
      // Docked, the document is laid out inside the stage and covers nothing
      // (M290's layout, unchanged off iOS). Only a FLOATING band has an edge
      // to report.
      report: floats,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        // Retracted the band is GONE rather than merely thin: the whole point
        // is the space, and a hidden ribbon that still swallows pointers over
        // a fifth of the screen would be worse than the one that was visible.
        child: retracted ? const SizedBox.shrink() : Ribbon(app: app),
      ),
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
    // M389 — [caption] is a row of the STAGE, not of the window. `_staged`
    // wraps whatever goes beside the band; the band itself is never inside it,
    // which is exactly why it now reaches the top edge. Top dock is the
    // exception documented on [caption] and takes the old outer row.
    // The handle sits on the band's INNER edge, the side the ribbon slides
    // away from — the same place and the same chevron the model browser's
    // retract has used since M244, so it reads as the control it is.
    final Widget? grip =
        canRetract ? _RibbonGrip(dock: RibbonDock.current) : null;
    final Widget rows = switch (RibbonDock.current) {
      RibbonPosition.top => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [band, if (grip != null) grip, Expanded(child: _inner())]),
      RibbonPosition.bottom => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _staged(_inner())),
            if (grip != null) grip,
            band
          ]),
      RibbonPosition.left => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _rail(band, retracted),
            if (grip != null) grip,
            Expanded(child: _staged(_inner())),
          ]),
      RibbonPosition.right => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _staged(_inner())),
            if (grip != null) grip,
            _rail(band, retracted),
          ]),
    };
    if (RibbonDock.current == RibbonPosition.top) {
      return _withCaption(floats
          ? Stack(children: [Positioned.fill(child: bleed), rows])
          : rows);
    }
    if (!floats) return rows;
    // The document first, at full size, and the band's row over it. The stage
    // is inside [rows], so it still gets the box that excludes the band.
    return Stack(children: [Positioned.fill(child: bleed), rows]);
  }

  /// M360 — the rail, at whatever width its content needs.
  ///
  /// [RibbonRail] is a notifier because the width is DECIDED by the ribbon
  /// inside this box and read by the box itself: the rail measures whether its
  /// panels could stand in one column, and a one-column rail is 46 points
  /// against a two-column rail's 84. Listening here rather than rebuilding the
  /// world keeps that to the one widget whose size it changes.
  Widget _rail(Widget band, bool retracted) => ValueListenableBuilder<int>(
        valueListenable: RibbonRail.columns,
        builder: (_, __, child) => SizedBox(
            width: retracted ? 0 : RibbonMetrics.railWidth, child: child),
        child: band,
      );

  /// What goes in the row the band does NOT take: both layers when the band
  /// is docked, the floating chrome alone when it floats (the document is
  /// then behind everything, at full size).
  Widget _inner() => floats ? stage : _layered();

  /// The stage with Windows' caption strip above it — the band excluded, which
  /// is the point. A no-op off Windows, where [caption] is null.
  Widget _staged(Widget inner) => caption == null
      ? inner
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [caption!, Expanded(child: inner)],
        );

  /// The caption above EVERYTHING — the home gallery, which has no band at
  /// all, and top dock, where the band owns the full width.
  Widget _withCaption(Widget child) => caption == null
      ? child
      : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [caption!, Expanded(child: child)],
        );

  Widget _layered() => Stack(children: [
        Positioned.fill(child: bleed),
        Positioned.fill(child: stage),
      ]);
}

/// #49 — whether the retract grip paints its bar and chevron.
///
/// Pulled its own top-level function (rather than inlined in [_RibbonGrip]'s
/// build method) so the "no bar while retracted" rule is a fact the test
/// suite can pin directly: `_RibbonGrip` only exists on a phone-shaped iOS
/// display, which this suite's host is not and — per m405_ribbon_retract_test
/// — must never be faked into pretending to be.
@visibleForTesting
bool ribbonGripPaintsBar(bool retracted) => !retracted;

/// M405 — the retract handle, and the only way in or out of the retracted
/// state (#38).
///
/// A slim strip on the band's inner edge with a chevron on it, pointing the
/// way the band is about to move. Drawn only on a phone — the one place the
/// retract is offered — so on every other device this widget does not exist
/// and the layout is untouched.
///
/// Eighteen points is the strip, which is under half the width of one ribbon
/// icon and about a twentieth of what the band it hides was taking. It is
/// deliberately not smaller: it is the whole ribbon's front door, and a door
/// nobody can hit is a ribbon nobody can get back.
///
/// #49 — RETRACTED, the strip PAINTS NOTHING. Before, the coloured bar and
/// its chevron stayed on screen the whole time the ribbon was away, because
/// the strip is also the only hit target that can bring it back and hit
/// targets in this codebase are never invisible by habit. But retracted is
/// the state a phone spends most of its life in, and a permanent bar down
/// the screen's edge is exactly the "why is this here" chrome the retract
/// exists to remove — iOS's own edge-swipe affordances (the back gesture,
/// the app-switcher edge) draw nothing until touched. The strip keeps its
/// size and both gestures either way — [ribbonGripPaintsBar] is the one
/// thing that changes.
class _RibbonGrip extends StatelessWidget {
  final RibbonPosition dock;
  const _RibbonGrip({required this.dock});

  static const double extent = 18;

  /// Which way the chevron points: at the edge the band hides into while it is
  /// out, and back at the document while it is away.
  IconData _glyph(bool retracted) => switch (dock) {
        RibbonPosition.left =>
          retracted ? Icons.chevron_right : Icons.chevron_left,
        RibbonPosition.right =>
          retracted ? Icons.chevron_left : Icons.chevron_right,
        RibbonPosition.top =>
          retracted ? Icons.expand_more : Icons.expand_less,
        RibbonPosition.bottom =>
          retracted ? Icons.expand_less : Icons.expand_more,
      };

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final retracted = RibbonRetract.on;
    final bar = ribbonGripPaintsBar(retracted)
        ? DecoratedBox(
            decoration: BoxDecoration(color: T.hover6),
            child: Center(
              child: Icon(_glyph(retracted), size: 16, color: T.dim),
            ),
          )
        // Same footprint, nothing drawn: HitTestBehavior.opaque below hits by
        // geometry, not by paint, so the tap and the swipe both still land.
        : const SizedBox.expand();
    return Tooltip(
      message: retracted ? t.ribbonShow : t.ribbonHide,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: RibbonRetract.toggle,
        // A flick works too, in the direction the band would go, which is how
        // the browser's handle behaves and what a thumb does without being
        // told (M244).
        onHorizontalDragEnd: dock.isVertical
            ? (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() < 50) return;
                RibbonRetract.set(
                    dock == RibbonPosition.left ? v < 0 : v > 0);
              }
            : null,
        onVerticalDragEnd: dock.isHorizontal
            ? (d) {
                final v = d.primaryVelocity ?? 0;
                if (v.abs() < 50) return;
                RibbonRetract.set(
                    dock == RibbonPosition.top ? v < 0 : v > 0);
              }
            : null,
        child: dock.isVertical
            ? SizedBox(width: extent, child: bar)
            : SizedBox(height: extent, child: bar),
      ),
    );
  }
}

/// M357 — the band, reporting the edge of the document it covers.
///
/// A render object rather than a post-frame read off a GlobalKey, for one
/// reason: the size is known in [performLayout], so the report is made in the
/// layout that produced it rather than by looking the widget up again a frame
/// later and hoping it is still the same widget. The NOTIFICATION is still
/// deferred by one frame ([RibbonBleed.publish]) — a notifier fired mid-layout
/// would dirty a subtree that has already been laid out — but the measurement
/// is not guesswork and there is no second widget tree walk.
///
/// [report] false publishes zero: off iOS the band takes a row of the layout
/// and covers nothing, which is M290's arrangement and still the default.
class _Bleed extends SingleChildRenderObjectWidget {
  final RibbonPosition dock;
  final bool report;
  const _Bleed({required this.dock, required this.report, required Widget child})
      : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBleed(dock, report);

  @override
  void updateRenderObject(BuildContext context, _RenderBleed r) {
    r.dock = dock;
    r.report = report;
  }
}

class _RenderBleed extends RenderProxyBox {
  RibbonPosition _dock;
  bool _report;
  _RenderBleed(this._dock, this._report);

  set dock(RibbonPosition v) {
    if (v == _dock) return;
    _dock = v;
    markNeedsLayout();
  }

  set report(bool v) {
    if (v == _report) return;
    _report = v;
    markNeedsLayout();
  }

  @override
  void performLayout() {
    super.performLayout();
    if (!_report) {
      RibbonBleed.publish(EdgeInsets.zero);
      return;
    }
    RibbonBleed.publish(switch (_dock) {
      RibbonPosition.top => EdgeInsets.only(top: size.height),
      RibbonPosition.bottom => EdgeInsets.only(bottom: size.height),
      RibbonPosition.left => EdgeInsets.only(left: size.width),
      RibbonPosition.right => EdgeInsets.only(right: size.width),
    });
  }
}
