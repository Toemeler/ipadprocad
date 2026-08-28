// M285 — sending the bug bundle to the relay, without a credential on device.
//
// M195 built and reverted a direct-to-GitHub uploader specifically because
// there is no anonymous write path into a repo and a device-held repo token
// was rejected. This module never holds one — it only POSTs to a relay that
// does (see relay/worker.js) — so what is testable from the host, without a
// network or the relay running, is the boundary that makes that true: with
// no relay configured (the default in every build config, including this
// test run, since no --dart-define is passed), uploadBugReport must fail
// FAST and LOCALLY, without ever reaching for the network, and the local
// bundle must be exactly as unaffected as it was before this file existed.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/bug_upload.dart';

void main() {
  test('no relay is configured by default (no --dart-define given)', () {
    // This is the whole safety property M195 asked for: a build that never
    // set BUG_RELAY_URL must behave exactly like the app before this file
    // existed. If this ever reads non-empty in an ordinary test run, a
    // secret would be a compile-time default rather than an opt-in flag.
    expect(bugRelayUrl, isEmpty);
    expect(bugUploadConfigured, isFalse);
  });

  test('uploadBugReport short-circuits without a relay, and does so fast',
      () async {
    // Bounded well under the function's own 20s default timeout: if this
    // took anywhere near that long, it would mean the "not configured"
    // check failed to short-circuit and a real network attempt was made
    // against an empty URL.
    final sw = Stopwatch()..start();
    final result = await uploadBugReport(
      zipBytes: Uint8List.fromList([1, 2, 3]),
      stem: 'bug-test',
      description: 'does not matter',
      timeout: const Duration(seconds: 5),
    );
    sw.stop();

    expect(result.ok, isFalse);
    expect(result.issueUrl, isNull);
    expect(result.error, 'no relay configured');
    expect(sw.elapsed, lessThan(const Duration(seconds: 1)));
  });

  group('BugUploadResult', () {
    test('ok() reports success and carries the issue URL', () {
      const r = BugUploadResult.ok(
          issueUrl: 'https://github.com/o/r/issues/1',
          fileUrl: 'https://github.com/o/r/blob/b/f.zip');
      expect(r.ok, isTrue);
      expect(r.issueUrl, 'https://github.com/o/r/issues/1');
      expect(r.fileUrl, 'https://github.com/o/r/blob/b/f.zip');
      expect(r.error, isNull);
    });

    test('failed() reports failure and carries the error, never an issue url',
        () {
      const r = BugUploadResult.failed('HTTP 502');
      expect(r.ok, isFalse);
      expect(r.issueUrl, isNull);
      expect(r.error, 'HTTP 502');
    });

    test('failed() can still carry a fileUrl — the bundle may have been '
        'committed even when filing the issue itself failed', () {
      const r = BugUploadResult.failed('github issues: 502 …',
          fileUrl: 'https://github.com/o/r/blob/b/f.zip');
      expect(r.ok, isFalse);
      expect(r.fileUrl, 'https://github.com/o/r/blob/b/f.zip');
    });
  });
}
