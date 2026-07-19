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

  Map<String, Object?> toMap({String idPrefix = ''}) => {
        'id': '$idPrefix$id',
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

  /// There is ONE interaction on the Flutter view but several widgets want to
  /// own targets (the gallery, the model browser). Each registers under its own
  /// scope and ids travel prefixed, so a selection can be routed back. Without
  /// this a disposing widget would wipe a freshly-mounted widget's targets —
  /// and those two change over in an unspecified order.
  static const String kGallery = 'gallery';
  static const String kLayers = 'layers';
  static const String _sep = '\u0001';

  static final Map<String, List<NativeMenuTarget>> _scopes = {};
  static final Map<String, NativeMenuSelection> _handlers = {};
  static bool _wired = false;

  /// True only where a real UIKit menu can exist. `Platform.isIOS` is false on
  /// the Linux/macOS host that runs `flutter test`, which is exactly what keeps
  /// the suite free of platform channels.
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  static void setSelectionHandler(String scope, NativeMenuSelection? handler) {
    if (handler == null) {
      _handlers.remove(scope);
    } else {
      _handlers[scope] = handler;
    }
    _wire();
  }

  static void _wire() {
    if (_wired || !isSupported) return;
    _wired = true;
    _ch.setMethodCallHandler((call) async {
      if (call.method != 'selected') return null;
      final args = (call.arguments as Map?)?.cast<String, Object?>();
      final target = args?['target'];
      final item = args?['item'];
      if (target is! String || item is! String) return null;
      final cut = target.indexOf(_sep);
      final scope = cut < 0 ? '' : target.substring(0, cut);
      final id = cut < 0 ? target : target.substring(cut + 1);
      _handlers[scope]?.call(id, item);
      return null;
    });
  }

  /// Replaces the targets owned by [scope]. An empty list drops the scope; when
  /// no scope holds a target the interaction is removed from the Flutter view
  /// entirely, so nothing on screen reacts to a long press.
  static Future<void> setTargets(
      String scope, List<NativeMenuTarget> targets) async {
    if (targets.isEmpty) {
      _scopes.remove(scope);
    } else {
      _scopes[scope] = targets;
    }
    if (!isSupported) return;
    final all = <Map<String, Object?>>[];
    _scopes.forEach((s, list) {
      for (final t in list) {
        all.add(t.toMap(idPrefix: '$s$_sep'));
      }
    });
    await _invoke<bool>('setTargets', {'targets': all});
  }

  /// Native single-field alert. Returns null when cancelled.
  static Future<String?> promptText({
    required String title,
    String? message,
    String initialValue = '',
    String placeholder = '',
    String confirmLabel = 'OK',
    String cancelLabel = 'Cancel',
  }) async {
    if (!isSupported) return null;
    return _invoke<String>('prompt', {
      'title': title,
      'message': message,
      'initialValue': initialValue,
      'placeholder': placeholder,
      'confirmLabel': confirmLabel,
      'cancelLabel': cancelLabel,
    });
  }

  /// Native confirmation alert. [destructive] paints the confirm action red.
  static Future<bool> confirm({
    required String title,
    String? message,
    required String confirmLabel,
    String cancelLabel = 'Cancel',
    bool destructive = true,
  }) async {
    if (!isSupported) return false;
    return await _invoke<bool>('confirm', {
          'title': title,
          'message': message,
          'confirmLabel': confirmLabel,
          'cancelLabel': cancelLabel,
          'destructive': destructive,
        }) ??
        false;
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
    return await _invoke<bool>(method, {
          'path': path,
          'anchor': NativeMenuTarget._rect(anchor),
        }) ??
        false;
  }

  static Future<T?> _invoke<T>(String method, Map<String, Object?> args) async {
    try {
      return await _ch.invokeMethod<T>(method, args);
    } on PlatformException {
      return null; // never let a menu problem take down a frame
    } on MissingPluginException {
      return null; // plugin absent (unexpected host) — stay silent
    }
  }

  /// Test-only: forget every registered scope and handler.
  static void resetForTest() {
    _scopes.clear();
    _handlers.clear();
  }
}
