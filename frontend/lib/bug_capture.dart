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

import 'app_state.dart';
import 'constraints.dart';
import 'bug_report.dart';
import 'ffi/occt_engine.dart';
import 'log.dart';
import 'part_model.dart';
import 'reality_scene.dart';

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
File? captureBugReport(AppState app, String description) {
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
    );

    // Added here rather than in buildBundle because it needs the scene layer,
    // which the pure builder deliberately does not import.
    files['mesh.txt'] = captureMeshReports(part);

    final dir = Directory('${_docsRoot(app)}/bugreports');
    final out = writeBundle(dir, bundleStem(when), files, when: when);
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
