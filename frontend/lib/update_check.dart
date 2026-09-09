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
  /// Returns true when the CALLER must now exit the process — Setup and the
  /// replaced AppImage both need this one's own executable to let go of its
  /// files, on Windows because a locked exe cannot be overwritten and on
  /// Linux because the just-launched new copy and this one must not both be
  /// running. Windows relies on Inno Setup's own CloseApplications /
  /// RestartApplications (see windows/installer/prototype.iss) as a
  /// backstop if the caller's exit is not fast enough; Linux has no such
  /// backstop, which is exactly why the caller is told to exit rather than
  /// left to find out.
  ///
  /// False means nothing was applied — either it opened the release page
  /// instead (the non-self-updatable Linux channel) or the download/launch
  /// failed, logged, with the app left running exactly as it was.
  static Future<bool> apply(UpdateInfo info) async {
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

    if (Platform.isWindows) {
      try {
        // Silent: the user already answered "update now" inside the app —
        // Inno's own wizard asking again would be a second confirmation for
        // one already-given answer. /NORESTART because CloseApplications
        // does not need a reboot to replace a file only this app has open.
        await Process.start(
          downloaded.path,
          const ['/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
          mode: ProcessStartMode.detached,
        );
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
    final actual = sha256.convert(await downloaded.readAsBytes()).toString();
    if (actual != expected) {
      Log.w('update', '${info.assetName} failed its checksum — not applying');
      return false;
    }
    return true;
  }

  static Future<File?> _download(UpdateInfo info) async {
    final client = http.Client();
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
      final out = File('${dir.path}/.prototype-update-${DateTime.now().millisecondsSinceEpoch}');
      final sink = out.openWrite();
      await req.stream.pipe(sink);
      await sink.close();
      return out;
    } catch (e) {
      Log.w('update', 'download failed: $e');
      return null;
    } finally {
      client.close();
    }
  }

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
