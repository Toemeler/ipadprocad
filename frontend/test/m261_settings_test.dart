// M261 — the Settings screen: what is on it, and what a tap does.
//
// THE REQUEST. "can you build a settings menu accessible from the menu. there
// should be a settings button but not on the plus. think about the user flow.
// put Darstellung and Language in this Settings and also other important stuff
// that would normaly be in settings. completely ios native."
//
// WHAT IS PINNED HERE, and what deliberately is not. The screen is UIKit
// (SettingsSheet.swift) and a UITableView cannot be asserted from a host test.
// What CAN be — and is the whole of what the sheet is told — is the SPEC:
// which sections exist, in which order, which row carries the tick, what the
// About section reports and what the wire form looks like. The sheet renders
// that and nothing else, so a spec that is right is a screen that is right
// apart from UIKit's own drawing, which is exactly the part worth handing to
// UIKit in the first place.
//
// The two behaviours that are NOT spec are pinned too, because they are the
// ones a refactor can quietly invert: the "+" menu must no longer carry the
// two preferences, and a language switch must relabel the SHEET rather than
// only the app behind it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/settings.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/home_view.dart';

const SettingsInfo _info = SettingsInfo(
  build: 'abc1234',
  kernel3d: 'OCCT 7.9.3 (shim v29)',
  kernel2d: 'Prototype C-API 0.1.0',
  system: 'ios 27.0',
);

List<SettingsSection> _spec({
  Locale locale = kDe,
  AppThemeMode mode = AppThemeMode.system,
  bool diagnostics = true,
}) =>
    buildSettings(L.stringsFor(locale),
        mode: mode, locale: locale, info: _info, diagnostics: diagnostics);

SettingsSection _sec(List<SettingsSection> s, String id) =>
    s.firstWhere((x) => x.id == id);

