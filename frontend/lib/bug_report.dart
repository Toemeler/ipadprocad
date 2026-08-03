// Prototype — the bug report bundle.
//
// One ZIP that answers, without the reporter having to say anything: what was
// on screen, what the model actually contained, which parts of it the kernel
// refused, and what the log said while it happened.
//
// The design rule is REPRODUCIBILITY, the same one diag.dart states for sketch
// dumps. A bundle is useful when it lets the failure be rebuilt off-device, so
// it carries the document itself (loadable) next to the derived state (why the
// document produced what it did). Everything in here is derived from the live
// model at the moment the button was pressed — nothing is recomputed later,
// because a recompute is exactly the thing that might not reproduce.
//
// The heavy lifting is pure functions over PartModel so it is testable on the
// host; only [captureBugReport] touches the app and the filesystem.
import 'dart:convert';
import 'dart:io';

import 'diag.dart';
import 'part_model.dart';
import 'zip_writer.dart';

/// One line per thing that is currently wrong, most actionable first.
///
/// This is the section read first, so it states PROBLEMS, not statistics. An
/// empty list is itself a finding: the model is healthy and the bug is in the
/// interaction or the display, which sends the reader to the log instead.
List<String> triage(PartModel? p) {
  final out = <String>[];
  if (p == null) return ['no part is open'];

  final sick = p.features.where((f) => f.computeError != null).toList();
  for (final f in sick) {
    out.add('SICK ${f.name} (${f.kind}) on ${f.bodyName}: ${f.computeError}');
  }

  // A feature that reports no error but produced nothing is worse than a sick
  // one: nothing in the UI marks it, so it is invisible until the body is
  // missing and no one knows why.
  for (final f in p.features) {
    if (f.computeError == null && f.solid == null && !f.rolledBack) {
      out.add('SILENT ${f.name} (${f.kind}): no solid and no error — '
          'the fold produced nothing and said nothing');
    }
  }

  // Blend features whose stored edges cannot all be found. The count is what
  // the last recompute resolved, so it is the live truth, not a guess.
  for (final f in p.features) {
    if (f is BodyModifyFeature && f.edges.isEmpty) {
      out.add('EMPTY ${f.name}: carries no edge selections at all');
    }
  }

  for (final cs in p.childSketches) {
    final gs = cs.model.geometry;
    if (!allFinite(gs)) {
      out.add('NOT FINITE ${cs.model.name}: geometry contains NaN/Inf — '
          'this is what makes drawing silently vanish');
    }
    final m = maxAbs(gs);
    if (m > 1e6) {
      out.add('EXPLODED ${cs.model.name}: largest coordinate is '
          '${m.toStringAsExponential(2)}');
    }
  }

  final bodies = <String>{for (final f in p.features) f.bodyName};
  for (final b in bodies) {
    final fs = p.features.where((f) => f.bodyName == b && !f.rolledBack);
    if (fs.isNotEmpty && fs.every((f) => f.solid == null)) {
      out.add('BODY GONE $b: every feature on it is without a solid');
    }
  }
  return out;
}

String _yn(bool b) => b ? 'yes' : 'no';

/// Everything about one solid that distinguishes "fine" from "wrong shape".
String _solidLine(KernelSolid? s) {
  if (s == null) return 'solid=NONE';
  final m = s.mesh;
  final tris = m.indices.length ~/ 3;
  final verts = m.positions.length ~/ 3;
  final faces = <int>{for (final f in m.triFaces) f}.length;
  var bbox = 'bbox=?';
  if (m.positions.isNotEmpty) {
    var x0 = m.positions[0], y0 = m.positions[1], z0 = m.positions[2];
    var x1 = x0, y1 = y0, z1 = z0;
    for (var i = 0; i + 2 < m.positions.length; i += 3) {
      final x = m.positions[i], y = m.positions[i + 1], z = m.positions[i + 2];
      if (x < x0) x0 = x;
      if (y < y0) y0 = y;
      if (z < z0) z0 = z;
      if (x > x1) x1 = x;
      if (y > y1) y1 = y;
      if (z > z1) z1 = z;
    }
    String r(double v) => v.toStringAsFixed(2);
    bbox = 'bbox=${r(x0)},${r(y0)},${r(z0)}..${r(x1)},${r(y1)},${r(z1)}';
  }
  return 'solid=present vol=${s.volume.toStringAsFixed(4)} tris=$tris '
      'faces=$faces verts=$verts meshLin=${s.meshLin.toStringAsExponential(2)} '
      'brep=${s.shape == null ? 'NONE (fake kernel)' : 'yes'} $bbox';
}

