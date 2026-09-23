// M462 — "i cant really delete part 1 they always respawn and copy
// themselves" (issue #88).
//
// Build c271cd9, so M445's stable ids and M446's stale-manifest guard were
// both on the iPad. The log still says what happened, and it happened every
// five seconds:
//
//   10:25:17  picked "delete" on gallery/Part1
//   10:25:19  deleted here: Part1.ptp
//   10:25:20  took Part1.ptp (186815 bytes)
//   ...
//   10:26:00  Part1.ptp was changed here and on localhost — both kept, the
//             older one as Part1 (localhost) 3.ptp
//
// "cloud: cycle: 1 in, 10 held, 1 kept-both, 4 device(s)" — and there WERE no
// other devices running. The four were manifests: three from earlier launches
// of this same iPad, when every launch minted a new id, and one from the
// person's other iOS device, all "localhost", none of them ever to be written
// again. Two rules turned those four snapshots into a machine for undoing
// deletes and making copies:
//
//   1. A DELETE ONLY RECOGNISED THE VERSION IT DELETED. Any other version on
//      offer read as "edited elsewhere after the delete" and was taken back.
//      A snapshot holds OLDER versions, so every delete came straight back.
//   2. M423'S BASE COMPARISON ASSUMED BOTH SIDES SPOKE AT THE SAME MOMENT. A
//      manifest is read hours after it is written, and meanwhile the reader
//      has moved its own base on — uploading a version counts as handing it
//      over. So a device that had merely been switched off read as "we never
//      agreed", and was forked. On every cycle, because a snapshot's base
//      never moves.
//
// The second is not specific to dead launches. It is what an ordinary day
// looks like — the desktop off, the iPad editing — and it is the generator
// behind #86's copies as well.
//
// THE FIX IS A VERSION VECTOR per document (see `SyncClock`): each device
// counts its own edits, and a version carries the counts of everything it was
// built on. One vector covering another is a version that has SEEN the other,
// however late either was read. Behind is skipped, ahead is taken, and only
// two histories that each have something the other lacks are kept twice —
// once, because the resolution covers both. A tombstone carries one too, so a
// delete wins over every version it had seen and still loses to an edit it
// had not (M417).
//
// And the cloud stops reading manifests from builds that minted a new id per
// launch: they are what nothing will ever update. The collector removes them
// a day after they were last written.
//
// What is pinned here:
//   * the vector itself;
//   * the report, as verdicts: a switched-off device is behind, not in
//     conflict; a delete stays deleted while an older copy is still offered;
//     the device that was behind applies the delete when it comes back; an
//     edit the delete never saw still wins;
//   * keeping both happens ONCE, and the other device takes the resolution;
//   * #47 still holds, now even when the new document's bytes are the old
//     one's;
//   * a restore from the drawer still travels;
//   * a peer that cannot count, or two vectors that say nothing, get the old
//     rule unchanged;
//   * the journal: survives a restart, seeds itself on the upgrade, is never
//     mirrored, follows the gallery;
//   * whole cloud cycles against a stand-in bucket: #88's four dead manifests
//     change nothing; the switched-off desktop, end to end; a real conflict
//     kept once on both devices; the old manifests collected after a day;
//     an upgraded device rewriting its own; a dropped connection retried.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prototype/sync/b2_signer.dart';
import 'package:prototype/sync/cloud_sync.dart';
import 'package:prototype/sync/lan_sync.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));
String _shaOf(String s) => sha256.convert(_bytes(s)).toString();

/// One install: its own documents, its own preferences — and therefore its
/// own device id, which `attachForTest` mints on the first attach.
class _Device {
  _Device(Directory root, this.name)
      : docs = Directory('${root.path}/$name/docs')..createSync(recursive: true),
        prefs = Directory('${root.path}/$name/prefs')
          ..createSync(recursive: true);

  final String name;
  final Directory docs;
  final Directory prefs;

  /// Makes this the device the mirror is running as.
  void use() => LanSync.instance
      .attachForTest(documents: docs, preferences: prefs, deviceName: name);

  File file(String n) => File('${docs.path}/$n');

  /// Saves [text] as [n] and lets the mirror notice, the way a cycle does.
  void save(String n, String text) {
    file(n).writeAsStringSync(text);
    LanSync.instance.mirrorState();
  }

  /// Deletes [n] and lets the mirror notice.
  void delete(String n) {
    file(n).deleteSync();
    LanSync.instance.mirrorState();
  }

  List<String> get names => docs
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.ptp'))
      .toList()
    ..sort();
}

