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
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/scheduler.dart';

import 'log.dart';

/// Rolling statistics for one named operation.
class PerfStat {
  int count = 0;
  double totalMs = 0;
  double worstMs = 0;
  double lastMs = 0;

  /// Samples kept for the percentile. Bounded: this runs for hours.
  ///
  /// A RING, not a growing list. The previous version did `removeAt(0)` on
  /// every sample past the 128th, i.e. an O(n) memmove inside the measuring
  /// code itself — on the 2D paint path that is per frame per phase. A probe
  /// that shows up in its own numbers is worthless (the rule at the top of
  /// this file), so the window now writes in place and never shifts.
  static const _keep = 128;
  final Float64List _samples = Float64List(_keep);
  int _n = 0; // how many slots are live (saturates at _keep)
  int _w = 0; // next write position

  void add(double ms) {
    count++;
    totalMs += ms;
    lastMs = ms;
    if (ms > worstMs) worstMs = ms;
    _samples[_w] = ms;
    _w = (_w + 1) % _keep;
    if (_n < _keep) _n++;
  }

  double get avgMs => count == 0 ? 0 : totalMs / count;

  /// 95th percentile of the retained window. The average hides hitches; the
  /// worst is one unlucky frame. p95 is what actually characterises feel.
  double get p95Ms => _pct(0.95);

  /// Median of the retained window. Together with p95 it says whether a
  /// subsystem is uniformly slow (p50 ~ p95) or usually fine with a tail
  /// (p50 << p95) — those two need opposite fixes, so both are reported.
  double get p50Ms => _pct(0.50);

  double _pct(double q) {
    if (_n == 0) return 0;
    final s = Float64List(_n);
    for (var i = 0; i < _n; i++) {
      s[i] = _samples[i];
    }
    s.sort();
    return s[((_n - 1) * q).round()];
  }

  Map<String, dynamic> toJson() => {
        'n': count,
        'lastMs': lastMs,
        'avgMs': avgMs,
        'p50Ms': p50Ms,
        'p95Ms': p95Ms,
        'worstMs': worstMs,
        'totalMs': totalMs,
      };
}

/// Sequential phase timing for a single hot function, without a closure per
/// phase.
///
/// [Perf.span] needs a `T Function()`, and a closure that captures locals
/// allocates. That is irrelevant for a kernel call that costs milliseconds,
/// and it is NOT irrelevant inside the 2D painter, which runs up to 120 times
/// a second and would pay for one allocation per phase per frame.
///
/// Usage — one long-lived instance (a `static final` on the painter), then:
///
///     _phases..begin()..mark('slice')..mark('entities')..mark('snap');
///
/// Each [mark] records the time since the previous mark under
/// `<prefix>.<phase>`. No allocation, one map lookup per phase, and the
/// phases sum to the whole function, so a share-of-total is meaningful.
class PerfPhases {
  PerfPhases(this.prefix);

  final String prefix;
  final Stopwatch _sw = Stopwatch();
  int _lastUs = 0;

  /// Cache of `prefix.phase` strings so a mark costs no string concatenation.
  final Map<String, String> _names = {};

  void begin() {
    _sw
      ..reset()
      ..start();
    _lastUs = 0;
  }

  void mark(String phase) {
    if (!_sw.isRunning) return;
    final now = _sw.elapsedMicroseconds;
    final dt = now - _lastUs;
    _lastUs = now;
    Perf.record(_names[phase] ??= '$prefix.$phase', dt / 1000.0);
  }

