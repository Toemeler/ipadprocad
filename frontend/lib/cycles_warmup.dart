// M320 — compiling the renderer's kernels at launch instead of at first use.
//
// ---------------------------------------------------------------------------
// WHY THIS EXISTS
// ---------------------------------------------------------------------------
//
// Cycles' Metal backend ships no compiled kernels. It builds them from source,
// on the device, the first time it renders — and on an iPad that is tens of
// seconds to a couple of minutes. Afterwards they sit in a binary archive in
// Library/Caches and a later launch costs nothing.
//
// Left alone, all of that lands on whoever first switches to rendered mode: a
// spinner, no picture, and no way to tell a slow render from a hung app. So it
// happens HERE, at startup, on its own isolate, while the person is still
// opening a document — and by the time rendered mode is asked for it is
// usually already done.
//
// ---------------------------------------------------------------------------
// AND WHY IT REPORTS STEPS
// ---------------------------------------------------------------------------
//
// If it is NOT done, rendered mode has to say so, and "please wait" is not
// enough for a two-minute wait. Cycles knows exactly what it is doing —
// "Loading render kernels (may take a few minutes the first time)", then the
// sample count — and says so through its own Progress. [status] is that
// sentence, read straight out of the shim.
//
// It crosses isolates the only way it can: the warm-up is one blocking FFI
// call in a background isolate, which cannot send a message out partway
// through, so the shim writes the status into a C global and the UI polls it.
// Both isolates are one process, so they see the same global.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'ffi/cycles_engine.dart';
import 'log.dart';

/// Where the renderer is in getting ready.
enum CyclesWarmupPhase {
  /// No renderer in this build, so there is nothing to prepare and nothing to
  /// say. Every host test, and every build without the Cycles libraries.
  absent,

  /// Compiling. [CyclesWarmup.status] says which step.
  compiling,

  /// Kernels are built; a render starts immediately.
  ready,

  /// The device could not be prepared. [CyclesWarmup.status] says why.
  failed,
}

/// Runs the shim's kernel compilation. Top-level so it can be an isolate body.
bool preloadCyclesKernels() => CyclesFfi.instance?.preload() ?? false;

/// How many times a warm-up may die before it is left alone.
///
/// The warm-up runs at launch and calls into a renderer. If it takes the
/// process down, it will do so again on the next launch, and the next — an app
/// that cannot be opened at all, in exchange for a feature nobody had asked
/// for yet. Build 619 was exactly that: a null dereference in the shim's world
/// setup, reached for the first time by the warm-up, on every single start.
///
/// So each attempt leaves a breadcrumb before it begins and clears it when it
/// finishes, however it finishes. A breadcrumb still on disk at startup means
/// the previous attempt did not return, and after [kCyclesWarmupAttempts] of
/// those the warm-up stops trying. Two rather than one, because a user killing
/// the app mid-compile looks identical to a crash and should not cost them the
/// feature.
const int kCyclesWarmupAttempts = 2;

/// The one warm-up, for the life of the process.
///
/// A singleton because what it tracks is a fact about the PROCESS — Metal has
/// compiled its kernels or it has not — rather than about a document or a
/// viewport. Two of these would each start their own compile, and the compile
/// is the expensive thing.
class CyclesWarmup {
  CyclesWarmup._();
  static final CyclesWarmup instance = CyclesWarmup._();

  CyclesWarmupPhase _phase = CyclesWarmupPhase.absent;
  String _status = '';
  double _progress = -1;
  Timer? _poll;
  bool _started = false;

  CyclesWarmupPhase get phase => _phase;
  bool get ready => _phase == CyclesWarmupPhase.ready;

  /// The step Cycles is on, in its own words. Empty when there is none.
  String get status => _status;

  /// 0..1 through the current step, or negative when there is no number yet.
  double get progress => _progress;

  final List<void Function()> _listeners = [];

  /// Fires whenever the phase, status or progress changes, so a viewport can
  /// repaint the message without polling on its own account.
  void addListener(void Function() fn) => _listeners.add(fn);
  void removeListener(void Function() fn) => _listeners.remove(fn);

  void _notify() {
    for (final fn in List.of(_listeners)) {
      fn();
    }
  }

