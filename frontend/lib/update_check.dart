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
// THE SHAPE OF AN UPDATE, and why it is this shape. The first version asked
// at launch, then downloaded ~100 MB in the foreground behind a toast that
// vanished after four seconds, then closed the window without a word, then
// ran a /VERYSILENT installer for anything up to a few minutes with nothing
// on screen at all. Every step worked; the whole read as a hang followed by a
// crash ("it feels stuck then it just closes the app and idk whats
// happening"). Now, the way VS Code does it:
//
//   1. the check and the download happen in the BACKGROUND, unasked — nothing
//      is on screen while they run, so nothing can look stuck;
//   2. only a download that has passed its checksum is offered, as a banner
//      that does not block anything: Restart now, or Later;
//   3. Later means it installs when the app is next closed (installOnQuit);
//   4. Restart now says so on screen, saves, hands over to an installer that
//      SHOWS its progress, and that installer brings the app back;
//   5. the next launch says how it went (takeOutcome) — "updated to X", or
//      that it did not install and the log says why.
//
// THROTTLED AND REMEMBERED, in the same settings.json every other preference
// lives in (see sync/sync_store.dart for the pattern this copies): at most
// once every twenty hours, so a user who launches the app ten times a day
// does not spend ten unauthenticated GitHub API calls on it, and a tag the
// user dismissed with "Not now" is not asked about again until a NEWER one
// replaces it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:http/http.dart' as http;

import 'log.dart';

/// One release worth offering, already resolved to the asset this platform
/// can actually use.
class UpdateInfo {
  /// The release's tag_name — `build-<sha>` for the rolling channel, or a
  /// named `v*` tag. Shown through [label]; used raw to remember what was
  /// dismissed and what was installed.
  final String tag;

  /// Where the platform asset lives, or empty when [selfUpdatable] is false
  /// and there is nothing to download — see updateManualMessage.
  final String assetUrl;

  /// [assetUrl]'s own filename — what a line in [checksumsUrl] names it as.
  final String assetName;

  /// Where the release's SHA256SUMS file for this platform lives (see
  /// build.yml's "ONE CHECKSUM FILE PER PLATFORM" step and
  /// ci/release_attach.sh, which both the rolling and named channels go
  /// through), or empty when the release carries none. Nothing is offered
  /// that cannot be checked against this — see [UpdateCheck._verify].
  final String checksumsUrl;

  /// The release's own page: "What's new", and the whole of the offer for
  /// the channels this cannot apply itself.
  final String releaseUrl;

  /// True when this app can download and install the release itself —
  /// Windows when running from an installed copy, Linux when running as the
  /// AppImage (see [UpdateCheck._pickAsset]). False for a copy nothing can
  /// safely swap out from under itself: a directory install (the
  /// prototype-*-linux-x64.tar.gz channel), or an unzipped Windows build
  /// that Setup never installed and would install a SECOND copy beside.
  final bool selfUpdatable;

  const UpdateInfo({
    required this.tag,
    required this.assetUrl,
    required this.assetName,
    required this.checksumsUrl,
    required this.releaseUrl,
    required this.selfUpdatable,
  });

  /// What a person is shown: "Build e136f74", or a named tag as it is.
  String get label => UpdateCheck.labelFor(tag);
}

/// Where the updater is up to, for the banner (widgets/update_prompt.dart)
/// to draw. Nothing here is on screen until [ready].
enum UpdatePhase {
  /// Nothing to offer, or still looking, or still downloading in the
  /// background. Deliberately NOT a visible state: see the header.
  idle,

  /// A newer release exists that this copy cannot install itself.
  manual,

  /// Downloaded and verified; Restart now / Later.
  ready,

  /// The user chose Restart now: saving, then handing over to Setup.
  restarting,

  /// Restart now could not start the installer. The app is still running,
  /// exactly as it was.
  failed,

  /// The previous run installed an update, and this run is the result.
  updated,

  /// The previous run tried to install an update, and this run is still the
  /// old build — see [UpdateCheck.takeOutcome].
  notInstalled,
}

class UpdateStatus {
  final UpdatePhase phase;
  final UpdateInfo? info;

  /// [UpdatePhase.updated] / [UpdatePhase.notInstalled]: the build label that
  /// was being installed.
  final String? label;

  /// [UpdatePhase.restarting]: what is happening right now, so the screen
  /// never sits on one unexplained spinner.
  final RestartStep step;

