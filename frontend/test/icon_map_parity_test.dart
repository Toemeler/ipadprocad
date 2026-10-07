// Icon v2 — icon_theme.dart's `_map` against the reference port.
//
// design/icons/SPEC.md §12 defines the v2 colour mapping (hue-less greys, the
// luminance-capped light band for chromatic ink, data-lit="2" material stops,
// the constraint red on Palette.conMark). The design tools compute it in
// Python (tools/icon_redesign/build.py) and JS (template.html) — that is what
// the icon lint measures contrast with — and the app computes it here. If the
// two drift, the lint signs off on colours the app never draws.
//
// test/fixtures/icon_map_parity.json is the Python port's output for a table
// of inputs (every v2 ink and material stop, every legacy literal, a sweep
// across each hue band edge), on Carbon Pro Neutral dark and light, as ink
// and as material, plus whole SVGs. Regenerate it with
//   python3 tools/icon_redesign/map_parity.py
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/icon_theme.dart';
import 'package:prototype/svg_icons.dart';
import 'package:prototype/theme.dart';

Color _c(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

void main() {
  final fixture =
      jsonDecode(File('test/fixtures/icon_map_parity.json').readAsStringSync())
          as Map<String, dynamic>;
  final palettes = (fixture['palettes'] as List).cast<Map<String, dynamic>>();

  test('the fixture covers both themes', () {
    expect(palettes.map((p) => (p['tones'] as Map)['dark']).toSet(),
        {true, false});
  });

  for (final p in palettes) {
    final tm = p['tones'] as Map<String, dynamic>;
    final tones = IconTones(
      dark: tm['dark'] as bool,
      ink: _c(tm['ink'] as String),
      bg: _c(tm['bg'] as String),
      accent: _c(tm['accent'] as String),
      ok: _c(tm['ok'] as String),
      projRef: _c(tm['projRef'] as String),
      err: _c(tm['err'] as String),
      conMark: _c(tm['conMark'] as String),
    );
    final id = p['id'] as String;

    group(id, () {
      test('the fixture palette is the shipped Carbon Pro Neutral', () {
        final dart =
            tones.dark ? kCarbonProNeutralDark : kCarbonProNeutralLight;
        expect(tones.ink, dart.ink, reason: 'ink');
        expect(tones.bg, dart.bg, reason: 'bg');
        expect(tones.accent, dart.rawAccent, reason: 'accent');
        expect(tones.ok, dart.ok, reason: 'ok');
        expect(tones.projRef, dart.projRef, reason: 'projRef');
        expect(tones.err, dart.err, reason: 'err');
        expect(tones.conMark, dart.conMark, reason: 'conMark');
      });

      for (final kind in ['ink', 'stop']) {
        test('$kind: Dart equals the Python port', () {
          final table = (p[kind] as Map).cast<String, String>();
          expect(table.length, greaterThan(100));
          final bad = <String>[];
          table.forEach((src, want) {
            final got = kind == 'ink'
                ? mapIconInk(src, tones)
                : mapIconStop(src, tones);
            if (got.toUpperCase() != want.toUpperCase()) {
              bad.add('#$src -> $got, Python $want');
            }
          });
          expect(bad, isEmpty, reason: bad.join('\n'));
        });
      }

      test('whole SVGs: Dart equals the Python port', () {
        for (final pair in (p['svg'] as List).cast<List>()) {
          final src = pair[0] as String, want = pair[1] as String;
          expect(mapIconSvg(src, tones).toUpperCase(), want.toUpperCase());
        }
      });

      test('material is never inverted: a lit stop stays the lighter one', () {
        double l(String h) => HSLColor.fromColor(_c(h)).lightness;
        // the steel and accent top / shade pair of the extrude
        for (final pair in [
          ['ECEDEE', '595E64'],
          ['D0E0F1', '3571B1'],
        ]) {
          expect(l(mapIconStop(pair[0], tones)),
              greaterThan(l(mapIconStop(pair[1], tones))));
        }
      });

      test('the constraint red maps to conMark, the status red to err', () {
        double hue(String h) => HSLColor.fromColor(_c(h)).hue;
        final con = mapIconInk('D96A6E', tones); // CON, hue 358
        final err = mapIconInk('E96C67', tones); // ERR, hue 2
        expect((hue(con) - HSLColor.fromColor(tones.conMark).hue).abs(),
            lessThan(1.5));
        expect((hue(err) - HSLColor.fromColor(tones.err).hue).abs(),
            lessThan(1.5));
      });
    });
  }

  test('themedIcon leaves a data-fixed icon alone', () {
    T.palette = kLightPalette;
    expect(themedIcon(treeFolderIcon), treeFolderIcon);
    expect(treeFolderIcon, contains('data-fixed'));
  });

  test('themedIcon uses the active palette (light: stops are material)', () {
    T.palette = kLightPalette;
    final src = CR['extrude']!;
    expect(src, contains('data-lit="2"'));
    expect(themedIcon(src), mapIconSvg(src, IconTones.current()));
  });
}
