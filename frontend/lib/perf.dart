// Performance metrics, written to their OWN file (performance_logs.txt).
//
// Why separate from prototype_log.txt: performance data is high-volume and
// periodic, and mixing it into the event log would drown the events that make
// a bug reproducible. Two files, two purposes.
//
// Why it exists at all: three rounds of this project's optimisation work went
// into the wrong layer (HANDOFF M75). The 3D re-tessellation was measured and
// improved repeatedly while the reported stutter came from the 2D painter,
// because the only instrumentation was a `perf:` line around re-meshing. The
// rule this file encodes: never optimise what you have not measured, and make
// measuring cheap enough that it is always on.
//
// Cost discipline: a probe that shows up in its own numbers is worthless.
// [Perf.span] is a Stopwatch start/stop plus one map lookup — no allocation
// per call, no string formatting until a flush, and flushes are periodic
// rather than per event.
import 'dart:async';
import 'dart:io';

import 'package:flutter/scheduler.dart';

import 'log.dart';

/// Rolling statistics for one named operation.
class PerfStat {
  int count = 0;
  double totalMs = 0;
  double worstMs = 0;
  double lastMs = 0;

  /// Samples kept for the percentile. Bounded: this runs for hours.
  static const _keep = 128;
  final List<double> _samples = [];

  void add(double ms) {
    count++;
    totalMs += ms;
    lastMs = ms;
    if (ms > worstMs) worstMs = ms;
    _samples.add(ms);
    if (_samples.length > _keep) _samples.removeAt(0);
  }

  double get avgMs => count == 0 ? 0 : totalMs / count;

  /// 95th percentile of the retained window. The average hides hitches; the
  /// worst is one unlucky frame. p95 is what actually characterises feel.
  double get p95Ms {
    if (_samples.isEmpty) return 0;
    final s = List<double>.of(_samples)..sort();
    return s[((s.length - 1) * 0.95).round()];
  }

  void resetInterval() {
    // count/total/worst are cumulative for the session; only the sample
    // window rolls, so p95 tracks recent behaviour rather than app start.
  }
}

/// Named performance counters plus frame timing, flushed periodically to
/// `logs/performance_logs.txt`.
class Perf {
  static File? _file;
  static bool _broken = false;
  static final StringBuffer _pending = StringBuffer();
  static Timer? _ticker;
  static final Map<String, PerfStat> _stats = {};
  static final Map<String, Stopwatch> _pool = {};

  /// Frame timings straight from the engine, split the way Flutter splits
  /// them: BUILD is Dart work, RASTER is the GPU thread. Which one is high
  /// tells you whether to look at widgets or at painting.
  static final PerfStat frameBuild = PerfStat();
  static final PerfStat frameRaster = PerfStat();
  static final PerfStat frameTotal = PerfStat();
  static int jankFrames = 0; // > 33 ms, i.e. a visibly dropped frame
  static int totalFrames = 0;

  /// Snapshot values, set by whoever owns them (scene size, entity counts).
  static final Map<String, int> gauges = {};

  /// Wall clock since the session started, so each subsystem's total can be
  /// expressed as a SHARE of elapsed time. That share is the number that
  /// answers "which part of the app is eating the machine" — a total of
  /// 4 000 ms means nothing until you know whether the app ran for five
  /// seconds or five minutes.
  static final Stopwatch _session = Stopwatch()..start();

  /// Resident memory in bytes, sampled at each report. This is real RSS from
  /// the OS, not an estimate.
  static int rssBytes = 0;
  static int rssPeakBytes = 0;

  static const _maxBytes = 4 * 1024 * 1024;
  static const _flushEvery = Duration(seconds: 5);

  static bool get ready => _file != null && !_broken;

  /// Where the perf log is, so a bug bundle can carry it. Empty when perf
  /// logging never came up.
  static String get path => _file?.path ?? '';

  static void init() {
    try {
      String? docs;
      if (Platform.isIOS || Platform.isMacOS) {
        final home = Platform.environment['HOME'];
        if (home != null && home.isNotEmpty) docs = '$home/Documents';
      }
      docs ??= Directory.systemTemp.path;
      _open(docs);
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _ticker = Timer.periodic(_flushEvery, (_) => report());
    } catch (e) {
      _broken = true;
      Log.i('perf', 'performance log init FAILED: $e');
    }
  }

