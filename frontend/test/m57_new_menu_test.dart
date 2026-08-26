// M57 — the gallery "+" is a real UIKit action sheet (native_menu) on iOS,
// with a Flutter showMenu fallback off iOS.
//
// The UIKit half can't run on the host, so what is pinned here is the part the
// device depends on:
//
//   * the MENU CONTRACT — ids '2d'/'3d', order and labels. NativeMenuPlugin's
//     action sheet returns the item id verbatim; home_view is the only source
//     of truth for those strings, and they must equal the values the Flutter
//     fallback yields or one of the two paths would route nowhere.
//   * NativeMenu.menu is a silent no-op off iOS (returns null), so the host
//     suite never trips a platform channel and _showNewMenu falls through to
//     the Flutter menu.
//   * the fallback still drives BOTH document kinds, including the 3D-part
//     branch that had no coverage before.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/widgets/home_view.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/l10n/l.dart';

AppState makeApp() =>
    AppState()..docsDirForTest = Directory.systemTemp.createTempSync('ipc_m57menu');

Future<void> pumpHome(WidgetTester t, AppState app) async {
  await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox.expand(child: HomeView(app: app)))));
  await t.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('new-document menu contract', () {
    test('four items: New 2D Sketch, New 3D Part, New Assembly, then Open',
        () {
      // M234 — pinned in ENGLISH, deliberately: this test is about the
      // contract (ids, order, no destructive flag, every glyph present),
      // and pinning it to one language keeps it a contract test rather than
      // a second copy of the ARB. The German side is pinned in
      // l10n_toggle_test.dart, where it belongs.
      final items = newDocMenuItems(L.stringsFor(kEn));
      // M117 — Open joined the two create actions, because opening a file IS
      // a third way to get a document. It comes LAST: the two you reach for
      // most often stay at the top.
      //
      // M177 — one verb. It is not "Import STEP / DXF" any more, because it
      // also opens the app's own documents from anywhere on the iPad; which
      // of those happens follows from the file the user picks.
      // M240 (SPEC CHANGE) — 'asm' joined the two create actions, ahead of
      // Open and for the same reason Open comes after them: the three ways to
      // START a document belong together, and Open is a way to GET one that
      // already exists.
      // M261 (SPEC CHANGE) — and the language and appearance rows LEFT. They
      // were here because the "+" was the only menu the app itself owned;
      // there is a Settings screen now, and "+" is back to meaning one thing.
      expect(items.map((i) => i.id).toList(),
          ['2d', '3d', 'asm', 'import'],
          reason: 'ids must match the showMenu fallback values');
      expect(items.map((i) => i.title).toList(),
          ['New 2D Sketch', 'New 3D Part', 'New Assembly', 'Open…']);
      // Neither entry is destructive (no red styling on a create action).
      expect(items.every((i) => !i.destructive), isTrue);
      // Every item carries an SF Symbol name for the native glyph.
      expect(items.every((i) => (i.symbol ?? '').isNotEmpty), isTrue);
    });

    test('NativeMenu.menu is a no-op off iOS and never throws', () async {
      expect(NativeMenu.isSupported, isFalse);
      final chosen = await NativeMenu.menu(
        items: newDocMenuItems(L.stringsFor(kEn)),
        anchor: Rect.zero,
      );
      expect(chosen, isNull, reason: 'host has no UIKit -> null, use fallback');
    });
  });

  group('fallback menu (off iOS) drives both kinds', () {
    testWidgets('New 3D Part opens the part-name prompt', (t) async {
      final app = makeApp();
      await pumpHome(t, app);

      await t.tap(find.byIcon(Icons.add));
      await t.pumpAndSettle();
      await t.tap(find.text(L.current.galleryNew3dPart));
      await t.pumpAndSettle();

      // The prompt comes first (nothing created yet), pre-filled with the next
      // free part name.
      expect(find.text(L.current.dlgNewPart), findsOneWidget);
      expect(find.text(app.suggestedPartName()), findsOneWidget);
      expect(app.openTabs, isEmpty);

      await t.enterText(find.byType(TextField), 'Housing');
      await t.tap(find.text(L.current.create));
      await t.pumpAndSettle();

      expect(app.isPartName('Housing'), isTrue);
      expect(app.curTab, 'Housing');
      expect(app.currentPart, isNotNull);
    });

    // M240 — the third kind, through the same door as the other two.
    testWidgets('New Assembly opens the assembly-name prompt', (t) async {
      final app = makeApp();
      await pumpHome(t, app);

      await t.tap(find.byIcon(Icons.add));
      await t.pumpAndSettle();
      await t.tap(find.text(L.current.galleryNewAssembly));
      await t.pumpAndSettle();

      expect(find.text(L.current.dlgNewAssembly), findsOneWidget);
      expect(find.text(app.suggestedAssemblyName()), findsOneWidget);
      expect(app.openTabs, isEmpty);

      await t.enterText(find.byType(TextField), 'Gearbox');
      await t.tap(find.text(L.current.create));
      await t.pumpAndSettle();

      expect(app.isAssemblyName('Gearbox'), isTrue);
      expect(app.curTab, 'Gearbox');
      expect(app.currentAssembly, isNotNull);
      // A brand-new assembly is empty and, being a document kind of its own,
      // is neither a part nor a sketch.
      expect(app.currentAssembly!.occurrences, isEmpty);
      expect(app.currentPart, isNull);
      expect(app.isPartName('Gearbox'), isFalse);
    });
  });
}