/// The entry as a peer too old to count would have sent it.
SyncEntry _uncounted(SyncEntry e) =>
    SyncEntry(e.path, e.size, e.mtimeMs, e.sha, base: e.base);

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('m462'));
  tearDown(() {
    CloudSync.instance.resetForTest();
    root.deleteSync(recursive: true);
  });

  group('the vector', () {
    test('compares from the first side', () {
      expect(SyncClock.compare({'a': 1}, {'a': 1}), SyncOrder.same);
      expect(SyncClock.compare({'a': 1}, {'a': 2}), SyncOrder.before);
      expect(SyncClock.compare({'a': 2}, {'a': 1}), SyncOrder.after);
      expect(SyncClock.compare({'a': 2}, {'b': 1}), SyncOrder.concurrent);
      expect(SyncClock.compare({}, {'b': 1}), SyncOrder.before);
      expect(SyncClock.compare({'a': 1, 'b': 1}, {'b': 1}), SyncOrder.after);
      expect(SyncClock.compare({}, {}), SyncOrder.same);
    });

    test('merges, counts and covers', () {
      expect(SyncClock.merge({'a': 2, 'b': 1}, {'b': 3, 'c': 1}),
          {'a': 2, 'b': 3, 'c': 1});
      expect(SyncClock.bump({'a': 2}, 'a'), {'a': 3});
      expect(SyncClock.bump({'a': 2}, 'b'), {'a': 2, 'b': 1});
      expect(SyncClock.covers({'a': 2, 'b': 1}, {'a': 1}), isTrue);
      expect(SyncClock.covers({'a': 1}, {'a': 1}), isTrue);
      expect(SyncClock.covers({'a': 1}, {'b': 1}), isFalse);
    });

    test('one read from another device is bounded and cleaned', () {
      expect(SyncClock.parse(null), isNull,
          reason: 'no vector at all is a peer too old to count');
      expect(SyncClock.parse('x'), isNull);
      expect(SyncClock.parse(<String, Object?>{}), isEmpty,
          reason: 'and an empty one is not the same thing');
      expect(
          SyncClock.parse({'a': 2, 'b': 0, 'c': -1, 'd': 'x', '': 3, 'e': 1.9}),
          {'a': 2, 'e': 1});
      final huge = {for (var i = 0; i < 500; i++) 'd$i': i + 1};
      expect(SyncClock.parse(huge)!.length, SyncClock.maxDevices);
    });

    test('crosses the wire, and absent stays absent', () {
      const e = SyncEntry('P.ptp', 1, 2, 'h', base: 'b', clock: {'x': 3});
      expect(SyncEntry.fromJson(jsonDecode(jsonEncode(e.toJson())))!.clock,
          {'x': 3});
      const bare = SyncEntry('P.ptp', 1, 2, 'h');
      expect(bare.toJson().containsKey('v'), isFalse);
      expect(SyncEntry.fromJson(bare.toJson())!.clock, isNull);
      const empty = SyncEntry('P.ptp', 1, 2, 'h', clock: {});
      expect(SyncEntry.fromJson(jsonDecode(jsonEncode(empty.toJson())))!.clock,
          isEmpty);
      const t = SyncTomb('P.ptp', 5, 'h', {'x': 4});
      expect(SyncTomb.fromJson(jsonDecode(jsonEncode(t.toJson())))!.clock,
          {'x': 4});
      expect(SyncTomb.fromJson(const SyncTomb('P.ptp', 5).toJson())!.clock,
          isNull);
    });
  });

  group('#88, as verdicts', () {
    late _Device ipad;
    late _Device desktop;
    late SyncEntry fromDesktop;

    // The desktop makes Part1 and uploads it, and is then switched off: from
    // here on its manifest says the same thing for ever. The iPad takes it
    // and goes on editing, uploading every save.
    setUp(() {
      ipad = _Device(root, 'iPad');
      desktop = _Device(root, 'Desktop');
      desktop.use();
      desktop.save('Part1.ptp', 'v1');
      LanSync.instance.noteHandedOverForTest('Part1.ptp', _shaOf('v1'));
      fromDesktop = LanSync.instance.outgoingForTest('Part1.ptp');
      expect(fromDesktop.clock, isNotEmpty);

      ipad.use();
      expect(
          LanSync.instance
              .applyForTest(fromDesktop, _bytes('v1'), peerName: 'Desktop'),
          isTrue);
      for (final v in ['v2', 'v3']) {
        ipad.save('Part1.ptp', v);
        LanSync.instance.noteHandedOverForTest('Part1.ptp', _shaOf(v));
      }
    });

    test('a device that was switched off is behind, not in conflict', () {
      expect(LanSync.instance.verdictFor(fromDesktop), SyncVerdict.skip);
      // THE ROOT CAUSE, kept visible. Read by the old rule — the base the
      // desktop published against the base the iPad has moved on to by
      // uploading — this is "we never agreed", and it forked. Every cycle.
      expect(LanSync.instance.verdictFor(_uncounted(fromDesktop)),
          SyncVerdict.fork);
    });

    test('and it takes the edit when it comes back, rather than a copy', () {
      final fromIpad = LanSync.instance.outgoingForTest('Part1.ptp');
      desktop.use();
      expect(LanSync.instance.verdictFor(fromIpad), SyncVerdict.take);
      expect(LanSync.instance.verdictFor(_uncounted(fromIpad)),
          SyncVerdict.fork,
          reason: 'the same misreading, from the other side');
    });

    test('a delete stays deleted while an older copy is still offered', () {
      ipad.delete('Part1.ptp');
      expect(LanSync.instance.tombsForTest.containsKey('Part1.ptp'), isTrue);
      // THE REPORT. The switched-off desktop still offers v1 — not the
      // version that was deleted (v3), so the old rule took it back.
      expect(LanSync.instance.verdictFor(fromDesktop), SyncVerdict.skip);
      expect(LanSync.instance.verdictFor(_uncounted(fromDesktop)),
          SyncVerdict.take,
          reason: 'what #88 did, a second after every delete');
      expect(ipad.file('Part1.ptp').existsSync(), isFalse);
    });

    test('and the device that was behind applies the delete on its return',
        () {
      ipad.delete('Part1.ptp');
      final tomb = LanSync.instance.tombListForTest().single;
      desktop.use();
      expect(LanSync.instance.applyTombForTest(tomb), isTrue,
          reason: 'it holds a version the delete had seen');
      expect(desktop.file('Part1.ptp').existsSync(), isFalse);
      // It is in the drawer all the same (M421).
      expect(LanSync.instance.backups().map((b) => b.path), contains('Part1.ptp'));
    });

    test('an edit the delete never saw still brings the document back', () {
      ipad.delete('Part1.ptp');
      final tomb = LanSync.instance.tombListForTest().single;
      // The desktop was not off after all: it edited its v1.
      desktop.use();
      desktop.save('Part1.ptp', 'edited on the desktop');
      final edited = LanSync.instance.outgoingForTest('Part1.ptp');
      expect(LanSync.instance.applyTombForTest(tomb), isFalse,
          reason: 'a delete never beats an edit it had not seen (M417)');
      expect(desktop.file('Part1.ptp').readAsStringSync(),
          'edited on the desktop');
      ipad.use();
      expect(LanSync.instance.verdictFor(edited), SyncVerdict.take);
    });
  });

  group('keeping both happens once', () {
    late _Device ipad;
    late _Device desktop;
    late SyncEntry fromDesktop;

    setUp(() {
      ipad = _Device(root, 'iPad');
      desktop = _Device(root, 'Desktop');
      desktop.use();
      desktop.save('Part1.ptp', 'made on the desktop');
      fromDesktop = LanSync.instance.outgoingForTest('Part1.ptp');
      ipad.use();
      ipad.save('Part1.ptp', 'made on the iPad');
    });

    test('two histories that each have something the other lacks: both kept',
        () {
      expect(LanSync.instance.verdictFor(fromDesktop), SyncVerdict.fork);
      expect(
          LanSync.instance.applyForTest(fromDesktop,
              _bytes('made on the desktop'),
              peerName: 'Desktop'),
          isTrue);
      expect(ipad.names.length, 2);
    });

    test('and the same manifest repeating it is not a second conflict', () {
      LanSync.instance.applyForTest(
          fromDesktop, _bytes('made on the desktop'),
          peerName: 'Desktop');
      final after = ipad.names;
      for (var i = 0; i < 5; i++) {
        LanSync.instance.mirrorState();
        expect(LanSync.instance.verdictFor(fromDesktop), SyncVerdict.skip,
            reason: 'round $i');
      }
      expect(ipad.names, after);
      expect(LanSync.instance.recentForks.value.length, 1);
    });

    test('deleting the copy does not make the next round keep it again', () {
      LanSync.instance.applyForTest(
          fromDesktop, _bytes('made on the desktop'),
          peerName: 'Desktop');
      final copy = ipad.names.firstWhere((n) => n != 'Part1.ptp');
      ipad.delete(copy);
      expect(LanSync.instance.verdictFor(fromDesktop), SyncVerdict.skip);
      expect(ipad.names, ['Part1.ptp'],
          reason: '"they always respawn and copy themselves"');
    });

    test('the other device takes the resolution and reaches the same files',
        () {
      LanSync.instance.applyForTest(
          fromDesktop, _bytes('made on the desktop'),
          peerName: 'Desktop');
      final names = ipad.names;
      final sent = [for (final n in names) LanSync.instance.outgoingForTest(n)];
      final bytes = {
        for (final n in names) n: ipad.file(n).readAsBytesSync(),
      };

      desktop.use();
      for (final e in sent) {
        final v = LanSync.instance.verdictFor(e);
        expect(v, isNot(SyncVerdict.fork),
            reason: '${e.path}: the resolution covers the desktop\'s version');
        if (v == SyncVerdict.take) {
          expect(
              LanSync.instance.applyForTest(e, bytes[e.path]!,
                  peerName: 'iPad'),
              isTrue);
        }
      }
      expect(desktop.names, names);
      for (final n in names) {
        expect(desktop.file(n).readAsBytesSync(), bytes[n], reason: n);
      }
      expect(LanSync.instance.recentForks.value, isEmpty);
    });
  });

  group('what the vector must not have traded away', () {
    test('#47: a new document with the old one\'s bytes outlives the stale '
        'tombstone', () {
      final ipad = _Device(root, 'iPad')..use();
      ipad.save('Part1.ptp', 'empty part');
      ipad.delete('Part1.ptp');
      final stale = LanSync.instance.tombListForTest().single;
      // A new document, named by counting, whose first save is byte for byte
      // the deleted one's.
      ipad.save('Part1.ptp', 'empty part');
      expect(LanSync.instance.tombsForTest, isEmpty);
      // A peer that never forgot the old delete announces it again. By the
      // sha alone this is exactly the version that was deleted.
      expect(stale.sha, _shaOf('empty part'));
      expect(LanSync.instance.applyTombForTest(stale), isFalse);
      expect(ipad.file('Part1.ptp').existsSync(), isTrue);
    });

    test('a restore from the drawer reaches a device that had those bytes',
        () {
      final ipad = _Device(root, 'iPad');
      final desktop = _Device(root, 'Desktop');
      ipad.use();
      ipad.save('Part1.ptp', 'good');
      final good = LanSync.instance.outgoingForTest('Part1.ptp');
      ipad.save('Part1.ptp', 'bad');
      final bad = LanSync.instance.outgoingForTest('Part1.ptp');

      // The desktop had both, in order; the good one is in its drawer.
      desktop.use();
      LanSync.instance.applyForTest(good, _bytes('good'), peerName: 'iPad');
      LanSync.instance.applyForTest(bad, _bytes('bad'), peerName: 'iPad');
      final drawer = LanSync.instance
          .backups()
          .firstWhere((b) => b.file.readAsStringSync() == 'good');
      expect(LanSync.instance.restore(drawer), isTrue);
      LanSync.instance.mirrorState();
      final restored = LanSync.instance.outgoingForTest('Part1.ptp');

      // Old bytes, new decision: the iPad has held exactly these before, and
      // must take them anyway.
      ipad.use();
      expect(LanSync.instance.verdictFor(restored), SyncVerdict.take);
    });

    test('a save the last scan has not seen is never replaced', () {
      final ipad = _Device(root, 'iPad');
      final desktop = _Device(root, 'Desktop');
      desktop.use();
      desktop.save('Part1.ptp', 'v1');
      final v1 = LanSync.instance.outgoingForTest('Part1.ptp');
      ipad.use();
      LanSync.instance.applyForTest(v1, _bytes('v1'), peerName: 'Desktop');
      desktop.use();
      desktop.save('Part1.ptp', 'v2 from the desktop');
      final v2 = LanSync.instance.outgoingForTest('Part1.ptp');

      ipad.use();
      // Saved on the iPad while the desktop's v2 was on its way down: the
      // last scan still says v1, and against v1 the desktop is simply ahead.
      ipad.file('Part1.ptp').writeAsStringSync('saved on the iPad just now');
      expect(
          LanSync.instance.applyForTest(v2, _bytes('v2 from the desktop'),
              peerName: 'Desktop'),
          isFalse);
      expect(ipad.file('Part1.ptp').readAsStringSync(),
          'saved on the iPad just now');
      // The next pass counts the save, and the two are what they are.
      LanSync.instance.mirrorState();
      expect(LanSync.instance.verdictFor(v2), SyncVerdict.fork);
    });

    test('a peer too old to count is judged by the rule as it was', () {
      final ipad = _Device(root, 'iPad')..use();
      ipad.save('Bracket.ptp', 'a');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('a'));
      final theirs = SyncEntry(
          'Bracket.ptp', 1, DateTime.now().millisecondsSinceEpoch, _shaOf('b'));
      expect(LanSync.instance.verdictFor(theirs), SyncVerdict.take,
          reason: 'M417: only they moved on');
    });

    test('two vectors that say nothing are judged by the rule as it was', () {
      final ipad = _Device(root, 'iPad')..use();
      ipad.save('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      // An empty vector: an install that has not changed this document since
      // it started counting. Beside another empty one it says nothing.
      File('${ipad.prefs.path}/sync-versions.json').writeAsStringSync(jsonEncode({
        'Bracket.ptp': {'h': _shaOf('mine'), 'v': <String, int>{}},
      }));
      ipad.use();
      final theirs = SyncEntry('Bracket.ptp', 1,
          DateTime.now().millisecondsSinceEpoch, _shaOf('agreed'),
          clock: const {});
      expect(LanSync.instance.verdictFor(theirs), SyncVerdict.skip,
          reason: 'M417: they hold the agreed version, only I moved on');
    });
  });

  group('the journal', () {
    test('counts a save once, and survives a restart', () {
      final ipad = _Device(root, 'iPad')..use();
      ipad.save('Part1.ptp', 'a');
      final me = LanSync.instance.deviceId;
      expect(LanSync.instance.clockForTest('Part1.ptp'), {me: 1});
      LanSync.instance.mirrorState();
      LanSync.instance.scanForTest();
      expect(LanSync.instance.clockForTest('Part1.ptp'), {me: 1},
          reason: 'looking again is not another edit');
      ipad.save('Part1.ptp', 'b');
      expect(LanSync.instance.clockForTest('Part1.ptp'), {me: 2});
      ipad.use();
      expect(LanSync.instance.deviceId, me);
      expect(LanSync.instance.clockForTest('Part1.ptp'), {me: 2});
    });

    test('an install from before it is seeded from what it agreed on', () {
      final ipad = _Device(root, 'iPad');
      ipad.file('Agreed.ptp').writeAsStringSync('as the group has it');
      ipad.file('Changed.ptp').writeAsStringSync('edited since');
      ipad.file('Local.ptp').writeAsStringSync('never left');
      File('${ipad.prefs.path}/sync-base.json').writeAsStringSync(jsonEncode({
        'Agreed.ptp': _shaOf('as the group has it'),
        'Changed.ptp': _shaOf('before the edit'),
      }));
      ipad.use();
      final me = LanSync.instance.deviceId;
      expect(LanSync.instance.clockForTest('Agreed.ptp'), isEmpty);
      expect(LanSync.instance.clockForTest('Changed.ptp'), {me: 1});
      expect(LanSync.instance.clockForTest('Local.ptp'), {me: 1});
    });

    test('an old tombstone is given this device\'s knowledge of the delete',
        () {
      final ipad = _Device(root, 'iPad');
      File('${ipad.prefs.path}/sync-deleted.json').writeAsStringSync(
          jsonEncode({
        'Part1.ptp': {'d': DateTime.now().millisecondsSinceEpoch},
      }));
      ipad.use();
      expect(LanSync.instance.tombsForTest['Part1.ptp']!.clock,
          {LanSync.instance.deviceId: 1});
      // Which is what keeps a copy from before the upgrade — an empty vector
      // — from bringing the document back.
      final before = SyncEntry('Part1.ptp', 1, 1, _shaOf('from before'),
          clock: const {});
      expect(LanSync.instance.verdictFor(before), SyncVerdict.skip);
    });

    test('is never mirrored, and follows the gallery', () {
      final ipad = _Device(root, 'iPad')..use();
      ipad.save('Part1.ptp', 'a');
      expect(File('${ipad.prefs.path}/sync-versions.json').existsSync(), isTrue);
      expect(LanSync.mirroredPrefFilesForTest,
          isNot(contains('sync-versions.json')));
      expect(LanSync.instance.scanForTest().keys,
          isNot(contains(contains('sync-versions'))));
      LanSync.instance.applyForTest(
          SyncEntry('Gone.ptp', 1, 1, _shaOf('x'), clock: const {'z': 1}),
          _bytes('x'));
      expect(LanSync.instance.clockForTest('Gone.ptp'), isNotNull);
      File('${ipad.docs.path}/Gone.ptp').deleteSync();
      LanSync.instance.mirrorState();
      // Tombstoned: kept, for as long as the tombstone is.
      expect(LanSync.instance.clockForTest('Gone.ptp'), isNotNull);
      LanSync.instance.tombsForTest.remove('Gone.ptp');
      LanSync.instance.pruneBaseForTest();
      expect(LanSync.instance.clockForTest('Gone.ptp'), isNull);
    });

    test('an entry whose bytes moved since the scan goes out uncounted', () {
      final ipad = _Device(root, 'iPad')..use();
      ipad.save('Part1.ptp', 'a');
      final stale = SyncEntry('Part1.ptp', 1, 1, _shaOf('saved since'));
      expect(LanSync.instance.outgoingEntryForTest(stale).clock, isNull,
          reason: 'the history on record is for other bytes');
      expect(LanSync.instance.outgoingForTest('Part1.ptp').clock, isNotNull);
    });
  });

  group('the cloud', () {
    test('reads only the manifests this build can trust', () {
      CloudManifest m(Object? v) => CloudManifest.fromJson({
            'device': 'd',
            'name': 'localhost',
            if (v != null) 'v': v,
            'entries': const [],
            'tombs': const [],
          })!;
      expect(m(null).legacy, isTrue);
      expect(m(null).readable, isFalse);
      expect(m(1).legacy, isTrue);
      expect(m(kCloudManifestVersion).readable, isTrue);
      expect(m(kCloudManifestVersion).legacy, isFalse);
      expect(m(kCloudManifestVersion + 1).readable, isFalse,
          reason: 'a newer format is not guessed at either');
      expect(m(kCloudManifestVersion + 1).legacy, isFalse);
    });

    test('an old manifest is collected a day after it was last written', () {
      final legacy = CloudManifest.fromJson(const {
        'device': 'd',
        'entries': [],
        'tombs': [],
      })!;
      const current = CloudManifest(
          device: 'd', deviceName: 'n', atMs: 1, entries: [], tombs: []);
      final now = DateTime.now().millisecondsSinceEpoch;
      const hour = 3600000;
      expect(
          CloudSync.legacyIsRetired(legacy,
              lastModifiedMs: now - 25 * hour, nowMs: now),
          isTrue);
      expect(
          CloudSync.legacyIsRetired(legacy,
              lastModifiedMs: now - 3 * hour, nowMs: now),
          isFalse);
      expect(
          CloudSync.legacyIsRetired(legacy, lastModifiedMs: 0, nowMs: now),
          isFalse,
          reason: 'no evidence of age is no reason to delete');
      expect(
          CloudSync.legacyIsRetired(current,
              lastModifiedMs: now - 100 * hour, nowMs: now),
          isFalse);
    });

    test('our own old manifest is rewritten even when it says the same', () {
      const entry = SyncEntry('P.ptp', 1, 1, 'h', clock: {'a': 1});
      final was = CloudManifest.fromJson({
        'device': 'd',
        'entries': [entry.toJson()],
        'tombs': const [],
      })!;
      const now = CloudManifest(
          device: 'd', deviceName: 'n', atMs: 2, entries: [entry], tombs: []);
      expect(CloudSync.differsForTest(was, now), isTrue);
    });

    test('a history that moved is news even when the bytes did not', () {
      const a = CloudManifest(device: 'd', deviceName: 'n', atMs: 1, entries: [
        SyncEntry('P.ptp', 1, 1, 'h', clock: {'a': 1}),
      ], tombs: []);
      const b = CloudManifest(device: 'd', deviceName: 'n', atMs: 2, entries: [
        SyncEntry('P.ptp', 1, 1, 'h', clock: {'a': 1, 'b': 1}),
      ], tombs: []);
      expect(CloudSync.differsForTest(a, b), isTrue);
      expect(CloudSync.differsForTest(a, a), isFalse);
    });

    test('a dropped connection is retried; an answer is not', () {
      expect(
          CloudSync.isDroppedConnection(http.ClientException(
              'Connection closed before full header was received')),
          isTrue);
      expect(
          CloudSync.isDroppedConnection(
              const SocketException('Connection reset by peer')),
          isTrue);
      expect(CloudSync.isDroppedConnection(const HttpException('x')), isTrue);
      expect(CloudSync.isDroppedConnection(StateError('list: 403')), isFalse);
      expect(CloudSync.isDroppedConnection(const FormatException('x')),
          isFalse);
    });
  });

  group('whole cycles, against a stand-in bucket', () {
    const creds = B2Credentials(
        keyId: 'test-key-id',
        appKey: 'test-app-key',
        bucket: 'test-bucket',
        region: 'eu-central-003');
    final group = CloudSync.groupForTest(creds);
    late _Bucket bucket;

    setUp(() => bucket = _Bucket());

    /// One cycle as [d]. Attaching is what a launch looks like.
    Future<CloudResult> launch(_Device d) async {
      d.use();
      CloudSync.instance.resetForTest();
      CloudSync.instance.httpForTest = bucket.client;
      await CloudSync.instance.setAccount(creds);
      final r = await CloudSync.instance.syncNow();
      CloudSync.instance.holdForTest();
      return r;
    }

    /// Another cycle as whoever is running now.
    Future<CloudResult> again() async {
      final r = await CloudSync.instance.syncNow();
      CloudSync.instance.holdForTest();
      return r;
    }

    /// A manifest from before M462, as the four in #88 were.
    void legacyManifest(String device, Map<String, String> docs,
        {Map<String, String> tombs = const {}, Duration age = const Duration(hours: 13)}) {
      final at = DateTime.now().subtract(age);
      for (final text in docs.values) {
        bucket.put('g/$group/b/${_shaOf(text)}', _bytes(text), at: at);
      }
      bucket.put(
          'g/$group/m/$device.json',
          utf8.encode(jsonEncode({
            'device': device,
            'name': 'localhost',
            'at': at.millisecondsSinceEpoch,
            'entries': [
              for (final e in docs.entries)
                SyncEntry(e.key, e.value.length, at.millisecondsSinceEpoch,
                        _shaOf(e.value), base: _shaOf(e.value))
                    .toJson(),
            ],
            'tombs': [
              for (final t in tombs.entries)
                SyncTomb(t.key, at.millisecondsSinceEpoch, _shaOf(t.value))
                    .toJson(),
            ],
          })),
          at: at);
    }

    test('#88: four manifests nothing will update change nothing here',
        () async {
      final ipad = _Device(root, 'iPad');
      ipad.file('Part1.ptp').writeAsStringSync('the part as it is now');
      ipad.file('Part2.ptp').writeAsStringSync('another part');
      // Three earlier launches of this iPad and the other iOS device, each
      // holding some older Part1 and a copy of it — and one of them a
      // tombstone for exactly the Part2 this iPad holds.
      legacyManifest('AOika0up5ch2', {
        'Part1.ptp': 'part one, yesterday afternoon',
        'Part1 (localhost).ptp': 'a copy, yesterday',
      });
      legacyManifest('BGbZW80bCrCs', {
        'Part1.ptp': 'part one, yesterday evening',
        'Part1 (localhost) 2.ptp': 'another copy',
      });
      legacyManifest('q4kAvrmSHPML', {'Part1.ptp': 'part one, last night'},
          tombs: {'Part2.ptp': 'another part'});
      legacyManifest('Lmh05C47mfwp', {'Part3.ptp': 'from the other device'});

      var r = await launch(ipad);
      expect(r.outcome, isNot(CloudOutcome.failed), reason: '${r.detail}');
      for (var i = 0; i < 3; i++) {
        r = await again();
        expect(r.forks, 0);
      }
      expect(ipad.names, ['Part1.ptp', 'Part2.ptp'],
          reason: 'no copies, nothing taken, nothing removed');
      expect(ipad.file('Part1.ptp').readAsStringSync(), 'the part as it is now');
      expect(LanSync.instance.recentForks.value, isEmpty);
      expect(CloudSync.instance.status.value.devices, 0,
          reason: 'none of them is a device that is still there');

      // THE REPORT: delete it, and it stays deleted.
      ipad.file('Part1.ptp').deleteSync();
      for (var i = 0; i < 3; i++) {
        await again();
      }
      expect(ipad.names, ['Part2.ptp']);

      // And our own manifest is the new format, so an updated device reads it.
      final mine = jsonDecode(utf8.decode(bucket
          .objects['g/$group/m/${LanSync.instance.deviceId}.json']!.body));
      expect(mine['v'], kCloudManifestVersion);
      expect((mine['tombs'] as List).map((t) => t['p']), contains('Part1.ptp'));
    });

    test('the desktop switched off for the day: behind, never a copy',
        () async {
      final ipad = _Device(root, 'iPad');
      final desktop = _Device(root, 'Desktop');
      desktop.file('Part1.ptp').writeAsStringSync('v1');
      await launch(desktop);

      await launch(ipad);
      expect(ipad.file('Part1.ptp').readAsStringSync(), 'v1');
      // A day of work on the iPad. The desktop's manifest never changes.
      for (final v in ['v2', 'v3', 'v4']) {
        ipad.file('Part1.ptp').writeAsStringSync(v);
        final r = await again();
        expect(r.forks, 0, reason: v);
        await again();
        // THE OTHER HALF OF THE OLD RULE. The desktop published v1 before it
        // had a base for it, so its entry carries none — and against a base
        // the iPad had moved on by uploading, "only they moved on" read true.
        // The edit was replaced by the desktop's week-old version, into the
        // drawer, with nothing on screen to say so.
        expect(ipad.file('Part1.ptp').readAsStringSync(), v,
            reason: 'an edit is never replaced by a version it was made on');
      }
      expect(ipad.names, ['Part1.ptp']);
      expect(LanSync.instance.recentForks.value, isEmpty);

      // Deleted on the iPad, and it stays deleted.
      ipad.file('Part1.ptp').deleteSync();
      for (var i = 0; i < 3; i++) {
        await again();
      }
      expect(ipad.names, isEmpty);

      // The desktop comes back: it had seen nothing since v1, and the delete
      // had seen v1 — so its copy goes too, and nothing is kept twice.
      await launch(desktop);
      expect(desktop.names, isEmpty);
      expect(LanSync.instance.recentForks.value, isEmpty);
      expect(LanSync.instance.backups().map((b) => b.path),
          contains('Part1.ptp'),
          reason: 'what it removed is in its drawer');

      await launch(ipad);
      expect(ipad.names, isEmpty);
    });

    test('the desktop comes back to edits, and takes them', () async {
      final ipad = _Device(root, 'iPad');
      final desktop = _Device(root, 'Desktop');
      desktop.file('Part1.ptp').writeAsStringSync('v1');
      await launch(desktop);
      await launch(ipad);
      ipad.file('Part1.ptp').writeAsStringSync('v2');
      await again();
      ipad.file('Part1.ptp').writeAsStringSync('v3');
      await again();

      final r = await launch(desktop);
      expect(r.forks, 0);
      expect(desktop.names, ['Part1.ptp']);
      expect(desktop.file('Part1.ptp').readAsStringSync(), 'v3');
    });

    test('a real conflict is kept once, and both devices end the same',
        () async {
      final ipad = _Device(root, 'iPad');
      final desktop = _Device(root, 'Desktop');
      desktop.file('Part1.ptp').writeAsStringSync('made on the desktop');
      await launch(desktop);
      ipad.file('Part1.ptp').writeAsStringSync('made on the iPad');
      final first = await launch(ipad);
      expect(first.forks, 1);
      final names = ipad.names;
      expect(names.length, 2);
      for (var i = 0; i < 3; i++) {
        expect((await again()).forks, 0, reason: 'round $i');
      }
      expect(ipad.names, names);

      final back = await launch(desktop);
      expect(back.forks, 0, reason: 'it takes the resolution');
      expect(desktop.names, names);
      for (final n in names) {
        expect(desktop.file(n).readAsStringSync(),
            ipad.file(n).readAsStringSync(),
            reason: n);
      }
      // And neither side has anything left to do about it.
      expect((await again()).forks, 0);
      await launch(ipad);
      expect(ipad.names, names);
      expect(LanSync.instance.recentForks.value, isEmpty);
    });

    test('an old manifest is collected once it has been left a day',
        () async {
      final ipad = _Device(root, 'iPad');
      ipad.file('Part1.ptp').writeAsStringSync('mine');
      legacyManifest('longGone0001', {'Old.ptp': 'old'},
          age: const Duration(days: 2));
      legacyManifest('stillBusy001', {'Busy.ptp': 'busy'},
          age: const Duration(hours: 3));
      await launch(ipad);
      await again(); // idle: the collector's turn
      expect(bucket.objects.containsKey('g/$group/m/longGone0001.json'), isFalse);
      expect(bucket.objects.containsKey('g/$group/m/stillBusy001.json'), isTrue,
          reason: 'a device on an old build may still be in use');
      expect(
          bucket.objects
              .containsKey('g/$group/m/${LanSync.instance.deviceId}.json'),
          isTrue);
    });

    test('an upgraded device rewrites the manifest its old build wrote',
        () async {
      final ipad = _Device(root, 'iPad');
      File('${ipad.prefs.path}/sync-device.json')
          .writeAsStringSync(jsonEncode({'id': '7nAcT-iYd7KK', 'name': 'ios-7nAc'}));
      ipad.file('Part1.ptp').writeAsStringSync('mine');
      legacyManifest('7nAcT-iYd7KK', {'Part1.ptp': 'mine'},
          age: const Duration(minutes: 5));
      await launch(ipad);
      expect(LanSync.instance.deviceId, '7nAcT-iYd7KK');
      final m = jsonDecode(utf8
          .decode(bucket.objects['g/$group/m/7nAcT-iYd7KK.json']!.body));
      expect(m['v'], kCloudManifestVersion,
          reason: 'or every updated device would go on ignoring this one');
    });

    test('a connection the server had already closed is retried once',
        () async {
      final ipad = _Device(root, 'iPad');
      ipad.file('Part1.ptp').writeAsStringSync('mine');
      bucket.dropNext = 1;
      final ok = await launch(ipad);
      expect(ok.outcome, isNot(CloudOutcome.failed), reason: '${ok.detail}');
      expect(bucket.log.first, bucket.log[1],
          reason: 'the same request, sent again');

      bucket.dropNext = 2;
      final twice = await again();
      expect(twice.outcome, CloudOutcome.failed,
          reason: 'once, not until it works');
    });

    test('a refusal is an answer, and is not sent again', () async {
      final ipad = _Device(root, 'iPad');
      bucket.refuseWith = 403;
      final r = await launch(ipad);
      expect(r.outcome, CloudOutcome.failed);
      expect(bucket.requests, 1);
    });
  });
}