  /// Closes the run. Anything after the last [mark] lands under `<prefix>.z`,
  /// which is deliberately ugly: if it ever shows up big, a phase is missing.
  void end() {
    if (!_sw.isRunning) return;
    mark('z');
    _sw.stop();
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

  /// The OS-level facts Dart cannot obtain: thermal state, physical footprint,
  /// memory headroom, per-thread CPU. Filled by [setNative]; empty elsewhere.
  ///
  /// Kept in its OWN map rather than folded into [gauges] because these are not
  /// all integers and, more importantly, because they are not properties of the
  /// app at all — they are properties of the machine it happens to be running
  /// on. A reader has to be able to tell "the code got slower" from "the iPad
  /// got hot", and mixing the two tables is how that distinction gets lost.
  static final Map<String, Object?> native = {};

  /// Records an OS probe. [phase] namespaces it, so a suite can capture the
  /// state BEFORE and AFTER a long run: a thermal state that rose from nominal
  /// to serious across the suite invalidates every comparison made with the
  /// numbers after the rise, and that is only visible with both ends recorded.
  static void setNative(String phase, Map<String, Object?> probe) {
    if (_broken || probe.isEmpty) return;
    for (final e in probe.entries) {
      native['$phase.${e.key}'] = e.value;
    }
    // Thermal state as a gauge too, so it rides along in the per-scenario
    // deltas where the actual timings live.
    final t = probe['thermalOrdinal'];
    if (t is int) gauge('native.thermal.$phase', t);
    final f = probe['footprintMB'];
    if (f is int) gauge('native.footprintMB.$phase', f);
    final a = probe['availableMB'];
    if (a is int) gauge('native.availableMB.$phase', a);
  }

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
      // Every Log.step in the app becomes a timed span (see Log.stepSink).
      // That covers the whole launch sequence without a probe per phase.
      Log.stepSink = record;
      _ticker = Timer.periodic(_flushEvery, (_) => report());
    } catch (e) {
      _broken = true;
      Log.i('perf', 'performance log init FAILED: $e');
    }
  }

  /// Registers the engine frame-timing callback. MUST be called after
  /// `WidgetsFlutterBinding.ensureInitialized()`, and is deliberately NOT part
  /// of [init].
  ///
  /// M210 — this is why the perf log never worked on the device, from M79
  /// until now. `init()` runs as the second statement of `main()`, before any
  /// binding exists, because the file has to be open before anything can be
  /// measured. It also used to call `SchedulerBinding.instance` right there —
  /// and that getter is a null check on a binding that does not exist yet, so
  /// it threw:
  ///
  ///   perf: performance log init FAILED: Null check operator used on a null value
  ///
  /// The catch then set `_broken = true`, which makes every span, record,
  /// count and gauge in the app a silent no-op, and stops [retarget] from ever
  /// moving the file into Documents. The result was an instrument that
  /// reported its own failure in one line of the OTHER log file and then
  /// pretended to work for months.
  ///
  /// Split in two so the parts fail independently: losing frame timings must
  /// not cost the subsystem spans, and neither may take the file down with it.
  static void attachToBinding() {
    if (_broken) return;
    if (_timingsAttached) return;
    try {
      SchedulerBinding.instance.addTimingsCallback(_onTimings);
      _timingsAttached = true;
      Log.i('perf', 'frame timings attached');
    } catch (e) {
      // Explicitly NOT _broken: spans, counters and gauges are all still
      // valid without frame timings. Only frame.* is lost.
      Log.i('perf', 'frame timings NOT attached (spans still record): $e');
    }
  }

  static bool _timingsAttached = false;

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

  /// Wall clock from the top of `main()`. Only used for [markLaunchStart].
  static final Stopwatch _launch = Stopwatch();
  static bool _firstFrameSeen = false;

  /// Starts the launch clock. Call as the first statement of `main()`.
  static void markLaunchStart() => _launch.start();

  static void _onTimings(List<FrameTiming> timings) {
    if (!_firstFrameSeen && _launch.isRunning && timings.isNotEmpty) {
      _firstFrameSeen = true;
      _launch.stop();
      final ms = _launch.elapsedMicroseconds / 1000.0;
      record('launch.toFirstFrame', ms);
      Log.i('perf', 'time to first frame: ${ms.toStringAsFixed(1)} ms');
    }
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
  ///
  /// Counters live in their OWN table. They used to be recorded as a 0 ms
  /// sample in [_stats], which quietly corrupted two things: the counter's own
  /// row showed avg/p95 = 0 ms as if the work were free, and — worse — a name
  /// used for both a duration and a count had its average dragged toward zero
  /// by every count. A count is not a fast measurement; it is not a
  /// measurement at all.
  static void count(String name, [int by = 1]) {
    if (_broken) return;
    counters[name] = (counters[name] ?? 0) + by;
  }

  /// Event counters, by name. See [count].
  static final Map<String, int> counters = {};

  /// Short free-text findings, by name — the channel a REASON travels on.
  ///
  /// M221. A counter can say a kernel call returned null; it cannot say why,
  /// and the shim maintains `lastError` for exactly that. Until now the reason
  /// went to the event log, and the device run of 11 Aug proved that path
  /// cannot work: `log.txt` is captured when the bug button is pressed, at
  /// 10:47:45, while the suite runs at 10:48:10 — the diagnostic is written
  /// TWENTY-FIVE SECONDS after the snapshot meant to carry it, so it could
  /// never appear in a bundle. Three runs reported `kernel.sweepTwist.fail`
  /// with no reason attached for that reason alone.
  ///
  /// Notes travel in the suite's own JSON, which is assembled after the suite
  /// by construction, so the ordering that lost the log entry cannot lose
  /// these. Kept short: this is a diagnostic channel, not a log.
  static final Map<String, String> notes = {};

  /// Records [text] under [name], keeping the FIRST occurrence.
  ///
  /// First rather than last, deliberately: when an operation fails repeatedly
  /// the interesting failure is the one that started it, and a later, more
  /// generic error would otherwise overwrite the specific one.
  static void note(String name, String text) {
    if (_broken) return;
    if (text.isEmpty) return;
    notes.putIfAbsent(name, () => text.length > 400
        ? '${text.substring(0, 400)}…'
        : text);
  }

  /// Records a hit/miss pair under one name, so the report can print a rate.
  /// A cache whose hit rate you cannot see is a cache you cannot tune.
  static void cache(String name, bool hit) {
    if (_broken) return;
    count('$name.${hit ? 'hit' : 'miss'}');
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
    // Self-diagnosis. Spans recording but zero frames means the timings
    // callback never attached — the M210 failure. Without this line that state
    // looks identical to "the app is idle", which is exactly how it survived
    // from M79 until someone went looking for a file that was not there.
    if (totalFrames == 0 && _stats.isNotEmpty) {
      b.writeln('  WARNING  no frame timings — Perf.attachToBinding() did not '
          'run or failed. Spans below are valid; frame.* is missing.');
    }
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
    if (counters.isNotEmpty) {
      final c = counters.keys.toList()..sort();
      b.writeln(
          '  COUNTERS  ${[for (final k in c) '$k=${counters[k]}'].join('  ')}');
      // Hit rates, derived from the .hit/.miss pairs written by [cache].
      final rates = <String>[];
      for (final k in c) {
        if (!k.endsWith('.hit')) continue;
        final base = k.substring(0, k.length - 4);
        final hit = counters[k] ?? 0;
        final miss = counters['$base.miss'] ?? 0;
        if (hit + miss == 0) continue;
        rates.add('$base=${(100 * hit / (hit + miss)).toStringAsFixed(0)}%');
      }
      if (rates.isNotEmpty) b.writeln('  CACHE HIT  ${rates.join('  ')}');
    }
    _pending.write(b.toString());
    flush();
  }

  /// One machine-readable snapshot: the same numbers [report] prints, as JSON.
  ///
  /// This is what a baseline is diffed against. The text report is for reading
  /// on the iPad; this is for `perf/baseline.json` and for the CI regression
  /// gate, which cannot parse a column layout that shifts when a name grows.
  static Map<String, dynamic> jsonSnapshot() {
    _sampleMemory();
    return {
      'at': DateTime.now().toIso8601String(),
      'build': Log.build,
      'wallMs': _session.elapsedMilliseconds,
      'frames': {
        'n': totalFrames,
        'jank33': jankFrames,
        'fps': frameTotal.avgMs <= 0.01 ? 0.0 : 1000 / frameTotal.avgMs,
        'total': frameTotal.toJson(),
        'build': frameBuild.toJson(),
        'raster': frameRaster.toJson(),
      },
      'memory': {
        'rssBytes': rssBytes,
        'rssPeakBytes': rssPeakBytes,
        ..._resources(),
      },
      // M214 — what the OS says, as opposed to what Dart can see. Empty on a
      // host without the plugin. See [setNative].
      if (native.isNotEmpty) 'native': Map<String, Object?>.of(native),
      'spans': {for (final e in _stats.entries) e.key: e.value.toJson()},
      'counters': Map<String, int>.of(counters),
      'gauges': Map<String, int>.of(gauges),
      if (notes.isNotEmpty) 'notes': Map<String, String>.of(notes),
    };
  }

  /// Writes [jsonSnapshot] next to the text log as `performance_snapshot.json`
  /// and returns the path (empty when perf logging never came up). The bug
  /// bundle carries this file; so does the CI scenario runner.
  static String writeJsonSnapshot() {
    if (!ready) return '';
    try {
      final dir = File(_file!.path).parent;
      final f = File('${dir.path}/performance_snapshot.json');
      f.writeAsStringSync(
          const JsonEncoder.withIndent('  ').convert(jsonSnapshot()),
          flush: true);
      return f.path;
    } catch (e) {
      Log.i('perf', 'perf snapshot write FAILED: $e');
      return '';
    }
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

  // ---- scenario isolation ------------------------------------------------
  //
  // A session-cumulative report answers "where did two minutes go". It cannot
  // answer "what does ONE fillet cost", because every number is mixed with
  // everything else that happened. The scenario runner needs the second
  // question, so it brackets each scenario and takes the DELTA.
  //
  // Deltas, not resets: resetting would throw away the session totals that the
  // normal report is built from, and would make the runner's own numbers
  // depend on running first.

  static Map<String, dynamic> _mark() => {
        'spans': {
          for (final e in _stats.entries)
            e.key: [e.value.count, e.value.totalMs, e.value.worstMs]
        },
        'counters': Map<String, int>.of(counters),
      };

  /// Runs [body] and returns everything that changed while it ran: per-span
  /// call count and total/worst milliseconds, plus counter increments, plus
  /// the gauges as they stood at the end.
  ///
  /// The `worstMs` is reported as the worst seen DURING the scenario only when
  /// the span's session worst grew; otherwise it is reported as null, because
  /// a session worst set by some earlier scenario says nothing about this one.
  static Map<String, dynamic> scenario(String name, void Function() body) {
    final before = _mark();
    final sw = Stopwatch()..start();
    Object? error;
    try {
      body();
    } catch (e) {
      error = e;
    }
    sw.stop();
    final bs = before['spans'] as Map<String, List<Object>>;
    final bc = before['counters'] as Map<String, int>;
    final spans = <String, dynamic>{};
    for (final e in _stats.entries) {
      final b = bs[e.key];
      final n = e.value.count - (b == null ? 0 : b[0] as int);
      if (n <= 0) continue;
      final tot = e.value.totalMs - (b == null ? 0.0 : b[1] as double);
      final grew = b == null || e.value.worstMs > (b[2] as double);
      spans[e.key] = {
        'n': n,
        'totalMs': tot,
        'avgMs': n == 0 ? 0.0 : tot / n,
        if (grew) 'worstMs': e.value.worstMs,
      };
    }
    final ctr = <String, int>{};
    for (final e in counters.entries) {
      final d = e.value - (bc[e.key] ?? 0);
      if (d != 0) ctr[e.key] = d;
    }
    return {
      'scenario': name,
      'wallMs': sw.elapsedMicroseconds / 1000.0,
      if (error != null) 'error': error.toString(),
      'spans': spans,
      'counters': ctr,
      'gauges': Map<String, int>.of(gauges),
      if (notes.isNotEmpty) 'notes': Map<String, String>.of(notes),
      'rssMB': (() {
        try {
          return ProcessInfo.currentRss ~/ (1024 * 1024);
        } catch (_) {
          return 0;
        }
      })(),
    };
  }

  /// Test hook.
  static void resetForTest() {
    _stats.clear();
    _pool.clear();
    gauges.clear();
    counters.clear();
    notes.clear();
    native.clear();
    totalFrames = 0;
    jankFrames = 0;
  }

  static Map<String, PerfStat> get stats => _stats;
}
