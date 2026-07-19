/// Real UIKit context menus, share sheet and Files exporter for Flutter.
///
/// Everything here is a NO-OP unless we are actually running on iOS: the host
/// test suite and `flutter analyze` must never see a MissingPluginException,
/// and every entry point swallows channel failures rather than throwing into
/// the widget tree.
library;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

/// One row in a native menu.
class NativeMenuItem {
  /// Returned verbatim to the selection handler.
  final String id;
  final String title;

  /// SF Symbol name, e.g. `trash`. Unknown names simply render without a glyph.
  final String? symbol;

  /// Destructive rows are drawn red by UIKit — we never colour them ourselves.
  final bool destructive;

  const NativeMenuItem({
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

/// A rectangle on screen that opens [groups] when long-pressed.
///
/// Each group becomes a visually separated section, which is how a destructive
/// row gets its own block at the bottom (the Files.app convention).
class NativeMenuTarget {
  final String id;

  /// Header shown above the menu. Empty string = no header.
  final String title;

  /// Whole hit region, in logical pixels, relative to the Flutter view.
  final Rect rect;

  /// Sub-region that visually lifts. Defaults to [rect].
  final Rect? previewRect;

  final double cornerRadius;

  /// Image shown in the lifted preview. Cheaper and far more reliable than
  /// snapshotting the Flutter surface.
  final String? previewImagePath;

  final List<List<NativeMenuItem>> groups;

  const NativeMenuTarget({
    required this.id,
    required this.rect,
    required this.groups,
    this.title = '',
    this.previewRect,
    this.cornerRadius = 0,
    this.previewImagePath,
  });

  static Map<String, Object?> _rect(Rect r) => {
        'left': r.left,
        'top': r.top,
        'width': r.width,
        'height': r.height,
      };

  Map<String, Object?> toMap() => {
        'id': id,
        'title': title,
        'rect': _rect(rect),
        'previewRect': _rect(previewRect ?? rect),
        'cornerRadius': cornerRadius,
        if (previewImagePath != null) 'previewImagePath': previewImagePath,
        'groups': [
          for (final g in groups) [for (final i in g) i.toMap()]
        ],
      };
}

typedef NativeMenuSelection = void Function(String targetId, String itemId);

class NativeMenu {
  NativeMenu._();

  static const MethodChannel _ch = MethodChannel('ipadprocad/native_menu');
  static NativeMenuSelection? _onSelected;
  static bool _wired = false;

  /// True only where a real UIKit menu can exist. `Platform.isIOS` is false on
  /// the Linux/macOS host that runs `flutter test`, which is exactly what keeps
  /// the suite free of platform channels.
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  static void setSelectionHandler(NativeMenuSelection? handler) {
    _onSelected = handler;
    if (_wired || !isSupported) return;
    _wired = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method != 'selected') return null;
      final args = (call.arguments as Map?)?.cast<String, Object?>();
      final target = args?['target'];
      final item = args?['item'];
      if (target is String && item is String) {
        _onSelected?.call(target, item);
      }
      return null;
    });
  }

  /// Replaces the full set of live menu targets. Pass an empty list to remove
  /// the interaction entirely (nothing on screen will react to a long press).
  static Future<void> setTargets(List<NativeMenuTarget> targets) async {
    if (!isSupported) return;
    try {
      await _ch.invokeMethod<bool>('setTargets', {
        'targets': [for (final t in targets) t.toMap()],
      });
    } on PlatformException {
      // Never let a menu problem take down a frame.
    } on MissingPluginException {
      // Plugin absent (e.g. an unexpected host) — stay silent.
    }
  }

  /// System share sheet. [anchor] is required on iPad: UIKit raises if a
  /// popover has no source rectangle.
  static Future<bool> shareFile(String path, {required Rect anchor}) =>
      _sheet('share', path, anchor);

  /// Files exporter ("Save to Files"). Exports a COPY — the sketch stays put.
  static Future<bool> exportFile(String path, {required Rect anchor}) =>
      _sheet('export', path, anchor);

  static Future<bool> _sheet(String method, String path, Rect anchor) async {
    if (!isSupported) return false;
    try {
      final ok = await _ch.invokeMethod<bool>(method, {
        'path': path,
        'anchor': NativeMenuTarget._rect(anchor),
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
