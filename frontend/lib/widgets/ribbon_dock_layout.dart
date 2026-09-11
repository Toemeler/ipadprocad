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
    // #49 — the handle is drawn only while the band is OUT.
    //
    // Retracted it used to stay: an 18 pt strip, first painted and then (in
    // this issue's first fix) merely invisible, but in both cases a real child
    // of the row with `HitTestBehavior.opaque` on it. That is a column of dead
    // screen down the edge the whole time the band is away — it swallowed the
    // taps and the orbit drags that land there, and being invisible made it
    // worse, not better, because nothing said why the model would not turn.
    // The way back in is now the edge-swipe overlay below, which takes no
    // layout space and lets everything it does not claim fall through.
    final Widget? grip = canRetract && !retracted
        ? _RibbonGrip(dock: RibbonDock.current)
        : null;
    final Widget rows = switch (RibbonDock.current) {
      RibbonPosition.top => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _reveal(canRetract),
            if (grip != null) grip,
            Expanded(child: _inner())
          ]),
      RibbonPosition.bottom => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _staged(_inner())),
            if (grip != null) grip,
            _reveal(canRetract),
          ]),
      RibbonPosition.left => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _reveal(canRetract),
            if (grip != null) grip,
            Expanded(child: _staged(_inner())),
          ]),
      RibbonPosition.right => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _staged(_inner())),
            if (grip != null) grip,
            _reveal(canRetract),
          ]),
    };
    if (RibbonDock.current == RibbonPosition.top) {
      return _edged(
          canRetract,
          retracted,
          _withCaption(floats
              ? Stack(children: [Positioned.fill(child: bleed), rows])
              : rows));
    }
    if (!floats) return _edged(canRetract, retracted, rows);
    // The document first, at full size, and the band's row over it. The stage
    // is inside [rows], so it still gets the box that excludes the band.
    return _edged(canRetract, retracted,
        Stack(children: [Positioned.fill(child: bleed), rows]));
  }

  /// #49 — the band's own slot, at whatever fraction of itself is showing.
  ///
  /// "it should only come expand when I swipe right from the left edge with a
  /// clean native Apple style animation." There was no animation at all: the
  /// rail was `SizedBox(width: retracted ? 0 : railWidth)`, so the band went
  /// from absent to full width between two frames, which on a device reads as
  /// a glitch rather than as a panel opening.
  ///
  /// Three things make this the native one rather than a fade:
  ///
  ///   * the band keeps its FULL size and is clipped to a fraction of it
  ///     ([Align]'s width/height factor), anchored to the edge it slides out
  ///     of. So the icons travel in from off-screen together, rigidly, the way
  ///     a UIKit panel does — they do not squash from 0 pt wide to 46, which
  ///     is what animating the child's own constraint would have done;
  ///   * [RibbonRetract.drag] short-circuits the tween while a finger is down,
  ///     at [Duration.zero], so the band is under the thumb rather than
  ///     chasing it — and because the tween is still the thing being driven,
  ///     the release animates on from exactly where the finger left it instead
  ///     of snapping back to 0 first;
  ///   * [kRibbonReveal] is an ease-out: fast to start, settling at the end.
  ///
  /// The band is only BUILT while some of it shows. Fully away it is gone from
  /// the tree, which is M405's own rule and the reason a retracted phone pays
  /// nothing for a 2 900-line ribbon it cannot see. [_Bleed] stays either way,
  /// so the inset it publishes can never go stale behind a band that left.
  /// Takes [canRetract] and reads the RETRACTED flag itself, rather than being
  /// handed the answer: the flag decides an animation, and an animation that
  /// is only correct when some ancestor happens to be listening is a lit fuse.
  /// main.dart does listen (it rebuilds the shell, because the band's row
  /// changes the stage's edges) — this makes the band's own movement true
  /// whether or not it ever does.
  /// Keyed for the same reason [_edged] keeps its shape: the handle beside it
  /// comes and goes as the flag flips, and an unkeyed child that changes
  /// position in a row is a NEW element — which would throw the tween away and
  /// snap, exactly the failure [_edged] describes.
  Widget _reveal(bool canRetract) => ValueListenableBuilder<bool>(
        key: const Key('ribbon.band.reveal'),
        valueListenable: RibbonRetract.retracted,
        builder: (_, away, __) => ValueListenableBuilder<double?>(
          valueListenable: RibbonRetract.drag,
          builder: (_, live, __) => TweenAnimationBuilder<double>(
            tween: Tween<double>(
                end: live ?? (canRetract && away ? 0.0 : 1.0)),
            duration: live != null ? Duration.zero : kRibbonReveal,
            curve: kRibbonRevealCurve,
            builder: (_, t, __) => _slice(t),
          ),
        ),
      );

  /// The band clipped to [t] of its extent, anchored to its own edge.
  Widget _slice(double t) {
    final dock = RibbonDock.current;
    final band = _Bleed(
      dock: dock,
      // Docked, the document is laid out inside the stage and covers nothing
      // (M290's layout, unchanged off iOS). Only a FLOATING band has an edge
      // to report.
      report: floats,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        // Retracted the band is GONE rather than merely thin: the whole point
        // is the space, and a hidden ribbon that still swallows pointers over
        // a fifth of the screen would be worse than the one that was visible.
        child: t <= 0 ? const SizedBox.shrink() : Ribbon(app: app),
      ),
    );
    final sized = dock.isVertical ? _rail(band) : band;
    if (t >= 1) return KeyedSubtree(key: kRibbonBandSlot, child: sized);
    return ClipRect(
      key: kRibbonBandSlot,
      child: Align(
        // The edge the band lives on stays pinned while the far edge travels,
        // so it slides out of its own side rather than growing from the middle.
        alignment: switch (dock) {
          RibbonPosition.left => Alignment.centerRight,
          RibbonPosition.right => Alignment.centerLeft,
          RibbonPosition.top => Alignment.bottomCenter,
          RibbonPosition.bottom => Alignment.topCenter,
        },
        widthFactor: dock.isVertical ? t.clamp(0.0, 1.0) : null,
        heightFactor: dock.isVertical ? null : t.clamp(0.0, 1.0),
        child: sized,
      ),
    );
  }

  /// The leading-edge swipe zone, over everything, when the band is away.
  ///
  /// [HitTestBehavior.translucent] and no `onTap`: it claims a horizontal drag
  /// that starts at the edge and nothing else, so a tap, a pinch and an orbit
  /// that begin there still reach the viewport underneath. It is `Positioned`
  /// rather than a row child for the same reason — it must cost the layout
  /// nothing, or it is the dead strip again by another name.
  /// THE SHAPE OF THIS TREE DOES NOT CHANGE WITH [retracted], and that is load
  /// bearing rather than tidiness. Wrapping only while retracted put the whole
  /// band under one more Stack on exactly the frame the flag flipped, so every
  /// element below was rebuilt from scratch — including the tween, which then
  /// initialised AT its new target instead of animating toward it. The reveal
  /// snapped, silently, and looked precisely like having written no animation
  /// at all. So the Stack and the slot are always here on a phone; only what
  /// sits in the slot changes.
  ///
  /// [StackFit.passthrough] hands [child] the constraints this widget was
  /// given, unchanged, so the row inside is laid out exactly as it is without
  /// the Stack. And nothing is built at all where the retract is not offered,
  /// so an iPad and every desktop keep the tree they have always had.
  Widget _edged(bool canRetract, bool retracted, Widget child) {
    if (!canRetract) return child;
    final dock = RibbonDock.current;
    return Stack(fit: StackFit.passthrough, children: [
      child,
      Positioned(
        left: dock == RibbonPosition.right ? null : 0,
        right: dock == RibbonPosition.left ? null : 0,
        top: dock == RibbonPosition.bottom ? null : 0,
        bottom: dock == RibbonPosition.top ? null : 0,
        width: dock.isVertical ? kRibbonEdgeSwipe : null,
        height: dock.isVertical ? null : kRibbonEdgeSwipe,
        child: retracted
            ? _RibbonEdgeSwipe(dock: dock)
            : const SizedBox.shrink(),
      ),
    ]);
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

/// #49 — how long the band takes to slide in or out, and on what curve.
///
/// 320 ms on an ease-out is the shape UIKit gives a panel this size: most of
/// the travel is over in the first third, and it settles rather than stopping.
/// Long enough to read as movement on a 390-point screen, short enough that a
/// thumb which flicks and then reaches for the ribbon is not left waiting.
const Duration kRibbonReveal = Duration(milliseconds: 320);
const Curve kRibbonRevealCurve = Curves.easeOutCubic;

/// #49 — the invisible strip on the band's own edge that a swipe may start in
/// while the band is away.
///
/// Twenty points is what UIKit gives its own screen-edge gestures. Unlike the
/// handle this replaced it takes no layout space and claims no tap, so the
/// only thing that changes for a finger landing here is that a drag ACROSS it
/// brings the ribbon back.
const double kRibbonEdgeSwipe = 20;

/// #49 — the band's own slot, whatever fraction of it is currently showing.
///
/// Keyed because how much of the band SHOWS is the claim of this issue's fix
/// and it is not otherwise measurable: mid-reveal the band keeps its full
/// width and is clipped to part of it, so the ribbon's own box reads the same
/// at every stage of the animation. This node is the part you can see.
const Key kRibbonBandSlot = Key('ribbon.band.slot');

/// #49 — the swipe that brings a retracted band back.
///
/// "it should only come expand when I swipe right from the left edge with a
/// clean native Apple style animation." Three properties make this that
/// gesture rather than the flick switch that was already on the handle:
///
///   * it TRACKS. Every update writes [RibbonRetract.drag], so the band is
///     under the thumb for the whole pull and follows it back out again if
///     the finger reverses. `onHorizontalDragEnd` alone cannot do that: it
///     sees the gesture only once it is over.
///   * a SLOW pull works. The handle's flick needed 50 px/s AT RELEASE or
///     nothing happened at all — so a deliberate drag, which is exactly what
///     someone does when finding out whether a gesture exists, was silently
///     ignored. Past halfway commits here whatever the speed.
///   * a FAST flick still works from anywhere in the travel, because a thumb
///     that has thrown the panel does not expect it to fall back.
class _RibbonEdgeSwipe extends StatefulWidget {
  final RibbonPosition dock;
  const _RibbonEdgeSwipe({required this.dock});

  /// Released past this fraction of the travel, it opens whatever the speed.
  static const double commitAt = 0.5;

  /// …and at this speed it opens from anywhere, in points per second.
  static const double flick = 250;

  @override
  State<_RibbonEdgeSwipe> createState() => _RibbonEdgeSwipeState();
}

class _RibbonEdgeSwipeState extends State<_RibbonEdgeSwipe> {
  /// How far the finger is from the band's edge, in points.
  double _pulled = 0;

  /// What a full reveal is worth. The rail's own width for a side dock, which
  /// is the distance the band really moves; for a top or bottom dock the
  /// band's height belongs to its content and is not known here, so the same
  /// number stands in as the gesture's scale — it sets how far a thumb pulls
  /// for a full reveal, not how large anything is drawn.
  double get _travel => RibbonMetrics.railWidth;

  /// WHERE THE FINGER IS, not how far it has moved.
  ///
  /// Summing `details.delta` looks equivalent and is not, for a reason worth
  /// writing down: a drag competing with another recognizer — and this one
  /// always competes, with whatever the viewport puts under it — spends its
  /// FIRST move resolving the gesture arena, and that delta is never
  /// delivered. The band then sat at zero for the whole first movement and
  /// started following one event late, which a test with a single large move
  /// catches and a test with twenty small ones does not.
  ///
  /// An absolute position cannot drift and cannot lose an event. It is also
  /// the more honest mapping: the band's open edge ends up exactly under the
  /// thumb, which is what a panel being pulled out is.
  double _distanceFromEdge(Offset global, Size screen) => switch (widget.dock) {
        RibbonPosition.left => global.dx,
        RibbonPosition.right => screen.width - global.dx,
        RibbonPosition.top => global.dy,
        RibbonPosition.bottom => screen.height - global.dy,
      };

  /// +1 where an opening flick has a positive velocity along its own axis.
  double get _sign => switch (widget.dock) {
        RibbonPosition.left || RibbonPosition.top => 1,
        RibbonPosition.right || RibbonPosition.bottom => -1,
      };

  void _track(Offset global, Size screen) {
    _pulled = _distanceFromEdge(global, screen).clamp(0.0, _travel);
    RibbonRetract.drag.value = _pulled / _travel;
  }

  void _end(double velocity) {
    final open = _pulled / _travel >= _RibbonEdgeSwipe.commitAt ||
        velocity * _sign >= _RibbonEdgeSwipe.flick;
    // The committed state first and the transient second: clearing [drag]
    // hands the reveal back to its tween, which then carries on from exactly
    // the fraction the finger let go at instead of restarting from nothing.
    if (open) RibbonRetract.set(false);
    _cancel();
  }

  void _cancel() {
    RibbonRetract.drag.value = null;
    _pulled = 0;
  }

  @override
  void dispose() {
    // A gesture interrupted by the band being rebuilt out from under it — a
    // dock change, a rotation — must not leave the reveal pinned to a finger
    // that is no longer there.
    if (RibbonRetract.drag.value != null) RibbonRetract.drag.value = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vertical = widget.dock.isVertical;
    final screen = MediaQuery.sizeOf(context);
    return GestureDetector(
      // Translucent, and with no tap of its own: a tap, a pinch or an orbit
      // beginning at the edge is not this gesture, and must reach the viewport
      // underneath rather than dying here.
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart:
          vertical ? (d) => _track(d.globalPosition, screen) : null,
      onHorizontalDragUpdate:
          vertical ? (d) => _track(d.globalPosition, screen) : null,
      onHorizontalDragEnd: vertical ? (d) => _end(d.primaryVelocity ?? 0) : null,
      onHorizontalDragCancel: vertical ? _cancel : null,
      onVerticalDragStart:
          vertical ? null : (d) => _track(d.globalPosition, screen),
      onVerticalDragUpdate:
          vertical ? null : (d) => _track(d.globalPosition, screen),
      onVerticalDragEnd: vertical ? null : (d) => _end(d.primaryVelocity ?? 0),
      onVerticalDragCancel: vertical ? null : _cancel,
    );
  }
}

/// M405 — the retract handle, and the only way in or out of the retracted
/// state (#38).
///
/// A slim strip on the band's inner edge with a chevron on it, pointing the
/// way the band is about to move. Drawn only on a phone — the one place the
/// retract is offered — so on every other device this widget does not exist
/// and the layout is untouched.
///
/// Eighteen points is the strip, which is under half the width of one ribbon
/// icon and about a twentieth of what the band it hides was taking.
///
/// #49 — AND IT IS DRAWN ONLY WHILE THE BAND IS OUT, where it is the way to
/// put the band away. Retracted it used to stay on screen the whole time, a
/// coloured bar down the edge of a phone that had never opened the ribbon —
/// "if the ribbon is retracted on ios there shouldnt be this Vertical bar."
/// Making it merely invisible (this issue's first fix) was worse: the strip
/// was still a row child with `HitTestBehavior.opaque` on it, so it went on
/// eating every tap and orbit that landed at the edge, with nothing left on
/// screen to explain why. The way back in is [_RibbonEdgeSwipe], which draws
/// nothing, costs no layout and claims only the one gesture — which is what
/// iOS's own edge affordances do.
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
    final bar = DecoratedBox(
      decoration: BoxDecoration(color: T.hover6),
      child: Center(
        child: Icon(_glyph(retracted), size: 16, color: T.dim),
      ),
    );
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
