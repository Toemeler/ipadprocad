// M420/M421 — "I want a clear all changes button but also when I longpress a
// menu item a clear changes button only for this item" (#43).
//
// DISCARDING IS THE ONLY DESTRUCTION IN THE WHOLE MIRROR THAT THE USER ASKS
// FOR. Everything else it does is either additive or, since M417, keeps both
// versions. So the three rules that make this safe enough to put in front of a
// beginner are the ones worth pinning:
//
//   * it REFUSES when no other device is reachable. There is nothing to go
//     back to, and swapping somebody's work for nothing is the one outcome
//     this must never have;
//   * the previous bytes are backed up first, so even the asked-for
//     destruction is undoable for a month;
//   * it only ever touches a document with an agreed version behind it. One
//     that has never left this device has nothing to be discarded in favour
//     of, and dropping it would be a delete wearing another name.
//
// M421's drawer is the net under all of it — a copy of everything the mirror
// replaced or removed, and the way back out.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/sync/lan_sync.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));
String _shaOf(String s) => sha256.convert(_bytes(s)).toString();

void main() {
  late Directory root;
  late Directory docs;
  late Directory prefs;

  SyncEntry local(String name, String text) {
    File('${docs.path}/$name').writeAsStringSync(text);
    LanSync.instance.attachForTest(documents: docs, preferences: prefs);
    return LanSync.instance.localManifestForTest[name]!;
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('m420');
    docs = Directory('${root.path}/docs')..createSync();
    prefs = Directory('${root.path}/prefs')..createSync();
    LanSync.instance.attachForTest(documents: docs, preferences: prefs);
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('what counts as a local change', () {
    test('a document changed since the two devices agreed', () {
      local('Bracket.ptp', 'edited');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      expect(LanSync.instance.hasLocalChanges('Bracket.ptp'), isTrue);
      expect(LanSync.instance.divergentDocuments, ['Bracket.ptp']);
    });

    test('one that matches the agreed version does not', () {
      final mine = local('Bracket.ptp', 'agreed');
      LanSync.instance.setBaseForTest('Bracket.ptp', mine.sha);
      expect(LanSync.instance.hasLocalChanges('Bracket.ptp'), isFalse);
      expect(LanSync.instance.divergentDocuments, isEmpty);
    });

    test('and one that has never left this device does NOT either', () {
      local('Brandnew.ptp', 'only here');
      expect(LanSync.instance.hasLocalChanges('Brandnew.ptp'), isFalse,
          reason: 'there is nothing to go back to — discarding it would be a '
              'delete wearing another name');
      expect(LanSync.instance.divergentDocuments, isEmpty);
    });

    test('preferences are never offered: they are merged, not replaced', () {
      File('${prefs.path}/settings.json').writeAsStringSync('{"a":1}');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      LanSync.instance
          .setBaseForTest('settings/settings.json', _shaOf('something else'));
      expect(LanSync.instance.divergentDocuments, isEmpty);
      expect(LanSync.instance.hasLocalChanges('settings/settings.json'),
          isFalse);
    });
  });

  group('discarding', () {
    test('REFUSES when no other device is reachable', () async {
      local('Bracket.ptp', 'edited');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      final done = await LanSync.instance
          .discardForTest(['Bracket.ptp'], pretendPeer: false);
      expect(done, isEmpty);
      expect(File('${docs.path}/Bracket.ptp').readAsStringSync(), 'edited',
          reason: 'the work is still here, which is the whole point');
    });

    test('gives up the document and asks for the group version back',
        () async {
      local('Bracket.ptp', 'edited');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      final done = await LanSync.instance
          .discardForTest(['Bracket.ptp'], pretendPeer: true);
      expect(done, ['Bracket.ptp']);
      expect(File('${docs.path}/Bracket.ptp').existsSync(), isFalse);
      // No tombstone: this is not a deletion, and one would tell the other
      // devices to throw the document away everywhere.
      expect(LanSync.instance.tombsForTest.containsKey('Bracket.ptp'), isFalse);
      // And no agreed version, so the copy coming back is TAKEN rather than
      // refused as one we threw away on purpose.
      expect(LanSync.instance.baseForTest.containsKey('Bracket.ptp'), isFalse);
      expect(
          LanSync.instance.verdictFor(
              SyncEntry('Bracket.ptp', 6, 1, _shaOf('agreed'))),
          SyncVerdict.take);
    });

    test('the version it gave up is kept, so even this is undoable', () async {
      local('Bracket.ptp', 'edited');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      await LanSync.instance
          .discardForTest(['Bracket.ptp'], pretendPeer: true);
      final kept = LanSync.instance.backups();
      expect(kept.length, 1);
      expect(kept.single.path, 'Bracket.ptp');
      expect(kept.single.reason, 'discarded');
      expect(kept.single.file.readAsStringSync(), 'edited');
    });

    test('it leaves alone what it was not asked about', () async {
      local('Bracket.ptp', 'edited');
      File('${docs.path}/Other.ptp').writeAsStringSync('mine');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      LanSync.instance.setBaseForTest('Other.ptp', _shaOf('agreed too'));
      await LanSync.instance
          .discardForTest(['Bracket.ptp'], pretendPeer: true);
      expect(File('${docs.path}/Other.ptp').existsSync(), isTrue);
    });

    test('and a document with nothing to go back to is skipped', () async {
      local('Brandnew.ptp', 'only here');
      final done = await LanSync.instance
          .discardForTest(['Brandnew.ptp'], pretendPeer: true);
      expect(done, isEmpty);
      expect(File('${docs.path}/Brandnew.ptp').existsSync(), isTrue);
    });
  });

  group('the drawer', () {
    test('a version replaced by a peer is kept', () {
      final mine = local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', mine.sha);
      LanSync.instance.applyForTest(
          SyncEntry('Bracket.ptp', 6, DateTime.now().millisecondsSinceEpoch,
              _shaOf('theirs')),
          _bytes('theirs'));
      expect(File('${docs.path}/Bracket.ptp').readAsStringSync(), 'theirs');
      final kept = LanSync.instance.backups();
      expect(kept.single.reason, 'replaced');
      expect(kept.single.file.readAsStringSync(), 'mine');
    });

    test('so is one removed by a delete from another device', () {
      final mine = local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', mine.sha);
      LanSync.instance.applyTombForTest(
          SyncTomb('Bracket.ptp', mine.mtimeMs + 60000, mine.sha));
      expect(File('${docs.path}/Bracket.ptp').existsSync(), isFalse);
      final kept = LanSync.instance.backups();
      expect(kept.single.reason, 'removed');
      expect(kept.single.file.readAsStringSync(), 'mine');
    });

    test('restoring puts it back as a SAVE, not as a rewind', () {
      final mine = local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', mine.sha);
      LanSync.instance.applyForTest(
          SyncEntry('Bracket.ptp', 6, DateTime.now().millisecondsSinceEpoch,
              _shaOf('theirs')),
          _bytes('theirs'));
      final kept =
          LanSync.instance.backups().firstWhere((b) => b.reason == 'replaced');
      expect(LanSync.instance.restore(kept), isTrue);
      expect(File('${docs.path}/Bracket.ptp').readAsStringSync(), 'mine');
      // No agreed version afterwards: this is now THIS device's newest
      // version and the next announcement carries it to the others. Anything
      // else and the group would simply send the replacement straight back,
      // which looks like an undo that undid itself.
      expect(LanSync.instance.baseForTest.containsKey('Bracket.ptp'), isFalse);
    });

    test('an undo can itself be undone', () {
      final mine = local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', mine.sha);
      LanSync.instance.applyForTest(
          SyncEntry('Bracket.ptp', 6, DateTime.now().millisecondsSinceEpoch,
              _shaOf('theirs')),
          _bytes('theirs'));
      final replaced =
          LanSync.instance.backups().firstWhere((b) => b.reason == 'replaced');
      LanSync.instance.restore(replaced);
      // The version the restore displaced is in the drawer too.
      final all = LanSync.instance.backups();
      expect(all.length, 2);
      expect(all.any((b) => b.file.readAsStringSync() == 'theirs'), isTrue);
    });

    test('it is newest first, and never mirrored', () {
      local('Bracket.ptp', 'a');
      LanSync.instance.backup('Bracket.ptp', 'replaced');
      File('${docs.path}/Bracket.ptp').writeAsStringSync('b');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      LanSync.instance.backup('Bracket.ptp', 'replaced');
      final all = LanSync.instance.backups();
      expect(all.length, greaterThanOrEqualTo(1));
      for (var i = 1; i < all.length; i++) {
        expect(all[i - 1].at.isBefore(all[i].at), isFalse);
      }
      expect(LanSync.instance.scanForTest().keys,
          isNot(contains(contains('sync-backup'))));
    });

    test('backing up something that is not there is still a safe answer', () {
      expect(LanSync.instance.backup('Gone.ptp', 'removed'), isTrue,
          reason: 'the caller is asking "is it safe to go ahead", and it is');
    });

    test('the document name drops the extension for anything user-facing', () {
      local('Bracket.ptp', 'a');
      LanSync.instance.backup('Bracket.ptp', 'replaced');
      expect(LanSync.instance.backups().single.documentName, 'Bracket',
          reason: 'the gallery never shows an extension and this list is the '
              'one place that must not start');
    });
  });
}
