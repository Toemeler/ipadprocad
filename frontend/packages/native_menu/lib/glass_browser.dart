/// M107 — the model browser rendered by UIKit on Liquid Glass.
///
/// Dart pushes a flat row model and receives events; it draws nothing and
/// hit-tests nothing in this panel. That is the point: every hard bug in the
/// old browser lived at the Flutter/UIKit boundary (a platform view swallowing
/// taps, a UIKit long-press cancelling a Flutter drag), and inside UIKit those
/// negotiations happen in one gesture system instead of two.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'native_touches.dart';
import 'perf_hook.dart';

/// One row of the tree.
class GlassRow {
  /// Stable identity — also what comes back on tap/menu/eye.
  final String id;

  /// Tree depth; UIKit turns it into indentation.
  final int depth;

  /// SF Symbol name.
  final String symbol;
  final String label;

  /// M243 — the row's NAME, which survives [compact] where [label] does not.
  ///
  /// A retracted row draws no text, but it still has to be able to SAY what it
  /// is: the context menu's title and the hover tooltip both read this. It
  /// defaults to [label], so a caller that never retracts nothing has to
  /// think about it.
  final String title;

  final bool hasEye;
  final bool eyeOn;

  /// Rolled back or hidden: drawn faded.
  final bool dim;

  final bool expandable;
  final bool expanded;
  final bool selected;

  /// M242 — the row under the POINTER (trackpad / Apple Pencil hover). Drawn
  /// like [selected] at half the strength: a prehighlight, not a choice.
  final bool hovered;

  /// The End of Part marker — the only draggable row.
  final bool isEop;

  /// 'blue' | 'red' | null.
  final String? tint;

  /// Context menu, as sections of items.
  final List<List<GlassMenuItem>> menu;

  const GlassRow({
    required this.id,
    required this.label,
    String? title,
    this.depth = 0,
    this.symbol = 'cube',
    this.hasEye = false,
    this.eyeOn = true,
    this.dim = false,
    this.expandable = false,
    this.expanded = false,
    this.selected = false,
    this.hovered = false,
    this.isEop = false,
    this.tint,
    this.menu = const [],
  }) : title = title ?? label;

  /// M200 — the same row, retracted: no label, no indentation, no eye.
  ///
  /// Collapsing is a VIEW of the tree, not a different tree. Keeping the id,
  /// the glyph, the tint, the dim state, the selection and the menu means a
  /// retracted panel does everything the wide one does, minus the words there
  /// is no room for.
  ///
  /// M204 — the +/- box goes too. The retracted card is 56 pt wide now, which
  /// is 34 pt of content: a 16 pt disclosure box AND a 16 pt glyph do not both
  /// fit, and squeezing them meant the thing you actually aim at was clipped.
  /// Nothing is lost — tapping a folder row toggles it (the host has done that
  /// since M121), so the box was the smaller of two targets for the same act.
  GlassRow compact() => GlassRow(
        id: id,
        label: '',
        // M243 — the NAME goes with it, unlike the label: retracted, it is
        // what the context menu is titled and what the tooltip spells out.
        title: title,
        depth: 0,
        symbol: symbol,
        hasEye: false,
        eyeOn: eyeOn,
        dim: dim,
        expandable: false,
        expanded: expanded,
        selected: selected,
        hovered: hovered,
        isEop: isEop,
        tint: tint,
        menu: menu,
      );

  /// M243 — the same row, marked as the one under the pointer.
  GlassRow hover(bool on) => on == hovered
      ? this
      : GlassRow(
          id: id,
          label: label,
          title: title,
          depth: depth,
          symbol: symbol,
          hasEye: hasEye,
          eyeOn: eyeOn,
          dim: dim,
          expandable: expandable,
          expanded: expanded,
          selected: selected,
          hovered: on,
          isEop: isEop,
          tint: tint,
          menu: menu,
        );

  Map<String, Object?> toMap() => {
        'id': id,
        'label': label,
        'title': title,
        'depth': depth,
        'symbol': symbol,
        'hasEye': hasEye,
        'eyeOn': eyeOn,
        'dim': dim,
        'expandable': expandable,
        'expanded': expanded,
        'selected': selected,
        'hovered': hovered,
        'isEop': isEop,
        if (tint != null) 'tint': tint,
        'menu': [
          for (final g in menu)
            if (g.isNotEmpty) [for (final i in g) i.toMap()]
        ],
      };
}

class GlassMenuItem {
  final String id;
  final String title;
  final String? symbol;
  final bool destructive;
  const GlassMenuItem({
    required this.id,
    required this.title,
    this.symbol,
    this.destructive = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        if (symbol != null) 'symbol': symbol,
        'destructive': destructive,
      };
}

/// The native browser surface.
class GlassBrowser extends StatefulWidget {
  final List<GlassRow> rows;
  final void Function(String id) onTap;

  /// M242 — the row under the pointer, or '' when it left the panel, with the
  /// row's vertical CENTRE in the panel's own coordinates so the caller can
  /// put something beside it. Optional: a surface that does not care about
  /// hover simply does not pass it.
  final void Function(String id, double y)? onHover;

