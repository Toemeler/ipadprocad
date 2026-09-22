// M441 — the same mirror, through a bucket instead of a socket.
//
// `lan_sync.dart` says what it cannot do: "It is NOT a cloud. There is no
// server, no account and nothing leaves the local network." M423 softened that
// with a typed-in address over an overlay, which still needs BOTH DEVICES
// SWITCHED ON AT ONCE — so the iPad edited on a train and the desktop opened
// that evening never sync. `cloud_sync.dart` removes the "at once" by leaving
// files somewhere the other device reads whenever it next runs.
//
// WHAT IS PINNED HERE is the claim the whole design rests on: THE CLOUD IS A
// TRANSPORT AND DECIDES NOTHING. Every rule about what wins stays in LanSync
// and is reached through the M441 forwarders, so a document arriving from a
// bucket meets byte for byte the rules a document from a socket meets. If
// that ever stops being true, the two halves of this app will disagree about
// somebody's work, silently, and these are the tests that should fail first.
//
// The wire itself is not tested here and cannot usefully be: it is one HTTP
// call per step against a Worker, and a fake of it would only assert that the
// fake was called. What IS testable without a network is everything that
// decides what goes over that wire, which is all of the below. The signer the
// Worker uses is checked separately against AWS's own published vector — see
// `cloud/test/sigv4.test.mjs`.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/sync/cloud_sync.dart';
import 'package:prototype/sync/lan_sync.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));
String _shaOf(String s) => sha256.convert(_bytes(s)).toString();

