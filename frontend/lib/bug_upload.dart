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

/// The cleared checkbox, written where an OLD RELAY CANNOT DROP IT.
///
/// M370 — WHY THE `autofix` FIELD IS NOT ENOUGH ON ITS OWN.
///
/// The relay decides an issue's label, and the label is what decides whether
/// `ci/bugfix` may claim it. `relay/worker.js` reads the `autofix` field and
/// does exactly that — but the relay is a Cloudflare Worker deployed by hand
/// with `wrangler deploy`, and the checkbox and the Worker's support for it
/// shipped in the same commit. Until someone redeploys, the live Worker is a
/// build that has never heard of the field: an unknown multipart field is
/// silently ignored, every report is filed under `bug-report`, and the box
/// does nothing at all. That is not a bug in either half; it is a switch whose
/// two ends were shipped on different release schedules.
///
/// So the answer also travels in the one thing EVERY version of the relay
/// forwards to GitHub verbatim: the description, which becomes the issue body.
/// `.github/workflows/bugfix.yml` reads it back from there and sets the label
/// the relay could not — see `ci/bugfix.AUTOFIX_OFF`, which must stay
/// byte-identical to this and has a test that says so.
///
/// Only the OFF direction is ever written. Absent means yes, exactly as the
/// missing field does, so nothing here can park a report nobody is watching.
const String bugAutofixOffMarker = '[autofix: off]';

/// The description to send, with the cleared box folded into it.
///
/// The marker goes LAST because the relay takes the issue TITLE from the first
/// non-empty line. A wordless report — which this dialog deliberately allows,
/// the state dump being the valuable half — would otherwise be titled with the
/// marker, so it gets the same placeholder first line the relay would have
/// written for it and keeps the marker out of the title either way.
String bugDescriptionFor(String text, {required bool autofix}) {
  if (autofix) return text;
  final head = text.trim().isEmpty ? '(no description given)' : text;
  return '$head\n\n$bugAutofixOffMarker';
}

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
  /// False when the reporter cleared the box in the dialog. The label on the
  /// issue is what decides whether `ci/bugfix` may claim it — see
  /// `.github/workflows/bugfix.yml` — and this reaches that label by two
  /// independent roads, because either one alone has a version of the relay
  /// that ignores it:
  ///
  ///   * the `autofix` FIELD, which a current `relay/worker.js` turns straight
  ///     into the label. Sent as '1'/'0' because a multipart field is a string
  ///     either way, and an absent field must mean "yes" for older app builds;
  ///   * the MARKER in the description ([bugAutofixOffMarker]), which every
  ///     version of the relay forwards into the issue body untouched, and
  ///     which the workflow translates into the same label.
  ///
  /// They agree by construction: both are derived from this one argument.
  bool autofix = true,
  Duration timeout = const Duration(seconds: 20),
}) async {
  if (!bugUploadConfigured) {
    return const BugUploadResult.failed('no relay configured');
  }
  try {
    final req = http.MultipartRequest('POST', Uri.parse(bugRelayUrl))
      ..fields['stem'] = stem
      // Folded in HERE rather than at the call site, so no caller can send
      // the flag and forget the marker and produce a report whose body and
      // whose form field disagree.
      ..fields['description'] = bugDescriptionFor(description, autofix: autofix)
      ..fields['autofix'] = autofix ? '1' : '0'
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
