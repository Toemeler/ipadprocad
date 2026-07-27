// M79 — the performance logger itself.
//
// It exists because three rounds of optimisation went into the wrong layer
// (HANDOFF M75). A measuring instrument that is wrong, or that costs enough
// to show up in its own numbers, is worse than none — so both properties are
// pinned here.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/perf.dart';

void main() {
  setUp(Perf.resetForTest);

  group('statistics', () {
    test('tracks count, average, worst and p95 separately', () {
      final s = PerfStat();
      for (final v in [1.0, 1.0, 1.0, 1.0, 100.0]) {
        s.add(v);
      }
      expect(s.count, 5);
      expect(s.lastMs, 100);
      expect(s.worstMs, 100);
      expect(s.avgMs, closeTo(20.8, 0.1));
      // The point of p95: the average hides a single hitch, the worst IS the
      // hitch. p95 is what characterises how it feels.
      expect(s.p95Ms, 100);
    });

    test('p95 sits below the worst once there are enough good samples', () {
      final s = PerfStat();
      for (var i = 0; i < 99; i++) {
        s.add(10);
      }
      s.add(500);
      expect(s.worstMs, 500);
      expect(s.p95Ms, 10, reason: 'one hitch in 100 must not dominate p95');
    });

    test('the sample window stays bounded over a long session', () {
      final s = PerfStat();
      for (var i = 0; i < 10000; i++) {
        s.add(i.toDouble());
      }
      expect(s.count, 10000, reason: 'counts stay cumulative');
      expect(s.worstMs, 9999, reason: 'the worst is never forgotten');
      // but memory is not allowed to grow with the session
      expect(s.p95Ms, greaterThan(9800),
          reason: 'p95 reflects the RECENT window, not all history');
    });
  });

  group('spans', () {
    test('records under its name and accumulates', () {
      Perf.span('unit.a', () => 1);
      Perf.span('unit.a', () => 2);
      expect(Perf.stats['unit.a']!.count, 2);
    });

    test('returns the body value through', () {
      expect(Perf.span('unit.b', () => 42), 42);
    });

    test('still records when the body throws', () {
      expect(() => Perf.span('unit.c', () => throw StateError('x')),
          throwsStateError);
      expect(Perf.stats['unit.c']!.count, 1,
          reason: 'a failing operation still cost time');
    });

    test('a re-entrant span does not corrupt the outer measurement', () {
      Perf.span('unit.d', () {
        Perf.span('unit.d', () => 1); // nested, same name
        return 2;
      });
      expect(Perf.stats['unit.d']!.count, 1,
          reason: 'the inner call must not double-count or reset the outer');
    });

    test('counters and gauges are separate from timings', () {
      Perf.count('unit.hits');
      Perf.count('unit.hits');
      Perf.gauge('unit.tris', 34236);
      expect(Perf.stats['unit.hits']!.count, 2);
      expect(Perf.gauges['unit.tris'], 34236);
    });
  });

  _underlayTransform();

  group('cost of measuring', () {
    test('a span is cheap enough to leave on permanently', () {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 20000; i++) {
        Perf.span('unit.cost', () => i);
      }
      sw.stop();
      final perCallUs = sw.elapsedMicroseconds / 20000;
      // Generous bound: the point is that it is microseconds, not that it
      // hits an exact number on unknown CI hardware.
      expect(perCallUs, lessThan(20),
          reason: 'a probe that shows up in its own numbers is useless');
    });
  });
}

// --- M79b: the underlay pan transform --------------------------------------
// Pinned because the sign was wrong once. The sketch Y axis points UP and the
// screen's points DOWN, so a pan delta shifts the cached picture by
// (-dx*zoom, +dy*zoom). Derived from Cam3.project and cross-checked against
// Viewport2D.map(), which the underlay has to move with — if these two ever
// disagree, the model slides away from the sketch while panning.
void _underlayTransform() {
  group('underlay pan transform', () {
    // map():        sx = w/2 + (x - pan.dx)*zoom
    //               sy = h/2 - (y - pan.dy)*zoom
    // Cam3.project: sx = ((W.s - ox)/(halfH*aspect)/2 + 0.5)*w
    //               sy = (1 - ((W.u - oy)/halfH/2 + 0.5))*h
    //               halfH = h/(2*zoom), aspect = w/h, ox/oy include pan
    double mapSx(double x, double panDx, double zoom, double w) =>
        w / 2 + (x - panDx) * zoom;
    double mapSy(double y, double panDy, double zoom, double h) =>
        h / 2 - (y - panDy) * zoom;

    double camSx(double x, double panDx, double zoom, double w, double h) {
      final halfH = h / (2 * zoom), aspect = w / h;
      return ((x - panDx) / (halfH * aspect) * 0.5 + 0.5) * w;
    }

    double camSy(double y, double panDy, double zoom, double w, double h) {
      final halfH = h / (2 * zoom);
      return (1 - ((y - panDy) / halfH * 0.5 + 0.5)) * h;
    }

    test('the 3D camera and the 2D map agree on where a point lands', () {
      const w = 800.0, h = 600.0, zoom = 3.0;
      for (final x in [-20.0, 0.0, 17.5]) {
        for (final y in [-9.0, 0.0, 4.25]) {
          expect(camSx(x, 2, zoom, w, h), closeTo(mapSx(x, 2, zoom, w), 1e-9));
          expect(camSy(y, -3, zoom, w, h), closeTo(mapSy(y, -3, zoom, h), 1e-9));
        }
      }
    });

    test('a pan delta shifts the screen by (-dx*zoom, +dy*zoom)', () {
      const w = 800.0, h = 600.0, zoom = 2.5;
      const x = 7.0, y = -4.0;
      const d = 3.0;
      expect(camSx(x, d, zoom, w, h) - camSx(x, 0, zoom, w, h),
          closeTo(-d * zoom, 1e-9));
      expect(camSy(y, d, zoom, w, h) - camSy(y, 0, zoom, w, h),
          closeTo(d * zoom, 1e-9),
          reason: 'Y is flipped; using -d here made the underlay drift');
    });
  });
}
