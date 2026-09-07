// M383 — the Sharing status row FOLLOWS the mirror, rather than being a
// snapshot of the moment Settings opened.
//
// This is where somebody types a code into a second device and then waits. The
// row was built once, when the sheet opened, and never asked again — so it
// said "Looking…" and went on saying it long after the pairing had happened.
// The only way to see "1 device" was to close Settings and open it. From the
// front that is indistinguishable from sharing not working at all, which is
// how it got reported.
//
// A FILE OF ITS OWN, and not tidiness: turning sharing on binds real sockets
// on the real event loop, which a widget test's clock does not drive. Sharing
// that state with tests that drive LanSync directly made this pass or fail
// according to what had run before it in the same isolate.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/sync/lan_sync.dart';
import 'package:prototype/sync/share_code.dart';
import 'package:prototype/sync/sync_store.dart';
import 'package:prototype/widgets/settings_sheet.dart';

void main() {
  group('the status row follows the mirror', () {
    late Directory dir;
    late Locale wasLocale;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('m383ui');
      ShareCodes.resetForTest();
      // The status line is built from `L.current`, the app-wide locale, while
      // the rest of the dialog reads the one in the widget tree. In the app
      // they are the same value — L.locale is what MaterialApp is given — so
      // this only has to be said here, where the MaterialApp under test names
      // its locale directly.
      wasLocale = L.locale.value;
      L.set(const Locale('en'));
    });

    tearDown(() async {
      await ShareCodes.set(null);
      ShareCodes.resetForTest();
      L.set(wasLocale);
      dir.deleteSync(recursive: true);
    });

    testWidgets('a change in the mirror redraws the row without reopening',
        (tester) async {
      // Sharing on BEFORE the sheet, and inside runAsync, which is the only
      // place it can happen at all: testWidgets runs its body under FakeAsync,
      // where a Future waiting on a REAL socket never completes — the clock
      // that would deliver it is the one the test is holding. Awaiting it
      // directly does not fail, it hangs, until the ten-minute timeout;
      // whether that happens depends on what else is running, which is how it
      // survived being run on its own.
      await tester.runAsync(
          () => ShareCodes.set(normaliseShareCode(generateShareCode())));

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
      expect(find.text('Devices'), findsOneWidget,
          reason: 'the status row is only there while sharing is on');

      // Now the mirror finds somebody, with the sheet already open and
      // untouched. A bare pump rather than pumpAndSettle, which would give
      // the real mirror's own sweep a chance to publish over the value under
      // test.
      LanSync.instance.status.value =
          const SyncStatus(SyncState.live, peers: 1);
      await tester.pump();
      expect(find.textContaining('1 device'), findsOneWidget);

      // And a second one, without so much as a tap in between.
      LanSync.instance.status.value =
          const SyncStatus(SyncState.live, peers: 2);
      await tester.pump();
      expect(find.textContaining('2 device'), findsOneWidget);
    });

    // The listener above is only affordable because the notifier stops
    // shouting. _publish() runs on every sweep — twice a second's worth of
    // "still one device" — and a ValueNotifier that cannot compare its values
    // wakes every listener each time.
    test('an unchanged status does not notify', () {
      final seen = <SyncStatus>[];
      final n = ValueNotifier<SyncStatus>(const SyncStatus(SyncState.off));
      void watch() => seen.add(n.value);
      n.addListener(watch);
      n.value = const SyncStatus(SyncState.live, peers: 1);
      n.value = const SyncStatus(SyncState.live, peers: 1);
      n.value = const SyncStatus(SyncState.live, peers: 1);
      expect(seen, hasLength(1));
      n.value = const SyncStatus(SyncState.live, peers: 2);
      expect(seen, hasLength(2));
      n.removeListener(watch);
    });
  });
}
