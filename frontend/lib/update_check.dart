// Prototype — checking GitHub for a newer desktop build, and applying one.
//
// iOS updates through SideStore/AltStore, which already polls source.json
// (see ci/publish_release.sh) — this file is Linux and Windows only, the two
// platforms with no store doing that for them.
//
// WHAT "NEWER" MEANS HERE. A desktop build carries no version number — only
// a commit, embedded as Log.build (--dart-define=GIT_SHA, see log.dart) — and
// every push to main publishes a GitHub Release tagged `build-<short sha>`,
// which build.yml's own comments call "the install target for main" (see
// .github/workflows/build.yml). So "is there an update" is simply: does
// GitHub's releases/latest carry a DIFFERENT tag than `build-<Log.build>`.
// A named `v*` release compares unequal by the same rule and is offered too
// — there is no local record of which commit a named tag was cut from to
// compare more precisely than that, and it is meant to be offered.
//
// THROTTLED AND REMEMBERED, in the same settings.json every other preference
// lives in (see sync/sync_store.dart for the pattern this copies): at most
// once every twenty hours, so a user who launches the app ten times a day
// does not spend ten unauthenticated GitHub API calls on it, and a tag the
// user dismissed with "Cancel" is not asked about again until a NEWER one
// replaces it.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;

import 'log.dart';

/// One release worth offering, already resolved to the asset this platform
/// can actually use.
class UpdateInfo {
  /// The release's tag_name — `build-<sha>` for the rolling channel, or a
  /// named `v*` tag. Never shown to the user (see l10n/app_en.arb —
  /// updateAvailableMessage is deliberately version-less); only logged and
  /// used to remember what was dismissed.
  final String tag;

  /// Where the platform asset lives, or empty when [selfUpdatable] is false
  /// and there is nothing to download — see updateManualMessage.
  final String assetUrl;

  /// [assetUrl]'s own filename — what a line in [checksumsUrl] names it as.
  final String assetName;

  /// Where the release's SHA256SUMS file for this platform lives (see
  /// build.yml's "ONE CHECKSUM FILE PER PLATFORM" step and
  /// ci/release_attach.sh, which both the rolling and named channels go
  /// through), or empty when the release carries none. [apply] refuses to
  /// run anything it cannot check against this — see [_verify].
  final String checksumsUrl;

  /// The release's own page, for the one channel this cannot apply itself.
  final String releaseUrl;

  /// True when [apply] can download and install this without the user
  /// leaving the app — Windows always, Linux only when running as the
  /// AppImage (see _pickAsset). False for a directory install (the
  /// prototype-*-linux-x64.tar.gz channel): there is no single file to swap
  /// out from under dozens of others the process has open.
  final bool selfUpdatable;

  const UpdateInfo({
    required this.tag,
    required this.assetUrl,
    required this.assetName,
    required this.checksumsUrl,
    required this.releaseUrl,
    required this.selfUpdatable,
  });
}

/// Where [UpdateCheck] remembers the last check time and the last tag the
/// user said not now to. Same file, same merge-not-own discipline as
/// SyncStore — see sync/sync_store.dart's header for why.
class UpdateStore {
  final Directory dir;
  const UpdateStore(this.dir);

  static const String fileName = 'settings.json';
  static const String key = 'update';

  File get _file => File('${dir.path}/$fileName');

  Map<String, Object?> _section() {
    try {
      final f = _file;
      if (!f.existsSync()) return const <String, Object?>{};
      final raw = jsonDecode(f.readAsStringSync());
      if (raw is! Map) return const <String, Object?>{};
      final s = raw[key];
      return s is Map
          ? <String, Object?>{for (final e in s.entries) '${e.key}': e.value}
          : const <String, Object?>{};
    } catch (e) {
      Log.w('update', 'could not read settings: $e');
      return const <String, Object?>{};
    }
  }

  /// Reads whatever is there, merges [patch] into this store's own section,
  /// and writes it back.
  ///
  /// A file that fails to PARSE is read as empty rather than aborting the
  /// write: the alternative — the read throwing, caught by an outer
  /// try/catch that covers the write too — means this store can never save
  /// anything again once settings.json is corrupt once, which is a worse
  /// failure than losing whatever else was in the file that one time. Only
  /// the write itself (a full disk, a permissions problem) is left to abort
  /// silently; there is nothing more useful to do about that.
  void _merge(Map<String, Object?> patch) {
    Map<String, Object?> data = <String, Object?>{};
    final f = _file;
    try {
      if (f.existsSync()) {
        final raw = jsonDecode(f.readAsStringSync());
        if (raw is Map) {
          data = <String, Object?>{
            for (final e in raw.entries) '${e.key}': e.value
          };
        }
      }
    } catch (e) {
      Log.w('update', 'settings.json unreadable, replacing it: $e');
    }
    final section = <String, Object?>{..._section(), ...patch};
    data[key] = section;
    try {
      if (!dir.existsSync()) dir.createSync(recursive: true);
      f.writeAsStringSync(jsonEncode(data));
    } catch (e) {
      Log.w('update', 'could not save settings: $e');
    }
  }

