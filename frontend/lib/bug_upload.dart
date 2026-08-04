// Prototype — M195: getting a bug bundle off the iPad by itself.
//
// THE PROBLEM WITH THE OLD LOOP
// -----------------------------
// Pressing the button wrote a zip into Files > On My iPad > prototype >
// bugreports, and there it sat until somebody remembered to pick it up and
// send it. A report that has to be carried by hand is a report that gets
// carried when it is convenient, which is never the moment the bug happened.
//
// WHERE IT GOES
// -------------
// Into a GitHub repository, via the Contents API — one authenticated PUT per
// bundle, no server to run and no service to sign up for. That target is
// chosen for one specific reason: a repository is somewhere the ASSISTANT can
// be pointed at ("look at the bug reports") and read every bundle itself,
// which a mailbox or a chat webhook is not.
//
// NOTHING IS CONFIGURED IN THIS REPOSITORY
// ----------------------------------------
// The destination lives in `bugupload.json` in the app's documents folder — on
// the DEVICE, reachable through the Files app, never in git. No file, no
// upload: the app then behaves exactly as it did before, and that is the
// default for anyone who builds this.
//
// TWO WAYS TO GET THERE, AND THE DIFFERENCE IS THE CREDENTIAL
// -----------------------------------------------------------
// RELAY (preferred). The iPad PUTs the raw zip at an https URL you control —
// ANY host will do, since this end is a plain PUT: a serverless function
// (Deno Deploy, Val.town, Vercel, Netlify, Lambda), or a box you already run.
// The GitHub token lives THERE, as a server-side secret. What the tablet holds
// is an upload key, and the worst anyone can do with a stolen one is APPEND
// files to the bug repository. It cannot read a repository, cannot touch
// source, cannot be replayed anywhere else, and it is rotated by editing one
// environment variable. The handler is about twenty lines; BUGREPORTS.md has
// it.
//
//   { "url": "https://bugs.you.workers.dev", "key": "any-long-random-string" }
//
// DIRECT. The iPad talks to the GitHub Contents API itself, holding a
// fine-grained PAT (one repo, Contents: RW, with an expiry). Fewer moving
// parts, but a real repository-write credential sits on a tablet — which is
// exactly the trade the relay exists to avoid. Kept because for a throwaway
// private repo it is a reasonable choice, not because it is the safe one.
//
//   {
//     "repo":   "Owner/name",
//     "branch": "reports",        // optional, default: the repo's default
//     "dir":    "bugreports",     // optional, path inside the repo
//     "token":  "github_pat_..."
//   }
//
// EITHER WAY THE SECRET NEVER LEAKS THROUGH US
// --------------------------------------------
// It is never logged (see [BugUploadConfig.toString], which redacts — so even
// an accidental interpolation cannot leak it), and the bundle builder never
// reads the documents directory, so the config cannot be swept into the very
// zip that is about to be published.
//
// FAILURE IS NORMAL
// -----------------
// An iPad is offline half the time. A bundle that fails to upload STAYS, and
// every later attempt retries it — that is what [pendingBundles] is for. A
// sent bundle gets a marker file beside it rather than being deleted: the
// local copy is the only one the user can still look at.
import 'dart:convert';
import 'dart:io';

import 'log.dart';

/// How a bundle travels.
enum BugUploadMode {
  /// Straight at your own endpoint, which holds the GitHub credential. The
  /// device carries an append-only upload key, or nothing at all.
  relay,

  /// Straight at GitHub, with a repository token on the device.
  github,
}

/// Where bundles are sent. Parsed from `bugupload.json`; absent or malformed
/// means "no uploading", which is a supported state and not an error.
class BugUploadConfig {
  final BugUploadMode mode;

  /// Relay only: the endpoint. The file name is appended as the last path
  /// segment, so the relay never has to parse anything.
  final String url;

  /// `Owner/name`. GitHub mode only.
  final String repo;

  /// Null = whatever the repository's default branch is.
  final String? branch;

  /// Folder inside the repository.
  final String dir;

  /// The device-side secret: an upload key for [BugUploadMode.relay], a
  /// fine-grained PAT for [BugUploadMode.github]. May be empty in relay mode
  /// (an unguessable Worker URL is itself the secret, if you prefer that).
  final String token;

  const BugUploadConfig({
    required this.token,
    this.mode = BugUploadMode.github,
    this.url = '',
    this.repo = '',
    this.branch,
    this.dir = 'bugreports',
  });

  /// A relay destination.
  const BugUploadConfig.relay({required this.url, this.token = ''})
      : mode = BugUploadMode.relay,
        repo = '',
        branch = null,
        dir = 'bugreports';

  /// Name of the file that holds this, in the app's documents folder.
  static const String fileName = 'bugupload.json';

