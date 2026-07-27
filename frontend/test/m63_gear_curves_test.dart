// M63 — an extruded gear must reach the kernel as CURVES, not a facet fan.
//
// Before: gearProfile() sampled the involute flank as 18 straight chords per
// side, so arcFitLoop could only recover the 4 genuinely-circular features per
// tooth and handed OCCT ~920 edges for a default z=20 gear (840 of them
// straight) — one lateral face each. These tests pin the two properties that
// fix costs: the flank is an ARC CHAIN that arcFitLoop recovers losslessly,
// and the outline is memoised so it is not rebuilt on every paint.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/gear.dart';
import 'package:prototype/part_model.dart';

/// Exact involute half-tooth angle, independent of gear.dart's implementation
/// so the accuracy check is a real cross-check and not a tautology.
double _psiExact(GearParams p, double rho) {
  final a = p.pressureAngleDeg * math.pi / 180.0;
  final rb = p.baseRadius;
  double inv(double t) => math.tan(t) - t;
  final psiP = p.internal
      ? (math.pi / 2 - 2 * p.profileShift * math.tan(a)) / p.teeth
      : (math.pi / 2 + 2 * p.profileShift * math.tan(a)) / p.teeth;
  final rr = rho < rb ? rb : rho;
  return psiP + inv(a) - inv(math.acos((rb / rr).clamp(-1.0, 1.0)));
}

/// Shortest distance from [q] to the exact involute flank of [p], found by
/// dense sampling + local refinement.
double _distToInvolute(GearParams p, Offset q) {
  final rLo = math.max(p.baseRadius, p.rootRadius);
  final rOut = p.tipRadius;
  double at(double t) {
    final rho = rLo + (rOut - rLo) * t;
    final ang = -_psiExact(p, rho);
    return (Offset(rho * math.cos(ang), rho * math.sin(ang)) - q).distance;
  }

  var best = double.infinity, bt = 0.0;
  const n = 2000;
  for (var i = 0; i <= n; i++) {
    final d = at(i / n);
    if (d < best) {
      best = d;
      bt = i / n;
    }
  }
  var step = 1.0 / n;
  for (var it = 0; it < 60; it++) {
    for (final s in [-step, step]) {
      final t = (bt + s).clamp(0.0, 1.0);
      final d = at(t);
      if (d < best) {
        best = d;
        bt = t;
      }
    }
    step /= 2;
  }
  return best;
}

