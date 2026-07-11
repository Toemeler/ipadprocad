// iPadProCAD — crash-safe file logger for on-device debugging.
//
// Every line is appended SYNCHRONOUSLY with flush:true so the last entry
// survives even a hard native crash: the final line in the file tells you
// which step the app died in.
//
// Log location (visible in the iPad Files app via UIFileSharingEnabled +
// LSSupportsOpeningDocumentsInPlace, see CI Info.plist patch):
//   On My iPad > ipadprocad > logs > ipadprocad_log.txt
//
// The Documents path is derived WITHOUT platform channels
// ($HOME/Documents inside the iOS sandbox), so logging works from the very
// first line of main(), before WidgetsFlutterBinding / path_provider exist.
import 'dart:io';

class Log {
  static File? _file;
  static bool _broken = false;
  static final List<String> _buffer = []; // pre-init lines
  static const _maxBytes = 2 * 1024 * 1024; // rotate at 2 MB

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
      // rotate: keep exactly one previous log
      if (f.existsSync() && f.lengthSync() > _maxBytes) {
        final old = File('${dir.path}/ipadprocad_log_prev.txt');
        if (old.existsSync()) old.deleteSync();
        f.renameSync(old.path);
      }
      _file = File('${dir.path}/ipadprocad_log.txt');
      _file!.writeAsStringSync(
          '\n================ APP LAUNCH ${DateTime.now().toIso8601String()} '
          '================\n',
          mode: FileMode.append,
          flush: true);
      i('log', 'logger ready, file=${_file!.path}');
      i('log', 'os=${Platform.operatingSystem} '
          'ver=${Platform.operatingSystemVersion} '
          'dart=${Platform.version} locale=${Platform.localeName}');
      for (final l in _buffer) {
        _file!.writeAsStringSync('$l\n', mode: FileMode.append, flush: true);
      }
      _buffer.clear();
    } catch (e) {
      _broken = true;
      // ignore: avoid_print
      print('LOG INIT FAILED: $e');
    }
  }

  static String get path => _file?.path ?? '(log unavailable)';

  static void _write(String level, String tag, String msg) {
    final line =
        '${DateTime.now().toIso8601String()} [$level] $tag: $msg';
    // ignore: avoid_print
    print(line); // also visible via --console-pty / Console.app
    if (_broken) return;
    final f = _file;
    if (f == null) {
      _buffer.add(line);
      if (_buffer.length > 500) _buffer.removeAt(0);
      return;
    }
    try {
      f.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {
      _broken = true;
    }
  }

  static void i(String tag, String msg) => _write('INFO ', tag, msg);
  static void w(String tag, String msg) => _write('WARN ', tag, msg);
  static void e(String tag, String msg, [Object? err, StackTrace? st]) {
    _write('ERROR', tag,
        '$msg${err != null ? ' | $err' : ''}${st != null ? '\n$st' : ''}');
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
}