  const UpdateStatus(this.phase,
      {this.info, this.label, this.step = RestartStep.saving});

  static const UpdateStatus none = UpdateStatus(UpdatePhase.idle);
}

enum RestartStep { saving, startingInstaller }

/// How the previous run's install turned out — see [UpdateCheck.takeOutcome].
enum UpdateOutcome { updated, notInstalled }

/// Where [UpdateCheck] remembers the last check time, the last tag the user
/// said not now to, and an install it handed to Setup. Same file, same
/// merge-not-own discipline as SyncStore — see sync/sync_store.dart's header
/// for why.
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
  /// and writes it back. A null value in [patch] removes that key.
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
    final section = <String, Object?>{..._section(), ...patch}
      ..removeWhere((_, v) => v == null);
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

  /// Written the moment Setup is started, read (and removed) by the next
  /// launch — which is the only thing that can know whether it worked.
  void recordPending({required String tag, required String fromBuild}) =>
      _merge({
        'pending': {
          'tag': tag,
          'from': fromBuild,
          'at': DateTime.now().toUtc().toIso8601String(),
        }
      });

  /// The install a previous run handed to Setup, or null; removed either
  /// way, so it is reported exactly once.
  ({String tag, String from, DateTime at})? takePending() {
    final p = _section()['pending'];
    if (p == null) return null;
    _merge({'pending': null});
    if (p is! Map) return null;
    final tag = p['tag'], from = p['from'], at = p['at'];
    if (tag is! String || from is! String || at is! String) return null;
    final when = DateTime.tryParse(at);
    if (when == null) return null;
    return (tag: tag, from: from, at: when);
  }
}

class UpdateCheck {
  UpdateCheck._();

  static const String _repo = 'toemeler/ipadprocad';
  static const Duration _interval = Duration(hours: 20);

  static UpdateStore? _store;

  /// What the banner draws. Starts, and mostly stays, at [UpdateStatus.none].
  static final ValueNotifier<UpdateStatus> status =
      ValueNotifier<UpdateStatus>(UpdateStatus.none);

  /// The verified installer [status] is offering, once there is one.
  static File? _ready;
  static UpdateInfo? _readyInfo;

  /// Set once Setup (or the AppImage swap) has been started, so a second
  /// close path — Windows and GTK both have two — cannot start it twice.
  static bool _handedOver = false;

  /// Called once, from AppState.init, alongside the other `attachStore`
  /// calls — see app_state.dart.
  static void attachStore(UpdateStore store) {
    _store = store;
    if (!_attached.isCompleted) _attached.complete();
  }

  /// AppState.init attaches the store AFTER an await (the secrets), and the
  /// banner starts [runInBackground] on the first frame — which can come
  /// first. Without waiting, that launch silently checked nothing and, worse,
  /// never reported how the last update went.
  static final Completer<void> _attached = Completer<void>();

  /// "Build e136f74" for the rolling channel; a named tag as it is.
  static String labelFor(String tag) =>
      tag.startsWith('build-') ? 'Build ${tag.substring(6)}' : tag;

  /// The AppImage this process was launched from, or null when it was not
  /// (a plain extracted `prototype-*-linux-x64.tar.gz` install, or a dev
  /// run). Set by the AppImage runtime itself before exec — see
  /// https://github.com/AppImage/AppImageKit — not something this app
  /// writes.
  static String? get _appImagePath => Platform.isLinux
      ? Platform.environment['APPIMAGE']
      : null;

  /// The folder this process runs from.
  static Directory get _exeDir => File(Platform.resolvedExecutable).parent;

  /// True when this Windows copy is one Setup installed — its uninstaller
  /// sits beside it. An unzipped build is not: running Setup would install a
  /// second copy somewhere else and relaunch this one, which is worse than
  /// not updating at all.
  static bool get _isInstalledWindowsCopy =>
      File('${_exeDir.path}${Platform.pathSeparator}unins000.exe')
          .existsSync();

  // ---------------------------------------------------------------------------
  // The whole background half, start to finish.
  // ---------------------------------------------------------------------------

