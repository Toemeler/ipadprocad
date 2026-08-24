// Profile COMPLEXITY ladders — the axis no tier has ever climbed.
//
// WHY THIS FILE EXISTS
// --------------------
// A user swept a real profile and waited five minutes twenty-three seconds.
// `ffi.occt.sweepProfile` reached 102 244 ms on one call. The suite's recorded
// figure for that same operation is 81.9 ms mean, 392 ms worst — a factor of
// 1250 between what was measured and what happens.
//
// The suite was not wrong. It was pointed at the wrong sizes. Its only sweep
// ladder is
//
//     for (final n in const [12, 48])      // perf_scenarios_kernel.dart
//
// — two rungs, topping out at 48 profile points, against a field profile of
// ~1218 segments. The stress tier climbs `allEdges` to 5 760 edges and
// `analyze` to 1 024 entities and sweeps NOTHING. So the operation that ate
// 53 % of a real session had no instrument pointed at it at any size a real
// part reaches.
//
// That is the generalisable lesson, and it is worth more than the sweep fix:
// a ladder finds the wall it is pointed at. These ladders are pointed at
// PROFILE COMPLEXITY — segment count, path resolution, loop count and
// self-intersection count — because that is the axis a real drawing grows
// along, and the axis every existing tier holds constant.
//
// TWO RUNGS CANNOT SHOW A KNEE
// ----------------------------
// The existing sweep ladder has two rungs, so any fit through it is a straight
// line by construction. Whether the sweep is linear with a huge constant or
// quadratic with a small one is the whole question, and two points cannot
// answer it. Every ladder here has at least four.
//
// WHY THIS IS OPT-IN, LIKE `stress`
// ---------------------------------
// At the field's cost one 1200-segment rung is ~100 s. Putting that in the
// ordinary suite would make every capture unusable and would silently change
// what every historical number means. `runProfileSuite()` is called by nothing
// in the ordinary path — same contract as `runStressSuite()`.
//
// AND IT ONLY ADDS
// ----------------
// No existing scenario's name, body or note changes here or in
// `perf_scenarios_kernel.dart`. An edited scenario rewrites the meaning of
// every number ever recorded under its name; an added one cannot.
import 'dart:io';
import 'dart:math' as math;

import 'ffi/occt_engine.dart';
import 'ffi/qcad_engine.dart' show Geo;
import 'log.dart';
import 'part_model.dart' show ProfileInput, profileLoopCount;
import 'perf.dart';
import 'perf_scenarios.dart' show PerfScenario;
import 'perf_scenarios_kernel.dart' show arcRing, arcPath, identityMat34;

// ---------------------------------------------------------------------------
// Budgets
// ---------------------------------------------------------------------------

/// Per-rung ceiling. Deliberately far above the stress tier's 4 s: the whole
/// point is to reach the size the field reached, and the field's single sweep
/// cost 102 s. A 4 s budget would stop this ladder at the rung BELOW the one
/// that matters and reproduce exactly the blind spot the file exists to fix.
const _rungBudgetMs = 150000;

/// Whole-ladder ceiling. Five rungs of a superlinear curve, with the top one
/// allowed to cost what the field cost.
const _ladderBudgetMs = 420000;

/// Cheap ladders (pure Dart, no kernel) get the ordinary budgets — nothing in
/// the 2D arrangement should take a minute, and if it does that is the finding.
const _cheapRungBudgetMs = 8000;
const _cheapLadderBudgetMs = 40000;

int _rssMB() {
  try {
    return ProcessInfo.currentRss ~/ (1024 * 1024);
  } catch (_) {
    return -1;
  }
}

