// M383 — what makes the mirror LIVE rather than merely correct.
//
// M381 pinned what crosses the wire. This pins the decisions that turn a
// mirror which eventually agrees into one that agrees at once, and every one
// of them is here because its failure is invisible from inside the app:
//
//   * a hash that is cached when it should not be reads a changed document as
//     unchanged, and the change simply never travels;
//   * a dial rule that assumes both devices can see each other leaves an iPad
//     and a PC a metre apart saying "looking" at each other for ever;
//   * an mDNS query without the unicast-reply bit is answered into a Windows
//     firewall, and nothing anywhere reports a packet that was dropped;
//   * an announcement that advertises the wrong one of a machine's addresses
//     is a peer that is found and then cannot be reached.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/sync/share_code.dart';
import 'package:prototype/sync/lan_sync.dart';
import 'package:prototype/sync/mdns.dart';
import 'package:prototype/sync/sync_protocol.dart';

void main() {
  // The mirror reaches for a platform channel when it starts (Bonjour, where
  // there is a plugin behind it), and an uninitialised binding turns that into
  // a paragraph of warning on the way past. Initialising it keeps the log to
  // what these tests are about.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('who dials whom', () {
    // The ordinary case: both devices can see each other, and exactly one of
    // them opens the connection.
    test('the lower id dials immediately, the higher one waits', () {
      expect(
          shouldDial(myId: 'aaa', peerId: 'bbb', seenFor: Duration.zero), isTrue);
      expect(
          shouldDial(myId: 'bbb', peerId: 'aaa', seenFor: Duration.zero), isFalse);
    });

    test('and only one of them does, at every moment of the grace period', () {
      for (final d in [
        Duration.zero,
        const Duration(seconds: 1),
        const Duration(seconds: 3),
        LanSync.dialGrace - const Duration(milliseconds: 1),
      ]) {
        expect(shouldDial(myId: 'aaa', peerId: 'bbb', seenFor: d), isTrue);
        expect(shouldDial(myId: 'bbb', peerId: 'aaa', seenFor: d), isFalse,
            reason: '$d');
      }
    });

    // THE ONE THIS EXISTS FOR. An iPad cannot send or hear the UDP beacon
    // without an entitlement Apple grants case by case; a Windows machine
    // cannot always answer on port 5353. Either leaves one device seeing a
    // peer that is blind to it — and if the sighted one holds the higher id,
    // the old rule meant nobody ever dialled.
    test('the higher id dials anyway once the other has plainly not', () {
      expect(shouldDial(myId: 'zzz', peerId: 'aaa', seenFor: LanSync.dialGrace),
          isTrue);
      expect(
          shouldDial(
              myId: 'zzz',
              peerId: 'aaa',
              seenFor: LanSync.dialGrace + const Duration(seconds: 30)),
          isTrue);
    });

    test('a device never dials itself, however long it has been seen', () {
      expect(
          shouldDial(
              myId: 'same', peerId: 'same', seenFor: const Duration(hours: 1)),
          isFalse);
    });
  });

  group('the local scan notices a change', () {
    late Directory root;
    late Directory docs;
    late Directory prefs;

    setUp(() {
      root = Directory.systemTemp.createTempSync('m383');
      docs = Directory('${root.path}/docs')..createSync();
      prefs = Directory('${root.path}/prefs')..createSync();
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('a scan of an unchanged gallery is stable', () {
      File('${docs.path}/Bracket.ptp').writeAsStringSync('hello');
      final a = LanSync.instance.scanForTest();
      final b = LanSync.instance.scanForTest();
      expect(b['Bracket.ptp']!.sha, a['Bracket.ptp']!.sha);
      expect(b['Bracket.ptp']!.mtimeMs, a['Bracket.ptp']!.mtimeMs);
    });

    // The hash cache is keyed on size and modification time, which cannot see
    // a file rewritten to the SAME length inside one clock tick — and a
    // preferences file with one boolean toggled is exactly that shape on a
    // filesystem with one-second timestamps. So a recently written file is
    // re-read rather than trusted.
    test('a same-length rewrite is still seen', () {
      final f = File('${prefs.path}/settings.json');
      f.writeAsStringSync('{"a":1}');
      final before = LanSync.instance.scanForTest();
      f.writeAsStringSync('{"a":2}'); // same length, same second
      final after = LanSync.instance.scanForTest();
      expect(after['settings/settings.json']!.sha,
          isNot(before['settings/settings.json']!.sha));
    });

    test('a document rewritten to a different length is seen', () {
      final f = File('${docs.path}/Plate.pts');
      f.writeAsStringSync('one');
      final before = LanSync.instance.scanForTest();
      f.writeAsStringSync('one and a half');
      final after = LanSync.instance.scanForTest();
      expect(after['Plate.pts']!.sha, isNot(before['Plate.pts']!.sha));
      expect(after['Plate.pts']!.size, 14);
    });

    test('a deleted document leaves the manifest', () {
      final f = File('${docs.path}/Gone.ptp')..writeAsStringSync('x');
      expect(LanSync.instance.scanForTest().containsKey('Gone.ptp'), isTrue);
      f.deleteSync();
      expect(LanSync.instance.scanForTest().containsKey('Gone.ptp'), isFalse);
    });
  });

  group('what this device puts on the mDNS wire', () {
    // The bit that makes an answer reach a Windows machine at all: its
    // firewall drops inbound multicast in its default state, and lets a
    // unicast reply back in only because the query that asked for it went out
    // moments earlier.
    test('the browse question asks for a unicast reply', () {
      final q = mdnsQueryPacket();
      // Header: 12 bytes, one question, no answers.
      final bd = ByteData.sublistView(q);
      expect(bd.getUint16(2) & 0x8000, 0, reason: 'a query, not a response');
      expect(bd.getUint16(4), 1, reason: 'exactly one question');
      // QCLASS is the last two bytes of the question, and its top bit is QU.
      final qclass = bd.getUint16(q.length - 2);
      expect(qclass & 0x8000, 0x8000, reason: 'the unicast-reply bit');
      expect(qclass & 0x7fff, 1, reason: 'class IN');
    });

    test('the question names the service Info.plist advertises', () {
      expect(utf8.decode(mdnsQueryPacket(), allowMalformed: true),
          contains('prototypesync'));
    });

    Uint8List announce({String id = 'peer-1', String fp = 'FINGERPRINT'}) =>
        mdnsAnnouncePacket(
          deviceId: id,
          deviceName: 'Toms iPad',
          fingerprint: fp,
          version: kSyncProtocolVersion,
          port: 47821,
          self: InternetAddress('192.168.1.40'),
        );

    test('an announcement reads back as the device that sent it', () {
      final s = mdnsSightingFromPacket(announce(),
          fingerprint: 'FINGERPRINT', selfId: 'me');
      expect(s, isNotNull);
      expect(s!.id, 'peer-1');
      expect(s.name, 'Toms iPad');
      expect(s.host, '192.168.1.40');
      expect(s.port, 47821);
      expect(s.version, kSyncProtocolVersion);
    });

    test('a device ignores its own announcement coming back', () {
      expect(
          mdnsSightingFromPacket(announce(id: 'me'),
              fingerprint: 'FINGERPRINT', selfId: 'me'),
          isNull);
    });

    test('a device sharing a different code is not a peer', () {
      expect(
          mdnsSightingFromPacket(announce(fp: 'SOMEONE-ELSE'),
              fingerprint: 'FINGERPRINT', selfId: 'me'),
          isNull);
    });

    // A machine with a virtual adapter — Hyper-V, WSL, a VPN — may advertise
    // an address nothing outside itself can reach. The address the packet
    // actually arrived from demonstrably can.
    test('an unusable advertised address gives way to the source address', () {
      final packet = mdnsAnnouncePacket(
        deviceId: 'peer-2',
        deviceName: 'PC',
        fingerprint: 'FINGERPRINT',
        version: kSyncProtocolVersion,
        port: 47822,
        self: null, // the sender could not work out its own address
      );
      final s = mdnsSightingFromPacket(packet,
          fingerprint: 'FINGERPRINT',
          selfId: 'me',
          source: InternetAddress('192.168.1.77'));
      expect(s, isNotNull);
      expect(s!.host, '192.168.1.77');
    });

    test('and with neither an address nor a source there is no sighting', () {
      final packet = mdnsAnnouncePacket(
        deviceId: 'peer-3',
        deviceName: 'PC',
        fingerprint: 'FINGERPRINT',
        version: kSyncProtocolVersion,
        port: 47823,
        self: null,
      );
      expect(
          mdnsSightingFromPacket(packet,
              fingerprint: 'FINGERPRINT', selfId: 'me'),
          isNull);
    });

    test('a query is not mistaken for an announcement', () {
      expect(
          mdnsSightingFromPacket(mdnsQueryPacket(),
              fingerprint: 'FINGERPRINT', selfId: 'me'),
          isNull);
    });

    test('the traffic of every other service on the LAN is ignored', () {
      for (final junk in [
        Uint8List(0),
        Uint8List.fromList(const [1, 2, 3]),
        Uint8List.fromList(utf8.encode('not dns at all, just bytes')),
      ]) {
        expect(
            mdnsSightingFromPacket(junk,
                fingerprint: 'FINGERPRINT', selfId: 'me'),
            isNull);
      }
    });
  });

  group('a session proves it is still there', () {
    // A half-open socket — what a Wi-Fi change or a sleeping laptop leaves
    // behind — is indistinguishable from a quiet one until something is
    // written down it. These two frame types are that something.
    test('ping and pong are distinct types that survive a round trip', () {
      expect(SyncMsg.ping, isNot(SyncMsg.pong));
      for (final t in [SyncMsg.ping, SyncMsg.pong]) {
        final frames = SyncFrameReader().add(SyncFrame({'t': t}).encode());
        expect(frames, hasLength(1));
        expect(frames.single.type, t);
        expect(frames.single.payload, isNull);
      }
    });

    test('an older peer that ignores them is not misread', () {
      // The reader hands an unknown type up unchanged; the session's default
      // branch drops it rather than hanging up, which is what lets a new
      // build talk to an old one at all.
      final frames =
          SyncFrameReader().add(SyncFrame({'t': 'something-newer'}).encode());
      expect(frames.single.type, 'something-newer');
    });
  });


  group('changing the code twice in a row', () {
    // Every code change stops one mirror and starts another, and both halves
    // await sockets — so two that overlap interleave, and the one that STARTED
    // first can finish last and assign its own code over the newer one's. The
    // shape it was found in: a share code on screen, a listener up, and a
    // status row saying "off".
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('m383code');
      LanSync.instance.attachForTest(
        documents: Directory('${root.path}/docs')..createSync(),
        preferences: Directory('${root.path}/prefs')..createSync(),
      );
    });

    tearDown(() async {
      await LanSync.instance.setCode(null);
      root.deleteSync(recursive: true);
    });

    test('ends on the second one, not on whichever finished last', () async {
      final first = normaliseShareCode(generateShareCode());
      final second = normaliseShareCode(generateShareCode());
      // Deliberately not awaited in turn: this is the sequence a person
      // produces by typing a code and then changing their mind.
      final a = LanSync.instance.setCode(first);
      final b = LanSync.instance.setCode(second);
      await Future.wait([a, b]);
      expect(LanSync.instance.code, second);
      expect(LanSync.instance.enabled, isTrue);
      expect(LanSync.instance.status.value.state, isNot(SyncState.off),
          reason: 'a mirror that is on must not report itself off');
    });

    test('and turning it off last really turns it off', () async {
      final a = LanSync.instance.setCode(normaliseShareCode(generateShareCode()));
      final b = LanSync.instance.setCode(null);
      await Future.wait([a, b]);
      expect(LanSync.instance.code, isNull);
      expect(LanSync.instance.enabled, isFalse);
      expect(LanSync.instance.status.value.state, SyncState.off);
    });
  });
}
