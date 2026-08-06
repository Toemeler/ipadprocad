// The 2D half nobody had measured: every drawing tool, every modify
// operation, constraint inference, and each constraint type in turn.
//
// WHY THIS EXISTS
// ---------------
// Until M213 the suite covered the solver, the DOF analysis, painting, snapping
// and the 3D kernel. That left roughly forty-five drawing tools, eight modify
// operations, the 2D fillet/chamfer solver, constraint inference and twelve
// constraint types with NO fixed-input measurement at all — they produced
// numbers only if someone happened to use them, entangled with whatever else
// was on screen, and never twice the same way.
//
// The honest consequence of that gap: "drawing feels slow" was unanswerable.
// Not "we think it is the solver" — literally unanswerable, because no number
// existed for the act of drawing.
//
// THE ONE SEAM THAT MAKES THIS TRACTABLE
// --------------------------------------
// Every drawing tool commits through `buildToolGeometry(tool, points)`, and
// `toolMeta` declares how many points each one needs. That pair lets the whole
// tool palette be driven GENERICALLY — add a tool to the app and it appears in
// this report automatically, with no scenario to write. A hand-written list
// would have gone stale the first time a tool was added, and a stale benchmark
// is worse than a missing one because it looks complete.
//
// EVERYTHING HERE IS PURE
// -----------------------
// No AppState, no Canvas, no binding. That is what lets it run from a unit
// test, from CI and from the device button with the same code. The parts that
// genuinely need AppState (patterns, projection, undo/redo, documents) live in
// perf_scenarios_app.dart.
import 'dart:math' as math;

import 'package:flutter/widgets.dart' show Offset, Rect;

import 'app_state.dart' show Tool;
import 'constraints.dart';
import 'ffi/qcad_engine.dart';
import 'freehand.dart';
import 'modify.dart';
import 'perf.dart';
import 'perf_scenarios.dart' show PerfScenario, sketchFixture, constraintFixture;
import 'solver.dart';
import 'spline.dart';
import 'tools.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// An [n] x [n] grid of crossing lines — n^2 intersections.
///
/// This is the fixture the modify tools need and the ring fixture cannot
/// provide: trim, extend and split all work by finding where an entity meets
/// its neighbours, so on geometry that never crosses they exit early and
/// measure nothing. Grid size is the honest axis for them.
List<Geo> crossFixture(int n, {double span = 100}) {
  final out = <Geo>[];
  for (var i = 0; i < n; i++) {
    final t = -span + 2 * span * i / math.max(n - 1, 1);
    out.add(Geo(Geo.line, [-span * 1.1, t, span * 1.1, t]));
  }
  for (var i = 0; i < n; i++) {
    final t = -span + 2 * span * i / math.max(n - 1, 1);
    out.add(Geo(Geo.line, [t, -span * 1.1, t, span * 1.1]));
  }
  return out;
}

/// Two lines meeting at a right angle, plus an arc — the minimum a 2D fillet
/// or chamfer needs, and the shape of a real corner.
List<Geo> cornerFixture() => [
      Geo(Geo.line, [0, 0, 60, 0]),
      Geo(Geo.line, [60, 0, 60, 60]),
      Geo(Geo.arc, [0, 60, 20, -math.pi / 2, math.pi / 2]),
      Geo(Geo.circle, [-40, -40, 15]),
    ];

/// Points for a tool that needs [k] of them. Deliberately NOT collinear and
/// not symmetric: several tools (arc-through-three-points, the slots, the
/// tangent constructions) degenerate on regular input and return null early,
/// which would measure the early return rather than the construction.
List<Offset> toolPoints(int k) {
  final out = <Offset>[];
  for (var i = 0; i < k; i++) {
    final a = 0.9 + i * 1.7; // irrational-ish stride, no repeats, no symmetry
    out.add(Offset(30 * math.cos(a) + i * 7.0, 30 * math.sin(a) - i * 3.0));
  }
  return out;
}

/// Dialog inputs a tool needs before it can build anything. A tool whose
/// parameters are missing returns null, and a null is a zero in a timing
/// report — so these are supplied rather than left to chance.
const _toolParams = <Tool, Map<String, double>>{
  Tool.polygon: {'sides': 6},
  Tool.fillet: {'r': 5},
  Tool.chamfer: {'d': 5, 'mode': 0},
};