/// The stored fingerprint of a picked edge — what a blend re-matches against.
String _edgeSelLine(int i, EdgeSel e) =>
    '  sel[$i] kind=${e.kind} r=${e.radius.toStringAsFixed(4)} '
    'len=${e.length.toStringAsFixed(4)} '
    'mid=(${e.mx.toStringAsFixed(4)},${e.my.toStringAsFixed(4)},'
    '${e.mz.toStringAsFixed(4)}) tol=${e.tol.toStringAsFixed(4)}';

/// Full state of every feature, in timeline order.
List<String> featureDump(PartModel p) {
  final out = <String>['features (${p.features.length}), eopAfter=${p.eopAfter}'
      ' (atEnd=${_yn(p.eopAtEnd)}):'];
  for (var i = 0; i < p.features.length; i++) {
    final f = p.features[i];
    out.add('[$i] ${f.name}  kind=${f.kind}  body=${f.bodyName}  '
        'output=${f.output}  visible=${_yn(f.visible)}  '
        'rolledBack=${_yn(f.rolledBack)}  consumed=${_yn(f.consumedByJoin)}  '
        'seq=${f.seq}');
    out.add('     ${_solidLine(f.solid)}');
    if (f.computeError != null) out.add('     ERROR: ${f.computeError}');
    if (f.sketchNames.isNotEmpty) {
      out.add('     sketches=${f.sketchNames.join(',')}');
    }
    // toJson carries every persisted parameter of every feature kind, so this
    // stays complete as new kinds are added instead of quietly omitting them.
    try {
      out.add('     params=${jsonEncode(f.toJson())}');
    } catch (e) {
      out.add('     params=<not serialisable: $e>');
    }
    out.add('     builtSig=${f.builtSig ?? '(none — will rebuild)'}');
    if (f is BodyModifyFeature) {
      out.add('     picked edges (${f.edges.length}):');
      for (var k = 0; k < f.edges.length; k++) {
        out.add('   ${_edgeSelLine(k, f.edges[k])}');
      }
      if (f is FilletFeature) {
        out.add('     radii=${f.radii}  radii2=${f.radii2}');
      }
    }
  }
  return out;
}

/// Full state of every sketch: enough to replay the solve off-device.
List<String> sketchesDump(PartModel p) {
  final out = <String>['sketches (${p.childSketches.length}):'];
  for (final cs in p.childSketches) {
    final m = cs.model;
    out.add('--- ${m.name}  plane=${cs.plane}  visible=${_yn(cs.visible)}  '
        'shared=${_yn(cs.shared)}  rolledBack=${_yn(cs.rolledBack)}  '
        'seq=${cs.seq}');
    out.add('    eosAfter=${m.eosAfter}  layers=${m.layers}  '
        'hidden=${m.hiddenLayers.toList()}  locked=${m.lockedLayers.toList()}');
    final f = cs.face;
    if (f != null) {
      String v(double a) => a.toStringAsFixed(4);
      out.add('    face frame: origin=(${v(f.origin.x)},${v(f.origin.y)},'
          '${v(f.origin.z)}) n=(${v(f.n.x)},${v(f.n.y)},${v(f.n.z)}) '
          'key=${f.key}');
    }
    out.add('    faceRef=${cs.faceRef == null ? 'none' : 'present'}  '
        'geometryFinite=${_yn(allFinite(m.geometry))}  '
        'maxAbs=${maxAbs(m.geometry).toStringAsFixed(3)}');
    for (final l in sketchDump(m.geometry, m.constraints)) {
      out.add('    $l');
    }
  }
  return out;
}

List<String> planesDump(PartModel p) => [
      'work planes (${p.workPlanes.length}):',
      for (var i = 0; i < p.workPlanes.length; i++)
        '[$i] ${jsonEncode(p.workPlanes[i].toJson())}',
      'origin visibility: ${jsonEncode(p.vis)}',
    ];

