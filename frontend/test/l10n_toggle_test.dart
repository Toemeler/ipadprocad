// M234 — the language switch: it applies, it sticks, and nothing restarts.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart' show kDefaultLayer;
import 'package:prototype/l10n/fmt.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/l10n/locale_store.dart';
import 'package:prototype/widgets/home_view.dart';
import 'package:prototype/widgets/ribbon.dart';

AppState makeApp(Directory dir) => AppState()..docsDirForTest = dir;

Widget wrap(Widget child) => ValueListenableBuilder<Locale>(
      valueListenable: L.locale,
      builder: (_, locale, __) => MaterialApp(
        locale: locale,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: SizedBox.expand(child: child)),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('ipc_l10n');
    L.resetForTest();
  });
  tearDown(() {
    L.resetForTest();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('the switch', () {
    test('German is the default, with nothing stored', () {
      expect(L.locale.value, kDe);
      expect(L.current.cancel, 'Abbrechen');
    });

    test('switching changes the strings and the notifier together', () {
      var notified = 0;
      void listener() => notified++;
      L.locale.addListener(listener);
      addTearDown(() => L.locale.removeListener(listener));

      L.set(kEn);
      expect(L.locale.value, kEn);
      expect(L.current.cancel, 'Cancel');
      expect(notified, 1);

      L.set(kDe);
      expect(L.current.cancel, 'Abbrechen');
      expect(notified, 2);
    });

    test('setting the language already in use notifies nobody', () {
      var notified = 0;
      void listener() => notified++;
      L.locale.addListener(listener);
      addTearDown(() => L.locale.removeListener(listener));
      L.set(kDe);
      expect(notified, 0, reason: 'a no-op switch must not rebuild the app');
    });

    test('an unsupported locale is ignored, not thrown', () {
      L.set(const Locale('fr'));
      expect(L.locale.value, kDe);
    });

    test('[other] names the language the toggle switches TO', () {
      expect(L.other, kEn);
      expect(L.otherStrings.languageName, 'English');
      L.set(kEn);
      expect(L.other, kDe);
      expect(L.otherStrings.languageName, 'Deutsch');
    });
  });

  group('it survives a restart', () {
    test('the choice is written to the settings file and read back', () {
      final store = LocaleStore(dir);
      L.attachStore(store);
      L.set(kEn);

      expect(store.file.existsSync(), isTrue);
      expect(jsonDecode(store.file.readAsStringSync())['locale'], 'en');

      // "Restart": forget everything and attach the same directory again.
      L.resetForTest();
      expect(L.locale.value, kDe, reason: 'a fresh process starts German');
      L.attachStore(LocaleStore(dir));
      expect(L.locale.value, kEn, reason: 'and then adopts what was stored');
      expect(L.current.cancel, 'Cancel');
    });

    test('a corrupt settings file costs the preference, not the launch', () {
      File('${dir.path}/${LocaleStore.fileName}')
          .writeAsStringSync('{ this is not json');
      expect(() => L.attachStore(LocaleStore(dir)), returnsNormally);
      expect(L.locale.value, kDe);
    });

    test('an unknown language code in the file is ignored', () {
      File('${dir.path}/${LocaleStore.fileName}')
          .writeAsStringSync(jsonEncode({'locale': 'fr'}));
      L.attachStore(LocaleStore(dir));
      expect(L.locale.value, kDe);
    });

    test('saving keeps other settings in the same file', () {
      final f = File('${dir.path}/${LocaleStore.fileName}');
      f.writeAsStringSync(jsonEncode({'somethingElse': 42}));
      LocaleStore(dir).save(kEn);
      final back = jsonDecode(f.readAsStringSync()) as Map;
      expect(back['locale'], 'en');
      expect(back['somethingElse'], 42, reason: 'must not clobber neighbours');
    });
  });

  group('the menu carries it', () {
    test('the "+" menu offers the OTHER language, by a stable id', () {
      final de = newDocMenuItems(lookupAppL10n(kDe));
      // M236 (SPEC CHANGE) — the appearance row joined the language row on
      // the app-level shelf, after it. The language row is therefore no
      // longer `last`; it is matched by id, which is what it was always for.
      expect(de.map((i) => i.id).toList(),
          ['2d', '3d', 'import', kLanguageMenuId, kAppearanceMenuId]);
      expect(de.firstWhere((i) => i.id == kLanguageMenuId).title,
          'Language: English',
          reason: 'while German is on, the row offers English');

      L.set(kEn);
      final en = newDocMenuItems(lookupAppL10n(kEn));
      expect(en.map((i) => i.id), contains(kLanguageMenuId),
          reason: 'the id never changes');
      expect(en.firstWhere((i) => i.id == kLanguageMenuId).title,
          'Sprache: Deutsch');
    });

    test('the create rows are localised too', () {
      expect(newDocMenuItems(lookupAppL10n(kDe))[0].title, 'Neue 2D-Skizze');
      expect(newDocMenuItems(lookupAppL10n(kEn))[0].title, 'New 2D Sketch');
    });
  });

  group('it applies without a rebuild of the app', () {
    testWidgets('the gallery re-renders in the new language in place',
        (t) async {
      final app = makeApp(dir);
      await t.pumpWidget(wrap(HomeView(app: app)));
      await t.pump();

      final galleryState = t.state(find.byType(HomeView));
      expect(find.text('Auf  +  tippen für eine neue Skizze oder ein Bauteil'),
          findsOneWidget);

      L.set(kEn);
      await t.pump();

      expect(find.text('Tap  +  to create a new sketch or part'), findsOneWidget);
      expect(find.text('Auf  +  tippen für eine neue Skizze oder ein Bauteil'),
          findsNothing);
      // THE point of the exercise: the same State object is still there. A
      // language switch that recreated the tree would lose an open sketch,
      // the scroll position and every controller in it.
      expect(t.state(find.byType(HomeView)), same(galleryState));
    });
  });

  group('the ribbon does not grow out of its scroller', () {
    // The per-string budget in l10n_length_test.dart guards one label at a
    // time. It cannot see the SUM: eleven panels, each two characters wider,
    // is a ribbon a fifth wider than it was, and the last panel walks off the
    // right edge. That is a layout fact and only a laid-out widget knows it.
    //
    // The ribbon is a horizontal scroller on purpose, so this is not a
    // failure — a user flicks it. It is a budget: a fifth is a flick, half
    // again is a command the user has to go looking for.
    Future<double> ribbonWidth(WidgetTester t, Locale locale) async {
      L.resetForTest();
      L.set(locale);
      resetFlyoutCacheForTest();
      // The full sketch ribbon, the way m50_ribbon_slimming_test raises it:
      // an open sketch with a layer being edited.
      final app = makeApp(dir)
        ..sketches['t'] = SketchModel('t')
        ..curTab = 't'
        ..editingLayer = kDefaultLayer;
      await t.binding.setSurfaceSize(const Size(4000, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(Ribbon(app: app)));
      await t.pumpAndSettle();
      // The scrollable's content, not the viewport it is clipped to.
      final row = find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.byType(IntrinsicHeight));
      return t.getSize(row.first).width;
    }

    testWidgets('German is at most a fifth wider than English', (t) async {
      final en = await ribbonWidth(t, kEn);
      final de = await ribbonWidth(t, kDe);
      expect(en, greaterThan(200), reason: 'the ribbon did not lay out');
      expect(de, lessThanOrEqualTo(en * 1.2),
          reason: 'the German ribbon is ${de.toStringAsFixed(0)} px against '
              "English's ${en.toStringAsFixed(0)} "
              '(${((de / en - 1) * 100).toStringAsFixed(1)}% wider). Shorten '
              'the panel titles or the button labels — widening the layout is '
              'not the fix.');
    });
  });

  group('numbers follow the language', () {
    test('decimal comma in German, point in English — display only', () {
      L.set(kDe);
      expect(Fmt.fixed(12.5, 2), '12,50');
      expect(Fmt.mm(12.5), '12,50 mm');
      expect(Fmt.deg(45), '45,0°');
      L.set(kEn);
      expect(Fmt.fixed(12.5, 2), '12.50');
      expect(Fmt.mm(12.5), '12.50 mm');
    });

    test('parsing accepts both conventions in both languages', () {
      for (final loc in [kDe, kEn]) {
        L.resetForTest();
        L.set(loc);
        expect(Fmt.num('12,5'), 12.5);
        expect(Fmt.num('12.5'), 12.5);
        expect(Fmt.num(' 12.5 '), 12.5);
        expect(Fmt.num('nonsense'), isNull);
      }
    });
  });
}
