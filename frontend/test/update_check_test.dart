// Supervisor pass — update_check.dart shipped with no tests at all, which is
// a real gap for the one piece of this app that downloads and silently
// executes a binary. It also shipped without checking the download against
// anything: this app already publishes SHA256SUMS-<platform>.txt with every
// release (see build.yml's "ONE CHECKSUM FILE PER PLATFORM" step) and
// nothing in UpdateCheck.apply used it — a corrupted or tampered download
// would have been run exactly as downloaded. checksumFor and the verify step
// built on it are the fix; this file is what pins them.
//
// What's tested here is the platform-independent half: the checksum-line
// parser (pure, and now exported for exactly this reason) and UpdateStore's
// throttle/skip bookkeeping. UpdateCheck.checkIfDue/_pickAsset/apply reach
// out to the network and branch on Platform.isWindows/isLinux, which this
// suite runs under (ubuntu-latest in CI) cannot flip — the same constraint
// every other platform-conditional file in this app has, and the reason
// those stay covered by the platform's own CI build rather than a host test.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/update_check.dart';

void main() {
  group('checksumFor', () {
    test('finds the hash on the one line naming the asset', () {
      // A real sha256 is 64 hex characters; this fixture is that shape.
      final hash = '1' * 64;
      final body = '$hash  prototype-build-abc1234-windows-setup.exe\n';
      expect(
          UpdateCheck.checksumFor(
              body, 'prototype-build-abc1234-windows-setup.exe'),
          hash);
    });

    test('the single-line file this app actually publishes', () {
      // sha256sum's own output format: hash, two spaces, filename.
      final hash = 'b' * 64;
      final body = '$hash  prototype-build-deadbee-linux-x64.AppImage';
      expect(
          UpdateCheck.checksumFor(
              body, 'prototype-build-deadbee-linux-x64.AppImage'),
          hash);
    });

    test('lower-cases an upper-case hash', () {
      final hash = 'ABCDEF01' * 8; // 64 chars, upper-case hex
      final body = '$hash  setup.exe';
      expect(UpdateCheck.checksumFor(body, 'setup.exe'), hash.toLowerCase());
    });

    test('no line names the asset: null', () {
      final hash = 'c' * 64;
      final body = '$hash  some-other-file.exe';
      expect(UpdateCheck.checksumFor(body, 'setup.exe'), isNull);
    });

    test('the token in hash position is not 64 hex characters: null', () {
      expect(UpdateCheck.checksumFor('deadbeef  setup.exe', 'setup.exe'),
          isNull, reason: 'far short of a sha256');
      expect(
          UpdateCheck.checksumFor(
              '${'a' * 63}  setup.exe', 'setup.exe'), // one short
          isNull);
      expect(
          UpdateCheck.checksumFor(
              '${'g' * 64}  setup.exe', 'setup.exe'), // not hex
          isNull);
    });

    test('an empty file: null, not a crash', () {
      expect(UpdateCheck.checksumFor('', 'setup.exe'), isNull);
    });

    test('picks the matching line among several', () {
      final wrong = 'd' * 64;
      final right = 'e' * 64;
      final body = '$wrong  prototype-build-000-linux-x64.AppImage\n'
          '$right  prototype-build-000-windows-setup.exe\n';
      expect(
          UpdateCheck.checksumFor(body, 'prototype-build-000-windows-setup.exe'),
          right);
    });
  });

  group('UpdateStore', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('update_check_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('nothing written yet: both empty', () {
      final store = UpdateStore(dir);
      expect(store.lastCheckAt, isNull);
      expect(store.skipTag, isNull);
    });

    test('recordCheck sets a UTC timestamp that round-trips', () {
      final store = UpdateStore(dir);
      final before = DateTime.now().toUtc();
      store.recordCheck();
      final at = store.lastCheckAt;
      expect(at, isNotNull);
      expect(at!.isAfter(before.subtract(const Duration(seconds: 5))), isTrue);
      expect(at.isUtc, isTrue);
    });

    test('recordSkip round-trips the tag', () {
      final store = UpdateStore(dir);
      store.recordSkip('build-abc1234');
      expect(store.skipTag, 'build-abc1234');
    });

    test('a later skip replaces the earlier one', () {
      final store = UpdateStore(dir);
      store.recordSkip('build-abc1234');
      store.recordSkip('build-def5678');
      expect(store.skipTag, 'build-def5678');
    });

    test('merges into settings.json, leaving other keys alone', () {
      final f = File('${dir.path}/settings.json');
      f.writeAsStringSync(jsonEncode({'appearance': 'dark', 'lang': 'en'}));
      UpdateStore(dir).recordSkip('build-abc1234');
      final raw = jsonDecode(f.readAsStringSync()) as Map;
      expect(raw['appearance'], 'dark');
      expect(raw['lang'], 'en');
      expect((raw['update'] as Map)['skipTag'], 'build-abc1234');
    });

    test('a second write does not clobber the first key in the section', () {
      final store = UpdateStore(dir);
      store.recordSkip('build-abc1234');
      store.recordCheck();
      expect(store.skipTag, 'build-abc1234',
          reason: 'recordCheck must merge into the update section, not '
              'replace it');
      expect(store.lastCheckAt, isNotNull);
    });

    test('a corrupt settings.json reads as empty rather than throwing', () {
      File('${dir.path}/settings.json').writeAsStringSync('{not json');
      final store = UpdateStore(dir);
      expect(store.lastCheckAt, isNull);
      expect(store.skipTag, isNull);
      // And writing still works — it does not stay broken.
      store.recordSkip('build-abc1234');
      expect(store.skipTag, 'build-abc1234');
    });
  });
}