/// The Equation Curve's expression. `ExprParser` accepts ONE function of a
/// single variable `x` — numbers, x, + - * / ^, parentheses and the usual
/// functions. The first version of this fixture passed a parametric PAIR
/// ('sin(t)*30, cos(t)*20'); the parser rejected the comma, `parse()` returned
/// null, and the tool exited before building anything. It still produced a
/// timing, and that timing was of the early return.
const _toolExpr = <Tool, String>{
  Tool.eqCurve: 'sin(x)*30',
};

/// Three lines forming a triangle, well clear of the ring fixture.
///
/// `circleTangent` picks three LINES out of the existing geometry and builds
/// the circle tangent to all three. On the ring fixture the three generic pick
/// points resolved to the same line more than once, `_tangentCircle3` had a
/// degenerate system, and the tool returned null. A triangle with pick points
/// just inside each edge is the configuration a user actually clicks.
List<Geo> _tangentTriangle() => [
      Geo(Geo.line, [200, 200, 320, 200]),
      Geo(Geo.line, [320, 200, 260, 300]),
      Geo(Geo.line, [260, 300, 200, 200]),
    ];

/// Pick points for tools whose GEOMETRIC preconditions the generic generator
/// cannot satisfy.
///
/// The generic driver stays in charge — a new tool still appears in the report
/// with no scenario written — and this map is the short, explicit list of
/// exceptions. Each entry exists because the tool refuses input that does not
/// meet a real condition, not because it is slow to please:
///
///   * circleTangent needs three picks landing on three DIFFERENT lines;
///   * slotOverall requires length > 2 x width, or there is no slot to draw.
Map<Tool, List<Offset>> _toolPointOverrides() => {
      Tool.circleTangent: const [
        Offset(260, 203), // just inside the bottom edge
        Offset(288, 252), // just inside the right edge
        Offset(232, 252), // just inside the left edge
      ],
      Tool.slotOverall: const [
        Offset(-40, 0),
        Offset(40, 0),
        Offset(0, 8), // width 8, length 80 — comfortably > 2 x width
      ],
    };

/// How many points to feed a tool. Variable-length tools (the splines) get a
/// realistic control-point count rather than their bare minimum: a 3-point
/// spline says nothing about what drawing a real curve costs.
int _pointsFor(Tool t) {
  final m = toolMeta[t];
  if (m == null) return 2;
  return m.fixed ?? math.max(m.minVar, 12);
}

/// The sketch a tool is built AGAINST. Several tools hit-test it (the tangent
/// and fillet constructions do), so an empty list would measure a different,
/// cheaper function than the one a user runs.
List<Geo> toolExistingFixture() => [
      ...sketchFixture(24),
      ..._tangentTriangle(),
    ];

/// The picks for [t]: an override where the tool has a real geometric
/// precondition, the generic set otherwise.
List<Offset> pointsForTool(Tool t) =>
    _toolPointOverrides()[t] ?? toolPoints(_pointsFor(t));

/// Builds [t] exactly as `tools.buildAll` does. Shared with the coverage test
/// so the test and the scenario can never drift apart — a test that drove the
/// tool differently from the benchmark would pass while the benchmark measured
/// an early return, which is the whole failure mode this file guards against.
List<Geo>? buildToolForPerf(Tool t, List<Geo> existing) => buildToolGeometry(
      t,
      pointsForTool(t),
      existing: existing,
      params: _toolParams[t] ?? const {},
      expr: _toolExpr[t] ?? '',
    );

// ---------------------------------------------------------------------------
// The suite
// ---------------------------------------------------------------------------