/// Enough of S3 for a cycle: LIST by prefix, GET, PUT, DELETE, kept in memory
/// — and able to drop a connection the way #88's log shows Backblaze doing.
class _Bucket {
  final Map<String, ({Uint8List body, DateTime at})> objects = {};

  /// Requests that fail as a closed pooled connection does, before any
  /// answer.
  int dropNext = 0;

  /// When set, every request is answered with this status.
  int refuseWith = 0;

  int requests = 0;
  final List<String> log = [];

  void put(String key, List<int> body, {DateTime? at}) =>
      objects[key] = (body: Uint8List.fromList(body), at: at ?? DateTime.now());

  http.Client get client => MockClient((req) async {
        requests++;
        log.add('${req.method} ${req.url.path}?${req.url.queryParameters['prefix'] ?? ''}');
        if (dropNext > 0) {
          dropNext--;
          throw http.ClientException(
              'Connection closed before full header was received', req.url);
        }
        if (refuseWith != 0) {
          return http.Response(
              '<Error><Code>AccessDenied</Code></Error>', refuseWith);
        }
        final key = Uri.decodeComponent(req.url.path.substring(1));
        switch (req.method) {
          case 'GET':
            if (req.url.queryParameters['list-type'] == '2') {
              final prefix = req.url.queryParameters['prefix'] ?? '';
              final keys = objects.keys.where((k) => k.startsWith(prefix)).toList()
                ..sort();
              final b = StringBuffer('<ListBucketResult>');
              for (final k in keys) {
                final o = objects[k]!;
                b.write('<Contents><Key>$k</Key>'
                    '<LastModified>${o.at.toUtc().toIso8601String()}</LastModified>'
                    '<ETag>&quot;${sha256.convert(o.body)}&quot;</ETag>'
                    '<Size>${o.body.length}</Size></Contents>');
              }
              b.write('<IsTruncated>false</IsTruncated></ListBucketResult>');
              return http.Response(b.toString(), 200);
            }
            final o = objects[key];
            if (o == null) {
              return http.Response('<Error><Code>NoSuchKey</Code></Error>', 404);
            }
            return http.Response.bytes(o.body, 200);
          case 'PUT':
            put(key, req.bodyBytes);
            return http.Response('', 200);
          case 'DELETE':
            objects.remove(key);
            return http.Response('', 204);
        }
        return http.Response('', 405);
      });
}
