// S4 — ONE DISPLAY SOLVE PER DRAG POSITION.
//
// `PERFORMANCE_PROFILE.md` §5.2 counted 60 painted frames of `ui.drag60`
// against 120 `2d.displayGeometry` invocations and 120 solves: two full
// 25-iteration constraint solves per painted frame, from two call sites in
// `viewport.dart` asking the same question about the same cursor position.
//
// They were NOT duplicates, and that is what this file exists to pin.
// `_displayGeometryInner` ends a good frame with `_lastGoodDragGeo = gs` and
// opens the next call by warm-starting from that field, so the second call
// re-pulled the grip to the cursor and ran 25 more iterations on the first
// call's output. Three things followed:
//
//   - entities were drawn from the first call's list and constraint glyphs
//     from the second's, so a glyph sat where its entity was ABOUT to be;
//   - the solve count varied with UI state (the glyph call is behind
//     `inEditMode`, the tool preview adds a third), so the geometry a drag
//     COMMITTED depended on whether glyphs were switched on;
//   - `endGripDrag` settles from `displayGeometry(s)`, so all of it reached
//     the document.
//
// `displayGeometry` is now memoised on the drag position. The tests below are
// in four parts: the memo does collapse the calls; painted both ways, the
// collapse is exact where it must be and bounded where it cannot be; the memo
// invalidates on every input that can change the answer; and the drag itself
// still behaves.
//
// The arithmetic and the pre-registered predictions are in
// `perf/findings/S4-painter.md`.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/perf.dart';
import 'package:prototype/snap.dart';
import 'package:prototype/solver.dart';

AppState _app() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

void _slot(AppState app, Offset a, Offset b, Offset w) {
  app.tool = Tool.slotCC;
  app.toolClick(a);
  app.toolClick(b);
  app.toolClick(w);
  app.tool = Tool.none;
}

/// Two slots coupled the way the device's auto-constraints coupled them —
/// the fixture `m207_drag_continuity_test.dart` was written for, and the
/// hardest constrained system the repo can build. A tangent plus a cap centre
/// pinned onto the other slot's cap curve.
AppState _twoCoupledSlots() {
  final app = _app();
  final s = app.current!;
  _slot(app, const Offset(0, 0), const Offset(40, 0), const Offset(20, 6));
  final firstB = s.geometry.length;
  _slot(app, const Offset(0, 60), const Offset(40, 60), const Offset(20, 66));
  s.constraints.add(Constraint(CType.coincident,
      pts: [const PRef(3, 0)], ents: [firstB + 2]));
  solveConstraints(s.geometry, s.constraints);
  return app;
}

/// A line pinned at one end with its length fixed, so its far end can only
/// ride a circle: dragging the cursor outside that circle is a wish the
/// constraints cannot grant.
AppState _unreachable() {
  final app = _app();
  final s = app.current!;
  s.geometry.add(Geo(Geo.line, [0, 0, 10, 0]));
  s.constraints.add(Constraint(CType.fix, pts: [const PRef(0, 0)]));
  s.constraints.add(Constraint(CType.dimension,
      pts: [const PRef(0, 0), const PRef(0, 1)], value: 10));
  solveConstraints(s.geometry, s.constraints);
  return app;
}

/// Largest absolute difference over every parameter of every entity.
/// Returns -1 when the two lists are not even the same shape.
double _maxDelta(List<Geo> a, List<Geo> b) {
  if (a.length != b.length) return -1;
  var worst = 0.0;
  for (var i = 0; i < a.length; i++) {
    if (a[i].data.length != b[i].data.length) return -1;
    for (var k = 0; k < a[i].data.length; k++) {
      final d = (a[i].data[k] - b[i].data[k]).abs();
      if (d > worst) worst = d;
    }
  }
  return worst;
}

/// The SECOND call as the painter used to make it.
///
/// Replaces `s.geometry` with a list holding the same (immutable) entities but
/// a new identity, which is the one cache guard a test can trip without
/// altering a single number the solve reads. Everything else — the grip, the
/// cursor, and `_lastGoodDragGeo` as the first call left it — is untouched, so
/// what comes back is exactly what the old second call computed.
List<Geo> _paintAgainTheOldWay(AppState app, SketchModel s) {
  s.geometry = List<Geo>.of(s.geometry);
  return app.displayGeometry(s);
}

