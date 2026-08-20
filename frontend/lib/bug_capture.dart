// Prototype — turning the live app into a bug bundle.
//
// bug_report.dart holds the pure part (what goes in, how it is formatted);
// this is the half that has to touch AppState, the FFI probes and the disk.
// Split that way so the formatting is testable on the host without a running
// app, and so a change to AppState cannot quietly break the report format.
//
// Everything here is defensive. A bug reporter that throws while reporting a
// bug is worse than none at all: the user loses both the report AND their
// confidence that pressing the button did anything. Every gather step is
// individually wrapped, and a step that fails puts its error IN the bundle
// rather than aborting it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:native_menu/native_menu.dart';

import 'app_state.dart';
import 'gesture_trace.dart';
import 'constraints.dart';
import 'bug_report.dart';
import 'ffi/occt_engine.dart';
import 'log.dart';
import 'part_model.dart';
import 'perf.dart';
import 'perf_scenarios.dart';
import 'perf_scenarios_profile.dart';
import 'perf_scenarios_stress.dart';
import 'perf_scenarios_ui.dart';
import 'reality_scene.dart';

/// Anchors the widget subtree the screenshot is taken from. Attached to a
/// RepaintBoundary wrapping the whole app body in main.dart.
final GlobalKey screenshotKey = GlobalKey(debugLabel: 'bug-screenshot');

/// PNG of whatever Flutter has rendered, or null.
///
/// On iOS the 3D body is a RealityKit PLATFORM VIEW: the OS composites it
/// outside Flutter's layer tree, so it is absent from this image however the
/// capture is done. 2D sketches are a CustomPainter and come out complete.
/// The bundle says which, next to the file, so an empty-looking viewport is
/// never mistaken for a missing body.
/// [timeout] exists because toImage can simply never complete: it hands the
/// work to the rasterizer and waits, and where there is no rasterizer to
/// answer — a headless test, and by extension a backgrounded or
/// surface-less app — the future stays pending forever. Writing this without
/// a bound meant the bug button could hang the app while reporting a hang,
/// which is the worst possible failure for this particular feature. Found by
/// the widget test below, which hung for ten minutes.
Future<Uint8List?> captureScreenshot({
  double pixelRatio = 1.5,
  Duration timeout = const Duration(seconds: 4),
}) async {
  try {
    final ctx = screenshotKey.currentContext;
    if (ctx == null) return null;
    final ro = ctx.findRenderObject();
    if (ro is! RenderRepaintBoundary) return null;
    final data = await () async {
      final ui.Image img = await ro.toImage(pixelRatio: pixelRatio);
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      return d;
    }()
        .timeout(timeout, onTimeout: () {
      Log.w('bug', 'screenshot timed out after ${timeout.inSeconds}s — '
          'no rasterizer answered; the rest of the bundle is unaffected');
      return null;
    });
    return data?.buffer.asUint8List();
  } catch (e, st) {
    Log.w('bug', 'screenshot failed: $e\n$st');
    return null;
  }
}

/// Runs [f], returning its value, or a placeholder string on any failure.
String _try(String what, String Function() f) {
  try {
    return f();
  } catch (e, st) {
    Log.w('bug', 'capture step "$what" failed: $e');
    return '<$what failed: $e\n$st>';
  }
}

String? _readIfExists(String path) {
  try {
    final f = File(path);
    return f.existsSync() ? f.readAsStringSync() : null;
  } catch (_) {
    return null;
  }
}

/// Build, device and backend identity — the first thing to check when a report
/// does not reproduce.
Map<String, String> captureEnv(AppState app) {
  final env = <String, String>{};
  env['captured'] = DateTime.now().toIso8601String();
  env['build'] = Log.build;
  env['os'] = _try('os', () => '${Platform.operatingSystem} '
      '${Platform.operatingSystemVersion}');
  env['dart'] = _try('dart', () => Platform.version);
  env['locale'] = _try('locale', () => Platform.localeName);
  env['qcad backend'] = _try(
      'qcad', () => '${app.backendReal ? 'REAL' : 'DART FALLBACK'} '
          '— ${app.backendInfo}');
  env['occt backend'] = _try('occt', () {
    final ffi = OcctFfi.instance();
    return ffi == null
        ? 'NOT LINKED — no 3D kernel, every solid will be missing'
        : '${ffi.version} (shim v${ffi.shimVersion})';
  });
  env['open part'] = app.curTab ?? '(none)';
  env['parts loaded'] = '${app.parts.length}';
  return env;
}

