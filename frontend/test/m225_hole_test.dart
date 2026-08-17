// M225 — Inventor's Modify > Hole, first cut: the FEATURE.
//
// Hole has been a label in the part ribbon since M56 and a full-size button
// with an empty `onTap` until M216 moved it into the panel's ▼. It is the most
// used entry in Inventor's Modify panel, and until now the only way to make
// one here was to draw a circle and extrude it as a cut — which is a different
// thing in every way that matters afterwards: the browser says "Extrusion",
// the diameter is a sketch dimension rather than a hole size, and moving the
// hole means editing geometry instead of a point.
//
// This file covers the model half: what reaches the kernel, where the tool is
// placed, how a placement follows its sketch point, and every way it can
// honestly fail. The panel is the next commit.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

import 'm56_part_test.dart' show FakeKernel, addRectLines;

/// A part with one built base extrusion and a second sketch carrying [pts]
/// sketch points, ready for a hole.
Future<(AppState, PartModel, String)> _partWithPoints(
    List<Offset> pts, FakeKernel k) async {
  final app = AppState()..partKernel = k;
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m225_');
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  addRectLines(app.activeChild!, 0, 0, 40, 30, layer: app.editingLayer!);
  app.finishPartSketch();
  final p = app.currentPart!;
  final base = ExtrudeFeature(
    name: 'Extrusion1',
    bodyName: 'Solid1',
    sketchName: p.childSketches.single.model.name,
    profiles: [ProfileSel(20, 15, 1200)],
    distanceA: 12,
  )..output = 'new';
  base.seq = p.nextSeq();
  p.appendFeature(base);

  app.startPartSketch();
  app.planePicked('xy');
  // Through the real tool, so the points are tagged exactly as M209 makes
  // them — a hole that only finds test-built points would prove nothing.
  for (final c in pts) {
    app.tool = Tool.point;
    app.toolClick(c);
  }
  app.tool = Tool.none;
  app.finishPartSketch();
  return (app, p, p.childSketches.last.model.name);
}

HoleFeature _hole(String sketch, List<Offset> at,
        {double dia = 6,
        double depth = 10,
        FeatureExtent extent = FeatureExtent.distance,
        bool flip = false}) =>
    HoleFeature(
      name: 'Hole1',
      bodyName: 'Solid1',
      sketchName: sketch,
      places: [for (final p in at) HolePlace(p.dx, p.dy)],
      dia: dia,
      depth: depth,
      extent: extent,
      flip: flip,
    );