  DateTime? get lastCheckAt {
    final v = _section()['lastCheckAt'];
    return v is String ? DateTime.tryParse(v) : null;
  }

  String? get skipTag {
    final v = _section()['skipTag'];
    return v is String ? v : null;
  }

  void recordCheck() =>
      _merge({'lastCheckAt': DateTime.now().toUtc().toIso8601String()});

  void recordSkip(String tag) => _merge({'skipTag': tag});
}

class UpdateCheck {
  UpdateCheck._();

  static const String _repo = 'toemeler/ipadprocad';
  static const Duration _interval = Duration(hours: 20);

  static UpdateStore? _store;

  /// Called once, from AppState.init, alongside the other `attachStore`
  /// calls — see app_state.dart.
  static void attachStore(UpdateStore store) => _store = store;

  /// The AppImage this process was launched from, or null when it was not
  /// (a plain extracted `prototype-*-linux-x64.tar.gz` install, or a dev
  /// run). Set by the AppImage runtime itself before exec — see
  /// https://github.com/AppImage/AppImageKit — not something this app
  /// writes.
  static String? get _appImagePath => Platform.isLinux
      ? Platform.environment['APPIMAGE']
      : null;

  /// Null when there is nothing to offer: not due yet, no newer release,
  /// the user already dismissed this exact tag, or the check itself failed
  /// (network errors are swallowed here — a failed update check must never
  /// interrupt launch or read as an app error to the user).
  static Future<UpdateInfo?> checkIfDue() async {
    if (!(Platform.isLinux || Platform.isWindows)) return null;
    // 'local' is a developer's own build (see log.dart) — nothing on GitHub
    // corresponds to it, so every release would look "newer".
    if (Log.build == 'local') return null;
    final store = _store;
    if (store == null) return null;
    final last = store.lastCheckAt;
    if (last != null && DateTime.now().toUtc().difference(last) < _interval) {
      return null;
    }
    store.recordCheck();

    try {
      final resp = await http.get(
        Uri.parse('https://api.github.com/repos/$_repo/releases/latest'),
        // GitHub's REST API 403s any request with no User-Agent at all.
        headers: const {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'prototype-desktop-updater',
        },
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        Log.w('update', 'releases/latest: HTTP ${resp.statusCode}');
        return null;
      }
      final data = jsonDecode(resp.body);
      if (data is! Map) return null;
      final tag = data['tag_name'];
      if (tag is! String || tag.isEmpty) return null;

      if (tag == 'build-${Log.build}') return null; // already this build
      if (tag == store.skipTag) return null; // already said not now

      final assets = data['assets'];
      final releaseUrl = data['html_url'] is String ? data['html_url'] as String : '';
      final info = _pickAsset(
          tag, assets is List ? assets : const [], releaseUrl);
      if (info != null) {
        Log.i('update', 'newer release available: $tag');
      }
      return info;
    } catch (e) {
      Log.w('update', 'check failed: $e');
      return null;
    }
  }

  static UpdateInfo? _pickAsset(String tag, List assets, String releaseUrl) {
    // Positional record: .$1 is the asset's name, .$2 its download URL.
    (String, String)? findEndingWith(String suffix) {
      for (final a in assets) {
        if (a is Map) {
          final name = a['name'];
          final url = a['browser_download_url'];
          if (name is String && url is String && name.endsWith(suffix)) {
            return (name, url);
          }
        }
      }
      return null;
    }

    if (Platform.isWindows) {
      final asset = findEndingWith('-windows-setup.exe');
      if (asset == null) return null; // no matching asset on this release
      final checksums = findEndingWith('SHA256SUMS-windows.txt');
      return UpdateInfo(
          tag: tag,
          assetUrl: asset.$2,
          assetName: asset.$1,
          checksumsUrl: checksums?.$2 ?? '',
          releaseUrl: releaseUrl,
          selfUpdatable: true);
    }

    if (Platform.isLinux) {
      if (_appImagePath != null) {
        final asset = findEndingWith('.AppImage');
        if (asset != null) {
          final checksums = findEndingWith('SHA256SUMS-linux.txt');
          return UpdateInfo(
              tag: tag,
              assetUrl: asset.$2,
              assetName: asset.$1,
              checksumsUrl: checksums?.$2 ?? '',
              releaseUrl: releaseUrl,
              selfUpdatable: true);
        }
      }
      // The tar.gz channel (or an AppImage release that, for whatever
      // reason, shipped none this time): see UpdateInfo.selfUpdatable.
      return UpdateInfo(
          tag: tag,
          assetUrl: '',
          assetName: '',
          checksumsUrl: '',
          releaseUrl: releaseUrl,
          selfUpdatable: false);
    }

    return null;
  }

