// Prototype — where the share code is remembered.
//
// The same `settings.json` every other preference lives in, and merged into
// rather than owned, for the reason ThemeStore gives: several preferences, one
// file, and none of them may drop the others.
//
// The `sync` key is the one thing in that file the mirror itself will NOT
// copy between devices — see LanSync._localOnlyPrefs. A code that travelled
// would mean one device could switch another one's sharing off by saving a
// preference, which is a remote control rather than a setting.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../log.dart';
import 'lan_sync.dart';
import 'share_code.dart';

class SyncStore {
  final Directory dir;
  const SyncStore(this.dir);

  static const String fileName = 'settings.json';
  static const String key = 'sync';

  File get file => File('${dir.path}/$fileName');

  /// The `sync` section of the file, or null when there is none to read.
  Map<Object?, Object?>? _section() {
    final f = file;
    if (!f.existsSync()) return null;
    final raw = jsonDecode(f.readAsStringSync());
    if (raw is! Map) return null;
    final s = raw[key];
    return s is Map ? s : null;
  }

  /// The remembered code, or null if this device is not sharing.
  String? load() {
    try {
      final s = _section();
      if (s == null) return null;
      final code = s['code'];
      if (code is! String) return null;
      // Validated on the way out as well as in: a hand-edited file, or one
      // written by a version with a different code length, must not start a
      // mirror with a key nothing else derives.
      return normaliseShareCode(code);
    } catch (e) {
      Log.w('sync', 'could not read the share code: $e');
      return null;
    }
  }

  void save(String? canonical) => _write('code', canonical);

  /// M423 — the address this device dials by hand, or null. See
  /// [LanSync.manualPeer]; it lives here rather than in its own file because
  /// it is the same kind of thing as the code — about THIS install, never
  /// mirrored — and [LanSync._localOnlyPrefs] already keeps the whole `sync`
  /// section from travelling.
  String? loadPeer() {
    try {
      final s = _section();
      if (s == null) return null;
      final peer = s['peer'];
      if (peer is! String || peer.trim().isEmpty) return null;
      return peer.trim();
    } catch (e) {
      Log.w('sync', 'could not read the peer address: $e');
      return null;
    }
  }

  void savePeer(String? address) => _write('peer', address);

  /// Merges one field of the `sync` section, leaving the rest of the file —
  /// and the rest of the section — exactly as it was.
  ///
  /// THE SECTION IS MERGED INTO rather than replaced, which is the same rule
  /// the file itself follows and now matters twice: turning sharing off must
  /// not silently forget the address somebody typed, or turning it back on
  /// would strand them looking at a status row that says "looking" for a
  /// reason nothing on the screen explains.
  void _write(String field, String? value) {
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
      final was = data[key];
      final section = <String, Object?>{
        if (was is Map)
          for (final e in was.entries) '${e.key}': e.value,
      };
      if (value == null) {
        section.remove(field);
      } else {
        section[field] = value;
      }
      if (section.isEmpty) {
        data.remove(key);
      } else {
        data[key] = section;
      }
      f.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      Log.w('sync', 'could not remember the $field: $e');
    }
  }
}

/// The live setting, as something the settings sheet can listen to.
///
/// Mirrors [T.scheme] and [L.locale] exactly, and for the same reason: the
/// sheet reads it at build time, so one notification rebuilds the row without a
/// BuildContext being threaded anywhere.
class ShareCodes {
  ShareCodes._();

  /// The canonical code, or null when this device is not sharing.
  static final ValueNotifier<String?> current = ValueNotifier<String?>(null);

  /// M423 — the address this device dials by hand, or null. Watched by the
  /// settings sheet exactly like [current].
  static final ValueNotifier<String?> peer = ValueNotifier<String?>(null);

  static SyncStore? _store;

  /// Point the setting at a file, adopt what it remembers, and START the
  /// mirror if there is a code. Called from AppState.init, off the launch
  /// path, like the other preference stores.
  static void attachStore(SyncStore store) {
    _store = store;
    // THE ADDRESS IS ADOPTED FIRST, and the order is not cosmetic: the mirror
    // dials it as part of coming up, and setting it afterwards would leave it
    // waiting for the next sweep for no reason.
    final address = store.loadPeer();
    if (address != null) {
      peer.value = address;
      LanSync.instance.setManualPeer(address).catchError((Object e) =>
          Log.w('sync', 'could not use the saved address: $e'));
    }
    final saved = store.load();
    if (saved != null) {
      current.value = saved;
      // Not awaited: the mirror binds sockets and the launch path must not
      // wait on a network. It reports through LanSync.status either way.
      _start(saved);
    }
  }

  /// Sets (or clears) the code, remembers it and turns the mirror on or off.
  static Future<void> set(String? canonical) async {
    if (canonical == current.value) return;
    current.value = canonical;
    _store?.save(canonical);
    await LanSync.instance.setCode(canonical);
  }

  /// Sets (or clears) the address this device dials by hand.
  static Future<void> setPeer(String? address) async {
    final next =
        (address == null || address.trim().isEmpty) ? null : address.trim();
    if (next == peer.value) return;
    peer.value = next;
    _store?.savePeer(next);
    await LanSync.instance.setManualPeer(next);
  }

  @visibleForTesting
  static void resetForTest() {
    _store = null;
    current.value = null;
    peer.value = null;
  }
}

/// Starts the mirror without making the caller wait for a socket.
///
/// Not `unawaited` from dart:async, because a failure here has to be REPORTED
/// rather than merely tolerated — a mirror that did not come up is exactly the
/// thing someone is looking at the settings row to find out about.
void _start(String code) {
  LanSync.instance.setCode(code).catchError(
      (Object e) => Log.w('sync', 'could not start sharing: $e'));
}
