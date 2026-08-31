// M236 — two palettes instead of one hardcoded scheme.
//
// The interesting failures in a theme rework are not "does it compile". They
// are the three below, and each one has a test here because each one ships a
// visibly broken app if it regresses:
//
//   1. A colour that is legible on charcoal and invisible on cream. Every text
//      and geometry token is measured against the surface it is actually drawn
//      on, in BOTH schemes, at the WCAG AA bar. This is the file's main job —
//      the numbers quoted in theme.dart's header are these numbers.
//   2. A colour written inline in a painter, where no palette can reach it.
//      That is how the app got into this state in the first place, so the
//      source tree itself is asserted on: `Color(0x…)` outside theme.dart is
//      a failure with exactly one documented exception.
//   3. A palette that is read once and cached. `T.x` must follow the ACTIVE
//      scheme at read time, including through the module-level helpers in
//      part_render.dart, or the gallery thumbnails keep the old colours.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/icon_theme.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/svg_icons.dart';
import 'package:prototype/theme.dart';

/// Relative luminance, WCAG 2.1 definition.
double _lum(Color c) {
  double ch(int v) {
    final s = v / 255.0;
    return s <= 0.03928 ? s / 12.92 : math.pow((s + 0.055) / 1.055, 2.4) as double;
  }

  int c8(double v) => (v * 255.0).round().clamp(0, 255);
  return 0.2126 * ch(c8(c.r)) + 0.7152 * ch(c8(c.g)) + 0.0722 * ch(c8(c.b));
}