  /// Remembers that the user said not now to this tag, so it is not asked
  /// about again until a newer one replaces it.
  static void skip(String tag) => _store?.recordSkip(tag);

  /// Downloads and applies [info], ending with the new build ready to run.
  ///
  /// Returns true when the CALLER must now exit the process, and it must do
  /// so IMMEDIATELY — everything slow has already been done.
  ///
  /// [beforeInstall] is where the caller saves. It runs after the download is
  /// downloaded and verified and BEFORE anything is launched, and that order
  /// is the whole of this method's contract.
  ///
  /// WHY, because it was the other way round and that is the bug. The Windows
  /// path used to launch Setup and return, leaving the caller to flush its
  /// documents afterwards. Setup is `CloseApplications=yes`
  /// (windows/installer/prototype.iss), which means the Restart Manager
  /// reaches for this process within a second or two of starting — while the
  /// caller was still writing a part file. The app vanished mid-save. From
  /// the outside that is indistinguishable from a crash, it happened on a
  /// document large enough to take a moment, and it could take the document
  /// with it. "the auto update is crashing the app often and is very
  /// unreliable" is that race.
  ///
  /// Nothing after [beforeInstall] can block: the script is spawned detached
  /// and this returns at once.
  ///
  /// False means nothing was applied — either it opened the release page
  /// instead (the non-self-updatable Linux channel) or the download, the
  /// checksum or the launch failed, logged, with the app left running exactly
  /// as it was and no installer started.
  static Future<bool> apply(UpdateInfo info,
      {Future<void> Function()? beforeInstall}) async {
    if (!info.selfUpdatable) {
      _openInBrowser(info.releaseUrl);
      return false;
    }

    final downloaded = await _download(info);
    if (downloaded == null) return false;

    if (!await _verify(downloaded, info)) {
      try {
        await downloaded.delete();
      } catch (_) {
        // Nothing more to do about a temp file that would not go away.
      }
      return false;
    }

    // The last point at which failing is still free. After this the installer
    // is running and the app is going away.
    if (beforeInstall != null) {
      try {
        await beforeInstall().timeout(_flushWindow);
      } catch (e) {
        // A save that failed or hung must not strand the user on a build they
        // have already agreed to replace, and must not skip the exit below
        // and leave the Restart Manager to do the closing. Say so and go on:
        // the document is no worse off than if they had closed the window.
        Log.w('update', 'pre-install flush did not finish: $e');
      }
    }

    if (Platform.isWindows) {
      try {
        await _runWindowsInstaller(downloaded);
        return true;
      } catch (e) {
        Log.w('update', 'could not launch the installer: $e');
        return false;
      }
    }

    if (Platform.isLinux) {
      final target = _appImagePath;
      if (target == null) return false; // should not happen — see _pickAsset
      try {
        await Process.run('chmod', ['+x', downloaded.path]);
        // Same filesystem as target (see _download) makes this an atomic
        // POSIX rename — never a half-written AppImage at `target`, whatever
        // happens to the process a moment later.
        await downloaded.rename(target);
        await Process.start(target, const [], mode: ProcessStartMode.detached);
        return true;
      } catch (e) {
        Log.w('update', 'could not apply the AppImage update: $e');
        return false;
      }
    }

    return false;
  }

  /// How long [apply] waits for the caller's save before going ahead.
  static const Duration _flushWindow = Duration(seconds: 30);

