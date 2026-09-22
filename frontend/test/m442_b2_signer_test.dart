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
}
