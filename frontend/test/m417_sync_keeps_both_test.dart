// M417 — "the syncing is very dangerous now".
//
// It was, and this is the reason. The mirror's conflict rule was one line —
// the newest write wins, per file, by modification time — and that rule cannot
// tell these two situations apart:
//
//   * I have an old version and they saved a new one   -> THEY should win
//   * I edited mine and they edited theirs             -> NOBODY should win
//
// Both look like "their timestamp is larger". So the second case silently
// destroyed one side's work, and which side depended on two clocks that were
// never synchronised.
//
// The fix is a BASE VERSION: the sha of the bytes this device and the group
// last agreed on, written down when a file is taken from a peer or handed to
// one. With it, the two cases are different questions with different answers,
// and no clock is consulted at all. Where both sides have moved on, BOTH
// versions are kept — there is no merge for a B-Rep feature tree, and a
// beginner cannot answer "mine or theirs?" from a filename and a time, but
// they can answer it from two thumbnails they can open and look at.
//
// What is pinned here:
//   * the whole verdict table, including the two cases the old rule could not
//     see, and that a clock alone decides nothing any more;
//   * keeping both: the newer keeps its name, the older is kept beside it,
//     named after the device it was last saved on, and nothing is overwritten
//     before its previous contents are written down;
//   * that BOTH devices reach the same two filenames holding the same two
//     documents — the mirror has to settle, not ping-pong;
//   * a delete never beats an edit, and still sticks when there is nothing to
//     lose;
//   * preferences keep their old rule, because they are merged, not replaced;
//   * the journal survives a restart and does not grow without bound.
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

  /// Writes [text] as the document [name] and returns the manifest entry the
  /// mirror now holds for it.
  SyncEntry local(String name, String text) {
    File('${docs.path}/$name').writeAsStringSync(text);
    LanSync.instance.attachForTest(documents: docs, preferences: prefs);
    return LanSync.instance.localManifestForTest[name]!;
  }

  /// What a peer would offer for [name] holding [text].
  SyncEntry remote(String name, String text, {int? mtimeMs}) => SyncEntry(
      name, text.length, mtimeMs ?? DateTime.now().millisecondsSinceEpoch,
      _shaOf(text));

  setUp(() {
    root = Directory.systemTemp.createTempSync('m417');
    docs = Directory('${root.path}/docs')..createSync();
    prefs = Directory('${root.path}/prefs')..createSync();
    LanSync.instance.attachForTest(documents: docs, preferences: prefs);
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('the verdict table', () {
    test('already the same: nothing happens', () {
      final mine = local('Bracket.ptp', 'a');
      expect(LanSync.instance.verdictFor(remote('Bracket.ptp', 'a')),
          SyncVerdict.skip);
      expect(mine.sha, _shaOf('a'));
    });

    test('nothing here to lose: take it', () {
      expect(LanSync.instance.verdictFor(remote('New.ptp', 'a')),
          SyncVerdict.take);
    });

    test('only THEY moved on: take it', () {
      final mine = local('Bracket.ptp', 'a');
      LanSync.instance.setBaseForTest('Bracket.ptp', mine.sha);
      expect(LanSync.instance.verdictFor(remote('Bracket.ptp', 'b')),
          SyncVerdict.take);
    });

    test('only I moved on: keep mine, and say nothing about theirs', () {
      local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      expect(LanSync.instance.verdictFor(remote('Bracket.ptp', 'agreed')),
          SyncVerdict.skip);
    });

    test('BOTH moved on: keep both', () {
      local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      expect(LanSync.instance.verdictFor(remote('Bracket.ptp', 'theirs')),
          SyncVerdict.fork);
    });

    test('never agreed on anything, and both have one: keep both', () {
      local('Bracket.ptp', 'mine');
      expect(LanSync.instance.verdictFor(remote('Bracket.ptp', 'theirs')),
          SyncVerdict.fork);
    });

    test('the clock decides nothing', () {
      final mine = local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', mine.sha);
      // An hour behind is still an update this device is behind on.
      expect(
          LanSync.instance.verdictFor(
              remote('Bracket.ptp', 'theirs', mtimeMs: mine.mtimeMs - 3600000)),
          SyncVerdict.take);
      // And an hour ahead is still a divergence when both have moved on.
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      expect(
          LanSync.instance.verdictFor(
              remote('Bracket.ptp', 'theirs', mtimeMs: mine.mtimeMs + 3600000)),
          SyncVerdict.fork);
    });
  });

  group('keeping both', () {
    test('the newer keeps its name, the older is kept beside it', () {
      final mine = local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      final theirs =
          remote('Bracket.ptp', 'theirs', mtimeMs: mine.mtimeMs + 60000);
      expect(
          LanSync.instance
              .applyForTest(theirs, _bytes('theirs'), peerName: 'Toms iPad'),
          isTrue);
      // Theirs is newer, so it takes the name...
      expect(File('${docs.path}/Bracket.ptp').readAsStringSync(), 'theirs');
      // ...and MY version is still here, under a name that says whose it is.
      expect(File('${docs.path}/Bracket (this device).ptp').existsSync(),
          isFalse,
          reason: 'named after the device it was saved on, not a placeholder');
      final kept = docs
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .where((n) => n != 'Bracket.ptp')
          .toList();
      expect(kept.length, 1);
      expect(File('${docs.path}/${kept.single}').readAsStringSync(), 'mine');
    });

    test('when MINE is newer it keeps the name and theirs is kept beside it',
        () {
      final mine = local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      final theirs =
          remote('Bracket.ptp', 'theirs', mtimeMs: mine.mtimeMs - 60000);
      expect(
          LanSync.instance
              .applyForTest(theirs, _bytes('theirs'), peerName: 'Toms iPad'),
          isTrue);
      expect(File('${docs.path}/Bracket.ptp').readAsStringSync(), 'mine');
      expect(File('${docs.path}/Bracket (Toms iPad).ptp').readAsStringSync(),
          'theirs');
    });

    test('it is reported, so the gallery can say so', () {
      final mine = local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      LanSync.instance.applyForTest(
          remote('Bracket.ptp', 'theirs', mtimeMs: mine.mtimeMs - 60000),
          _bytes('theirs'),
          peerName: 'Toms iPad');
      final forks = LanSync.instance.recentForks.value;
      expect(forks.length, 1);
      expect(forks.single.original, 'Bracket.ptp');
      expect(forks.single.copy, 'Bracket (Toms iPad).ptp');
      expect(forks.single.owner, 'Toms iPad');
    });

    test('BOTH devices reach the same two files, so the mirror settles', () {
      // This device holds "mine"; the peer holds "theirs" and is newer.
      File('${docs.path}/Bracket.ptp').writeAsStringSync('mine');
      LanSync.instance.attachForTest(
          documents: docs, preferences: prefs, deviceName: 'Studio PC');
      final mine = LanSync.instance.localManifestForTest['Bracket.ptp']!;
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      final theirsEntry =
          remote('Bracket.ptp', 'theirs', mtimeMs: mine.mtimeMs + 60000);
      LanSync.instance.applyForTest(theirsEntry, _bytes('theirs'),
          peerName: 'Toms iPad');
      final here = docs
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();

      // Now the SAME divergence, seen from the peer: it holds "theirs" and is
      // offered "mine", older, from a device called Laptop.
      final other = Directory('${root.path}/other')..createSync();
      final otherPrefs = Directory('${root.path}/otherprefs')..createSync();
      File('${other.path}/Bracket.ptp').writeAsStringSync('theirs');
      LanSync.instance.attachForTest(
          documents: other, preferences: otherPrefs, deviceName: 'Toms iPad');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      LanSync.instance.applyForTest(
          SyncEntry('Bracket.ptp', 4, theirsEntry.mtimeMs - 60000,
              _shaOf('mine')),
          _bytes('mine'),
          peerName: 'Studio PC');
      final there = other
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();

      expect(there, here,
          reason: 'the same two filenames on both devices, or it never settles');
      expect(File('${other.path}/Bracket.ptp').readAsStringSync(), 'theirs');
      expect(File('${docs.path}/Bracket.ptp').readAsStringSync(), 'theirs');
    });

    test('resolving it twice does not make a third copy', () {
      final mine = local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      final theirs =
          remote('Bracket.ptp', 'theirs', mtimeMs: mine.mtimeMs - 60000);
      LanSync.instance
          .applyForTest(theirs, _bytes('theirs'), peerName: 'Toms iPad');
      final after = docs.listSync().length;
      // The peer announces the same version again, as it will.
      expect(LanSync.instance.verdictFor(theirs), SyncVerdict.skip,
          reason: 'the group version is agreed now, so there is nothing to do');
      expect(docs.listSync().length, after);
    });

    test('a device name that would break a path is made safe', () {
      final mine = local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      LanSync.instance.applyForTest(
          remote('Bracket.ptp', 'theirs', mtimeMs: mine.mtimeMs - 60000),
          _bytes('theirs'),
          peerName: 'a/b\\c:d*e?f');
      final kept = docs
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .firstWhere((n) => n != 'Bracket.ptp');
      expect(kept, isNot(contains('/')));
      expect(kept, isNot(contains(r'\')));
      expect(kept, endsWith('.ptp'));
    });
  });

  group('a delete never beats an edit', () {
    test('changed here since we agreed: the file stays', () {
      final mine = local('Bracket.ptp', 'edited here');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      expect(
          LanSync.instance.applyTombForTest(SyncTomb('Bracket.ptp',
              mine.mtimeMs + 60000, _shaOf('agreed'))),
          isFalse);
      expect(File('${docs.path}/Bracket.ptp').existsSync(), isTrue);
    });

    test('holding exactly what was thrown away: it goes', () {
      final mine = local('Bracket.ptp', 'agreed');
      LanSync.instance.setBaseForTest('Bracket.ptp', mine.sha);
      expect(
          LanSync.instance.applyTombForTest(
              SyncTomb('Bracket.ptp', mine.mtimeMs + 60000, mine.sha)),
          isTrue);
      expect(File('${docs.path}/Bracket.ptp').existsSync(), isFalse);
    });

    test('a delete this device makes carries the version it removed', () {
      final mine = local('Bracket.ptp', 'a');
      File('${docs.path}/Bracket.ptp').deleteSync();
      final gone = LanSync.instance.noticeDeletesForTest();
      expect(gone.single.sha, mine.sha);
    });

    test('and that sha survives a restart of the app', () {
      local('Bracket.ptp', 'a');
      File('${docs.path}/Bracket.ptp').deleteSync();
      final sent = LanSync.instance.noticeDeletesForTest().single;
      // A fresh attach is what a relaunch looks like.
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      expect(LanSync.instance.tombsForTest.containsKey('Bracket.ptp'), isTrue);
      expect(sent.sha, isNotNull);
    });
  });

  group('the agreed-version journal', () {
    test('taking a file from a peer records the agreement', () {
      final e = remote('Bracket.ptp', 'theirs');
      LanSync.instance.applyForTest(e, _bytes('theirs'));
      expect(LanSync.instance.baseForTest['Bracket.ptp'], e.sha);
    });

    test('handing one over records it too', () {
      final mine = local('Bracket.ptp', 'mine');
      LanSync.instance.noteHandedOverForTest('Bracket.ptp', mine.sha);
      expect(LanSync.instance.baseForTest['Bracket.ptp'], mine.sha);
    });

    test('two devices already holding the same bytes have agreed', () {
      final mine = local('Bracket.ptp', 'same');
      LanSync.instance.noteAgreementForTest(remote('Bracket.ptp', 'same'));
      expect(LanSync.instance.baseForTest['Bracket.ptp'], mine.sha);
    });

    test('it survives a restart', () {
      final mine = local('Bracket.ptp', 'a');
      LanSync.instance.noteHandedOverForTest('Bracket.ptp', mine.sha);
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      expect(LanSync.instance.baseForTest['Bracket.ptp'], mine.sha);
    });

    test('it does not grow with everything that ever passed through', () {
      final mine = local('Bracket.ptp', 'a');
      LanSync.instance.noteHandedOverForTest('Bracket.ptp', mine.sha);
      LanSync.instance.setBaseForTest('LongGone.ptp', _shaOf('x'));
      LanSync.instance.pruneBaseForTest();
      expect(LanSync.instance.baseForTest.keys, ['Bracket.ptp']);
    });

    test('it is never mirrored as a file', () {
      final mine = local('Bracket.ptp', 'a');
      LanSync.instance.noteHandedOverForTest('Bracket.ptp', mine.sha);
      expect(File('${prefs.path}/sync-base.json').existsSync(), isTrue);
      expect(LanSync.instance.scanForTest().keys,
          isNot(contains(contains('sync-base'))));
    });
  });

  group('preferences are not documents', () {
    test('they are merged, so they are never kept twice', () {
      File('${prefs.path}/settings.json').writeAsStringSync('{"theme":"dark"}');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      final v = LanSync.instance.verdictFor(SyncEntry(
          'settings/settings.json',
          20,
          DateTime.now().millisecondsSinceEpoch + 60000,
          _shaOf('{"theme":"light"}')));
      expect(v, isNot(SyncVerdict.fork));
    });
  });
}
