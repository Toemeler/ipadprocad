// S4 — TEST (c): DOES THE DIFFERENCE ACCUMULATE UNDER REPETITION?
//
// The integrator's ruling on S4-2 narrowed plan §1's "bit-identical" rule to a
// three-part test, and asked for the one part I had not proven:
//
//   (a) the constraint residual is no worse
//   (b) the difference lies inside the tolerance the code declares for that
//       data path — a rendering tolerance covers rendering, never persistence
//   (c) it does not accumulate under repetition
//
//   "One drag differs by 2.6e-4; nothing yet says a hundred drags differ by
//    2.6e-4 rather than by 2.6e-2. If the gap grows with N, come back — that
//    is a different finding and a much more interesting one."
//
// IT GROWS. This file is that finding, pinned.
//
// What these tests assert is MEASURED BEHAVIOUR, not desired behaviour. They
// exist so that a future change to the drag/commit loop is noticed, and so the
// numbers in perf/findings/S4-painter.md §9 can be reproduced. If someone fixes
// the accumulation, these tests will fail — read this header, then update them
// and celebrate.
//
// The result in one line: committed geometry after N drags is not a function of
// the cursor path alone. It depends on how many refinement solves each frame
// happened to run, and that dependence compounds — linearly to N≈100, faster
// beyond. **The shipped application already has this property**: the 2-solve
// and 3-solve regimes below are both pre-existing behaviour (edit mode without
// a tool preview, and with one), and they diverge from each other the same way.
//
// N is small here to keep the suite fast. The §9 figures out to N=400 come from
// raising `_nDrags`; nothing else changes.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/constraints.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/snap.dart';
import 'package:prototype/solver.dart';

// The growth signal needs enough drags to separate from the per-lap wobble of
// the circular path. 60 x 4 is the smallest configuration where the exponent
// comes out clean; shrinking it further does not make the finding go away, it
// makes it unmeasurable, which is not the same thing. The determinism control
// and the jitter control assert flatness rather than growth, so they run
// shorter. Cost is ~35 s — noted in S4-painter.md §9 so the integrator can
// decide whether it belongs in the default suite.
const _nDrags = 60;
const _nShort = 15;
const _nJitter = 30;
const _stepsPerDrag = 4;
const _radius = 3.0;
const _perLap = 12;

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

/// The fixture M207 was written for: two slots coupled by a tangent and a cap
/// centre pinned onto the other slot's cap curve. The hardest constrained
/// system the repo can build, and the only one where collapsing the paint
/// solves changes a number at all.
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

/// Force a genuine extra solve at the same cursor: replace `s.geometry` with a
/// list holding the same immutable entities but a new identity, which trips the
/// one memo guard a test can trip without altering a number the solve reads.
void _invalidate(SketchModel s) => s.geometry = List<Geo>.of(s.geometry);

/// One complete drag of entity 0's endpoint through [path] (ABSOLUTE cursor
/// positions), committed through `endGripDrag`.
///
/// [solvesPerFrame]: 1 = the memo as shipped; 2 = the painter before it, in
/// edit mode; 3 = the painter before it, with a tool preview up as well.
/// `endGripDrag` opens with its own `displayGeometry` call — a hit under the
/// memo, a further solve before it — so that is reproduced too.
void _oneDrag(AppState app, List<Offset> path, {required int solvesPerFrame}) {
  final s = app.current!;
  app.beginGripDrag(Grip(0, 1, getPt(s.geometry[0], 1), 'end'));
  if (app.dragGrip == null) return;
  for (final at in path) {
    app.updateGripDrag(at);
    app.displayGeometry(s);
    for (var c = 1; c < solvesPerFrame; c++) {
      _invalidate(s);
      app.displayGeometry(s);
    }
  }
  if (solvesPerFrame > 1) _invalidate(s);
  app.endGripDrag();
}

class _Race {
  final List<double> gaps;
  final List<double> residualA;
  final List<double> residualB;
  _Race(this.gaps, this.residualA, this.residualB);
}

/// Runs two regimes side by side over [_nDrags] drags on ONE shared stream of
/// ABSOLUTE cursor positions, so neither regime's own state can steer the
/// input and any divergence is accumulated internal state alone.
_Race _race(int solvesA, int solvesB, {int n = _nDrags}) {
  final a = _twoCoupledSlots(), b = _twoCoupledSlots();
  final anchor = getPt(a.current!.geometry[0], 1);
  var prev = anchor;
  final gaps = <double>[], rA = <double>[], rB = <double>[];
  for (var k = 1; k <= n; k++) {
    final th = 2 * math.pi * (k % _perLap) / _perLap;
    final target =
        anchor + Offset(_radius * math.cos(th), _radius * math.sin(th));
    final path = [
      for (var i = 1; i <= _stepsPerDrag; i++)
        Offset.lerp(prev, target, i / _stepsPerDrag)!
    ];
    prev = target;
    _oneDrag(a, path, solvesPerFrame: solvesA);
    _oneDrag(b, path, solvesPerFrame: solvesB);
    gaps.add(_maxDelta(a.current!.geometry, b.current!.geometry));
    rA.add(constraintResidualNorm(
        a.current!.geometry, a.current!.constraints));
    rB.add(constraintResidualNorm(
        b.current!.geometry, b.current!.constraints));
  }
  return _Race(gaps, rA, rB);
}

