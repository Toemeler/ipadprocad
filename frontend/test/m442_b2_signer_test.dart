// M442 — signing a B2 request on the device.
//
// A SIGNER CANNOT BE TESTED BY READING IT. Every mistake in one — a byte
// encoded the wrong way, a query parameter out of order, a date stamp sliced
// a character short — produces a string that looks exactly as plausible as
// the right one, and the server answers `SignatureDoesNotMatch` with nothing
// else to go on. The only useful test is a known input with a known
// signature, and AWS publishes one:
//
//   "Example: Signature Calculation for Presigned URL"
//   https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html
//
// B2's S3 API implements the same SigV4 — which is the whole reason a bucket
// there can be reached with an S3 signer at all — so a signer that reproduces
// AWS's example byte for byte is one B2 accepts. The Worker's JavaScript
// signer is checked against the same vector in `cloud/test/sigv4.test.mjs`;
// the two now have to agree with AWS rather than merely with each other.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/sync/b2_signer.dart';
import 'package:prototype/sync/cloud_sync.dart';

void main() {
  // The credentials from AWS's example. They are documentation, not secrets:
  // this exact pair appears in the S3 signing docs and in every SDK's test
  // suite, and it authenticates nothing.
  const example = B2Credentials(
    keyId: 'AKIAIOSFODNN7EXAMPLE',
    appKey: 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY',
    bucket: 'examplebucket',
    region: 'us-east-1',
  );
  final when = DateTime.utc(2013, 5, 24);

  group('the signature AWS published', () {
    // AWS's example signs `examplebucket.s3.amazonaws.com`. B2's host is
    // `<bucket>.s3.<region>.backblazeb2.com`, so the vector is reproduced by
    // signing with the host the example uses — which is what this overrides.
    // Everything else is the real code path.
    test('is reproduced byte for byte', () {
      final url = B2Signer.sign(
        credentials: example,
        method: 'GET',
        key: 'test.txt',
        expiry: const Duration(days: 1),
        now: when,
        hostOverride: 'examplebucket.s3.amazonaws.com',
      );
      expect(
        url.queryParameters['X-Amz-Signature'],
        'aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404',
      );
    });

    test('carries the scope and the date the example carries', () {
      final url = B2Signer.sign(
        credentials: example,
        method: 'GET',
        key: 'test.txt',
        expiry: const Duration(days: 1),
        now: when,
        hostOverride: 'examplebucket.s3.amazonaws.com',
      );
      expect(url.queryParameters['X-Amz-Credential'],
          'AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request');
      expect(url.queryParameters['X-Amz-Date'], '20130524T000000Z');
      expect(url.queryParameters['X-Amz-Expires'], '86400');
      expect(url.queryParameters['X-Amz-SignedHeaders'], 'host');
    });
  });

  group('the pieces the vector cannot reach', () {
    // RFC 3986 encodes these four; Uri.encodeComponent does not. A key
    // carrying one would be signed differently from how it is sent.
    test('encodes what Uri.encodeComponent leaves alone', () {
      expect(B2Signer.uriEncode("a!b'c(d)e*f"), 'a%21b%27c%28d%29e%2Af');
    });

    // A blob key is `g/<hex>/b/<hex>`. Encoding its separators would sign a
    // path the server never sees and every request would fail.
    test('keeps the separators in a multi-segment key', () {
      expect(B2Signer.canonicalPath('g/abc123/b/deadbeef'),
          '/g/abc123/b/deadbeef');
    });

    // Both stamps come from one instant; an off-by-one in either puts the
    // scope's date out of step with X-Amz-Date, which the server rejects.
    test('derives both stamps from the same instant', () {
      final s = B2Signer.stamps(DateTime.utc(2026, 9, 22, 11, 42, 33, 500));
      expect(s.amzDate, '20260922T114233Z');
      expect(s.dateStamp, '20260922');
    });

    test('a local time is signed as the UTC it actually is', () {
      final utc = B2Signer.stamps(DateTime.utc(2026, 1, 2, 3, 4, 5));
      final local =
          B2Signer.stamps(DateTime.utc(2026, 1, 2, 3, 4, 5).toLocal());
      expect(local.amzDate, utc.amzDate,
          reason: 'a device in any timezone signs the same instant');
    });

    test('the query is signed in sorted order, not insertion order', () {
      final url = B2Signer.sign(
        credentials: example,
        method: 'GET',
        key: '',
        query: const {'prefix': 'g/aa/m/', 'list-type': '2'},
        now: when,
      );
      final q = url.query;
      expect(q.indexOf('X-Amz-Algorithm'), lessThan(q.indexOf('list-type')));
      expect(q.indexOf('list-type'), lessThan(q.indexOf('prefix')));
    });
  });

  group('the bucket this app actually talks to', () {
    const mine = B2Credentials(
      keyId: 'k',
      appKey: 's',
      bucket: 'prototype-tomatensaftomat',
      region: 'eu-central-003',
    );

    test('is addressed virtual-host style', () {
      expect(mine.host, 'prototype-tomatensaftomat.s3.eu-central-003.backblazeb2.com');
      final url = B2Signer.sign(
          credentials: mine, method: 'PUT', key: 'g/aa/b/${'c' * 64}');
      expect(url.host, mine.host);
      expect(url.path, '/g/aa/b/${'c' * 64}');
      expect(url.scheme, 'https');
    });

    test('a listing signs the bucket root', () {
      final url = B2Signer.sign(
          credentials: mine,
          method: 'GET',
          key: '',
          query: const {'list-type': '2'});
      expect(url.path, '/');
      expect(url.queryParameters['list-type'], '2');
    });
  });

  // NOBODY SHOULD HAVE TO KNOW which dotted segment of an endpoint is the
  // region. The console shows an endpoint; the settings row takes whatever
  // was on screen.
  group('reading the region off what Backblaze showed', () {
    test('takes the endpoint as the console prints it', () {
      expect(regionFromEndpoint('s3.eu-central-003.backblazeb2.com'),
          'eu-central-003');
      expect(regionFromEndpoint('https://s3.us-west-004.backblazeb2.com/'),
          'us-west-004');
      expect(regionFromEndpoint('  S3.EU-CENTRAL-003.BackblazeB2.com '),
          'eu-central-003');
    });

    test('takes a bare region too', () {
      expect(regionFromEndpoint('eu-central-003'), 'eu-central-003');
      expect(regionFromEndpoint('us-west-004'), 'us-west-004');
    });

    test('refuses what is neither, so the row can say so', () {
      for (final bad in const [
        '',
        '   ',
        'my bucket',
        'https://example.com',
        's3.amazonaws.com',
      ]) {
        expect(regionFromEndpoint(bad), isNull, reason: '"$bad"');
      }
    });
  });

  group('the credentials themselves', () {
    test('are not complete until every field is there', () {
      expect(
          const B2Credentials(keyId: '', appKey: 's', bucket: 'b', region: 'r')
              .isComplete,
          isFalse);
      expect(
          const B2Credentials(keyId: 'k', appKey: '', bucket: 'b', region: 'r')
              .isComplete,
          isFalse);
      expect(
          const B2Credentials(keyId: 'k', appKey: 's', bucket: '', region: 'r')
              .isComplete,
          isFalse);
      expect(
          const B2Credentials(keyId: 'k', appKey: 's', bucket: 'b', region: '')
              .isComplete,
          isFalse);
      expect(
          const B2Credentials(keyId: 'k', appKey: 's', bucket: 'b', region: 'r')
              .isComplete,
          isTrue);
    });

    // A credential printed by a stray log line or an exception's toString is
    // a credential in a bug bundle, and a bug bundle becomes a GitHub issue.
    test('never print the key', () {
      const c = B2Credentials(
          keyId: 'KEYID000', appKey: 'SECRET123', bucket: 'b', region: 'r');
      expect(c.toString(), isNot(contains('SECRET123')));
      expect(c.toString(), isNot(contains('KEYID000')));
      expect(c.toString(), contains('b'));
    });

    test('compare by value, so a notifier stays quiet', () {
      const a = B2Credentials(keyId: 'k', appKey: 's', bucket: 'b', region: 'r');
      const b = B2Credentials(keyId: 'k', appKey: 's', bucket: 'b', region: 'r');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(a.copyWith(bucket: 'other')));
    });
  });
  productionChecks();
}

