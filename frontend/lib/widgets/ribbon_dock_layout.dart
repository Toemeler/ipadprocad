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
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app_state.dart';
import '../menus.dart';
import '../ribbon_dock.dart';
import 'ribbon.dart';
import 'ribbon_chrome.dart';

/// Windows only — the ribbon is not a docked band at all there; it opens as
/// a floating menu on a right-click and closes the way every other popup in
/// the app does (a click elsewhere, see [OpenMenus]).
///
/// A static notifier rather than State on [RibbonDockLayout] itself: the
/// layout is a [StatelessWidget] rebuilt from `AnimatedBuilder(animation:
/// app)` above it (see main.dart), and the menu's open/shut state is chrome,
/// not a document field — the same reasoning [NativeModelBrowser.occupied]
/// already uses for this file's neighbour.
class RibbonRightClickMenu {
  RibbonRightClickMenu._();

  static final ValueNotifier<bool> visible = ValueNotifier<bool>(false);

  static void open() {
    if (visible.value) return;
    OpenMenus.closeAll();
    visible.value = true;
    OpenMenus.register(close);
  }

  static void close() {
    if (!visible.value) return;
    visible.value = false;
    OpenMenus.unregister(close);
  }

  static void toggle() => visible.value ? close() : open();
}

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

  /// Windows only: the toolbar is a right-click menu rather than a docked
  /// band (see [RibbonRightClickMenu]). Every other platform keeps the M290
  /// layout untouched.
  static bool get _rightClickDock => !kIsWeb && Platform.isWindows;

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
      return _layered();
    }
    if (_rightClickDock) {
      RibbonBleed.publish(EdgeInsets.zero);
      return _RightClickBand(app: app, document: _layered());
    }
    // M350 — the band SWALLOWS pointers.
    //
    // Floating, its empty space sits over the viewport, and a Stack lets a hit
    // fall through whatever does not claim it: a tap on the ribbon's
    // background would otherwise orbit the model behind it. The glass itself
    // cannot take the hit (it is a platform view with interaction switched
    // off, deliberately — see GlassPanelView), so the swallow goes here.
    final Widget band = _Bleed(
      dock: RibbonDock.current,
      // Docked, the document is laid out inside the stage and covers nothing
      // (M290's layout, unchanged off iOS). Only a FLOATING band has an edge
      // to report.
      report: floats,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: Ribbon(app: app),
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
            _rail(band),
            Expanded(child: _inner()),
          ]),
      RibbonPosition.right => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _inner()),
            _rail(band),
          ]),
    };
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
  Widget _rail(Widget band) => ValueListenableBuilder<int>(
        valueListenable: RibbonRail.columns,
        builder: (_, __, child) =>
            SizedBox(width: RibbonMetrics.railWidth, child: child),
        child: band,
      );

  /// What goes in the row the band does NOT take: both layers when the band
  /// is docked, the floating chrome alone when it floats (the document is
  /// then behind everything, at full size).
  Widget _inner() => floats ? stage : _layered();

  Widget _layered() => Stack(children: [
        Positioned.fill(child: bleed),
        Positioned.fill(child: stage),
      ]);
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

/// Windows — the toolbar itself: [document] full-size underneath, a
/// right-click anywhere on it summons the ribbon at its dock edge
/// ([RibbonDock.current]), and it stands until something dismisses it —
/// a click elsewhere (the barrier, same convention as every other popup
/// in the app, see menus.dart), or a second right-click.
///
/// M49 in viewport.dart already gives a mouse right-click a meaning of its
/// own inside a Split/Trim/Extend session (cycling the tool family); this
/// widget sits ABOVE that gesture in the tree, so it defers to it rather
/// than fighting it for the same click.
class _RightClickBand extends StatelessWidget {
  final AppState app;
  final Widget document;
  const _RightClickBand({required this.app, required this.document});

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind != PointerDeviceKind.mouse) return;
    if (e.buttons != kSecondaryButton) return;
    if (modifyTools.contains(app.tool)) return; // M49 owns this click
    RibbonRightClickMenu.toggle();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      child: ValueListenableBuilder<bool>(
        valueListenable: RibbonRightClickMenu.visible,
        builder: (context, open, child) {
          if (!open) return document;
          return Stack(children: [
            Positioned.fill(child: document),
            // The dismiss barrier: translucent, so the click that closes the
            // menu still reaches whatever is under it — the same contract
            // showAppContextMenu and Ribbon's own flyout barrier keep.
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (_) => RibbonRightClickMenu.close(),
                child: const SizedBox.expand(),
              ),
            ),
            switch (RibbonDock.current) {
              RibbonPosition.top => Align(
                  alignment: Alignment.topCenter,
                  child: _band(context)),
              RibbonPosition.bottom => Align(
                  alignment: Alignment.bottomCenter,
                  child: _band(context)),
              RibbonPosition.left =>
                Align(alignment: Alignment.centerLeft, child: _band(context)),
              RibbonPosition.right => Align(
                  alignment: Alignment.centerRight, child: _band(context)),
            },
          ]);
        },
      ),
    );
  }

  /// The ribbon, sized to the axis its dock doesn't stretch along: full
  /// width docked top/bottom, full height docked left/right — the same
  /// shape [RibbonDockLayout]'s CrossAxisAlignment.stretch gives it when it
  /// is a row of the layout, so nothing inside the ribbon has to know it is
  /// floating rather than docked.
  Widget _band(BuildContext context) {
    final vertical = RibbonDock.current == RibbonPosition.left ||
        RibbonDock.current == RibbonPosition.right;
    final size = MediaQuery.of(context).size;
    return Listener(
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: vertical ? null : size.width,
        height: vertical ? size.height : null,
        child: Ribbon(app: app),
      ),
    );
  }
}
