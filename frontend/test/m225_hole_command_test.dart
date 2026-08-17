// M225 (2/2) — the Hole COMMAND: the panel's session, the pick, the commit.
//
// The feature itself is pinned in m225_hole_test.dart. This is the half that
// decides whether it can be reached at all: arming, what a tap on a sketch
// point does, what OK builds, and the refusals that keep the panel honest.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/tools.dart' show Tool;

import 'm56_part_test.dart' show FakeKernel, addRectLines;

/// A part with a built base extrusion and a second sketch holding [pts].
Future<AppState> _app(List<Offset> pts, {bool withBase = true}) async {
  final app = AppState()..partKernel = FakeKernel();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m225c_');
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  addRectLines(app.activeChild!, 0, 0, 40, 30, layer: app.editingLayer!);
  app.finishPartSketch();
  final p = app.currentPart!;
  if (withBase) {
    final base = ExtrudeFeature(
      name: 'Extrusion1',
      bodyName: 'Solid1',
      sketchName: p.childSketches.single.model.name,
      profiles: [ProfileSel(20, 15, 1200)],
      distanceA: 12,
    )..output = 'new';
    base.seq = p.nextSeq();
    p.appendFeature(base);
    recomputeAllFeatures(p, app.partKernel);
  }
  if (pts.isNotEmpty) {
    app.startPartSketch();
    app.planePicked('xy');
    for (final c in pts) {
      app.tool = Tool.point;
      app.toolClick(c);
    }
    app.tool = Tool.none;
    app.finishPartSketch();
  }
  return app;
}

String _lastSketch(AppState app) =>
    app.currentPart!.childSketches.last.model.name;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M225 — arming the command', () {
    test('the same entry twice closes it (M210s toggle)', () async {
      final app = await _app([const Offset(10, 10)]);
      app.openHole();
      expect(app.holeSession, isNotNull);
      expect(app.holePicking3D, isTrue);
      app.openHole();
      expect(app.holeSession, isNull);
    });

    test('a part with no body says so instead of opening', () async {
      final app = await _app([const Offset(10, 10)], withBase: false);
      app.openHole();
      expect(app.holeSession, isNull,
          reason: 'a hole needs material — opening a panel that cannot '
              'produce anything is the dead control M216 removed');
    });

    test('it takes the viewport back from an open sketch', () async {
      final app = await _app([const Offset(10, 10)]);
      app.openChildSketch(_lastSketch(app));
      expect(app.activeChild, isNotNull);
      app.openHole();
      expect(app.activeChild, isNull, reason: 'M221 — its picks are 3D picks');
      expect(app.holeSession, isNotNull);
    });

    test('Esc closes the panel and its picking together', () async {
      final app = await _app([const Offset(10, 10)]);
      app.openHole();
      app.escape3D();
      expect(app.holeSession, isNull);
      expect(app.holePicking3D, isFalse);
    });

    test('opening Extrude closes the hole panel', () async {
      final app = await _app([const Offset(10, 10)]);
      app.openHole();
      app.openExtrude();
      expect(app.holeSession, isNull,
          reason: 'two 3D panels competing for one tap is not a UI');
    });
  });

  group('M225 — picking the points', () {
    test('a tap adds a placement, the same tap again removes it', () async {
      final app = await _app([const Offset(10, 10), const Offset(30, 20)]);
      final sk = _lastSketch(app);
      app.openHole();
      app.holePointPicked(sk, const Offset(10, 10));
      app.holePointPicked(sk, const Offset(30, 20));
      expect(app.holeSession!.places.length, 2);
      app.holePointPicked(sk, const Offset(10, 10));
      expect(app.holeSession!.places.length, 1);
      expect(app.holeSession!.places.single.x, 30);
    });

    test('the last placement removed clears the sketch binding', () async {
      final app = await _app([const Offset(10, 10)]);
      final sk = _lastSketch(app);
      app.openHole();
      app.holePointPicked(sk, const Offset(10, 10));
      expect(app.holeSession!.sketchName, sk);
      app.holePointPicked(sk, const Offset(10, 10));
      expect(app.holeSession!.sketchName, isNull,
          reason: 'with nothing picked, any sketch is still open to it');
    });

    test('holes of one feature come from ONE sketch', () async {
      final app = await _app([const Offset(10, 10)]);
      final first = _lastSketch(app);
      app.openHole();
      app.holePointPicked(first, const Offset(10, 10));
      app.holePointPicked('Sketch99', const Offset(5, 5));
      expect(app.holeSession!.places.length, 1);
      expect(app.holeSession!.sketchName, first);
    });
  });

  group('M225 — OK', () {
    test('builds the feature, on the body it drills', () async {
      final app = await _app([const Offset(10, 10), const Offset(30, 20)]);
      final p = app.currentPart!;
      final sk = _lastSketch(app);
      app.openHole();
      app.holePointPicked(sk, const Offset(10, 10));
      app.holePointPicked(sk, const Offset(30, 20));
      app.setHole(exprDia: '8 mm', exprDepth: '5 mm');
      expect(await app.applyHole(), isTrue);

      final f = p.features.whereType<HoleFeature>().single;
      expect(f.name, 'Hole1');
      expect(f.bodyName, 'Solid1');
      expect(f.places.length, 2);
      expect(f.dia, 8);
      expect(f.depth, 5);
      expect(f.sketchName, sk);
      expect(f.computeError, isNull, reason: f.computeError ?? '');
      expect(app.holeSession, isNull, reason: 'the panel closes on OK');
    });

    test('with no point picked it refuses and stays open', () async {
      final app = await _app([const Offset(10, 10)]);
      app.openHole();
      expect(await app.applyHole(), isFalse);
      expect(app.holeSession, isNotNull);
      expect(app.currentPart!.features.whereType<HoleFeature>(), isEmpty);
    });

    test('a diameter that is not a number is refused', () async {
      final app = await _app([const Offset(10, 10)]);
      final sk = _lastSketch(app);
      app.openHole();
      app.holePointPicked(sk, const Offset(10, 10));
      app.setHole(exprDia: 'wide');
      expect(await app.applyHole(), isFalse);
      expect(app.holeSession, isNotNull);
    });

    test('Through All needs no depth at all', () async {
      final app = await _app([const Offset(10, 10)]);
      final sk = _lastSketch(app);
      app.openHole();
      app.holePointPicked(sk, const Offset(10, 10));
      app.setHole(extent: FeatureExtent.throughAll, exprDepth: '');
      expect(await app.applyHole(), isTrue);
      final f = app.currentPart!.features.whereType<HoleFeature>().single;
      expect(f.extent, FeatureExtent.throughAll);
      expect(f.computeError, isNull, reason: f.computeError ?? '');
    });

    test('editing an existing hole replaces it in place', () async {
      final app = await _app([const Offset(10, 10)]);
      final p = app.currentPart!;
      final sk = _lastSketch(app);
      app.openHole();
      app.holePointPicked(sk, const Offset(10, 10));
      await app.applyHole();
      final first = p.features.whereType<HoleFeature>().single;
      final seq = first.seq;
      final count = p.features.length;

      app.openHole(first);
      expect(app.holeSession!.places.length, 1,
          reason: 'the panel opens with what the feature holds');
      app.setHole(exprDia: '12 mm');
      expect(await app.applyHole(), isTrue);

      expect(p.features.length, count, reason: 'edited, not appended');
      final again = p.features.whereType<HoleFeature>().single;
      expect(again.dia, 12);
      expect(again.seq, seq, reason: 'it keeps its place in the timeline');
      expect(again.name, 'Hole1');
    });
  });
}
