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
import 'package:prototype/part_render.dart';
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