  /// The batch file that runs Setup once this process is gone, and brings the
  /// app back afterwards.
  ///
  /// THREE THINGS THE OLD ONE-LINER DID NOT DO.
  ///
  /// It waits for US. Setup's `CloseApplications=yes` would otherwise reach
  /// for a process that is already on its way out, and the two racing is what
  /// made an update look like a crash. Waiting on the PID means Setup finds
  /// nothing to close, which also settles the second problem below.
  ///
  /// It brings the app BACK. Setup is `RestartApplications=yes`, but the
  /// Restart Manager only restarts what IT closed — and after a clean exit
  /// there is nothing for it to have closed, so the app simply did not come
  /// back. Updating and being left staring at the desktop is most of "very
  /// unreliable". Now exactly one thing relaunches the app: this script,
  /// after Setup has finished, whatever the Restart Manager did or did not do.
  ///
  /// It CLEANS UP. The installer and the script both go, so %TEMP% does not
  /// collect a 100 MB installer per update.
  ///
  /// Pure and exported for testing: the quoting is the part that goes wrong,
  /// and `Program Files` has a space in it.
  static String windowsRelaunchScript({
    required int waitForPid,
    required String installerPath,
    required String exePath,
  }) =>
      '@echo off\r\n'
      'setlocal\r\n'
      'rem Wait for the app to let go of its files. `tasklist` is on every\r\n'
      'rem supported Windows; `ping -n 2 127.0.0.1` is the sleep that is.\r\n'
      ':wait\r\n'
      'tasklist /FI "PID eq $waitForPid" 2>NUL | find "$waitForPid" >NUL\r\n'
      'if not errorlevel 1 (\r\n'
      '  ping -n 2 127.0.0.1 >NUL\r\n'
      '  goto wait\r\n'
      ')\r\n'
      'rem Silent: the user already answered "update now" inside the app.\r\n'
      'rem /NORESTART is about REBOOTING, not about the app.\r\n'
      '"$installerPath" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART\r\n'
      'start "" "$exePath"\r\n'
      'del /f /q "$installerPath" >NUL 2>&1\r\n'
      'del /f /q "%~f0" >NUL 2>&1\r\n';

  /// Writes [windowsRelaunchScript] and starts it detached.
  static Future<void> _runWindowsInstaller(File installer) async {
    final script = File(
        '${installer.parent.path}/${_downloadPrefix}$pid.cmd');
    await script.writeAsString(windowsRelaunchScript(
      waitForPid: pid,
      installerPath: installer.path,
      exePath: Platform.resolvedExecutable,
    ));
    // `cmd /c` rather than the .cmd directly: a detached batch file needs an
    // interpreter, and this is the one every Windows has.
    await Process.start(
      'cmd',
      ['/c', script.path],
      mode: ProcessStartMode.detached,
    );
    Log.i('update', 'installer queued; this process may now exit');
  }

  /// The hash [assetName] is recorded against in a `sha256sum`-format file
  /// ([sumsBody]), lower-cased, or null when no line names it or the token in
  /// that position is not a plausible sha256 hex digest.
  ///
  /// Pure and exported for testing (see [_verify]): the network fetch around
  /// it is the only part that needs a release to exercise.
  static String? checksumFor(String sumsBody, String assetName) {
    final line = sumsBody
        .split('\n')
        .firstWhere((l) => l.contains(assetName), orElse: () => '');
    if (line.isEmpty) return null;
    final hash = line.trim().split(RegExp(r'\s+')).first.toLowerCase();
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(hash) ? hash : null;
  }

