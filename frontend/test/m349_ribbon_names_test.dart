// M349 — the ribbon stops writing names, and gets thinner for it.
//
// "in the ribbon are currently names displayed. make this per default off so
//  you can make the ribbon thiner. but still in the settings should be a
//  checkbox 'display names' so i can turn it on again."
//
// Three claims, and each one is measured here rather than described:
//
//   1. OFF BY DEFAULT. Not "there is a switch" — the switch's default is the
//      change, and a default is exactly the kind of thing that survives a
//      refactor by accident and reverts by accident.
//   2. THINNER, IN NUMBERS. A milestone that says "thinner" and moves the band
//      by seven points has not done the thing; the numbers are asserted, with
//      the before and after in one test so a regression names itself.
//   3. NOTHING BECAME UNREACHABLE. The words are gone, not the commands: the
//      flyout chips are still there, the panel's ▼ is still there, and every
//      button still carries its name as a tooltip — which is what VoiceOver
//      and a trackpad hover read.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/ribbon_dock.dart';
import 'package:prototype/settings.dart';
import 'package:prototype/theme.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/widgets/ribbon_chrome.dart';
import 'package:prototype/widgets/ribbon_dock_layout.dart';

const Size _screen = Size(1600, 900);

AppState _document(String tag) {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync(tag);
  app.sketches['t'] = SketchModel('t');
  app.curTab = 't';
  app.editingLayer = kDefaultLayer; // edit mode: the full ribbon is up
  return app;
}