  /// Returns null for anything unusable — a missing field, a repo that is not
  /// `Owner/name`, an empty token. Never throws: a broken config must not be
  /// able to stop the app, and it certainly must not stop a bug report from
  /// being WRITTEN.
  static BugUploadConfig? parse(String source) {
    try {
      final j = jsonDecode(source);
      if (j is! Map) return null;
      final repo = (j['repo'] as String?)?.trim() ?? '';
      final token = ((j['key'] ?? j['token']) as String?)?.trim() ?? '';

      // A url means the relay: no repo, no token, nothing here that can read
      // anything. Checked FIRST so a config carrying both is the safe one.
      final url = (j['url'] as String?)?.trim() ?? '';
      if (url.isNotEmpty) {
        final u = Uri.tryParse(url);
        // https only. A bundle holds the whole log and a screenshot of the
        // screen; sending that over plain http on café wifi is not a thing to
        // leave to a typo in a config file.
        if (u == null || u.scheme != 'https' || (u.host).isEmpty) return null;
        return BugUploadConfig.relay(
            url: url.replaceAll(RegExp(r'/+$'), ''), token: token);
      }

      if (token.isEmpty) return null;
      // Exactly one slash, and something on both sides of it.
      final parts = repo.split('/');
      if (parts.length != 2 || parts.any((p) => p.trim().isEmpty)) return null;
      final branch = (j['branch'] as String?)?.trim();
      final dir = (j['dir'] as String?)?.trim();
      return BugUploadConfig(
        repo: repo,
        token: token,
        branch: (branch == null || branch.isEmpty) ? null : branch,
        dir: (dir == null || dir.isEmpty)
            ? 'bugreports'
            : dir.replaceAll(RegExp(r'^/+|/+$'), ''),
      );
    } catch (_) {
      return null;
    }
  }

  /// Reads the config next to the bundles. Null when there is none.
  static BugUploadConfig? load(Directory docsRoot) {
    try {
      final f = File('${docsRoot.path}/$fileName');
      if (!f.existsSync()) return null;
      return parse(f.readAsStringSync());
    } catch (_) {
      return null;
    }
  }

  /// REDACTED on purpose. This is the last line of defence for a credential
  /// that lives on a tablet: the bundle carries the whole log, and the log is
  /// exactly where a stray '$cfg' would put the token — in a file that is
  /// about to be uploaded to a repository that may be public.
  @override
  String toString() => mode == BugUploadMode.relay
      ? 'BugUploadConfig(relay: ${Uri.tryParse(url)?.host ?? "?"}, '
          'key: <redacted>)'
      : 'BugUploadConfig(repo: $repo, branch: ${branch ?? "(default)"}, '
          'dir: $dir, token: <redacted>)';

  /// What the log and the dialog may say about the destination. The relay's
  /// full URL is itself a secret when it is the unguessable kind, so only the
  /// host goes in.
  String get describe => mode == BugUploadMode.relay
      ? (Uri.tryParse(url)?.host ?? 'relay')
      : repo;
}

/// Outcome of one attempt. [retry] says whether trying again later could ever
/// help — a rejected token cannot be fixed by waiting, and hammering a 401
/// every launch just burns battery.
enum BugSendResult {
  sent,
  noConfig,
  tooBig,
  offline,
  rejected,
}

extension BugSendOutcome on BugSendResult {
  bool get retry => this == BugSendResult.offline;
}

/// GitHub's own cap for the Contents API is far higher, but a bundle this big
/// means something went wrong while building it, and a tablet on cellular
/// should not spend ten minutes discovering that.
const int kMaxBundleBytes = 25 * 1024 * 1024;

/// The endpoint one bundle is PUT to.
Uri bundleUri(BugUploadConfig cfg, String fileName) =>
    cfg.mode == BugUploadMode.relay
        ? Uri.parse('${cfg.url}/$fileName')
        : Uri.https(
            'api.github.com',
            '/repos/${cfg.repo}/contents/${cfg.dir}/$fileName',
          );

/// The bytes that go on the wire.
///
/// The relay gets the zip ITSELF — no base64, no envelope, so the thing on the
/// other end can be thirty lines long and the tablet does not spend battery
/// inflating a 2 MB file by a third.
List<int> bundlePayload(
  BugUploadConfig cfg,
  String fileName,
  List<int> bytes,
) =>
    cfg.mode == BugUploadMode.relay
        ? bytes
        : utf8.encode(jsonEncode(bundleBody(cfg, fileName, bytes)));

/// The JSON body GitHub expects. [bytes] goes in base64 — the Contents API
/// takes the file inline, which is why this needs no multipart handling.
Map<String, Object?> bundleBody(
  BugUploadConfig cfg,
  String fileName,
  List<int> bytes,
) =>
    {
      'message': 'bug report $fileName',
      'content': base64Encode(bytes),
      if (cfg.branch != null) 'branch': cfg.branch,
    };

