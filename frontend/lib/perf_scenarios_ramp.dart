// Gradual ramps: the SHAPE of a cost curve, not two points and a line.
//
// WHY THE SWEEPS WERE NOT ENOUGH
// ------------------------------
// The sweeps measure three sizes and the report fits n^k through them. That is
// enough to say "superlinear" and rank the offenders, and it is what found the
// quadratic in `allEdges` and the n^2.33 in the DOF analysis.
//
// It cannot show a KNEE. A power-law fit through three points assumes the curve
// IS a power law, and silently averages away anything that is not: a cache that
// stops working above a size, a solver that starts rejecting native results, an
// allocator that changes behaviour, a threshold inside OCCT. Those are not
// hypothetical here — the device data already showed the constraint solver
// costing 0.277 ms on one path and 92.5 ms on another, a 334x cliff that no
// exponent through three points would ever reveal.
//
// So these ramp in small steps and record EVERY rung as its own span, plus the
// LOCAL exponent between consecutive rungs. A curve whose local exponent is
// flat is a genuine power law; one whose local exponent jumps has a knee, and
// the rung where it jumps is the size that matters.
//
// AND THEY RECORD WHICH PATH WAS TAKEN
// ------------------------------------
// For the solver ramps the `solve.path.*` counters are captured per rung. That
// answers the question the cliff raises: at what size does a sketch stop being
// solvable by libslvs and fall onto the Dart fallback? An average over the
// whole ramp cannot answer it; a per-rung count can.
//
// COST
// ----
// A geometric ramp is dominated by its top rung — the sum of all the smaller
// ones is typically under twice the largest — so this buys the shape of a
// curve for roughly double the price of its endpoint. Each ramp still carries
// a budget, and skips its remaining rungs rather than let the ordinary capture
// become a stress run.
import 'dart:math' as math;

import 'constraints.dart';
import 'ffi/occt_engine.dart';
import 'log.dart';
import 'perf.dart';
import 'perf_scenarios.dart'
    show PerfScenario, sketchFixture, constraintFixture, ringProfile;
import 'solver.dart';

/// Per-ramp ceiling. Generous enough for the shape to emerge, small enough
/// that the ordinary capture stays a capture.
const _rampBudgetMs = 3500;

/// Runs [body] at every size in [sizes], recording each rung separately.
///
/// Records `ramp.<name>.<n>` per rung and, between consecutive rungs, the
/// LOCAL exponent as `ramp.<name>.k.<n>` (scaled by 100, because gauges are
/// integers — 233 means n^2.33). The local exponent is the point of the whole
/// exercise: a constant one means a clean power law, a rising one means the
/// curve is getting worse than any single fit suggests, and a jump means a
/// threshold was crossed at that rung.
void _ramp(String name, List<int> sizes, void Function(int n) body) {
  final total = Stopwatch()..start();
  int? prevN;
  double? prevMs;
  for (final n in sizes) {
    if (total.elapsedMilliseconds > _rampBudgetMs) {
      Perf.gauge('ramp.$name.truncatedAt', n);
      Log.i('perf', 'ramp $name: budget spent, stopping before rung $n');
      break;
    }
    final sw = Stopwatch()..start();
    try {
      body(n);
    } catch (e) {
      Perf.count('ramp.$name.threw');
      Log.w('perf', 'ramp $name rung $n threw: $e');
      break;
    }
    sw.stop();
    final ms = sw.elapsedMicroseconds / 1000.0;
    Perf.record('ramp.$name.$n', ms);
    // Local slope in log-log space, i.e. the exponent over THIS step alone.
    if (prevN != null && prevMs != null && prevMs > 0.01 && ms > 0.01) {
      final k = math.log(ms / prevMs) / math.log(n / prevN);
      Perf.gauge('ramp.$name.k.$n', (k * 100).round());
    }
    prevN = n;
    prevMs = ms;
  }
  Perf.gauge('ramp.$name.rungs', sizes.length);
}