  /// Moves the file next to the main log once the real Documents path is
  /// known, carrying the history across — same dance as Log.retarget.
  static void retarget(String documentsDir) {
    if (_broken) return;
    try {
      final dir = Directory('$documentsDir/logs');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final target = File('${dir.path}/performance_logs.txt');
      final old = _file;
      if (old != null && old.path == target.path) return;
      flush();
      if (old != null && old.existsSync()) {
        try {
          target.writeAsStringSync(old.readAsStringSync(),
              mode: FileMode.append, flush: true);
          old.deleteSync();
        } catch (_) {/* keep going */}
      }
      _file = target;
      Log.i('perf', 'performance log at ${target.path}');
    } catch (e) {
      Log.i('perf', 'performance log retarget FAILED: $e');
    }
  }

  static void _open(String docs) {
    final dir = Directory('$docs/logs');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final f = File('${dir.path}/performance_logs.txt');
    if (f.existsSync() && f.lengthSync() > _maxBytes) {
      final prev = File('${dir.path}/performance_logs_prev.txt');
      if (prev.existsSync()) prev.deleteSync();
      f.renameSync(prev.path);
    }
    _file = File('${dir.path}/performance_logs.txt');
    _file!.writeAsStringSync(
        '\n================ PERF SESSION ${DateTime.now().toIso8601String()}'
        ' build=${Log.build} ================\n'
        '# ms columns are: last / avg / p95 / worst   (n = calls)\n',
        mode: FileMode.append,
        flush: true);
  }

  /// What we can and cannot measure from Dart, stated plainly so nobody reads
  /// more into these numbers than they carry:
  ///
  ///  * RAM  — exact. ProcessInfo.currentRss is the real resident set.
  ///  * GPU  — frame.raster is the raster-thread duration, which is the honest
  ///           proxy for GPU-side cost per frame. It is NOT a utilisation
  ///           percentage and there is no Dart API that gives one.
  ///  * CPU  — no per-process CPU% is available from Dart. frame.build plus
  ///           the named spans below ARE the CPU work, attributed by
  ///           subsystem, which is more actionable than a single percentage
  ///           anyway. Do not invent a CPU% here.
  static void _sampleMemory() {
    try {
      rssBytes = ProcessInfo.currentRss;
      final peak = ProcessInfo.maxRss;
      if (peak > rssPeakBytes) rssPeakBytes = peak;
      if (rssBytes > rssPeakBytes) rssPeakBytes = rssBytes;
    } catch (_) {
      // some platforms refuse; leave the last value
    }
  }