// ---------------------------------------------------------------------------
// M443 — the production-readiness pass.
//
// Two of these are leaks that a review found rather than a test, which is the
// wrong way round; they are pinned here so they cannot come back quietly.
// ---------------------------------------------------------------------------
void productionChecks() {
  group('a signed URL never reaches a log', () {
    // THE LEAK. `package:http` throws ClientException, whose toString() is
    // 'ClientException: <message>, uri=<uri>'. Logging one with interpolation
    // wrote the whole presigned URL — X-Amz-Credential (the key ID) and
    // X-Amz-Signature, a bearer token for that object — into a log that
    // `bug_capture.dart` puts in a bundle and the relay commits to a GitHub
    // issue. A dropped connection would have published a working credential.
    test('the query string of a signed URL is taken out', () {
      final url = B2Signer.sign(
        credentials: const B2Credentials(
            keyId: 'AKIAEXAMPLE',
            appKey: 'secret',
            bucket: 'b',
            region: 'eu-central-003'),
        method: 'GET',
        key: 'g/aa/b/${'c' * 64}',
      );
      final line = redactUrls('ClientException: Connection reset, uri=$url');
      expect(line, isNot(contains('X-Amz-Signature')));
      expect(line, isNot(contains('X-Amz-Credential')));
      expect(line, isNot(contains('AKIAEXAMPLE')));
      expect(line, contains('<signed>'),
          reason: 'and says that something was taken out');
      expect(line, contains('Connection reset'),
          reason: 'without losing what actually went wrong');
    });

    test('a line with no url in it is left alone', () {
      expect(redactUrls('cycle failed: Bad state: list: 403'),
          'cycle failed: Bad state: list: 403');
    });

    test('the path survives, so the log still says which object', () {
      final line = redactUrls(
          'uri=https://b.s3.eu-central-003.backblazeb2.com/g/aa/b/dead?X-Amz-Signature=beef');
      expect(line, contains('/g/aa/b/dead'));
      expect(line, isNot(contains('beef')));
    });
  });

  // A raw status code sends somebody to a search engine rather than back to
  // the field they mistyped.
  group('a failure says what to do about it', () {
    test('a refused key names the two fields it could be', () {
      for (final code in const ['401', '403']) {
        final s = explainForTest(StateError('list: $code'));
        expect(s, contains('Key ID'));
        expect(s, isNot(contains(code)));
      }
    });

    test('a missing bucket names the bucket', () {
      expect(explainForTest(StateError('list: 404')), contains('bucket'));
    });

    test('anything else is passed through, redacted', () {
      expect(explainForTest(StateError('something odd')), contains('odd'));
    });
  });
  finalChecks();
}

