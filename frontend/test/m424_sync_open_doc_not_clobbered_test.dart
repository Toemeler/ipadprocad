// M424 — "the sync clearly doesn't work, I just synced and still have an
// old version" (issue #44).
//
// The bug report's own log has the shape exactly: a part was OPEN on the
// iPad while the mirror took two newer versions of it from a peer (`took
// ...45453 bytes`), each one correctly left un-adopted into the live editor
// because a document that is open is never reloaded out from under someone
// (see AppState._adoptSynced). Forty seconds later the part was closed — no
// part was open when the bug report itself was captured — and the on-disk
// file was back to being the OLD content.
//
// The cause is upstream of anything sync-specific: AppState.goHome calls
// flushCurrentDocument UNCONDITIONALLY, on every way out of a document, so
// that a sketch merely viewed (never edited) still gets a fresh thumbnail.
// savePart/saveSketch then packed the STAGED copy — read from disk when the
// document was OPENED, before the peer's newer bytes arrived — back over the
// file that sync had just correctly written, silently reverting it. No edit
// was needed to trigger this: opening a document, sitting on it while a sync
// lands, and leaving is enough.
//
// The fix: a save that finds (a) nothing was actually changed in memory
// (`dirty` is false) and (b) the file on disk is no longer the one this
// device staged, backs off instead of committing — the sync's bytes are
// already the truth, and there is nothing of this device's own to save. A
// real edit still saves and wins, exactly as documented.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/display_mode.dart';

Directory _scratch() => Directory.systemTemp.createTempSync('m424');

AppState _app(Directory docs) => AppState()
  ..docsDirForTest = docs
  ..volatileDirsForTest = const [];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('a document open while a sync lands', () {
    late Directory docs;

    setUp(() => docs = _scratch());
    tearDown(() => docs.deleteSync(recursive: true));

    test('is not clobbered back to the old version on exit', () async {
      // This device creates the part and has it open — the baseline version,
      // `showFloor: true` (the default).
      final onThisDevice = _app(docs);
      await onThisDevice.createNamedPart('Bracket');
      expect(onThisDevice.parts['Bracket']!.showFloor, isTrue);

      // A peer edits the SAME document and its bytes land on disk here —
      // exactly what LanSync._apply does when it takes a file from another
      // device. A second AppState instance against the same folder stands in
      // for that peer without needing a real network.
      final peer = _app(docs);
      await peer.openPart('Bracket');
      peer.parts['Bracket']!.showFloor = false;
      peer.parts['Bracket']!.dirty = true;
      await peer.savePart('Bracket');

      // Filesystem mtimes can be coarse; force the on-disk file to read as
      // strictly newer than what `onThisDevice` staged, so the test does not
      // depend on the two writes happening to land in different clock ticks.
      final file = File('${docs.path}/Bracket.ptp');
      file.setLastModifiedSync(
          file.lastModifiedSync().add(const Duration(seconds: 2)));

      // Back on this device: the part is still open (never reloaded — an
      // open document is never pulled out from under someone), so its
      // in-memory copy is still the OLD, `showFloor: true` version. Nothing
      // here was edited.
      expect(onThisDevice.parts['Bracket']!.dirty, isFalse);
      expect(onThisDevice.parts['Bracket']!.showFloor, isTrue,
          reason: 'an open document is never reloaded out from under '
              'someone');

      // Backing out to the gallery must not silently revert the peer's
      // change: flushCurrentDocument (called from goHome) has nothing of
      // THIS device's to save.
      onThisDevice.curTab = 'Bracket';
      onThisDevice.goHome();
      // flushCurrentDocument is fire-and-forget from goHome; give it a turn.
      await Future<void>.delayed(Duration.zero);

      final onDisk = AppState()
        ..docsDirForTest = docs
        ..volatileDirsForTest = const [];
      await onDisk.openPart('Bracket');
      expect(onDisk.parts['Bracket']!.showFloor, isFalse,
          reason: 'the peer\'s version must survive this device\'s exit');
    });

    test('a real edit on the open document still saves and wins', () async {
      final onThisDevice = _app(docs);
      await onThisDevice.createNamedPart('Bracket');

      final peer = _app(docs);
      await peer.openPart('Bracket');
      peer.parts['Bracket']!.showFloor = false;
      peer.parts['Bracket']!.dirty = true;
      await peer.savePart('Bracket');
      final file = File('${docs.path}/Bracket.ptp');
      file.setLastModifiedSync(
          file.lastModifiedSync().add(const Duration(seconds: 2)));

      // This device ALSO changes it locally — a real edit, not just having
      // sat open. That is what `dirty` distinguishes, and it must still win:
      // the guard is for "nothing changed here", not for "an edit lost a
      // race".
      onThisDevice.parts['Bracket']!.displayMode = DisplayMode.rendered;
      onThisDevice.parts['Bracket']!.dirty = true;
      final saved = await onThisDevice.savePart('Bracket');
      expect(saved, isTrue);

      final reread = AppState()
        ..docsDirForTest = docs
        ..volatileDirsForTest = const [];
      await reread.openPart('Bracket');
      expect(reread.parts['Bracket']!.displayMode, DisplayMode.rendered,
          reason: 'a real local edit is a real save, and wins as documented');
    });
  });
}
