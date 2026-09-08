// M388 — a document that arrives from another device has to appear WITHOUT
// anybody touching the screen.
//
// "The sync only updates when I open a part and go back to the menu, or if I
// close and open the app. But not if I'm just in the menu."
//
// The mirror was working the whole time: the file lands, `refreshSaved`
// rebuilds `library` and `saved`, and then nothing tells the widget tree. The
// gallery goes on drawing the list it built at launch until something else
// rebuilds the route — opening a part and coming back, or a relaunch — at
// which point the document appears and the sync looks like it only runs on
// navigation.
//
// It survived everywhere else because every other caller of `refreshSaved`
// follows it with a `notifyListeners()` of its own; all fifteen of them are
// reached by somebody tapping something. Sync is the one path where nobody
// taps anything, so it was the one path with no repaint.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('m388'));
  tearDown(() => dir.deleteSync(recursive: true));

  AppState appFor(Directory d) => AppState()..docsDirForTest = d;

  test('refreshSaved announces the change itself', () async {
    final app = appFor(dir);
    var notified = 0;
    app.addListener(() => notified++);

    File('${dir.path}/Bracket.ptp').writeAsStringSync('x');
    await app.refreshSaved();

    expect(app.saved.map((s) => s.name), contains('Bracket'),
        reason: 'the document is in the gallery list');
    expect(notified, greaterThan(0),
        reason: 'and the gallery was told, without anyone tapping anything');
  });

  // The shape the bug actually had: a file appears on disk while the app sits
  // on the gallery, exactly as the mirror writes one. Nobody navigates.
  test('a document appearing on disk reaches the gallery on its own',
      () async {
    final app = appFor(dir);
    await app.refreshSaved();
    expect(app.saved, isEmpty);

    var notified = 0;
    app.addListener(() => notified++);

    // What LanSync._apply does: write the file, then tell the app.
    File('${dir.path}/FromTheiPad.ptp').writeAsStringSync('x');
    await app.refreshSaved();

    expect(notified, greaterThan(0));
    expect(app.saved.map((s) => s.name), contains('FromTheiPad'));
  });

  test('a document deleted on another device leaves the gallery too', () async {
    final f = File('${dir.path}/Gone.ptp')..writeAsStringSync('x');
    final app = appFor(dir);
    await app.refreshSaved();
    expect(app.saved.map((s) => s.name), contains('Gone'));

    var notified = 0;
    app.addListener(() => notified++);

    f.deleteSync(); // what an applied tombstone does
    await app.refreshSaved();

    expect(notified, greaterThan(0));
    expect(app.saved.map((s) => s.name), isNot(contains('Gone')));
  });
}
