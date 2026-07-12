// iPadProCAD — crash-safe file logger for on-device debugging.
//
// LOG LOCATION (iPad Files app):
//   On My iPad > ipadprocad > logs > ipadprocad_log.txt
// Visible because the M5 CI job patches UIFileSharingEnabled +
// LSSupportsOpeningDocumentsInPlace into Info.plist. The previous session is
// kept as ipadprocad_log_prev.txt.
//
// WRITE POLICY. Lines are BUFFERED and flushed in batches. The grip drag solves
// (and therefore logs) at ~60 Hz, and an fsync per line would stall the very
// interaction we are trying to diagnose — the log would change the behaviour it
// is meant to record. So:
//   * DEBUG/INFO  -> buffered, flushed every 120 lines / 400 ms / on lifecycle
//   * WARN/ERROR  -> flushed IMMEDIATELY and synchronously, so the last line
//                    before a hard native crash still reaches the disk.
//
// The Documents path is derived WITHOUT platform channels ($HOME/Documents
// inside the iOS sandbox), so logging works from the very first line of main(),
// before WidgetsFlutterBinding / path_provider exist.
import 'dart:async';
import 'dart:io';

class Log {
  static File? _file;
  static bool _broken = false;
  static final StringBuffer _pending = StringBuffer();
  static int _pendingLines = 0;
  static final List<String> _preInit = [];
  static Timer? _flusher;
  static final Stopwatch _clock = Stopwatch()..start();
  static final Map<String, int> _throttle = {};

  static const _maxBytes = 8 * 1024 * 1024; // rotate at 8 MB
  static const _flushLines = 120;

  /// Commit the build came from; injected via --dart-define=GIT_SHA=...
  static const build =
      String.fromEnvironment('GIT_SHA', defaultValue: 'local');

  /// Best-effort synchronous init. Never throws.
  static void init() {
    try {
      String? docs;
      if (Platform.isIOS || Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) docs = '$home/Documents';
      }
      docs ??= Directory.systemTemp.path;
      final dir = Directory('$docs/logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final f = File('${dir.path}/ipadprocad_log.txt');
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        final old = File('${dir.path}/ipadprocad_log_prev.txt');
        if (old.existsSync()) old.deleteSync();
        f.renameSync(old.path);
      }
      _file = File('${dir.path}/ipadprocad_log.txt');
      _file!.writeAsStringSync(
          '\n================ APP LAUNCH ${DateTime.now().toIso8601String()}'
          ' build=$build ================\n',
          mode: FileMode.append,
          flush: true);
      i('log', 'logger ready, file=${_file!.path}');
      i('log', 'os=${Platform.operatingSystem} '
          'ver=${Platform.operatingSystemVersion} '
          'dart=${Platform.version} locale=${Platform.localeName}');
      for (final l in _preInit) {
        _pending.writeln(l);
        _pendingLines++;
      }
      _preInit.clear();
      flush();
      // Backstop: nothing sits in the buffer for longer than 400 ms.
      _flusher = Timer.periodic(const Duration(milliseconds: 400), (_) => flush());
    } catch (e) {
      _broken = true;
      // ignore: avoid_print
      print('LOG INIT FAILED: $e');
    }
  }

  static String get path => _file?.path ?? '(log unavailable)';

  /// True at most once per [ms] for [key] — gate for per-frame logging so the
  /// 60 Hz drag loop cannot drown the interesting lines.
  static bool every(String key, int ms) {
    final now = _clock.elapsedMilliseconds;
    final last = _throttle[key];
    if (last != null && now - last < ms) return false;
    _throttle[key] = now;
    return true;
  }

  /// Forget a throttle key, so the next call logs again (use at drag start).
  static void resetThrottle(String key) => _throttle.remove(key);

  static void flush() {
    if (_broken || _pendingLines == 0) return;
    final f = _file;
    if (f == null) return;
    try {
      f.writeAsStringSync(_pending.toString(),
          mode: FileMode.append, flush: true);
      _pending.clear();
      _pendingLines = 0;
    } catch (_) {
      _broken = true;
    }
  }

  static void _write(String level, String tag, String msg,
      {bool urgent = false}) {
    final line = '${DateTime.now().toIso8601String()} [$level] $tag: $msg';
    // ignore: avoid_print
    print(line); // also visible via Console.app / --console-pty
    if (_broken) return;
    if (_file == null) {
      _preInit.add(line);
      if (_preInit.length > 800) _preInit.removeAt(0);
      return;
    }
    _pending.writeln(line);
    _pendingLines++;
    if (urgent || _pendingLines >= _flushLines) flush();
  }

  static void d(String tag, String msg) => _write('DEBUG', tag, msg);
  static void i(String tag, String msg) => _write('INFO ', tag, msg);
  static void w(String tag, String msg) =>
      _write('WARN ', tag, msg, urgent: true);
  static void e(String tag, String msg, [Object? err, StackTrace? st]) {
    _write('ERROR', tag,
        '$msg${err != null ? ' | $err' : ''}${st != null ? '\n$st' : ''}',
        urgent: true);
  }

  /// A multi-line block (sketch dumps). Written as one unit, flushed at once.
  static void block(String tag, String title, List<String> lines) {
    _write('DEBUG', tag, '--- $title ---');
    for (final l in lines) {
      _write('DEBUG', tag, '    $l');
    }
    flush();
  }

  /// Runs [fn] with breadcrumbs before/after; rethrows after logging.
  static T step<T>(String tag, String what, T Function() fn) {
    i(tag, '>> $what');
    try {
      final r = fn();
      i(tag, '<< $what OK');
      return r;
    } catch (e2, st) {
      Log.e(tag, 'FAILED in $what', e2, st);
      rethrow;
    }
  }

  static Future<T> stepAsync<T>(
      String tag, String what, Future<T> Function() fn) async {
    i(tag, '>> $what');
    try {
      final r = await fn();
      i(tag, '<< $what OK');
      return r;
    } catch (e2, st) {
      Log.e(tag, 'FAILED in $what', e2, st);
      rethrow;
    }
  }

  static void dispose() {
    _flusher?.cancel();
    flush();
  }
}
