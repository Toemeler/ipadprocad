// M445 — "The objects keep appearing 2 times then 3 times and so on"
// (issue #86, bug-2026-09-22T230542).
//
// The log names the whole mechanism, and it is a cascade rather than a
// duplicate:
//
//   101  Part1.ptp changed on two devices at once (the base versions do not
//        match) — keeping both
//    58  Part1.ptp was changed here and on localhost — both kept, the older
//        one as Part1 (localhost).ptp
//    50  Part1 (localhost).ptp was changed here and on localhost — both kept,
//        the older one as Part1 (localhost) (localhost).ptp
//
// TWO FAULTS, and it needed both.
//
//   1. EVERY iOS DEVICE IS CALLED `localhost`. `Platform.localHostname`
//      answers that on all of them, and the name is what `_freeCopyPath`
//      stamps on a conflict copy. So two iPads resolving the same conflict
//      both wrote `Part1 (localhost).ptp` — two DIFFERENT files under one
//      name, which is itself a divergence, which forks. The device id was
//      minted fresh every launch too (the log has five for one iPad), so the
//      pair never built a shared history to settle against.
//
//   2. A CONFLICT COPY IS ITSELF MIRRORED. Keeping both is the right answer
//      once. The copy is then a new document, so if the two devices disagree
//      about IT the rule fires again, and again — `(localhost) (localhost)`.
//      Nothing bounded the depth.
//
// Fixing only the names would leave the cascade armed for the next collision.
// Fixing only the depth would leave every iPad indistinguishable in the
// gallery. Both are pinned here.
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

  setUp(() {
    root = Directory.systemTemp.createTempSync('m445');
    docs = Directory('${root.path}/docs')..createSync();
    prefs = Directory('${root.path}/prefs')..createSync();
    LanSync.instance.attachForTest(documents: docs, preferences: prefs);
  });

  tearDown(() => root.deleteSync(recursive: true));

  List<String> gallery() => (docs
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .toList()
    ..sort());

  group('a device knows which device it is', () {
    // THE FIRST FAULT. A name that is the same on every device is not a name,
    // and this one ends up in a FILENAME.
    test('it is never just "localhost"', () {
      expect(LanSync.instance.deviceName.toLowerCase(), isNot('localhost'));
      expect(LanSync.instance.deviceName, isNotEmpty);
    });

    // The id keys a manifest per device in the cloud mirror, and it decides
    // who dials whom on the LAN. A fresh one per launch left an orphan
    // manifest in the bucket every time the app started.
    test('the id and name survive a restart', () {
      final id = LanSync.instance.deviceId;
      final name = LanSync.instance.deviceName;
      expect(id, isNotEmpty);

      // Same install, new process.
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);

      expect(LanSync.instance.deviceId, id,
          reason: 'the log for #86 has five ids for one iPad');
      expect(LanSync.instance.deviceName, name);
    });

    test('it is written down where the mirror cannot carry it', () {
      expect(File('${prefs.path}/sync-device.json').existsSync(), isTrue);
      // An identity that travelled would make every device the same device,
      // which is the failure it exists to prevent.
      expect(LanSync.mirroredPrefFilesForTest, isNot(contains('sync-device.json')));
    });

    // THE FAULT ITSELF, as a pure rule: a Linux runner cannot be made to
    // claim it is called `localhost`, so the decision is tested rather than
    // the platform.
    test('two devices that both say "localhost" still differ', () {
      final a = LanSync.nameFrom('localhost', 'ios', 'A_Mk_XqTOqSA');
      final b = LanSync.nameFrom('localhost', 'ios', 'Lr7gfhTnvz8K');
      expect(a, isNot(b),
          reason: 'both iPads called themselves localhost, so their conflict '
              'copies collided under one name and forked again');
      expect(a.toLowerCase(), isNot(contains('localhost')));
      expect(a, startsWith('ios-'));
    });

    test('an empty hostname is treated the same way', () {
      expect(LanSync.nameFrom('', 'ios', 'A_Mk_XqTOqSA'), startsWith('ios-'));
      expect(LanSync.nameFrom('   ', 'ios', 'A_Mk_XqTOqSA'),
          startsWith('ios-'));
    });

    // A desktop with a real hostname keeps it: it already distinguishes, and
    // "tomeler-laptop" reads better in a filename than "linux-7f3a".
    test('a real hostname is kept as it is', () {
      expect(LanSync.nameFrom('tomeler-laptop', 'linux', 'abc123'),
          'tomeler-laptop');
    });

    // The name lands in a FILENAME, so it must survive _safeName intact.
    test('the derived name is safe to put in a file name', () {
      final n = LanSync.nameFrom('localhost', 'ios', 'A_Mk/Xq+TOqSA');
      expect(n, matches(RegExp(r'^[A-Za-z0-9-]+$')));
    });
  });

  group('keeping both stops at keeping both', () {
    // THE REPORT. A conflict on a document that is ALREADY a conflict copy
    // must not make a third file.
    test('a copy of a copy is never written', () {
      File('${docs.path}/Part1 (ios-aaaa).ptp').writeAsStringSync('mine');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      LanSync.instance.setBaseForTest(
          'Part1 (ios-aaaa).ptp', _shaOf('what we agreed'));

      final theirs = SyncEntry(
        'Part1 (ios-aaaa).ptp',
        6,
        DateTime.now().millisecondsSinceEpoch + 5000, // newer
        _shaOf('theirs'),
        base: _shaOf('something else entirely'), // bases disagree -> was fork
      );
      LanSync.instance.mirrorApply(theirs, _bytes('theirs'),
          peerName: 'ios-bbbb');

      expect(gallery(), ['Part1 (ios-aaaa).ptp'],
          reason: 'Part1 (ios-aaaa) (ios-bbbb).ptp is the cascade');
      expect(File('${docs.path}/Part1 (ios-aaaa).ptp').readAsStringSync(),
          'theirs',
          reason: 'at that depth the newer version wins outright');
    });

    test('and the older one is still recoverable', () {
      File('${docs.path}/Part1 (ios-aaaa).ptp').writeAsStringSync('mine');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      LanSync.instance.setBaseForTest('Part1 (ios-aaaa).ptp', _shaOf('agreed'));
      LanSync.instance.mirrorApply(
          SyncEntry('Part1 (ios-aaaa).ptp', 6,
              DateTime.now().millisecondsSinceEpoch + 5000, _shaOf('theirs'),
              base: _shaOf('elsewhere')),
          _bytes('theirs'),
          peerName: 'ios-bbbb');
      expect(LanSync.instance.backups().map((b) => b.path),
          contains('Part1 (ios-aaaa).ptp'),
          reason: 'nothing is lost, it moves to the drawer');
    });

    // Losing must settle too, or the peer re-offers for ever — which is what
    // 101 identical lines in the log look like.
    test('losing at that depth settles instead of repeating', () {
      File('${docs.path}/Part1 (ios-aaaa).ptp').writeAsStringSync('mine');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      final older = SyncEntry('Part1 (ios-aaaa).ptp', 6, 1000, _shaOf('older'),
          base: _shaOf('elsewhere'));

      // Applied twice, as a peer re-announcing it would: the invariant that
      // matters is that neither round writes a file. (It is still fetched
      // again — the base-crossing rule cannot reconcile two copies — so the
      // cost of a stubborn peer is a download, never a document.)
      for (var i = 0; i < 2; i++) {
        expect(
            LanSync.instance
                .mirrorApply(older, _bytes('older'), peerName: 'ios-bbbb'),
            isFalse);
      }
      expect(gallery(), ['Part1 (ios-aaaa).ptp']);
      expect(File('${docs.path}/Part1 (ios-aaaa).ptp').readAsStringSync(),
          'mine');
    });

    // THE FIRST FORK IS STILL RIGHT. This is the whole point of M417 and must
    // not be traded away to stop the cascade.
    test('a genuine first conflict still keeps both', () {
      File('${docs.path}/Bracket.ptp').writeAsStringSync('mine');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));

      LanSync.instance.mirrorApply(
          SyncEntry('Bracket.ptp', 6, DateTime.now().millisecondsSinceEpoch,
              _shaOf('theirs'),
              base: _shaOf('agreed')),
          _bytes('theirs'),
          peerName: 'ios-bbbb');

      expect(gallery().length, 2, reason: 'neither version may be thrown away');
      expect(gallery(), contains('Bracket.ptp'));
    });
  });

  group('what counts as a copy', () {
    test('the shapes _freeCopyPath writes are recognised', () {
      for (final p in const [
        'Part1 (ios-7f3a).ptp',
        'Part1 (ios-7f3a) 2.ptp',
        'Lampenbefestigung Marshydro (localhost).ptp',
        'Part1 (localhost) (localhost).ptp',
      ]) {
        expect(LanSync.isConflictCopyForTest(p), isTrue, reason: p);
      }
    });

    // A document somebody named with brackets themselves is not a copy, and
    // must keep the full keep-both treatment.
    test('an ordinary name with no tag is not one', () {
      for (final p in const [
        'Part1.ptp',
        'Cable+holder+1.ptp',
        'Bracket v2.ptp',
        'Gewürzhalter.ptp',
      ]) {
        expect(LanSync.isConflictCopyForTest(p), isFalse, reason: p);
      }
    });
  });
}
