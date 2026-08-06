// The app measuring itself, on the real device, without anyone tapping.
//
// WHY THIS EXISTS
// ---------------
// A hand-driven session answers "what happened while I was using it". It
// cannot answer "what does ONE fillet cost on a 400-edge solid", because every
// number is entangled with everything else that happened, the inputs are never
// the same twice, and a human cannot drive the same drag reproducibly. The
// first real device session (M210) proved the point: it found a 15.8-second
// freeze and could not say what the cost curve behind it looked like.
//
// So the app drives itself. Each scenario is a fixed input, a fixed action and
// a bracketed measurement (see Perf.scenario), and the whole suite writes one
// JSON file that can be diffed against a baseline or against another device.
//
// WHAT IS DELIBERATELY NOT HERE
// -----------------------------
// Anything needing a widget tree, a Canvas or a gesture: paint phases, snap on
// a live drag, platform-view traffic. Those need the UI layer and belong in a
// second runner driven from a debug screen. Everything here runs headless,
// which is what makes it usable from a unit test, from CI, and from a device
// button with the same code.
//
// THE NUMBERS THAT SURVIVE A CHIP CHANGE
// --------------------------------------
// Milliseconds on an M4 iPad say little about an A-series one. Call counts,
// edge counts, allocation counts and iteration counts are the same everywhere.
// Every scenario therefore reports COUNTERS next to durations, and the sweeps
// below report a cost CURVE rather than a single number — a curve's shape
// (linear vs quadratic) is a property of the algorithm, not of the silicon.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'constraints.dart';
import 'ffi/occt_engine.dart';
import 'ffi/qcad_engine.dart';
import 'gear.dart';
import 'log.dart';
import 'perf.dart';
import 'solver.dart';

/// One measured case.
class PerfScenario {
  const PerfScenario(this.name, this.run, {this.note = ''});

  /// Stable identity — the key a baseline is diffed on. Never rename lightly.
  final String name;
  final void Function() run;

  /// What a reader should take from this scenario's numbers.
  final String note;
}

// ---------------------------------------------------------------------------
// Fixtures — deterministic, and sized S / M / L so a cost CURVE is visible
// rather than a single point.
// ---------------------------------------------------------------------------

/// [n] circles on a ring plus [n] connecting lines. No randomness: the same
/// input on every device and every run, which is what makes a diff meaningful.
List<Geo> sketchFixture(int n) {
  final out = <Geo>[];
  for (var i = 0; i < n; i++) {
    final a = 2 * math.pi * i / n;
    final cx = 60 * math.cos(a), cy = 60 * math.sin(a);
    out.add(Geo(Geo.circle, [cx, cy, 4.0]));
  }
  for (var i = 0; i < n; i++) {
    final a1 = 2 * math.pi * i / n, a2 = 2 * math.pi * ((i + 1) % n) / n;
    out.add(Geo(Geo.line, [
      60 * math.cos(a1), 60 * math.sin(a1),
      60 * math.cos(a2), 60 * math.sin(a2),
    ]));
  }
  return out;
}

/// Equal-radius constraints across consecutive circles plus horizontal pins.
/// Enough coupling that the solver cannot treat them independently, which is
/// what makes the cost scale the way a real sketch does.
List<Constraint> constraintFixture(int nCircles) {
  final cs = <Constraint>[];
  for (var i = 0; i + 1 < nCircles; i++) {
    cs.add(Constraint(CType.equal, ents: [i, i + 1]));
  }
  return cs;
}

/// One involute gear as the app stores it: two defining vertices plus the
/// parameter block. [teeth] drives the tooth count; everything else mirrors
/// the values found in the crashing part (module 2, 20°, root fillets on).
Geo gearFixture({int teeth = 20, double module = 2.0}) => Geo(
      Geo.polyline,
      [
        1.0, 2.0, // count=2 header as the app packs it
        0.0, 0.0, // centre
        20.0, 0.0, // orientation handle
        module, teeth.toDouble(), 20.0, 0.0, 0.0, 0.0,
        1.0, 0.38, 0.12, 0.0, // internal=0, fillet on, rfc, trc, cr
      ],
      spline: Geo.gearTag,
    );