Map<String, String> bundleHeaders(BugUploadConfig cfg) =>
    cfg.mode == BugUploadMode.relay
        ? {
            // A header, not a query parameter: URLs end up in server logs and
            // browser history, and an upload key in a log file is one more
            // place it can be read from.
            if (cfg.token.isNotEmpty) 'X-Upload-Key': cfg.token,
            'Content-Type': 'application/zip',
            'User-Agent': 'ipadprocad-bugreporter',
          }
        : {
            'Authorization': 'Bearer ${cfg.token}',
            'Accept': 'application/vnd.github+json',
            'X-GitHub-Api-Version': '2022-11-28',
            'User-Agent': 'ipadprocad-bugreporter',
            'Content-Type': 'application/json',
          };

/// Classifies the answer, from GitHub or from a relay that forwards its status
/// (the Worker in BUGREPORTS.md does, which is why one table covers both).
///
/// 409/422 mean the path is already taken. Bundle names carry a timestamp to
/// the second, so in practice that is the SAME bundle sent twice — counting it
/// as delivered is what stops an unsendable file from being retried forever.
BugSendResult resultForStatus(int status) {
  if (status == 200 || status == 201) return BugSendResult.sent;
  if (status == 409 || status == 422) return BugSendResult.sent;
  if (status >= 500) return BugSendResult.offline; // GitHub having a moment
  return BugSendResult.rejected; // 401/403/404: config is wrong, not the net
}

/// Does the PUT. Injectable so the tests can exercise every branch above
/// without a network — the one thing a host test cannot have.
typedef BundlePutter = Future<int> Function(
    Uri url, Map<String, String> headers, List<int> body);

Future<int> _httpPut(
    Uri url, Map<String, String> headers, List<int> body) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 20);
  try {
    final req = await client.putUrl(url);
    headers.forEach(req.headers.set);
    req.add(body);
    final res = await req.close();
    await res.drain<void>();
    return res.statusCode;
  } finally {
    client.close(force: true);
  }
}

/// Marker written beside a bundle once it has landed. A marker rather than a
/// delete: the local copy is the only one the user can open on the device, and
/// a reporter that eats its own evidence is not one you trust twice.
File sentMarker(File bundle) => File('${bundle.path}.sent');

/// Bundles still waiting, oldest first. Sorted by name, which is the same
/// thing — the stem is a timestamp.
List<File> pendingBundles(Directory dir) {
  try {
    if (!dir.existsSync()) return const [];
    final zips = <File>[
      for (final e in dir.listSync())
        if (e is File &&
            e.path.endsWith('.zip') &&
            !sentMarker(e).existsSync())
          e
    ];
    zips.sort((a, b) => a.path.compareTo(b.path));
    return zips;
  } catch (_) {
    return const [];
  }
}

/// Sends one bundle. Never throws.
Future<BugSendResult> sendBundle(
  File bundle,
  BugUploadConfig? cfg, {
  BundlePutter? put,
}) async {
  if (cfg == null) return BugSendResult.noConfig;
  try {
    if (!bundle.existsSync()) return BugSendResult.sent; // nothing to do
    final bytes = bundle.readAsBytesSync();
    if (bytes.length > kMaxBundleBytes) {
      Log.w('bug', 'bundle too big to upload: ${bytes.length} bytes');
      return BugSendResult.tooBig;
    }
    final name = bundle.uri.pathSegments.last;
    final status = await (put ?? _httpPut)(
      bundleUri(cfg, name),
      bundleHeaders(cfg),
      bundlePayload(cfg, name, bytes),
    );
    final result = resultForStatus(status);
    // The destination, never the secret — see BugUploadConfig.toString.
    Log.i('bug', 'upload $name -> ${cfg.describe} [$status] ${result.name}');
    if (result == BugSendResult.sent) {
      try {
        sentMarker(bundle).writeAsStringSync(
            DateTime.now().toUtc().toIso8601String());
      } catch (_) {/* the retry is harmless: GitHub answers 422 */}
    }
    return result;
  } catch (e) {
    // Offline, DNS, TLS, a captive portal — all the same answer: try later.
    Log.w('bug', 'upload failed, will retry: $e');
    return BugSendResult.offline;
  }
}

/// Sends everything still pending. Called after a new report and once at
/// launch, so a bundle written on a plane goes out when the iPad next has a
/// network — that is the whole point of keeping the queue.
///
/// Returns the number delivered. Stops early on a [BugSendResult.rejected]:
/// if the token is wrong for one bundle it is wrong for all of them, and
/// twenty rejected PUTs are twenty chances to trip a rate limit.
Future<int> flushBugUploads(
  Directory bundleDir,
  BugUploadConfig? cfg, {
  BundlePutter? put,
}) async {
  if (cfg == null) return 0;
  var sent = 0;
  for (final b in pendingBundles(bundleDir)) {
    final r = await sendBundle(b, cfg, put: put);
    if (r == BugSendResult.sent) sent++;
    if (r == BugSendResult.rejected) break;
    if (r == BugSendResult.offline) break;
  }
  return sent;
}
