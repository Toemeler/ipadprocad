/// M149 — the document tab bar rendered by UIKit.
///
/// Dart says which documents are open and which one is current; UIKit draws
/// the capsules and owns every touch inside the bar. Same split as the model
/// browser, and for the same reason: every expensive bug in this project has
/// lived on the Flutter/UIKit boundary, and inside UIKit the negotiation
/// happens in one gesture system instead of two.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'perf_hook.dart';

import 'native_touches.dart';

/// One entry of the bar.
class GlassTab {
  /// Stable identity — comes back on tap and close.
  final String id;

  /// Empty for an icon-only tab (Home).
  final String label;

  /// SF Symbol name.
  final String symbol;

  final bool selected;

  /// Home cannot be closed; documents can.
  final bool closable;

  const GlassTab({
    required this.id,
    this.label = '',
    this.symbol = 'doc',
    this.selected = false,
    this.closable = false,
  });

  Map<String, Object?> toMap() => {
        'id': id,
        'label': label,
        'symbol': symbol,
        'selected': selected,
        'closable': closable,
      };
}

class GlassTabBar extends StatefulWidget {
  final List<GlassTab> tabs;
  final void Function(String id) onTap;
  final void Function(String id) onClose;

  /// M260 — the camera is under a finger. The bar folds down to the open
  /// document while this holds and unfolds when it drops, the way iOS 26's
  /// own tab bar minimises while a view scrolls.
  ///
  /// Its own channel call, not part of the tab payload: it changes twice per
  /// gesture and the tab list changes once per document, so pushing them
  /// together would either rebuild the row on every orbit or debounce the
  /// fold behind a signature comparison it has no business waiting for.
  final bool engaged;

  const GlassTabBar({
    super.key,
    required this.tabs,
    required this.onTap,
    required this.onClose,
    this.engaged = false,
  });

  /// Only iOS has the native bar; elsewhere the caller keeps its own.
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> {
  MethodChannel? _ch;
  String? _lastPushed;
  bool? _lastEngaged;

  void _onCreated(int id) {
    final ch = MethodChannel('prototype/glass_tabbar/$id');
    _ch = ch;
    ch.setMethodCallHandler((call) async {
      final a = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
      final tid = a['id'] as String? ?? '';
      switch (call.method) {
        case 'tap':
          widget.onTap(tid);
          break;
        case 'close':
          widget.onClose(tid);
          break;
      }
      return null;
    });
    _push(force: true);
    _pushEngaged(force: true);
  }

  /// M260 — one bool over the wire, on the edge only.
  void _pushEngaged({bool force = false}) {
    final ch = _ch;
    if (ch == null) return;
    if (!force && widget.engaged == _lastEngaged) return;
    _lastEngaged = widget.engaged;
    nmCount('tabbar.setEngaged.calls', 1);
    ch.invokeMethod('setEngaged', {'engaged': widget.engaged})
        .catchError((_) {});
  }

  /// Pushes only on a real change: this rebuilds with the whole app, and
  /// rebuilding the bar's view hierarchy every frame would throw away the
  /// scroll position along with the frame budget.
  void _push({bool force = false}) {
    final ch = _ch;
    if (ch == null) return;
    // Same shape, same measurement as glass_browser._push: the gate below
    // stops the push, but BUILDING the signature it compares is paid on every
    // rebuild of the surrounding app whether the gate fires or not. The hit
    // rate says whether that comparison is earning its keep or whether the
    // gate belongs further up, at the model.
    final sw = Stopwatch()..start();
    final payload = [for (final e in widget.tabs) e.toMap()];
    final sig = payload.toString();
    sw.stop();
    nmRecord('tabbar.sig', sw.elapsedMicroseconds / 1000.0);
    final unchanged = sig == _lastPushed;
    nmCount('tabbar.rows.${unchanged ? 'hit' : 'miss'}', 1);
    if (!force && unchanged) return;
    _lastPushed = sig;
    nmCount('tabbar.setTabs.calls', 1);
    ch.invokeMethod('setTabs', payload).catchError((_) {});
  }

  @override
  void didUpdateWidget(covariant GlassTabBar old) {
    super.didUpdateWidget(old);
    _push();
    _pushEngaged();
  }

  @override
  Widget build(BuildContext context) {
    if (!GlassTabBar.isSupported) return const SizedBox.shrink();
    return UiKitView(
      viewType: 'prototype/glass_tabbar',
      onPlatformViewCreated: _onCreated,
      creationParamsCodec: const StandardMessageCodec(),
      // M205 — the bar owns its touches outright, so a press can never be
      // handed to UIKit as a highlight and taken back as a cancel.
      gestureRecognizers: eagerNativeTouches(),
    );
  }
}