/// Contrast ratio between two OPAQUE colours.
double _cr(Color a, Color b) {
  final l1 = _lum(a), l2 = _lum(b);
  final hi = math.max(l1, l2), lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

/// Anything the eye reads as TEXT: WCAG 2.1 AA for normal-size text.
const double kMinText = 4.5;

/// Graphical states that are MEANT to recede — construction geometry, an
/// unconstrained curve, a disabled control, a thin witness line. WCAG 1.4.11
/// (non-text contrast) is the applicable bar, and it is 3:1.
///
/// This is not a softer bar for colours that failed the first one. Forcing an
/// unconstrained curve to 4.5:1 against the paper would make it as loud as a
/// fully-defined one, which is the exact distinction Inventor's DOF colouring
/// exists to draw. The floor still has to hold: below 3:1 the state stops
/// being visible at all.
const double kMinGraphic = 3.0;

void main() {
  tearDown(T.resetForTest);

  group('contrast', () {
    // (label, foreground, background) for one palette.
    List<(String, Color, Color)> text(Palette p) => [
          ('text on panel', p.text, p.panel),
          ('text on bg', p.text, p.bg),
          ('text on fly', p.text, p.fly),
          ('dim on panel', p.dim, p.panel),
          ('dim on bg', p.dim, p.bg),
          ('dim on field', p.dim, p.field),
          ('text on field', p.text, p.field),
          ('accent on panel', p.accent, p.panel),
          ('accent on viewport', p.accent, p.viewport),
          ('mbText on mbBg', p.mbText, p.mbBg),
          ('mbDim on mbBg', p.mbDim, p.mbBg),
          ('tabText on tabbarBg', p.tabText, p.tabbarBg),
          ('cardName on cardBg', p.cardName, p.cardBg),
          ('cardDate on cardBg', p.cardDate, p.cardBg),
          ('galleryTitle on galleryBg', p.galleryTitle, p.galleryBg),
          ('onAccent on chipStrong', p.onAccent, p.chipStrong),
          ('onAccent on errFill', p.onAccent, p.errFill),
          ('errText on panel', p.errText, p.panel),
          ('okText on panel', p.okText, p.panel),
          ('warnText on panel', p.warnText, p.panel),
          ('toastText on toastBg', p.toastText, Color.alphaBlend(p.toastBg, p.viewport)),
          // the drawing's own text, on the ground it is drawn on
          ('ink on viewport', p.ink, p.viewport),
          ('dofFull on viewport', p.dofFull, p.viewport),
          ('dofUnder on viewport', p.dofUnder, p.viewport),
          ('projRef on viewport', p.projRef, p.viewport),
          ('edgeAccent on viewport', p.edgeAccent, p.viewport),
          ('dimText on dimPlate', p.dimText, Color.alphaBlend(p.dimPlate, p.viewport)),
          ('cubeText on cubeFace', p.cubeText, p.cubeFace),
          ('cubeText on cubeFaceDim', p.cubeText, p.cubeFaceDim),
        ];

    // Marks and lines, not glyphs — and the two states that are supposed to
    // read as "quieter than the rest".
    List<(String, Color, Color)> graphic(Palette p) => [
          ('constr on viewport', p.constr, p.viewport),
          ('rawGrey on viewport', p.rawGrey, p.viewport),
          ('dimLine on viewport', p.dimLine, p.viewport),
          ('snapOk on viewport', p.snapOk, p.viewport),
          ('dofArrow on viewport', p.dofArrow, p.viewport),
          ('ctrl on viewport', p.ctrl, p.viewport),
          ('solidEdge on solid', p.solidEdge, p.solid),
          ('axisX on viewport', p.axisX, p.viewport),
          ('axisY on viewport', p.axisY, p.viewport),
          ('axisZ on viewport', p.axisZ, p.viewport),
          ('disabled on fly', p.disabled, p.fly),
        ];

    void check(Palette p, String what, double bar,
        List<(String, Color, Color)> pairs) {
      final bad = <String>[];
      for (final (label, fg, bg) in pairs) {
        final r = _cr(fg, bg);
        if (r < bar) bad.add('$label = ${r.toStringAsFixed(2)}:1');
      }
      expect(bad, isEmpty,
          reason: '${p.name} $what below $bar:1:\n  ${bad.join('\n  ')}');
    }

    // Bug report #11 — the accent became the user's choice, so the bar it
    // already answered to has to follow it. A settings screen that lets you
    // pick an accent nobody can read against the panel would have moved the
    // one colour this file exists to hold OUT of this file's reach, which is
    // exactly the failure M236 was written to end. Every entry, both
    // palettes, the same 4.5:1 as `Palette.accent` itself.
    for (final p in [kChalk, kEmber]) {
      test('${p.name}: every choosable accent clears $kMinText:1', () {
        check(p, 'accents', kMinText, [
          for (final a in Accent.values)
            ...[
              ('${a.id} on panel', a.swatchOn(p), p.panel),
              ('${a.id} on viewport', a.swatchOn(p), p.viewport),
            ],
        ]);
      });
    }

    for (final p in [kChalk, kEmber]) {
      test('${p.name}: text clears $kMinText:1', () {
        check(p, 'text', kMinText, text(p));
      });
      test('${p.name}: graphical states clear $kMinGraphic:1', () {
        check(p, 'marks', kMinGraphic, graphic(p));
      });
      test('${p.name}: the grid stays scaffolding', () {
        // Grid dots and the world axes are the paper, not the drawing. WCAG
        // exempts purely decorative marks and it is right to: a grid held to
        // 3:1 is a cage over the geometry. The two rules that DO apply are
        // that it can be seen at all, and that it never competes with the
        // sketch drawn on top of it.
        for (final (label, c) in [('grid', p.grid), ('axis', p.axis)]) {
          final r = _cr(c, p.viewport);
          expect(r, greaterThan(1.2), reason: '$label is invisible ($r:1)');
          expect(r, lessThan(_cr(p.constr, p.viewport)),
              reason: '$label must stay quieter than construction geometry');
        }
      });

      test('${p.name}: the quiet states stay quieter than the loud ones', () {
        // The other half of the graphic bar: a floor is only half the rule.
        // Unconstrained geometry MUST read as weaker than fully-defined
        // geometry, or the DOF colouring says nothing.
        expect(_cr(p.rawGrey, p.viewport), lessThan(_cr(p.dofFull, p.viewport)));
        expect(_cr(p.constr, p.viewport), lessThan(_cr(p.ink, p.viewport)));
        expect(_cr(p.disabled, p.fly), lessThan(_cr(p.text, p.fly)));
      });
    }

    test('a field well sits BELOW its dialog on light, above it on dark', () {
      // M237 — the reason `field` exists. On paper an input has to sink or it
      // stops looking editable; on charcoal it lifts for the same reason.
      expect(_lum(kChalk.field), lessThan(_lum(kChalk.fly)),
          reason: 'a light-scheme field must be darker than the surface it is on');
      expect(_lum(kEmber.field), lessThan(_lum(kEmber.panel)),
          reason: 'a dark-scheme field stays recessed against its panel');
    });

    test('the two schemes really are light and dark', () {
      expect(kChalk.brightness, Brightness.light);
      expect(kEmber.brightness, Brightness.dark);
      // Not a tautology: it catches a light palette built out of dark values,
      // which is what a careless copy of the dark block produces.
      expect(_lum(kChalk.viewport), greaterThan(0.6));
      expect(_lum(kEmber.viewport), lessThan(0.1));
      expect(_lum(kChalk.panel), greaterThan(_lum(kChalk.text)));
      expect(_lum(kEmber.panel), lessThan(_lum(kEmber.text)));
    });

    test('the rendered floor follows the scheme, not a frozen charcoal', () {
      // The floor is what the RENDERED view draws under the model, and where
      // the model browser's icons sit. It used to be a fixed charcoal — right
      // on Ember, a dark island under Chalk's cream chrome — which is how the
      // icons stopped switching colour with the ground behind them.
      expect(_lum(kEmber.floor), lessThan(0.1),
          reason: 'the Ember floor must stay dark for its light icons');
      expect(_lum(kChalk.floor), greaterThan(0.6),
          reason: 'the Chalk floor must be light for its dark icons');
      // A step away from the viewport in BOTH schemes, so it reads as a
      // ground plane rather than vanishing into the background — and still
      // catches the shadow it exists to catch.
      expect(_cr(kEmber.floor, kEmber.viewport), greaterThan(1.15),
          reason: 'the Ember floor must read against the Ember viewport');
      expect(_cr(kChalk.floor, kChalk.viewport), greaterThan(1.15),
          reason: 'the Chalk floor must read against the Chalk viewport');
    });

    test('the neutral overlays flip polarity between the schemes', () {
      // A white 6% wash is invisible on cream — the single most likely way to
      // ship a broken light mode.
      for (final c in [kEmber.hover6, kEmber.hover8, kEmber.border10]) {
        expect(_lum(c.withValues(alpha: 1)), greaterThan(0.5),
            reason: 'dark-scheme overlays lift, so they must be light');
      }
      for (final c in [kChalk.hover6, kChalk.hover8, kChalk.border10]) {
        expect(_lum(c.withValues(alpha: 1)), lessThan(0.1),
            reason: 'light-scheme overlays must darken, not lighten');
      }
    });
  });

  group('T follows the active palette', () {
    test('switching the palette switches every token', () {
      T.palette = kEmber;
      final darkInk = T.ink, darkBg = T.bg, darkAccent = T.accent;
      T.palette = kChalk;
      expect(T.ink, isNot(darkInk));
      expect(T.bg, isNot(darkBg));
      expect(T.accent, isNot(darkAccent));
      expect(T.ink, kChalk.ink);
      expect(T.isDark, isFalse);
    });

    test('part_render reads the palette at call time, not at first use', () {
      // The regression this pins: a top-level `final` here would freeze the
      // palette that happened to be active when the gallery first rendered a
      // thumbnail, and every later thumbnail would come out in the old scheme.
      T.palette = kEmber;
      expect(kSolidBase, kEmber.solid);
      expect(kEdgeAccent, kEmber.edgeAccent);
      expect(kSolidEdge, kEmber.solidEdge);
      expect(kFaceHighlight, kEmber.faceHighlight);
      T.palette = kChalk;
      expect(kSolidBase, kChalk.solid);
      expect(kEdgeAccent, kChalk.edgeAccent);
      expect(kSolidEdge, kChalk.solidEdge);
      expect(kFaceHighlight, kChalk.faceHighlight);
    });
  });

  group('the switch', () {
    test('an explicit choice overrides the platform, and system resolves',
        () {
      T.followPlatform();
      T.set(AppThemeMode.light);
      expect(T.palette, same(kChalk));
      T.set(AppThemeMode.dark);
      expect(T.palette, same(kEmber));
      T.set(AppThemeMode.system);
      // The host reports no platform brightness change, so `system` resolves
      // to whatever the dispatcher says — what matters is that it resolves to
      // one of the two and never to null.
      expect([kChalk, kEmber], contains(T.palette));
    });

    test('the notifier fires exactly once per real change', () {
      T.followPlatform();
      T.set(AppThemeMode.dark);
      var n = 0;
      void bump() => n++;
      T.scheme.addListener(bump);
      T.set(AppThemeMode.light); // a change
      T.set(AppThemeMode.light); // not a change
      expect(n, 1);
      T.scheme.removeListener(bump);
    });

    test('the choice survives a restart', () {
      final dir = Directory.systemTemp.createTempSync('ipc_m236');
      addTearDown(() => dir.deleteSync(recursive: true));

      T.attachStore(ThemeStore(dir));
      T.set(AppThemeMode.light);
      expect(File('${dir.path}/${ThemeStore.fileName}').existsSync(), isTrue);

      // A "restart": drop the state, then read the same directory back.
      T.resetForTest();
      T.attachStore(ThemeStore(dir));
      expect(T.mode, AppThemeMode.light);
      expect(T.palette, same(kChalk));
    });

    test('it shares settings.json with the language, without clobbering it',
        () {
      // The two preferences live in the same file. Writing one must never
      // drop the other — a regression here loses the language on a theme
      // switch, and nothing in the theme tests would otherwise notice.
      final dir = Directory.systemTemp.createTempSync('ipc_m236_share');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/${ThemeStore.fileName}')
          .writeAsStringSync('{"locale":"en"}');

      T.attachStore(ThemeStore(dir));
      T.set(AppThemeMode.dark);

      final raw = jsonDecode(
          File('${dir.path}/${ThemeStore.fileName}').readAsStringSync());
      expect(raw['locale'], 'en', reason: 'the language must survive');
      expect(raw[ThemeStore.key], AppThemeMode.dark.id);
    });

    test('a missing or corrupt file leaves the default in place', () {
      final dir = Directory.systemTemp.createTempSync('ipc_m236_bad');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/${ThemeStore.fileName}').writeAsStringSync('{not json');
      T.attachStore(ThemeStore(dir));
      expect(T.mode, AppThemeMode.system);
    });
  });

  group('the icon set follows the palette (M237)', () {
    // Every literal in svg_icons.dart, so the test cannot drift from the set.
    final all = RegExp(r'#([0-9a-fA-F]{6})')
        .allMatches(File('lib/svg_icons.dart').readAsStringSync())
        .map((m) => '#${m.group(1)!.toLowerCase()}')
        .toSet()
        .toList()
      ..sort();

    Color parse(String h) => Color(0xFF000000 | int.parse(h.substring(1), radix: 16));

    test('the set is not already themed', () {
      expect(all.length, greaterThan(20),
          reason: 'svg_icons.dart should still hold its authored colours');
    });

    for (final p in [kChalk, kEmber]) {
      test('${p.name}: no stop is less readable than it was authored', () {
        // The right instrument. An absolute floor punishes the darkest and
        // lightest stops of a modelled face, which are SUPPOSED to be subtle —
        // they are the shading. What must never happen is a stop coming out of
        // the mapping harder to see than the artist drew it, so each one is
        // measured against its own authored readability on the scheme it was
        // drawn for (Ember).
        T.palette = p;
        final bad = <String>[];
        for (final src in all) {
          final out = themedIcon('<path fill="$src"/>');
          final hex = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(out);
          expect(hex, isNotNull, reason: '$src produced no colour');
          final now = _cr(parse('#${hex!.group(1)!}'), p.panel);
          // Two roles, two rules.
          //
          // A NEUTRAL stop is the glyph's structure — its outline and its
          // plate. It must not come out of the mapping harder to see than it
          // was drawn, so it is held to its authored readability.
          //
          // A CHROMATIC stop is shading, and its authored contrast is partly
          // an accident of the ground: a near-white highlight on charcoal
          // starts at 11:1, and the honest equivalent on paper is a mid-tone,
          // not a near-black — near-black would still be legible and would no
          // longer be blue. Those are held to "clearly visible" instead, with
          // the whole-set test below guaranteeing the glyph carries contrast
          // somewhere.
          final chromatic = HSLColor.fromColor(parse(src)).saturation >= 0.12;
          final was = _cr(parse(src), kEmber.panel);
          if (chromatic) {
            // Clearly visible, OR no worse than it was drawn. The second arm
            // is not a loophole: the darkest shadow stop of a red glyph was
            // authored at 1.4:1 on charcoal ON PURPOSE, and demanding 2.0 of
            // it would mean brightening a shadow until it stops being one.
            if (now < 2.0 && now < was) {
              bad.add('$src -> #${hex.group(1)} = ${now.toStringAsFixed(2)}:1 '
                  '(dimmer than authored ${was.toStringAsFixed(2)}:1)');
            }
          } else {
            if (now < was * 0.75) {
              bad.add('$src -> #${hex.group(1)}: '
                  '${was.toStringAsFixed(2)} -> ${now.toStringAsFixed(2)}:1 '
                  '(neutral regressed)');
            }
          }
        }
        expect(bad, isEmpty,
            reason: '${p.name}: stops lost readability:\n  ${bad.join('\n  ')}');
      });

      test('${p.name}: the set as a whole is legible', () {
        // The other half: subtlety is allowed per stop, invisibility is not.
        // Some stop in the set has to carry real contrast, or every glyph is
        // a smudge.
        T.palette = p;
        var best = 0.0;
        for (final src in all) {
          final out = themedIcon('<path fill="$src"/>');
          final hex = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(out)!;
          final r = _cr(parse('#${hex.group(1)!}'), p.panel);
          if (r > best) best = r;
        }
        expect(best, greaterThan(4.5),
            reason: '${p.name}: the strongest icon stop is only $best:1');
      });
    }

    test('Chalk darkens the set, Ember does not', () {
      // The authored set was drawn FOR charcoal. On paper it has to invert, and
      // this is the assertion that the inversion actually happened rather than
      // the icons merely being passed through.
      const grey = '<path fill="#e8eaec"/>'; // the lightest authored stop
      T.palette = kEmber;
      final onDark = themedIcon(grey);
      T.palette = kChalk;
      final onLight = themedIcon(grey);
      expect(onLight, isNot(onDark));
      Color only(String s) =>
          parse('#${RegExp(r'#([0-9a-fA-F]{6})').firstMatch(s)!.group(1)!}');
      expect(_lum(only(onLight)), lessThan(_lum(only(onDark))),
          reason: 'a light stop must become a DARK one on paper');
    });

    test('orange stays annotation and never becomes an error colour', () {
      // The bug this pins: a 26-degree orange fell through a too-narrow amber
      // band into the red bucket, so the extrude preview glyph came out as a
      // failure glyph.
      for (final p in [kChalk, kEmber]) {
        T.palette = p;
        for (final src in ['#E59B63', '#C8843F', '#E8C63F']) {
          final out = themedIcon('<path fill="$src"/>');
          final c = parse('#${RegExp(r'#([0-9a-fA-F]{6})').firstMatch(out)!.group(1)!}');
          final got = HSLColor.fromColor(c).hue;
          final want = HSLColor.fromColor(p.projRef).hue;
          final red = HSLColor.fromColor(p.err).hue;
          expect((got - want).abs(), lessThan((got - red).abs()),
              reason: '${p.name}: $src landed nearer the error hue than the '
                  'annotation hue');
        }
      }
    });

    test('the blue family lands on the accent, not on some other hue', () {
      T.palette = kChalk;
      final out = themedIcon('<path fill="#3D9BE9"/>');
      final c = parse('#${RegExp(r'#([0-9a-fA-F]{6})').firstMatch(out)!.group(1)!}');
      final want = HSLColor.fromColor(kChalk.accent).hue;
      expect((HSLColor.fromColor(c).hue - want).abs(), lessThan(12),
          reason: 'the old app blue must read as the new accent');
    });

    test('a real icon comes back as valid, fully-mapped SVG', () {
      T.palette = kChalk;
      final out = themedIcon(homeTabIcon);
      expect(out, isNot(contains('#3D9BE9')));
      expect(out.split('<').length, homeTabIcon.split('<').length,
          reason: 'only colours change, never structure');
    });
  });

  test('no colour is written inline outside theme.dart', () {
    // The rule that keeps a second light-mode rewrite from being necessary.
    // One exception, and it carries its reason in the source: an alpha
    // multiplier for drawImageRect is not a theme colour.
    const allowed = {'lib/widgets/viewport.dart': 1};
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final rel = f.path.replaceAll('\\', '/');
      if (rel.endsWith('lib/theme.dart') ||
          rel.endsWith('lib/vector_font_data.dart')) continue;
      final n = RegExp(r'Color\(0x[0-9A-Fa-f]{8}\)')
          .allMatches(f.readAsStringSync())
          .length;
      if (n > (allowed[rel] ?? 0)) {
        offenders.add('$rel: $n literal colour(s)');
      }
    }
    expect(offenders, isEmpty,
        reason: 'move these into Palette (theme.dart):\n  '
            '${offenders.join('\n  ')}');
  });
}
