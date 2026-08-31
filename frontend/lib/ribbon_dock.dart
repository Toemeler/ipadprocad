// M290 — WHICH EDGE THE RIBBON IS DOCKED ON, as a value rather than a widget.
//
// M284 introduced the setting and put the enum, the switch and the settings
// file reader inside widgets/ribbon_chrome.dart. That file is the ribbon's
// SURFACE — the thing that paints glass — and it ended up importing dart:io
// and dart:convert to read a preference off disk.
//
// This repository states the rule twice in its own headers, once in
// settings.dart ("deliberately free of Flutter widgets ... a pure function
// should be testable without a device, a channel or a widget tree") and once
// in backdrop.dart, which is the same shape of preference and lives in lib/
// for exactly this reason. A dock position is a value and a stored string; it
// has no business needing a widget tree to be tested, and a surface has no
// business doing file I/O.
//
// So the value, its store and the switch live here, and ribbon_chrome.dart
// goes back to being about paint.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log.dart';

/// Which edge the ribbon band is docked on.
enum RibbonPosition {
  top,
  bottom,
  left,
  right;

  /// The name as it is stored in settings.json. NOT shown to anyone — the
  /// visible names come from the ARB.
  String get id => name;

  /// True for the two edges where the band is a COLUMN of panels rather than a
  /// row of them. The whole ribbon changes shape on these, which is why it is
  /// asked as a property rather than compared against two values everywhere.
  bool get isVertical =>
      this == RibbonPosition.left || this == RibbonPosition.right;

  bool get isHorizontal => !isVertical;

  static RibbonPosition? byId(Object? s) {
    for (final p in RibbonPosition.values) {
      if (p.id == s) return p;
    }
    return null;
  }
}

/// The default: the flush band across the top.
const RibbonPosition kRibbonDockDefault = RibbonPosition.top;

/// The live setting, as something the layout can listen to.
///
/// Mirrors [Backdrops]: a ValueNotifier the app root watches, plus a store
/// attached once the documents directory is known. Before that the choice
/// still WORKS, it simply is not remembered — the right behaviour for a
/// preference changed on a device whose disk is not ready yet.
class RibbonDock {
  RibbonDock._();

  static final ValueNotifier<RibbonPosition> position =
      ValueNotifier<RibbonPosition>(kRibbonDockDefault);

  static RibbonPosition get current => position.value;
  static bool get isTop => current == RibbonPosition.top;
  static bool get isBottom => current == RibbonPosition.bottom;
  static bool get isLeft => current == RibbonPosition.left;
  static bool get isRight => current == RibbonPosition.right;
  static bool get isVertical => current.isVertical;
  static bool get isHorizontal => current.isHorizontal;

  static RibbonStore? _store;

  /// Point the switch at a settings file and adopt whatever it remembers.
  ///
  /// Called from [AppState.init], off the launch path, for the same reason
  /// [T.attachStore] is: a settings read in front of the first frame is a
  /// launch-time regression this repository measures.
  static void attachStore(RibbonStore store) {
    _store = store;
    final saved = store.load();
    if (saved != null) position.value = saved;
  }

  /// Switch edge, and remember it.
  static void set(RibbonPosition p) {
    if (p == position.value) return;
    position.value = p;
    _store?.save(p);
  }

  @visibleForTesting
  static void resetForTest() {
    position.value = kRibbonDockDefault;
    _store = null;
  }
}

/// Where the ribbon position survives a restart.
///
/// The same file, the same shape and the same swallow-the-error rule as
/// [ThemeStore]: it merges into `settings.json` rather than owning it, so the
/// language and appearance preferences sitting beside it are never dropped.
class RibbonStore {
  final Directory dir;
  const RibbonStore(this.dir);

  static const String fileName = 'settings.json';
  static const String key = 'ribbon';

  File get file => File('${dir.path}/$fileName');

  RibbonPosition? load() {
    try {
      final f = file;
      if (!f.existsSync()) return null;
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return null;
      return RibbonPosition.byId(raw[key]);
    } catch (e) {
      // A corrupt settings file costs a ribbon position and nothing else. It
      // must not cost the launch.
      Log.w('ribbon', 'could not read the ribbon position: $e');
      return null;
    }
  }

  void save(RibbonPosition p) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      Map<String, Object?> data = <String, Object?>{};
      final f = file;
      if (f.existsSync()) {
        final raw = jsonDecode(f.readAsStringSync());
        if (raw is Map) {
          data = <String, Object?>{
            for (final e in raw.entries) '${e.key}': e.value
          };
        }
      }
      data[key] = p.id;
      f.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      Log.w('ribbon', 'could not remember the ribbon position: $e');
    }
  }
}
