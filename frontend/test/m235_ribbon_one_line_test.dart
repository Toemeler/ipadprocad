// M235 — every ribbon label gets the width it needs.
//
// The report: "a lot of the German names are now on 2 lines because they're
// too long in the ribbon."
//
// The cause was structural, not a translation problem. The ribbon's buttons
// were FIXED-width boxes (`SizedBox(width: 62)` in _Big, 58..78 in _BigWide)
// sized against the ENGLISH labels, and their `Text` had no line limit. A
// German label wider than its box therefore did not clip or ellipsise — it
// SOFT-WRAPPED onto a second line, and because the panels share a row, one
// wrapped label makes the entire ribbon taller.
//
// The fix makes those widths a FLOOR instead of a cap (`BoxConstraints
// (minWidth:)`) and turns soft wrapping off, so a button grows to fit its
// label. The ribbon is a horizontal SingleChildScrollView whose panels
// "routinely overflow" by its own design note, so the extra width costs
// scroll, not layout.
//
// ---------------------------------------------------------------------------
// WHAT THIS TEST ACTUALLY MEASURES, and why it is not circular.
//
// `softWrap: false` alone would make "renders on one line" trivially true --
// the text would simply be clipped instead. So line-counting is only half the
// assertion. The half that has teeth is:
//
//     paragraph.getMaxIntrinsicWidth(inf) <= paragraph.size.width
//
// i.e. the label was GIVEN the width it wanted. That fails if any ancestor
// bounds the button, which is the way this fix could silently not work.
//
// The host test font is wider per character than the iPad's SF Pro Text, so a
// label that fits here fits on the device. The test is conservative in the
// safe direction.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/ribbon.dart';

/// The six labels that are two lines ON PURPOSE. Each carries its own '\n' in
/// BOTH ARBs -- the English is two lines too -- because that stacked shape is
/// Inventor's, not a symptom. They are exempt from the one-line rule and from
/// nothing else: they must still be given their full width.
const _deliberateTwoLine = <String>{
  'Neue\nSkizze',
  '2D-Skizze\nbeginnen',
  'Neuer\nLayer',
  'Geometrie\nprojizieren',
  'Grafik\nschneiden',
  'Skizze\nfertig',
};

AppState _sketchApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m235');
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer; // edit mode: the full ribbon is up
  return app;
}

AppState _homeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m235h');
  app.curTab = null; // isHome: the Create-New-Sketch ribbon
  return app;
}

AppState _partApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m235p');
  app.parts['p'] = PartModel('Part1');
  app.curTab = 'p';
  return app;
}

/// M240 — the assembly tab. It is held to the same rule as the other three:
/// German labels are longer, and "Abhängig machen" is the longest label the
/// app has ever put under a ribbon icon.
AppState _assemblyApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m235a');
  app.assemblies['a'] = AssemblyModel('Assembly1');
  app.curTab = 'a';
  return app;
}

Future<void> _pump(WidgetTester t, AppState app) async {
  // A real iPad Pro's logical width, not a luxurious test surface: the point
  // is that the ribbon SCROLLS at this size, not that everything fits.
  await t.binding.setSurfaceSize(const Size(1366, 1024));
  await t.pumpWidget(MaterialApp(home: Scaffold(body: Ribbon(app: app))));
  await t.pump();
}

Set<String> _arbValues(String locale) {
  final m = jsonDecode(File('lib/l10n/app_$locale.arb').readAsStringSync())
      as Map<String, dynamic>;
  return {
    for (final e in m.entries)
      if (!e.key.startsWith('@') && e.value is String) e.value as String
  };
}

/// Strings that exist in exactly one of the two ARBs, so seeing one on screen
/// is proof of which language is actually rendering.
final Set<String> _onlyGerman = _arbValues('de').difference(_arbValues('en'));
final Set<String> _onlyEnglish = _arbValues('en').difference(_arbValues('de'));

/// Glyphs that are drawn with a `Text` but are ICONS, not names.
///
/// `fx` is Inventor's italic mark for Parameters and is deliberately sized to
/// the 18 px icon column that lines its row up with the SVG icons beside it --
/// widening that column would break the alignment it exists to keep. It is
/// held to the one-line rule below but exempt from the width rule.
const _iconGlyphs = <String>{'fx'};

/// Every LABEL the ribbon is currently painting, with its rendered geometry.
///
/// Material `Icon`s are `RichText` too -- an `Icon` renders one private-use
/// codepoint from the MaterialIcons font -- and they are not names, so the
/// filter drops any string with no letter or digit in it. (Those glyphs are
/// also drawn ~2 px narrower than their nominal size by the icon font's own
/// padding, which would otherwise show up here as a permanent false alarm.)
List<(String, RenderParagraph)> _labels(WidgetTester t) {
  final out = <(String, RenderParagraph)>[];
  final hasWord = RegExp(r'[A-Za-z0-9\u00C0-\u024F]');
  for (final e in find
      .descendant(of: find.byType(Ribbon), matching: find.byType(RichText))
      .evaluate()) {
    final r = e.renderObject;
    if (r is! RenderParagraph) continue;
    final text = r.text.toPlainText();
    if (!hasWord.hasMatch(text)) continue;
    out.add((text, r));
  }
  return out;
}

