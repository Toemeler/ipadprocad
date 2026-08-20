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

    // M209 — the window is a RING now. It used to be a List with removeAt(0)
    // per sample past the 128th, i.e. an O(n) memmove inside the measuring
    // code, on the per-frame paint path.
    test('the ring keeps exactly the last 128 samples, in order', () {
      final s = PerfStat();
      // 128 zeros, then 128 ascending values that fully lap the ring.
      for (var i = 0; i < 128; i++) {
        s.add(0);
      }
      for (var i = 1; i <= 128; i++) {
        s.add(i.toDouble());
      }
      expect(s.p50Ms, closeTo(64, 1),
          reason: 'the zeros must have been overwritten, not appended');
      expect(s.p95Ms, closeTo(122, 2));
    });

    test('p50 and p95 separate "uniformly slow" from "fine with a tail"', () {
      final flat = PerfStat();
      for (var i = 0; i < 100; i++) {
        flat.add(20);
      }
      final spiky = PerfStat();
      for (var i = 0; i < 90; i++) {
        spiky.add(1);
      }
      for (var i = 0; i < 10; i++) {
        spiky.add(400);
      }
      expect(flat.p50Ms, 20);
      expect(flat.p95Ms, 20, reason: 'uniformly slow: p50 == p95');
      expect(spiky.p50Ms, 1);
      expect(spiky.p95Ms, greaterThan(100),
          reason: 'usually fine with a tail: p50 << p95');
    });

    test('adding samples stays cheap once the ring is full', () {
      final s = PerfStat();
      for (var i = 0; i < 128; i++) {
        s.add(1);
      }
      final sw = Stopwatch()..start();
      for (var i = 0; i < 200000; i++) {
        s.add(1);
      }
      sw.stop();
      // The old removeAt(0) made this O(n) per call. Sub-microsecond per add
      // is the property; the exact number is CI-hardware dependent.
      expect(sw.elapsedMicroseconds / 200000, lessThan(1.0));
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
      expect(Perf.counters['unit.hits'], 2);
      expect(Perf.gauges['unit.tris'], 34236);
    });

    // M209 — a counter used to be stored as a 0 ms sample in the SAME table as
    // durations. Two things went wrong with that, and both are pinned here:
    // the counter's own row claimed avg 0 ms as if the work were free, and a
    // name used for both a duration and a count had its average dragged toward
    // zero by every count.
    test('a count never lands in the duration table', () {
      Perf.count('unit.pure');
      expect(Perf.stats['unit.pure'], isNull,
          reason: 'a count is not a fast measurement, it is no measurement');
    });

    test('a count cannot dilute a duration recorded under the same name', () {
      Perf.record('unit.both', 10);
      Perf.count('unit.both');
      Perf.count('unit.both');
      expect(Perf.stats['unit.both']!.count, 1);
      expect(Perf.stats['unit.both']!.avgMs, 10);
      expect(Perf.counters['unit.both'], 2);
    });

    test('count takes a bulk increment', () {
      Perf.count('unit.bulk', 440);
      Perf.count('unit.bulk', 60);
      expect(Perf.counters['unit.bulk'], 500);
    });

    test('cache() records hit and miss under one name', () {
      Perf.cache('unit.cache', true);
      Perf.cache('unit.cache', true);
      Perf.cache('unit.cache', false);
      expect(Perf.counters['unit.cache.hit'], 2);
      expect(Perf.counters['unit.cache.miss'], 1);
    });
  });

  group('phases', () {
    test('each mark records the time since the previous one', () {
      final ph = PerfPhases('unit.ph');
      ph
        ..begin()
        ..mark('a')
        ..mark('b')
        ..end();
      expect(Perf.stats['unit.ph.a']!.count, 1);
      expect(Perf.stats['unit.ph.b']!.count, 1);
      expect(Perf.stats['unit.ph.z']!.count, 1,
          reason: 'end() closes the tail, so a missing phase shows up');
    });

    test('a mark outside begin/end is ignored rather than corrupting', () {
      final ph = PerfPhases('unit.stray');
      ph.mark('nope');
      expect(Perf.stats['unit.stray.nope'], isNull);
    });

    test('phases are reusable across runs and accumulate', () {
      final ph = PerfPhases('unit.reuse');
      for (var i = 0; i < 3; i++) {
        ph
          ..begin()
          ..mark('a')
          ..end();
      }
      expect(Perf.stats['unit.reuse.a']!.count, 3);
    });

    test('a phase mark allocates nothing per call', () {
      // The reason PerfPhases exists at all: the 2D painter runs up to 120
      // times a second with 18 phases, and Perf.span would cost one closure
      // allocation each. This does not prove zero allocation directly — Dart
      // gives no such hook — but it pins the cost at the same order as a span,
      // which is the property that matters.
      final ph = PerfPhases('unit.cost');
      final sw = Stopwatch()..start();
      for (var i = 0; i < 20000; i++) {
        ph
          ..begin()
          ..mark('x');
      }
      sw.stop();
      expect(sw.elapsedMicroseconds / 20000, lessThan(20));
    });
  });

  // M210 — the bug that made every number in this file worthless on the
  // device from M79 until now.
  //
  // `Perf.init()` is the second statement of main(), before any binding
  // exists, because the log file has to be open before anything can be
  // measured. It also called `SchedulerBinding.instance` there, which is a
  // null check on a binding that does not exist yet, so it threw. The catch
  // set `_broken`, and a broken Perf makes EVERY span, record, count and gauge
  // a silent no-op — while the only evidence was one line in the other log
  // file. The registration now lives in `attachToBinding`, called after
  // `ensureInitialized`, and its failure is not allowed to break the rest.
  group('binding attachment (M210)', () {
    test('attachToBinding is idempotent', () {
      Perf.attachToBinding();
      Perf.attachToBinding();
      // No throw, and recording still works afterwards.
      Perf.record('unit.afterAttach', 5);
      expect(Perf.stats['unit.afterAttach']!.count, 1);
    });

    test('spans record whether or not frame timings are attached', () {
      // The property that matters: losing frame.* must not cost the subsystem
      // breakdown. That was the whole failure — one missing binding took the
      // entire instrument down with it.
      Perf.span('unit.noBinding', () => 1);
      Perf.count('unit.noBindingCount');
      Perf.gauge('unit.noBindingGauge', 3);
      expect(Perf.stats['unit.noBinding']!.count, 1);
      expect(Perf.counters['unit.noBindingCount'], 1);
      expect(Perf.gauges['unit.noBindingGauge'], 3);
    });
  });

  group('json snapshot', () {
    test('carries spans, counters and gauges under stable keys', () {
      Perf.record('unit.j', 3);
      Perf.count('unit.k');
      Perf.gauge('unit.g', 7);
      final j = Perf.jsonSnapshot();
      expect((j['spans'] as Map)['unit.j'], isA<Map>());
      expect(((j['spans'] as Map)['unit.j'] as Map)['p95Ms'], 3);
      expect((j['counters'] as Map)['unit.k'], 1);
      expect((j['gauges'] as Map)['unit.g'], 7);
      // The regression gate diffs these keys, so a rename is a breaking
      // change and should fail here first.
      expect(j.keys,
          containsAll(['at', 'build', 'wallMs', 'frames', 'memory', 'spans']));
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
