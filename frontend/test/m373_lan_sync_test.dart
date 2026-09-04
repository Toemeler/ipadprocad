// M373 — the share code, the wire, and the rule about who wins.
//
// The network half of this feature is exercised end to end by running two
// copies of the app with different data directories (see LINUX.md); what is
// pinned here is everything that decides WHAT crosses the wire and what
// happens to it when it lands, because those are the parts whose failure is
// silent and expensive: a mirror that copies a file back and forth forever, a
// peer that can write outside the document folder, a settings merge that takes
// somebody else's share code.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/sync/lan_sync.dart';
import 'package:prototype/sync/share_code.dart';
import 'package:prototype/sync/sync_protocol.dart';
import 'package:prototype/sync/sync_store.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('the share code', () {
    test('a generated code reads back as itself', () {
      for (var i = 0; i < 50; i++) {
        final shown = generateShareCode();
        expect(shown, matches(RegExp(r'^[0-9A-Z]{4}-[0-9A-Z]{4}-[0-9A-Z]{4}$')));
        final canonical = normaliseShareCode(shown);
        expect(canonical, isNotNull);
        expect(canonical!.length, kShareCodeLength);
        expect(formatShareCode(canonical), shown);
      }
    });

    test('it is typed by a person, so it is read like one', () {
      final code = normaliseShareCode(generateShareCode())!;
      final shown = formatShareCode(code);
      // Lower case, spaces instead of hyphens, no separators at all: three
      // ways the same code arrives from three people.
      expect(normaliseShareCode(shown.toLowerCase()), code);
      expect(normaliseShareCode(shown.replaceAll('-', ' ')), code);
      expect(normaliseShareCode(shown.replaceAll('-', '')), code);
    });

    test('the look-alikes are refused rather than guessed at', () {
      // I/O/1/0 are not in the alphabet, and a code is not the place to guess
      // which one somebody meant.
      for (final bad in ['ABCD-EFGH-JKL1', 'ABCD-EFGH-JKLO', 'ABCD-EFGH-JKLI']) {
        expect(normaliseShareCode(bad), isNull, reason: bad);
      }
      // And the wrong length is not a code either.
      expect(normaliseShareCode('ABCD-EFGH'), isNull);
      expect(normaliseShareCode('ABCD-EFGH-JKLM-N'), isNull);
      expect(normaliseShareCode(''), isNull);
    });

    test('the key and the fingerprint are not the same value', () {
      // The fingerprint is broadcast in the clear. If it were derived the same
      // way as the key, hearing a beacon would be knowing the key.
      final code = normaliseShareCode(generateShareCode())!;
      final key = shareCodeKey(code);
      final fp = shareCodeFingerprint(code);
      final keyHex =
          key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      expect(keyHex.startsWith(fp), isFalse);
      expect(keyHex.contains(fp), isFalse);
    });

    test('a different code is a different group and a different key', () {
      final a = normaliseShareCode(generateShareCode())!;
      final b = normaliseShareCode(generateShareCode())!;
      expect(shareCodeFingerprint(a), isNot(shareCodeFingerprint(b)));
      final nonce = newNonce();
      expect(shareCodeProof(shareCodeKey(a), nonce),
          isNot(shareCodeProof(shareCodeKey(b), nonce)));
    });

    test('a proof answers the nonce it was given, and only that one', () {
      final key = shareCodeKey(normaliseShareCode(generateShareCode())!);
      final n1 = newNonce(), n2 = newNonce();
      expect(secureEquals(shareCodeProof(key, n1), shareCodeProof(key, n1)),
          isTrue);
      expect(secureEquals(shareCodeProof(key, n1), shareCodeProof(key, n2)),
          isFalse);
      // A replayed nonce is what the handshake's freshness rests on.
      expect(n1, isNot(n2));
    });

    test('secureEquals is an equality, whatever else it is', () {
      expect(secureEquals('', ''), isTrue);
      expect(secureEquals('abc', 'abc'), isTrue);
      expect(secureEquals('abc', 'abd'), isFalse);
      expect(secureEquals('abc', 'ab'), isFalse);
    });
  });

  group('the wire', () {
    test('a frame survives being cut anywhere', () {
      final frame = SyncFrame({'t': SyncMsg.file, 'x': 1}, _bytes('hello'));
      final wire = frame.encode();
      // Every split point, including inside the length prefix and inside the
      // payload. A socket hands out whatever arrived, and this is the whole
      // class of bug that costs a week.
      for (var cut = 0; cut <= wire.length; cut++) {
        final r = SyncFrameReader();
        final out = <SyncFrame>[];
        out.addAll(r.add(wire.sublist(0, cut)));
        out.addAll(r.add(wire.sublist(cut)));
        expect(out.length, 1, reason: 'cut at $cut');
        expect(out.single.type, SyncMsg.file);
        expect(out.single.header['x'], 1);
        expect(utf8.decode(out.single.payload!), 'hello');
      }
    });

    test('two frames in one read come out as two', () {
      final a = SyncFrame({'t': SyncMsg.hello}).encode();
      final b = SyncFrame({'t': SyncMsg.want, 'paths': ['x.ptp']}).encode();
      final r = SyncFrameReader();
      final out = r.add(<int>[...a, ...b]);
      expect(out.length, 2);
      expect(out[0].type, SyncMsg.hello);
      expect(out[1].header['paths'], ['x.ptp']);
    });

    test('a frame with no payload has none, rather than an empty one', () {
      final r = SyncFrameReader();
      final out = r.add(SyncFrame({'t': SyncMsg.hello}).encode());
      expect(out.single.payload, isNull);
    });

    test('an impossible length is refused rather than buffered', () {
      // A peer that says "the next header is a gigabyte" must not be believed:
      // buffering it is how a mirror becomes an out-of-memory crash, and there
      // is no way to resynchronise a length-prefixed stream anyway.
      final r = SyncFrameReader();
      final bad = ByteData(4)..setUint32(0, SyncFrameReader.maxHeader + 1);
      expect(() => r.add(bad.buffer.asUint8List()), throwsFormatException);
    });
  });

  group('what crosses, and what does not', () {
    late Directory root;
    late Directory docs;
    late Directory prefs;

    setUp(() {
      root = Directory.systemTemp.createTempSync('m373');
      docs = Directory('${root.path}/docs')..createSync();
      prefs = Directory('${root.path}/prefs')..createSync();
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
    });

    tearDown(() {
      root.deleteSync(recursive: true);
      ShareCodes.resetForTest();
    });

    test('the manifest is documents and preferences, and nothing else', () {
      File('${docs.path}/Bracket.ptp').writeAsStringSync('a');
      File('${docs.path}/Plate.pts').writeAsStringSync('b');
      File('${docs.path}/Gearbox.pas').writeAsStringSync('c');
      // Everything a mirror must not carry: the log, a crash report, a
      // thumbnail, a stray file the user dropped in.
      File('${docs.path}/prototype_log.txt').writeAsStringSync('x');
      File('${docs.path}/holiday.jpg').writeAsStringSync('x');
      File('${prefs.path}/settings.json').writeAsStringSync('{}');
      File('${prefs.path}/thumbs.db').writeAsStringSync('x');

      final m = LanSync.instance.scanForTest();
      expect(m.keys.toSet(), {
        'Bracket.ptp',
        'Plate.pts',
        'Gearbox.pas',
        'settings/settings.json',
      });
    });

    test('a peer cannot name a file outside the two folders', () {
      // The path in a manifest is chosen by the OTHER device. Every one of
      // these is a write this app must refuse rather than perform.
      for (final path in [
        '../escape.ptp',
        '/etc/passwd.ptp',
        'sub/dir.ptp',
        r'..\windows.ptp',
        'settings/../../out.json',
        'settings/private.key',
        'notadocument.txt',
      ]) {
        expect(
          LanSync.instance.applyForTest(
              SyncEntry(path, 1, 1, 'nope'), _bytes('x')),
          isFalse,
          reason: path,
        );
      }
      expect(docs.listSync(), isEmpty);
      expect(prefs.listSync(), isEmpty);
    });

    test('a body that does not match its hash is dropped', () {
      // Not paranoia about the wire — a truncated transfer looks exactly like
      // this, and half a document written over a whole one is the worst
      // outcome this feature has.
      final e = SyncEntry('Bracket.ptp', 5, 1, 'not the hash of anything');
      expect(LanSync.instance.applyForTest(e, _bytes('hello')), isFalse);
      expect(File('${docs.path}/Bracket.ptp').existsSync(), isFalse);
    });

    test('the newest write wins, and an identical file never moves', () {
      final f = File('${docs.path}/Bracket.ptp')..writeAsStringSync('mine');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      final mine = LanSync.instance.localManifestForTest['Bracket.ptp']!;

      // The same bytes, whatever the clock says: nothing to do. Without this a
      // pair of devices copies every document to each other forever.
      expect(
          LanSync.instance.wantsForTest(
              SyncEntry('Bracket.ptp', mine.size, mine.mtimeMs + 60000, mine.sha)),
          isFalse);

      // Different bytes, older: keep what is here.
      expect(
          LanSync.instance.wantsForTest(
              SyncEntry('Bracket.ptp', 4, mine.mtimeMs - 60000, 'other')),
          isFalse);

      // Different bytes, newer: take theirs.
      expect(
          LanSync.instance.wantsForTest(
              SyncEntry('Bracket.ptp', 4, mine.mtimeMs + 60000, 'other')),
          isTrue);

      // A document this device has never seen.
      expect(LanSync.instance.wantsForTest(SyncEntry('New.ptp', 1, 1, 'x')),
          isTrue);
      expect(f.readAsStringSync(), 'mine');
    });

    test('a difference of milliseconds is not a decision anybody made', () {
      File('${docs.path}/Bracket.ptp').writeAsStringSync('mine');
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      final mine = LanSync.instance.localManifestForTest['Bracket.ptp']!;
      // Two devices' clocks are never equal. Inside the slack, this device
      // keeps what it has rather than ping-ponging with its neighbour.
      expect(
          LanSync.instance.wantsForTest(
              SyncEntry('Bracket.ptp', 4, mine.mtimeMs + 200, 'other')),
          isFalse);
    });

    test('a document lands whole or not at all', () {
      final e = SyncEntry('Bracket.ptp', 5, DateTime.now().millisecondsSinceEpoch,
          _shaOf('hello'));
      expect(LanSync.instance.applyForTest(e, _bytes('hello')), isTrue);
      expect(File('${docs.path}/Bracket.ptp').readAsStringSync(), 'hello');
      // The temporary the write went through is not left behind.
      expect(File('${docs.path}/Bracket.ptp.sync-part').existsSync(), isFalse);
    });
  });

  group('the settings merge', () {
    late Directory root;
    late Directory docs;
    late Directory prefs;

    setUp(() {
      root = Directory.systemTemp.createTempSync('m373s');
      docs = Directory('${root.path}/docs')..createSync();
      prefs = Directory('${root.path}/prefs')..createSync();
    });

    tearDown(() => root.deleteSync(recursive: true));

    Map<String, Object?> mergeInto(
        Map<String, Object?> mine, Map<String, Object?> theirs) {
      File('${prefs.path}/settings.json').writeAsStringSync(jsonEncode(mine));
      LanSync.instance.attachForTest(documents: docs, preferences: prefs);
      final body = _bytes(jsonEncode(theirs));
      final e = SyncEntry('settings/settings.json', body.length,
          DateTime.now().millisecondsSinceEpoch + 60000, _shaOfBytes(body));
      expect(LanSync.instance.applyForTest(e, body), isTrue);
      final out = jsonDecode(File('${prefs.path}/settings.json').readAsStringSync());
      return <String, Object?>{
        for (final en in (out as Map).entries) '${en.key}': en.value
      };
    }

    test('a preference from the other device is adopted', () {
      final merged = mergeInto(
        {'appearance': 'light', 'locale': 'en'},
        {'appearance': 'dark', 'locale': 'de', 'ribbon': 'left'},
      );
      expect(merged['appearance'], 'dark');
      expect(merged['locale'], 'de');
      expect(merged['ribbon'], 'left');
    });

    test('the share code does NOT travel', () {
      // The one key that must never cross. A device that could write another
      // device's `sync` block could switch its sharing off, or point it at a
      // different group — that is a remote control, not a preference.
      final merged = mergeInto(
        {'sync': {'code': 'MINE'}, 'appearance': 'light'},
        {'sync': {'code': 'THEIRS'}, 'appearance': 'dark'},
      );
      expect((merged['sync'] as Map)['code'], 'MINE');
      expect(merged['appearance'], 'dark');
    });

    test('a device with no code does not get one from a peer', () {
      final merged = mergeInto(
        {'appearance': 'light'},
        {'sync': {'code': 'THEIRS'}},
      );
      expect(merged.containsKey('sync'), isFalse);
    });

    test('the thumbnail bookkeeping stays local', () {
      // Cache state, not preference: a shared value would mean one device's
      // repairs counted for another's cache.
      final merged = mergeInto(
        {'previewFormat': 3, 'previewsRepaired': ['A']},
        {'previewFormat': 9, 'previewsRepaired': ['B', 'C']},
      );
      expect(merged['previewFormat'], 3);
      expect(merged['previewsRepaired'], ['A']);
    });

    test('a key only the other device has is still adopted', () {
      final merged = mergeInto({}, {'samples': 512});
      expect(merged['samples'], 512);
    });
  });

  group('the store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('m373st'));
    tearDown(() {
      dir.deleteSync(recursive: true);
      ShareCodes.resetForTest();
    });

    test('the code survives a restart, and shares the file', () {
      final store = SyncStore(dir);
      File('${dir.path}/settings.json')
          .writeAsStringSync(jsonEncode({'appearance': 'dark'}));
      final code = normaliseShareCode(generateShareCode())!;
      store.save(code);
      expect(store.load(), code);
      // The other preferences in the same file are still there — the merge
      // rule this store shares with ThemeStore and the rest.
      final data = jsonDecode(File('${dir.path}/settings.json').readAsStringSync());
      expect((data as Map)['appearance'], 'dark');
    });

    test('clearing it leaves the rest of the file alone', () {
      final store = SyncStore(dir);
      store.save(normaliseShareCode(generateShareCode())!);
      File('${dir.path}/settings.json').writeAsStringSync(jsonEncode({
        ...jsonDecode(File('${dir.path}/settings.json').readAsStringSync()) as Map,
        'locale': 'de',
      }));
      store.save(null);
      expect(store.load(), isNull);
      final data = jsonDecode(File('${dir.path}/settings.json').readAsStringSync());
      expect((data as Map)['locale'], 'de');
    });

    test('a hand-edited code that is not a code is refused', () {
      File('${dir.path}/settings.json').writeAsStringSync(jsonEncode({
        'sync': {'code': 'nonsense'}
      }));
      // Validated on the way OUT as well as in: starting a mirror with a key
      // nothing else derives would look like a network fault forever.
      expect(SyncStore(dir).load(), isNull);
    });
  });
}

/// The same hash the mirror uses, computed the same way, so a test that passes
/// here is a test of the real comparison rather than of a stub.
String _shaOf(String s) => _shaOfBytes(_bytes(s));

String _shaOfBytes(Uint8List b) => sha256.convert(b).toString();
