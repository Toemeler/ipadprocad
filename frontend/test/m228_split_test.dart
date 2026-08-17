// M228 — Inventor's Modify > Split, in the half this architecture carries:
// Trim Solid.
//
// Inventor's Split does three things: split a FACE with a curve, split a body
// into TWO bodies, and trim a body away on one side of a plane. The middle one
// is not a footnote — a feature that produces a SECOND body has no place in a
// fold that maps one feature to one solid and folds it into one chain. So this
// is the trim, and the panel says so rather than leaving the user to find out.
//
// The tool is the half-space box Slice Graphics has been building since M168,
// which is why its sizing is not re-derived here: it has been cutting the near
// side away on every device session since.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

import 'm56_part_test.dart' show FakeKernel, addRectLines;

Future<AppState> _appWithBody({bool build = true}) async {
  final app = AppState()..partKernel = FakeKernel();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m228_');
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  addRectLines(app.activeChild!, 0, 0, 40, 30, layer: app.editingLayer!);
  app.finishPartSketch();
  if (build) {
    final p = app.currentPart!;
    final f = ExtrudeFeature(
      name: 'Extrusion1',
      bodyName: 'Solid1',
      sketchName: p.childSketches.single.model.name,
      profiles: [ProfileSel(20, 15, 1200)],
      distanceA: 12,
    )..output = 'new';
    f.seq = p.nextSeq();
    p.appendFeature(f);
    recomputeAllFeatures(p, app.partKernel);
  }
  return app;
}

