// M219 — the two spline defects reported from the device:
//
//   "I can't trim splines. It's really fucked up."
//   "Also splines are low resolution sometimes."
//
// (1) TRIM. A spline is stored as a POLYLINE of control/fit points plus a
//     Dart-side tag, so Trim and Split fell through to the plain-polyline
//     branch and cut the CONTROL POLYGON — for a CV spline a chain of straight
//     lines that does not even touch the curve. What came back was a straight
//     fragment re-tagged as a spline: a different curve, in a different place.
//     An ellipse was worse still (its three vertices are centre/major/minor, so
//     "the clicked segment" was a radius).
//     Now every spline kind is converted to its EXACT cubic Bézier chain
//     (bezier.dart), cut there by de Casteljau — which is lossless — and stored
//     back as Geo.splineBez. A trimmed spline is the same curve, only shorter.
//
// (2) RESOLUTION. splineCurveFor returned the curve decimated onto a chain of
//     true arcs with five points per arc. That chain exists for the 3D profile
//     path, where arcFitLoop turns those points back into exact bulges — but as
//     a DISPLAY curve it is terrible, because the tolerance it respects is the
//     arc's, not that of the five chords drawn between its points. Rendering,
//     picking and snapping now get the real curve, sampled to a tolerance; the
//     painter passes a tolerance derived from the ZOOM, so the curve is smooth
//     at whatever magnification it is being looked at.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/bezier.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/modify.dart';
import 'package:prototype/part_model.dart' show arcFitLoop;
import 'package:prototype/pick_math.dart';
import 'package:prototype/snap.dart';
import 'package:prototype/spline.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

/// Largest distance from any point of [from] to the polyline [to].
///
/// Note the floor of every measurement made with this: a REFERENCE chain of
/// 20 000 de Boor samples still carries a couple of microns of its own chord
/// error, so `< 1e-5` is the tightest honest bound for "this piece lies on that
/// curve". The exactness itself is proved a group higher up, against the
/// closed-form samplers at 1e-9.
double maxDev(List<Offset> from, List<Offset> to) {
  if (to.length < 2) return double.infinity;
  var worst = 0.0;
  for (final p in from) {
    var best = double.infinity;
    for (var i = 0; i + 1 < to.length; i++) {
      final d = (p - closestOnSegment(p, to[i], to[i + 1])).distance;
      if (d < best) best = d;
    }
    if (best > worst) worst = best;
  }
  return worst;
}

/// Largest distance from any point of [from] to the NEAREST of [chains] — how
/// far the original curve is from being covered by a set of pieces.
double maxDevToAny(List<Offset> from, List<List<Offset>> chains) {
  var worst = 0.0;
  for (final p in from) {
    var best = double.infinity;
    for (final c in chains) {
      for (var i = 0; i + 1 < c.length; i++) {
        final d = (p - closestOnSegment(p, c[i], c[i + 1])).distance;
        if (d < best) best = d;
      }
    }
    if (best > worst) worst = best;
  }
  return worst;
}

double chainLength(List<Offset> p) {
  var s = 0.0;
  for (var i = 0; i + 1 < p.length; i++) {
    s += (p[i + 1] - p[i]).distance;
  }
  return s;
}

double maxChord(List<Offset> p) {
  var s = 0.0;
  for (var i = 0; i + 1 < p.length; i++) {
    final d = (p[i + 1] - p[i]).distance;
    if (d > s) s = d;
  }
  return s;
}

Geo cvSpline(List<Offset> cv, {bool closed = false}) => Geo(Geo.polyline, [
      closed ? 1.0 : 0.0,
      cv.length.toDouble(),
      for (final p in cv) ...[p.dx, p.dy],
    ]).asSpline(Geo.splineCv);

Geo fitSpline(List<Offset> p, {bool closed = false}) => Geo(Geo.polyline, [
      closed ? 1.0 : 0.0,
      p.length.toDouble(),
      for (final q in p) ...[q.dx, q.dy],
    ]).asSpline(Geo.splineFit);

/// The arch used throughout: a 100 mm open CV spline rising to ~y=45.
final archCv = const [
  Offset(0, 0),
  Offset(30, 60),
  Offset(70, 60),
  Offset(100, 0),
];

/// A vertical cutter at [x].
Geo cutter(double x) => Geo(Geo.line, [x, -20, x, 90]);

