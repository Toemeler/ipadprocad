// M442 — the one thing you type, and the only thing either mirror needs.
//
// WHAT REPLACED WHAT. Until now pairing was a SHARE CODE: twelve characters
// somebody read off one screen and typed into another. It did three jobs at
// once (see `share_code.dart`) — a name for the group, a key for the LAN
// handshake, and a fingerprint to broadcast — and it did them for a mirror
// that never left the local network.
//
// M441 added a bucket, and that made the code the weaker half of the setup: a
// person now had to type a code AND stand up a Worker AND hold a B2 key, three
// secrets for one idea ("these are my devices"). Worse, `share_code.dart` is
// explicit that the code is "not a password and is not treated as one — a
// rendezvous token whose exposure is bounded by being on one local network",
// and a bucket removes that bound.
//
// So there is one secret now, and it is the one that was unavoidable anyway:
// THE BACKBLAZE APPLICATION KEY. Devices holding the same key and bucket are
// the same group. Nothing else is typed, and nothing is generated.
//
// WHAT THAT BUYS, beyond one less thing to type:
//
//   * ENTROPY. A share code is 60 bits of a 32-symbol alphabet, chosen to be
//     sayable across a room. A B2 application key is 31 characters the
//     console generated and nobody ever reads aloud. The group fingerprint
//     derived from it is not something anyone precomputes.
//   * ONE REVOCATION. Revoking the key in the Backblaze console locks every
//     device out of the bucket AND, because the LAN group is derived from it,
//     unpairs them from each other. Before, those were two unrelated actions
//     and forgetting one of them left a device still syncing.
//   * NO SERVER. The app signs its own B2 requests (`b2_signer.dart`), so
//     there is nothing to deploy and no terminal needed. M441's Worker still
//     works and is still the right answer when the credential must not be on
//     the device at all; see `cloud/README.md`.
//
// WHAT IT COSTS, said plainly. The key is on each device rather than in one
// Worker, so a device somebody else unlocks is a bucket somebody else can
// read. Scope the key to one bucket in the console — the blast radius is then
// that bucket, and revoking it is one click.
//
// WHERE IT IS KEPT, AND WHY NOT IN settings.json. The obvious home is the
// preferences file every other setting lives in. It would be a serious
// mistake:
//
//   `settings.json` IS MIRRORED. It is in `LanSync._prefFiles`, so it travels
//   to every peer and, since M441, up to the bucket. `_localOnlyPrefs` does
//   NOT prevent that — read it again in `_applySettings`: it filters what is
//   taken FROM a peer, never what is sent TO one. The file goes out verbatim.
//
// And the LAN mirror is not encrypted; `lan_sync.dart` says so in its header.
// A credential in `settings.json` would therefore be broadcast in the clear
// across the local network on every sync, and uploaded to the very bucket it
// unlocks. So this lives in its OWN file, beside the delete journal and the
// agreed-version journal, which are not mirrored for the same kind of reason:
// they describe THIS INSTALL, not the gallery.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../log.dart';
import 'b2_signer.dart';
import 'cloud_sync.dart';
import 'lan_sync.dart';

/// Where the account is remembered.
///
/// ITS OWN FILE, and the name matters: anything added to
/// [LanSync._prefFiles] travels, and this must never be added there. There is
/// a test that fails if it ever is.
///
/// WHAT THIS IS NOT, AND THE GAP IS REAL. This is a plain JSON file holding a
/// live credential. It is not the platform keystore, and the two differ in
/// ways worth naming rather than glossing:
///
///   * ON iOS the app container is sandboxed and encrypted while the device
///     is locked, which is most of what the Keychain would add — but
///     `UIFileSharingEnabled` is on (the gallery is meant to be browsable in
///     Files), and this file sits under `<Documents>/.cache`. A leading dot
///     is why Files does not list it. THAT IS OBSCURITY, NOT PROTECTION: an
///     unencrypted local backup carries the whole container, dot-files
///     included.
///   * ON A DESKTOP there is no container at all. [_restrictToThisUser] takes
///     the group and world bits off, which stops the other accounts on the
///     machine; it does nothing about a stolen disk.
///
/// The fix is the Keychain on iOS and libsecret/DPAPI on the desktop, which
/// is a plugin and a platform channel per OS — real work, not a line. Until
/// then: SCOPE THE KEY TO ONE BUCKET in the Backblaze console, so what a
/// copied file costs is that bucket, and revoking it is one click that locks
/// every device out at once.
class CloudAccountStore {
  final Directory dir;
  const CloudAccountStore(this.dir);

  /// Deliberately NOT `settings.json`, and deliberately not in
  /// `LanSync._prefFiles`. See this file's header.
  static const String fileName = 'b2-account.json';

  File get file => File('${dir.path}/$fileName');

  B2Credentials? load() {
    try {
      final f = file;
      if (!f.existsSync()) return null;
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return null;
      final c = B2Credentials(
        keyId: '${raw['keyId'] ?? ''}',
        appKey: '${raw['appKey'] ?? ''}',
        bucket: '${raw['bucket'] ?? ''}',
        region: '${raw['region'] ?? ''}',
      );
      // A PARTIAL ACCOUNT IS KEPT, not discarded. The four fields are typed
      // one row at a time and come off two different pages of the Backblaze
      // console, so an account is incomplete for as long as it takes to fetch
      // the next one — including across the app being closed. What an
      // incomplete account does NOT do is start anything; see [set].
      return (c.keyId.isEmpty &&
              c.appKey.isEmpty &&
              c.bucket.isEmpty &&
              c.region.isEmpty)
          ? null
          : c;
    } catch (e) {
      // Never logs the file's contents.
      Log.w('cloud', 'could not read the account: $e');
      return null;
    }
  }