  /// Reports how the previous run's install went, then checks for a newer
  /// release and, if this copy can install it, downloads and verifies it —
  /// all without putting anything on screen until there is something to act
  /// on. Never throws; a failed update check must never interrupt the app
  /// or read as an app error.
  static Future<void> runInBackground() async {
    if (!(Platform.isLinux || Platform.isWindows)) return;
    try {
      try {
        await _attached.future.timeout(const Duration(seconds: 60));
      } on TimeoutException {
        Log.w('update', 'settings never attached — skipping this launch');
        return;
      }
      final outcome = takeOutcome();
      if (outcome != null) {
        status.value = UpdateStatus(
            outcome.$1 == UpdateOutcome.updated
                ? UpdatePhase.updated
                : UpdatePhase.notInstalled,
            label: outcome.$2);
      }

      final info = await checkIfDue();
      if (info == null) return;

      if (!info.selfUpdatable) {
        _show(UpdateStatus(UpdatePhase.manual, info: info));
        return;
      }

      final file = await _download(info);
      if (file == null) return; // logged; the next check tries again
      _ready = file;
      _readyInfo = info;
      _show(UpdateStatus(UpdatePhase.ready, info: info));
    } catch (e, st) {
      Log.e('update', 'background update failed', e, st);
    }
  }

  /// Puts [s] on screen — unless the banner is busy reporting the last
  /// update, which the person has not dismissed yet. That report is short
  /// (see update_prompt.dart) and [showPendingOffer] brings this back after.
  static void _show(UpdateStatus s) {
    final cur = status.value.phase;
    if (cur == UpdatePhase.updated || cur == UpdatePhase.notInstalled) {
      _deferred = s;
      return;
    }
    status.value = s;
  }

  static UpdateStatus? _deferred;

  /// Called by the banner when an outcome report is dismissed.
  static void showPendingOffer() {
    status.value = _deferred ?? UpdateStatus.none;
    _deferred = null;
  }

  /// The previous run's install, if it handed one to Setup: whether this run
  /// is the build it was installing, and that build's label. Read once.
  ///
  /// "Updated" is "this is no longer the build that started the install"
  /// rather than "this is exactly the tag": a named `v*` tag cannot be
  /// compared with Log.build (see the header), and a build that is neither
  /// is still not the one that asked.
  static (UpdateOutcome, String)? takeOutcome() {
    final p = _store?.takePending();
    if (p == null) return null;
    // A marker from weeks ago is not news about this launch.
    if (DateTime.now().toUtc().difference(p.at) > const Duration(days: 3)) {
      return null;
    }
    final outcome = outcomeFor(fromBuild: p.from, currentBuild: Log.build);
    if (outcome == UpdateOutcome.updated) {
      Log.i('update', 'now running ${p.tag} (was build ${p.from})');
    } else {
      Log.w('update',
          '${p.tag} did not install — still on build ${p.from}; Setup log follows');
      _logSetupLog();
    }
    return (outcome, labelFor(p.tag));
  }

  /// Pure and exported for testing.
  static UpdateOutcome outcomeFor(
          {required String fromBuild, required String currentBuild}) =>
      fromBuild == currentBuild
          ? UpdateOutcome.notInstalled
          : UpdateOutcome.updated;

  /// Where Setup is told to write its log: beside the app's own.
  static String get setupLogPath {
    final p = Log.path;
    // log.dart answers a placeholder, not null, when it has no file.
    final logs = p.startsWith('(') ? Directory.systemTemp : File(p).parent;
    return '${logs.path}${Platform.pathSeparator}update-install.log';
  }

  /// Copies the end of Setup's log into the app's own, which is the one a bug
  /// report carries — an install that failed must be explicable from it.
  static void _logSetupLog() {
    try {
      final f = File(setupLogPath);
      if (!f.existsSync()) {
        Log.w('update', 'no Setup log at ${f.path}');
        return;
      }
      final lines = const LineSplitter().convert(f.readAsStringSync());
      for (final l in lines.skip(lines.length > 40 ? lines.length - 40 : 0)) {
        Log.w('update', 'setup: $l');
      }
    } catch (e) {
      Log.w('update', 'could not read the Setup log: $e');
    }
  }

  /// Null when there is nothing to offer: not due yet, no newer release,
  /// the user already dismissed this exact tag, or the check itself failed
  /// (network errors are swallowed here — see [runInBackground]).
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
        Log.i('update', 'newer release available: $tag '
            '(${info.selfUpdatable ? 'downloading in the background' : 'manual'})');
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