/// How many lines a paragraph actually rendered on.
///
/// `RenderParagraph` exposes no line metrics, so this counts the distinct
/// vertical positions of the selection boxes covering the whole string --
/// one row of boxes per rendered line.
int _lineCount(RenderParagraph p, String text) {
  final boxes = p.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length));
  if (boxes.isEmpty) return 1;
  final tops = <double>{};
  for (final b in boxes) {
    // Round: boxes on the same line can differ in the last bit.
    tops.add((b.top * 10).roundToDouble());
  }
  return tops.length;
}

void main() {
  setUp(resetFlyoutCacheForTest);
  // M349 — this whole file is about how a LABEL renders, so it drives the
  // ribbon that has labels. They are off by default now; which of the two
  // modes a suite about typography drives is a property of the suite.
  setUp(() => RibbonLabels.set(true));
  tearDown(RibbonLabels.resetForTest);
  tearDown(() => L.set(kDe));

  for (final (name, make) in <(String, AppState Function())>[
    ('the home ribbon', _homeApp),
    ('the sketch ribbon', _sketchApp),
    ('the part ribbon', _partApp),
    ('the assembly ribbon', _assemblyApp),
  ]) {
    // Both languages, because the fix has two halves to prove. German is the
    // one that was broken. English is the one that must not have MOVED: every
    // English label already fitted the old fixed widths, so if the ribbon is
    // laid out correctly a floor-instead-of-a-cap changes nothing there.
    for (final locale in [kDe, kEn]) {
    group('$name in ${locale.languageCode}', () {
      setUp(() {
        // L.set, NOT `L.locale.value = ...`: `L.of(context)` falls back to
        // `L.current`, and only L.set updates that. Assigning the notifier
        // moves MaterialApp.locale and leaves every string in German, which
        // makes an English test quietly vacuous.
        L.set(locale);
        resetFlyoutCacheForTest();
      });
      // The guard on the guard. An earlier draft of this file switched
      // languages with `L.locale.value = ...` and every "English" assertion
      // silently ran against German strings, passing for the wrong reason.
      // This fails loudly if that ever comes back.
      testWidgets('is actually rendering ${locale.languageCode}', (t) async {
        await _pump(t, make());
        final texts = _labels(t).map((e) => e.$1).toSet();
        final mine = locale == kDe ? _onlyGerman : _onlyEnglish;
        final theirs = locale == kDe ? _onlyEnglish : _onlyGerman;
        expect(texts.intersection(mine), isNotEmpty,
            reason: 'nothing on screen is uniquely '
                '${locale.languageCode}; it shows ${texts.take(12).toList()}');
        expect(texts.intersection(theirs), isEmpty,
            reason: 'the locale switch did not take -- '
                '${texts.intersection(theirs)} is from the other language');
      });

      testWidgets('every label is given the width it asks for',
          (t) async {
        await _pump(t, make());
        final cramped = <String>[];
        for (final (text, p) in _labels(t)) {
          if (_iconGlyphs.contains(text)) continue;
          final wanted = p.getMaxIntrinsicWidth(double.infinity);
          // Half a logical pixel of slack: intrinsic width and laid-out width
          // are both computed in doubles and can disagree in the last bit.
          if (wanted > p.size.width + 0.5) {
            cramped.add('"${text.replaceAll("\n", "\\n")}" wants '
                '${wanted.toStringAsFixed(1)}px, got '
                '${p.size.width.toStringAsFixed(1)}px');
          }
        }
        expect(cramped, isEmpty,
            reason: 'these ribbon labels are squeezed narrower than their '
                'text, so they wrap or clip:\n  ${cramped.join("\n  ")}');
      });

      testWidgets('no label wraps onto a line it was not written with',
          (t) async {
        await _pump(t, make());
        final wrapped = <String>[];
        for (final (text, p) in _labels(t)) {
          final lines = _lineCount(p, text);
          final intended = text.split('\n').length;
          if (lines > intended) {
            wrapped.add('"${text.replaceAll("\n", "\\n")}" renders on $lines '
                'lines but was written as $intended');
          }
        }
        expect(wrapped, isEmpty,
            reason: 'a soft-wrapped label makes the whole ribbon taller:\n'
                '  ${wrapped.join("\n  ")}');
      });
    });
    }
  }

  testWidgets('the deliberate two-liners keep both of their lines', (t) async {
    L.set(kDe);
    await _pump(t, _sketchApp());
    final seen = <String>{};
    for (final (text, p) in _labels(t)) {
      if (!_deliberateTwoLine.contains(text)) continue;
      seen.add(text);
      expect(_lineCount(p, text), 2,
          reason: '"$text" is written as two lines and must render as two -- '
              'turning soft wrap off must not CLIP a hard newline');
    }
    expect(seen, isNotEmpty,
        reason: 'the sketch ribbon shows none of the deliberate two-line '
            'labels, so this guard is measuring nothing');
  });
}
