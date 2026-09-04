// M382 — the Sharing rows have to work on the surface most people see.
//
// The bug: `SettingsSheet` has two tap routers — one for the native UIKit
// sheet and one for the Flutter dialog that every Linux and Windows user gets
// — and only the native one had a `kSecSync` case. The rows drew, took the
// tap, and fell through to a `setState` that changed nothing. The fallback
// also called `buildSettings` without `shareCode`, so it could never show a
// code that was set and never offered "Stop Sharing" at all.
//
// Both surfaces now call the same `applySyncRow`, and what is pinned here is
// the FALLBACK, because that is the half that was broken and the half the host
// suite can actually drive.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/gen/app_l10n.dart';
import 'package:prototype/sync/lan_sync.dart';
import 'package:prototype/sync/share_code.dart';
import 'package:prototype/sync/sync_store.dart';
import 'package:prototype/widgets/settings_sheet.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('m382');
    ShareCodes.resetForTest();
  });

  tearDown(() async {
    // The mirror binds sockets when a code is set; hand them back before the
    // next case, or the second test in this file is testing a busy port.
    await ShareCodes.set(null);
    ShareCodes.resetForTest();
    dir.deleteSync(recursive: true);
  });

  Future<void> openSettings(WidgetTester tester) async {
    final app = AppState()..docsDirForTest = dir;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('en'),
      home: Builder(
        builder: (c) => Material(
          child: TextButton(
            onPressed: () => SettingsSheet.show(c, app),
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Taps a settings row by its label, scrolling it into view first.
  ///
  /// The Sharing section sits near the bottom of a scrolling dialog, and a tap
  /// at a finder that is off-screen misses silently — which would make this
  /// test pass for the wrong reason on the day the bug came back.
  Future<void> tapRow(WidgetTester tester, String label) async {
    final f = find.text(label);
    await tester.scrollUntilVisible(f, 60,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f, warnIfMissed: true);
    await tester.pumpAndSettle();
  }

  group('the Sharing rows on the Flutter surface', () {
    testWidgets('the section is there at all', (tester) async {
      await openSettings(tester);
      // The dialog upper-cases a section header, so this is the header.
      expect(find.text('SHARING'), findsOneWidget);
      expect(find.text('Enter a Share Code'), findsOneWidget);
      expect(find.text('Create a Share Code'), findsOneWidget);
    });

    testWidgets('"Create a Share Code" actually creates one', (tester) async {
      await openSettings(tester);
      expect(ShareCodes.current.value, isNull);

      await tapRow(tester, 'Create a Share Code');

      // THE REGRESSION. This used to fall through the fallback's switch and
      // do nothing at all — the whole report was "the sync buttons do
      // nothing".
      final code = ShareCodes.current.value;
      expect(code, isNotNull,
          reason: 'the row has to reach applySyncRow, not a bare setState');
      expect(normaliseShareCode(code!), code,
          reason: 'and what it stores has to be a canonical code');
    });

    testWidgets('once a code is set the dialog shows it and offers to stop',
        (tester) async {
      await openSettings(tester);
      await tapRow(tester, 'Create a Share Code');

      // The fallback used to call buildSettings without `shareCode`, so the
      // section was permanently in its nothing-shared shape: no code on
      // screen, and no way to turn sharing off.
      expect(find.text('Share Code'), findsOneWidget);
      expect(find.text('Stop Sharing'), findsOneWidget);
      expect(find.text(formatShareCode(ShareCodes.current.value!)),
          findsOneWidget,
          reason: 'the code is shown grouped, the way it is meant to be read');
    });

    testWidgets('the status row appears once sharing is on', (tester) async {
      await openSettings(tester);
      expect(find.text('Devices'), findsNothing,
          reason: 'nothing to report before a code is set');
      await tapRow(tester, 'Create a Share Code');
      // Present because the fallback now passes `syncDetail` at all. What it
      // SAYS depends on whether this host let the mirror bind a socket, which
      // is not something a unit test should assert — the shape is.
      expect(find.text('Devices'), findsOneWidget);
    });
  });
}