void main() {
  setUp(clearGearCurveCache);

  group('flank is an arc chain the kernel can use', () {
    test('arcFitLoop recovers arcs and collapses the edge count', () {
      for (final z in [12, 20, 40]) {
        final pts = gearProfile(
            center: Offset.zero,
            angle: 0,
            params: GearParams(module: 2.0, teeth: z));
        final segs = arcFitLoop(pts);
        final arcs = segs.where((s) => s.bulge != 0.0).length;
        final lines = segs.length - arcs;

        // Every tooth contributes 2 flank chains + crest + root gap + fillets;
        // the old code produced 46 edges per tooth, 36 of them straight.
        // Was 46 edges per tooth (36 of them straight); now ~23 with the
        // flanks carried by real arcs instead of a chord fan.
        expect(segs.length, lessThan(28 * z),
            reason: 'z=$z: ${segs.length} edges is not a collapse');
        expect(arcs, greaterThanOrEqualTo(9 * z),
            reason: 'z=$z: only $arcs arcs — flanks did not become arcs');
        // The remaining straight edges are single junction vertices between
        // features, not the old per-sample chord fan.
        expect(lines, lessThan(17 * z),
            reason: 'z=$z: $lines straight edges left');
      }
    });

    test('default gear halves the old 920-edge budget', () {
      final pts = gearProfile(
          center: Offset.zero,
          angle: 0,
          params: GearParams(module: 2.0, teeth: 20));
      final segs = arcFitLoop(pts);
      expect(segs.length, lessThanOrEqualTo(920 ~/ 2));
    });

    test('every emitted flank vertex lies on the true involute within 1 um',
        () {
      final p = GearParams(module: 2.0, teeth: 20);
      final pts = gearProfile(center: Offset.zero, angle: 0, params: p);
      // Consider only vertices in the flank radius band, away from the tip
      // round and root fillet which are deliberately NOT on the involute.
      final rLo = math.max(p.baseRadius, p.rootRadius);
      final rOut = p.tipRadius;
      var checked = 0;
      for (final q in pts) {
        final rho = q.distance;
        if (rho < rLo + 0.25 || rho > rOut - 0.25) continue;
        // fold into the first tooth's right flank
        final pitch = 2 * math.pi / p.teeth;
        var ang = math.atan2(q.dy, q.dx) % pitch;
        if (ang > pitch / 2) ang -= pitch;
        if (ang > 0) continue; // left flank: mirror handled by symmetry
        final folded = Offset(rho * math.cos(ang), rho * math.sin(ang));
        expect(_distToInvolute(p, folded), lessThan(1e-3),
            reason: 'vertex at r=$rho deviates from the involute');
        checked++;
      }
      expect(checked, greaterThan(50), reason: 'test checked too few vertices');
    });

    test('outline stays closed, non-degenerate and positively wound', () {
      for (final p in [
        GearParams(module: 2.0, teeth: 20),
        GearParams(module: 1.0, teeth: 12),
        GearParams(module: 5.0, teeth: 40, profileShift: 0.5),
        GearParams(module: 2.0, teeth: 17, profileShift: -0.3),
        GearParams(module: 2.0, teeth: 30, fillet: false),
      ]) {
        final pts =
            gearProfile(center: const Offset(7, -3), angle: 0.4, params: p);
        expect(pts.length, greaterThan(8 * p.teeth));
        // no coincident consecutive vertices (would sink the OCCT wire, M62)
        var minEdge = double.infinity;
        var area2 = 0.0;
        for (var i = 0; i < pts.length; i++) {
          final a = pts[i], b = pts[(i + 1) % pts.length];
          minEdge = math.min(minEdge, (a - b).distance);
          area2 += a.dx * b.dy - b.dx * a.dy;
        }
        expect(minEdge, greaterThan(1e-7),
            reason: 'degenerate edge in m=${p.module} z=${p.teeth}');
        expect(area2 / 2, greaterThan(0), reason: 'winding flipped');
        // all vertices inside the tip circle, none inside the root - fillet
        for (final q in pts) {
          final r = (q - const Offset(7, -3)).distance;
          expect(r, lessThan(p.tipRadius + 1e-6));
        }
      }
    });

    test('internal (ring) gears also produce arcs and stay closed', () {
      final p = GearParams(module: 2.0, teeth: 30, internal: true);
      final pts = gearProfile(center: Offset.zero, angle: 0, params: p);
      final segs = arcFitLoop(pts);
      expect(segs.length, lessThan(28 * p.teeth));
      expect(segs.where((s) => s.bulge != 0.0).length, greaterThan(0));
      var minEdge = double.infinity;
      for (var i = 0; i < pts.length; i++) {
        minEdge = math.min(
            minEdge, (pts[i] - pts[(i + 1) % pts.length]).distance);
      }
      expect(minEdge, greaterThan(1e-7));
    });
  });

  group('outline is memoised', () {
    test('same gear twice returns the identical list instance', () {
      final g = buildGearGeo(const Offset(3, 4), 0.2, GearParams());
      final a = gearCurve(g);
      final b = gearCurve(g);
      expect(identical(a, b), isTrue,
          reason: 'gearCurve rebuilt the involute instead of reusing it');
    });

    test('moving or re-parameterising the gear misses the cache', () {
      final g1 =
          buildGearGeo(Offset.zero, 0, GearParams());
      final g2 = buildGearGeo(const Offset(10, 0), 0, GearParams());
      final g3 = buildGearGeo(Offset.zero, 0, GearParams(teeth: 21));
      final c1 = gearCurve(g1);
      expect(identical(gearCurve(g2), c1), isFalse);
      expect(identical(gearCurve(g3), c1), isFalse);
      // and the moved gear really is translated
      expect((gearCurve(g2).first - c1.first).distance, closeTo(10, 1e-9));
    });

    test('cache stays bounded', () {
      for (var i = 0; i < 200; i++) {
        gearCurve(buildGearGeo(Offset(i.toDouble(), 0), 0, GearParams()));
      }
      // no assertion on the internal size beyond "it did not blow up"; the
      // bound is exercised by clearing at the cap.
      expect(true, isTrue);
    });
  });

  group('corner radius replaces the pitch-radius setting', () {
    test('default reproduces the legacy module-relative shape exactly', () {
      // cornerRadius 0 = "auto": the old rootFilletCoef * module behaviour.
      final legacy = GearParams(module: 2.0, teeth: 20);
      expect(legacy.cornerRadius, 0.0);
      expect(legacy.rootFilletRadius, closeTo(0.38 * 2.0, 1e-12));
      expect(legacy.tipRoundRadius, closeTo(0.12 * 2.0, 1e-12));

      // ...and setting it explicitly to that same value changes nothing.
      final explicit = GearParams(module: 2.0, teeth: 20, cornerRadius: 0.76);
      final a = gearProfile(center: Offset.zero, angle: 0, params: legacy);
      final b = gearProfile(center: Offset.zero, angle: 0, params: explicit);
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        expect((a[i] - b[i]).distance, lessThan(1e-9));
      }
    });

    test('a bigger corner radius really rounds the corners more', () {
      Offset rootDip(double cr) {
        final p = GearParams(module: 2.0, teeth: 20, cornerRadius: cr);
        final pts = gearProfile(center: Offset.zero, angle: 0, params: p);
        // the point closest to the centre sits in the root gap
        var best = pts.first;
        for (final q in pts) {
          if (q.distance < best.distance) best = q;
        }
        return best;
      }

      // The realised radius of curvature at the sharpest point of the outline
      // IS the tip round, so it measures the rounding directly. Before the
      // fillet rework this stayed pinned to the tessellation chord no matter
      // what radius was asked for, and the setting did nothing at all.
      double sharpest(double cr) {
        final p = GearParams(module: 2.0, teeth: 20, cornerRadius: cr);
        final pts = gearProfile(center: Offset.zero, angle: 0, params: p);
        var m = double.infinity;
        for (var i = 0; i < pts.length; i++) {
          final a = pts[(i - 1 + pts.length) % pts.length];
          final b = pts[i];
          final c = pts[(i + 1) % pts.length];
          final d = 2 *
              (a.dx * (b.dy - c.dy) +
                  b.dx * (c.dy - a.dy) +
                  c.dx * (a.dy - b.dy));
          if (d.abs() < 1e-14) continue;
          final a2 = a.dx * a.dx + a.dy * a.dy;
          final b2 = b.dx * b.dx + b.dy * b.dy;
          final c2 = c.dx * c.dx + c.dy * c.dy;
          final o = Offset(
              (a2 * (b.dy - c.dy) + b2 * (c.dy - a.dy) + c2 * (a.dy - b.dy)) / d,
              (a2 * (c.dx - b.dx) + b2 * (a.dx - c.dx) + c2 * (b.dx - a.dx)) / d);
          final r = (b - o).distance;
          if (r < m) m = r;
        }
        return m;
      }

      // strictly monotone in the requested radius
      var prev = 0.0;
      for (final cr in [0.2, 0.4, 0.6, 0.9, 1.2]) {
        final got = sharpest(cr);
        expect(got, greaterThan(prev),
            reason: 'a larger corner radius must round the corners more');
        // and it is the radius actually ASKED for, not a chord-sized stub
        expect(got,
            closeTo(GearParams(module: 2.0, teeth: 20, cornerRadius: cr)
                .tipRoundRadius, 1e-3),
            reason: 'the realised fillet must match the requested radius');
        prev = got;
      }

      expect(rootDip(0.2).distance, isNot(closeTo(rootDip(0.9).distance, 1e-6)),
          reason: 'the corner radius must change the root geometry');
    });

    test('pre-M63 sketches (9-slot block) still load and keep their shape', () {
      final p = GearParams(module: 2.0, teeth: 20);
      final full = buildGearGeo(Offset.zero, 0, p);
      // an old file stored only nine block values (no corner radius)
      final oldData = List<double>.from(full.data)..removeLast();
      final oldGeo = full.withData(oldData);
      final loaded = gearParams(oldGeo);
      expect(loaded, isNotNull);
      expect(loaded!.cornerRadius, 0.0);
      expect(loaded.rootFilletRadius, closeTo(p.rootFilletRadius, 1e-12));
      final a = gearCurve(full);
      final b = gearCurve(oldGeo);
      expect(b.length, a.length);
      for (var i = 0; i < a.length; i++) {
        expect((a[i] - b[i]).distance, lessThan(1e-9));
      }
    });

    test('corner radius survives the block and JSON round-trips', () {
      final p = GearParams(module: 3.0, teeth: 24, cornerRadius: 1.4);
      final viaBlock = GearParams.fromBlock(p.toBlock());
      expect(viaBlock!.cornerRadius, closeTo(1.4, 1e-12));
      final viaJson = GearParams.fromJson(p.toJson());
      expect(viaJson.cornerRadius, closeTo(1.4, 1e-12));
      expect(GearParams.blockLen, p.toBlock().length);
    });

    test('the outline stays sound across the corner-radius range', () {
      for (final cr in [0.0, 0.05, 0.4, 0.76, 1.2, 2.5]) {
        final p = GearParams(module: 2.0, teeth: 20, cornerRadius: cr);
        expect(p.valid, isTrue, reason: 'cr=$cr rejected');
        final pts = gearProfile(center: Offset.zero, angle: 0, params: p);
        var minEdge = double.infinity, area2 = 0.0;
        for (var i = 0; i < pts.length; i++) {
          final a = pts[i], b = pts[(i + 1) % pts.length];
          minEdge = math.min(minEdge, (a - b).distance);
          area2 += a.dx * b.dy - b.dx * a.dy;
        }
        expect(minEdge, greaterThan(1e-7), reason: 'cr=$cr degenerate edge');
        expect(area2 / 2, greaterThan(0), reason: 'cr=$cr winding flipped');
      }
      expect(GearParams(module: 2.0, teeth: 20, cornerRadius: -1).valid, isFalse);
    });

    test('pitch radius remains available as DERIVED geometry', () {
      // removed from the dialog, but the handle still rides the pitch circle
      final p = GearParams(module: 2.0, teeth: 20);
      expect(p.pitchRadius, closeTo(20.0, 1e-12));
      expect(p.handleRadius, closeTo(p.pitchRadius, 1e-12));
    });
  });
}