void main() {
  late Directory root;
  late Directory docs;
  late Directory prefs;

  setUp(() {
    root = Directory.systemTemp.createTempSync('m441');
    docs = Directory('${root.path}/docs')..createSync();
    prefs = Directory('${root.path}/prefs')..createSync();
    LanSync.instance.attachForTest(documents: docs, preferences: prefs);
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('the manifest that travels', () {
    test('survives the round trip it is written for', () {
      final manifest = CloudManifest(
        device: 'abc123',
        deviceName: 'the iPad',
        atMs: 1700000000000,
        entries: [
          SyncEntry('Bracket.ptp', 42, 1700000000000, _shaOf('bracket'),
              base: _shaOf('older bracket')),
          SyncEntry('settings/settings.json', 7, 1699999999000, _shaOf('prefs')),
        ],
        tombs: [SyncTomb('Gone.ptp', 1699000000000, _shaOf('gone'))],
      );

      final back = CloudManifest.fromJson(
          jsonDecode(jsonEncode(manifest.toJson())));

      expect(back, isNotNull);
      expect(back!.device, 'abc123');
      expect(back.deviceName, 'the iPad');
      expect(back.entries.length, 2);
      expect(back.entries.first.path, 'Bracket.ptp');
      expect(back.entries.first.sha, _shaOf('bracket'));
      expect(back.tombs.single.path, 'Gone.ptp');
      expect(back.tombs.single.sha, _shaOf('gone'));
    });

    // THE BASE IS THE POINT OF M423 AND MUST SURVIVE THE BUCKET. Without it
    // `verdictFor` cannot tell "only they moved on" from "both of us did", and
    // a pair of devices swaps two versions back and forth for ever instead of
    // forking once and stopping.
    test('carries the version the group last agreed on', () {
      final entry = SyncEntry('Bracket.ptp', 42, 1700000000000,
          _shaOf('now'), base: _shaOf('agreed'));
      final back = CloudManifest.fromJson(jsonDecode(jsonEncode(CloudManifest(
        device: 'd',
        deviceName: 'n',
        atMs: 1,
        entries: [entry],
        tombs: const [],
      ).toJson())));
      expect(back!.entries.single.base, _shaOf('agreed'));
    });

    // One unreadable record costs one document this cycle; refusing the whole
    // manifest costs every document that device holds. Same reasoning as
    // SyncEntry.fromJson returning null per entry rather than throwing.
    test('drops a broken entry without losing the good ones', () {
      final back = CloudManifest.fromJson({
        'device': 'd',
        'name': 'n',
        'at': 1,
        'entries': [
          {'p': 'Good.ptp', 's': 1, 'm': 2, 'h': 'abc'},
          {'s': 1, 'm': 2, 'h': 'no path at all'},
          'not even an object',
        ],
        'tombs': [
          {'p': 'Gone.ptp', 'd': 5},
          {'p': 'no date'},
        ],
      });
      expect(back!.entries.single.path, 'Good.ptp');
      expect(back.tombs.single.path, 'Gone.ptp');
    });

    // The LAN protocol ignores unknown header keys on purpose so a newer peer
    // can add a field without an older one refusing the frame. A manifest is
    // read by the same fleet of mixed versions and needs the same property.
    test('ignores a field a newer version added', () {
      final back = CloudManifest.fromJson({
        'v': 99,
        'device': 'd',
        'name': 'n',
        'at': 1,
        'entries': <Object?>[],
        'tombs': <Object?>[],
        'somethingTheFutureAdded': {'deeply': ['nested']},
      });
      expect(back, isNotNull);
      expect(back!.device, 'd');
    });

    test('is nothing at all without a device to attribute it to', () {
      expect(CloudManifest.fromJson({'name': 'n', 'entries': []}), isNull);
      expect(CloudManifest.fromJson({'device': '', 'entries': []}), isNull);
      expect(CloudManifest.fromJson('not a manifest'), isNull);
      expect(CloudManifest.fromJson(null), isNull);
    });

    // A manifest from a peer too old to send a name still has to be usable:
    // the name is only ever a label on a kept-both copy, and losing it must
    // not lose the documents.
    test('a manifest with no name still names the fork something', () {
      final back = CloudManifest.fromJson({'device': 'd', 'entries': []});
      expect(back!.deviceName, isNotEmpty);
    });
  });

  group('the cloud decides nothing', () {
    // The load-bearing claim. `mirrorWants` is `_wants` is `verdictFor`, so
    // the cloud cannot want a file the LAN would have refused — which is what
    // stops a bucket from resurrecting something a delete already settled.
    test('it refuses what a peer on the wire would be refused', () {
      File('${docs.path}/Part1.ptp').writeAsStringSync('drawn today');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      final fresh = LanSync.instance.localManifestForTest['Part1.ptp']!;
      LanSync.instance.setBaseForTest('Part1.ptp', fresh.sha);

      // Exactly the M425 report, arriving from a bucket instead of a socket:
      // a stale bare tombstone for a name that has been handed out again.
      final stale = SyncTomb(
          'Part1.ptp',
          DateTime.now()
              .subtract(const Duration(days: 20))
              .millisecondsSinceEpoch);
      expect(LanSync.instance.mirrorApplyTomb(stale), isFalse);
      expect(File('${docs.path}/Part1.ptp').existsSync(), isTrue);
    });

    test('bytes that do not match their entry are dropped', () {
      final lying = SyncEntry('Bracket.ptp', 5,
          DateTime.now().millisecondsSinceEpoch, _shaOf('what it claims'));
      expect(
          LanSync.instance
              .mirrorApply(lying, _bytes('what it is'), peerName: 'the bucket'),
          isFalse);
      expect(File('${docs.path}/Bracket.ptp').existsSync(), isFalse);
    });

    test('a document this device has never seen is taken', () {
      final entry = SyncEntry('Bracket.ptp', 7,
          DateTime.now().millisecondsSinceEpoch, _shaOf('bracket'));
      expect(LanSync.instance.mirrorWants(entry), isTrue);
      expect(
          LanSync.instance
              .mirrorApply(entry, _bytes('bracket'), peerName: 'the bucket'),
          isTrue);
      expect(File('${docs.path}/Bracket.ptp').readAsStringSync(), 'bracket');
    });

    test('a document already held byte for byte is not downloaded again', () {
      File('${docs.path}/Bracket.ptp').writeAsStringSync('bracket');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      final mine = LanSync.instance.localManifestForTest['Bracket.ptp']!;
      expect(
          LanSync.instance.mirrorWants(
              SyncEntry('Bracket.ptp', mine.size, mine.mtimeMs, mine.sha)),
          isFalse);
    });

    // Both devices moved on from the same base. On a LAN this keeps both
    // copies; through a bucket it must do the very same thing.
    test('a divergence still keeps both copies', () {
      File('${docs.path}/Bracket.ptp').writeAsStringSync('mine');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('what we agreed'));

      final theirs = SyncEntry(
        'Bracket.ptp',
        6,
        DateTime.now().millisecondsSinceEpoch,
        _shaOf('theirs'),
        base: _shaOf('what we agreed'),
      );
      expect(LanSync.instance.mirrorWants(theirs), isTrue);
      expect(
          LanSync.instance
              .mirrorApply(theirs, _bytes('theirs'), peerName: 'the desktop'),
          isTrue);

      final kept = docs
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList()
        ..sort();
      expect(kept.length, 2, reason: 'neither version may be thrown away');
      expect(kept, contains('Bracket.ptp'),
          reason: 'the newer version keeps the name');

      // The second file is named after the device that OWNED the version
      // being set aside — not after the one the bytes arrived from. Here that
      // is us, because our 'mine' is the older of the two. See [SyncFork.owner].
      final fork = LanSync.instance.recentForks.value.last;
      expect(fork.original, 'Bracket.ptp');
      expect(kept, contains(fork.copy));
      expect(fork.copy, isNot('Bracket.ptp'));
    });
  });

  group('what this device offers the bucket', () {
    test('notices a deletion before it publishes anything', () {
      File('${docs.path}/Gone.ptp').writeAsStringSync('here for now');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      expect(LanSync.instance.mirrorState().entries.map((e) => e.path),
          contains('Gone.ptp'));

      File('${docs.path}/Gone.ptp').deleteSync();

      // The one call does the noticing. A cycle that skipped it would upload
      // a document this device has already thrown away.
      final state = LanSync.instance.mirrorState();
      expect(state.entries.map((e) => e.path), isNot(contains('Gone.ptp')));
      expect(state.tombs.map((t) => t.path), contains('Gone.ptp'));
    });

    test('offers the agreed version alongside each entry', () {
      File('${docs.path}/Bracket.ptp').writeAsStringSync('bracket');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      LanSync.instance.setBaseForTest('Bracket.ptp', _shaOf('agreed'));
      final entry = LanSync.instance
          .mirrorState()
          .entries
          .firstWhere((e) => e.path == 'Bracket.ptp');
      expect(entry.base, _shaOf('agreed'));
    });

    test('reads back the bytes it is about to upload', () {
      File('${docs.path}/Bracket.ptp').writeAsStringSync('bracket');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      expect(utf8.decode(LanSync.instance.bytesFor('Bracket.ptp')!), 'bracket');
    });

    test('has nothing to read for a document that went away', () {
      expect(LanSync.instance.bytesFor('NeverExisted.ptp'), isNull);
    });

    // The uploader must not be the one place in the mirror a crafted path
    // reaches outside the gallery. `bytesFor` goes through `_fileFor`, which
    // is where that is refused — so this is testing that it kept doing so.
    test('refuses a path that climbs out of the gallery', () {
      for (final path in const [
        '../settings.json',
        '/etc/passwd',
        'nested/Bracket.ptp',
        r'..\windows',
        'Bracket.exe',
      ]) {
        expect(LanSync.instance.bytesFor(path), isNull,
            reason: '$path must not be readable');
      }
    });
  });

  // ---------------------------------------------------------------------
  // WHAT MUST NEVER LEAVE THE DEVICE
  //
  // A bug bundle is written to `<docs>/bugreports/*.zip` — inside the very
  // directory the mirror watches (`bug_capture.dart` → `_docsRoot`, which is
  // `AppState.docsDir`, which is what `LanSync.attach` is given). It holds a
  // screenshot of the whole window, log tails and enough of the model to
  // rebuild the sketch. It has its own destination and its own consent: the
  // report dialog, and the relay in `relay/`.
  //
  // It is excluded from the mirror today by three separate accidents of the
  // LAN design — a non-recursive scan, an extension list, and a path check.
  // Three accidents are not a guarantee, and the cost of one of them being
  // relaxed for an unrelated reason is a screenshot of somebody's screen in a
  // bucket. So all three are pinned here.
  // ---------------------------------------------------------------------
  group('a bug report never reaches the bucket', () {
    late Directory reports;

    setUp(() {
      reports = Directory('${docs.path}/bugreports')..createSync();
      File('${reports.path}/bug-2026-09-22T101500.zip')
          .writeAsStringSync('a screenshot and the logs');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
    });

    test('it is not among the things this device offers', () {
      final offered = LanSync.instance.mirrorState().entries;
      expect(offered, isEmpty,
          reason: 'the gallery holds no documents — only a bug bundle');
      expect(offered.map((e) => e.path).where((p) => p.contains('bug')),
          isEmpty);
    });

    test('a document beside it is offered, so the scan really ran', () {
      File('${docs.path}/Bracket.ptp').writeAsStringSync('a real document');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      expect(LanSync.instance.mirrorState().entries.map((e) => e.path),
          ['Bracket.ptp'],
          reason: 'exactly one: the document, never the bundle');
    });

    // Barrier two, on its own: even without the subdirectory, a .zip is not a
    // document. This is what stops a bundle that somehow lands at the top
    // level from travelling.
    test('a zip at the top level is not a document either', () {
      File('${docs.path}/bug-loose.zip').writeAsStringSync('a stray bundle');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      expect(LanSync.instance.mirrorState().entries, isEmpty);
    });

    // Barrier three, on its own: the uploader cannot read one even if
    // something asked it to by name. `bytesFor` is the only way bytes reach
    // the cloud, and it goes through `_fileFor`.
    test('the uploader cannot read one even when named outright', () {
      for (final path in const [
        'bugreports/bug-2026-09-22T101500.zip',
        'bug-loose.zip',
        'bugreports/',
      ]) {
        expect(LanSync.instance.bytesFor(path), isNull,
            reason: '$path must not be readable by the uploader');
      }
    });

    // And the reverse direction: a manifest naming a bundle — from a peer, a
    // bucket, or a bug — must not be able to write one into the gallery.
    test('one cannot be written back in from a manifest', () {
      final smuggled = SyncEntry('bugreports/evil.zip', 4,
          DateTime.now().millisecondsSinceEpoch, _shaOf('payload'));
      expect(
          LanSync.instance
              .mirrorApply(smuggled, _bytes('payload'), peerName: 'a peer'),
          isFalse);
      expect(File('${docs.path}/bugreports/evil.zip').existsSync(), isFalse);
    });

    // The logs themselves live beside the bundles and are no less personal.
    test('logs are not offered either', () {
      File('${docs.path}/prototype.log').writeAsStringSync('every action');
      Directory('${docs.path}/logs').createSync();
      File('${docs.path}/logs/perf.log').writeAsStringSync('timings');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      expect(LanSync.instance.mirrorState().entries, isEmpty);
      expect(LanSync.instance.bytesFor('prototype.log'), isNull);
      expect(LanSync.instance.bytesFor('logs/perf.log'), isNull);
    });
  });

  group('the cloud stays out of the way when it is not configured', () {
    // Every existing build config leaves CLOUD_SYNC_URL unset, and that has to
    // mean the app behaves exactly as it did before this file existed — no
    // timer, no request, nothing to go wrong on a device that never opted in.
    test('nothing is configured in a build with no url', () {
      expect(cloudSyncConfigured, isFalse);
      expect(cloudSyncUrl, isEmpty);
    });

    test('setting a code without a url starts nothing', () async {
      await CloudSync.instance.setCode('23456789ABCD');
      expect(CloudSync.instance.enabled, isFalse);
      expect(CloudSync.instance.status.value.state, CloudState.off);
      CloudSync.instance.resetForTest();
    });

    test('a nudge on an unconfigured build is a no-op', () {
      CloudSync.instance.nudge();
      expect(CloudSync.instance.status.value.state, CloudState.off);
    });

    test('a cycle on an unconfigured build reports off, not failed', () async {
      final result = await CloudSync.instance.syncNow();
      expect(result.outcome, CloudOutcome.off);
    });
  });

  group('status', () {
    // A ValueNotifier published every cycle: without value equality every
    // listener is woken twice a minute to be told what it already knew, and
    // the settings row redraws through a platform channel for nothing. The
    // same reasoning SyncStatus records for itself.
    test('two identical statuses are equal, so listeners stay quiet', () {
      const a = CloudStatus(CloudState.idle, devices: 2);
      const b = CloudStatus(CloudState.idle, devices: 2);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different device count is a different status', () {
      expect(const CloudStatus(CloudState.idle, devices: 2),
          isNot(const CloudStatus(CloudState.idle, devices: 3)));
    });
  });
}
