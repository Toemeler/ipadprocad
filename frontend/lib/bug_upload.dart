// Prototype — handing a bug bundle to the relay so it lands somewhere online.
//
// M195 built and reverted a direct-to-GitHub uploader: there is no anonymous
// write path into a repo, and a repo token baked into the shipped IPA is a
// plaintext credential on a tablet the moment someone extracts the app
// bundle. This module does not repeat that — it never holds a GitHub
// credential at all. It POSTs the bundle to a small relay (see
// `relay/worker.js`) that holds the token itself; the app carries at most an
// abuse-throttle string, not a secret with any write access of its own (see
// `relay/README.md` for exactly why that distinction holds).
//
// Local-first, always: this is called AFTER the bundle is already written to
// disk in bug_capture.dart, and a failure here must never make that report
// disappear or look like it failed. Every path returns a result; nothing
// throws out of [uploadBugReport].
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'log.dart';

/// The relay's address, baked in at build time via
/// `--dart-define=BUG_RELAY_URL=...`. Empty means "no relay configured" —
/// upload is skipped outright and the app behaves exactly as it did before
/// this module existed: local bundle only.
const String bugRelayUrl = String.fromEnvironment('BUG_RELAY_URL');

/// An abuse throttle the relay checks before spending its GitHub token on a
/// request. NOT a credential — see the module comment above. Baked in via
/// `--dart-define=BUG_RELAY_SECRET=...`.
const String bugRelaySecret = String.fromEnvironment('BUG_RELAY_SECRET');

/// Whether an upload will even be attempted.
bool get bugUploadConfigured => bugRelayUrl.isNotEmpty;

/// What came back from trying to hand the bundle to the relay.
class BugUploadResult {
  const BugUploadResult.ok({required this.issueUrl, this.fileUrl})
      : error = null;
  const BugUploadResult.failed(this.error, {this.fileUrl}) : issueUrl = null;

  /// The GitHub issue filed for this report, or null on failure.
  final String? issueUrl;

  /// The committed bundle's URL, when the relay got that far even if the
  /// issue itself failed to file.
  final String? fileUrl;

  final String? error;

  bool get ok => issueUrl != null;
}

/// POSTs [zipBytes] to the configured relay. Never throws: a network failure,
/// a timeout, or a malformed response all come back as a failed
/// [BugUploadResult] rather than an exception, because losing the (already
/// locally-saved) report to an upload error would be strictly worse than not
/// trying at all.
Future<BugUploadResult> uploadBugReport({
  required Uint8List zipBytes,
  required String stem,
  required String description,
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (!bugUploadConfigured) {
    return const BugUploadResult.failed('no relay configured');
  }
  try {
    final req = http.MultipartRequest('POST', Uri.parse(bugRelayUrl))
      ..fields['stem'] = stem
      ..fields['description'] = description
      ..files.add(http.MultipartFile.fromBytes('bundle', zipBytes,
          filename: '$stem.zip'));
    if (bugRelaySecret.isNotEmpty) {
      req.headers['x-bug-relay-secret'] = bugRelaySecret;
    }
    final streamed = await req.send().timeout(timeout);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      Log.w('bug', 'upload failed: HTTP ${streamed.statusCode} $body');
      return BugUploadResult.failed('HTTP ${streamed.statusCode}');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map) {
      return const BugUploadResult.failed('relay returned malformed JSON');
    }
    final issueUrl = decoded['issueUrl'];
    final fileUrl = decoded['fileUrl'];
    if (issueUrl is! String) {
      return BugUploadResult.failed(
          'relay did not return an issue URL: $body',
          fileUrl: fileUrl is String ? fileUrl : null);
    }
    return BugUploadResult.ok(
        issueUrl: issueUrl, fileUrl: fileUrl is String ? fileUrl : null);
  } catch (e) {
    Log.w('bug', 'upload failed: $e');
    return BugUploadResult.failed('$e');
  }
}
