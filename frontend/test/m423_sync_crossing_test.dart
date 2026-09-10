// M423 — "the sync doesnt work correctly. i changed the part on my ipad
// multiple times but at all times i have the old version on my windows pc"
// (issue #45).
//
// The log in that report says exactly what happened, and it is not what the
// sentence sounds like. Nothing was lost and nothing failed to travel. The
// same document arrived on the PC over and over, alternating between two
// versions, several times a minute, with no one touching it there:
//
//   11:30:31  took Lampenbefestigung Marshydro.ptp (93287 bytes)
//   11:30:38  took Lampenbefestigung Marshydro.ptp (73517 bytes)
//   11:31:18  took Lampenbefestigung Marshydro.ptp (93287 bytes)
//   11:31:27  took Lampenbefestigung Marshydro.ptp (73517 bytes)
//   11:31:41  took Lampenbefestigung Marshydro.ptp (93287 bytes)
//
// Two devices SWAPPING one document, for as long as both were running. Open it
// on the PC and you see whichever version lost the last round — which, half
// the time, is the old one.
//
// HOW A MIRROR GETS INTO THAT STATE. M417's conflict rule reads three shas: L
// (what I hold), R (what they offer) and B (the version we last agreed on). It
// is a good rule and it has one assumption: that B means the same thing on
// both devices. A manifest exchange breaks it, because both sides ask before
// either has answered — so both apply, each ends up holding what the OTHER
// had, and each writes THAT down as the agreed version. From then on the rule
// is read against two different bases and both sides conclude "only they moved
// on". Both take. Both keep taking, for ever.
//
// The fix is to make the disagreement visible instead of invisible: an entry
// on the wire now carries the sender's own base, and two bases that do not
// match are two devices that never agreed — which is a divergence, and the
// mirror already knows what to do with one. Keep both, deterministically, and
// it is over on the first pass. A second net catches the same shape from this
// side alone, for a peer too old to send its base: a version this device threw
// away minutes ago is its own past coming back, not an edit.
//
// What is pinned here:
//   * the crossing itself: two bases that disagree end in one fork, not in a
//     swap, and both devices reach the same two files;
//   * that the loop is actually OVER — the round after the fork is a skip;
//   * the net for a peer with no base to send;
//   * every case the old rule got right still gets the same answer, because
//     the cure for a mirror that takes too often must not be a mirror that
//     forks at the sight of a normal edit;
//   * that the base survives the wire, including from a peer that omits it.
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

  /// Writes [text] as the document [name] and returns what the mirror holds.
  SyncEntry local(String name, String text) {
    File('${docs.path}/$name').writeAsStringSync(text);
    LanSync.instance.attachForTest(documents: docs, preferences: prefs);
    return LanSync.instance.localManifestForTest[name]!;
  }

  /// What a peer holding [text] would offer, saying what IT last agreed on.
  SyncEntry remote(String name, String text, {String? base, int? mtimeMs}) =>
      SyncEntry(name, text.length, mtimeMs ?? DateTime.now().millisecondsSinceEpoch,
          _shaOf(text),
          base: base);

  List<String> namesIn(Directory d) => d
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((n) => n.endsWith('.ptp'))
      .toList()
    ..sort();

  setUp(() {
    root = Directory.systemTemp.createTempSync('m423');
    docs = Directory('${root.path}/docs')..createSync();
    prefs = Directory('${root.path}/prefs')..createSync();
    LanSync.instance.attachForTest(documents: docs, preferences: prefs);
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('the crossing', () {
    test('two bases that disagree are a divergence, not news', () {
      // The PC, mid-swap: it holds what the iPad had, and wrote that down as
      // the agreed version when it took it.
      local('Bracket.ptp', 'ipad');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('ipad'));

      // The iPad, mid-swap, offers what the PC had — and says the same thing
      // about it: "this is the version we agreed on".
      final theirs = remote('Bracket.ptp', 'pc', base: _shaOf('pc'));

      // THE REGRESSION. Read against one base this is "only they moved on",
      // and taking it is what starts the next lap.
      expect(LanSync.instance.verdictFor(theirs), SyncVerdict.fork,
          reason: 'neither side moved on from anything the other agreed to');
    });

    test('one pass, and the swapping is over', () {
      final mine = local('Bracket.ptp', 'pc');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('pc'));
      final theirs = remote('Bracket.ptp', 'ipad',
          base: _shaOf('ipad'), mtimeMs: mine.mtimeMs + 60000);

      expect(
          LanSync.instance
              .applyForTest(theirs, _bytes('ipad'), peerName: 'Toms iPad'),
          isTrue);

      // Both versions are on disk: the newer under the document's own name,
      // the older beside it. Nothing was thrown away to stop the loop.
      expect(File('${docs.path}/Bracket.ptp').readAsStringSync(), 'ipad');
      expect(namesIn(docs).length, 2);

      // AND THE NEXT ROUND IS A SKIP. This is the actual claim of this file:
      // the peer announces the same version again — as it does, every few
      // seconds — and nothing happens any more.
      expect(LanSync.instance.verdictFor(theirs), SyncVerdict.skip,
          reason: 'the same bytes on both devices is an agreement');
      expect(
          LanSync.instance.verdictFor(
              remote('Bracket.ptp', 'ipad', base: _shaOf('ipad'))),
          SyncVerdict.skip);
    });

    test('both devices reach the same two files', () {
      // NAMED, both of them, because the copy is named after the device the
      // losing version was last saved on: two devices resolving the same
      // divergence have to arrive at the same filename or the mirror trades
      // copies instead of settling.
      File('${docs.path}/Bracket.ptp').writeAsStringSync('pc');
      LanSync.instance.attachForTest(
          documents: docs, preferences: prefs, deviceName: 'Studio PC');
      final mine = LanSync.instance.localManifestForTest['Bracket.ptp']!;
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('pc'));
      LanSync.instance.applyForTest(
          remote('Bracket.ptp', 'ipad',
              base: _shaOf('ipad'), mtimeMs: mine.mtimeMs + 60000),
          _bytes('ipad'),
          peerName: 'Toms iPad');
      final here = namesIn(docs);

      // The same crossing from the iPad's side: it holds "ipad", agreed on
      // "ipad", and is offered the PC's older version with the PC's base.
      final other = Directory('${root.path}/other')..createSync();
      final otherPrefs = Directory('${root.path}/otherprefs')..createSync();
      File('${other.path}/Bracket.ptp').writeAsStringSync('ipad');
      LanSync.instance.attachForTest(
          documents: other, preferences: otherPrefs, deviceName: 'Toms iPad');
      final theirs = LanSync.instance.localManifestForTest['Bracket.ptp']!;
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('ipad'));
      LanSync.instance.applyForTest(
          SyncEntry('Bracket.ptp', 2, theirs.mtimeMs - 60000, _shaOf('pc'),
              base: _shaOf('pc')),
          _bytes('pc'),
          peerName: 'Studio PC');

      expect(namesIn(other), here,
          reason: 'the same two filenames on both devices, or it never settles');
      expect(File('${other.path}/Bracket.ptp').readAsStringSync(), 'ipad');
      expect(File('${docs.path}/Bracket.ptp').readAsStringSync(), 'ipad');
    });

    test('a version this device already replaced is not taken back', () {
      // The net for a peer too old to send a base at all: no `base` on either
      // entry, so the rule above cannot fire and this one has to.
      final mine = local('Bracket.ptp', 'old');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('old'));
      LanSync.instance.applyForTest(
          remote('Bracket.ptp', 'new', mtimeMs: mine.mtimeMs + 1000),
          _bytes('new'));
      expect(File('${docs.path}/Bracket.ptp').readAsStringSync(), 'new');

      // The peer now offers back the very version this device just replaced.
      // Read against the base alone that is "only they moved on" — the second
      // half of the swap.
      expect(
          LanSync.instance
              .verdictFor(remote('Bracket.ptp', 'old', mtimeMs: mine.mtimeMs)),
          SyncVerdict.fork,
          reason: 'this device threw those bytes away a moment ago');
    });
  });

  group('everything the old rule got right', () {
    test('a peer that moved on from what we agreed still wins', () {
      local('Bracket.ptp', 'agreed');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      expect(
          LanSync.instance.verdictFor(
              remote('Bracket.ptp', 'their edit', base: _shaOf('agreed'))),
          SyncVerdict.take,
          reason: 'the bases match, so the three-sha rule is sound');
    });

    test('a peer that is behind is still ignored', () {
      local('Bracket.ptp', 'my edit');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      expect(
          LanSync.instance.verdictFor(
              remote('Bracket.ptp', 'agreed', base: _shaOf('agreed'))),
          SyncVerdict.skip);
    });

    test('both edited from the same agreed version: still kept both', () {
      local('Bracket.ptp', 'my edit');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      expect(
          LanSync.instance.verdictFor(
              remote('Bracket.ptp', 'their edit', base: _shaOf('agreed'))),
          SyncVerdict.fork);
    });

    test('nothing here to lose: taken, whatever either base says', () {
      expect(
          LanSync.instance
              .verdictFor(remote('Bracket.ptp', 'theirs', base: _shaOf('x'))),
          SyncVerdict.take);
    });

    test('identical bytes are an agreement even mid-disagreement', () {
      local('Bracket.ptp', 'same');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('one thing'));
      // This is what heals a crossing after the fork: the two devices hold the
      // same bytes, so whatever they each thought they had agreed on stops
      // mattering, and the next announcement writes one base on both.
      final theirs = remote('Bracket.ptp', 'same', base: _shaOf('another'));
      expect(LanSync.instance.verdictFor(theirs), SyncVerdict.skip);
      LanSync.instance.noteAgreementForTest(theirs);
      expect(LanSync.instance.baseForTest['Bracket.ptp'], _shaOf('same'));
    });

    test('preferences keep their own rule', () {
      // Merged rather than replaced, so there is nothing to fork and a base
      // that disagrees must not start one.
      File('${prefs.path}/settings.json').writeAsStringSync('{"a":1}');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      final path = 'settings/settings.json';
      LanSync.instance.setBaseForTest(path, _shaOf('mine'));
      final mine = LanSync.instance.localManifestForTest[path]!;
      expect(
          LanSync.instance.verdictFor(SyncEntry(path, 8, mine.mtimeMs + 60000,
              _shaOf('theirs'),
              base: _shaOf('theirs'))),
          SyncVerdict.take,
          reason: 'a preference that loses is a tick box, not an afternoon');
    });
  });

  group('the base on the wire', () {
    test('an entry carries it there and back', () {
      final e = SyncEntry('Bracket.ptp', 3, 1234, _shaOf('a'), base: 'abc');
      final back = SyncEntry.fromJson(jsonDecode(jsonEncode(e.toJson())))!;
      expect(back.base, 'abc');
      expect(back.sha, e.sha);
      expect(back.mtimeMs, 1234);
    });

    test('a peer too old to send one is read as having none', () {
      final back = SyncEntry.fromJson(
          {'p': 'Bracket.ptp', 's': 3, 'm': 1234, 'h': _shaOf('a')})!;
      expect(back.base, isNull);
    });

    test('this device fills it in from its own journal', () {
      local('Bracket.ptp', 'mine');
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      final sent = LanSync.instance
          .manifestJsonForTest()
          .firstWhere((m) => m['p'] == 'Bracket.ptp');
      expect(sent['b'], _shaOf('agreed'),
          reason: 'without this the peer cannot tell a crossing from an edit');
    });

    test('a document with no agreed version sends no base at all', () {
      local('Bracket.ptp', 'mine');
      final sent = LanSync.instance
          .manifestJsonForTest()
          .firstWhere((m) => m['p'] == 'Bracket.ptp');
      expect(sent.containsKey('b'), isFalse);
    });
  });
}