/// Climbs [sizes], running [body] at each, until a rung exceeds its budget.
///
/// Records `profile.<name>.<size>` per rung and `profile.<name>.maxSize` at the
/// end. A ladder that stops early is the RESULT, not a failure: `maxSize` is
/// the number being sought, exactly as in the stress tier.
///
/// This is a local copy of the stress tier's ladder rather than an import:
/// `perf_scenarios_stress.dart` belongs to another session, its `_ladder` is
/// private to it, and the budgets here differ by two orders of magnitude for
/// the reason given above.
void _ladder(String name, List<int> sizes, void Function(int n) body,
    {int rungBudgetMs = _rungBudgetMs, int ladderBudgetMs = _ladderBudgetMs}) {
  final total = Stopwatch()..start();
  var reached = 0;
  final rss0 = _rssMB();
  for (final n in sizes) {
    if (total.elapsedMilliseconds > ladderBudgetMs) {
      Log.w('perf', 'profile $name: ladder budget spent, stopping at $reached');
      break;
    }
    final sw = Stopwatch()..start();
    try {
      body(n);
    } catch (e) {
      Perf.count('profile.$name.threw');
      Log.w('perf', 'profile $name rung $n THREW: $e');
      break;
    }
    sw.stop();
    Perf.record('profile.$name.$n', sw.elapsedMilliseconds.toDouble());
    reached = n;
    Log.i(
        'perf',
        'profile $name rung $n: ${sw.elapsedMilliseconds} ms, '
            'rss ${_rssMB()} MB');
    if (sw.elapsedMilliseconds > rungBudgetMs) {
      Log.w('perf',
          'profile $name: rung $n blew the $rungBudgetMs ms budget — the wall');
      break;
    }
  }
  total.stop();
  Perf.gauge('profile.$name.maxSize', reached);
  Perf.gauge('profile.$name.rssDeltaMB', _rssMB() - rss0);
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// A closed polyline [Geo] through [pts] given as flat (x, y) pairs.
Geo _closedPoly(List<double> pts) =>
    Geo(Geo.polyline, [1.0, (pts.length ~/ 2).toDouble(), ...pts]);

/// A [ProfileInput] over [geo] with no layer rules in play.
///
/// `layers` empty means `_profileGeo`'s `layers.indexOf` returns -1 and the
/// End-of-Sketch check is skipped, so every entity counts as profile geometry.
/// That is what a measurement wants: the layer rules are not on this axis.
ProfileInput _input(List<Geo> geo) =>
    ProfileInput(geo, const <String>[], const <String>{}, 0);

/// A simple convex closed polygon of [n] vertices — zero self-intersections,
/// exactly one bounded face.
List<double> convexLoop(int n, double r) {
  final out = <double>[];
  for (var i = 0; i < n; i++) {
    final a = 2 * math.pi * i / n;
    out..add(r * math.cos(a))..add(r * math.sin(a));
  }
  return out;
}

/// The star polygon {[points]/2}, optionally subdivided.
///
/// WHY A STAR: its self-intersection count is known exactly rather than
/// measured. For a star polygon {n/m} with gcd(n, m) = 1 the number of
/// transversal self-crossings is n(m - 1), so {n/2} with n ODD crosses itself
/// exactly n times. The pentagram is the familiar case: 5 crossings, and 6
/// bounded faces (five points and the middle) = crossings + 1.
///
/// That identity — bounded faces == crossings + 1 — is Euler's formula for a
/// planar graph: k crossings add k vertices and split 2k edges, so
/// F = E - V + 2 = (n + 2k) - (n + k) + 2 = k + 2, one of which is unbounded.
/// It is what `profile.loops.selfIntersect` checks, and it is what says whether
/// the field's 110 zero-area loops were crossings or snapping artefacts.
///
/// [subdiv] splits each edge into that many straight pieces. It changes the
/// VERTEX count without changing the crossing count, which is how this fixture
/// reproduces the field's shape: ~1200 vertices carrying ~110 crossings.
List<double> starLoop(int points, double r, {int subdiv = 1}) {
  assert(points.isOdd,
      'gcd(points, 2) must be 1 for the crossing count to hold');
  final verts = <double>[];
  for (var i = 0; i < points; i++) {
    final k = (i * 2) % points;
    final a = 2 * math.pi * k / points;
    verts..add(r * math.cos(a))..add(r * math.sin(a));
  }
  if (subdiv <= 1) return verts;
  final out = <double>[];
  for (var i = 0; i < points; i++) {
    final x0 = verts[2 * i], y0 = verts[2 * i + 1];
    final j = (i + 1) % points;
    final x1 = verts[2 * j], y1 = verts[2 * j + 1];
    for (var s = 0; s < subdiv; s++) {
      final t = s / subdiv;
      out..add(x0 + (x1 - x0) * t)..add(y0 + (y1 - y0) * t);
    }
  }
  return out;
}

/// [n] disjoint square loops — the LOOP-COUNT axis with the segment count held
/// as low as it can go (4 per loop).
///
/// Squares rather than circles on purpose. `_profileChain` samples a circle at
/// 96 points, so 512 circles would be 49 152 segments and this ladder would be
/// measuring the segment axis over again under a different name. Four segments
/// per loop keeps the two axes apart, which is the only way either fit means
/// anything. (The 96-per-circle multiplier is itself worth knowing, and
/// `profile.loops.segments` prices it.)
List<Geo> squareGrid(int n, {double side = 4, double pitch = 10}) {
  final out = <Geo>[];
  final cols = _isqrt(n) + 1;
  for (var i = 0; i < n; i++) {
    final cx = (i % cols) * pitch, cy = (i ~/ cols) * pitch;
    final h = side / 2;
    out.add(_closedPoly([
      cx - h, cy - h, //
      cx + h, cy - h, //
      cx + h, cy + h, //
      cx - h, cy + h,
    ]));
  }
  return out;
}

int _isqrt(int n) {
  var r = 0;
  while ((r + 1) * (r + 1) <= n) {
    r++;
  }
  return r;
}

// ---------------------------------------------------------------------------
// The ladders
// ---------------------------------------------------------------------------

List<PerfScenario> buildProfileScenarios() {
  final out = <PerfScenario>[];
  final occt = OcctFfi.instance();

  // The two kernel ladders below need the shim; the 2D ones after them do
  // not. `OcctFfi.instance()` is nullable and is null wherever the native
  // kernel is not linked -- every Linux host, in particular. Registering
  // them anyway would produce a ladder whose every rung failed, and a rung
  // that failed and a rung that was fast are the same number in a timing
  // report. So they are not registered at all, which is what
  // perf_scenarios_kernel.dart:162, _ramp.dart:187 and _stress.dart:150 all
  // do with the same fact. The 2D ladders are pure Dart and always run.
  if (occt != null) {
    // ---- the one that matters: sweep against profile segment count ---------
    //
    // Rungs chosen to bracket the field: 32 and 128 sit near the sizes the
    // existing ladder already covers (so the two are comparable), 512 and 1200
    // reach the size that actually happened, and 2048 is there to show whether
    // the curve bends. Five rungs over a 64x range fit an exponent with an
    // interval worth quoting.
    //
    // The path is held at 16 spans, which is what the field's path had: faces
    // ~= segments x spans, so leaving the path free would confound the two axes
    // and produce a number that describes neither.
    out.add(PerfScenario(
      'profile.sweep.segments',
      () {
        _ladder('sweep.segments', const [32, 128, 512, 1200, 2048], (n) {
          Perf.gauge('profile.sweepSegments', n);
          final s = _sweep(occt, segments: n, spans: 16);
          if (s != null) {
            Perf.gauge('profile.sweepFaces', s.counts()?.faces ?? -1);
            s.dispose();
          }
        });
      },
      note: 'THE missing axis. sweepProfile vs profile segment count at a '
          'fixed '
          '16-span path. The existing kernel ladder stops at 48 points; the '
          'field profile was ~1218 segments and cost 102 244 ms. Fit the '
          'exponent over the five rungs: linear says the cost is the output '
          'size, quadratic says something inside the pipe-shell does '
          'whole-wire work per segment — which is the same shape of defect '
          'S2/S6 found in '
          'edge_info, in a different operation',
    ));

    // ---- the OTHER half of the multiplier ----------------------------------
    //
    // Spans are chosen in Dart, not by the kernel: resolvePath emits every
    // point
    // of sketchCurve(), and sampleEntity uses arcSamples: 64 REGARDLESS of the
    // arc's angle. So an arc used as a sweep path is always 64 spans, and
    // against a 512-segment profile that is 32 768 faces where four spans might
    // have done. This ladder prices that decision.
    out.add(PerfScenario(
      'profile.sweep.spans',
      () {
        _ladder('sweep.spans', const [1, 4, 16, 64], (spans) {
          Perf.gauge('profile.sweepSpans', spans);
          _sweep(occt, segments: 512, spans: spans)?.dispose();
        });
      },
      note: 'path resolution at a FIXED 512-segment profile. Faces ~= '
          'segments x spans, so if cost tracks faces this is linear with the '
          'same constant as profile.sweep.segments. If it is not, the two axes '
          'are not interchangeable and the cost model needs both. 64 is what '
          'an arc path costs today, whatever its angle',
    ));
  }

  // ---- 2D: the arrangement, which runs on every paint --------------------
  out.add(PerfScenario(
    'profile.loops.segments',
    () {
      _ladder('loops.segments', const [32, 128, 512, 1200, 2048, 5000], (n) {
        Perf.gauge('profile.loopSegments', n);
        Perf.gauge('profile.loopsFound.$n',
            profileLoopCount(_input([_closedPoly(convexLoop(n, 60))])));
      },
          rungBudgetMs: _cheapRungBudgetMs,
          ladderBudgetMs: _cheapLadderBudgetMs);
    },
    note: 'the planar arrangement vs segment count. Step 2 of '
        '_arrangementLoops '
        'is an explicit all-pairs crossing test with no spatial index, so this '
        'is predicted Theta(n^2): 741 153 pair tests at 1218 segments and '
        '12 497 500 at 5000. It runs on every hit-test and every paint, which '
        'is what makes the exponent matter rather than the constant',
  ));

  // ---- 2D: hundreds of loops, the count axis -----------------------------
  out.add(PerfScenario(
    'profile.loops.count',
    () {
      _ladder('loops.count', const [8, 32, 128, 512], (n) {
        Perf.gauge('profile.loopCount', n);
        Perf.gauge(
            'profile.loopsFound.$n', profileLoopCount(_input(squareGrid(n))));
      },
          rungBudgetMs: _cheapRungBudgetMs,
          ladderBudgetMs: _cheapLadderBudgetMs);
    },
    note: 'loop COUNT at four segments per loop, so this axis is separate from '
        'profile.loops.segments. The field sketch reported 116 loops. Watch '
        'dropDuplicateLoops as well as the arrangement: it is O(L^2) in loop '
        'count and recomputes each candidate perimeter inside the inner loop',
  ));

  // ---- 2D: are the phantoms crossings, or are they snapping? -------------
  //
  // The field logged 116 loops of which 110 had an area printing as 0.00.
  // Two mechanisms can manufacture a bounded face: a genuine self-crossing,
  // and two non-adjacent vertices snapped onto one node by nodeOf's 1e-6
  // radius. They are told apart by AREA — snapping produces ~1e-12, and the
  // arrangement already drops everything at or below 1e-9 — but the cleanest
  // check is constructive: plant a known number of crossings and count.
  //
  // Each rung's vertex count is held near 1200 by subdivision, so the fixture
  // has the field's shape as well as its crossing count.
  out.add(PerfScenario(
    'profile.loops.selfIntersect',
    () {
      // k = 0 is the control and must be a SIMPLE closed curve: star{1/2}
      // would be a one-vertex degenerate, not a crossing-free star.
      for (final k in const [0, 9, 65, 111]) {
        // Vertex count held near the field's 1200 at every rung, so the
        // fixture carries its shape as well as its crossing count.
        final pts = k == 0
            ? convexLoop(1200, 60)
            : starLoop(k, 60, subdiv: (1200 / k).round().clamp(1, 400));
        Perf.gauge('profile.crossingVerts.$k', pts.length ~/ 2);
        final loops = profileLoopCount(_input([_closedPoly(pts)]));
        Perf.gauge('profile.loopsFound.x$k', loops);
        // The prediction, checked in place: bounded faces == crossings + 1.
        // {n/2} with n odd crosses itself exactly n times, and k = 111 mirrors
        // the field's 110 phantoms on a curve of the field's vertex count.
        if (loops != k + 1) {
          Perf.count('profile.selfIntersect.mismatch');
          Log.w(
              'perf',
              'profile selfIntersect: $k planted crossings over '
                  '${pts.length ~/ 2} vertices gave $loops loops, '
                  'expected ${k + 1}');
        }
      }
    },
    note: 'plants a KNOWN number of self-crossings and counts the loops the '
        'arrangement finds. Euler says bounded faces == crossings + 1. If that '
        'holds, the field sketch\'s 110 near-zero loops were 110 real '
        'self-intersections of its 1200-vertex polyline and not an artefact of '
        'node snapping; profile.selfIntersect.mismatch says it did not hold',
  ));

  return out;
}

/// One sweep of an [segments]-segment ring along a path of [spans] spans.
///
/// Guarded the way every kernel scenario is guarded: a null from the shim is
/// counted, not thrown, because a silent failure and a fast success are the
/// same number in a timing report.
OcctShape? _sweep(OcctFfi occt, {required int segments, required int spans}) {
  try {
    final s = occt.sweepProfile(
        [arcRing(segments, 6)], identityMat34(), arcPath(spans + 1, 60));
    if (s == null) {
      Perf.count('profile.sweep.fail');
      Log.w('perf',
          'profile sweep $segments seg x $spans spans: ${occt.lastError()}');
    }
    return s;
  } catch (e) {
    Perf.count('profile.sweep.throw');
    Log.w('perf', 'profile sweep $segments x $spans threw: $e');
    return null;
  }
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

/// Runs the profile-complexity tier. Deliberately NOT called by the ordinary
/// suite — one rung of `profile.sweep.segments` can cost as much as the field's
/// whole sweep did.
Map<String, dynamic> runProfileSuite() {
  final results = <Map<String, dynamic>>[];
  final sw = Stopwatch()..start();
  for (final s in buildProfileScenarios()) {
    Log.i('perf', 'profile scenario ${s.name}');
    // NO warmup, for the stress tier's reason: a warmup pass would double the
    // wall time of the most expensive thing in the suite, and these ladders
    // are self-limiting rather than precision measurements.
    final r = Perf.scenario(s.name, s.run);
    r['note'] = s.note;
    results.add(r);
  }
  sw.stop();
  return {
    'suite': 'perf_scenarios_profile/v1',
    'at': DateTime.now().toIso8601String(),
    'build': Log.build,
    'wallMs': sw.elapsedMilliseconds,
    'occtAvailable': OcctFfi.available,
    'scenarios': results,
  };
}
