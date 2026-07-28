// M87 — the freehand spline tool.
//
// The fitting is pure (lib/freehand.dart), so the real algorithm is exercised
// here rather than a stand-in: a raw stroke goes in and the spline's fit
// points come out, exactly as the dialog and the commit path see them.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/qcad_engine.dart' show Geo;
import 'package:prototype/freehand.dart';
import 'package:prototype/tools.dart';

/// A hand-drawn quarter arc, sampled unevenly — dense at the start, sparse at
/// the end, the way a real stroke that slows down and speeds up looks.
List<Offset> _stroke({double r = 50, int n = 120}) => [
      for (var i = 0; i < n; i++)
        () {
          final t = math.pow(i / (n - 1), 1.6).toDouble(); // uneven in time
          final a = t * math.pi / 2;
          return Offset(r * math.cos(a), r * math.sin(a));
        }()
    ];

void main() {
  group('dedupe and arc-length resampling', () {
    test('a stationary pointer does not grow the stroke', () {
      final raw = [
        const Offset(0, 0),
        const Offset(0, 0),
        const Offset(0, 0),
        const Offset(10, 0),
      ];
      expect(dedupeStroke(raw), hasLength(2));
    });

    test('resampling produces exactly the requested count', () {
      for (final n in [2, 3, 16, 60]) {
        expect(resampleByArcLength(_stroke(), n), hasLength(n));
      }
    });

    test('the ends are preserved exactly', () {
      final raw = _stroke();
      final fit = resampleByArcLength(raw, 12);
      expect(fit.first, raw.first);
      expect(fit.last, raw.last);
    });

    test('spacing is EVEN by arc length, not by input sample index', () {
      // This is the point of resampling: the input is deliberately clustered
      // at one end, the output must not be.
      final fit = resampleByArcLength(_stroke(), 20);
      final gaps = [
        for (var i = 1; i < fit.length; i++) (fit[i] - fit[i - 1]).distance
      ];
      final mean = gaps.reduce((a, b) => a + b) / gaps.length;
      for (final g in gaps) {
        expect((g - mean).abs(), lessThan(mean * 0.25),
            reason: 'gaps should be near-uniform, got $gaps');
      }
    });
  });

  group('smoothing', () {
    test('zero smoothing is a no-op', () {
      final raw = _stroke();
      expect(smoothStroke(raw, 0), raw);
    });

    test('smoothing reduces jitter but pins the endpoints', () {
      final rng = math.Random(7);
      final jittered = [
        for (final p in _stroke())
          p + Offset(rng.nextDouble() - 0.5, rng.nextDouble() - 0.5)
      ];
      final smooth = smoothStroke(jittered, 0.8);
      expect(smooth.first, jittered.first, reason: 'start must not move');
      expect(smooth.last, jittered.last, reason: 'end must not move');
      // Total turning is a good proxy for jitter.
      double wiggle(List<Offset> p) {
        var w = 0.0;
        for (var i = 2; i < p.length; i++) {
          final a = p[i - 1] - p[i - 2], b = p[i] - p[i - 1];
          w += (a.dx * b.dy - a.dy * b.dx).abs();
        }
        return w;
      }

      expect(wiggle(smooth), lessThan(wiggle(jittered)));
    });
  });

  group('fitting a stroke', () {
    test('a stroke becomes an ordinary interpolation spline', () {
      final fit = fitFreehandStroke(_stroke(), points: 14, smoothing: 0.3);
      expect(fit.isUsable, isTrue);
      expect(fit.points, hasLength(14));
      expect(fit.closed, isFalse);
      // It commits through the ORDINARY pipeline.
      final geos = buildToolGeometry(Tool.splineFree, fit.points);
      expect(geos, isNotNull);
      expect(geos!, hasLength(1));
      expect(geos.first.spline, Geo.splineFit);
    });

    test('a stray tap is rejected instead of opening a dialog over nothing',
        () {
      expect(fitFreehandStroke([const Offset(1, 1)]).isUsable, isFalse);
      expect(fitFreehandStroke(const []).isUsable, isFalse);
    });

    test('ends that meet close the curve EXACTLY', () {
      final loop = [
        for (var i = 0; i <= 80; i++)
          Offset(30 * math.cos(2 * math.pi * i / 80),
              30 * math.sin(2 * math.pi * i / 80))
      ];
      final fit =
          fitFreehandStroke(loop, points: 20, smoothing: 0, snapClosed: true);
      expect(fit.closed, isTrue);
      expect(fit.points.first, fit.points.last,
          reason: 'the close convention _spline reads is exact equality');
      // And the tool pipeline really does emit a closed spline.
      final g = buildToolGeometry(Tool.splineFree, fit.points)!.first;
      expect(g.data[0], isNot(0));
    });

    test('closing is off when the switch is off', () {
      final loop = [
        for (var i = 0; i <= 80; i++)
          Offset(30 * math.cos(2 * math.pi * i / 80),
              30 * math.sin(2 * math.pi * i / 80))
      ];
      expect(
          fitFreehandStroke(loop, points: 20, snapClosed: false).closed, isFalse);
    });

    test('endpoints snap to nearby existing points, interior ones never do',
        () {
      final raw = [const Offset(0.4, 0.3), const Offset(20, 0), const Offset(39.6, 0.2)];
      final fit = fitFreehandStroke(
        raw,
        points: 3,
        smoothing: 0,
        snapToPoints: true,
        snapTargets: const [Offset(0, 0), Offset(40, 0), Offset(20, 5)],
        snapTol: 2.0,
      );
      expect(fit.points.first, const Offset(0, 0));
      expect(fit.points.last, const Offset(40, 0));
      expect(fit.snappedStart, isTrue);
      expect(fit.snappedEnd, isTrue);
      // The middle point stayed on the stroke — (20,5) was within tolerance of
      // nothing it is allowed to move.
      expect(fit.points[1].dy, lessThan(1));
    });

    test('snapping is off when the switch is off', () {
      final fit = fitFreehandStroke(
        [const Offset(0.4, 0.3), const Offset(20, 0), const Offset(39.6, 0.2)],
        points: 3,
        smoothing: 0,
        snapToPoints: false,
        snapTargets: const [Offset(0, 0), Offset(40, 0)],
      );
      expect(fit.points.first, const Offset(0.4, 0.3));
    });

    test('the point count is clamped to a usable band', () {
      expect(fitFreehandStroke(_stroke(), points: 0).points.length,
          kFreehandMinPoints);
      expect(fitFreehandStroke(_stroke(), points: 9999).points.length,
          kFreehandMaxPoints);
    });

    test('re-fitting is non-destructive: the raw ink drives every result', () {
      final raw = _stroke();
      final coarse = fitFreehandStroke(raw, points: 5, smoothing: 0.9);
      final fine = fitFreehandStroke(raw, points: 40, smoothing: 0.0);
      // Going back gives the first result again — sliders are reversible.
      final again = fitFreehandStroke(raw, points: 5, smoothing: 0.9);
      expect(coarse.points, again.points);
      expect(fine.points.length, greaterThan(coarse.points.length));
    });
  });

  group('session wiring', () {
    test('the tool is in the line flyout group, so the button goes sticky', () {
      expect(toolFlyoutGroup[Tool.splineFree], 'line');
    });

    test('a session outside edit mode never starts', () {
      final app = AppState();
      expect(app.inEditMode, isFalse);
      app.freehandBegin(const Offset(1, 1));
      expect(app.freehand, isNull);
    });

    test('cancel clears the ink and the pending points', () {
      final app = AppState();
      app.toolPoints.addAll([const Offset(0, 0), const Offset(1, 1)]);
      app.freehandCancel();
      expect(app.freehand, isNull);
      expect(app.toolPoints, isEmpty);
    });
  });
}