void main() {
  group('one solve per drag position', () {
    test('every caller within a frame gets the same list object', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      app.beginGripDrag(Grip(0, 1, getPt(s.geometry[0], 1), 'end'));
      app.updateGripDrag(getPt(s.geometry[0], 1) + const Offset(6, 4));

      final entitiesPhase = app.displayGeometry(s); // viewport ent.dofColour
      final glyphPhase = app.displayGeometry(s); // viewport constraints
      final toolPreview = app.displayGeometry(s); // viewport tool preview

      // Not merely equal — the SAME list. This is what stops a constraint
      // glyph being placed against geometry the entity under it was not
      // drawn from.
      expect(identical(entitiesPhase, glyphPhase), isTrue);
      expect(identical(glyphPhase, toolPreview), isTrue);
    });

    test('the counters say one solve and the rest hits', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      app.beginGripDrag(Grip(0, 1, getPt(s.geometry[0], 1), 'end'));
      app.updateGripDrag(getPt(s.geometry[0], 1) + const Offset(6, 4));

      Perf.resetForTest();
      for (var i = 0; i < 4; i++) {
        app.displayGeometry(s);
      }

      expect(Perf.counters['2d.displayGeometry.solves'], 1);
      expect(Perf.counters['2d.displayGeometry.cacheHit'], 3);
      // `solve.total` is a SPAN, so it is counted in Perf.stats rather than in
      // the counter table — and it is the one that matters: it says the
      // constraint solve itself ran once, not that a counter was skipped.
      expect(Perf.stats['solve.total']?.count, 1);
    });

    test('sixty frames cost sixty solves, not a hundred and twenty', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      var at = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, at, 'end'));

      Perf.resetForTest();
      for (var i = 1; i <= 60; i++) {
        at = at + const Offset(0.4, 0.25);
        app.updateGripDrag(at);
        app.displayGeometry(s); // ent.dofColour phase
        app.displayGeometry(s); // constraints phase
      }

      // The headline of §5.2, halved. 120 calls, 60 of them solving.
      expect(Perf.counters['2d.displayGeometry.solves'], 60);
      expect(Perf.counters['2d.displayGeometry.cacheHit'], 60);
    });

    test('the real pointer-move order costs one solve, not three', () {
      // viewport.dart, the 'grip' case of the pan handler, is
      //
      //     app.updateGripDrag(_snapped(w, ...));
      //
      // and Dart evaluates the argument first. So _snapped -> _snapAt ->
      // app.displayGeometry runs while dragPos is STILL THE PREVIOUS VALUE,
      // and only then does updateGripDrag move it. The real per-move sequence
      // is therefore: snap at the old position, then two paint calls at the
      // new one.
      //
      // Before the memo that was THREE solves per pointer-move, and the first
      // of them was at a stale cursor — it solved for a position the user had
      // already left, and wrote the result into _lastGoodDragGeo, which is
      // what the paint then warm-started from. `ui.drag60` never saw it: the
      // scenario drives the painter directly rather than through the pointer
      // pipeline, which is why PERFORMANCE_PROFILE §5.2 counts 120 and not 180.
      final app = _twoCoupledSlots();
      final s = app.current!;
      var at = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, at, 'end'));
      app.updateGripDrag(at);
      app.displayGeometry(s); // settle the first position

      Perf.resetForTest();
      for (var i = 1; i <= 10; i++) {
        app.displayGeometry(s); // _snapped(), at the OLD dragPos — a hit
        at = at + const Offset(0.4, 0.25);
        app.updateGripDrag(at); // now the cursor moves
        app.displayGeometry(s); // paint: ent.dofColour — the one solve
        app.displayGeometry(s); // paint: constraints — a hit
      }

      expect(Perf.counters['2d.displayGeometry.solves'], 10,
          reason: 'one solve per pointer-move, whatever asks for it');
      expect(Perf.counters['2d.displayGeometry.cacheHit'], 20);
    });

    test('a cursor move solves again', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      final start = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, start, 'end'));
      app.updateGripDrag(start + const Offset(4, 2));
      final first = app.displayGeometry(s);
      app.updateGripDrag(start + const Offset(8, 5));
      final second = app.displayGeometry(s);

      expect(identical(first, second), isFalse);
      expect(_maxDelta(first, second), greaterThan(1e-6),
          reason: 'the grip must follow the cursor');
    });
  });

  group('painted both ways — where collapsing is exact', () {
    test('a free line endpoint drag is bit-identical', () {
      final app = _app();
      final s = app.current!;
      s.geometry.add(Geo(Geo.line, [0, 0, 10, 0]));
      app.beginGripDrag(Grip(0, 1, const Offset(10, 0), 'end'));
      app.updateGripDrag(const Offset(14, 3));

      final once = app.displayGeometry(s);
      final twice = _paintAgainTheOldWay(app, s);
      expect(_maxDelta(once, twice), 0.0);
    });

    test('a body drag is bit-identical', () {
      // By construction: `prev = grip.isBody ? null : _lastGoodDragGeo`, so a
      // body drag never warm-starts and both calls begin from the committed
      // geometry.
      final app = _app();
      final s = app.current!;
      s.geometry.add(Geo(Geo.line, [0, 0, 10, 0]));
      app.beginGripDrag(Grip.body(0, const Offset(5, 0)));
      app.updateGripDrag(const Offset(9, 4));

      final once = app.displayGeometry(s);
      final twice = _paintAgainTheOldWay(app, s);
      expect(_maxDelta(once, twice), 0.0);
    });

    test('a cursor the constraints cannot reach is bit-identical', () {
      final app = _unreachable();
      final s = app.current!;
      app.beginGripDrag(Grip(0, 1, getPt(s.geometry[0], 1), 'end'));
      app.updateGripDrag(const Offset(60, 40));

      final once = app.displayGeometry(s);
      final twice = _paintAgainTheOldWay(app, s);
      expect(_maxDelta(once, twice), 0.0);
    });
  });

  group('painted both ways — the coupled system', () {
    // The one case that is NOT bit-identical, measured rather than waved at.
    // The second call was a convergence refinement, so removing it moves the
    // answer — by 3.2e-4 on a 64-unit sketch, five parts per million, and the
    // solver renders anything inside 1e-2 without complaint.
    test('the two regimes differ far inside the render tolerance', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      final start = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, start, 'end'));
      app.updateGripDrag(start + const Offset(6, 4));

      final once = app.displayGeometry(s);
      final twice = _paintAgainTheOldWay(app, s);
      final delta = _maxDelta(once, twice);

      expect(delta, greaterThan(0.0),
          reason: 'the second call really was doing arithmetic — if this ever '
              'goes to zero, the warm start has been changed and the whole '
              'argument in S4-painter.md needs re-deriving');
      expect(delta, lessThan(1e-3),
          reason: 'a convergence residual, not a different answer');
    });

    test('both regimes commit to the same constraint residual', () {
      // The difference is a point ON the constraint manifold, not a residual
      // off it. If that ever stops being true, the collapse is unsafe.
      List<Geo> run(int callsPerFrame) {
        final app = _twoCoupledSlots();
        final s = app.current!;
        var at = getPt(s.geometry[0], 1);
        app.beginGripDrag(Grip(0, 1, at, 'end'));
        for (var i = 1; i <= 60; i++) {
          at = at + const Offset(0.4, 0.25);
          app.updateGripDrag(at);
          app.displayGeometry(s);
          for (var c = 1; c < callsPerFrame; c++) {
            _paintAgainTheOldWay(app, s);
          }
        }
        app.endGripDrag();
        return List<Geo>.from(s.geometry);
      }

      final cs = _twoCoupledSlots().current!.constraints;
      final oneSolve = run(1);
      final twoSolves = run(2);

      final rOne = constraintResidualNorm(oneSolve, cs);
      final rTwo = constraintResidualNorm(twoSolves, cs);

      expect((rOne - rTwo).abs(), lessThan(1e-9),
          reason: 'both commits land on the manifold equally well');
      expect(_maxDelta(oneSolve, twoSolves), lessThan(1e-3),
          reason: 'and they land close together on it');
    });
  });

  group('the memo invalidates', () {
    test('when a new drag starts at the same cursor position', () {
      final app = _app();
      final s = app.current!;
      s.geometry.add(Geo(Geo.line, [0, 0, 10, 0]));
      s.geometry.add(Geo(Geo.line, [0, 5, 10, 5]));
      const cursor = Offset(14, 3);

      app.beginGripDrag(Grip(0, 1, const Offset(10, 0), 'end'));
      app.updateGripDrag(cursor);
      final first = app.displayGeometry(s);
      app.endGripDrag();

      // A DIFFERENT entity, dragged to the SAME point. Only the grip identity
      // distinguishes the two, which is the guard under test.
      app.beginGripDrag(Grip(1, 1, const Offset(10, 5), 'end'));
      app.updateGripDrag(cursor);
      final second = app.displayGeometry(s);

      expect(identical(first, second), isFalse);
      expect(getPt(second[1], 1).dx, closeTo(cursor.dx, 1e-6));
      expect(getPt(second[1], 1).dy, closeTo(cursor.dy, 1e-6));
    });

    test('when the geometry list is replaced under an unchanged cursor', () {
      final app = _app();
      final s = app.current!;
      s.geometry.add(Geo(Geo.line, [0, 0, 10, 0]));
      app.beginGripDrag(Grip(0, 1, const Offset(10, 0), 'end'));
      app.updateGripDrag(const Offset(14, 3));
      final first = app.displayGeometry(s);

      // Same values, new list identity — and a fresh solve must follow.
      s.geometry = List<Geo>.of(s.geometry);
      final second = app.displayGeometry(s);
      expect(identical(first, second), isFalse);

      // Different values too: the answer must track them.
      s.geometry = [Geo(Geo.line, [0, 20, 10, 20])];
      app.beginGripDrag(Grip(0, 1, const Offset(10, 20), 'end'));
      app.updateGripDrag(const Offset(14, 23));
      final third = app.displayGeometry(s);
      expect(getPt(third[0], 1).dy, closeTo(23, 1e-6));
    });

    test('when the sketch is switched', () {
      final app = _app();
      final a = app.current!;
      a.geometry.add(Geo(Geo.line, [0, 0, 10, 0]));
      final b = SketchModel('u');
      b.geometry.add(Geo(Geo.line, [0, 0, 10, 0]));
      app.sketches['u'] = b;

      app.beginGripDrag(Grip(0, 1, const Offset(10, 0), 'end'));
      app.updateGripDrag(const Offset(14, 3));
      final first = app.displayGeometry(a);
      final second = app.displayGeometry(b);

      expect(identical(first, second), isFalse,
          reason: 'a different sketch is a different question');
    });

    test('and is released when the drag ends', () {
      final app = _app();
      final s = app.current!;
      s.geometry.add(Geo(Geo.line, [0, 0, 10, 0]));
      app.beginGripDrag(Grip(0, 1, const Offset(10, 0), 'end'));
      app.updateGripDrag(const Offset(14, 3));
      app.displayGeometry(s);
      app.endGripDrag();

      // No drag in flight: the committed list itself, and no solve.
      Perf.resetForTest();
      final after = app.displayGeometry(s);
      expect(identical(after, s.geometry), isTrue);
      expect(Perf.counters['2d.displayGeometry.solves'], isNull);
      expect(Perf.counters['2d.displayGeometry.cacheHit'], isNull);
    });
  });

  group('the drag still behaves', () {
    test('nothing teleports along a sixty-frame path', () {
      // M207's property, re-asserted against one solve per frame: the whole
      // point of the warm start is that a drag is a path, and halving the
      // solves per frame must not let it jump between solution branches.
      final app = _twoCoupledSlots();
      final s = app.current!;
      var at = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, at, 'end'));

      var prev = app.displayGeometry(s);
      var worst = 0.0;
      for (var i = 1; i <= 60; i++) {
        at = at + const Offset(0.4, 0.25);
        app.updateGripDrag(at);
        final now = app.displayGeometry(s);
        final jump = _maxDelta(prev, now);
        if (jump > worst) worst = jump;
        prev = now;
      }

      // A frame step is |(0.4, 0.25)| = 0.47 units. A branch flip on this
      // fixture moves whole slots — tens of units.
      expect(worst, lessThan(5.0),
          reason: 'a jump this size is a different solution branch, which is '
              'exactly the M207 bug');
    });

    test('the commit satisfies the constraints', () {
      final app = _twoCoupledSlots();
      final s = app.current!;
      var at = getPt(s.geometry[0], 1);
      app.beginGripDrag(Grip(0, 1, at, 'end'));
      for (var i = 1; i <= 60; i++) {
        at = at + const Offset(0.4, 0.25);
        app.updateGripDrag(at);
        app.displayGeometry(s);
      }
      app.endGripDrag();

      expect(constraintResidualNorm(s.geometry, s.constraints), lessThan(1e-2),
          reason: 'the settle in endGripDrag pulls the drag onto the manifold '
              'however many display solves preceded it');
    });
  });
}