SplitFeature _split(PartModel p, {bool flip = false, PlaneFrame? frame}) {
  final f = SplitFeature(
    name: 'Split1',
    bodyName: 'Solid1',
    frame: frame ?? offsetPlaneFrame(planeFrame('xy'), 5),
    label: 'XY Plane',
    flip: flip,
  );
  f.seq = p.nextSeq();
  p.appendFeature(f);
  return f;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M228 — the trim', () {
    test('one cut with a half-space, from the plane', () async {
      final app = await _appWithBody();
      final p = app.currentPart!;
      final k = app.partKernel as FakeKernel;
      final f = _split(p);
      recomputeAllFeatures(p, k);

      expect(f.computeError, isNull, reason: f.computeError ?? '');
      expect(k.cuts, 1, reason: 'the half-space is cut away, once');
      expect(f.solid, isNotNull);
      // The tool starts AT the plane and runs along +n.
      expect(k.lastMat![11], closeTo(5, 1e-9));
      expect(k.lastHeight, greaterThan(40),
          reason: 'long enough to swallow a 40x30 part');
      expect(p.features.first.consumedByJoin, isTrue,
          reason: 'the trimmed body is what survives');
    });

    test('flip keeps the other side', () async {
      final app = await _appWithBody();
      final p = app.currentPart!;
      final k = app.partKernel as FakeKernel;
      _split(p, flip: true);
      recomputeAllFeatures(p, k);

      final start = k.lastMat![11], h = k.lastHeight!;
      expect(start, lessThan(5),
          reason: 'the box is started a full length back');
      expect(start + h, closeTo(5, 1e-6),
          reason: 'and ends exactly ON the plane, so the two sides meet '
              'there and neither is cut twice');
    });

    test('with no body it says so', () async {
      final app = await _appWithBody(build: false);
      final p = app.currentPart!;
      final f = _split(p);
      recomputeAllFeatures(p, app.partKernel);
      expect(f.solid, isNull);
      expect(f.computeError, contains('needs a body'));
    });

    test('a plane with no normal is refused', () async {
      final app = await _appWithBody();
      final p = app.currentPart!;
      final f = _split(p,
          frame: const PlaneFrame('work', Vec3(1, 0, 0), Vec3(0, 1, 0),
              Vec3.zero, Vec3.zero));
      recomputeAllFeatures(p, app.partKernel);
      expect(f.solid, isNull);
      expect(f.computeError, contains('plane is gone'));
    });

    test('round-trips through JSON, frame and all', () async {
      final app = await _appWithBody();
      final p = app.currentPart!;
      final f = _split(p, flip: true);
      final back = PartFeature.fromJson(f.toJson()) as SplitFeature;
      expect(back.kind, 'split');
      expect(back.flip, isTrue);
      expect(back.label, 'XY Plane');
      expect(back.frame.origin.z, closeTo(5, 1e-9));
      expect(back.frame.n.z, closeTo(1, 1e-9));
      expect(back.ownSig(), f.ownSig());
    });

    test('the key notices the plane AND the side', () {
      final a = SplitFeature(
          name: 'S', bodyName: 'B', frame: planeFrame('xy'));
      final moved = SplitFeature(
          name: 'S',
          bodyName: 'B',
          frame: offsetPlaneFrame(planeFrame('xy'), 3));
      final flipped = SplitFeature(
          name: 'S', bodyName: 'B', frame: planeFrame('xy'), flip: true);
      expect(a.ownSig(), isNot(moved.ownSig()));
      expect(a.ownSig(), isNot(flipped.ownSig()));
    });
  });

  group('M228 — the command', () {
    test('it needs a body, and asks for a plane', () async {
      final empty = await _appWithBody(build: false);
      empty.openSplit();
      expect(empty.splitSession, isNull, reason: 'nothing to trim');

      final app = await _appWithBody();
      app.openSplit();
      expect(app.splitSession, isNotNull);
      expect(app.pickPlane, isTrue, reason: 'the plane pick is armed');
      expect(app.currentPart!.vis['xy'], isTrue,
          reason: 'the origin planes come out, as they do for a sketch');
    });

    test('picking a plane fills the panel and ends the pick', () async {
      final app = await _appWithBody();
      app.openSplit();
      app.planePicked('xz');
      expect(app.splitSession!.frame, isNotNull);
      expect(app.splitSession!.label, contains('XZ'));
      expect(app.pickPlane, isFalse);
      expect(app.currentPart!.vis['xy'], isFalse,
          reason: 'and the origin planes go away again');
      expect(app.currentPart!.childSketches.length, 1,
          reason: 'the pick must NOT start a sketch — that is the other flow');
    });

    test('OK builds the feature with the plane that was picked', () async {
      final app = await _appWithBody();
      final p = app.currentPart!;
      app.openSplit();
      app.planePicked('xz');
      app.setSplit(flip: true);
      expect(await app.applySplit(), isTrue);

      final f = p.features.whereType<SplitFeature>().single;
      expect(f.name, 'Split1');
      expect(f.bodyName, 'Solid1');
      expect(f.flip, isTrue);
      expect(f.frame.n.y.abs(), closeTo(1, 1e-9), reason: 'the XZ normal');
      expect(f.computeError, isNull, reason: f.computeError ?? '');
      expect(app.splitSession, isNull);
    });

    test('without a plane OK refuses and the panel stays', () async {
      final app = await _appWithBody();
      app.openSplit();
      expect(await app.applySplit(), isFalse);
      expect(app.splitSession, isNotNull);
    });

    test('Esc closes it and puts the origin planes back', () async {
      final app = await _appWithBody();
      app.openSplit();
      expect(app.currentPart!.vis['xy'], isTrue);
      app.escape3D();
      expect(app.splitSession, isNull);
      expect(app.pickPlane, isFalse);
      expect(app.currentPart!.vis['xy'], isFalse);
    });

    test('another 3D panel displaces it', () async {
      final app = await _appWithBody();
      app.openSplit();
      app.openExtrude();
      expect(app.splitSession, isNull);
      expect(app.pickPlane, isFalse,
          reason: 'and its plane pick goes with it');
    });

    test('the browser can open it', () async {
      final app = await _appWithBody();
      final p = app.currentPart!;
      app.openSplit();
      app.planePicked('xz');
      await app.applySplit();
      final f = p.features.whereType<SplitFeature>().single;

      app.editFeature(f);
      expect(app.splitSession, isNotNull);
      expect(app.splitSession!.editing, same(f));
      expect(app.splitSession!.frame, isNotNull,
          reason: 'it opens with the plane it already has, not asking again');
      expect(app.pickPlane, isFalse);
    });
  });
}