// ---------------------------------------------------------------------------
// M446 — the last production pass.
// ---------------------------------------------------------------------------
void finalChecks() {
  // SigV4 signs with the DEVICE clock, so a tablet whose time is wrong gets a
  // 403 — the same status a wrong key gets. Reporting that as "check your
  // key" sends somebody to retype a key that was never the problem.
  group('a wrong clock is not a wrong key', () {
    final server = DateTime.utc(2026, 9, 22, 12);
    String hdr(DateTime d) =>
        '${['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d.weekday - 1]}, '
        '${d.day.toString().padLeft(2, '0')} '
        '${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][d.month - 1]} '
        '${d.year} ${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}:'
        '${d.second.toString().padLeft(2, '0')} GMT';

    test('a device an hour ahead is measured as an hour ahead', () {
      final skew = CloudSync.clockSkewOf(hdr(server),
          now: server.add(const Duration(hours: 1)));
      expect(skew, isNotNull);
      expect(skew!.inMinutes, 60);
    });

    test('a device an hour behind is measured too', () {
      final skew = CloudSync.clockSkewOf(hdr(server),
          now: server.subtract(const Duration(hours: 1)));
      expect(skew!.inMinutes, -60);
    });

    test('a correct clock is within the allowance', () {
      final skew = CloudSync.clockSkewOf(hdr(server),
          now: server.add(const Duration(seconds: 30)));
      expect(skew!.abs(), lessThan(CloudSync.maxClockSkew));
    });

    // No header is not evidence of a good clock, so nothing is claimed.
    test('a missing or unreadable header claims nothing', () {
      expect(CloudSync.clockSkewOf(null), isNull);
      expect(CloudSync.clockSkewOf(''), isNull);
      expect(CloudSync.clockSkewOf('not a date at all'), isNull);
    });

    test('the message sends you to the clock, not to the key', () {
      final s = explainForTest(StateError('list: 403 clock-skew 61min'));
      expect(s.toLowerCase(), contains('clock'));
      expect(s, isNot(contains('Key ID')),
          reason: 'the key is not the thing to go and check');
    });

    test('a real 403 still sends you to the key', () {
      final s = explainForTest(StateError('list: 403 SignatureDoesNotMatch'));
      expect(s, contains('Key ID'));
    });
  });

  // A manifest nobody updates keeps offering the versions that device held
  // when it last ran, and pins their bytes against the collector for ever.
  group('a manifest speaks only while its device is around', () {
    CloudManifest at(int atMs) => CloudManifest(
        device: 'd', deviceName: 'n', atMs: atMs, entries: const [],
        tombs: const []);
    final now = DateTime.utc(2026, 9, 22, 12);

    test('a manifest from today is live', () {
      expect(
          CloudSync.manifestIsLive(
              at(now.subtract(const Duration(hours: 2)).millisecondsSinceEpoch),
              now: now),
          isTrue);
    });

    test('one from a holiday ago is still live', () {
      expect(
          CloudSync.manifestIsLive(
              at(now.subtract(const Duration(days: 21)).millisecondsSinceEpoch),
              now: now),
          isTrue,
          reason: 'being away for three weeks must not unpair a device');
    });

    test('one from months ago is not', () {
      expect(
          CloudSync.manifestIsLive(
              at(now.subtract(const Duration(days: 45)).millisecondsSinceEpoch),
              now: now),
          isFalse);
    });

    // Refusing to read a manifest is how a REAL device's documents stop
    // arriving, so the two cases we cannot date are trusted.
    test('an undated manifest is trusted rather than dropped', () {
      expect(CloudSync.manifestIsLive(at(0), now: now), isTrue);
    });

    test('a peer whose clock is ahead is not mistaken for a stale one', () {
      expect(
          CloudSync.manifestIsLive(
              at(now.add(const Duration(days: 2)).millisecondsSinceEpoch),
              now: now),
          isTrue);
    });
  });
}