List<PerfScenario> buildToolScenarios() {
  final out = <PerfScenario>[];

  // ---- every drawing tool ------------------------------------------------
  //
  // Driven from toolMeta, so this list cannot go stale. Each tool is built 50
  // times against a 48-entity sketch (several tools hit-test `existing` — the
  // tangent and fillet constructions do — so an empty sketch would measure a
  // different, cheaper function).
  out.add(PerfScenario(
    'tools.buildAll',
    () {
      final existing = toolExistingFixture();
      var built = 0, missing = 0;
      for (final t in toolMeta.keys) {
        final name = t.name;
        List<Geo>? r;
        for (var i = 0; i < 50; i++) {
          r = Perf.span('tool.build.$name', () => buildToolForPerf(t, existing));
        }
        // A tool that returns null measured its own early exit. Counting it
        // is the difference between "this tool is instant" and "this tool
        // never ran" — the exact confusion that made gear.curve read as free.
        if (r == null || r.isEmpty) {
          Perf.count('tool.build.$name.null');
          missing++;
        } else {
          built++;
          Perf.count('tool.build.$name.entities', r.length);
        }
      }
      Perf.gauge('tools.built', built);
      Perf.gauge('tools.nullResult', missing);
    },
    note: 'EVERY drawing tool, 50 builds each, driven from toolMeta so the '
        'list cannot go stale. Read tool.build.<name> for the per-tool cost '
        'and tools.nullResult for how many produced nothing (those numbers '
        'are meaningless and the .null counters name them)',
  ));

  // Splines separately and by size: they are the only tools whose cost grows
  // with what the user does, and the freehand tool feeds them a fitted stroke
  // that can carry a hundred points.
  for (final k in const [4, 16, 64]) {
    out.add(PerfScenario(
      'tools.spline.$k',
      () {
        final pts = toolPoints(k);
        Perf.gauge('tools.splineCVs', k);
        for (var i = 0; i < 20; i++) {
          Perf.span('tool.spline.cv',
              () => buildToolGeometry(Tool.splineCV, pts));
          Perf.span('tool.spline.interp',
              () => buildToolGeometry(Tool.splineInterp, pts));
        }
      },
      note: 'spline construction vs control-point count — the freehand tool '
          'commits through the same path with a fitted stroke, so this is '
          'also the cost of drawing with a pencil',
    ));
  }

  // Curve evaluation, which is NOT the same thing as construction: this runs
  // on every paint, every hit-test and every snap query for every spline on
  // screen.
  for (final k in const [4, 16, 64]) {
    out.add(PerfScenario(
      'tools.splineEval.$k',
      () {
        final g = buildToolGeometry(Tool.splineCV, toolPoints(k))?.first;
        if (g == null) return;
        var pts = 0;
        for (var i = 0; i < 100; i++) {
          pts = Perf.span('spline.curveFor', () => splineCurveFor(g)).length;
        }
        Perf.gauge('tools.splinePolyPts', pts);
      },
      note: 'evaluating a spline to a polyline, 100x — paid per paint, per '
          'hit-test and per snap for every spline on screen. Compare against '
          'tool.spline.cv: building once is irrelevant if evaluating is not',
    ));
  }

  out.add(PerfScenario(
    'tools.ellipseEval',
    () {
      final g = buildToolGeometry(Tool.ellipse, toolPoints(3))?.first;
      if (g == null) return;
      for (var i = 0; i < 100; i++) {
        Perf.span('ellipse.curve', () => splineCurveFor(g));
      }
    },
    note: 'the ellipse equivalent of tools.splineEval — same per-paint path',
  ));

  // ---- freehand ----------------------------------------------------------
  //
  // Drawing with a pencil produces a raw stroke at the touch sampling rate —
  // up to 120 samples a second — and every one of them is dedup'd, smoothed
  // and resampled before a curve exists. Swept against raw sample count,
  // because that is what a longer stroke means.
  for (final raw in const [64, 256, 1024]) {
    out.add(PerfScenario(
      'tools.freehand.$raw',
      () {
        final stroke = <Offset>[];
        for (var i = 0; i < raw; i++) {
          final t = i / raw;
          // A wobbly spiral: real strokes are neither smooth nor uniform, and
          // a clean circle would let dedupe and smoothing exit early.
          final a = t * 6 * math.pi;
          final r = 10 + 40 * t + 1.5 * math.sin(a * 7);
          stroke.add(Offset(r * math.cos(a), r * math.sin(a)));
        }
        Perf.gauge('freehand.rawSamples', raw);
        for (var i = 0; i < 10; i++) {
          Perf.span('freehand.dedupe', () => dedupeStroke(stroke));
          Perf.span('freehand.smooth', () => smoothStroke(stroke, 0.35));
          Perf.span('freehand.resample', () => resampleByArcLength(stroke, 32));
          Perf.span('freehand.fit', () => fitFreehandStroke(stroke));
        }
      },
      note: 'the pencil path vs raw stroke length, phase by phase. The four '
          'spans nest inside fitFreehandStroke, so compare them against it to '
          'see which stage dominates a long stroke',
    ));
  }

  // ---- 2D fillet and chamfer --------------------------------------------
  //
  // These are SOLVERS, not constructions: they build offset carriers for both
  // picks and choose the candidate nearest the two pick points. Nothing in the
  // suite covered them, and filletMaxRadius below is the reason that mattered.
  out.add(PerfScenario(
    'tools.fillet2d',
    () {
      final gs = cornerFixture();
      for (var i = 0; i < 50; i++) {
        Perf.span('tools.filletInventor',
            () => filletInventor(gs, const Offset(30, 2), const Offset(58, 30), 5));
      }
    },
    note: '2D fillet between two picked entities, 50x',
  ));

  out.add(PerfScenario(
    'tools.chamfer2d',
    () {
      final gs = cornerFixture();
      for (var i = 0; i < 50; i++) {
        Perf.span(
            'tools.chamferInventor',
            () => chamferInventor(gs, const Offset(30, 2), const Offset(58, 30),
                mode: 0, d1: 5));
      }
    },
    note: '2D chamfer, 50x; compare against tools.filletInventor — chamfer is '
        'line-line only and should be much simpler',
  ));

  out.add(PerfScenario(
    'tools.filletMaxRadius',
    () {
      final gs = cornerFixture();
      for (var i = 0; i < 10; i++) {
        Perf.span('tools.filletMaxRadius',
            () => filletMaxRadius(gs, const Offset(30, 2), const Offset(58, 30), 200));
      }
    },
    note: 'THE one to watch here. filletMaxRadius binary-searches the largest '
        'radius that fits by calling filletInventor FORTY times per query. '
        'Divide its avgMs by tools.filletInventor avgMs: anything near 40 '
        'means the search is the whole cost, and it runs while the user drags '
        'the radius',
  ));

  // ---- modify operations -------------------------------------------------
  //
  // Swept against grid size, because every one of them starts by finding the
  // intersections with the neighbours — an O(entities) walk per call at best.

  for (final n in const [4, 10, 20]) {
    out.add(PerfScenario(
      'modify.intersections.$n',
      () {
        final gs = crossFixture(n);
        Perf.gauge('modify.entities', gs.length);
        var hits = 0;
        for (var i = 0; i < gs.length; i++) {
          hits += Perf.span('modify.intersectionsWithOthers',
              () => intersectionsWithOthers(gs, i)).length;
        }
        Perf.gauge('modify.intersectionsFound', hits);
      },
      note: 'the shared prelude of trim/extend/split: every entity against '
          'every other. n^2 in entity count is expected — the question is the '
          'constant, because this runs per modify CLICK on a live sketch',
    ));
  }

  for (final n in const [4, 10, 20]) {
    out.add(PerfScenario(
      'modify.trim.$n',
      () {
        final gs = crossFixture(n);
        Perf.gauge('modify.entities', gs.length);
        // Trim the horizontal lines, one click each, at a point that really
        // lies between two crossings — a click that hits nothing exits early
        // and measures the early exit.
        for (var i = 0; i < n; i++) {
          final y = gs[i].data[1];
          Perf.span('modify.trimEntity',
              () => trimEntity(List<Geo>.from(gs), i, Offset(5, y)));
        }
      },
      note: 'trim, one click per horizontal line, vs grid size',
    ));
  }

  out.add(PerfScenario(
    'modify.trimCutAway',
    () {
      final gs = crossFixture(10);
      for (var i = 0; i < 10; i++) {
        final y = gs[i].data[1];
        Perf.span('modify.trimCutAway',
            () => trimCutAway(List<Geo>.from(gs), i, Offset(5, y)));
      }
    },
    note: 'the cut-away variant; compare against modify.trimEntity',
  ));

  out.add(PerfScenario(
    'modify.extend',
    () {
      // Short stubs that need extending to reach the grid.
      final gs = crossFixture(10)
        ..add(Geo(Geo.line, [-150, 33, -120, 33]))
        ..add(Geo(Geo.line, [-150, -47, -120, -47]));
      for (var i = 0; i < 20; i++) {
        Perf.span('modify.extendEntity',
            () => extendEntity(gs, gs.length - 1, const Offset(-122, -47)));
      }
    },
    note: 'extend a stub to its nearest neighbour, 20x',
  ));

  out.add(PerfScenario(
    'modify.split',
    () {
      final gs = crossFixture(10);
      for (var i = 0; i < 10; i++) {
        final y = gs[i].data[1];
        Perf.span('modify.splitEntity',
            () => splitEntity(List<Geo>.from(gs), i, Offset(5, y)));
      }
    },
    note: 'split at a click point, 10x on a 20x20 grid',
  ));

  out.add(PerfScenario(
    'modify.offsetSingle',
    () {
      final gs = cornerFixture();
      for (var i = 0; i < 100; i++) {
        for (var k = 0; k < gs.length; k++) {
          Perf.span('modify.offsetEntity',
              () => offsetEntity(gs[k], const Offset(10, 10)));
        }
      }
    },
    note: 'single-entity offset across line/arc/circle, 100 rounds',
  ));

  out.add(PerfScenario(
    'modify.offsetChain',
    () {
      // A connected chain is what Inventor's offset actually walks, and the
      // walk is the expensive half.
      final gs = <Geo>[
        Geo(Geo.line, [0, 0, 50, 0]),
        Geo(Geo.line, [50, 0, 50, 40]),
        Geo(Geo.line, [50, 40, 10, 40]),
        Geo(Geo.line, [10, 40, 0, 20]),
        Geo(Geo.line, [0, 20, 0, 0]),
      ];
      final allowed = {for (var i = 0; i < gs.length; i++) i};
      for (var i = 0; i < 50; i++) {
        Perf.span('modify.offsetChainAt',
            () => offsetChainAt(gs, 0, const Offset(25, 5), allowed));
      }
    },
    note: 'chain offset: walks the connected loop, then offsets every member. '
        'Compare avgMs against 5x modify.offsetEntity to price the WALK',
  ));

  for (final n in const [24, 128]) {
    out.add(PerfScenario(
      'modify.transform.$n',
      () {
        final gs = sketchFixture(n ~/ 2);
        Perf.gauge('modify.entities', gs.length);
        for (var i = 0; i < 20; i++) {
          Perf.span('modify.transformGeo', () {
            for (final g in gs) {
              transformGeo(g, (p) => p + const Offset(1, 1));
            }
          });
        }
      },
      note: 'move/copy/rotate/scale all funnel through transformGeo; this is '
          'one drag frame of a whole-selection move, 20x',
    ));
  }

  out.add(PerfScenario(
    'modify.stretch',
    () {
      final gs = sketchFixture(24);
      const box = Rect.fromLTRB(-70, -70, 70, 70);
      for (var i = 0; i < 20; i++) {
        Perf.span('modify.stretchGeo', () {
          for (final g in gs) {
            stretchGeo(g, box, const Offset(2, 1));
          }
        });
      }
    },
    note: 'stretch moves only the points inside the box, so it costs more per '
        'entity than a plain transform — this says how much more',
  ));

  // ---- constraint inference ----------------------------------------------
  //
  // Runs on EVERY entity the user draws, against everything already there.
  // Never measured before, and it is O(existing) at minimum.
  for (final n in const [8, 24, 64]) {
    out.add(PerfScenario(
      'constraints.infer.$n',
      () {
        final gs = sketchFixture(n);
        Perf.gauge('infer.existing', gs.length);
        var found = 0;
        for (var i = 1; i < gs.length; i += math.max(gs.length ~/ 12, 1)) {
          found += Perf.span('constraints.inferConstraints',
              () => inferConstraints(gs, i)).length;
          found += Perf.span('constraints.inferPointBindings',
              () => inferPointBindings(gs, i)).length;
        }
        Perf.gauge('infer.found', found);
      },
      note: 'auto-constraint inference vs sketch size — paid once per entity '
          'DRAWN, so a 200-entity sketch pays it 200 times against a list that '
          'grows each time. If this is n-squared cumulatively, drawing gets '
          'slower the longer you draw',
    ));
  }

  // ---- every constraint type ---------------------------------------------
  //
  // Adding one constraint means: append it, solve, re-analyse. All three are
  // measured together because that is what the user waits for, and separately
  // by name so the expensive third can be told from the cheap first.
  out.add(PerfScenario(
    'constraints.addEachType',
    () {
      for (final t in CType.values) {
        final gs = sketchFixture(12);
        final cs = constraintFixture(12);
        final c = _sampleConstraint(t);
        if (c == null) {
          Perf.count('constraints.unsupportedInFixture.${t.name}');
          continue;
        }
        cs.add(c);
        Perf.span('constraints.add.${t.name}', () {
          solveConstraints(gs, cs, iterations: 25);
          analyzeSketch(gs, cs);
        });
      }
    },
    note: 'add-one-constraint round trip (solve + DOF re-analysis) for EVERY '
        'constraint type, on the same 24-entity sketch. Differences between '
        'types point at a residual that is more expensive than its neighbours',
  ));

  out.add(PerfScenario(
    'constraints.encode',
    () {
      final cs = constraintFixture(64);
      Perf.gauge('constraints.encoded', cs.length);
      var s = '';
      for (var i = 0; i < 20; i++) {
        s = Perf.span('constraints.encode', () => encodeConstraints(cs));
      }
      for (var i = 0; i < 20; i++) {
        Perf.span('constraints.decode', () => decodeConstraints(s));
      }
    },
    note: 'the sidecar codec, paid on every save and every load of a sketch',
  ));

  // ---- solver detail -----------------------------------------------------
  //
  // perf_scenarios.dart sweeps the solver on a SETTLED system and on a drag.
  // These are the two cases it does not cover and that a user hits constantly.
  out.add(PerfScenario(
    'solve.fromViolated',
    () {
      // Every dimension changed at once: the worst honest case, and what
      // editing a driving parameter does.
      for (var i = 0; i < 10; i++) {
        final gs = sketchFixture(24);
        final cs = constraintFixture(24);
        for (final c in cs) {
          if (c.type == CType.dimension && c.value != null) c.value = 9.5;
        }
        solveConstraints(gs, cs, iterations: 80);
      }
    },
    note: 'solving a sketch that is NOT already satisfied, 80 iterations — the '
        'parameter-edit path. Compare against solve.sweep.24 (the settled '
        'floor) for what convergence actually costs',
  ));

  out.add(PerfScenario(
    'solve.overConstrained',
    () {
      // Two conflicting fixes on the same point. Inventor reports this rather
      // than hanging; the question is what detecting it costs.
      for (var i = 0; i < 10; i++) {
        final gs = sketchFixture(24);
        final cs = constraintFixture(24)
          ..add(Constraint(CType.fix,
              ents: [1], pts: [const PRef(1, 0)], anchors: [999.0, 999.0]));
        solveConstraints(gs, cs, iterations: 80);
      }
    },
    note: 'an unsatisfiable system, 80 iterations x10. The solver cannot win, '
        'so this is the cost of LOSING — and a user who over-constrains by '
        'accident pays it on every subsequent edit',
    ));

  return out;
}

