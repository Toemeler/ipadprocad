// M195 — the bug bundle leaves the iPad by itself.
//
// Two things here can hurt if they are wrong, and neither shows up as a crash.
//
//   1. THE TOKEN. It is a real credential living on a tablet, and the bundle
//      that gets uploaded carries the whole log. One '$cfg' in a log line and
//      the token ships inside the very zip that goes to a repository — which
//      for this project is a PUBLIC one. So toString() redacting is a tested
//      contract, not a nicety.
//   2. THE QUEUE. "Automatic" that silently drops a report on a bad network is
//      worse than a manual copy out of the Files app, because nobody notices.
//
// The HTTP call is injected, so every status GitHub can answer with is
// exercised here — including the ones a device would only hit months later.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/bug_upload.dart';

const _token = 'github_pat_11ABCDEFG_secretsecretsecret';

BugUploadConfig cfg({String? branch, String dir = 'bugreports'}) =>
    BugUploadConfig(
        repo: 'Owner/name', token: _token, branch: branch, dir: dir);

Directory tempDir() => Directory.systemTemp.createTempSync('ipc_m195');

File writeZip(Directory d, String name, {int bytes = 32}) {
  final f = File('${d.path}/$name');
  // Uint8List, not List<int>: the oversize case is 25 MB, and a List<int> of
  // that length is boxed elements — 200 MB of heap to write a 25 MB file.
  f.writeAsBytesSync(Uint8List(bytes)..fillRange(0, bytes, 7));
  return f;
}

