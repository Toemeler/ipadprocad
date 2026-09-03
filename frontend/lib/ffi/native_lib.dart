// Prototype — WHERE THE NATIVE SYMBOLS COME FROM, per platform.
//
// The four FFI facades in this directory (qcad, slvs, occt, cycles) all begin
// the same way: get a [DynamicLibrary] and look their symbols up in it. On
// iOS that library is the app binary itself — the CI links libqcadcapi.a,
// libslvs.a and libocct_capi.a straight into Runner and keeps the C symbols
// in the export trie, so `DynamicLibrary.process()` finds every one of them.
//
// A DESKTOP build cannot do that. A Flutter Linux/Windows app is a small
// runner executable plus a bundle of shared libraries, and there is no link
// step we own that could pull a static archive into it. The kernels ship as
// ONE shared library beside the runner instead (`libprototype_native.so` /
// `prototype_native.dll`, built by tools/desktop/build_native.sh), and this
// file is the one place that knows how to find it.
//
// WHY ONE FILE RATHER THAN FOUR
// -----------------------------
// Each facade probing on its own would dlopen the same library up to four
// times, and — worse — would report four different diagnoses when it is
// missing. The failure that actually happens on a desktop machine is "the
// bundle was assembled without the native library", and it has to read the
// same way in the log whichever facade noticed first. So the handle is opened
// once, cached, and the search is narrated once (see [NativeLib.report]).
//
// It NEVER throws. Every caller already treats "no symbols" as a supported
// state — the QCAD facade falls back to its Dart engine, the solver to the
// Dart solver, OCCT to no-3D-kernel, Cycles to no-path-tracer — so a desktop
// run with no kernels must degrade exactly like `flutter run` on a host has
// always done, not crash at start-up.
import 'dart:ffi';
import 'dart:io' as io;

import '../log.dart';

/// The handle every FFI facade in this directory starts from.
class NativeLib {
  NativeLib._();

  /// The kernels: QCAD's C-API, the libslvs shim and the OCCT shim, in one
  /// library. Built by tools/desktop/build_native.sh.
  static const String kernels = 'prototype_native';

  /// Cycles — a SECOND library on purpose. It is an order of magnitude bigger
  /// than the three kernels together, it is optional (a build without it is a
  /// build without path tracing, which the app already handles), and on Linux
  /// it drags in a GPU runtime. Keeping it out of [kernels] is what lets a
  /// package ship without it and still be the same app.
  static const String cycles = 'prototype_cycles';

  static final Map<String, DynamicLibrary?> _cache = <String, DynamicLibrary?>{};
  static final List<String> _report = <String>[];

  /// What the search did, for the log and the bug bundle. One line per
  /// candidate tried, in order.
  static List<String> get report => List.unmodifiable(_report);

  /// True where the symbols are linked into the app binary itself — iOS and
  /// macOS. There is nothing to open there and nothing that can be missing.
  static bool get linkedIntoProcess => io.Platform.isIOS || io.Platform.isMacOS;

  /// The library named [name], or null when this build has none.
  ///
  /// On iOS/macOS this is always `DynamicLibrary.process()` and [name] is
  /// ignored: the symbols are in the binary. On Linux and Windows the file is
  /// looked for beside the runner, then on the loader's own search path.
  ///
  /// [optional] says what a miss MEANS, and it changes only the log level.
  /// A missing kernel library is a warning — the app still runs, on its Dart
  /// fallbacks, but somebody assembled a bundle wrong. A missing Cycles is
  /// the normal state of every build that does not ship a path tracer, and a
  /// warning for it would train the reader to skim the warnings.
  ///
  /// Cached — including the null — so a miss costs one search per process
  /// rather than one per facade.
  static DynamicLibrary? open(String name, {bool optional = false}) {
    if (_cache.containsKey(name)) return _cache[name];
    final lib = _open(name, optional);
    _cache[name] = lib;
    return lib;
  }

