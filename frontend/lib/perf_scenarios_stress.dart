// How far does it actually go before it breaks?
//
// WHY A SEPARATE TIER
// -------------------
// Every other scenario in this suite is sized so the bug button stays usable:
// 128 sketch entities, 360 edges, 6 features. Those sizes answer "what does
// this cost and how does it scale". They do NOT answer "what happens to a real
// part with two thousand edges and thirty features", and the honest position
// until now has been that we do not know — the exponents predict it, and an
// exponent extrapolated ten-fold is a guess with a decimal point on it.
//
// Predictions from the measured curves, for the record, so they can be checked
// against what this tier actually finds:
//
//     allEdges   n^1.93   360 edges = 1.2 s  ->  3600 edges = ~100 s
//     analysis   n^2.33    64 ents  = 26 ms  ->   512 ents  = ~3.3 s
//     rebuild    n^1.66     6 feats = 76 ms  ->    30 feats = ~1.1 s
//
// If those hold, a large part is not slow, it is unusable — and one of them is
// the crash the device already produced. Worth knowing for certain.
//
// A LADDER, NOT A SIZE
// --------------------
// Picking one big size is the wrong shape for this question: too small and it
// proves nothing, too large and the app dies before reporting anything, which
// is precisely the failure being investigated. So each probe climbs — doubling
// until it blows a time budget — and reports THE RUNG IT REACHED. "Fell over
// above 1920 edges" is a fact; "took 90 seconds" is a fact; a hang is not.
//
// OPT-IN ONLY
// -----------
// This is not in the bug-button suite. At the sizes involved a full ladder can
// take minutes, and a diagnostic that makes the app look broken while
// diagnosing it is worse than none. Type `stress` in the bug description to
// include it (see bug_capture.dart).
import 'dart:io' show ProcessInfo;

import 'ffi/occt_engine.dart';
import 'log.dart';
import 'perf.dart';
import 'perf_scenarios.dart' show PerfScenario, sketchFixture, constraintFixture,
    ringProfile;
import 'perf_scenarios_kernel.dart' show arcRing;
import 'solver.dart';

/// Per-rung ceiling. A rung slower than this ends the ladder: the next one
/// would be ~4x worse on a quadratic curve, and the point is to find the wall,
/// not to walk into it.
const _rungBudgetMs = 4000;

/// Whole-ladder ceiling, so one probe cannot eat the entire capture.
const _ladderBudgetMs = 20000;

int _rssMB() {
  try {
    return ProcessInfo.currentRss ~/ (1024 * 1024);
  } catch (_) {
    return -1;
  }
}

/// Climbs [sizes], running [body] at each, until a rung exceeds the budget.
///
/// Records per rung: `stress.<name>.<size>` (duration), and at the end
/// `stress.<name>.maxSize` plus `stress.<name>.rssMB`. A ladder that stops
/// early is the RESULT, not a failure — `maxSize` is the number being sought.
void _ladder(String name, List<int> sizes, void Function(int n) body) {
  final total = Stopwatch()..start();
  var reached = 0;
  final rss0 = _rssMB();
  for (final n in sizes) {
    if (total.elapsedMilliseconds > _ladderBudgetMs) {
      Log.w('perf', 'stress $name: ladder budget spent, stopping at $reached');
      break;
    }
    final sw = Stopwatch()..start();
    try {
      body(n);
    } catch (e) {
      Perf.count('stress.$name.threw');
      Log.w('perf', 'stress $name rung $n THREW: $e');
      break;
    }
    sw.stop();
    Perf.record('stress.$name.$n', sw.elapsedMilliseconds.toDouble());
    reached = n;
    Log.i('perf', 'stress $name rung $n: ${sw.elapsedMilliseconds} ms, '
        'rss ${_rssMB()} MB');
    if (sw.elapsedMilliseconds > _rungBudgetMs) {
      Log.w('perf', 'stress $name: rung $n blew the ${_rungBudgetMs} ms '
          'budget — this is the wall');
      break;
    }
  }
  total.stop();
  // THE number this tier exists to produce.
  Perf.gauge('stress.$name.maxSize', reached);
  Perf.gauge('stress.$name.rssDeltaMB', _rssMB() - rss0);
}

