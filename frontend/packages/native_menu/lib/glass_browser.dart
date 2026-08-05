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

/// One row of the tree.
class GlassRow {
  /// Stable identity — also what comes back on tap/menu/eye.
  final String id;

  /// Tree depth; UIKit turns it into indentation.
  final int depth;

  /// SF Symbol name.
  final String symbol;
  final String label;

  final bool hasEye;
  final bool eyeOn;

  /// Rolled back or hidden: drawn faded.
  final bool dim;

  final bool expandable;
  final bool expanded;
  final bool selected;

  /// The End of Part marker — the only draggable row.
  final bool isEop;

  /// 'blue' | 'red' | null.
  final String? tint;

  /// Context menu, as sections of items.
  final List<List<GlassMenuItem>> menu;

  const GlassRow({
    required this.id,
    required this.label,
    this.depth = 0,
    this.symbol = 'cube',
    this.hasEye = false,
    this.eyeOn = true,
    this.dim = false,
    this.expandable = false,
    this.expanded = false,
    this.selected = false,
    this.isEop = false,
    this.tint,
    this.menu = const [],
  });

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
        depth: 0,
        symbol: symbol,
        hasEye: false,
        eyeOn: eyeOn,
        dim: dim,
        expandable: false,
        expanded: expanded,
        selected: selected,
        isEop: isEop,
        tint: tint,
        menu: menu,
      );

  Map<String, Object?> toMap() => {
        'id': id,
        'label': label,
        'depth': depth,
        'symbol': symbol,
        'hasEye': hasEye,
        'eyeOn': eyeOn,
        'dim': dim,
        'expandable': expandable,
        'expanded': expanded,
        'selected': selected,
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
    final payload = [for (final r in widget.rows) r.toMap()];
    final sig = payload.toString();
    if (!force && sig == _lastPushed) return;
    _lastPushed = sig;
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
    );
  }
}
