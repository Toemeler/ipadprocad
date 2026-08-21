// M234 — where the language choice survives a restart.
//
// A single JSON file next to `externals.json`, written with the same
// synchronous-write / swallow-the-error shape the rest of the app uses for
// small preferences: losing a language preference must never be able to take
// a launch down with it, and the fallback (German) is the default anyway.
//
// It is NOT stored in the document. A .ptp is a part, not a workstation
// setting, and writing a locale into one would make the file differ between
// two users who drew the same thing.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../log.dart';

/// Reads and writes the app's language choice.
class LocaleStore {
  /// The directory the settings file lives in — `<documents>/.cache`, the
  /// same dot-directory the gallery never scans.
  final Directory dir;

  const LocaleStore(this.dir);

  static const String fileName = 'settings.json';

  /// The key inside the JSON. A named field rather than a bare string, so the
  /// next preference to be remembered has somewhere to go.
  static const String key = 'locale';

  File get file => File('${dir.path}/$fileName');

  /// The remembered language, or null if there is none (or it is unreadable).
  Locale? load() {
    try {
      final f = file;
      if (!f.existsSync()) return null;
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return null;
      final code = raw[key];
      if (code is! String || code.isEmpty) return null;
      return Locale(code);
    } catch (e) {
      // A settings file that has been corrupted, half-written by a crash, or
      // edited by hand costs the user their language preference and nothing
      // else. It must not cost them the launch.
      Log.w('l10n', 'could not read the language setting: $e');
      return null;
    }
  }

  /// Remembers [l]. Merges into whatever else the file holds, so a future
  /// preference written by someone else is not silently dropped here.
  void save(Locale l) {
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
      data[key] = l.languageCode;
      f.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      Log.w('l10n', 'could not remember the language setting: $e');
    }
  }
}