List<PerfScenario> buildStressScenarios() {
  final out = <PerfScenario>[];
  final occt = OcctFfi.instance();

  // ---- 2D: how big a sketch stays workable -------------------------------
  out.add(PerfScenario(
    'stress.sketch.analyze',
    () => _ladder('analyze', const [64, 128, 256, 512, 1024], (n) {
          final gs = sketchFixture(n ~/ 2);
          final cs = constraintFixture(n ~/ 2);
          Perf.gauge('stress.analyze.entities', gs.length);
          analyzeSketch(gs, cs);
        }),
    note: 'DOF analysis until it blows a 4 s rung. stress.analyze.maxSize is '
        'the largest sketch that still analysed — beyond it, every rebuild, '
        'solve and tab switch pays more than four seconds',
  ));

  out.add(PerfScenario(
    'stress.sketch.solve',
    () => _ladder('solve', const [64, 128, 256, 512, 1024], (n) {
          final gs = sketchFixture(n ~/ 2);
          final cs = constraintFixture(n ~/ 2);
          solveConstraints(gs, cs, iterations: 25);
        }),
    note: 'one solve at increasing sketch size; compare maxSize against '
        'stress.analyze.maxSize — whichever is smaller is the real 2D ceiling',
  ));

  out.add(PerfScenario(
    'stress.sketch.drag',
    () => _ladder('drag', const [64, 128, 256, 512], (n) {
          final gs = sketchFixture(n ~/ 2);
          final cs = constraintFixture(n ~/ 2);
          // Ten frames, not sixty: at these sizes sixty would blow the ladder
          // budget on the first rung and report nothing at all.
          final base = gs[1].data[0];
          for (var f = 0; f < 10; f++) {
            final d = List<double>.from(gs[1].data);
            d[0] = base + f * 0.5;
            gs[1] = gs[1].withData(d);
            solveConstraints(gs, cs, dragged: {(1, 0)}, iterations: 25);
          }
        }),
    note: 'TEN drag frames at increasing size. Divide by 10 for the per-frame '
        'cost and compare against 8 ms — the size where that is exceeded is '
        'where dragging stops being smooth',
  ));

  if (occt == null) return out;

  // ---- 3D: the one that produced the crash -------------------------------
  //
  // The ladder is in PROFILE POINTS; edges are 3x that. 640 profile points is
  // 1920 edges, which is the neighbourhood of the part that died.
  out.add(PerfScenario(
    'stress.kernel.allEdges',
    () => _ladder('allEdges', const [120, 240, 480, 960, 1920], (n) {
          final s = occt.extrudeProfileArcs([ringProfile(n, 40)], 10.0);
          if (s == null) {
            Perf.count('stress.allEdges.buildFailed');
            return;
          }
          try {
            Perf.gauge('stress.allEdges.edges', s.edgeCount);
            s.allEdges();
          } finally {
            s.dispose();
          }
        }),
    note: 'THE one. Edge enumeration until it blows the budget. '
        'stress.allEdges.edges is the edge count of the last rung that '
        'finished — the device part that crashed carried roughly 3400',
  ));

  // The same ladder without allEdges, to prove the wall is enumeration and
  // not merely "big solids are slow".
  out.add(PerfScenario(
    'stress.kernel.buildOnly',
    () => _ladder('buildOnly', const [120, 240, 480, 960, 1920], (n) {
          final s = occt.extrudeProfileArcs([ringProfile(n, 40)], 10.0);
          if (s == null) return;
          try {
            Perf.gauge('stress.buildOnly.edges', s.edgeCount);
            s.counts();
            s.mesh(linDeflection: 0.2);
          } finally {
            s.dispose();
          }
        }),
    note: 'the CONTROL for stress.kernel.allEdges: same solids, built and '
        'tessellated but never enumerated. If this ladder climbs far higher, '
        'the ceiling belongs to edge enumeration alone',
  ));

  // ---- lots of solids ----------------------------------------------------
  //
  // "Many solids" is a different axis from "one complicated solid", and it is
  // the one that decides whether a part with thirty features opens at all. RSS
  // is sampled per rung because this is where memory, not time, is expected to
  // end the run.
  out.add(PerfScenario(
    'stress.manySolids',
    () => _ladder('manySolids', const [4, 8, 16, 32, 64], (n) {
          final held = <OcctShape>[];
          try {
            var tris = 0;
            for (var i = 0; i < n; i++) {
              final s = occt.extrudeProfileArcs(
                  [arcRing(48, 20 + i * 2.0)], 10.0);
              if (s == null) continue;
              held.add(s);
              final m = s.mesh(linDeflection: 0.2);
              if (m != null) tris += m.triangleCount;
            }
            Perf.gauge('stress.manySolids.held', held.length);
            Perf.gauge('stress.manySolids.tris', tris);
            Perf.gauge('stress.manySolids.rssMB', _rssMB());
          } finally {
            // Held SIMULTANEOUSLY, as a part holds its bodies — that is the
            // whole point — and released together. Disposing as we go would
            // measure a sequence of one-solid parts.
            for (final s in held) {
              s.dispose();
            }
          }
        }),
    note: 'N solids alive at once, meshed, as a multi-body part holds them. '
        'Watch stress.manySolids.rssMB and rssDeltaMB: if this ladder ends on '
        'memory rather than time, that is the ceiling on part size',
  ));

  out.add(PerfScenario(
    'stress.booleanChain',
    () => _ladder('boolChain', const [4, 8, 16, 32], (n) {
          var acc = occt.makeBox(80, 80, 12);
          if (acc == null) return;
          try {
            for (var i = 0; i < n; i++) {
              final b = occt.makeCylinder(
                  -30 + (i % 8) * 8.0, -30 + (i ~/ 8) * 8.0, -2, 3, 20);
              if (b == null) continue;
              final next = occt.fuse(acc!, b);
              b.dispose();
              if (next == null) continue;
              acc!.dispose();
              acc = next;
            }
            Perf.gauge('stress.boolChain.edges', acc?.edgeCount ?? -1);
          } finally {
            acc?.dispose();
          }
        }),
    note: 'a feature tree N deep, fusing onto one accumulating body. The edge '
        'gauge says how complicated the result got; if the ladder stops early '
        'the tree depth is the limit, not the individual booleans',
  ));

  return out;
}

/// Runs the stress tier. Deliberately NOT called by the ordinary suite.
Map<String, dynamic> runStressSuite() {
  final results = <Map<String, dynamic>>[];
  final sw = Stopwatch()..start();
  for (final s in buildStressScenarios()) {
    Log.i('perf', 'stress scenario ${s.name}');
    // NO warmup. A warmup pass would double the wall time of the most
    // expensive thing in the whole suite, and these ladders are self-limiting
    // rather than precision measurements — the rung reached matters, the third
    // significant figure does not.
    final r = Perf.scenario(s.name, s.run);
    r['note'] = s.note;
    results.add(r);
  }
  sw.stop();
  return {
    'suite': 'perf_scenarios_stress/v1',
    'at': DateTime.now().toIso8601String(),
    'build': Log.build,
    'wallMs': sw.elapsedMilliseconds,
    'occtAvailable': OcctFfi.available,
    'scenarios': results,
  };
}
