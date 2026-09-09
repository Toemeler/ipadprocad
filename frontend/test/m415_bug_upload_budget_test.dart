// M415 — "i have internet but my ipad could not reach the relay when i make a
// bug report. on windows it works but on ipad it wont reach the relay" (#41).
//
// The upload budget was a CONSTANT (20 s) and the payload is not. That budget
// has to cover the DNS lookup, the TLS handshake, the whole multipart body
// going up, the Worker committing the zip to GitHub and opening an issue, and
// the answer coming back — and the two bundles filed from the desktop the day
// #41 was written are 1.3 MB and 2.2 MB. Twenty seconds for those is asking
// for better than 900 kbit/s of uplink before anything else has cost a
// millisecond: a desktop clears it every time, a tablet at the far end of a
// flat does not, which is the shape of the report.
//
// What is pinned here:
//   * the budget grows with the bundle, and is never below the old constant;
//   * it is capped, because this path deliberately has no progress indicator;
//   * a caller may still hand one in (the other tests do);
//   * the failure the dialog shows names the timeout, the size and the
//     seconds — a fault a reporter can actually pass on.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/bug_upload.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/widgets/bug_button.dart';

Future<void> _pump(WidgetTester t, Widget dialog) async {
  await t.pumpWidget(MaterialApp(
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    locale: const Locale('en'),
    home: Scaffold(body: dialog),
  ));
  await t.pump();
}

void main() {
  group('the budget follows the payload', () {
    test('a small bundle still gets at least the old twenty seconds', () {
      expect(bugUploadTimeoutFor(0), const Duration(seconds: 20));
      expect(bugUploadTimeoutFor(1024).inSeconds, greaterThanOrEqualTo(20));
    });

    test('a real bundle gets meaningfully longer than the old constant', () {
      // The sizes actually filed on 2026-09-09: 1.29 MB and 2.17 MB.
      final small = bugUploadTimeoutFor(1290000);
      final large = bugUploadTimeoutFor(2170000);
      expect(small.inSeconds, greaterThan(40));
      expect(large.inSeconds, greaterThan(small.inSeconds));
      expect(large.inSeconds, greaterThan(65));
    });

    test('it is monotonic in the size', () {
      var last = Duration.zero;
      for (final mb in [0, 1, 2, 3, 4]) {
        final d = bugUploadTimeoutFor(mb * (1 << 20));
        expect(d, greaterThanOrEqualTo(last));
        last = d;
      }
    });

    test('and capped, because nothing on screen is counting it down', () {
      expect(bugUploadTimeoutFor(500 * (1 << 20)),
          const Duration(seconds: 90));
      expect(bugUploadTimeoutFor(1 << 30).inSeconds, lessThanOrEqualTo(90));
    });
  });

  group('the dialog says WHY, not just that', () {
    testWidgets('the relay failure is shown under the sentence about it',
        (t) async {
      await _pump(
          t,
          bugResultDialogForTest(
            path: '/x/bugreports/b.zip',
            uploadFailed: true,
            uploadError: 'timed out after 52s uploading 1290000 bytes',
          ));
      expect(find.textContaining('Could not reach the relay'), findsOneWidget);
      expect(find.text('timed out after 52s uploading 1290000 bytes'),
          findsOneWidget);
    });

    testWidgets('and it is selectable, because it exists to be copied',
        (t) async {
      await _pump(
          t,
          bugResultDialogForTest(
            path: '/x/bugreports/b.zip',
            uploadFailed: true,
            uploadError: 'SocketException: Failed host lookup',
          ));
      expect(
          find.byWidgetPredicate((w) =>
              w is SelectableText &&
              w.data == 'SocketException: Failed host lookup'),
          findsOneWidget);
    });

    testWidgets('a build with no relay shows no reason — none was attempted',
        (t) async {
      await _pump(
          t,
          bugResultDialogForTest(
            path: '/x/bugreports/b.zip',
            noRelay: true,
            uploadError: 'should never be shown',
          ));
      expect(find.textContaining('cannot file anything online'), findsOneWidget);
      expect(find.text('should never be shown'), findsNothing);
    });

    testWidgets('a report that went through shows no reason either', (t) async {
      await _pump(
          t,
          bugResultDialogForTest(
            path: '/x/bugreports/b.zip',
            issueUrl: 'https://github.com/x/y/issues/1',
          ));
      expect(find.textContaining('Could not reach the relay'), findsNothing);
    });
  });

  group('the caller can still override it', () {
    test('an explicit timeout is honoured, and no relay still short-circuits',
        () async {
      // No BUG_RELAY_URL is compiled into a test run, so this returns before
      // it can spend either budget — which is the point: the override has to
      // still be accepted by the signature.
      final sw = Stopwatch()..start();
      final r = await uploadBugReport(
        zipBytes: Uint8List(0),
        stem: 'bug-test',
        description: 'x',
        timeout: const Duration(seconds: 5),
      );
      sw.stop();
      expect(r.ok, isFalse);
      expect(r.error, 'no relay configured');
      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
    });
  });
}