/// Per-solid mesh analysis, forced on regardless of [meshDiagnostics].
///
/// The full watertightness pass is normally off because it costs ~50 ms on a
/// large mesh and used to run on every re-tessellation. Pressing the bug
/// button is exactly the moment to pay for it once: a non-watertight or
/// inside-out mesh is invisible in the cheap summary and is precisely what
/// "the shape looks wrong" means.
String captureMeshReports(PartModel? p) {
  if (p == null) return 'no part open';
  final b = StringBuffer();
  final was = meshDiagnostics;
  meshDiagnostics = true;
  try {
    for (final f in p.features) {
      final s = f.solid;
      if (s == null) {
        b.writeln('${f.name}: no solid');
        continue;
      }
      b.writeln(_try('mesh ${f.name}', () => meshSelfReport(f.name, s.mesh)));
      for (final a in meshAnomalies(s.mesh)) {
        b.writeln('   !! $a');
      }
    }
  } finally {
    meshDiagnostics = was;
  }
  return b.toString();
}

/// Writes a bug bundle and returns the file, or null if it could not be
/// written. Never throws.
///
/// [description] is what the user typed. Everything else is gathered here.
Future<File?> captureBugReport(AppState app, String description) async {
  final when = DateTime.now();
  try {
    // Get the log on disk BEFORE reading it, or the bundle ships a log that
    // stops a few hundred lines before the thing being reported.
    Log.i('bug', '=== BUG REPORT REQUESTED ===');
    Log.i('bug', 'description: ${description.replaceAll('\n', ' | ')}');
    Log.flush();

    final part = app.curTab == null ? null : app.parts[app.curTab!];

    String? partJson;
    final sketchJson = <String, String>{};
    if (part != null) {
      partJson = _try('part.json', () =>
          const JsonEncoder.withIndent('  ').convert(part.toJson()));
      // A sketch persists as a DXF plus half a dozen JSON sidecars, so there
      // is no single document to lift. This is a self-contained equivalent:
      // raw geometry arrays in the solver's own layout, plus the constraint
      // encoder the real save path uses. Enough to rebuild the sketch and
      // replay its solve, which is the whole point of shipping it.
      for (final cs in part.childSketches) {
        sketchJson[cs.model.name] = _try('sketch ${cs.model.name}', () {
          final m = cs.model;
          return const JsonEncoder.withIndent('  ').convert({
            'name': m.name,
            'plane': cs.plane,
            'seq': cs.seq,
            'visible': cs.visible,
            'shared': cs.shared,
            'eosAfter': m.eosAfter,
            'layers': m.layers,
            'hiddenLayers': m.hiddenLayers.toList(),
            'lockedLayers': m.lockedLayers.toList(),
            'geometry': [
              for (final g in m.geometry)
                {
                  'type': g.type,
                  'spline': g.spline,
                  'style': g.style,
                  'layer': g.layer,
                  'isProjection': g.isProjection,
                  'data': g.data,
                }
            ],
            // The same encoder savePart writes, so this round-trips.
            'constraints': jsonDecode(encodeConstraints(m.constraints)),
          });
        });
      }
    }

    // Before anything else that could change the screen. The dialog has
    // already closed by this point, so this is the state being complained
    // about, not the reporting UI.
    final png = await captureScreenshot();

    final logPath = Log.path;
    final logText = _readIfExists(logPath);
    final prevText = _readIfExists(
        logPath.replaceFirst('prototype_log.txt', 'prototype_log_prev.txt'));

    final files = buildBundle(
      description: description,
      when: when,
      env: captureEnv(app),
      part: part,
      partJson: partJson,
      sketchJson: sketchJson,
      logText: logText,
      prevLogText: prevText,
      // Frame and remesh timings. The 10.7-second remesh in the device log
      // was a perf line, not a log line, so a bundle without this can miss
      // the whole character of a "it froze" report.
      perfText: Perf.path.isEmpty ? null : _readIfExists(Perf.path),
      gestureText: GestureTrace.dump().join('\n'),
      realityText: RealityPush.dump().join('\n'),
      hasScreenshot: png != null,
      screenshotOmits3D: Platform.isIOS,
    );

    // Added here rather than in buildBundle because it needs the scene layer,
    // which the pure builder deliberately does not import.
    files['mesh.txt'] = captureMeshReports(part);

    // The scenario suite: the app measuring ITSELF, on this device, with
    // fixed inputs. A hand-driven session says what happened; this says what
    // each operation costs and how that cost scales — and unlike the session,
    // it is identical on every device, so two bundles from two iPads are
    // directly comparable. Runs inside the bundle capture so one tap produces
    // both the observation and the benchmark.
    //
    // Guarded: it is measurement, and a measurement failing must never cost
    // the user their bug report.
    // M214 — the machine's own state, BEFORE the suite runs.
    //
    // This is the number that decides whether an M4 measurement says anything
    // about an M2. A fanless iPad throttles under a sustained benchmark, and
    // the suite below IS a sustained benchmark: without a thermal reading at
    // both ends, a slow second half is indistinguishable from slow code. The
    // same applies to memory — the suite allocates real solids, and how much
    // headroom there was when it started changes what the numbers mean.
    try {
      Perf.setNative('preSuite', await NativeMenu.perfProbe());
    } catch (e) {
      Log.w('perf', 'native probe (pre) failed: $e');
    }

    try {
      files['perf_suite.json'] = const JsonEncoder.withIndent('  ')
          .convert(runPerfSuite());
    } catch (e) {
      files['perf_suite.json'] = 'scenario suite failed: $e';
    }
    // The UI half — paint phases, the drag path, snap. Separate call because
    // it needs a Flutter binding; separate try because a Canvas failing must
    // not cost the headless numbers that already succeeded.
    try {
      files['perf_suite_ui.json'] = const JsonEncoder.withIndent('  ')
          .convert(runUiPerfSuite());
    } catch (e) {
      files['perf_suite_ui.json'] = 'ui scenario suite failed: $e';
    }

    // The STRESS tier — opt-in, by typing `stress` in the description.
    //
    // Not in the ordinary capture because its ladders climb until they blow a
    // time budget, which at the top rungs means minutes. A diagnostic that
    // makes the app look broken while diagnosing it is worse than no
    // diagnostic — and this one deliberately drives the exact operation that
    // already killed the app once, so it must never fire by accident.
    if (description.toLowerCase().contains('stress')) {
      Log.i('bug', 'stress tier requested — this will take a while');
      try {
        files['perf_suite_stress.json'] = const JsonEncoder.withIndent('  ')
            .convert(runStressSuite());
      } catch (e) {
        files['perf_suite_stress.json'] = 'stress suite failed: $e';
      }
    }

    // The PROFILE-COMPLEXITY tier (S11) — opt-in, by typing `profile`.
    //
    // Separate from `stress` and not implied by it. The stress ladders climb
    // entity and edge counts; these climb PROFILE complexity — segment count,
    // path resolution, loop count, self-intersections — which is the axis no
    // tier has ever covered and the one a real drawing grows along. It is
    // opt-in for the stress tier's reason and then some: a single rung of
    // profile.sweep.segments reproduces the field's 1200-segment sweep, and
    // that sweep cost 102 seconds.
    if (description.toLowerCase().contains('profile')) {
      Log.i('bug', 'profile tier requested — the top rungs cost minutes');
      try {
        files['perf_suite_profile.json'] = const JsonEncoder.withIndent('  ')
            .convert(runProfileSuite());
      } catch (e) {
        files['perf_suite_profile.json'] = 'profile suite failed: $e';
      }
    }

    // ...and again afterwards. A thermal state that rose from nominal to
    // serious across the run invalidates every comparison made with the
    // numbers from its second half, and that is only visible with both ends
    // recorded. A footprint that grew and never came back is the other thing
    // this pair catches.
    try {
      Perf.setNative('postSuite', await NativeMenu.perfProbe());
    } catch (e) {
      Log.w('perf', 'native probe (post) failed: $e');
    }

    // M215 — the time spent PAST the platform-view boundary.
    //
    // `rv.setScene` on the Dart side measures how long the channel call takes
    // to return; on an asynchronous channel that is not how long RealityKit
    // took to apply the payload. This is the native table, phase by phase, and
    // it is the last thing in the report that used to be unmeasurable by
    // construction. Recorded as ordinary spans so it ranks alongside
    // everything else rather than sitting in a corner of its own.
    try {
      final rv = await RealityPush.drainNative();
      rv.forEach((name, v) {
        if (v is Map) {
          final n = (v['n'] as num?)?.toInt() ?? 0;
          final total = (v['totalMs'] as num?)?.toDouble() ?? 0.0;
          final worst = (v['worstMs'] as num?)?.toDouble() ?? 0.0;
          // Recorded as n samples of the average: PerfStat keeps a count and a
          // total, and feeding one fat sample would make the call count wrong
          // in every report that reads it.
          if (n > 0) {
            for (var i = 0; i < n; i++) {
              Perf.record(name, total / n);
            }
            // ...but n copies of the average erase the WORST, and on this path
            // the worst is the interesting number: one 300 ms mesh upload
            // among fifty cheap camera pushes is a visible stall, and an
            // average of 6 ms hides it completely. The native side already
            // tracked it, so publishing it separately costs nothing — as a
            // gauge rather than a sample, because a sample would corrupt the
            // total the loop above just got right.
            Perf.gauge('$name.worstUs', (worst * 1000).round());
          }
        }
      });
    } catch (e) {
      Log.w('perf', 'reality native drain failed: $e');
    }

    // The perf data a MACHINE can read. `perfText` above is the rolling text
    // log, which is what a person reads; this is one structured snapshot of
    // the same counters at the moment of capture, which is what gets diffed
    // against perf/baseline.json. A slowdown report is only actionable if the
    // numbers can be compared to a known-good run without re-typing them.
    Perf.report();
    files['perf_snapshot.json'] =
        const JsonEncoder.withIndent('  ').convert(Perf.jsonSnapshot());
    // The PREVIOUS perf session too. A "it got slow after a while" report is
    // about a trend, and the trend is exactly what rotation threw out of the
    // current file.
    if (Perf.path.isNotEmpty) {
      final prevPerf = _readIfExists(Perf.path
          .replaceFirst('performance_logs.txt', 'performance_logs_prev.txt'));
      if (prevPerf != null && prevPerf.isNotEmpty) {
        files['performance_logs_prev.txt'] = prevPerf;
      }
    }

    final dir = Directory('${_docsRoot(app)}/bugreports');
    final out = writeBundle(dir, bundleStem(when), files,
        when: when,
        binaries: png == null ? const {} : {'screenshot.png': png});
    if (out == null) {
      Log.e('bug', 'bundle could not be written to ${dir.path}');
    } else {
      Log.i('bug', 'bug bundle written: ${out.path} '
          '(${out.lengthSync()} bytes, ${files.length} members)');
    }
    return out;
  } catch (e, st) {
    Log.e('bug', 'capture failed outright', e, st);
    return null;
  }
}

String _docsRoot(AppState app) {
  final d = app.docsDir;
  if (d != null) return d.path;
  // Same derivation Log.init uses, so a report is still written when the
  // platform channel never came up.
  final home = Platform.environment['HOME'];
  if (home != null && home.isNotEmpty) return '$home/Documents';
  return Directory.systemTemp.path;
}