    UpdateInfo manual() => UpdateInfo(
        tag: tag,
        assetUrl: '',
        assetName: '',
        checksumsUrl: '',
        releaseUrl: releaseUrl,
        selfUpdatable: false);

    if (Platform.isWindows) {
      final asset = findEndingWith('-windows-setup.exe');
      if (asset == null) return null; // no matching asset on this release
      if (!_isInstalledWindowsCopy) return manual();
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
      return manual();
    }

    return null;
  }

  /// Remembers that the user said not now to this tag, so it is not asked
  /// about again until a newer one replaces it.
  static void skip(String tag) {
    _store?.recordSkip(tag);
    status.value = UpdateStatus.none;
  }

  /// "Later": the banner goes, the download stays, and [installOnQuit]
  /// installs it when the app is next closed.
  static void later() {
    Log.i('update', '${_readyInfo?.tag} deferred — installs on quit');
    status.value = UpdateStatus.none;
  }

  /// Dismisses whatever the banner is showing.
  static void dismiss() => status.value = UpdateStatus.none;

  // ---------------------------------------------------------------------------
  // The hand-over.
  // ---------------------------------------------------------------------------

  /// "Restart now": saves via [beforeInstall], starts the installer, and
  /// returns true when the CALLER must now exit the process — IMMEDIATELY,
  /// everything slow has already been done, and Setup is waiting on this PID.
  ///
  /// [beforeInstall] runs BEFORE anything is launched, and that order is the
  /// whole of this method's contract: Setup closes whatever still holds its
  /// files, and a save racing that close is how an update used to take the
  /// window away mid-write.
  ///
  /// False means nothing was started and the app is exactly as it was;
  /// [status] says so.
  static Future<bool> restartNow(
      {Future<void> Function()? beforeInstall}) async {
    final file = _ready, info = _readyInfo;
    if (file == null || info == null || _handedOver) return false;

    status.value = UpdateStatus(UpdatePhase.restarting, info: info);
    if (beforeInstall != null) {
      try {
        await beforeInstall().timeout(_flushWindow);
      } catch (e) {
        // A save that failed or hung must not strand the user on a build they
        // have already agreed to replace. Say so and go on: the document is no
        // worse off than if they had closed the window.
        Log.w('update', 'pre-install flush did not finish: $e');
      }
    }
    status.value = UpdateStatus(UpdatePhase.restarting,
        info: info, step: RestartStep.startingInstaller);

    if (await _handOver(file, info, relaunch: true)) return true;
    status.value = UpdateStatus(UpdatePhase.failed, info: info);
    return false;
  }

  /// "Later", followed through: called from the window-close handshake (see
  /// main.dart), after the documents are saved. Starts the installer with
  /// nothing on screen and does not bring the app back — the person closed
  /// it. Quick by construction: it only starts a process.
  static Future<void> installOnQuit() async {
    final file = _ready, info = _readyInfo;
    if (file == null || info == null || _handedOver) return;
    Log.i('update', 'installing ${info.tag} on quit');
    await _handOver(file, info, relaunch: false);
  }

  /// How long [restartNow] waits for the caller's save before going ahead.
  static const Duration _flushWindow = Duration(seconds: 30);

  static Future<bool> _handOver(File file, UpdateInfo info,
      {required bool relaunch}) async {
    try {
      if (!file.existsSync()) {
        Log.w('update', 'the verified download is gone: ${file.path}');
        return false;
      }
      if (Platform.isWindows) {
        final args = windowsSetupArgs(
          waitForPid: pid,
          logPath: setupLogPath,
          installDir: _exeDir.path,
          relaunchExe: relaunch ? Platform.resolvedExecutable : null,
        );
        // Setup itself, detached: it waits for this PID (see the iss file's
        // InitializeSetup), so there is no script in between to go wrong.
        await Process.start(file.path, args, mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        final target = _appImagePath;
        if (target == null) return false; // should not happen — see _pickAsset
        await Process.run('chmod', ['+x', file.path]);
        // Same filesystem as target (see _download) makes this an atomic
        // POSIX rename — never a half-written AppImage at `target`, whatever
        // happens to the process a moment later.
        await file.rename(target);
        if (relaunch) {
          await Process.start(target, const [], mode: ProcessStartMode.detached);
        }
      } else {
        return false;
      }
      _handedOver = true;
      _store?.recordPending(tag: info.tag, fromBuild: Log.build);
      Log.i('update', 'handed ${info.tag} to the installer '
          '(${relaunch ? 'relaunching' : 'on quit'})');
      // The process is about to go. INFO lines are buffered (log.dart), and an
      // exit drops the buffer — which is how the last update left no trace.
      Log.flush();
      return true;
    } catch (e) {
      Log.w('update', 'could not start the installer: $e');
      return false;
    }
  }

  /// Setup's command line for an update.
  ///
  /// /SILENT, not /VERYSILENT, when the app is coming back: /SILENT shows the
  /// installer's own progress card (prototype.iss skins it in update mode),
  /// which is the difference between "the app closed and nothing happened for
  /// a minute" and an update you can watch. On quit there is nobody watching
  /// for it, so /VERYSILENT.
  ///
  /// /DIR is the folder THIS copy runs from, so it is this copy that is
  /// updated — never a second one at Setup's default location.
  ///
  /// /LOG is what makes a failed install explicable afterwards — see
  /// [takeOutcome], which copies it into the app's own log.
  ///
  /// Pure and exported for testing.
  static List<String> windowsSetupArgs({
    required int waitForPid,
    required String logPath,
    required String installDir,
    String? relaunchExe,
  }) =>
      [
        relaunchExe != null ? '/SILENT' : '/VERYSILENT',
        '/SUPPRESSMSGBOXES',
        // About REBOOTING, not about the app.
        '/NORESTART',
        '/UPDATE=1',
        '/WAITPID=$waitForPid',
        '/LOG=$logPath',
        '/DIR=$installDir',
        if (relaunchExe != null) '/RELAUNCH=$relaunchExe',
      ];

  // ---------------------------------------------------------------------------
  // Download and verification.
  // ---------------------------------------------------------------------------

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

  /// The release's expected sha256 for [info]'s asset, or null when it cannot
  /// be had — no checksums file, a network failure, no line naming the asset.
  /// Null means NOT OFFERED: a download nothing can vouch for is never run.
  static Future<String?> _expectedHash(UpdateInfo info) async {
    if (info.checksumsUrl.isEmpty || info.assetName.isEmpty) {
      Log.w('update', 'no checksums published for ${info.tag} — not offering it');
      return null;
    }
    try {
      final resp = await http
          .get(Uri.parse(info.checksumsUrl))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        Log.w('update', 'checksums: HTTP ${resp.statusCode}');
        return null;
      }
      final hash = checksumFor(resp.body, info.assetName);
      if (hash == null) {
        Log.w('update', 'no usable checksum line for ${info.assetName}');
      }
      return hash;
    } catch (e) {
      Log.w('update', 'could not fetch checksums: $e');
      return null;
    }
  }

  /// STREAMED, not readAsBytes: a Windows installer is ~100 MB and this runs
  /// on the UI isolate while the app is holding a document and a kernel.
  static Future<bool> _verify(File f, String expected) async {
    final actual = (await sha256.bind(f.openRead()).first).toString();
    if (actual != expected) {
      Log.w('update', '${f.path} failed its checksum — not offering it');
      return false;
    }
    return true;
  }

  /// The name a downloaded asset is kept under once verified, and — with
  /// [partSuffix] — while it is still arriving.
  ///
  /// ONE NAME PER RELEASE, so a download cut short by a closed laptop lid
  /// resumes where it stopped on the next launch instead of starting again,
  /// and a download finished last time is simply offered again. It ends in
  /// the asset's own extension: an extensionless binary in %TEMP% is what a
  /// good deal of endpoint security is tuned to block.
  ///
  /// Pure and exported for testing.
  static String downloadName(String tag, String assetName) {
    final dot = assetName.lastIndexOf('.');
    final ext = dot > 0 ? assetName.substring(dot) : '';
    final safeTag = tag.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return '$_downloadPrefix$safeTag$ext';
  }

  static const String _downloadPrefix = 'prototype-update-';
  static const String partSuffix = '.part';

  /// Removes what earlier runs left behind for any OTHER release — a stale
  /// installer is ~100 MB that nothing else would ever collect.
  static Future<void> _clearStaleDownloads(Directory dir, String keep) async {
    try {
      await for (final e in dir.list(followLinks: false)) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.startsWith(_downloadPrefix)) continue;
        if (name.startsWith(keep)) continue;
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

  /// Downloads [info]'s asset and checks it, resuming a partial download and
  /// retrying a dropped one. Returns the verified file, or null (logged).
  static Future<File?> _download(UpdateInfo info) async {
    final expected = await _expectedHash(info);
    if (expected == null) return null;

    // Same directory as the AppImage being replaced (see _handOver) so the
    // later rename is on one filesystem; anywhere writable otherwise.
    final appImage = _appImagePath;
    final dir = appImage != null ? File(appImage).parent : Directory.systemTemp;
    final name = downloadName(info.tag, info.assetName);
    await _clearStaleDownloads(dir, name);
    final done = File('${dir.path}${Platform.pathSeparator}$name');
    final part = File('${done.path}$partSuffix');

    // Finished on an earlier run, and still intact.
    if (done.existsSync()) {
      if (await _verify(done, expected)) {
        Log.i('update', '${info.tag} already downloaded');
        return done;
      }
      await _deleteQuietly(done);
    }

    for (var attempt = 1; attempt <= 3; attempt++) {
      final ok = await _fetchInto(part, info.assetUrl);
      if (ok) break;
      if (attempt == 3) {
        final kept = part.existsSync() ? part.lengthSync() : 0;
        Log.w('update', 'download gave up after $attempt attempts; '
            'keeping $kept bytes to resume next time');
        return null;
      }
      await Future<void>.delayed(Duration(seconds: 5 * attempt));
    }

    if (!await _verify(part, expected)) {
      // Corrupt or tampered: resuming would only append to it.
      await _deleteQuietly(part);
      return null;
    }
    await part.rename(done.path);
    Log.i('update', '${info.tag} downloaded and verified');
    return done;
  }

  /// One attempt at bringing [part] up to the whole asset, appending to what
  /// is already there via an HTTP Range request. True when complete.
  static Future<bool> _fetchInto(File part, String url) async {
    final client = http.Client();
    try {
      final have = part.existsSync() ? part.lengthSync() : 0;
      final req = http.Request('GET', Uri.parse(url));
      req.headers['User-Agent'] = 'prototype-desktop-updater';
      if (have > 0) req.headers['Range'] = 'bytes=$have-';
      final resp =
          await client.send(req).timeout(const Duration(seconds: 30));

      final IOSink sink;
      if (resp.statusCode == 206 && have > 0) {
        sink = part.openWrite(mode: FileMode.append);
      } else if (resp.statusCode == 200) {
        // The server ignored the Range, or there was nothing to resume.
        sink = part.openWrite();
      } else if (resp.statusCode == 416 && have > 0) {
        // Nothing left to send: the part file is already the whole thing.
        return true;
      } else {
        Log.w('update', 'download: HTTP ${resp.statusCode}');
        return false;
      }
      if (have > 0) {
        Log.i('update', 'resuming download at $have bytes (HTTP ${resp.statusCode})');
      }
      try {
        // An IDLE timeout, not a total one. A total one either cuts off a
        // slow-but-moving connection or lets a stalled one sit for as long
        // as it is; no data for a minute is a stall whatever the line speed.
        await resp.stream
            .timeout(const Duration(seconds: 60))
            .pipe(sink);
      } finally {
        await sink.close();
      }
      // A connection that closes cleanly part-way is not an error to the
      // stream, only to the byte count. Short means retry — and resume.
      final len = resp.contentLength;
      if (len != null) {
        final want = (resp.statusCode == 206 ? have : 0) + len;
        final got = part.lengthSync();
        if (got < want) {
          Log.w('update', 'download ended early: $got of $want bytes');
          return false;
        }
      }
      return true;
    } catch (e) {
      Log.w('update', 'download interrupted: $e');
      return false;
    } finally {
      client.close();
    }
  }

  static Future<void> _deleteQuietly(File f) async {
    try {
      if (f.existsSync()) await f.delete();
    } catch (_) {
      // Nothing more to do about a temp file that would not go away.
    }
  }

  /// Opens [url] in the default browser — "What's new", and the whole of the
  /// offer for a copy that cannot update itself.
  static void openInBrowser(String url) {
    if (url.isEmpty) return;
    try {
      if (Platform.isLinux) {
        Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      } else if (Platform.isWindows) {
        // `start` is a cmd builtin, and the empty string is its
        // (often-forgotten) window-title argument — without it, a URL
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
