// M423 — "is it possible to somehow sync the files over a cloud instead".
//
// The answer this file is half of: not a cloud, an ADDRESS. Discovery is a UDP
// broadcast and an mDNS query, and both stop at the edge of the network, so
// two devices that cannot hear each other never pair however well they could
// talk if they were introduced. That is every pair on different networks — the
// iPad away from home, the PC on the desk — and it is the whole of what a
// cloud would have been bought for here: not storage, not an account, just a
// way for the two to reach each other.
//
// So the mirror can now be TOLD where the other device is. Put both on one
// overlay network (Tailscale, ZeroTier, a VPN), type the other one's address
// in Settings, and the same handshake, the same frames and the same conflict
// rule run over that instead. The overlay also brings what lan_sync.dart's
// header says the mirror does not have: on WireGuard the bytes are encrypted
// end to end.
//
// What is pinned here:
//   * the parser, because it is the part with the edge cases and because the
//     settings prompt validates with it — a typo has to be refused where it
//     was made, not become an address that is dialled for ever;
//   * that the address is remembered across a restart, and that turning
//     sharing off does not silently forget it.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/sync/lan_sync.dart';
import 'package:prototype/sync/share_code.dart';
import 'package:prototype/sync/sync_protocol.dart' show kSyncFirstDataPort;
import 'package:prototype/sync/sync_store.dart';

void main() {
  group('reading an address a person typed', () {
    test('a bare host or IP gets the mirror\'s own port', () {
      expect(parseSyncAddress('100.64.0.2')!.host, '100.64.0.2');
      expect(parseSyncAddress('100.64.0.2')!.port, kSyncFirstDataPort);
      expect(parseSyncAddress('tom-pc.tail1234.ts.net')!.host,
          'tom-pc.tail1234.ts.net');
      expect(parseSyncAddress('laptop.local')!.port, kSyncFirstDataPort);
    });

    test('a port may be given, and is checked', () {
      expect(parseSyncAddress('100.64.0.2:47822')!.port, 47822);
      expect(parseSyncAddress('100.64.0.2:0'), isNull);
      expect(parseSyncAddress('100.64.0.2:70000'), isNull);
      expect(parseSyncAddress('100.64.0.2:'), isNull);
      expect(parseSyncAddress('100.64.0.2:port'), isNull);
    });

    test('IPv6 is read the way it is written', () {
      // Bare, it cannot carry a port — the colons are the address.
      expect(parseSyncAddress('fd7a:115c::1')!.host, 'fd7a:115c::1');
      expect(parseSyncAddress('fd7a:115c::1')!.port, kSyncFirstDataPort);
      // In brackets, it can.
      expect(parseSyncAddress('[fd7a:115c::1]:47822')!.host, 'fd7a:115c::1');
      expect(parseSyncAddress('[fd7a:115c::1]:47822')!.port, 47822);
      expect(parseSyncAddress('[fd7a:115c::1]')!.port, kSyncFirstDataPort);
      expect(parseSyncAddress('[fd7a:115c::1'), isNull);
      expect(parseSyncAddress('[]:47821'), isNull);
    });

    test('what is not an address is refused rather than guessed at', () {
      // A URL, a sentence and an empty field are all things somebody will put
      // in this box, and dialling a guess at any of them would look exactly
      // like a network that is not working.
      expect(parseSyncAddress(''), isNull);
      expect(parseSyncAddress('   '), isNull);
      expect(parseSyncAddress('http://100.64.0.2'), isNull);
      expect(parseSyncAddress('my laptop'), isNull);
      expect(parseSyncAddress('user@host'), isNull);
      expect(parseSyncAddress('host/path'), isNull);
    });

    test('surrounding space is forgiven', () {
      expect(parseSyncAddress('  100.64.0.2:47821  ')!.host, '100.64.0.2');
    });
  });

  group('remembering it', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('m423peer');
      ShareCodes.resetForTest();
    });

    tearDown(() async {
      await LanSync.instance.setManualPeer(null);
      ShareCodes.resetForTest();
      dir.deleteSync(recursive: true);
    });

    test('it survives a restart and leaves the rest of the file alone', () {
      final store = SyncStore(dir);
      File('${dir.path}/settings.json')
          .writeAsStringSync(jsonEncode({'appearance': 'dark'}));
      store.savePeer('100.64.0.2:47821');
      expect(store.load(), isNull, reason: 'an address is not a share code');
      expect(SyncStore(dir).loadPeer(), '100.64.0.2:47821');
      final data =
          jsonDecode(File('${dir.path}/settings.json').readAsStringSync());
      expect((data as Map)['appearance'], 'dark');
    });

    test('the code and the address do not overwrite each other', () {
      final store = SyncStore(dir);
      final code = normaliseShareCode(generateShareCode())!;
      store.save(code);
      store.savePeer('laptop.local');
      expect(store.load(), code);
      expect(store.loadPeer(), 'laptop.local');

      // TURNING SHARING OFF MUST NOT FORGET THE ADDRESS. It used to write the
      // whole `sync` section from scratch, so clearing either field took the
      // other with it — and someone who switched sharing off and on again
      // would be back to a status row that says "looking" with nothing on the
      // screen explaining why.
      store.save(null);
      expect(store.load(), isNull);
      expect(store.loadPeer(), 'laptop.local');
    });

    test('clearing it empties the field rather than the file', () {
      final store = SyncStore(dir);
      store.savePeer('laptop.local');
      store.savePeer(null);
      expect(store.loadPeer(), isNull);
      expect(File('${dir.path}/settings.json').existsSync(), isTrue);
    });

    test('setting it reaches the mirror and the store together', () async {
      final store = SyncStore(dir);
      ShareCodes.attachStore(store);
      await ShareCodes.setPeer(' laptop.local ');
      expect(ShareCodes.peer.value, 'laptop.local',
          reason: 'trimmed, or the same address typed twice is two addresses');
      expect(LanSync.instance.manualPeer, 'laptop.local');
      expect(store.loadPeer(), 'laptop.local');

      await ShareCodes.setPeer('');
      expect(ShareCodes.peer.value, isNull,
          reason: 'an empty field is how it is removed');
      expect(LanSync.instance.manualPeer, isNull);
      expect(store.loadPeer(), isNull);
    });

    test('a remembered address is adopted at startup', () async {
      SyncStore(dir).savePeer('100.64.0.2');
      ShareCodes.attachStore(SyncStore(dir));
      expect(ShareCodes.peer.value, '100.64.0.2');
      expect(LanSync.instance.manualPeer, '100.64.0.2');
    });
  });
}