Future<Size> _band(WidgetTester t, {required bool names}) async {
  RibbonLabels.set(names);
  await t.binding.setSurfaceSize(_screen);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: RibbonDockLayout(
        app: _document('ipc_m349'),
        stage: const SizedBox.expand(),
      ),
    ),
  ));
  await t.pump();
  return t.getSize(find.byType(Ribbon));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    L.set(kDe);
    RibbonLabels.resetForTest();
    RibbonDock.resetForTest();
  });
  tearDown(() {
    RibbonLabels.resetForTest();
    RibbonDock.resetForTest();
  });

  // -------------------------------------------------------------------------
  group('the default', () {
    test('names are OFF until somebody turns them on', () {
      expect(kRibbonLabelsDefault, isFalse);
      expect(RibbonLabels.on, isFalse);
    });

    test('the switch remembers, and a file that never carried it does not',
        () {
      final dir = Directory.systemTemp.createTempSync('ipc_m349s');
      final store = RibbonStore(dir);
      expect(store.loadNames(), isNull,
          reason: 'a document from before this milestone must fall to the '
              'DEFAULT, and the default is what changed');
      store.saveNames(true);
      expect(store.loadNames(), isTrue);
      store.saveNames(false);
      expect(store.loadNames(), isFalse);
    });

    test('it shares settings.json with the dock rather than owning it', () {
      final dir = Directory.systemTemp.createTempSync('ipc_m349m');
      final store = RibbonStore(dir);
      store.save(RibbonPosition.right);
      store.saveNames(true);
      expect(store.load(), RibbonPosition.right,
          reason: 'the labels write must not drop the dock');
      expect(store.loadNames(), isTrue);
    });

    test('attaching a store adopts what it remembers', () {
      final dir = Directory.systemTemp.createTempSync('ipc_m349a');
      RibbonStore(dir).saveNames(true);
      RibbonLabels.attachStore(RibbonStore(dir));
      expect(RibbonLabels.on, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('what it costs the band', () {
    testWidgets('a top band is measurably thinner without names', (t) async {
      RibbonDock.set(RibbonPosition.top);
      final named = await _band(t, names: true);
      final compact = await _band(t, names: false);
      expect(compact.height, lessThan(named.height * 0.85),
          reason: 'measured 112 -> 90 on this screen; a milestone that says '
              '"thinner" and moves it by seven points has not done the thing');
      expect(compact.width, _screen.width, reason: 'still flush (M346)');
    });

    testWidgets('a side rail is half the width without names', (t) async {
      RibbonDock.set(RibbonPosition.right);
      final named = await _band(t, names: true);
      final compact = await _band(t, names: false);
      expect(named.width, RibbonMetrics.railWidthNamed);
      expect(compact.width, RibbonMetrics.railWidthCompact);
      expect(compact.width, lessThan(named.width * 0.6));
      expect(compact.height, _screen.height, reason: 'still full height (M346)');
    });

    testWidgets('every dock lays out without overflowing, both ways',
        (t) async {
      // The compact rail is 88 pt and the constraint grid is 123 pt wide at
      // four columns — which is exactly the overflow this milestone had to
      // solve rather than tune around. A RenderFlex overflow throws in a
      // test, so pumping all eight combinations IS the assertion.
      for (final dock in RibbonPosition.values) {
        for (final names in [true, false]) {
          RibbonDock.set(dock);
          final size = await _band(t, names: names);
          expect(size.width, greaterThan(0), reason: '$dock names=$names');
          expect(size.height, greaterThan(0), reason: '$dock names=$names');
        }
      }
    });
  });

  // -------------------------------------------------------------------------
  group('what is on screen', () {
    testWidgets('the words are there with names on and gone without',
        (t) async {
      RibbonDock.set(RibbonPosition.top);
      await _band(t, names: true);
      expect(find.text(L.current.btnRectangle), findsWidgets);
      await _band(t, names: false);
      expect(find.text(L.current.btnRectangle), findsNothing);
    });

    testWidgets('the name survives as a tooltip — nothing is anonymous',
        (t) async {
      RibbonDock.set(RibbonPosition.top);
      await _band(t, names: false);
      expect(find.byTooltip(L.current.btnRectangle), findsWidgets,
          reason: 'a picture with no name is unreachable for VoiceOver and '
              'unreadable for anyone who does not know the glyph');
    });

    testWidgets('every flyout still has a way in', (t) async {
      // The flyout is the only way to a split button's variants and the panel
      // ▼ the only way to the overflow commands. A thinner ribbon that hid a
      // command would be a different feature.
      //
      // M352 changed the AFFORDANCE and this test with it: M349 kept M205's
      // 46 x 26 chip under every compact button, which is what read as an
      // empty grey pill in a band with no words in it. The chip is now a
      // corner ▾ on the cell and a long press (see _CompactCell); what has to
      // stay true is the COUNT — one opener with the names off for every
      // opener with them on.
      RibbonDock.set(RibbonPosition.top);
      await _band(t, names: true);
      final withNames = find.byIcon(Icons.arrow_drop_down).evaluate().length;
      expect(withNames, greaterThan(0));
      await _band(t, names: false);
      expect(find.text('▾').evaluate().length, withNames,
          reason: 'a command that lost its opener is a command that is gone');
      expect(find.text('▼'), findsWidgets, reason: 'the panel expanders stay');
    });

    testWidgets('a panel keeps its title only while names are on', (t) async {
      RibbonDock.set(RibbonPosition.top);
      await _band(t, names: true);
      expect(find.text(L.current.panelCreate), findsOneWidget);
      await _band(t, names: false);
      expect(find.text(L.current.panelCreate), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  group('the switch in Settings', () {
    test('the ribbon section carries a checkbox, last', () {
      final rows = [
        for (final s in _spec())
          if (s.id == kSecRibbon) ...s.rows
      ];
      expect(rows.last.id, kRowRibbonNames);
      expect(rows.last.kind, SettingsRowKind.check);
      expect(rows.map((r) => r.id).where((id) => id == kRowRibbonNames),
          hasLength(1));
    });

    test('its tick follows the setting', () {
      SettingsRow rowFor(bool names) => [
            for (final s in _spec(ribbonNames: names))
              if (s.id == kSecRibbon) ...s.rows
          ].last;
      expect(rowFor(false).selected, isFalse);
      expect(rowFor(true).selected, isTrue);
    });

    test('the four dock rows are still a choice of one', () {
      // The checkbox shares the section with them, so the section must not
      // have become a free-for-all: exactly one position is ticked.
      final rows = [
        for (final s in _spec(ribbon: RibbonPosition.left))
          if (s.id == kSecRibbon) ...s.rows
      ];
      final docks = rows.where((r) => r.id != kRowRibbonNames);
      expect(docks, hasLength(4));
      expect(docks.where((r) => r.selected).map((r) => r.id), ['left']);
    });

    test('the section says what the switch costs', () {
      final section = _spec()
          .firstWhere((s) => s.id == kSecRibbon);
      expect(section.footer, isNotNull);
      expect(section.footer, isNotEmpty);
    });
  });
}

const SettingsInfo _info =
    SettingsInfo(build: 'test', kernel3d: '—', kernel2d: '—', system: '—');

/// The settings screen as the app builds it, with only the two things this
/// suite varies passed in.
List<SettingsSection> _spec({
  bool ribbonNames = kRibbonLabelsDefault,
  RibbonPosition ribbon = RibbonPosition.top,
}) =>
    buildSettings(L.current,
        mode: AppThemeMode.system,
        locale: kDe,
        info: _info,
        ribbon: ribbon,
        ribbonNames: ribbonNames);
