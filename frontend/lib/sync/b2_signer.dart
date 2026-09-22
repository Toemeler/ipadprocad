// Prototype — signing a request to Backblaze B2, on the device.
//
// WHY THIS IS HERE AT ALL. M441 put the B2 credential in a Cloudflare Worker
// and had the app ask it for presigned URLs, on the reasoning M195 established
// and `relay/README.md` argues: a credential shipped inside the IPA is a
// credential in the wild the moment somebody extracts the app bundle.
//
// M442 keeps that reasoning and notices it does not cover THIS case. The two
// are different things:
//
//   * M195's key was ONE key, the same in every copy of the app, put there by
//     us. Anybody who downloaded the app had it, and it opened OUR repository.
//     That is a secret with no owner, and it was rightly rejected.
//   * This key is the user's own, typed in by them, scoped by them to one
//     bucket of their own, and kept in their own app container. It is the
//     same arrangement every S3 client on every platform uses — Cyberduck,
//     Transmit, rclone — because there is no other one available to a program
//     that talks to a bucket without a server in between.
//
// The cost is real and is stated rather than implied away: the key now sits on
// each device instead of in one Worker, so a device somebody else unlocks is a
// bucket somebody else can read. Scoped to one bucket, the blast radius is
// that bucket. `cloud_account.dart` says what to do about it (revoke the key —
// one click in the Backblaze console, and every device is locked out at once).
//
// WHAT SIGV4 IS, briefly, because the failure mode is the reason this file is
// so careful. Every request to B2 carries a signature over a CANONICAL form of
// itself: the method, the path, the query in sorted order, the signed headers,
// and a hash of the payload. The server rebuilds that form from what it
// received and checks the signature matches. Any disagreement at all — one
// byte encoded differently, one query parameter out of order, a date stamp
// sliced a character short — produces `SignatureDoesNotMatch` and nothing
// else. There is no partial credit and no useful error message.
//
// Which is why `m442_b2_signer_test.dart` checks this against AWS's OWN
// published example rather than against itself. A signer that reproduces a
// known signature byte for byte is correct; one that merely looks correct is
// not evidence of anything.
//
// NO NEW DEPENDENCY. SigV4 needs SHA-256 and HMAC-SHA256 and nothing else, and
// `crypto` has been in the tree since M381 for the share code and the mirror's
// per-file hash.
import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One set of Backblaze B2 credentials, as the settings sheet holds them.
///
/// Immutable and value-comparable: it is handed to a ValueNotifier the
/// settings rows watch, and a notifier that fires when nothing changed
/// redraws the sheet through a platform channel for nothing — the reason
/// [SyncStatus] gives for its own `==`.
class B2Credentials {
  /// The application key ID, e.g. `00319390fd8d1160000000001`.
  final String keyId;

  /// Its secret half, shown once by the Backblaze console.
  final String appKey;

  /// The bucket, e.g. `prototype-tomatensaftomat`.
  final String bucket;

  /// The region out of the bucket's endpoint: `s3.eu-central-003.backblazeb2.com`
  /// is region `eu-central-003`. See [regionFromEndpoint], which is what the
  /// settings row uses so nobody has to know that.
  final String region;

  const B2Credentials({
    required this.keyId,
    required this.appKey,
    required this.bucket,
    required this.region,
  });

  /// Whether all four fields are filled in. Nothing is attempted until they
  /// are — a half-entered account should be silent, not failing.
  bool get isComplete =>
      keyId.isNotEmpty &&
      appKey.isNotEmpty &&
      bucket.isNotEmpty &&
      region.isNotEmpty;

  /// The host B2 serves this bucket on, virtual-hosted style.
  String get host => '$bucket.s3.$region.backblazeb2.com';

  B2Credentials copyWith({
    String? keyId,
    String? appKey,
    String? bucket,
    String? region,
  }) =>
      B2Credentials(
        keyId: keyId ?? this.keyId,
        appKey: appKey ?? this.appKey,
        bucket: bucket ?? this.bucket,
        region: region ?? this.region,
      );

  @override
  bool operator ==(Object other) =>
      other is B2Credentials &&
      other.keyId == keyId &&
      other.appKey == appKey &&
      other.bucket == bucket &&
      other.region == region;

  @override
  int get hashCode => Object.hash(keyId, appKey, bucket, region);

  /// Never the key. This is what a log line or a `toString` in a stack trace
  /// would otherwise print, and a credential in a bug bundle is a credential
  /// in a GitHub issue.
  @override
  String toString() => 'B2Credentials($bucket @ $region)';
}

/// The region out of whatever the Backblaze console showed.
///
/// Takes the endpoint as it is displayed — `s3.eu-central-003.backblazeb2.com`
/// — and also a bare region, so a person who typed either gets the same
/// answer. Null when it is neither, which the settings row turns into "that
/// does not look like an endpoint" rather than a mirror that never connects.
///
/// THE POINT IS THAT NOBODY SHOULD HAVE TO KNOW THIS. The console shows an
/// endpoint; asking someone to work out which of its five dotted segments is
/// the region is the kind of step that turns a five-minute setup into a
/// support thread.
String? regionFromEndpoint(String input) {
  final s = input.trim().toLowerCase();
  if (s.isEmpty) return null;
  // Bare region, as the settings row itself stores it.
  if (RegExp(r'^[a-z]{2,4}-[a-z]+-\d{3}$').hasMatch(s)) return s;
  final m = RegExp(r'^(?:https?://)?s3\.([a-z0-9-]+)\.backblazeb2\.com/?$')
      .firstMatch(s);
  return m?.group(1);
}

