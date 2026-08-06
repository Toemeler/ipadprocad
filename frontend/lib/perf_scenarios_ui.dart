// The half of the suite that needs the UI layer.
//
// perf_scenarios.dart is deliberately headless — kernel, solver, gear curves —
// so it runs from a unit test with no binding. This file covers what that one
// cannot reach and what the device session showed to matter most:
//
//   * PAINT, phase by phase. `2d.paint.ent.dofColour` alone was 85% of all
//     painting on the device. Measuring a reimplementation would measure the
//     reimplementation, so this drives the REAL CustomPainter through
//     `paintViewportForBenchmark` into a PictureRecorder canvas.
//   * The DRAG path, which is the one that runs a 25-iteration constraint
//     solve inside `CustomPainter.paint` and is therefore the reason a sketch
//     stalls mid-gesture.
//   * SNAP, which runs per pointer-move and walks the visible geometry twice —
//     a per-frame cost that never appears in `2d.paint` at all.
//
// It needs a Flutter binding (a Canvas and image decoding do), which is why it
// is separate: keeping it out of perf_scenarios.dart is what lets that file
// stay runnable anywhere.
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart' show Offset, Size;

import 'app_state.dart';
import 'ffi/qcad_engine.dart';
import 'perf.dart';
import 'perf_scenarios.dart';
import 'perf_scenarios_app.dart';
import 'snap.dart' show Grip;
import 'solver.dart' show analyzeSketch;
import 'widgets/viewport.dart'
    show paintViewportForBenchmark, snapViewportForBenchmark;

/// Paints [app] once into a throwaway canvas at [size].
///
/// The recorded picture is disposed immediately: we want the COST of painting,
/// not the picture, and holding them would turn a 60-frame scenario into a
/// memory measurement of something nobody does.
void _paintOnce(AppState app, {Size size = const Size(1024, 768)}) {
  final rec = ui.PictureRecorder();
  final canvas = ui.Canvas(rec);
  try {
    paintViewportForBenchmark(canvas, size, app);
  } finally {
    rec.endRecording().dispose();
  }
}

/// Builds an AppState carrying a sketch of [n] ring entities.
///
/// Uses the app's own document path rather than poking fields, so the geometry
/// arrives the way it does in real use — through the engine, with the same
/// layer and style handling. Returns null when no sketch could be prepared,
/// which the scenarios treat as "skip" rather than "fail": a perf suite that
/// throws on a device with an unexpected state is worse than one that reports
/// a gap.
AppState? _buildAppWithSketch(int n) {
  try {
    final app = AppState();
    // CREATE the sketch rather than hoping one is open.
    //
    // Relying on `app.current` was wrong twice over: on a device it depends on
    // what the user happened to have open, which destroys the fixed-input
    // property the whole suite rests on; and on a fresh AppState there is no
    // current sketch at all, so every scenario silently skipped and measured
    // nothing. The unit tests caught the second case, which is exactly why
    // they assert a solve happened rather than merely that the code ran.
    final s = SketchModel('perf');
    app.sketches['perf'] = s;
    app.curTab = 'perf';
    app.editingLayer = kDefaultLayer;
    s.geometry
      ..clear()
      ..addAll(sketchFixture(n));
    // CONSTRAINTS AND THE DOF ANALYSIS — the fixture's second gap (M212).
    //
    // The painter colours every entity by its constraint state, and the whole
    // branch that does it is guarded by `hasAnalysis`:
    //
    //     bool segFull(int i, int seg) =>
    //         hasAnalysis && app.analysis!.carrierFixed(i, seg);
    //
    // A sketch with no constraints and a null analysis short-circuits that
    // guard on the first term, so the painter took the cheap path on every
    // entity and `2d.paint.ent.*` reported near zero — for the phase that was
    // 85% of all painting on the device. The fixture was measuring a sketch
    // nobody draws.
    //
    // So the fixture now carries the device's constraint density (about 1.5
    // per entity, see constraintFixture) AND the analysis those constraints
    // produce, which is what makes `carrierFixed` return a mix of true and
    // false rather than a constant. The analysis itself is deliberately built
    // HERE, in fixture setup, and not inside a measured body: it is what the
    // app has already computed by the time it paints, so charging it to a
    // paint scenario would inflate paint by work paint does not do.
    s.constraints
      ..clear()
      ..addAll(constraintFixture(n));
    app.analysis = analyzeSketch(s.geometry, s.constraints);
    return app;
  } catch (_) {
    return null;
  }
}

/// Fixtures, memoised by size.
///
/// Building one now includes a full DOF analysis, which is itself one of the
/// costs under study — and the scenarios call this from inside their measured
/// body. Caching moves that build into the warmup pass, where its cost is
/// discarded, so `ui.paint.sweep.64` reports painting rather than painting
/// plus a rank analysis. Scenarios that mutate the app (the drag) restore what
/// they touched, so sharing one instance across the suite is safe.
final Map<int, AppState?> _fixtureApps = {};

AppState? _appWithSketch(int n) =>
    _fixtureApps.putIfAbsent(n, () => _buildAppWithSketch(n));

/// Drops the memoised fixtures. For tests that want a cold build; normal runs
/// never need it.
void resetUiFixturesForTest() => _fixtureApps.clear();

