/// M192 — the vertical quick-tool bar rendered by UIKit.
///
/// Dart says which buttons exist, whether they are enabled and what a tap
/// means; UIKit draws them on Liquid Glass and owns every touch inside the
/// bar. Same split as the tab bar and the model browser, for the same reason.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'perf_hook.dart';

import 'native_touches.dart';

/// One button — or, with [separator], one hairline rule.
class GlassToolItem {
  /// Stable identity; comes back on tap.
  final String id;

  /// SF Symbol name.
  final String symbol;

  /// Older SF Symbol for OS versions where [symbol] does not exist yet. An
  /// unknown name draws NOTHING, and a blank button is the one failure mode an
  /// icons-only bar cannot absorb.
  final String fallback;

  /// VoiceOver label. Never drawn: the bar is icons only, by design.
  final String label;

  final bool enabled;

  /// The armed tool, drawn as a tinted capsule.
  final bool selected;

  /// Red glyph (Cancel).
  final bool destructive;

  final bool separator;

  const GlassToolItem({
    required this.id,
    required this.symbol,
    this.fallback = '',
    this.label = '',
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
  }) : separator = false;

  /// A rule between two groups. Carries a unique [id] so the payload
  /// signature stays honest when two groups collapse into one.
  const GlassToolItem.separator(this.id)
      : symbol = '',
        fallback = '',
        label = '',
        enabled = false,
        selected = false,
        destructive = false,
        separator = true;

  Map<String, Object?> toMap() => {
        'id': id,
        'symbol': symbol,
        'fallback': fallback,
        'label': label,
        'enabled': enabled,
        'selected': selected,
        'destructive': destructive,
        'separator': separator,
      };
}

class GlassToolBar extends StatefulWidget {
  final List<GlassToolItem> items;
  final void Function(String id) onTap;

  const GlassToolBar({super.key, required this.items, required this.onTap});

  /// Only iOS has the native bar; elsewhere the caller draws its own.
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  // Geometry. DUPLICATED in GlassToolBar.swift, which lays the stack out from
  // the same numbers — Dart has to size the platform view before UIKit ever
  // sees it, so neither side can be the single source of truth. Change one,
  // change both.
  static const double buttonSize = 44;
  static const double spacing = 2;
  static const double separatorSlot = 11;
  static const double padding = 5;

  /// Width of the glass slab itself (no outer margin: the platform view eats
  /// every touch inside its frame, so it stays exactly as wide as it looks).
  static const double width = buttonSize + 2 * padding;

  /// Height the given items need, laid out top to bottom.
  static double heightFor(List<GlassToolItem> items) {
    if (items.isEmpty) return 0;
    var h = 2 * padding + spacing * (items.length - 1);
    for (final i in items) {
      h += i.separator ? separatorSlot : buttonSize;
    }
    return h;
  }

  @override
  State<GlassToolBar> createState() => _GlassToolBarState();
}

class _GlassToolBarState extends State<GlassToolBar> {
  MethodChannel? _ch;
  String? _lastPushed;

  void _onCreated(int id) {
    final ch = MethodChannel('prototype/glass_toolbar/$id');
    _ch = ch;
    ch.setMethodCallHandler((call) async {
      if (call.method == 'tap') {
        final a = (call.arguments as Map?)?.cast<String, Object?>() ?? const {};
        widget.onTap(a['id'] as String? ?? '');
      }
      return null;
    });
    _push(force: true);
  }

  /// Pushes only on a real change: this rebuilds with the whole app, and
  /// rebuilding a UIKit view hierarchy every frame is how a bar starts
  /// swallowing the taps that land during its own teardown.
  void _push({bool force = false}) {
    final ch = _ch;
    if (ch == null) return;
    // Same shape, same measurement as glass_browser._push: the gate below
    // stops the push, but BUILDING the signature it compares is paid on every
    // rebuild of the surrounding app whether the gate fires or not. The hit
    // rate says whether that comparison is earning its keep or whether the
    // gate belongs further up, at the model.
    final sw = Stopwatch()..start();
    final payload = [for (final e in widget.items) e.toMap()];
    final sig = payload.toString();
    sw.stop();
    nmRecord('toolbar.sig', sw.elapsedMicroseconds / 1000.0);
    final unchanged = sig == _lastPushed;
    nmCount('toolbar.rows.${unchanged ? 'hit' : 'miss'}', 1);
    if (!force && unchanged) return;
    _lastPushed = sig;
    nmCount('toolbar.setItems.calls', 1);
    ch.invokeMethod('setItems', payload).catchError((_) {});
  }

  @override
  void didUpdateWidget(covariant GlassToolBar old) {
    super.didUpdateWidget(old);
    _push();
  }

  @override
  Widget build(BuildContext context) {
    if (!GlassToolBar.isSupported) return const SizedBox.shrink();
    return SizedBox(
      width: GlassToolBar.width,
      height: GlassToolBar.heightFor(widget.items),
      child: UiKitView(
        viewType: 'prototype/glass_toolbar',
        onPlatformViewCreated: _onCreated,
        creationParamsCodec: const StandardMessageCodec(),
        // M205 — the bar owns its touches outright, so a press can never be
        // handed to UIKit as a highlight and taken back as a cancel.
        gestureRecognizers: eagerNativeTouches(),
      ),
    );
  }
}
