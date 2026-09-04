// M115 — every icon key the ribbon looks up must exist in the map it looks it
// up in.
//
// This shipped a build with NO RIBBON AT ALL: `IC['acad']!` was written for an
// icon that lives in `IN`, so the null-check operator threw during build,
// Flutter replaced the whole ribbon with its red error widget, and every tool
// — including the Import button that change was adding — disappeared. The
// analyzer cannot see it: the maps are `Map<String, String>`, so a missing key
// is a runtime null, not a type error.
//
// The maps are plain top-level constants, so checking every key the ribbon
// asks for is cheap and catches the whole class before it reaches a device.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/svg_icons.dart';

void main() {
  test('every icon lookup in the ribbon resolves', () {
    final src = File('lib/widgets/ribbon.dart').readAsStringSync();
    final maps = <String, Map<String, String>>{
      'IC': IC,
      'IN': IN,
      'CN': CN,
      'MO': MO,
      'MD': MD,
      // M371 — the measure icon's map. `MS['measure']!` in the ribbon carries
      // a bang, so a typo in the key would take the whole band down at build
      // time: exactly what this test exists to catch.
      'MS': MS,
    };
    final missing = <String>[];
    for (final entry in maps.entries) {
      final re = RegExp("${entry.key}\\['([A-Za-z0-9_]+)'\\]");
      for (final m in re.allMatches(src)) {
        final key = m.group(1)!;
        if (!entry.value.containsKey(key)) {
          missing.add("${entry.key}['$key']");
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'these lookups return null; a `!` on them kills the whole '
            'ribbon at build time');
  });

  test('the icon maps are not accidentally empty', () {
    for (final m in [IC, IN, CN, MO, MD, MS]) {
      expect(m, isNotEmpty);
    }
  });
}