/// A constraint of type [t] that is valid on [sketchFixture(12)], or null when
/// the fixture cannot express it. Circles are entities 0..11 (point 0 = the
/// centre), lines are 12..23 (points 0 and 1).
///
/// Returning null rather than inventing a malformed constraint is deliberate:
/// a constraint the solver rejects contributes zero residuals, so it would be
/// timed as free and reported as covered. The `unsupportedInFixture` counter
/// names the gap instead.
Constraint? _sampleConstraint(CType t) {
  switch (t) {
    case CType.coincident:
      return Constraint(t, pts: [const PRef(12, 0), const PRef(2, 0)]);
    case CType.concentric:
      return Constraint(t, ents: [2, 3]);
    case CType.equal:
      return Constraint(t, ents: [2, 3]);
    case CType.fix:
      return Constraint(t, ents: [2], pts: [const PRef(2, 0)], anchors: [10, 10]);
    case CType.collinear:
    case CType.parallel:
    case CType.perpendicular:
      return Constraint(t, ents: [12, 13]);
    case CType.horizontal:
    case CType.vertical:
      return Constraint(t, ents: [12]);
    case CType.tangent:
      return Constraint(t, ents: [2, 12]);
    case CType.smooth:
      return Constraint(t, ents: [12, 13]);
    case CType.symmetric:
      return Constraint(t,
          pts: [const PRef(12, 0), const PRef(13, 1)], ents: [14]);
    case CType.midpoint:
      return Constraint(t, ents: [12], pts: [const PRef(2, 0)]);
    case CType.dimension:
      return Constraint(t, ents: [2], value: 6.0, dimKind: 'rad');
    case CType.pattern:
      // Needs a source/copy pair produced by the pattern tool; the ring
      // fixture has no patterned geometry, so this is honestly out of scope
      // here and is covered by the pattern scenarios in perf_scenarios_app.
      return null;
  }
}