  /// M244 — where the rows sit inside the panel: the top and bottom of the
  /// list and the trailing edge of the retracted glyph column, all in the
  /// panel's own coordinates. Sent whenever the rows change.
  ///
  /// The card's insets, its row height and its image box are UIKit's, so a
  /// caller drawing chrome BESIDE the rows would otherwise have to keep a
  /// second copy of three numbers it cannot see.
  final void Function(double top, double bottom, double x)? onMetrics;
  final void Function(String id) onEye;
  final void Function(String id, bool expanded) onExpand;
  final void Function(String id, String item) onMenu;

  /// Live End of Part drag: [steps] is the offset in ROWS from where the drag
  /// began, so Dart owns what a step means.
  final void Function(int steps) onEopDrag;
  final VoidCallback onEopEnd;

  /// M199 — draw the glass slab behind the rows. False leaves the panel
  /// TRANSPARENT: retracted, it is a column of icons over the model, and a
  /// frosted plate behind them is one more thing covering the drawing.
  final bool glass;

  const GlassBrowser({
    super.key,
    required this.rows,
    required this.onTap,
    this.onHover,
    this.onMetrics,
    required this.onEye,
    required this.onExpand,
    required this.onMenu,
    required this.onEopDrag,
    required this.onEopEnd,
    this.glass = true,
  });

  static bool get isSupported => !kIsWeb && Platform.isIOS;

  @override
  State<GlassBrowser> createState() => _GlassBrowserState();
}

class _GlassBrowserState extends State<GlassBrowser> {
  MethodChannel? _ch;
  String? _lastPushed;
  bool? _lastGlass;

  void _onCreated(int id) {
    final ch = MethodChannel('prototype/glass_browser/$id');
    _ch = ch;
    ch.setMethodCallHandler((call) async {
      final a = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      switch (call.method) {
        case 'tap':
          widget.onTap(a['id'] as String? ?? '');
          break;
        case 'hover':
          widget.onHover?.call(
              a['id'] as String? ?? '', (a['y'] as num?)?.toDouble() ?? 0);
          break;
        case 'metrics':
          widget.onMetrics?.call(
              (a['top'] as num?)?.toDouble() ?? 0,
              (a['bottom'] as num?)?.toDouble() ?? 0,
              (a['x'] as num?)?.toDouble() ?? 0);
          break;
        case 'eye':
          widget.onEye(a['id'] as String? ?? '');
          break;
        case 'expand':
          widget.onExpand(a['id'] as String? ?? '', a['on'] as bool? ?? false);
          break;
        case 'menu':
          widget.onMenu(a['id'] as String? ?? '', a['item'] as String? ?? '');
          break;
        case 'eopDrag':
          widget.onEopDrag((a['steps'] as num?)?.toInt() ?? 0);
          break;
        case 'eopEnd':
          widget.onEopEnd();
          break;
      }
      return null;
    });
    _push(force: true);
    _pushGlass(force: true);
  }

  /// Pushes only when the model actually changed — this runs on every rebuild
  /// of the surrounding app, and a diffable snapshot reload per frame would be
  /// wasteful.
  void _push({bool force = false}) {
    final ch = _ch;
    if (ch == null) return;
    // MEASURED, not changed. The gate below is what stops a snapshot reload
    // per frame — but building the thing it compares is NOT free and happens
    // whether or not the gate then fires: one `toMap()` per row, then
    // `toString()` over the whole list. That cost scales with the model and is
    // paid on every rebuild of the surrounding app.
    //
    // `browser.sig` is the duration of computing the signature.
    // `browser.rows.hit` / `.miss` is whether it changed anything: a high hit
    // rate means the app is rebuilding this widget constantly and paying for a
    // comparison that almost never differs. That ratio is the number that says
    // whether the gate belongs earlier (at the model) instead of here.
    final sw = Stopwatch()..start();
    final payload = [for (final r in widget.rows) r.toMap()];
    final sig = payload.toString();
    sw.stop();
    nmRecord('browser.sig', sw.elapsedMicroseconds / 1000.0);
    nmCount('browser.sig.rows', widget.rows.length);
    final unchanged = sig == _lastPushed;
    nmCount('browser.rows.${unchanged ? 'hit' : 'miss'}', 1);
    if (!force && unchanged) return;
    _lastPushed = sig;
    nmCount('browser.setRows.calls', 1);
    ch.invokeMethod('setRows', payload).catchError((_) {});
  }

  void _pushGlass({bool force = false}) {
    final ch = _ch;
    if (ch == null) return;
    if (!force && _lastGlass == widget.glass) return;
    _lastGlass = widget.glass;
    ch.invokeMethod('setGlass', widget.glass).catchError((_) {});
  }

  @override
  void didUpdateWidget(covariant GlassBrowser old) {
    super.didUpdateWidget(old);
    _push();
    _pushGlass();
  }

  @override
  Widget build(BuildContext context) {
    if (!GlassBrowser.isSupported) return const SizedBox.shrink();
    return UiKitView(
      viewType: 'prototype/glass_browser',
      onPlatformViewCreated: _onCreated,
      creationParamsCodec: const StandardMessageCodec(),
      // M205 — the bar owns its touches outright, so a press can never be
      // handed to UIKit as a highlight and taken back as a cancel.
      gestureRecognizers: eagerNativeTouches(),
    );
  }
}