  void save(B2Credentials? c) {
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = file;
      if (c == null) {
        if (f.existsSync()) f.deleteSync();
        return;
      }
      // Written through a temporary and renamed, like every other journal
      // here: a half-written credential file read at the next launch is an
      // account that silently stops working.
      final tmp = File('${f.path}.part');
      tmp.writeAsStringSync(
          jsonEncode({
            'keyId': c.keyId,
            'appKey': c.appKey,
            'bucket': c.bucket,
            'region': c.region,
          }),
          flush: true);
      tmp.renameSync(f.path);
      _restrictToThisUser(f);
    } catch (e) {
      Log.w('cloud', 'could not remember the account: $e');
    }
  }

  /// Takes the file's group and world permissions away, where that means
  /// anything.
  ///
  /// ON A SHARED DESKTOP IT MEANS A GREAT DEAL. `writeAsStringSync` creates a
  /// file at the process umask, which on most Linux systems is 0644 — every
  /// account on the machine can read it, and the Backblaze key opens the
  /// bucket from anywhere. The iPad does not need this (a container is
  /// unreadable by other apps) and Windows does not have it, which is why the
  /// failure is swallowed rather than reported: `chmod` is absent on Windows
  /// and this is best-effort hardening, not a precondition for syncing.
  ///
  /// It is NOT a substitute for the platform keystore. See the class comment.
  static void _restrictToThisUser(File f) {
    if (!Platform.isLinux && !Platform.isMacOS) return;
    try {
      Process.runSync('chmod', ['600', f.path]);
    } catch (_) {
      // Best effort. A file that could not be chmod'ed is still the file the
      // user asked us to keep, and refusing to sync over it would be a
      // worse answer than syncing.
    }
  }
}

/// The live account, as something the settings sheet can listen to.
///
/// Mirrors [ShareCodes] exactly, and for the same reason: the sheet reads it
/// at build time, so one notification rebuilds the row without a BuildContext
/// being threaded anywhere.
class CloudAccount {
  CloudAccount._();

  /// The credentials, or null when this device has no account.
  static final ValueNotifier<B2Credentials?> current =
      ValueNotifier<B2Credentials?>(null);

  static CloudAccountStore? _store;

  /// The group both mirrors pair on, derived from the account.
  ///
  /// DOMAIN-SEPARATED AND ONE-WAY. This is handed to [LanSync.setCode], which
  /// hashes it again into a handshake key and a fingerprint it broadcasts —
  /// so this string reaches the network, and it must not be possible to walk
  /// back from it to the application key. A sha256 under its own prefix is
  /// that, and `share_code.dart` derives its own key the same way for the
  /// same reason.
  ///
  /// THE BUCKET IS IN IT as well as the key. A key is scoped to a bucket in
  /// the console, so in practice one implies the other; including both means
  /// two accounts that somehow shared a key still cannot be one group by
  /// accident.
  static String? tokenFor(B2Credentials? c) {
    if (c == null || !c.isComplete) return null;
    return sha256
        .convert(utf8.encode('prototype-group\x00${c.appKey}\x00${c.bucket}'))
        .toString();
  }

  /// The group token for the account this device holds, or null.
  static String? get token => tokenFor(current.value);

  /// Point the account at a file, adopt what it remembers, and START both
  /// mirrors if there is an account. Called from AppState.init, off the
  /// launch path, like the other preference stores.
  static void attachStore(CloudAccountStore store) {
    _store = store;
    final saved = store.load();
    if (saved == null) return;
    current.value = saved;
    if (!saved.isComplete) return;
    // Not awaited: one mirror binds sockets and the other reaches a bucket,
    // and the launch path must wait for neither. Both report through their
    // own status.
    _start(saved);
  }

  /// Sets (or clears) the account, remembers it, and turns both mirrors on or
  /// off together.
  ///
  /// ONE KEY DRIVES BOTH. The LAN mirror is the fast path when two devices can
  /// see each other — a save is on the other machine in about a second — and
  /// the bucket is what makes a device that was switched off catch up at all.
  /// They are two transports over one group, not two features, so there is one
  /// place to turn them on.
  /// AN INCOMPLETE ACCOUNT IS REMEMBERED BUT STARTS NOTHING. The four fields
  /// are entered one row at a time, so for most of the setup there is a
  /// partial account on this device; throwing it away between rows would make
  /// the form impossible to finish. [tokenFor] returns null until it is
  /// complete, which is what keeps both mirrors off in the meantime.
  static Future<void> set(B2Credentials? credentials) async {
    final next = (credentials == null ||
            (credentials.keyId.isEmpty &&
                credentials.appKey.isEmpty &&
                credentials.bucket.isEmpty &&
                credentials.region.isEmpty))
        ? null
        : credentials;
    if (next == current.value) return;
    current.value = next;
    _store?.save(next);
    await LanSync.instance.setCode(tokenFor(next));
    // NOT awaited, for the reason `sync_store.dart` gives: the settings sheet
    // redraws in a `.then()` on this future, and a round trip to a bucket is
    // not something the Account row should make somebody watch.
    // `setAccount` refuses an incomplete one itself, so this is off until
    // every field is there.
    CloudSync.instance.setAccount(next).catchError(
        (Object e) => Log.w('cloud', 'could not change the cloud mirror: $e'));
  }

  @visibleForTesting
  static void resetForTest() {
    _store = null;
    current.value = null;
  }
}

void _start(B2Credentials c) {
  LanSync.instance.setCode(CloudAccount.tokenFor(c)).catchError(
      (Object e) => Log.w('sync', 'could not start sharing: $e'));
  CloudSync.instance.setAccount(c).catchError(
      (Object e) => Log.w('cloud', 'could not start the cloud mirror: $e'));
}