/// A closed polygon profile with [n] points, as (x, y, bulge) triplets — the
/// encoding `extrudeProfileArcs` expects.
List<double> ringProfile(int n, double r) {
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    final a = 2 * math.pi * i / n;
    out..add(r * math.cos(a))..add(r * math.sin(a))..add(0.0);
  }
  return out;
}

// ---------------------------------------------------------------------------
// The suite
// ---------------------------------------------------------------------------

List<PerfScenario> buildScenarios() {
  final out = <PerfScenario>[];

  // ---- solver ------------------------------------------------------------
  // Three sizes, so the report shows how solve cost grows rather than what it
  // was once. The device session measured avg 27 ms and a 3.92 s worst; only a
  // sweep can say whether that tail is size-driven or a degenerate case.
  for (final n in const [8, 24, 64]) {
    out.add(PerfScenario(
      'solve.sweep.$n',
      () {
        final gs = sketchFixture(n);
        final cs = constraintFixture(n);
        for (var i = 0; i < 10; i++) {
          solveConstraints(gs, cs, iterations: 25);
        }
      },
      note: 'solve cost vs sketch size; compare totalMs across the three sizes',
    ));
  }

  // Drag solve: the path that runs inside CustomPainter.paint. Same wish, 60
  // frames, which is one second of dragging.
  out.add(PerfScenario(
    'solve.drag60',
    () {
      final gs = sketchFixture(24);
      final cs = constraintFixture(24);
      for (var f = 0; f < 60; f++) {
        solveConstraints(gs, cs, dragged: {(0, 0)}, iterations: 25);
      }
    },
    note: 'one second of dragging at 60 fps; divide totalMs by 60 for per-frame',
  ));

  // ---- gear curve generation --------------------------------------------
  // The crashing part carried four 20-tooth gears whose loops arrived at OCCT
  // as ~1200 points each. This measures the Dart side of that, and how it
  // scales with tooth count.
  for (final t in const [10, 20, 40]) {
    out.add(PerfScenario(
      'gear.curve.$t',
      () {
        final g = gearFixture(teeth: t);
        for (var i = 0; i < 20; i++) {
          Perf.span('gear.curve', () => gearCurve(g));
        }
      },
      note: 'gear outline generation; points scale with teeth',
    ));
  }

  final occt = OcctFfi.instance();
  if (occt != null) {
    // ---- THE ONE THAT MATTERS ------------------------------------------
    //
    // allEdges was 85.7% of a session and produced a 15.8 s freeze, and the
    // app died inside it on the bigger part. The open question is the SHAPE of
    // the curve: linear in edge count means crossing overhead, superlinear
    // means occt_shape_edge_info re-walks the topology per call and the fix is
    // a different one entirely. A sweep answers that in one run, on any chip.
    for (final n in const [12, 48, 120]) {
      out.add(PerfScenario(
        'kernel.allEdges.sweep.$n',
        () {
          final s = occt.extrudeProfileArcs([ringProfile(n, 40)], 5.0);
          if (s == null) return;
          try {
            Perf.gauge('sweep.profilePts', n);
            Perf.gauge('sweep.edgeCount', s.edgeCount);
            s.allEdges();
          } finally {
            s.dispose();
          }
        },
        note: 'edge enumeration vs edge count — LINEAR or QUADRATIC is the '
            'whole question; compare avgMs against sweep.edgeCount',
      ));
    }

    // Same solid, edge enumeration repeated: is there per-call setup that a
    // cache would remove, or is every call equally expensive?
    out.add(PerfScenario(
      'kernel.allEdges.repeat',
      () {
        final s = occt.extrudeProfileArcs([ringProfile(48, 40)], 5.0);
        if (s == null) return;
        try {
          for (var i = 0; i < 5; i++) {
            s.allEdges();
          }
        } finally {
          s.dispose();
        }
      },
      note: 'five enumerations of one solid; flat avg means no reusable setup',
    ));

    // ---- kernel primitives ---------------------------------------------
    out.add(PerfScenario(
      'kernel.extrude.sweep',
      () {
        for (final n in const [12, 48, 120, 300]) {
          final s = occt.extrudeProfileArcs([ringProfile(n, 40)], 5.0);
          s?.dispose();
        }
      },
      note: 'extrude cost vs profile point count',
    ));

    out.add(PerfScenario(
      'kernel.boolean',
      () {
        final a = occt.makeBox(40, 40, 10);
        final b = occt.makeCylinder(20, 20, -5, 8, 20);
        if (a == null || b == null) {
          a?.dispose();
          b?.dispose();
          return;
        }
        try {
          for (var i = 0; i < 5; i++) {
            occt.fuse(a, b)?.dispose();
            occt.cut(a, b)?.dispose();
            occt.common(a, b)?.dispose();
          }
        } finally {
          a.dispose();
          b.dispose();
        }
      },
      note: 'fuse/cut/common on a trivial pair — the floor cost of a boolean',
    ));

    out.add(PerfScenario(
      'kernel.fillet',
      () {
        final s = occt.extrudeProfileArcs([ringProfile(24, 40)], 10.0);
        if (s == null) return;
        try {
          final edges = s.allEdges().where((e) => e.filletable).toList();
          Perf.gauge('fillet.candidates', edges.length);
          if (edges.isEmpty) return;
          final ids = [for (final e in edges.take(4)) e.index];
          s.filletEdges(ids, [for (final _ in ids) 1.0])?.dispose();
        } finally {
          s.dispose();
        }
      },
      note: 'fillet incl. the allEdges needed to find candidates — the real '
          'cost of the user action, not just the kernel call',
    ));

    // Tessellation: the two halves are measured separately (meshCreate is
    // OCCT, meshCopyOut is Dart crossing the boundary) because they grow for
    // different reasons and are fixed in different places.
    out.add(PerfScenario(
      'kernel.mesh.sweep',
      () {
        for (final d in const [0.5, 0.2, 0.05]) {
          final s = occt.extrudeProfileArcs([ringProfile(48, 40)], 10.0);
          if (s == null) continue;
          try {
            final m = s.mesh(linDeflection: d);
            if (m != null) Perf.gauge('mesh.tris.last', m.triangleCount);
          } finally {
            s.dispose();
          }
        }
      },
      note: 'tessellation vs deflection; meshCreate is OCCT, meshCopyOut is '
          'the Dart copy — compare the two',
    ));
  }

  return out;
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

/// Runs every scenario and returns the report.
///
/// [warmup] runs each scenario once, unmeasured, first. Without it the first
/// scenario carries every one-time cost in the process — lazy FFI symbol
/// resolution, the first OCCT allocation, JIT warmup on a debug build — and
/// reads as though it were slow.
Map<String, dynamic> runPerfSuite({bool warmup = true}) {
  final scenarios = buildScenarios();
  final results = <Map<String, dynamic>>[];
  final sw = Stopwatch()..start();

  for (final s in scenarios) {
    if (warmup) {
      try {
        s.run();
      } catch (_) {/* the measured pass records the error */}
    }
    Log.i('perf', 'scenario ${s.name}');
    final r = Perf.scenario(s.name, s.run);
    r['note'] = s.note;
    results.add(r);
  }
  sw.stop();

  return {
    'suite': 'perf_scenarios/v1',
    'at': DateTime.now().toIso8601String(),
    'build': Log.build,
    'os': Platform.operatingSystemVersion,
    'wallMs': sw.elapsedMilliseconds,
    'occtAvailable': OcctFfi.available,
    'scenarios': results,
  };
}

/// Runs the suite and writes it next to the perf log. Returns the path, or ''.
String runAndWritePerfSuite({String? documentsDir}) {
  try {
    final report = runPerfSuite();
    var dir = documentsDir;
    if (dir == null) {
      final p = Perf.path;
      dir = p.isEmpty ? Directory.systemTemp.path : File(p).parent.path;
    }
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '')
        .substring(0, 15);
    final f = File('$dir/perf_suite_$stamp.json');
    f.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(report), flush: true);
    Log.i('perf', 'scenario suite written: ${f.path}');
    return f.path;
  } catch (e, st) {
    Log.e('perf', 'scenario suite FAILED', e, st);
    return '';
  }
}