List<PerfScenario> buildUiScenarios() {
  final out = <PerfScenario>[];

  // ---- paint, by size ----------------------------------------------------
  // Three sizes so the report shows how paint scales with entity count. The
  // per-phase breakdown falls out automatically: every `2d.paint.*` phase is
  // recorded by the painter itself.
  for (final n in const [8, 24, 64]) {
    out.add(PerfScenario(
      'ui.paint.sweep.$n',
      () {
        final app = _appWithSketch(n);
        if (app == null) return;
        Perf.gauge('ui.paint.entities', n * 2);
        Perf.gauge('ui.paint.constraints', app.current?.constraints.length ?? 0);
        for (var f = 0; f < 30; f++) {
          _paintOnce(app);
        }
      },
      note: 'painter cost vs entity count, on a CONSTRAINED sketch with a live '
          'DOF analysis so the entity colouring really runs; the 2d.paint.* '
          'phases in the same report say WHICH phase grows',
    ));
  }

  // ---- the drag path -----------------------------------------------------
  // What actually happens per frame while a grip is held: displayGeometry
  // solves, then the painter runs. 60 iterations is one second of dragging.
  out.add(PerfScenario(
    'ui.drag60',
    () {
      final app = _appWithSketch(24);
      if (app == null) return;
      final s = app.current;
      if (s == null || s.geometry.isEmpty) return;
      // BOTH are required: displayGeometry returns the committed geometry
      // untouched unless a grip AND a position are set, so setting only
      // dragPos would measure a scenario that never solves — a plausible
      // wrong number, which is worse than no number.
      //
      // Entity 1 rather than 0 for the same reason solve.drag60 uses it:
      // circle 0 is the fixture's ground, and dragging a fixed point measures
      // the solver failing, not the solver working.
      app.dragGrip = const Grip(1, 0, Offset(20, 10), 'center');
      try {
        for (var f = 0; f < 60; f++) {
          // Move the wish a little each frame, as a finger does. A stationary
          // drag would let the solver converge instantly and measure nothing.
          app.dragPos = Offset(20 + f * 0.5, 10 + f * 0.25);
          _paintOnce(app);
        }
      } finally {
        app.dragGrip = null;
        app.dragPos = null;
      }
    },
    note: 'one second of dragging: solve + paint per frame. Divide totalMs by '
        '60 for the per-frame cost, and compare 2d.displayGeometry.solves '
        'against 60 — more than one solve per frame means duplicated work',
  ));

  // ---- snap --------------------------------------------------------------
  // Runs per pointer-move, not per frame, and is invisible inside 2d.paint.
  out.add(PerfScenario(
    'ui.snapHover',
    () {
      final app = _appWithSketch(24);
      if (app == null) return;
      for (var i = 0; i < 120; i++) {
        // The REAL pointer-move sequence, in the order the viewport runs it:
        // snap the raw world point first, then publish the snapped result as
        // the hover. The first version called only `setHover`, which is the
        // second half — so `2d.snap` never appeared in any report and the
        // scenario's note promised a breakdown it could not deliver. Snapping
        // lived inside the widget state and was unreachable from here until
        // `snapViewportForBenchmark` moved the body out (M212).
        final w = Offset(i * 0.9 - 50, i * 0.4 - 20);
        app.setHover(snapViewportForBenchmark(app, w));
      }
    },
    note: 'pointer-move path at 120 events, snap then hover; 2d.snap and '
        '2d.pickEntity in the same report carry the breakdown — snap walks '
        'the visible geometry twice per event, hover picks once',
  ));

  // ---- document round trip ----------------------------------------------
  out.add(PerfScenario(
    'ui.engineRebuild',
    () {
      final app = _appWithSketch(64);
      if (app == null) return;
      final s = app.current;
      if (s == null) return;
      for (var i = 0; i < 5; i++) {
        Perf.span('ui.allGeometry', () => s.engine.allGeometry());
      }
    },
    note: 'reading the whole document back out of the C++ side; compare '
        'ffi.qcad.allGeometry.entities against the call count',
  ));

  // ---- everything that needs a live AppState or a real part (M213) -------
  //
  // Patterns, projection, the RealityKit handover, the undo journal and the
  // document codec. They belong on this side of the split for the same reason
  // painting does: they cannot run without the app object, and the headless
  // runner's whole value is that it can.
  out.addAll(buildAppScenarios());

  return out;
}

/// Runs the UI scenarios. Separate from [runPerfSuite] because these need a
/// Flutter binding; the caller decides whether one exists.
Map<String, dynamic> runUiPerfSuite({bool warmup = true}) {
  final results = <Map<String, dynamic>>[];
  final sw = Stopwatch()..start();
  for (final s in buildUiScenarios()) {
    if (warmup) {
      try {
        s.run();
      } catch (_) {/* the measured pass records it */}
    }
    final r = Perf.scenario(s.name, s.run);
    r['note'] = s.note;
    results.add(r);
  }
  sw.stop();
  return {
    'suite': 'perf_scenarios_ui/v1',
    'wallMs': sw.elapsedMilliseconds,
    'scenarios': results,
  };
}

/// True when a Geo list looks like the ring fixture — used by tests to prove
/// the UI scenarios operate on the same deterministic input as the headless
/// ones rather than on whatever the app happened to have open.
bool isRingFixture(List<Geo> gs, int n) =>
    gs.length == n * 2 &&
    gs.take(n).every((g) => g.type == Geo.circle) &&
    gs.skip(n).every((g) => g.type == Geo.line);