/// Captures which solver path the rung took. See solver.dart — a sketch that
/// falls off libslvs costs 334x more, and the ramp is where that transition
/// becomes visible.
void _pathAt(String name, int n) {
  for (final p in const ['slvs', 'lm-frozen', 'lm-relaxed', 'lm']) {
    final v = Perf.counters['solve.path.$p'];
    if (v != null) Perf.gauge('ramp.$name.path.$p.$n', v);
  }
}

List<PerfScenario> buildRampScenarios() {
  final out = <PerfScenario>[];

  // ---- 2D: entity count, in small steps ----------------------------------
  //
  // Entity counts, not fixture sizes: sketchFixture(n) produces 2n entities,
  // and a ramp labelled in the units a user thinks in is a ramp whose numbers
  // can be acted on.
  const entitySteps = [8, 16, 24, 32, 48, 64, 96, 128, 192, 256];

  out.add(PerfScenario(
    'ramp.solve.entities',
    () => _ramp('solve', entitySteps, (n) {
          final gs = sketchFixture(n ~/ 2);
          final cs = constraintFixture(n ~/ 2);
          Perf.gauge('ramp.solve.cons.$n', cs.length);
          solveConstraints(gs, cs, iterations: 25);
          _pathAt('solve', n);
        }),
    note: 'one solve from 8 to 256 entities in ten steps. Read '
        'ramp.solve.k.<n> for the LOCAL exponent — a jump between two rungs is '
        'a threshold, which a three-point fit averages away. '
        'ramp.solve.path.*.<n> says whether that rung stayed on libslvs',
  ));

  out.add(PerfScenario(
    'ramp.analyze.entities',
    () => _ramp('analyze', entitySteps, (n) {
          final gs = sketchFixture(n ~/ 2);
          final cs = constraintFixture(n ~/ 2);
          analyzeSketch(gs, cs);
        }),
    note: 'the DOF analysis over the same ten sizes. It is the steepest curve '
        'in 2D (n^2.33 from the coarse sweep); this says whether that exponent '
        'is constant or itself growing with size',
  ));

  out.add(PerfScenario(
    'ramp.drag.entities',
    () => _ramp('drag', const [8, 16, 24, 32, 48, 64, 96, 128], (n) {
          final gs = sketchFixture(n ~/ 2);
          final cs = constraintFixture(n ~/ 2);
          final base = gs[1].data[0];
          // Ten frames per rung: enough to be a drag rather than a single
          // solve, few enough that the ramp stays inside its budget.
          for (var f = 0; f < 10; f++) {
            final d = List<double>.from(gs[1].data);
            d[0] = base + f * 0.5;
            gs[1] = gs[1].withData(d);
            solveConstraints(gs, cs, dragged: {(1, 0)}, iterations: 25);
          }
          _pathAt('drag', n);
        }),
    note: 'TEN drag frames per rung. Divide a rung by 10 for the per-frame '
        'cost; the rung where that crosses 8 ms is where dragging stops being '
        'smooth on a 120 Hz display',
  ));

  // ---- 2D: constraint DENSITY at a fixed entity count ---------------------
  //
  // The other axis entirely, and one nothing has measured. Two sketches with
  // the same number of entities behave completely differently at 0.5 and 3
  // constraints per entity, and it is density — not entity count — that
  // decides whether the solver stays on its fast path.
  out.add(PerfScenario(
    'ramp.solve.density',
    () => _ramp('density', const [1, 2, 3, 4, 6, 8], (mult) {
          final gs = sketchFixture(32);
          final cs = <Constraint>[];
          // Stack the base fixture's constraints `mult` times over. Repeats
          // are REDUNDANT rather than contradictory, which is the realistic
          // way a sketch becomes over-constrained: nobody adds a conflict on
          // purpose, they add the same relationship twice by different routes.
          for (var i = 0; i < mult; i++) {
            cs.addAll(constraintFixture(32));
          }
          Perf.gauge('ramp.density.cons.$mult', cs.length);
          solveConstraints(gs, cs, iterations: 25);
          _pathAt('density', mult);
        }),
    note: 'SAME 64 entities, 1x to 8x the constraints. This is the axis that '
        'produces the 334x cliff: watch ramp.density.path.lm-*.<n> for the '
        'multiplier at which libslvs stops being trusted and the Dart '
        'fallback takes over',
  ));

  final occt = OcctFfi.instance();
  if (occt == null) return out;

  // ---- 3D: profile complexity, in small steps ----------------------------
  //
  // The cheap operations ramp high; `allEdges` is deliberately given a shorter
  // ramp because it is the known quadratic and a top rung there costs seconds.
  const profileSteps = [12, 24, 36, 48, 72, 96, 144, 192, 288];

  out.add(PerfScenario(
    'ramp.kernel.build',
    () => _ramp('build', profileSteps, (n) {
          final s = occt.extrudeProfileArcs([ringProfile(n, 40)], 10.0);
          if (s == null) {
            Perf.count('ramp.build.failed');
            return;
          }
          try {
            Perf.gauge('ramp.build.edges.$n', s.edgeCount);
          } finally {
            s.dispose();
          }
        }),
    note: 'extrude from 12 to 288 profile points. The coarse sweep called this '
        'linear (n^0.99); nine rungs say whether it stays linear all the way '
        'or bends somewhere',
  ));

  out.add(PerfScenario(
    'ramp.kernel.mesh',
    () => _ramp('mesh', profileSteps, (n) {
          final s = occt.extrudeProfileArcs([ringProfile(n, 40)], 10.0);
          if (s == null) return;
          try {
            final m = s.mesh(linDeflection: 0.2);
            if (m != null) Perf.gauge('ramp.mesh.tris.$n', m.triangleCount);
          } finally {
            s.dispose();
          }
        }),
    note: 'tessellation over the same nine sizes, with the triangle count per '
        'rung so cost can be read per triangle rather than per profile point',
  ));

  out.add(PerfScenario(
    'ramp.kernel.allEdges',
    () => _ramp('allEdges', const [12, 24, 36, 48, 72, 96, 144], (n) {
          final s = occt.extrudeProfileArcs([ringProfile(n, 40)], 10.0);
          if (s == null) return;
          try {
            Perf.gauge('ramp.allEdges.edges.$n', s.edgeCount);
            s.allEdges();
          } finally {
            s.dispose();
          }
        }),
    note: 'the known quadratic, at seven sizes rather than three. A LOCAL '
        'exponent that stays near 2 confirms a clean n-squared; one that '
        'climbs means it is worse than quadratic at scale',
  ));

  out.add(PerfScenario(
    'ramp.kernel.boolean',
    () => _ramp('boolean', const [12, 24, 36, 48, 72, 96, 144], (n) {
          final a = occt.extrudeProfileArcs([ringProfile(n, 40)], 10.0);
          final b = occt.extrudeProfileArcs([ringProfile(n, 25)], 20.0);
          if (a == null || b == null) {
            a?.dispose();
            b?.dispose();
            return;
          }
          try {
            occt.fuse(a, b)?.dispose();
          } finally {
            a.dispose();
            b.dispose();
          }
        }),
    note: 'one fuse at seven operand complexities. The coarse sweep called '
        'booleans linear; this is where that either holds or breaks',
  ));

  // ---- 3D: number of solids alive at once --------------------------------
  out.add(PerfScenario(
    'ramp.solids',
    () => _ramp('solids', const [1, 2, 4, 6, 8, 12, 16], (n) {
          final held = <OcctShape>[];
          try {
            var tris = 0;
            for (var i = 0; i < n; i++) {
              final s =
                  occt.extrudeProfileArcs([ringProfile(48, 20 + i * 2.0)], 10.0);
              if (s == null) continue;
              held.add(s);
              final m = s.mesh(linDeflection: 0.2);
              if (m != null) tris += m.triangleCount;
            }
            Perf.gauge('ramp.solids.tris.$n', tris);
          } finally {
            for (final s in held) {
              s.dispose();
            }
          }
        }),
    note: 'N solids built and meshed while all are held alive, as a multi-body '
        'part holds them. A local exponent above 1 here means solids are not '
        'independent — that each additional body costs more than the last',
  ));

  return out;
}