/// AWS Signature Version 4, query-string form, for one B2 object operation.
///
/// EVERYTHING IS PRESIGNED, including requests this app makes and immediately
/// sends itself. Signing into the `Authorization` header and signing into the
/// query string differ in one place, and carrying both would mean two code
/// paths where one of them is always the one with the bug.
///
/// The payload is always `UNSIGNED-PAYLOAD`. Hashing a document body to sign
/// it would mean reading every megabyte of it twice, on the UI thread, for a
/// property TLS already provides on the wire.
class B2Signer {
  static const String _algorithm = 'AWS4-HMAC-SHA256';
  static const String _service = 's3';

  /// How long a signed URL is good for.
  ///
  /// Long enough for a slow upload of a large document on a phone connection,
  /// short enough that one caught in a log is not a standing grant.
  static const Duration defaultExpiry = Duration(minutes: 15);

  /// RFC 3986, which is stricter than [Uri.encodeComponent]: AWS wants the
  /// four characters it leaves alone encoded too, and a signature that
  /// disagrees with the server about one byte fails with no useful message.
  static String uriEncode(String s) =>
      Uri.encodeComponent(s).replaceAllMapped(
        RegExp(r"[!'()*]"),
        (m) => '%${m[0]!.codeUnitAt(0).toRadixString(16).toUpperCase()}',
      );

  /// A key's path, each SEGMENT encoded and the slashes left as separators.
  ///
  /// A blob key is `g/<hex>/b/<hex>`; encoding its slashes would sign a path
  /// the server never sees, and every request would fail.
  static String canonicalPath(String key) =>
      '/${key.split('/').map(uriEncode).join('/')}';

  /// The `20260922T114233Z` / `20260922` pair the signature needs in two
  /// places. Derived from ONE instant, because a scope dated differently from
  /// `X-Amz-Date` is rejected.
  static ({String amzDate, String dateStamp}) stamps(DateTime at) {
    final u = at.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    final date =
        '${u.year.toString().padLeft(4, '0')}${two(u.month)}${two(u.day)}';
    return (
      amzDate: '${date}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z',
      dateStamp: date,
    );
  }

  static List<int> _hmac(List<int> key, String message) =>
      Hmac(sha256, key).convert(utf8.encode(message)).bytes;

  /// A signed URL for [method] on [key], valid for [expiry].
  ///
  /// [query] carries operation parameters that must be SIGNED — a listing's
  /// `list-type` and `prefix`, say. Anything appended to the URL afterwards
  /// invalidates the signature, so there is nowhere else for them to go.
  static Uri sign({
    required B2Credentials credentials,
    required String method,
    required String key,
    Map<String, String> query = const {},
    Duration expiry = defaultExpiry,
    DateTime? now,
    String? hostOverride,
  }) {
    final at = now ?? DateTime.now();
    final (amzDate: amzDate, dateStamp: dateStamp) = stamps(at);
    final scope = '$dateStamp/${credentials.region}/$_service/aws4_request';
    // [hostOverride] exists for ONE caller: the test that reproduces AWS's
    // published example, which signs `examplebucket.s3.amazonaws.com`. Without
    // it the only way to check this signer against a known-good signature
    // would be to reimplement the host rule inside the test, which would then
    // be testing the test. Nothing in the app passes it.
    final host = hostOverride ?? credentials.host;

    final params = <String, String>{
      ...query,
      'X-Amz-Algorithm': _algorithm,
      'X-Amz-Credential': '${credentials.keyId}/$scope',
      'X-Amz-Date': amzDate,
      'X-Amz-Expires': '${expiry.inSeconds}',
      'X-Amz-SignedHeaders': 'host',
    };

    // Sorted by key, as the canonical form requires — not by insertion order,
    // which is a property of how this map happened to be built.
    final sortedKeys = params.keys.toList()..sort();
    final canonicalQuery = [
      for (final k in sortedKeys) '${uriEncode(k)}=${uriEncode(params[k]!)}',
    ].join('&');

    final canonicalPathStr = canonicalPath(key);
    final canonicalRequest = [
      method,
      canonicalPathStr,
      canonicalQuery,
      'host:$host\n',
      'host',
      'UNSIGNED-PAYLOAD',
    ].join('\n');

    final stringToSign = [
      _algorithm,
      amzDate,
      scope,
      sha256.convert(utf8.encode(canonicalRequest)).toString(),
    ].join('\n');

    var signing = _hmac(utf8.encode('AWS4${credentials.appKey}'), dateStamp);
    signing = _hmac(signing, credentials.region);
    signing = _hmac(signing, _service);
    signing = _hmac(signing, 'aws4_request');
    final signature = _hmac(signing, stringToSign)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return Uri.parse(
        'https://$host$canonicalPathStr?$canonicalQuery&X-Amz-Signature=$signature');
  }
}