/// Radius of every point of [loop] about [c] — a circle, or it is not a hole.
(double, double) _radii(List<Offset> loop, Offset c) {
  var lo = double.infinity, hi = 0.0;
  for (final p in loop) {
    final d = (p - c).distance;
    if (d < lo) lo = d;
    if (d > hi) hi = d;
  }
  return (lo, hi);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M225 — what reaches the kernel', () {
    test('one circular tool per placement, at the right radius', () async {
      final k = FakeKernel();
      final (app, p, sk) =
          await _partWithPoints([const Offset(10, 10), const Offset(30, 20)], k);
      final f = _hole(sk, [const Offset(10, 10), const Offset(30, 20)], dia: 6);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);

      expect(f.computeError, isNull, reason: f.computeError ?? '');
      final groups = k.lastGroups!;
      expect(groups.length, 2, reason: 'two holes, two tools');
      for (final g in groups) {
        expect(g.length, 1, reason: 'a drilled hole has no inner loop');
      }
      final (lo1, hi1) = _radii(groups[0].single, const Offset(10, 10));
      expect(lo1, closeTo(3, 1e-9));
      expect(hi1, closeTo(3, 1e-9));
      final (lo2, hi2) = _radii(groups[1].single, const Offset(30, 20));
      expect(lo2, closeTo(3, 1e-9));
      expect(hi2, closeTo(3, 1e-9));
      expect(k.cuts, 1, reason: 'the tool is cut from the body, once');
    });

    test('it drills INTO the material, not out of the screen', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)], depth: 7);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);

      expect(k.lastHeight, closeTo(7, 1e-9));
      // mat34's translation is origin + n*zOffset; on XY that is z.
      expect(k.lastMat![11], closeTo(-7, 1e-9),
          reason: 'the tool starts 7 mm below the sketch and ends ON it');
    });

    test('flip drills the other way', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)], depth: 7, flip: true);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);
      expect(k.lastMat![11], closeTo(0, 1e-9));
      expect(k.lastHeight, closeTo(7, 1e-9));
    });

    test('Through All reaches past the part on both sides', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)],
          extent: FeatureExtent.throughAll);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);

      expect(f.computeError, isNull, reason: f.computeError ?? '');
      final start = k.lastMat![11], h = k.lastHeight!;
      expect(start, lessThan(0));
      expect(start + h, greaterThanOrEqualTo(1.0),
          reason: 'it must come out the other side, not stop ON the face — a '
              'tool face flush with a body face is the classic boolean coin '
              'toss');
      expect(h, greaterThan(40),
          reason: 'long enough to clear a 40x30x12 part');
    });
  });

  group('M225 — a placement follows its point', () {
    test('moving the sketch point moves the hole', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)]);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);

      // The user drags the point: same entity, new numbers.
      final model = p.sketchByName(sk)!.model;
      for (var i = 0; i < model.geometry.length; i++) {
        final g = model.geometry[i];
        if (g.isSketchPoint) {
          model.geometry[i] = g.withData([25, 5, g.data[2]]);
        }
      }
      f.builtSig = null; // what an edit does
      recomputeAllFeatures(p, app.partKernel);

      final centre = _centreOf(k.lastGroups!.single.single);
      expect(centre.dx, closeTo(25, 1e-6));
      expect(centre.dy, closeTo(5, 1e-6));
      expect(f.places.single.x, closeTo(25, 1e-6),
          reason: 'the placement is rewritten, so it keeps following');
    });

    test('a sketch with no points cannot hold a hole', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints(const [], k);
      final f = _hole(sk, [const Offset(10, 10)]);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);
      expect(f.solid, isNull);
      expect(f.computeError, contains('no sketch point'));
    });

    test('two placements cannot collapse onto one point', () async {
      // What a deleted point leaves behind: both placements find the same
      // survivor. Drilling one hole twice is not the answer.
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10), const Offset(30, 20)]);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);
      expect(f.solid, isNull);
      expect(f.computeError, contains('same sketch point'));
    });
  });

  group('M225 — how it fails', () {
    test('a hole with nothing to drill says so', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      // Remove the base extrusion: the hole is now first in its body.
      p.features.removeWhere((f) => f is ExtrudeFeature);
      final f = _hole(sk, [const Offset(10, 10)]);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);
      expect(f.solid, isNull);
      expect(f.computeError, contains('needs a body'));
    });

    test('a zero diameter is refused', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)], dia: 0);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);
      expect(f.computeError, contains('diameter'));
    });

    test('To Next is refused rather than drilled as a distance', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f =
          _hole(sk, [const Offset(10, 10)], extent: FeatureExtent.toNext);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);
      expect(f.computeError, contains('not available for a hole yet'));
    });
  });

  // -------------------------------------------------------------------------
  // M226 — the shape at the mouth
  // -------------------------------------------------------------------------

  group('M226 — counterbore and spotface', () {
    test('a second, wider tool is cut at the surface', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)], dia: 6, depth: 20)
        ..type = HoleType.counterbore
        ..cbDia = 12
        ..cbDepth = 4;
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);

      expect(f.computeError, isNull, reason: f.computeError ?? '');
      expect(k.cuts, 2, reason: 'the hole, then its mouth');
      // The LAST extrude is the counterbore.
      final (lo, hi) = _radii(k.lastGroups!.single.single, const Offset(10, 10));
      expect(lo, closeTo(6, 1e-9));
      expect(hi, closeTo(6, 1e-9));
      expect(k.lastHeight, closeTo(4, 1e-9));
      expect(k.lastTaper, 0, reason: 'a counterbore has a FLAT bottom');
      expect(k.lastMat![11], closeTo(-4, 1e-9),
          reason: 'it opens AT the face, not somewhere down the hole');
    });

    test('a spotface is the same cut, and says it is a spotface', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)])
        ..type = HoleType.spotface
        ..cbDia = 14
        ..cbDepth = 1;
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);
      expect(f.computeError, isNull, reason: f.computeError ?? '');
      expect(holeTypeLabel(f.type), 'Spotface');
      expect(k.lastHeight, closeTo(1, 1e-9));
    });

    test('one no wider than the hole is refused', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)], dia: 6)
        ..type = HoleType.counterbore
        ..cbDia = 6
        ..cbDepth = 3;
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);
      expect(f.solid, isNull);
      expect(f.computeError, contains('wider than the hole'));
    });
  });

  group('M226 — countersink', () {
    test('the cone opens from the hole to the countersink diameter', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)], dia: 6)
        ..type = HoleType.countersink
        ..csDia = 12
        ..csAngle = 90;
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);

      expect(f.computeError, isNull, reason: f.computeError ?? '');
      // 90 deg included angle: the wall runs at 45 deg, so opening out by
      // (6-3) = 3 mm takes exactly 3 mm of depth.
      expect(k.lastHeight, closeTo(3, 1e-9));
      expect(k.lastTaper, closeTo(45, 1e-9),
          reason: "the shim's taper is Inventor's sign: positive flares out "
              'along the extrusion, which is what a countersink does when the '
              'tool runs from the small end up to the face');
      expect(k.lastMat![11], closeTo(-3, 1e-9));
      final (lo, hi) = _radii(k.lastGroups!.single.single, const Offset(10, 10));
      expect(lo, closeTo(3, 1e-9),
          reason: 'it starts at the HOLE radius and flares to 6');
      expect(hi, closeTo(3, 1e-9));
    });

    test('flipped, the cone starts wide and closes', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)], dia: 6, flip: true)
        ..type = HoleType.countersink
        ..csDia = 12
        ..csAngle = 90;
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);

      expect(f.computeError, isNull, reason: f.computeError ?? '');
      expect(k.lastTaper, closeTo(-45, 1e-9));
      expect(k.lastMat![11], closeTo(0, 1e-9));
      final (lo, _) = _radii(k.lastGroups!.single.single, const Offset(10, 10));
      expect(lo, closeTo(6, 1e-9), reason: 'the WIDE end leads');
    });

    test('an angle of 180 deg has no cone in it', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)])
        ..type = HoleType.countersink
        ..csDia = 12
        ..csAngle = 180;
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);
      expect(f.solid, isNull);
      expect(f.computeError, contains('between 0 and 180'));
    });
  });

  group('M225 — it is a feature like the others', () {
    test('it consumes the body it drills, like a fillet does', () async {
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)]);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);

      expect(f.modifiesBody, isTrue);
      final base = p.features.whereType<ExtrudeFeature>().single;
      expect(base.consumedByJoin, isTrue,
          reason: 'the drilled body is the one that survives');
      expect(p.bodyNames, ['Solid1'], reason: 'a hole makes no new body');
    });

    test('a pattern refuses it rather than eating the part', () async {
      // M226 — a hole's own solid is the whole body with the hole already in
      // it. The pattern's clone path would place a copy of THAT at every
      // occurrence and cut the part out of itself, silently.
      final k = FakeKernel();
      final (app, p, sk) = await _partWithPoints([const Offset(10, 10)], k);
      final f = _hole(sk, [const Offset(10, 10)]);
      f.seq = p.nextSeq();
      p.appendFeature(f);
      recomputeAllFeatures(p, app.partKernel);

      final pat = PatternFeature(
        name: 'Pattern1',
        bodyName: 'Solid1',
        mode: PatternKind.rectangular,
        sources: [f.name],
      );
      pat.seq = p.nextSeq();
      p.appendFeature(pat);
      recomputeAllFeatures(p, app.partKernel);

      expect(pat.solid, isNull);
      expect(pat.computeError, contains('cannot be patterned yet'));
      expect(pat.computeError, contains('changes the body'));
      expect(pat.computeError, contains('sketch points'),
          reason: 'the refusal names the way round that does work');
    });

    test('round-trips through JSON', () {
      final f = _hole('Sketch2', [const Offset(1, 2), const Offset(3, 4)],
          dia: 8.5, depth: 3, extent: FeatureExtent.throughAll, flip: true);
      f.seq = 7;
      final back = PartFeature.fromJson(f.toJson()) as HoleFeature;
      expect(back.kind, 'hole');
      expect(back.sketchName, 'Sketch2');
      expect(back.places.length, 2);
      expect(back.places[1].x, 3);
      expect(back.dia, 8.5);
      expect(back.extent, FeatureExtent.throughAll);
      expect(back.flip, isTrue);
      expect(back.seq, 7);
      expect(back.type, HoleType.simple, reason: 'M226 defaults to simple');
      expect(back.cbDia, f.cbDia);
      expect(back.csAngle, f.csAngle);
      expect(back.ownSig(), f.ownSig());
    });

    test('the rebuild key notices every number a hole has', () {
      final a = _hole('Sketch2', [const Offset(1, 2)]);
      expect(a.ownSig(), isNot(_hole('Sketch2', [const Offset(1, 2)], dia: 7)
          .ownSig()));
      expect(a.ownSig(),
          isNot(_hole('Sketch2', [const Offset(1, 2)], depth: 11).ownSig()));
      expect(a.ownSig(),
          isNot(_hole('Sketch2', [const Offset(9, 9)]).ownSig()));
      expect(
          a.ownSig(),
          isNot(_hole('Sketch2', [const Offset(1, 2)], flip: true).ownSig()));
      // M226 — and the mouth's numbers, or a counterbore edit would not rebuild.
      final cb = _hole('Sketch2', [const Offset(1, 2)])
        ..type = HoleType.counterbore;
      expect(a.ownSig(), isNot(cb.ownSig()));
      final deeper = _hole('Sketch2', [const Offset(1, 2)])
        ..type = HoleType.counterbore
        ..cbDepth = 9;
      expect(cb.ownSig(), isNot(deeper.ownSig()));
    });
  });
}

Offset _centreOf(List<Offset> loop) {
  var x = 0.0, y = 0.0;
  for (final p in loop) {
    x += p.dx;
    y += p.dy;
  }
  return Offset(x / loop.length, y / loop.length);
}
