// Tests for the M22 spline fixes:
//  1. the spline tag survives an engine rebuild that ADDED the spline
//     (refresh(tagSource:) — this was the "Enter turns my spline into
//     straight lines" bug)
//  2. a closed CV spline is a true PERIODIC B-spline: it meets its start
//     point exactly and has no corner there
//  3. a closed fit spline meets its start point exactly
//  4. _spline (via buildToolGeometry) closes when the last point coincides
//     with the first
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/spline.dart';
import 'package:ipadprocad/tools.dart';
import 'package:ipadprocad/snap.dart';

void main() {
  test('spline tag survives a rebuild that added the spline', () {
    final s = SketchModel('t');
    // the engine (Dart fallback on the host) holds the plain polyline...
    s.engine.addPolyline([0, 0, 40, 10, 80, -10, 120, 0]);
    // ...and the authoritative list carries the tag, exactly like _rebuildEngine
    final tagged = [
      Geo(Geo.polyline, [0, 4, 0, 0, 40, 10, 80, -10, 120, 0])
          .asSpline(Geo.splineCv)
    ];
    s.refresh(tagSource: tagged);
    expect(s.geometry, hasLength(1));
    expect(s.geometry[0].spline, Geo.splineCv,
        reason: 'freshly committed splines must keep their tag');
    // and WITHOUT the source (an unrelated refresh) the tag still sticks,
    // because s.geometry now carries it
    s.refresh();
    expect(s.geometry[0].spline, Geo.splineCv);
  });

  test('closed CV spline is periodic: closes exactly, no corner', () {
    final cv = const [
      Offset(0, 0),
      Offset(100, 0),
      Offset(100, 100),
      Offset(0, 100),
      Offset(-40, 50),
    ];
    final c = bsplineCurve(cv, closed: true, samples: 200);
    expect((c.first - c.last).distance, lessThan(1e-9),
        reason: 'a closed spline must meet its start point');
    // smoothness at the seam: the incoming and outgoing directions agree
    final din = c[c.length - 1] - c[c.length - 2];
    final dout = c[1] - c[0];
    final cosA = (din.dx * dout.dx + din.dy * dout.dy) /
        (din.distance * dout.distance);
    expect(cosA, greaterThan(0.99),
        reason: 'periodic B-spline is C2 — no corner at the seam');
  });

  test('closed fit spline meets its start point', () {
    final p = const [Offset(0, 0), Offset(60, 20), Offset(30, 80)];
    final c = fitCurve(p, closed: true);
    expect((c.first - c.last).distance, lessThan(1e-9));
    // and it passes through every fit point
    for (final q in p) {
      final hit = c.any((o) => (o - q).distance < 1e-6);
      expect(hit, isTrue, reason: 'fit spline must pass through $q');
    }
  });

  test('spline tool closes when the last point equals the first', () {
    final pts = const [
      Offset(0, 0),
      Offset(50, 40),
      Offset(100, 0),
      Offset(50, -40),
      Offset(0, 0), // clicked back on the start
    ];
    final g = buildToolGeometry(Tool.splineCV, List.of(pts))!.single;
    expect(g.data[0], 1.0, reason: 'closed flag set');
    expect(g.data[1], 4.0, reason: 'the duplicate start point was dropped');
    expect(g.spline, Geo.splineCv);
    final curve = splineCurveFor(g);
    expect((curve.first - curve.last).distance, lessThan(1e-9));
  });

  group('ellipse (M23)', () {
    test('ellipse tool emits 3 defining points, not a sampled polygon', () {
      final g = buildToolGeometry(Tool.ellipse, const [
        Offset(10, 5), //  center
        Offset(50, 5), //  major vertex (a = 40)
        Offset(10, 90), // minor extent picked anywhere (b = 15 via projection
        //               of nothing — here straight up, b = 85? no: see below)
      ])!
          .single;
      expect(g.spline, Geo.ellipseTag);
      expect(g.data[1], 3.0, reason: '3 vertices, not 96');
      // minor vertex is stored ON the minor axis
      expect(g.data[6], closeTo(10, 1e-9));
      expect(g.data[7], closeTo(90, 1e-9));
    });

    test('ellipseCurve closes and hits all four quadrants', () {
      final c = ellipseCurve(const [
        Offset(0, 0),
        Offset(40, 0),
        Offset(0, 15),
      ]);
      expect((c.first - c.last).distance, lessThan(1e-9));
      for (final q in const [
        Offset(40, 0),
        Offset(-40, 0),
        Offset(0, 15),
        Offset(0, -15),
      ]) {
        expect(c.any((o) => (o - q).distance < 1e-6), isTrue,
            reason: 'curve must pass quadrant $q');
      }
    });

    test('minor vertex only contributes its perpendicular component', () {
      // minor point dragged diagonally: the parallel part must be ignored
      final c = ellipseCurve(const [
        Offset(0, 0),
        Offset(40, 0),
        Offset(30, 15), // 30 along major is noise, 15 across is b
      ]);
      final maxY = c.map((o) => o.dy).reduce((a, b) => a > b ? a : b);
      expect(maxY, closeTo(15, 1e-6));
    });

    test('normalizedEllipse puts a drifted minor vertex back on the axis', () {
      final g = Geo(Geo.polyline, [1, 3, 0, 0, 40, 0, 30, 15])
          .asSpline(Geo.ellipseTag);
      final n = normalizedEllipse(g);
      expect(n.data[6], closeTo(0, 1e-9));
      expect(n.data[7], closeTo(15, 1e-9));
      expect(n.spline, Geo.ellipseTag, reason: 'withData keeps the tag');
    });

    test('center grip translates the whole ellipse', () {
      final g = Geo(Geo.polyline, [1, 3, 0, 0, 40, 0, 0, 15])
          .asSpline(Geo.ellipseTag);
      final m = moveGrip(g, Grip(0, 0, Offset.zero, 'vertex'), const Offset(10, 10));
      expect(m.data.sublist(2), [10, 10, 50, 10, 10, 25]);
    });

    test('major grip rotates: minor follows perpendicular, b kept', () {
      final g = Geo(Geo.polyline, [1, 3, 0, 0, 40, 0, 0, 15])
          .asSpline(Geo.ellipseTag);
      // rotate the major axis to point up
      final m = moveGrip(g, Grip(0, 1, Offset.zero, 'vertex'), const Offset(0, 40));
      expect(m.data[4], closeTo(0, 1e-9));
      expect(m.data[5], closeTo(40, 1e-9));
      // minor axis now horizontal, length still 15
      expect((Offset(m.data[6], m.data[7])).distance, closeTo(15, 1e-9));
      expect(m.data[7], closeTo(0, 1e-9));
    });
  });
}