  /// Starts the compile, once. Safe to call again; the second call does
  /// nothing. Returns immediately — the work is on another isolate.
  void start() {
    if (_started) return;
    _started = true;
    final ffi = CyclesFfi.instance;
    if (ffi == null) {
      _phase = CyclesWarmupPhase.absent;
      return;
    }
    if (ffi.kernelsReady) {
      _phase = CyclesWarmupPhase.ready;
      Log.i('cycles', 'kernels already compiled');
      return;
    }
    final crumb = _breadcrumb();
    final attempts = _readAttempts(crumb);
    if (attempts >= kCyclesWarmupAttempts) {
      _phase = CyclesWarmupPhase.failed;
      _status = 'the renderer stopped the app while preparing itself';
      // Loud, and flushed: this is the line that explains why rendered mode is
      // unavailable on an app that is otherwise working perfectly.
      Log.w(
          'cycles',
          'kernel compilation has failed to return $attempts times; not trying '
              'again. Delete ${crumb?.path} to re-arm it.');
      return;
    }
    _writeAttempt(crumb, attempts + 1);

    _phase = CyclesWarmupPhase.compiling;
    _status = 'Preparing the renderer';
    // milestone, not i: this is the last line before control crosses into a
    // renderer that has twice now been able to end the process, and an
    // ordinary buffered line would not survive that to say how far it got.
    Log.milestone('cycles',
        'compiling Metal kernels in the background (attempt ${attempts + 1})');
    _poll = Timer.periodic(const Duration(milliseconds: 400), (_) => _tick());
    Isolate.run(preloadCyclesKernels).then(_finished).catchError((Object e) {
      _clearAttempts(_breadcrumb());
      _stopPolling();
      _phase = CyclesWarmupPhase.failed;
      _status = '$e';
      Log.w('cycles', 'kernel compilation threw: $e');
      _notify();
    });
  }

  void _finished(bool ok) {
    // Cleared however it ended. A warm-up that returned did not crash, and a
    // clean failure is a fact about the device, not a reason to stop trying
    // after the next update.
    _clearAttempts(_breadcrumb());
    _stopPolling();
    _progress = -1;
    if (ok) {
      _phase = CyclesWarmupPhase.ready;
      _status = '';
      Log.i('cycles', 'kernels ready');
    } else {
      _phase = CyclesWarmupPhase.failed;
      final why = CyclesFfi.instance?.lastError ?? '';
      _status = why.isEmpty ? 'the renderer would not start' : why;
      Log.w('cycles', 'kernel compilation failed: $_status');
    }
    _notify();
  }

  void _stopPolling() {
    _poll?.cancel();
    _poll = null;
  }

  /// Where the attempt counter lives.
  ///
  /// Library/Caches, because it is writable, survives a relaunch, and is the
  /// same place the compiled kernels themselves go — if the system clears it
  /// under storage pressure, the kernels and the counter go together, which is
  /// exactly the pairing you want.
  File? _breadcrumb() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    return File('$home/Library/Caches/cycles_warmup_attempts');
  }

  int _readAttempts(File? f) {
    try {
      if (f == null || !f.existsSync()) return 0;
      return int.tryParse(f.readAsStringSync().trim()) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void _writeAttempt(File? f, int n) {
    try {
      f?.parent.createSync(recursive: true);
      f?.writeAsStringSync('$n', flush: true);
    } catch (_) {
      // A warm-up that cannot leave a breadcrumb still runs; it just cannot
      // protect the next launch. Better than not running.
    }
  }

  void _clearAttempts(File? f) {
    try {
      if (f != null && f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _tick() {
    final ffi = CyclesFfi.instance;
    if (ffi == null) return;
    final s = ffi.status;
    final p = ffi.progress;
    if (s == _status && p == _progress) return;
    if (s.isNotEmpty) _status = s;
    _progress = p;
    _notify();
  }

  /// For tests, which must not inherit another case's answer.
  void resetForTest() {
    _stopPolling();
    _started = false;
    _phase = CyclesWarmupPhase.absent;
    _status = '';
    _progress = -1;
    _listeners.clear();
  }

  /// For tests: pretend the compile reported this.
  void setForTest(CyclesWarmupPhase phase,
      {String status = '', double progress = -1}) {
    _phase = phase;
    _status = status;
    _progress = progress;
    _notify();
  }
}