/// Same, but B's cursor stream is displaced by [jitter] — an INPUT
/// perturbation rather than a solve-count one.
_Race _raceJitter(int solves, double jitter, {int n = _nJitter}) {
  final a = _twoCoupledSlots(), b = _twoCoupledSlots();
  final anchor = getPt(a.current!.geometry[0], 1);
  var prev = anchor;
  final gaps = <double>[], rA = <double>[], rB = <double>[];
  for (var k = 1; k <= n; k++) {
    final th = 2 * math.pi * (k % _perLap) / _perLap;
    final target =
        anchor + Offset(_radius * math.cos(th), _radius * math.sin(th));
    final path = [
      for (var i = 1; i <= _stepsPerDrag; i++)
        Offset.lerp(prev, target, i / _stepsPerDrag)!
    ];
    prev = target;
    _oneDrag(a, path, solvesPerFrame: solves);
    _oneDrag(b, [for (final p in path) p + Offset(jitter, 0)],
        solvesPerFrame: solves);
    gaps.add(_maxDelta(a.current!.geometry, b.current!.geometry));
    rA.add(constraintResidualNorm(
        a.current!.geometry, a.current!.constraints));
    rB.add(constraintResidualNorm(
        b.current!.geometry, b.current!.constraints));
  }
  return _Race(gaps, rA, rB);
}

/// Races are expensive (each is 2 x _nDrags full drags with a commit each), so
/// every distinct pair is computed once and shared across the tests below.
final _cache = <String, _Race>{};
_Race _cached(int a, int b) => _cache.putIfAbsent('$a-$b', () => _race(a, b));
final _cachedJitter = <double, _Race>{};
_Race _cachedJit(double j) =>
    _cachedJitter.putIfAbsent(j, () => _raceJitter(2, j));

/// Mean of the first / last tenth — robust against the per-lap wobble that
/// makes any single drag's gap a poor estimate on its own.
double _meanFirstTenth(List<double> g) {
  final n = math.max(1, g.length ~/ 10);
  return g.take(n).reduce((x, y) => x + y) / n;
}

double _meanLastTenth(List<double> g) {
  final n = math.max(1, g.length ~/ 10);
  return g.skip(g.length - n).reduce((x, y) => x + y) / n;
}

/// log-log slope of gap against drag number. 1.0 = linear growth,
/// 0.5 = a random walk, 0.0 = saturated (no accumulation).
double _exponent(List<double> g) {
  var sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0, n = 0;
  for (var i = g.length ~/ 6; i < g.length; i++) {
    if (g[i] <= 0) continue;
    final x = math.log((i + 1).toDouble()), y = math.log(g[i]);
    sx += x;
    sy += y;
    sxx += x * x;
    sxy += x * y;
    n++;
  }
  return (n * sxy - sx * sy) / (n * sxx - sx * sx);
}

void main() {
  group('(c) accumulation under repetition', () {
    test('control: identical regimes stay bit-identical for every drag', () {
      // If this ever fails, the harness is nondeterministic and every other
      // number in this file is noise rather than signal. It is the first thing
      // to check, not the last.
      final r = _race(2, 2, n: _nShort);
      expect(r.gaps.reduce(math.max), 0.0);
    });

    test('(a) HOLDS under repetition — the residual never degrades', () {
      // This is the part that passes, and it is the part that matters for
      // validity: both regimes stay exactly as satisfied as they started. The
      // states drift ALONG the constraint manifold, never off it.
      final r = _cached(1, 2);
      final first = r.residualA.first;
      for (var i = 0; i < r.gaps.length; i++) {
        expect((r.residualA[i] - first).abs(), lessThan(1e-9),
            reason: 'regime A residual moved at drag ${i + 1}');
        expect((r.residualB[i] - first).abs(), lessThan(1e-9),
            reason: 'regime B residual moved at drag ${i + 1}');
      }
    });

    test('(c) FAILS — the gap grows at least linearly with the drag count', () {
      final r = _cached(1, 2);
      final k = _exponent(r.gaps);
      expect(k, greaterThan(0.8),
          reason: 'measured ~1.0 (linear) over this range. A saturating gap '
              'would sit near 0 and (c) would be satisfied; it does not.');
      final grew = _meanLastTenth(r.gaps) / _meanFirstTenth(r.gaps);
      expect(grew, greaterThan(5.0),
          reason: 'the last tenth of $_nDrags drags sits ~16x above the first '
              'tenth. A bounded difference would sit near 1.');
    });

    test('and the PRE-EXISTING regimes fail it the same way — 2 solves vs 3',
        () {
      // The control that decides what this finding means. Neither of these is
      // my change: 2 solves per frame is what the painter did in edit mode,
      // 3 is what it did with a tool preview open as well. Both shipped. If
      // they diverge from each other under repetition too, then linear
      // accumulation is a property of the drag/commit loop rather than
      // something the memo introduced.
      final r = _cached(2, 3);
      final k = _exponent(r.gaps);
      expect(k, greaterThan(0.8),
          reason: 'the shipped application already accumulates divergence '
              'between two of its own UI modes, at the same exponent');
      final first = r.residualA.first;
      expect((r.residualA.last - first).abs(), lessThan(1e-9));
      expect((r.residualB.last - first).abs(), lessThan(1e-9));
    });

    test('the channel is the solve count, not input sensitivity', () {
      // A perturbed CURSOR washes out; a perturbed SOLVE COUNT compounds. So
      // the loop is not generically chaotic — it is specifically the number of
      // refinement iterations that decides where on the manifold each commit
      // lands, and that offset is systematic rather than random.
      final jit = _cachedJit(1e-6);
      final k = _exponent(jit.gaps);
      expect(k, lessThan(0.6),
          reason: 'a 1e-6 cursor displacement does NOT accumulate — measured '
              'flat, against ~1.0 for a one-solve difference');
    });
  });
}
