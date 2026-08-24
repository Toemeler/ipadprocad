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

  const GlassTabBar({
    super.key,
    required this.tabs,
    required this.onTap,
    required this.onClose,
  });

  /// Only iOS has the native bar; elsewhere the caller keeps its own.
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> {
  MethodChannel? _ch;
  String? _lastPushed;

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