  static DynamicLibrary? _open(String name, bool optional) {
    if (linkedIntoProcess) {
      try {
        return DynamicLibrary.process();
      } catch (e) {
        _note('$name: DynamicLibrary.process() failed: $e');
        return null;
      }
    }
    for (final path in candidates(name)) {
      try {
        final lib = DynamicLibrary.open(path);
        _note('$name: opened $path');
        Log.i('ffi', 'native library "$name" -> $path');
        return lib;
      } catch (e) {
        _note('$name: $path — ${_short(e)}');
      }
    }
    // Last resort: the symbols may have been linked into the runner after all
    // (a custom build, or a test host that loaded them itself). Cheap, and it
    // is the difference between "no kernels" and "kernels the search did not
    // know the name of".
    try {
      final proc = DynamicLibrary.process();
      // Probing a symbol is what tells a loaded-into-process build apart from
      // an empty one: process() itself succeeds everywhere.
      proc.lookup<Void>(_probeSymbol(name));
      _note('$name: found in the running process');
      return proc;
    } catch (_) {
      _note('$name: not in the running process either');
    }
    final searched =
        'native library "$name" not found — searched:\n  ${_report.join('\n  ')}';
    if (optional) {
      Log.i('ffi', searched);
    } else {
      Log.w('ffi', searched);
    }
    return null;
  }

  /// One exported symbol per library, used only to tell "already linked in"
  /// apart from "not here". Both are cheap C functions with no side effects.
  static String _probeSymbol(String name) =>
      name == cycles ? 'cy_available' : 'qcad_version';

  /// Every place a desktop build may keep its native library, most specific
  /// first. Public so the packaging script and its test can assert that what
  /// they install is on this list.
  static List<String> candidates(String name) {
    final file = fileName(name);
    final out = <String>[];

    // 1. An explicit override. This is what a developer running `flutter run`
    //    against a build tree in another directory sets, and what the CI uses
    //    before the bundle has been assembled.
    final override = io.Platform.environment['PROTOTYPE_NATIVE_DIR'];
    if (override != null && override.isNotEmpty) {
      out.add('$override${io.Platform.pathSeparator}$file');
    }

    // 2. Beside the runner, in the layout `flutter build linux` produces:
    //    bundle/prototype and bundle/lib/*.so. This is the shipping case.
    try {
      final exe = io.File(io.Platform.resolvedExecutable).parent;
      out.add('${exe.path}/lib/$file');
      out.add('${exe.path}/$file');
      // `flutter run` puts the runner in build/linux/<arch>/debug/bundle, and
      // a developer's kernels in build/native. One level up covers that
      // without a second environment variable.
      out.add('${exe.parent.path}/lib/$file');
    } catch (e) {
      _note('$name: could not resolve the executable path: $e');
    }

    // 3. The loader's own search path (LD_LIBRARY_PATH, /usr/lib, the DLL
    //    search order on Windows). A distribution package installs here.
    out.add(file);
    return out;
  }

  /// The platform's file name for the library called [name].
  static String fileName(String name) {
    if (io.Platform.isWindows) return '$name.dll';
    if (io.Platform.isMacOS || io.Platform.isIOS) return 'lib$name.dylib';
    return 'lib$name.so';
  }

  static void _note(String line) {
    // Bounded: a pathological environment must not grow this without limit.
    if (_report.length < 32) _report.add(line);
  }

  /// dlopen errors arrive as a paragraph with the whole path in it; the log
  /// already has the path.
  static String _short(Object e) {
    final s = e.toString();
    final cut = s.indexOf('(');
    final head = cut > 0 ? s.substring(0, cut) : s;
    return head.length > 120 ? '${head.substring(0, 120)}…' : head.trim();
  }

  /// Tests only: forget what was found, so a case can set the environment and
  /// search again.
  static void resetForTest() {
    _cache.clear();
    _report.clear();
  }
}
