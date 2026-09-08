// M389 — "I wrote a bug report on windows but it doesnt show up in the issues."
//
// It never left the machine, and the app said nothing about that.
//
// `bug_upload.dart` gates the whole upload on a BUILD-TIME constant —
// `String.fromEnvironment('BUG_RELAY_URL')`. The iOS workflow has passed the
// matching `--dart-define` since M285; the Windows and Linux workflows never
// did, so `bugUploadConfigured` was false in every desktop build ever shipped,
// `captureBugReport` skipped the relay, and `BugCaptureResult.upload` came back
// null.
//
// Null then failed BOTH branches of the result dialog: there was one for "an
// issue was filed" and one for "the upload failed", and none at all for "no
// upload was attempted". So the dialog said "Report saved", showed a path, and
// was letter-for-letter identical to the dialog a successful report produces.
// The reporter had no way to know, which is exactly why the report reads the
// way it does.
//
// The workflows are fixed (see ci/bugfix/test_run.py, RelayIsCompiledInTest,
// which is what stops that half regressing). These are the other half: the
// dialog must never again be silent about a report that went nowhere.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/widgets/bug_button.dart';

Future<void> _pump(WidgetTester t, Widget dialog) async {
  await t.pumpWidget(MaterialApp(
    localizationsDelegates: AppL10n.localizationsDelegates,
    supportedLocales: AppL10n.supportedLocales,
    locale: kEn,
    home: Scaffold(body: dialog),
  ));
  await t.pump();
}

/// The English strings, looked up directly. `L.current` tracks the app-wide
/// locale, which is GERMAN — the language the app is written in — while the
/// tree below is pinned to English; reading the wrong one compares a sentence
/// against its own translation and fails for no reason at all.
final AppL10n _l = lookupAppL10n(kEn);

/// The visible text of the whole dialog, joined. `find.text` needs the exact
/// string; what these tests care about is which SENTENCE is on screen, and the
/// sentences come from the ARB.
String _words(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .join('\n');

void main() {
  testWidgets('a build with no relay says the report was not filed',
      (t) async {
    await _pump(t, bugResultDialogForTest(path: r'C:\x\bugreports\b.zip',
        noRelay: true));

    expect(_words(t), contains(_l.msgBugNoRelay),
        reason: 'the one thing the reporter could not otherwise know');
    // NOT the other two. "Could not reach the relay" would send them looking
    // for a network problem that does not exist, and the uploaded line would
    // be a lie.
    expect(_words(t), isNot(contains(_l.msgBugUploaded)));
    expect(_words(t), isNot(contains(_l.msgBugUploadFailed)));
  });

  testWidgets('a configured relay that could not be reached says so instead',
      (t) async {
    await _pump(t, bugResultDialogForTest(
        path: '/home/u/bugreports/b.zip', uploadFailed: true));

    expect(_words(t), contains(_l.msgBugUploadFailed));
    // The distinction is the point: one of these is worth retrying on a
    // better connection and the other never will be.
    expect(_words(t), isNot(contains(_l.msgBugNoRelay)));
  });

  testWidgets('a filed report shows the issue and neither complaint',
      (t) async {
    const url = 'https://github.com/Toemeler/ipadprocad/issues/42';
    await _pump(t, bugResultDialogForTest(
        path: '/home/u/bugreports/b.zip', issueUrl: url));

    expect(_words(t), contains(_l.msgBugUploaded));
    expect(find.text(url), findsOneWidget);
    expect(_words(t), isNot(contains(_l.msgBugNoRelay)));
    expect(_words(t), isNot(contains(_l.msgBugUploadFailed)));
  });

  testWidgets('a bundle that was never written claims no local copy',
      (t) async {
    // The one case where the two are independent: [noRelay] is a property of
    // the BUILD, not of this report, so it is true even when nothing was
    // written. Both complaints end with "only the local copy above exists",
    // and there is no copy above — msgBugBundleFailed has already said so.
    await _pump(t, bugResultDialogForTest(path: null, noRelay: true));

    expect(_words(t), contains(_l.msgBugBundleFailed));
    expect(_words(t), isNot(contains(_l.msgBugNoRelay)));
    expect(_words(t), isNot(contains(_l.msgBugUploadFailed)));
    expect(find.text(_l.btnCopyPath), findsNothing);
  });

  // ---- and where the file is, in the words of the right platform ----------
  //
  // Second-order, and the reporter would have hit it the moment they went
  // looking: the "where it landed" line said "Files app > On My iPad >
  // prototype > bugreports" on Windows and Linux too, where there is no Files
  // app, no On My iPad, and the only true part is the path underneath it.
  testWidgets('the desktop says where a desktop file is', (t) async {
    await _pump(t, bugResultDialogForTest(path: r'C:\x\bugreports\b.zip'));

    // The host IS a desktop, so this is the branch the suite exercises.
    expect(Platform.isLinux || Platform.isMacOS || Platform.isWindows, isTrue);
    expect(_words(t), contains(_l.msgBugSavedDesktop));
    expect(_words(t), isNot(contains(_l.msgBugSaved)),
        reason: 'the iPad wording names a Files app that is not there');
  });

  testWidgets('the path itself is always shown and always copyable',
      (t) async {
    const path = r'C:\Users\t\Documents\prototype\bugreports\b.zip';
    for (final d in [
      bugResultDialogForTest(path: path, noRelay: true),
      bugResultDialogForTest(path: path, uploadFailed: true),
      bugResultDialogForTest(path: path, issueUrl: 'https://x/1'),
    ]) {
      await _pump(t, d);
      // Whatever went wrong online, the local bundle is the thing that always
      // exists — losing sight of it would make a failed upload strictly worse
      // than no upload at all.
      expect(find.text(path), findsOneWidget);
      expect(find.text(_l.btnCopyPath), findsOneWidget);
    }
  });
}