/// The human-facing front page of the bundle.
String reportMarkdown({
  required String description,
  required DateTime when,
  required Map<String, String> env,
  required PartModel? part,
  required List<String> contents,
}) {
  final b = StringBuffer()
    ..writeln('# Bug report — ${when.toIso8601String()}')
    ..writeln();
  for (final e in env.entries) {
    b.writeln('- **${e.key}**: ${e.value}');
  }
  b
    ..writeln()
    ..writeln('## What the user saw')
    ..writeln()
    ..writeln(description.trim().isEmpty
        ? '_(no description given)_'
        : description.trim())
    ..writeln()
    ..writeln('## Triage')
    ..writeln();
  final t = triage(part);
  if (t.isEmpty) {
    b.writeln('No broken feature, no non-finite geometry, no missing body. '
        'The model is internally healthy, so the fault is in the '
        'interaction or the display — read `log.txt` around the timestamp '
        'above rather than `state.txt`.');
  } else {
    for (final l in t) {
      b.writeln('- $l');
    }
  }
  if (part != null) {
    b
      ..writeln()
      ..writeln('## Shape of the model')
      ..writeln()
      ..writeln('- part: `${part.name}`')
      ..writeln('- features: ${part.features.length} '
          '(${part.features.where((f) => f.computeError != null).length} sick)')
      ..writeln('- sketches: ${part.childSketches.length}')
      ..writeln('- work planes: ${part.workPlanes.length}');
  }
  b
    ..writeln()
    ..writeln('## Contents')
    ..writeln();
  for (final c in contents) {
    b.writeln('- $c');
  }
  return b.toString();
}

/// Assembles the members of the bundle. Pure: no filesystem, no app.
///
/// [logText] / [prevLogText] / [perfText] are passed in rather than read here
/// so the whole bundle can be built and asserted on in a host test.
Map<String, String> buildBundle({
  required String description,
  required DateTime when,
  required Map<String, String> env,
  required PartModel? part,
  String? partJson,
  Map<String, String> sketchJson = const {},
  String? logText,
  String? prevLogText,
  String? perfText,
}) {
  final files = <String, String>{};

  final contents = <String>[];
  if (partJson != null) {
    files['part.json'] = partJson;
    contents.add('`part.json` — the document itself; load this to reproduce');
  }
  for (final e in sketchJson.entries) {
    files['sketches/${e.key}.json'] = e.value;
  }
  if (sketchJson.isNotEmpty) {
    contents.add('`sketches/` — ${sketchJson.length} child sketch document(s)');
  }

  if (part != null) {
    final b = StringBuffer()
      ..writeln('part "${part.name}" state at ${when.toIso8601String()}')
      ..writeln();
    for (final l in featureDump(part)) {
      b.writeln(l);
    }
    b.writeln();
    for (final l in planesDump(part)) {
      b.writeln(l);
    }
    b.writeln();
    for (final l in sketchesDump(part)) {
      b.writeln(l);
    }
    files['state.txt'] = b.toString();
    contents.add('`state.txt` — every feature, its parameters, its solid or '
        'its error, every picked edge fingerprint, and every sketch with its '
        'full geometry and constraint list');
  }

  if (logText != null) {
    files['log.txt'] = logText;
    contents.add('`log.txt` — this session (${'\n'.allMatches(logText).length}'
        ' lines); the report was written at the END of it');
  }
  if (prevLogText != null) {
    files['log_prev.txt'] = prevLogText;
    contents.add('`log_prev.txt` — the previous session');
  }
  if (perfText != null) {
    files['perf.txt'] = perfText;
    contents.add('`perf.txt` — frame and remesh timings');
  }

  files['env.txt'] =
      env.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  contents.add('`env.txt` — build, device and backend versions');

  files['report.md'] = reportMarkdown(
    description: description,
    when: when,
    env: env,
    part: part,
    contents: contents,
  );
  return files;
}

/// Zips [files] and writes the archive to [dir]. Returns the file, or null if
/// it could not be written — a failing bug reporter must never take the app
/// down with it.
File? writeBundle(Directory dir, String stem, Map<String, String> files,
    {DateTime? when}) {
  try {
    final z = ZipWriter(stamp: when);
    // report.md first so it is what an unzip lands on.
    final ordered = <String>[
      if (files.containsKey('report.md')) 'report.md',
      ...files.keys.where((k) => k != 'report.md'),
    ];
    for (final name in ordered) {
      z.addText(name, files[name]!);
    }
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final out = File('${dir.path}/$stem.zip');
    out.writeAsBytesSync(z.finish(), flush: true);
    return out;
  } catch (_) {
    return null;
  }
}

/// A filesystem-safe stem like `bug-2026-08-03T091233`.
String bundleStem(DateTime when) {
  final s = when
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '')
      .split('T');
  return 'bug-${s[0]}T${s.length > 1 ? s[1].substring(0, 6) : '000000'}';
}