  /// Checks [downloaded] against the release's own SHA256SUMS file before
  /// [apply] does anything with it — a corrupted or tampered download must
  /// never be run silently, which is exactly what the caller was about to do.
  ///
  /// False on a mismatch, and equally on any reason the check itself could
  /// not be completed: no checksums file on the release, a network failure
  /// fetching it, or no line naming this asset. Both channels this app
  /// offers publish one (see [UpdateInfo.checksumsUrl]), so this is not
  /// expected to fail in ordinary operation — but where it does, "no update"
  /// is the safe answer, the same choice M413 made about a screenshot it
  /// could not verify.
  static Future<bool> _verify(File downloaded, UpdateInfo info) async {
    if (info.checksumsUrl.isEmpty || info.assetName.isEmpty) {
      Log.w('update', 'no checksums published for ${info.tag} — not applying');
      return false;
    }
    String expected;
    try {
      final resp = await http
          .get(Uri.parse(info.checksumsUrl))
          .timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) {
        Log.w('update', 'checksums: HTTP ${resp.statusCode}');
        return false;
      }
      final hash = checksumFor(resp.body, info.assetName);
      if (hash == null) {
        Log.w('update', 'no usable checksum line for ${info.assetName}');
        return false;
      }
      expected = hash;
    } catch (e) {
      Log.w('update', 'could not fetch checksums: $e');
      return false;
    }
    // STREAMED, not readAsBytes. A Windows installer is ~100 MB and this ran
    // on the UI isolate: loading it whole spikes the heap by the size of the
    // download at the exact moment the app is also holding a document and a
    // kernel, which on a small machine is the difference between an update
    // and an out-of-memory kill. `sha256.bind` hashes the file in chunks.
    final actual = (await sha256.bind(downloaded.openRead()).first).toString();
    if (actual != expected) {
      Log.w('update', '${info.assetName} failed its checksum — not applying');
      return false;
    }
    return true;
  }

  /// The name a downloaded asset is written under.
  ///
  /// It ENDS IN THE ASSET'S OWN EXTENSION, and on Windows that matters: the
  /// old name was `.prototype-update-<millis>`, with no extension and a
  /// leading dot. An extensionless binary in %TEMP% is what a good deal of
  /// endpoint security is tuned to block, and a leading dot buys nothing on a
  /// filesystem that has no notion of it. Naming it `prototype-update.exe`
  /// makes it what it is.
  ///
  /// One name per PROCESS rather than per download: two runs cannot collide,
  /// and [_clearStaleDownloads] can recognise its own leavings without a
  /// timestamp to parse.
  static String downloadName(String assetName) {
    final dot = assetName.lastIndexOf('.');
    final ext = dot > 0 ? assetName.substring(dot) : '';
    return '$_downloadPrefix$pid$ext';
  }

  static const String _downloadPrefix = 'prototype-update-';

  /// Removes what earlier runs left behind.
  ///
  /// Every applied update used to leave its whole installer in %TEMP% — about
  /// 100 MB a time, never collected, because the process that downloaded it
  /// exits by design and nothing else knew the name. Skips anything belonging
  /// to THIS process, which is the file about to be written.
  static Future<void> _clearStaleDownloads(Directory dir) async {
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.startsWith(_downloadPrefix)) continue;
        if (name.startsWith('$_downloadPrefix$pid')) continue;
        try {
          await e.delete();
        } catch (_) {
          // Another process may still be running it. Leave it; the next
          // launch will try again.
        }
      }
    } catch (e) {
      Log.w('update', 'could not sweep old downloads: $e');
    }
  }

  static Future<File?> _download(UpdateInfo info) async {
    final client = http.Client();
    File? out;
    try {
      final req = await client
          .send(http.Request('GET', Uri.parse(info.assetUrl)))
          .timeout(const Duration(seconds: 20));
      if (req.statusCode != 200) {
        Log.w('update', 'download: HTTP ${req.statusCode}');
        return null;
      }
      // Same directory as the AppImage being replaced (see apply) so the
      // later rename is on one filesystem; anywhere writable otherwise.
      final appImage = _appImagePath;
      final dir = appImage != null ? File(appImage).parent : Directory.systemTemp;
      await _clearStaleDownloads(dir);
      out = File('${dir.path}/${downloadName(info.assetName)}');
      final sink = out.openWrite();
      try {
        // BOUNDED. The 20 s above covers the response HEADERS and nothing
        // else, so a connection that opened and then stalled left this
        // awaiting a body that never came — with the app showing
        // "downloading" for as long as the user was willing to watch it. An
        // update that cannot finish has to fail and say so.
        await req.stream.pipe(sink).timeout(_downloadWindow);
      } finally {
        await sink.close();
      }
      return out;
    } catch (e) {
      Log.w('update', 'download failed: $e');
      // A partial file is worse than none: it fails its checksum, which is
      // right, but it also sits in %TEMP% at the size it got to.
      if (out != null) {
        try {
          await out.delete();
        } catch (_) {
          // Nothing more to do about a temp file that would not go away.
        }
      }
      return null;
    } finally {
      client.close();
    }
  }

  /// How long the asset body may take. Generous — this is a ~100 MB installer
  /// on whatever connection the user has — but finite.
  static const Duration _downloadWindow = Duration(minutes: 10);

  static void _openInBrowser(String url) {
    if (url.isEmpty) return;
    try {
      if (Platform.isLinux) {
        Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      } else if (Platform.isWindows) {
        // The classic idiom: `start` is a cmd builtin, and the empty string
        // is its (often-forgotten) window-title argument — without it, a URL
        // containing quotes would be taken as the title instead of the
        // target.
        Process.start('cmd', ['/c', 'start', '', url],
            mode: ProcessStartMode.detached);
      }
    } catch (e) {
      Log.w('update', 'could not open $url: $e');
    }
  }
}
