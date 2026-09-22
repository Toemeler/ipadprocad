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

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/gen/app_l10n.dart';
import 'package:prototype/sync/lan_sync.dart';
import 'package:prototype/sync/b2_signer.dart';
import 'package:prototype/sync/cloud_account.dart';
import 'package:prototype/sync/cloud_sync.dart';
import 'package:prototype/widgets/settings_sheet.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('m382');
    CloudAccount.resetForTest();
  });

  tearDown(() async {
    // The mirror binds sockets when a code is set; hand them back before the
    // next case, or the second test in this file is testing a busy port.
    await CloudAccount.set(null);
    CloudAccount.resetForTest();
    CloudSync.instance.resetForTest();
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
    // THE TAP GOES THROUGH runAsync, and it is not decoration. A Sharing row
    // turns the mirror on, which binds a TCP listener, a UDP beacon and an
    // mDNS socket — real asynchronous I/O — while `testWidgets` runs its body
    // under FakeAsync, where the clock that would deliver those Futures is the
    // one the test is holding. Started under the fake clock they never
    // complete at all.
    //
    // That used to be merely untidy: the tap handler does not await them, so
    // the case carried on and only the mirror was left half-started. Since
    // code changes are serialised (LanSync._enqueue) it is not — the
    // never-finishing call holds the queue, and the `ShareCodes.set(null)` in
    // tearDown, along with every later case in this file, waits behind it for
    // ever.
    //
    // Pumping is not allowed inside runAsync, so only the tap goes in.
    await tester.runAsync(() => tester.tap(f, warnIfMissed: true));
    await tester.pumpAndSettle();
  }

  group('the Sharing rows on the Flutter surface', () {
    testWidgets('the section is there at all', (tester) async {
      await openSettings(tester);
      // The dialog upper-cases a section header, so this is the header.
      expect(find.text('SHARING'), findsOneWidget);
      // M442 — the four account fields replaced the share code. All four are
      // shown from the start, unset, so somebody can see what is being asked
      // for before they go and fetch it.
      for (final row in const [
        'Bucket',
        'Endpoint',
        'Key ID',
        'Application Key',
      ]) {
        expect(find.text(row), findsOneWidget, reason: row);
      }
      expect(find.text('Not set up'), findsNWidgets(4));
    });

    testWidgets('nothing about the mirror is shown until it is complete',
        (tester) async {
      await openSettings(tester);
      // A status row over a half-entered account would report a failure the
      // person is still in the middle of causing.
      expect(find.text('Devices'), findsNothing);
      expect(find.text('Remove Cloud Account'), findsNothing);
    });

    testWidgets('a field typed in is saved and shown back', (tester) async {
      await openSettings(tester);
      await tapRow(tester, 'Bucket');
      await tester.enterText(find.byType(CupertinoTextField).first, 'my-bucket');
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('OK').last));
      await tester.pumpAndSettle();

      // THE REGRESSION M382 IS ABOUT, in its M442 shape: the row has to reach
      // applySyncRow rather than a bare setState that changes nothing.
      expect(CloudAccount.current.value?.bucket, 'my-bucket');
      expect(find.text('my-bucket'), findsOneWidget,
          reason: 'and the sheet redraws from the new state');
    });

    // The console shows an endpoint; which of its dotted segments is the
    // region is not something anybody should have to know.
    testWidgets('an endpoint is stored as the region it names',
        (tester) async {
      await openSettings(tester);
      await tapRow(tester, 'Endpoint');
      await tester.enterText(
          find.byType(CupertinoTextField).first, 's3.eu-central-003.backblazeb2.com');
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('OK').last));
      await tester.pumpAndSettle();
      expect(CloudAccount.current.value?.region, 'eu-central-003');
    });

    // A key rendered as a row's detail is a key in the next bug report's
    // screenshot.
    testWidgets('the key is never shown back, only that there is one',
        (tester) async {
      await openSettings(tester);
      await tapRow(tester, 'Application Key');
      await tester.enterText(find.byType(CupertinoTextField).first, 'K003SECRETVALUE');
      await tester.pumpAndSettle();
      await tester.runAsync(() => tester.tap(find.text('OK').last));
      await tester.pumpAndSettle();

      expect(CloudAccount.current.value?.appKey, 'K003SECRETVALUE');
      expect(find.text('K003SECRETVALUE'), findsNothing,
          reason: 'the row says Saved, never the key');
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('a complete account brings the mirror rows out',
        (tester) async {
      await CloudAccount.set(const B2Credentials(
        keyId: 'k',
        appKey: 's',
        bucket: 'b',
        region: 'eu-central-003',
      ));
      // The cloud schedules its next cycle the moment it has an account, and
      // a timer started under this test's fake clock never fires — which the
      // framework reports as a leak rather than as the timer it is. The rows
      // read `CloudAccount`, not `CloudSync`, so stopping it changes nothing
      // this test is about.
      CloudSync.instance.resetForTest();
      await openSettings(tester);
      expect(find.text('Devices'), findsOneWidget);
      expect(find.text('Remove Cloud Account'), findsOneWidget);
    });
  });
}