void main() {
  setUp(() => L.set(kDe));
  tearDown(() {
    L.set(kDe);
    T.resetForTest();
  });

  // -------------------------------------------------------------------------
  group('M261 — the shape of the screen', () {
    test('four sections, in the order a user reads them', () {
      // Appearance and Language first because they are what the user came
      // for; Diagnostics and About below, because they are what they come for
      // once. Not alphabetical, and not the order they were built in.
      expect(_spec().map((s) => s.id).toList(),
          [kSecAppearance, kSecLanguage, kSecDiagnostics, kSecAbout]);
    });

    test('every section has a header, and every row a non-empty title', () {
      for (final s in _spec()) {
        expect(s.header, isNotNull, reason: '${s.id} has no header');
        expect(s.header, isNotEmpty);
        expect(s.rows, isNotEmpty, reason: '${s.id} is an empty group');
        for (final r in s.rows) {
          expect(r.title, isNotEmpty, reason: '${s.id}/${r.id} has no title');
          expect(r.id, isNotEmpty);
        }
      }
    });

    test('the whole screen is German by default, and English on request', () {
      expect(_sec(_spec(), kSecAppearance).header, 'Darstellung');
      expect(_sec(_spec(), kSecLanguage).header, 'Sprache');
      expect(_sec(_spec(locale: kEn), kSecAppearance).header, 'Appearance');
      expect(_sec(_spec(locale: kEn), kSecLanguage).header, 'Language');
    });
  });

  // -------------------------------------------------------------------------
  group('M261 — Darstellung', () {
    test('three rows, and exactly one tick', () {
      for (final mode in AppThemeMode.values) {
        final rows = _sec(_spec(mode: mode), kSecAppearance).rows;
        expect(rows.map((r) => r.id).toList(), ['system', 'light', 'dark']);
        expect(rows.every((r) => r.kind == SettingsRowKind.check), isTrue);
        expect(rows.where((r) => r.selected).map((r) => r.id).toList(),
            [mode.id],
            reason: 'a section of checkmarks with two ticks is a bug');
      }
    });

    test('the rows are named, not spelled — and named in the ARB', () {
      expect(_sec(_spec(), kSecAppearance).rows.map((r) => r.title).toList(),
          ['System', 'Hell', 'Dunkel']);
      expect(
          _sec(_spec(locale: kEn), kSecAppearance)
              .rows
              .map((r) => r.title)
              .toList(),
          ['System', 'Light', 'Dark']);
    });

    test('the row ids round-trip through AppThemeMode, which is what the '
        'handler applies', () {
      for (final r in _sec(_spec(), kSecAppearance).rows) {
        expect(AppThemeMode.byId(r.id), isNotNull,
            reason: 'a row id the handler cannot decode does nothing at all');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('M261 — Sprache', () {
    test('every shipped language, each named in ITSELF', () {
      // The old "+" row named the language it switched TO, which is right for
      // a two-state toggle and wrong for a list. Here the German row says
      // "Deutsch" in both languages — so someone who has landed in a language
      // they cannot read can still find their way out.
      for (final l in [kDe, kEn]) {
        final rows = _sec(_spec(locale: l), kSecLanguage).rows;
        expect(rows.map((r) => r.id).toList(), ['de', 'en']);
        expect(rows.map((r) => r.title).toList(), ['Deutsch', 'English']);
        expect(rows.where((r) => r.selected).map((r) => r.id).toList(),
            [l.languageCode]);
      }
    });

    test('the row ids are language codes L.set understands', () {
      for (final r in _sec(_spec(), kSecLanguage).rows) {
        expect(L.supports(Locale(r.id)), isTrue);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('M261 — the rest of what belongs in Settings', () {
    test('Diagnose offers the report and the log, and says what it sends', () {
      final s = _sec(_spec(), kSecDiagnostics);
      expect(s.rows.map((r) => r.id).toList(),
          [kRowReportProblem, kRowShareLog]);
      expect(s.rows.every((r) => r.kind == SettingsRowKind.action), isTrue);
      expect(s.rows.every((r) => r.symbol != null), isTrue,
          reason: 'an action row without a glyph reads as a label');
      expect(s.footer, isNotNull,
          reason: 'a report that quietly ships the open document has to say '
              'so BEFORE it is tapped');
    });

    test('and the whole section goes when the affordance is retired', () {
      // BugReport.enabled is the prototype switch. Dropping the rows and
      // keeping the header would leave a heading over nothing.
      final ids = _spec(diagnostics: false).map((s) => s.id).toList();
      expect(ids, [kSecAppearance, kSecLanguage, kSecAbout]);
    });

    test('Über reports the build and both kernels, read-only', () {
      final s = _sec(_spec(), kSecAbout);
      expect(s.rows.map((r) => r.id).toList(),
          ['build', 'kernel3d', 'kernel2d', 'system']);
      expect(s.rows.every((r) => r.kind == SettingsRowKind.value), isTrue,
          reason: 'a fact that flashes when tapped reads as a control');
      expect(s.rows.map((r) => r.detail).toList(), [
        'abc1234',
        'OCCT 7.9.3 (shim v29)',
        'Prototype C-API 0.1.0',
        'ios 27.0',
      ]);
    });

    test('nothing on the screen is destructive', () {
      for (final s in _spec()) {
        for (final r in s.rows) {
          expect(r.destructive, isFalse,
              reason: '${s.id}/${r.id} — Settings deletes nothing');
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('M261 — the wire form', () {
    test('every row carries the keys SettingsSheet.swift reads', () {
      final maps = settingsToMaps(_spec());
      expect(maps, hasLength(4));
      for (final s in maps) {
        expect(s['id'], isA<String>());
        expect(s['header'], isA<String>());
        final rows = s['rows'] as List;
        expect(rows, isNotEmpty);
        for (final raw in rows) {
          final r = raw as Map<String, Object?>;
          // These four are read unconditionally on the Swift side; a missing
          // one is a row that renders as a blank line.
          expect(r['id'], isA<String>());
          expect(r['title'], isA<String>());
          expect(r['kind'], isA<String>());
          expect(r['selected'], isA<bool>());
          expect(r['destructive'], isA<bool>());
        }
      }
    });

    test('kind is spelled the way the Swift switch spells it', () {
      // The sheet switches on these three literals. A renamed enum value that
      // still compiles here would silently make every row an `action`.
      final kinds = {
        for (final s in settingsToMaps(_spec()))
          for (final r in (s['rows'] as List))
            (r as Map<String, Object?>)['kind'] as String
      };
      expect(kinds, {'check', 'action', 'value'});
    });

    test('a value row carries its detail and a check row does not', () {
      final maps = settingsToMaps(_spec());
      final about = maps.firstWhere((s) => s['id'] == kSecAbout);
      for (final r in (about['rows'] as List)) {
        expect((r as Map)['detail'], isA<String>());
      }
      final appearance = maps.firstWhere((s) => s['id'] == kSecAppearance);
      for (final r in (appearance['rows'] as List)) {
        expect((r as Map).containsKey('detail'), isFalse,
            reason: 'a detail on a checkmark row would draw twice');
      }
    });
  });

  // -------------------------------------------------------------------------
  group('M261 — the "+" is a verb again', () {
    test('it offers four ways to get a document and no preferences', () {
      final ids = newDocMenuItems(L.stringsFor(kDe)).map((i) => i.id).toList();
      expect(ids, ['2d', '3d', 'asm', 'import']);
      expect(ids, isNot(contains('lang')));
      expect(ids, isNot(contains(kSecAppearance)));
    });
  });

  // -------------------------------------------------------------------------
  group('M261 — the screen answers to the state, not to itself', () {
    test('switching the language relabels the SHEET, not just the app', () {
      // The sheet holds no state: after a tap the whole spec is rebuilt from
      // L and pushed back down. If this ever stopped being true the tick would
      // move and the headings would not, which is the exact half-applied look
      // that makes people tap a setting twice.
      final before = _spec(locale: kDe);
      L.set(kEn);
      final after = buildSettings(L.current,
          mode: T.mode, locale: L.locale.value, info: _info);
      expect(_sec(before, kSecAppearance).header, 'Darstellung');
      expect(_sec(after, kSecAppearance).header, 'Appearance');
      expect(_sec(after, kSecLanguage).rows.firstWhere((r) => r.id == 'en')
          .selected, isTrue);
    });

    test('switching the appearance moves the tick and touches nothing else',
        () {
      final before = _spec(mode: AppThemeMode.system);
      T.set(AppThemeMode.dark);
      final after = buildSettings(L.current,
          mode: T.mode, locale: L.locale.value, info: _info);
      expect(_sec(after, kSecAppearance).rows.firstWhere((r) => r.selected).id,
          'dark');
      // The other sections are untouched — an appearance change is not a
      // reason for the language list to reorder itself.
      expect(_sec(after, kSecLanguage).rows.map((r) => r.id).toList(),
          _sec(before, kSecLanguage).rows.map((r) => r.id).toList());
    });
  });

  // -------------------------------------------------------------------------
  group('M266 — the header buttons are the app\'s own chrome', () {
    testWidgets('both are drawn by the SAME thing the quick-tool bar is',
        (tester) async {
      // "the settings and the plus button dont seem truly ios native. they
      // seem like flutter." They were: a Flutter Container with a
      // BoxDecoration circle and a MATERIAL glyph, on a front page whose
      // ribbon, browser, tab bar and tool bar are all native glass.
      //
      // This runs OFF iOS, so what it can pin is the SWITCH rather than the
      // glass: the header asks GlassToolBar.isSupported exactly as
      // quick_tools does, and falls back to the Material circle only because
      // this host has no UIKit. If the native branch is ever deleted, the
      // widget under the anchor stops being a GlassToolBar on the device and
      // this stays green — so the assertion below is on the FALLBACK being
      // reachable, and the native branch is pinned by the source itself.
      expect(GlassToolBar.isSupported, isFalse,
          reason: 'the host has no UIKit, so the fallback is what renders');

      final app = AppState()
        ..docsDirForTest = Directory.systemTemp.createTempSync('ipc_m266_');
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: kDe,
        home: Material(child: HomeView(app: app)),
      ));
      await tester.pumpAndSettle();

      // Two round buttons in the header, and they are the two commands —
      // not a preference hiding in a create menu.
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    test('M267 — a one-item bar is SQUARE, so half its width is a circle', () {
      // The header asks for GlassToolBar.width / 2 and expects a circle. That
      // is only true while a one-item bar is square, which is arithmetic on
      // four constants that live in two languages (see GlassToolBar.swift).
      // Change padding or the button size without this and the "circle"
      // quietly becomes a lozenge on the device, where nothing here would
      // catch it.
      const one = [GlassToolItem(id: 'x', symbol: 'plus')];
      expect(GlassToolBar.width, GlassToolBar.heightFor(one),
          reason: 'a single-button bar has to be square to be round');
      expect(GlassToolBar.width / 2, 27.0);
      // ...and the DEFAULT is still the squircle every other bar draws, so
      // the quick-tool column is untouched by the header's shape.
      expect(GlassToolBar.radius, 16.0);
    });
  });
}