void main() {
  setUp(clearSplineCurveCache);

  // -------------------------------------------------------------------------
  group('the exact Bézier form of every spline kind', () {
    // The reference is the sampler that has always drawn these curves
    // (de Boor / Catmull-Rom in spline.dart). The Bézier chain is a change of
    // BASIS, not a fit, so the two must agree to machine precision — that is
    // what makes cutting the chain the same as cutting the curve.

    test('a clamped CV spline is reproduced to machine precision', () {
      for (var n = 4; n <= 12; n++) {
        final cv = [
          for (var i = 0; i < n; i++)
            Offset(i * 17.0, 40 * math.sin(i * 1.1) + 3 * i)
        ];
        final path = bezPathOf(cvSpline(cv))!;
        expect(path.count, n - 3,
            reason: 'a clamped cubic with $n CVs has ${n - 3} Bézier spans');
        const ns = 600;
        final ref = bsplineCurve(cv, samples: ns);
        var worst = 0.0;
        for (var i = 0; i <= ns; i++) {
          final u = (i == ns ? 1.0 - 1e-12 : i / ns) * path.count;
          final d = (path.at(u) - ref[i]).distance;
          if (d > worst) worst = d;
        }
        expect(worst, lessThan(1e-9), reason: 'n=$n');
      }
    });

    test('a closed PERIODIC CV spline is reproduced', () {
      for (var m = 3; m <= 9; m++) {
        final cv = [
          for (var i = 0; i < m; i++)
            Offset(50 * math.cos(2 * math.pi * i / m),
                35 * math.sin(2 * math.pi * i / m))
        ];
        final path = bezPathOf(cvSpline(cv, closed: true))!;
        expect(path.closed, isTrue);
        expect(path.count, m);
        const ns = 480;
        final ref = bsplineCurve(cv, closed: true, samples: ns);
        var worst = 0.0;
        for (var i = 0; i < ns; i++) {
          final d = (path.at(m * i / ns) - ref[i]).distance;
          if (d > worst) worst = d;
        }
        expect(worst, lessThan(1e-9), reason: 'm=$m');
      }
    });

    test('a fit (Catmull-Rom) spline is reproduced, open and closed', () {
      for (final closed in [false, true]) {
        for (var m = 3; m <= 8; m++) {
          final p = [
            for (var i = 0; i < m; i++)
              Offset(20.0 * i, 30 * math.sin(i * 0.9))
          ];
          final path = bezPathOf(fitSpline(p, closed: closed))!;
          const per = 24;
          final ref = fitCurve(p, closed: closed, perSeg: per);
          // a closed fitCurve repeats its first point at the end; the chain
          // parameter only runs to segs, so stop there
          final segs = closed ? m : m - 1;
          var worst = 0.0;
          for (var i = 0; i <= per * segs; i++) {
            final d = (path.at(i / per) - ref[i]).distance;
            if (d > worst) worst = d;
          }
          expect(worst, lessThan(1e-9), reason: 'closed=$closed m=$m');
        }
      }
    });

    test('an ellipse is reproduced to a fraction of a micron', () {
      final g = Geo(Geo.polyline, [1, 3, 10, 5, 90, 5, 10, 45])
          .asSpline(Geo.ellipseTag);
      final path = bezPathOf(g)!;
      const c = Offset(10, 5);
      const a = 80.0, b = 40.0;
      var worst = 0.0;
      for (var i = 0; i <= 2000; i++) {
        final p = path.at(path.count * i / 2000);
        // implicit ellipse residual, converted back to a distance
        final dx = (p.dx - c.dx) / a, dy = (p.dy - c.dy) / b;
        final r = math.sqrt(dx * dx + dy * dy);
        final d = ((r - 1).abs() * math.min(a, b));
        if (d > worst) worst = d;
      }
      expect(worst, lessThan(1e-5),
          reason: 'the ellipse must stay an ellipse in Bézier form');
    });

    test('a Bézier chain round-trips through a Geo unchanged', () {
      final path = bezPathOf(cvSpline(archCv))!;
      final g = bezGeo(path)!;
      expect(g.spline, Geo.splineBez);
      expect(g.data[1].toInt(), 3 * path.count + 1);
      final back = bezPathOf(g)!;
      expect(back.count, path.count);
      var worst = 0.0;
      for (var i = 0; i <= 500; i++) {
        final u = path.count * i / 500;
        final d = (back.at(u) - path.at(u)).distance;
        if (d > worst) worst = d;
      }
      expect(worst, lessThan(1e-12));
      // ...and it samples as the very same curve the CV spline did
      expect(maxDev(splineCurveFor(g), splineCurveFor(cvSpline(archCv))),
          lessThan(1e-6));
    });
  });

  // -------------------------------------------------------------------------
  group('Trim cuts the curve, not the control polygon', () {
    late Geo sp;
    late List<Geo> gs;
    late List<Offset> full; // the model chain, as the app samples it
    late List<Offset> truth; // 20 000 exact de Boor samples, for measuring
    late Offset midClick;

    setUp(() {
      sp = cvSpline(archCv);
      gs = [sp, cutter(25), cutter(75)];
      full = splineCurveFor(sp);
      truth = bsplineCurve(archCv, samples: 20000);
      midClick = full[full.length ~/ 2];
    });

    test('the surviving pieces lie ON the original curve', () {
      final kept = trimEntity(gs, 0, midClick);
      expect(kept, hasLength(2),
          reason: 'two cutters leave the two outer spans');
      for (final piece in kept) {
        expect(piece.type, Geo.polyline);
        expect(piece.spline, Geo.splineBez,
            reason: 'a cut spline is still a spline');
        expect(maxDev(splineCurveFor(piece), truth), lessThan(1e-5),
            reason: 'the piece must be the SAME curve, only shorter');
      }
    });

    test('a piece is still CURVED — the old bug handed back a straight line',
        () {
      final kept = trimEntity(gs, 0, midClick);
      // the left piece runs from (0,0) up to the x=25 crossing
      final left = kept.firstWhere((g) => splineCurveFor(g).first.dx < 1);
      final c = splineCurveFor(left);
      final chord = [c.first, c.last];
      expect(maxDev(c, chord), greaterThan(1.0),
          reason: 'the kept span bulges millimetres off its own chord; a '
              'straight fragment would score ~0 here');
    });

    test('the cut span and the kept spans partition the original curve', () {
      final kept = trimEntity(gs, 0, midClick);
      final cut = trimCutAway(gs, 0, midClick);
      expect(cut, hasLength(1));
      // sampled tight: this measures the GEOMETRY, and a piece's own model
      // tolerance would otherwise show up as the deviation being measured
      final chains = [
        for (final g in [...kept, ...cut]) splineCurveFor(g, tolMm: 1e-7)
      ];
      // nothing of the original is lost. The bound is loose on purpose: this
      // direction measures a dense truth against the pieces' own FLATTENED
      // chains, so its floor is their chord error (~1e-5). A gap would be
      // millimetres, and the length sum below pins the microns.
      expect(maxDevToAny(truth, chains), lessThan(1e-3));
      // ...and nothing is covered twice: the pieces' lengths add up to the
      // original's, which they cannot do if any two of them overlap.
      final sum = chains.fold<double>(0, (a, c) => a + chainLength(c));
      expect(sum, closeTo(chainLength(truth), chainLength(truth) * 1e-4));
    });

    test('the CLICKED span is the one that goes', () {
      final cut = trimCutAway(gs, 0, midClick);
      final c = splineCurveFor(cut.single);
      // the removed span is the middle one: it spans x=25..75 and contains
      // the click, and the survivors do not
      expect(maxDev([midClick], c), lessThan(1e-6));
      for (final g in trimEntity(gs, 0, midClick)) {
        expect(maxDev([midClick], splineCurveFor(g)), greaterThan(1.0));
      }
    });

    test('one cutter leaves one piece, on the far side of the click', () {
      final one = [sp, cutter(25)];
      final click = splineCurveFor(sp).last; // near the x=100 end
      final kept = trimEntity(one, 0, click);
      expect(kept, hasLength(1));
      final c = splineCurveFor(kept.single);
      expect(c.first.dx, closeTo(0, 1e-9),
          reason: 'the span from the start up to the cut survives');
      expect(c.last.dx, closeTo(25, 1e-9),
          reason: 'the cut lands ON the cutting line, not a tolerance beside '
              'it — the crossing is refined against the cutter itself');
      expect(maxDev(c, truth), lessThan(1e-5));
    });

    test('nothing crossing it deletes the whole spline (Inventor)', () {
      expect(trimEntity([sp], 0, midClick), isEmpty);
      expect(trimCutAway([sp], 0, midClick), hasLength(1));
    });

    test('a CLOSED spline keeps the complement of the clicked span', () {
      final ring = cvSpline(const [
        Offset(-50, 0),
        Offset(0, 40),
        Offset(50, 0),
        Offset(0, -40),
      ], closed: true);
      final ringCurve = splineCurveFor(ring);
      final gsR = [ring, Geo(Geo.line, [-80, 0, 80, 0])]; // cuts left & right
      // click on the TOP half
      final top = ringCurve.reduce((a, b) => a.dy > b.dy ? a : b);
      final kept = trimEntity(gsR, 0, top);
      expect(kept, hasLength(1));
      final c = splineCurveFor(kept.single);
      expect(maxDev(c, bsplineCurve(polyPoints(ring), closed: true, samples: 20000)),
          lessThan(1e-5));
      final ys = c.map((p) => p.dy).toList();
      expect(ys.reduce(math.min), lessThan(-1),
          reason: 'what survives is the BOTTOM half');
      expect(ys.reduce(math.max), lessThan(1e-6));
    });

    test('an ELLIPSE trims to an elliptical piece, not to one of its radii',
        () {
      // The worst of the old behaviour: an ellipse stores [centre, major,
      // minor], so the "clicked segment" of its control polygon was the line
      // from the centre to a vertex — trimming an ellipse produced a radius.
      final el = Geo(Geo.polyline, [1, 3, 0, 0, 60, 0, 0, 30])
          .asSpline(Geo.ellipseTag);
      final elCurve = splineCurveFor(el);
      final gsE = [el, Geo(Geo.line, [-80, 0, 80, 0])];
      final top = elCurve.reduce((a, b) => a.dy > b.dy ? a : b);
      final kept = trimEntity(gsE, 0, top);
      expect(kept, hasLength(1));
      final c = splineCurveFor(kept.single);
      expect(maxDev(c, ellipseCurve(polyPoints(el), samples: 20000)),
          lessThan(1e-4),
          reason: 'every point of the piece is still on the ellipse');
      // it is the BOTTOM half, and it really is half an ellipse
      expect(c.map((p) => p.dy).reduce(math.min), closeTo(-30, 1e-3));
      expect(chainLength(c), closeTo(chainLength(elCurve) / 2, 0.5));
    });

    test('a fit spline trims like a CV spline', () {
      final fs = fitSpline(const [
        Offset(0, 0),
        Offset(25, 40),
        Offset(50, 0),
        Offset(75, -40),
        Offset(100, 0),
      ]);
      final fc = splineCurveFor(fs);
      // the curve dips to y=-40, so the cutters have to reach down there
      final gsF = [
        fs,
        Geo(Geo.line, [20, -80, 20, 90]),
        Geo(Geo.line, [80, -80, 80, 90]),
      ];
      final kept = trimEntity(gsF, 0, fc[fc.length ~/ 2]);
      expect(kept, hasLength(2));
      final fitTruth = fitCurve(polyPoints(fs), perSeg: 8000);
      for (final piece in kept) {
        expect(maxDev(splineCurveFor(piece), fitTruth), lessThan(1e-5));
      }
    });

    test('the layer and the line style ride along', () {
      final styled = cvSpline(archCv)
          .onLayer('Sketch2')
          .withStyle(Geo.styleCenterline);
      final kept = trimEntity([styled, cutter(25), cutter(75)], 0, midClick);
      expect(kept, isNotEmpty);
      for (final g in kept) {
        expect(g.layer, 'Sketch2');
        expect(g.style, Geo.styleCenterline);
        expect(g.spline, Geo.splineBez,
            reason: 'the piece carries its OWN tag; _carry must not stamp the '
                'source tag onto a different number of vertices');
      }
    });

    test('a trimmed piece can be trimmed again and stays on the curve', () {
      final kept = trimEntity(gs, 0, midClick);
      final left = kept.firstWhere((g) => splineCurveFor(g).first.dx < 1);
      final lc = splineCurveFor(left);
      final again = trimEntity([left, cutter(12)], 0, lc.first);
      expect(again, hasLength(1));
      expect(maxDev(splineCurveFor(again.single), truth), lessThan(1e-5),
          reason: 'cutting a cut spline is still exact');
    });

    test('a ROUND cutter cuts just as exactly', () {
      // The crossing with a circle is analytic on the circle's side and
      // sampled on the spline's, so the refinement has to slide it along the
      // curve onto the rim — this is the case that proves it does.
      final circle = Geo(Geo.circle, [50, 60, 30]);
      final kept = trimEntity([sp, circle], 0, midClick);
      expect(kept, hasLength(2));
      for (final g in kept) {
        final c = splineCurveFor(g);
        final ends = [c.first, c.last];
        final onRim = ends.where(
            (p) => ((p - const Offset(50, 60)).distance - 30).abs() < 1e-9);
        expect(onRim, hasLength(1),
            reason: 'exactly one end of each piece sits ON the circle');
      }
    });

    test('a spline can cut another spline', () {
      final other = fitSpline(const [
        Offset(10, 60),
        Offset(50, -10),
        Offset(90, 60),
      ]);
      final kept = trimEntity([sp, other], 0, midClick);
      expect(kept, hasLength(2));
      for (final g in kept) {
        expect(maxDev(splineCurveFor(g), truth), lessThan(1e-5));
      }
    });

    test('the cut lands exactly on the intersection', () {
      final kept = trimEntity(gs, 0, midClick);
      final xs = <double>[
        for (final g in kept) ...[
          splineCurveFor(g).first.dx,
          splineCurveFor(g).last.dx,
        ]
      ];
      expect(xs.where((x) => (x - 25).abs() < 1e-9), hasLength(1));
      expect(xs.where((x) => (x - 75).abs() < 1e-9), hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  group('Split cuts the curve too', () {
    test('both halves are on the original curve and meet at the cut', () {
      final sp = cvSpline(archCv);
      final gs = [sp, cutter(60)];
      final full = splineCurveFor(sp);
      final plan = planSplit(gs, 0, full[full.length ~/ 4])!;
      expect(plan.pieces, hasLength(2));
      expect(plan.cuts, hasLength(1));
      expect(plan.cuts.single.dx, closeTo(60, 1e-9));
      final truth = bsplineCurve(archCv, samples: 20000);
      final chains = [
        for (final g in plan.pieces) splineCurveFor(g, tolMm: 1e-7)
      ];
      for (final c in chains) {
        expect(maxDev(c, truth), lessThan(1e-5));
      }
      expect(maxDevToAny(truth, chains), lessThan(1e-3));
      final sum = chains.fold<double>(0, (a, c) => a + chainLength(c));
      expect(sum, closeTo(chainLength(truth), chainLength(truth) * 1e-4));
      // the hovered piece is the one the cursor was on — the OTHER piece is
      // tens of millimetres away, so this is not a close call
      expect(maxDev([full[full.length ~/ 4]], chains[plan.hovered]),
          lessThan(1e-4));
      expect(maxDev([full[full.length ~/ 4]], chains[1 - plan.hovered]),
          greaterThan(1.0));
    });

    test('a closed spline splits into the two spans around the cursor', () {
      final ring = cvSpline(const [
        Offset(-50, 0),
        Offset(0, 40),
        Offset(50, 0),
        Offset(0, -40),
      ], closed: true);
      final full = splineCurveFor(ring);
      final gs = [ring, Geo(Geo.line, [-80, 0, 80, 0])];
      final top = full.reduce((a, b) => a.dy > b.dy ? a : b);
      final plan = planSplit(gs, 0, top)!;
      expect(plan.pieces, hasLength(2));
      final chains = [
        for (final g in plan.pieces) splineCurveFor(g, tolMm: 1e-7)
      ];
      expect(
          maxDevToAny(
              bsplineCurve(polyPoints(ring), closed: true, samples: 20000),
              chains),
          lessThan(1e-3));
    });
  });

  // -------------------------------------------------------------------------
  group('resolution', () {
    test('the sampled curve honours the tolerance it is asked for', () {
      final sp = cvSpline(archCv);
      final truth = bsplineCurve(archCv, samples: 20000);
      for (final tol in [1e-1, 1e-2, 1e-3, 1e-4]) {
        clearSplineCurveCache();
        final c = splineCurveFor(sp, tolMm: tol);
        expect(maxDev(truth, c), lessThan(tol * 1.5),
            reason: 'tol=$tol produced ${c.length} points');
      }
    });

    test('a long gentle spline is no longer a chain of 10 mm chords', () {
      // The reported symptom, measured. The old pipeline decimated this curve
      // onto ~6 arcs and emitted 5 points per arc: 25 points, ~10 mm apart,
      // 0.17 mm off the true curve — a visible polygon at any working zoom.
      final cv = const [
        Offset(0, 0),
        Offset(60, 80),
        Offset(140, 80),
        Offset(200, 0),
      ];
      final sp = cvSpline(cv);
      final c = splineCurveFor(sp);
      final truth = bsplineCurve(cv, samples: 20000);
      expect(maxDev(truth, c), lessThan(5e-3),
          reason: 'the model curve is accurate to microns, not to a fifth of '
              'a millimetre');
      expect(maxChord(c), lessThan(2.0),
          reason: 'no 10 mm facets left');
    });

    test('zooming in samples finer, zooming out samples coarser', () {
      final sp = cvSpline(archCv);
      final far = splineCurveFor(sp, tolMm: splineDisplayTol(0.5));
      final near = splineCurveFor(sp, tolMm: splineDisplayTol(400));
      expect(splineDisplayTol(400), lessThan(splineDisplayTol(0.5)));
      expect(near.length, greaterThan(far.length),
          reason: 'the display curve follows the magnification');
      // and at 400 px/mm the chain is within a fifth of a pixel of the truth
      final truth = bsplineCurve(archCv, samples: 20000);
      expect(maxDev(truth, near) * 400, lessThan(0.5));
    });

    test('the display tolerance is bucketed, so a pinch does not thrash', () {
      // A pinch walks the scale continuously. Bucketed to powers of two, a
      // whole octave of zoom shares ONE tolerance — so the sampled curve is
      // rebuilt about once per doubling, not once per frame.
      final seen = <double>{
        for (var k = 0; k < 100; k++) splineDisplayTol(100.0 + k)
      };
      expect(seen.length, lessThanOrEqualTo(2),
          reason: 'zoom 100..200 px/mm is one octave: at most two buckets');
      expect(splineDisplayTol(400), lessThan(splineDisplayTol(100)));
      expect(splineDisplayTol(0), greaterThan(0)); // never divides by zero
      expect(splineDisplayTol(double.nan), greaterThan(0));
      expect(splineDisplayTol(double.infinity), greaterThan(0));
    });

    test('an ellipse follows the tolerance as well', () {
      final el = Geo(Geo.polyline, [1, 3, 0, 0, 200, 0, 0, 120])
          .asSpline(Geo.ellipseTag);
      final coarse = splineCurveFor(el, tolMm: 1e-1);
      final fine = splineCurveFor(el, tolMm: 1e-4);
      expect(fine.length, greaterThan(coarse.length));
      expect(maxDev(ellipseCurve(polyPoints(el), samples: 20000), fine),
          lessThan(1.5e-4));
      // the historical 96-sample floor is never undercut
      expect(coarse.length, greaterThanOrEqualTo(97));
    });

    test('the 3D arc chain still recovers arcs — and no longer runs out', () {
      // The arc chain is what the kernel gets, and it must still collapse into
      // few true arcs. The old 64-arc budget was spent before the end of a long
      // spline, and _greedySpans then covered the whole remainder with ONE arc:
      // the tail of the profile simply left the curve.
      final cv = [
        for (var i = 0; i < 40; i++) Offset(i * 5.0, 20 * math.sin(i * 0.7))
      ];
      final sp = cvSpline(cv);
      final chain = splineArcChain(sp);
      final full = splineCurveFor(sp);
      expect(maxDev(chain, full), lessThan(0.06),
          reason: 'every arc-chain point sits on the curve, all the way to '
              'the far end');
      final segs = arcFitLoop(chain);
      expect(segs.length, lessThan(chain.length ~/ 3),
          reason: 'the chain still collapses into true arcs for the kernel');
      expect(segs.any((s) => s.bulge.abs() > 1e-6), isTrue);
    });

    test('a spline is still hit-testable on its curve, not on its hull', () {
      final sp = cvSpline(archCv);
      final onCurve = splineCurveFor(sp)[40];
      expect(distToEntity(sp, onCurve), lessThan(1e-6));
      // a control vertex of a CV spline is OFF the curve — that is the whole
      // point of the kind, and the hit test must agree
      expect(distToEntity(sp, const Offset(30, 60)), greaterThan(5.0));
    });
  });

  // -------------------------------------------------------------------------
  group('end to end, through the tool the user actually taps', () {
    // The unit tests above cut a Geo. This one runs the whole path: pick,
    // trim, constraint remap, solve, engine rebuild, and the refresh that
    // reads the geometry back OUT of the (spline-less) backend. That last step
    // is where a spline has always been at risk — the core hands back a plain
    // polyline and the tag is reapplied by index.
    test('tapping Trim on a spline leaves curved spline pieces', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addPolyline([0, 0, 30, 60, 70, 60, 100, 0]);
      s.engine.addLine(25, -20, 25, 90);
      s.engine.addLine(75, -20, 75, 90);
      s.refresh(tagSource: [cvSpline(archCv)]);
      expect(s.geometry[0].spline, Geo.splineCv);

      final full = splineCurveFor(s.geometry[0]);
      app.selectTool(Tool.trim);
      app.toolClick(full[full.length ~/ 2]);

      final pieces = s.geometry
          .where((g) => g.type == Geo.polyline && !g.isConstruction)
          .toList();
      expect(pieces, hasLength(2), reason: 'the middle span was cut out');
      final truth = bsplineCurve(archCv, samples: 20000);
      for (final g in pieces) {
        expect(g.spline, Geo.splineBez,
            reason: 'the tag survived _rebuildEngine + refresh');
        final c = splineCurveFor(g);
        expect(maxDev(c, truth), lessThan(1e-5),
            reason: 'still the same curve after the engine round-trip');
        expect(maxDev(c, [c.first, c.last]), greaterThan(1.0),
            reason: 'and still curved, not a straight fragment');
      }
      // M191: the removed span stays as construction geometry, and it is a
      // spline too — the ghost has to follow the shape it was cut from.
      final ghosts = s.geometry.where((g) => g.isConstruction).toList();
      expect(ghosts, hasLength(1));
      expect(ghosts.single.spline, Geo.splineBez);
      expect(maxDev(splineCurveFor(ghosts.single), truth), lessThan(1e-5));
    });

    test('tapping Trim on an ellipse leaves half an ellipse', () {
      final app = makeApp();
      final s = app.current!;
      s.engine.addPolyline([0, 0, 60, 0, 0, 30], closed: true);
      s.engine.addLine(-80, 0, 80, 0);
      s.refresh(tagSource: [
        Geo(Geo.polyline, [1, 3, 0, 0, 60, 0, 0, 30]).asSpline(Geo.ellipseTag)
      ]);
      expect(s.geometry[0].spline, Geo.ellipseTag);
      final el = splineCurveFor(s.geometry[0]);
      final top = el.reduce((a, b) => a.dy > b.dy ? a : b);

      app.selectTool(Tool.trim);
      app.toolClick(top);

      final kept = s.geometry
          .where((g) => g.type == Geo.polyline && !g.isConstruction)
          .toList();
      expect(kept, hasLength(1));
      final c = splineCurveFor(kept.single);
      expect(maxDev(c, ellipseCurve(const [Offset(0, 0), Offset(60, 0), Offset(0, 30)],
              samples: 20000)),
          lessThan(1e-4),
          reason: 'the survivor is still ON the ellipse — the old trim handed '
              'back a piece of the centre-to-vertex radius');
      expect(c.map((p) => p.dy).reduce(math.min), closeTo(-30, 1e-3));
    });
  });

  // -------------------------------------------------------------------------
  group('a gear is BAKED by a cut, never silently mangled', () {
    test('trimming a gear leaves plain geometry on the outline', () {
      final gear = Geo(Geo.polyline, [
        1, 2, // closed, two defining vertices
        0, 0, // centre
        20, 0, // handle
        2.0, 20.0, 20.0, 0.0, 0.0, 0.0, // module, teeth, angle, shift, ...
      ]).asSpline(Geo.gearTag);
      final outline = splineCurveFor(gear);
      expect(outline.length, greaterThan(50),
          reason: 'the fixture must really be a generated gear outline');
      final gs = [gear, Geo(Geo.line, [-60, 0, 60, 0])];
      final top = outline.reduce((a, b) => a.dy > b.dy ? a : b);
      final kept = trimEntity(gs, 0, top);
      expect(kept, isNotEmpty);
      for (final g in kept) {
        expect(g.spline, isNot(Geo.gearTag),
            reason: 'half a gear is not a gear — it must not keep a tag that '
                'says "read my two points as a parameter block"');
        expect(maxDev(sampleEntity(g), outline), lessThan(1e-6));
      }
    });
  });
}