  static void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final b = t.buildDuration.inMicroseconds / 1000.0;
      final r = t.rasterDuration.inMicroseconds / 1000.0;
      final tot = t.totalSpan.inMicroseconds / 1000.0;
      frameBuild.add(b);
      frameRaster.add(r);
      frameTotal.add(tot);
      totalFrames++;
      if (tot > 33) jankFrames++;
    }
  }

  /// Times [body] under [name]. Reuses a pooled Stopwatch so a probe costs no
  /// allocation; exceptions still record the time before rethrowing.
  static T span<T>(String name, T Function() body) {
    if (_broken) return body();
    final sw = _pool.putIfAbsent(name, () => Stopwatch());
    // Re-entrant call (a span inside the same span): just run it, rather than
    // corrupting the outer measurement.
    if (sw.isRunning) return body();
    sw
      ..reset()
      ..start();
    try {
      return body();
    } finally {
      sw.stop();
      record(name, sw.elapsedMicroseconds / 1000.0);
    }
  }

  /// Records a duration measured elsewhere.
  static void record(String name, double ms) {
    if (_broken) return;
    (_stats[name] ??= PerfStat()).add(ms);
  }

  /// Sets a snapshot number (triangles, entities, cache size, ...).
  static void gauge(String name, int value) {
    if (_broken) return;
    gauges[name] = value;
  }

  /// Counts an event (cache hit, rebuild, ...) without a duration.
  static void count(String name) {
    if (_broken) return;
    (_stats[name] ??= PerfStat()).add(0);
  }

  // ---- system resources -------------------------------------------------
  //
  // What is actually obtainable from Dart on iOS, and what is not:
  //
  //  RAM  — ProcessInfo.currentRss is the resident set size of the whole
  //         process, reported by the OS. Real and exact.
  //  GPU  — no API exposes GPU utilisation to a sandboxed iOS app. But
  //         FrameTiming.rasterDuration IS the time the raster thread spent
  //         producing the frame, which is the number that matters for us:
  //         it rises exactly when the GPU work per frame grows.
  //  CPU  — no per-process CPU percentage either. frame.build is the Dart
  //         (UI-thread) cost and the named spans below attribute it to
  //         concrete work, which answers "which part costs what" without
  //         pretending to a percentage we cannot measure.
  //
  // Anything not measurable is left out rather than estimated. A plausible
  // wrong number is worse than a missing one.
  static int _peakRssMb = 0;

  static Map<String, int> _resources() {
    final out = <String, int>{};
    try {
      final rss = ProcessInfo.currentRss ~/ (1024 * 1024);
      if (rss > _peakRssMb) _peakRssMb = rss;
      out['rssMB'] = rss;
      out['rssPeakMB'] = _peakRssMb;
      final max = ProcessInfo.maxRss ~/ (1024 * 1024);
      if (max > 0) out['rssMaxMB'] = max;
    } catch (_) {/* not all platforms report it */}
    return out;
  }

  static String _row(String name, PerfStat s) =>
      '  ${name.padRight(26)} n=${s.count.toString().padLeft(6)}  '
      '${s.lastMs.toStringAsFixed(1).padLeft(7)} /'
      '${s.avgMs.toStringAsFixed(1).padLeft(7)} /'
      '${s.p95Ms.toStringAsFixed(1).padLeft(7)} /'
      '${s.worstMs.toStringAsFixed(1).padLeft(7)} ms';

  /// Writes one full snapshot. Called on the timer and on demand.
  static void report() {
    if (!ready) return;
    if (_stats.isEmpty && totalFrames == 0) return;
    final b = StringBuffer()
      ..writeln('--- ${DateTime.now().toIso8601String()} ---');
    if (totalFrames > 0) {
      final fps = frameTotal.avgMs <= 0.01 ? 0.0 : 1000 / frameTotal.avgMs;
      b
        ..writeln('  FRAMES  n=$totalFrames  fps=${fps.toStringAsFixed(1)}  '
            'jank(>33ms)=$jankFrames '
            '(${(100 * jankFrames / totalFrames).toStringAsFixed(1)}%)')
        ..writeln(_row('frame.total', frameTotal))
        ..writeln(_row('frame.build(dart)', frameBuild))
        ..writeln(_row('frame.raster(gpu)', frameRaster));
    }
    _sampleMemory();
    b.writeln('  MEMORY  rss=${_mb(rssBytes)} peak=${_mb(rssPeakBytes)}');

    // Subsystem breakdown, sorted by TOTAL time spent — the answer to "what
    // is eating the machine", with each subsystem's share of wall clock.
    final elapsed = _session.elapsedMilliseconds.toDouble();
    final names = _stats.keys.toList()
      ..sort((a, c) => _stats[c]!.totalMs.compareTo(_stats[a]!.totalMs));
    b.writeln('  SUBSYSTEMS (by total time, share of ${(elapsed / 1000)
        .toStringAsFixed(0)}s wall clock)');
    for (final n in names) {
      final st = _stats[n]!;
      final share = elapsed <= 0 ? 0.0 : 100 * st.totalMs / elapsed;
      b.writeln('${_row(n, st)}  tot=${(st.totalMs / 1000).toStringAsFixed(2)}s'
          ' ${share.toStringAsFixed(1)}%');
    }
    final res = _resources();
    if (res.isNotEmpty) {
      final r = res.keys.toList()..sort();
      b.writeln(
          '  MEMORY  ${[for (final k in r) '$k=${res[k]}'].join('  ')}');
    }
    if (gauges.isNotEmpty) {
      final g = gauges.keys.toList()..sort();
      b.writeln('  GAUGES  ${[for (final k in g) '$k=${gauges[k]}'].join('  ')}');
    }
    _pending.write(b.toString());
    flush();
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';

  static void flush() {
    if (!ready || _pending.isEmpty) return;
    try {
      _file!.writeAsStringSync(_pending.toString(),
          mode: FileMode.append, flush: true);
      _pending.clear();
    } catch (e) {
      _broken = true;
      Log.i('perf', 'performance log write FAILED: $e');
    }
  }

  static void dispose() {
    _ticker?.cancel();
    _ticker = null;
    report();
  }

  /// Test hook.
  static void resetForTest() {
    _stats.clear();
    _pool.clear();
    gauges.clear();
    totalFrames = 0;
    jankFrames = 0;
  }

  static Map<String, PerfStat> get stats => _stats;
}