void main() {
  group('config', () {
    test('a complete file parses', () {
      final c = BugUploadConfig.parse(jsonEncode({
        'repo': 'Owner/name',
        'branch': 'reports',
        'dir': 'bugs/',
        'token': _token,
      }))!;
      expect(c.repo, 'Owner/name');
      expect(c.branch, 'reports');
      expect(c.dir, 'bugs', reason: 'trailing slashes would double up in the '
          'URL path');
      expect(c.token, _token);
    });

    test('the optional fields have working defaults', () {
      final c = BugUploadConfig
          .parse(jsonEncode({'repo': 'Owner/name', 'token': _token}))!;
      expect(c.branch, isNull, reason: 'null means the repo default branch');
      expect(c.dir, 'bugreports');
    });

    test('anything unusable parses to null rather than throwing', () {
      // A broken config must never be able to stop a report being WRITTEN,
      // which is the half that matters even when uploading is impossible.
      for (final bad in [
        '',
        'not json at all',
        '[]',
        '{}',
        jsonEncode({'repo': 'Owner/name'}), // no token
        jsonEncode({'token': _token}), // no repo
        jsonEncode({'repo': 'noslash', 'token': _token}),
        jsonEncode({'repo': 'too/many/parts', 'token': _token}),
        jsonEncode({'repo': '/name', 'token': _token}),
        jsonEncode({'repo': 'Owner/', 'token': _token}),
        jsonEncode({'repo': 'Owner/name', 'token': '   '}),
      ]) {
        expect(BugUploadConfig.parse(bad), isNull, reason: bad);
      }
    });

    test('load() returns null when there is no config file', () {
      expect(BugUploadConfig.load(tempDir()), isNull);
    });

    test('load() reads the file beside the bundles', () {
      final d = tempDir();
      File('${d.path}/${BugUploadConfig.fileName}').writeAsStringSync(
          jsonEncode({'repo': 'Owner/name', 'token': _token}));
      expect(BugUploadConfig.load(d)?.repo, 'Owner/name');
    });

    test('toString REDACTS the token', () {
      // The log goes into the bundle and the bundle goes to a repository. This
      // one line is what makes an accidental interpolation harmless.
      final s = cfg(branch: 'reports').toString();
      expect(s, isNot(contains(_token)));
      expect(s, contains('redacted'));
      expect(s, contains('Owner/name'), reason: 'the useful half stays');
    });
  });

  group('relay mode', () {
    // The point of the relay is that the GitHub credential is NOT on the
    // tablet: the device holds an append-only upload key for an endpoint you
    // own, and the worst a stolen one can do is add files to a bug repo.
    test('a url selects the relay, and no repo token is needed', () {
      final c = BugUploadConfig.parse(jsonEncode({
        'url': 'https://bugs.example.workers.dev',
        'key': 'long-random-string',
      }))!;
      expect(c.mode, BugUploadMode.relay);
      expect(c.repo, isEmpty);
      expect(c.token, 'long-random-string');
    });

    test('a url wins over a repo/token pair in the same file', () {
      // If a config carries both, the SAFE one has to win — the other way
      // round, a leftover token would keep being used silently.
      final c = BugUploadConfig.parse(jsonEncode({
        'url': 'https://bugs.example.workers.dev',
        'repo': 'Owner/name',
        'token': _token,
      }))!;
      expect(c.mode, BugUploadMode.relay);
      expect(c.token, isNot(_token));
    });

    test('the key is optional — an unguessable URL can be the secret', () {
      final c = BugUploadConfig
          .parse(jsonEncode({'url': 'https://bugs.example.workers.dev/x9f2'}))!;
      expect(c.token, isEmpty);
      expect(bundleHeaders(c).containsKey('X-Upload-Key'), isFalse,
          reason: 'an empty key header would be a header saying "no key"');
    });

    test('plain http is refused outright', () {
      // A bundle is the whole log plus a screenshot of the screen. That does
      // not go over café wifi in the clear because of a typo in a config file.
      expect(BugUploadConfig.parse(jsonEncode({'url': 'http://bugs.example'})),
          isNull);
      expect(BugUploadConfig.parse(jsonEncode({'url': 'not a url'})), isNull);
    });

    test('the file name is the last path segment, and the zip is the body',
        () async {
      final c = BugUploadConfig.parse(jsonEncode({
        'url': 'https://bugs.example.workers.dev/',
        'key': 'k',
      }))!;
      expect(bundleUri(c, 'bug1.zip').toString(),
          'https://bugs.example.workers.dev/bug1.zip',
          reason: 'the trailing slash must not double up');
      // Raw bytes: no base64, no envelope. A thirty-line relay can handle it
      // and the tablet does not inflate a 2 MB file by a third.
      expect(bundlePayload(c, 'bug1.zip', const [1, 2, 3]), const [1, 2, 3]);
      expect(bundleHeaders(c)['X-Upload-Key'], 'k');
      expect(bundleHeaders(c)['Content-Type'], 'application/zip');
    });

    test('the key never reaches the log, and neither does the full URL', () {
      final c = BugUploadConfig.parse(jsonEncode({
        'url': 'https://bugs.example.workers.dev/secret-path',
        'key': 'long-random-string',
      }))!;
      expect(c.toString(), isNot(contains('long-random-string')));
      expect(c.toString(), isNot(contains('secret-path')),
          reason: 'an unguessable URL is itself a secret');
      expect(c.describe, 'bugs.example.workers.dev');
    });

    test('it sends through the same queue and marking as GitHub mode',
        () async {
      final d = tempDir();
      final z = writeZip(d, 'bug1.zip');
      final c = BugUploadConfig.parse(
          jsonEncode({'url': 'https://bugs.example.workers.dev'}))!;
      List<int>? body;
      final r = await sendBundle(z, c, put: (_, __, b) async {
        body = b;
        return 201;
      });
      expect(r, BugSendResult.sent);
      expect(body, hasLength(32), reason: 'the zip itself, unwrapped');
      expect(sentMarker(z).existsSync(), isTrue);
    });
  });

  group('request', () {
    test('the URL is the Contents API path for the bundle', () {
      final u = bundleUri(cfg(), 'bug20260804T112835.zip');
      expect(u.scheme, 'https');
      expect(u.host, 'api.github.com');
      expect(u.path,
          '/repos/Owner/name/contents/bugreports/bug20260804T112835.zip');
    });

    test('the body carries the bytes base64-encoded, and the branch', () {
      final bytes = [1, 2, 3, 4, 5];
      final b = bundleBody(cfg(branch: 'reports'), 'b.zip', bytes);
      expect(base64Decode(b['content']! as String), bytes);
      expect(b['branch'], 'reports');
      expect(b['message'], contains('b.zip'));
    });

    test('no branch key at all when the repo default is wanted', () {
      // Sending branch:null would make GitHub answer 422, not "use default".
      expect(bundleBody(cfg(), 'b.zip', const [1]).containsKey('branch'),
          isFalse);
    });

    test('the token travels as a bearer header', () {
      final h = bundleHeaders(cfg());
      expect(h['Authorization'], 'Bearer $_token');
      expect(h['Accept'], 'application/vnd.github+json');
      expect(h['X-GitHub-Api-Version'], isNotEmpty);
    });
  });

  group('status handling', () {
    test('201 and 200 are delivered', () {
      expect(resultForStatus(201), BugSendResult.sent);
      expect(resultForStatus(200), BugSendResult.sent);
    });

    test('409/422 count as delivered — the name is already taken', () {
      // Bundle names are timestamps, so this is the same bundle twice. Calling
      // it a failure would retry it forever.
      expect(resultForStatus(409), BugSendResult.sent);
      expect(resultForStatus(422), BugSendResult.sent);
    });

    test('5xx is worth retrying, 4xx is not', () {
      expect(resultForStatus(500).retry, isTrue);
      expect(resultForStatus(503).retry, isTrue);
      expect(resultForStatus(401), BugSendResult.rejected);
      expect(resultForStatus(403), BugSendResult.rejected);
      expect(resultForStatus(404), BugSendResult.rejected);
      expect(resultForStatus(401).retry, isFalse,
          reason: 'a bad token cannot be fixed by waiting');
    });
  });

  group('sending', () {
    test('a sent bundle is marked, and the local copy is KEPT', () async {
      final d = tempDir();
      final z = writeZip(d, 'bug1.zip');
      expect(await sendBundle(z, cfg(), put: (_, __, ___) async => 201),
          BugSendResult.sent);
      expect(sentMarker(z).existsSync(), isTrue);
      expect(z.existsSync(), isTrue,
          reason: 'the local copy is the only one the user can open');
    });

    test('a failed send leaves no marker, so it is retried', () async {
      final d = tempDir();
      final z = writeZip(d, 'bug1.zip');
      expect(await sendBundle(z, cfg(), put: (_, __, ___) async => 500),
          BugSendResult.offline);
      expect(sentMarker(z).existsSync(), isFalse);
      // Paths, not File objects: dart:io entities are identity-compared.
      expect(pendingBundles(d).map((f) => f.path), [z.path]);
    });

    test('a thrown network error is offline, not a crash', () async {
      final d = tempDir();
      final z = writeZip(d, 'bug1.zip');
      expect(
          await sendBundle(z, cfg(),
              put: (_, __, ___) async => throw const SocketException('down')),
          BugSendResult.offline);
      expect(sentMarker(z).existsSync(), isFalse);
    });

    test('without a config nothing is attempted', () async {
      final d = tempDir();
      final z = writeZip(d, 'bug1.zip');
      var called = false;
      final r = await sendBundle(z, null, put: (_, __, ___) async {
        called = true;
        return 201;
      });
      expect(r, BugSendResult.noConfig);
      expect(called, isFalse);
      expect(sentMarker(z).existsSync(), isFalse);
    });

    test('an oversized bundle is refused locally, not uploaded', () async {
      final d = tempDir();
      final z = writeZip(d, 'huge.zip', bytes: kMaxBundleBytes + 1);
      var called = false;
      final r = await sendBundle(z, cfg(), put: (_, __, ___) async {
        called = true;
        return 201;
      });
      expect(r, BugSendResult.tooBig);
      expect(called, isFalse, reason: 'a tablet on cellular should not find '
          'out the hard way');
    });
  });

  group('the queue', () {
    test('pending means "a zip with no marker", oldest first', () {
      final d = tempDir();
      final b = writeZip(d, 'bug20260804T120000.zip');
      final a = writeZip(d, 'bug20260804T110000.zip');
      final done = writeZip(d, 'bug20260804T100000.zip');
      sentMarker(done).writeAsStringSync('x');
      // Not a bundle: must not be uploaded.
      File('${d.path}/notes.txt').writeAsStringSync('hello');
      expect(pendingBundles(d).map((f) => f.path), [a.path, b.path]);
    });

    test('a missing directory is empty, not an exception', () {
      expect(pendingBundles(Directory('/nope/does/not/exist')), isEmpty);
    });

    test('flushing sends every waiting bundle', () async {
      final d = tempDir();
      writeZip(d, 'b1.zip');
      writeZip(d, 'b2.zip');
      writeZip(d, 'b3.zip');
      final urls = <String>[];
      final n = await flushBugUploads(d, cfg(), put: (u, __, ___) async {
        urls.add(u.path);
        return 201;
      });
      expect(n, 3);
      expect(urls, hasLength(3));
      expect(pendingBundles(d), isEmpty);
    });

    test('a rejected token stops the run instead of hammering the API',
        () async {
      final d = tempDir();
      writeZip(d, 'b1.zip');
      writeZip(d, 'b2.zip');
      writeZip(d, 'b3.zip');
      var calls = 0;
      final n = await flushBugUploads(d, cfg(), put: (_, __, ___) async {
        calls++;
        return 401;
      });
      expect(n, 0);
      expect(calls, 1, reason: 'if the token is wrong for one it is wrong for '
          'all of them');
      expect(pendingBundles(d), hasLength(3), reason: 'nothing is lost');
    });

    test('going offline mid-queue keeps the rest for next time', () async {
      final d = tempDir();
      writeZip(d, 'b1.zip');
      writeZip(d, 'b2.zip');
      writeZip(d, 'b3.zip');
      var calls = 0;
      final n = await flushBugUploads(d, cfg(), put: (_, __, ___) async {
        calls++;
        return calls == 1 ? 201 : 500;
      });
      expect(n, 1);
      expect(pendingBundles(d), hasLength(2));
    });

    test('flushing without a config does nothing at all', () async {
      final d = tempDir();
      writeZip(d, 'b1.zip');
      expect(await flushBugUploads(d, null), 0);
      expect(pendingBundles(d), hasLength(1));
    });
  });
}
