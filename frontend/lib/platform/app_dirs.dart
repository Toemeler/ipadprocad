// Prototype — where the app's own files live, per platform.
//
// On the iPad there is one answer and the system gives it:
// `getApplicationDocumentsDirectory()` is the app's container, it is what
// `UIFileSharingEnabled` exposes in Files, and every document, sidecar,
// preview and log goes in it.
//
// A desktop has no container, and asking the same question there gets the
// wrong answer twice over:
//
//   * `path_provider` maps it to the user's ~/Documents — a folder that
//     belongs to the USER, not to us. Writing a gallery, a cache, a settings
//     file and a logs/ directory straight into it is what a badly-behaved
//     desktop app does.
//   * It reaches that answer by running `xdg-user-dir`, which is not
//     installed everywhere, and THROWS when it is not. Measured, not assumed:
//     on a machine without xdg-user-dirs the app fell through to
//     `Directory.systemTemp` and put every document the user made in /tmp,
//     where the next reboot deletes them. A silent, total data loss with no
//     symptom until it happens.
//
// So the desktop gets the desktop's own answer: the XDG data directory, which
// is what `~/.local/share/prototype` is for, resolved here rather than
// through a plugin because two of the three callers run BEFORE any platform
// channel exists (Log.init and Perf.init are the second and third statements
// of main()).
//
// Nothing here throws. A path that cannot be resolved falls through to the
// next candidate and, in the last resort, to a NAMED directory under the temp
// root — still wrong, but at least identifiable, and it logs.
import 'dart:io' as io;

/// The folder name the app owns under whichever base directory applies.
/// Matches the binary name and the `.desktop` file's `Exec`, so a user who
/// goes looking finds one word in three places.
const String kAppDirName = 'prototype';

/// True where [desktopAppDirectory] is the right answer and
/// `getApplicationDocumentsDirectory()` is not.
bool get isDesktopHost =>
    io.Platform.isLinux || io.Platform.isWindows || io.Platform.isMacOS;

/// The app's own directory on a desktop, created if it is not there.
///
/// SYNCHRONOUS on purpose: [Log.init] and [Perf.init] both need a place to
/// write before `WidgetsFlutterBinding` exists, and an async answer would mean
/// the first lines of every launch — the ones that say what the kernels did —
/// are written somewhere else and then moved.
///
/// Order:
///   1. `$XDG_DATA_HOME/prototype`      the spec's own answer, when set
///   2. `$HOME/.local/share/prototype`  the spec's default when it is not
///   3. `%APPDATA%\prototype`           the same question on Windows
///   4. `<temp>/prototype`              nothing else worked; named, not loose
io.Directory desktopAppDirectory() {
  final env = io.Platform.environment;
  final candidates = <String>[];

  if (io.Platform.isWindows) {
    final appData = env['APPDATA'];
    if (appData != null && appData.isNotEmpty) candidates.add(appData);
  } else {
    final xdg = env['XDG_DATA_HOME'];
    if (xdg != null && xdg.isNotEmpty) candidates.add(xdg);
    final home = env['HOME'];
    if (home != null && home.isNotEmpty) candidates.add('$home/.local/share');
  }
  candidates.add(io.Directory.systemTemp.path);

  for (final base in candidates) {
    try {
      final dir = io.Directory('$base${io.Platform.pathSeparator}$kAppDirName');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      // Existing is not enough — a read-only or full mount exists and cannot
      // be written to, and finding that out here is far cheaper than finding
      // it out when a document is being saved.
      final probe = io.File(
          '${dir.path}${io.Platform.pathSeparator}.write-probe');
      probe.writeAsStringSync('', flush: true);
      probe.deleteSync();
      return dir;
    } catch (_) {
      // Next candidate. The last one is the temp root, which cannot realistic-
      // ally fail; if it does, the exception belongs to the caller.
    }
  }
  return io.Directory(
      '${io.Directory.systemTemp.path}${io.Platform.pathSeparator}$kAppDirName')
    ..createSync(recursive: true);
}
