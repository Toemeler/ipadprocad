// M443 — where a live Backblaze credential is kept, and where it is not.
//
// THE PROBLEM THIS FIXES. M442 put the account under `<Documents>/.cache`,
// which on iOS is inside the directory `UIFileSharingEnabled` exposes: the
// gallery is meant to be browsable in Files, and the key was sitting in it. A
// leading dot is the only reason Files did not list it — obscurity, not
// protection, and an unencrypted backup carries the whole container anyway.
//
// It lives in Application Support now, which that flag does not expose, and an
// account written by the older build is MOVED rather than copied: leaving the
// original behind would leave the key exactly where this was meant to get it
// out of.
//
// None of this is the platform keystore, and `cloud_account.dart` says so
// rather than implying otherwise. What is pinned here is that the file is not
// somewhere the file browser will hand to anybody who asks.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/sync/b2_signer.dart';
import 'package:prototype/sync/cloud_account.dart';

void main() {
  late Directory root;
  late Directory browsable; // stands in for <Documents>/.cache
  late Directory private; // stands in for Application Support

  const account = B2Credentials(
    keyId: '00319390fd8d1160000000001',
    appKey: 'K003SECRETVALUEHERE',
    bucket: 'prototype-tomatensaftomat',
    region: 'eu-central-003',
  );

  setUp(() {
    root = Directory.systemTemp.createTempSync('m443');
    browsable = Directory('${root.path}/docs/.cache')..createSync(recursive: true);
    private = Directory('${root.path}/support')..createSync(recursive: true);
  });

  tearDown(() {
    CloudAccount.resetForTest();
    root.deleteSync(recursive: true);
  });

  File legacyFile() =>
      File('${browsable.path}/${CloudAccountStore.fileName}');
  File newFile() => File('${private.path}/${CloudAccountStore.fileName}');

  void writeLegacy(B2Credentials c) => legacyFile().writeAsStringSync(jsonEncode({
        'keyId': c.keyId,
        'appKey': c.appKey,
        'bucket': c.bucket,
        'region': c.region,
      }));

  group('an account from the old build is moved out', () {
    test('it is readable at the new path and gone from the old one', () {
      writeLegacy(account);
      final store = CloudAccountStore(private, legacyDir: browsable);

      final loaded = store.load();

      expect(loaded, account, reason: 'nothing is lost in the move');
      expect(newFile().existsSync(), isTrue);
      expect(legacyFile().existsSync(), isFalse,
          reason: 'a copy left behind is the leak this fixes');
    });

    // The whole point: the key must not still be sitting in the directory a
    // file browser lists.
    test('the key is nowhere in the browsable directory afterwards', () {
      writeLegacy(account);
      CloudAccountStore(private, legacyDir: browsable).load();

      final leftBehind = browsable
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.readAsStringSync())
          .join('\n');
      expect(leftBehind, isNot(contains(account.appKey)));
      expect(leftBehind, isNot(contains(account.keyId)));
    });

    // A build that already has an account must not have it replaced by an
    // older one — but the stale copy still has to go.
    test('a newer account wins, and the stale copy is still removed', () {
      writeLegacy(account);
      final store = CloudAccountStore(private, legacyDir: browsable);
      store.save(account.copyWith(bucket: 'the-newer-one'));

      final loaded = store.load();

      expect(loaded?.bucket, 'the-newer-one');
      expect(legacyFile().existsSync(), isFalse);
    });

    test('nothing to move is not an error', () {
      final store = CloudAccountStore(private, legacyDir: browsable);
      expect(store.load(), isNull);
      expect(newFile().existsSync(), isFalse);
    });

    // On the desktop both paths are the same directory, and a migration that
    // did not notice would delete the file it had just adopted.
    test('the same directory twice does not eat the account', () {
      final store = CloudAccountStore(private, legacyDir: private);
      store.save(account);
      expect(store.load(), account);
      expect(newFile().existsSync(), isTrue);
    });
  });

  group('what the file itself gives away', () {
    test('it round-trips every field', () {
      final store = CloudAccountStore(private);
      store.save(account);
      expect(store.load(), account);
    });

    test('clearing the account removes the file, not just its contents', () {
      final store = CloudAccountStore(private);
      store.save(account);
      store.save(null);
      expect(newFile().existsSync(), isFalse,
          reason: 'an emptied file still holds the old bytes on some systems');
      expect(store.load(), isNull);
    });

    // A partial account is kept so the four rows can be filled in one at a
    // time, across the app being closed. An empty one is not an account.
    test('a partial account survives but an empty one is nothing', () {
      final store = CloudAccountStore(private);
      store.save(const B2Credentials(
          keyId: '', appKey: '', bucket: 'just-the-bucket', region: ''));
      expect(store.load()?.bucket, 'just-the-bucket');
      expect(store.load()?.isComplete, isFalse);

      store.save(const B2Credentials(
          keyId: '', appKey: '', bucket: '', region: ''));
      expect(store.load(), isNull);
    });

    test('a corrupt file costs the account and nothing else', () {
      newFile().writeAsStringSync('{not json at all');
      expect(CloudAccountStore(private).load(), isNull);
    });
  });

  // POSIX only; Windows has no mode bits and iOS does not need them.
  group('the file is not readable by other accounts on the machine', () {
    test('it is written 0600', () {
      if (!Platform.isLinux && !Platform.isMacOS) return;
      CloudAccountStore(private).save(account);
      final mode = Process.runSync('stat', ['-c', '%a', newFile().path])
          .stdout
          .toString()
          .trim();
      expect(mode, '600',
          reason: 'writeAsStringSync creates at the umask, 0644 on most '
              'systems, and the key opens the bucket from anywhere');
    });
  });
}
