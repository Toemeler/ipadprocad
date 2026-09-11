// M425 — "somehow one document went away on my iphone after i closed it on
// ipad, but on ipad it is there so it should be there here to but it isnt"
// (issue #47).
//
// It really did go away, and the log says so twice. From the iPhone's report:
//
//   14:20:47  asking localhost for Part1.ptp
//   14:20:47  took Part1.ptp (321 bytes)
//   ...                                     (the drawing, arriving as it grew)
//   14:21:27  took Part1.ptp (45101 bytes)
//   14:21:29  Bonjour up: _prototypesync._tcp on 47821
//   14:21:29  removed Part1.ptp — deleted on another device
//
// Two seconds after the last save, a re-pair delivered a full manifest and the
// brand-new document was deleted by a tombstone for a DIFFERENT document that
// had carried the same name weeks earlier. The same three lines appear again
// on the previous evening, so it had already happened once unnoticed.
//
// THREE FAULTS LINED UP, and every one of them had to be there:
//
//   1. New documents are named by counting: `Part1`, `Part2`, … So the name of
//      a document you delete is the first name handed out again. A tombstone
//      for `Part1.ptp` is not an obscure record, it is the one most likely to
//      collide with something new.
//
//   2. A tombstone was only ever forgotten when the file came back FROM A PEER
//      ([LanSync._apply]). Created here, at a path this device remembered
//      deleting, the record stood — so the device holding the live document
//      went on announcing its death in every manifest it sent.
//
//   3. And that announcement went out BARE. M417 had added the sha of the
//      version that was thrown away — the whole point of which is that a peer
//      can answer "have I got anything to lose?" — but the journal stored
//      `Map<String, int>`, so the sha survived exactly one hop and every
//      re-announcement after it was a fact nobody could check. Without it the
//      rule fell back to "do I hold what the group agreed on?", which is TRUE
//      OF EVERY FILE that arrived from a peer and has not been touched since.
//      It is not evidence about this tombstone at all, and the iPhone — which
//      had just taken the new Part1 and so held exactly the agreed version —
//      read it as permission to delete.
//
// What is pinned here:
//   * the report, end to end: a stale bare tombstone does not remove a
//     document created after it, even when the base matches exactly;
//   * that the journal keeps the sha, over the wire and over a restart;
//   * that a document which exists again here is no longer announced as
//     deleted;
//   * that a real delete still lands, still sticks, and still loses to an
//     edit — the M417/M420 rules the fix must not have traded away;
//   * that a journal written in the old shape is still read.
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
    root = Directory.systemTemp.createTempSync('m425');
    docs = Directory('${root.path}/docs')..createSync();
    prefs = Directory('${root.path}/prefs')..createSync();
    LanSync.instance.attachForTest(documents: docs, preferences: prefs);
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('the report', () {
    test('a stale tombstone does not remove a document made after it', () {
      // The iPad, weeks ago: Part1 existed and was deleted. That record is
      // still in every device's journal, and the journal keeps a month.
      final old = DateTime.now()
          .subtract(const Duration(days: 20))
          .millisecondsSinceEpoch;

      // The iPhone, today: a NEW document arrives from the iPad, under the
      // same name, because new documents are named by counting.
      final fresh = SyncEntry('Part1.ptp', 6, DateTime.now().millisecondsSinceEpoch,
          _shaOf('drawn today'));
      expect(LanSync.instance.applyForTest(fresh, _bytes('drawn today')), isTrue);
      expect(File('${docs.path}/Part1.ptp').existsSync(), isTrue);

      // THE EXACT CONDITION THAT FIRED. Having just taken the file from a
      // peer, this device holds precisely the version the group agreed on —
      // which the old rule read as "nothing to lose".
      expect(LanSync.instance.baseForTest['Part1.ptp'], fresh.sha);

      // And now the stale record arrives, re-announced by a peer that has
      // never forgotten it, with no sha because the journal never kept one.
      expect(LanSync.instance.applyTombForTest(SyncTomb('Part1.ptp', old)),
          isFalse,
          reason: 'a document made after the deletion outlives it');
      expect(File('${docs.path}/Part1.ptp').readAsStringSync(), 'drawn today');
    });

    test('the same record with its sha is harmless on sight', () {
      final fresh = SyncEntry('Part1.ptp', 6,
          DateTime.now().millisecondsSinceEpoch, _shaOf('drawn today'));
      LanSync.instance.applyForTest(fresh, _bytes('drawn today'));
      // The version that was thrown away was some older Part1 — not this one,
      // and the sha says so without any clock being consulted.
      expect(
          LanSync.instance.applyTombForTest(SyncTomb('Part1.ptp',
              DateTime.now().millisecondsSinceEpoch + 60000,
              _shaOf('the old Part1'))),
          isFalse);
      expect(File('${docs.path}/Part1.ptp').existsSync(), isTrue);
    });

    test('a document that is here again stops being announced as deleted', () {
      final f = File('${docs.path}/Part1.ptp')..writeAsStringSync('first');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      f.deleteSync();
      LanSync.instance.noticeDeletesForTest();
      expect(LanSync.instance.tombsForTest.keys, ['Part1.ptp']);

      // The user makes a new document. It is called Part1 again, because the
      // old one is gone and the counter starts from what exists.
      File('${docs.path}/Part1.ptp').writeAsStringSync('second');
      LanSync.instance.noticeResurrectionsForTest();

      expect(LanSync.instance.tombsForTest, isEmpty,
          reason: 'this device holds the document; it cannot also be telling '
              'the group that it is deleted');
      expect(LanSync.instance.tombListForTest(), isEmpty);
    });
  });

  group('the journal keeps the whole tombstone', () {
    test('what is announced still carries the sha', () {
      final mine = local('Bracket.ptp', 'a');
      File('${docs.path}/Bracket.ptp').deleteSync();
      final gone = LanSync.instance.noticeDeletesForTest();
      expect(gone.single.sha, mine.sha);

      // THE REGRESSION. This list is rebuilt from the journal, and it used to
      // be rebuilt without the sha — so the device that did the deleting told
      // the truth once and then announced a bare record for a month.
      final announced = LanSync.instance.tombListForTest();
      expect(announced.single.path, 'Bracket.ptp');
      expect(announced.single.sha, mine.sha);
    });

    test('and still carries it after a restart', () {
      final mine = local('Bracket.ptp', 'a');
      File('${docs.path}/Bracket.ptp').deleteSync();
      LanSync.instance.noticeDeletesForTest();

      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      expect(LanSync.instance.tombListForTest().single.sha, mine.sha);
    });

    test('a bare one is filled in from what it actually removed', () {
      final mine = local('Bracket.ptp', 'a');
      // An older peer deletes it and can only say when, not what.
      expect(
          LanSync.instance.applyTombForTest(
              SyncTomb('Bracket.ptp', mine.mtimeMs + 60000)),
          isTrue);
      // What this device passes on is better than what it was told: the
      // version it removed is the version that was deleted.
      expect(LanSync.instance.tombListForTest().single.sha, mine.sha);
    });

    test('the old journal shape is still read', () {
      final when = DateTime.now().millisecondsSinceEpoch;
      File('${prefs.path}/sync-deleted.json')
          .writeAsStringSync('{"Old.ptp":$when}');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      expect(LanSync.instance.tombsForTest.keys, ['Old.ptp']);
      expect(LanSync.instance.tombsForTest['Old.ptp']!.deletedAtMs, when);
      expect(LanSync.instance.tombsForTest['Old.ptp']!.sha, isNull);
    });

    test('a stale one is still forgotten', () {
      final old = DateTime.now()
          .subtract(const Duration(days: 40))
          .millisecondsSinceEpoch;
      File('${prefs.path}/sync-deleted.json').writeAsStringSync(jsonEncode({
        'Old.ptp': {'d': old, 'h': _shaOf('x')},
        'Recent.ptp': {'d': DateTime.now().millisecondsSinceEpoch},
      }));
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      expect(LanSync.instance.tombsForTest.keys, ['Recent.ptp']);
    });
  });

  group('what a delete must still do', () {
    test('a real one still removes the file', () {
      final mine = local('Bracket.ptp', 'a');
      expect(
          LanSync.instance.applyTombForTest(
              SyncTomb('Bracket.ptp', mine.mtimeMs + 60000, mine.sha)),
          isTrue);
      expect(File('${docs.path}/Bracket.ptp').existsSync(), isFalse);
    });

    test('and still sticks when the copy comes back', () {
      final mine = local('Bracket.ptp', 'a');
      LanSync.instance.applyTombForTest(
          SyncTomb('Bracket.ptp', mine.mtimeMs + 60000, mine.sha));
      expect(
          LanSync.instance.wantsForTest(
              SyncEntry('Bracket.ptp', 1, mine.mtimeMs, _shaOf('a'))),
          isFalse,
          reason: 'the very version that was deleted is not news');
    });

    test('a document saved again after the delete still comes back', () {
      final mine = local('Bracket.ptp', 'a');
      LanSync.instance.applyTombForTest(
          SyncTomb('Bracket.ptp', mine.mtimeMs + 60000, mine.sha));
      final revived =
          SyncEntry('Bracket.ptp', 1, mine.mtimeMs + 120000, _shaOf('b'));
      expect(LanSync.instance.wantsForTest(revived), isTrue);
      expect(LanSync.instance.applyForTest(revived, _bytes('b')), isTrue);
      expect(LanSync.instance.tombsForTest.containsKey('Bracket.ptp'), isFalse);
    });

    test('a delete still loses to an edit made here', () {
      final mine = local('Bracket.ptp', 'edited here');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      expect(
          LanSync.instance.applyTombForTest(SyncTomb(
              'Bracket.ptp', mine.mtimeMs + 60000, _shaOf('agreed'))),
          isFalse);
      expect(File('${docs.path}/Bracket.ptp').existsSync(), isTrue);
    });

    test('a bare tombstone still applies to the version it is about', () {
      // The upgrade path: an old peer, an old journal, nothing to compare —
      // the timestamp heuristic is kept rather than making documents
      // undeletable, but it now has to be met as well as the base.
      final mine = local('Bracket.ptp', 'a');
      LanSync.instance.setBaseForTest('Bracket.ptp', mine.sha);
      expect(
          LanSync.instance
              .applyTombForTest(SyncTomb('Bracket.ptp', mine.mtimeMs + 60000)),
          isTrue);
      expect(File('${docs.path}/Bracket.ptp').existsSync(), isFalse);
    });
  });
}
