// M168 — Inventor's Slice Graphics (F7) in the 2D sketch ribbon.
//
// Inside a sketch, cut away everything between the viewer and the sketch
// plane so the part can be seen and drawn INSIDE. A display state: nothing
// enters the timeline and it clears when the sketch closes.
//
// The cut is a real boolean, not a clipped render, because the section faces
// have to be REAL faces — a hatch follows actual face boundaries, and a
// clipped render has none to follow.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart';

import 'm56_part_test.dart' show FakeKernel, addRectLines;

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m168_');
  app.partKernel = FakeKernel();
  return app;
}

Future<AppState> _partWithSolidAndOpenSketch() async {
  final app = _app();
  await app.createNamedPart('P');
  app.startPartSketch();
  app.planePicked('xy');
  addRectLines(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
  await app.applyExtrude();
  // ... and a second sketch, left OPEN: that is when slicing is offered.
  app.startPartSketch();
  app.planePicked('yz');
  return app;
}

void main() {
  group('M168 — when the command is offered', () {
    test('never outside a sketch', () async {
      final app = _app();
      await app.createNamedPart('P');
      expect(app.canSliceGraphics, isFalse, reason: 'no sketch open');
    });

    test('never without a solid to cut', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startPartSketch();
      app.planePicked('xy');
      expect(app.activeChild, isNotNull);
      expect(app.canSliceGraphics, isFalse,
          reason: 'a sketch on an empty part has nothing to slice');
    });

    test('yes with a solid and an open sketch', () async {
      final app = await _partWithSolidAndOpenSketch();
      expect(app.canSliceGraphics, isTrue);
    });

    test('toggling is refused when it is not offered', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.toggleSliceGraphics();
      expect(app.sliceGraphics, isFalse,
          reason: 'the ribbon hides the button, and the call is guarded too');
    });
  });

  group('M168 — the state', () {
    test('toggles on and off', () async {
      final app = await _partWithSolidAndOpenSketch();
      app.toggleSliceGraphics();
      expect(app.sliceGraphics, isTrue);
      app.toggleSliceGraphics();
      expect(app.sliceGraphics, isFalse);
    });

    test('closing the sketch clears it', () async {
      final app = await _partWithSolidAndOpenSketch();
      app.toggleSliceGraphics();
      expect(app.sliceGraphics, isTrue);
      app.finishPartSketch();
      expect(app.sliceGraphics, isFalse,
          reason: 'a sketch display state must not cut the PART view');
      expect(app.canSliceGraphics, isFalse);
    });

    test('it is in the scene signature, so toggling actually redraws',
        () async {
      // M95/M122/M165, the same lesson a fourth time: a change absent from the
      // signature sends no rebuild and the button appears dead.
      final app = await _partWithSolidAndOpenSketch();
      final p = app.currentPart!;
      final before = sceneSignature(app, p);
      app.toggleSliceGraphics();
      expect(sceneSignature(app, p), isNot(before));
    });
  });

  _sectionTests();

  group('M168 — a failed slice never hides the part', () {
    test('with no kernel the solid is drawn WHOLE', () async {
      final app = await _partWithSolidAndOpenSketch();
      app.toggleSliceGraphics();
      final p = app.currentPart!;
      final whole = p.features.first.solid!;
      // FakeKernel returns a stub for extrude but null for a cut it cannot do;
      // either way the scene must still contain the body.
      final ids = [for (final (id, _) in visibleSolids(app, p)) id];
      expect(ids, contains('Extrusion1'),
          reason: 'the part is never allowed to vanish because a cut failed');
      final shown = visibleSolids(app, p)
          .firstWhere((e) => e.$1 == 'Extrusion1')
          .$2;
      expect(shown, isNotNull);
      expect(identical(shown, whole) || shown.volume != whole.volume, isTrue,
          reason: 'either the original, or a genuinely different cut solid');
    });

    test('slicedSolid returns null when the state is off', () async {
      final app = await _partWithSolidAndOpenSketch();
      final f = app.currentPart!.features.first;
      expect(app.slicedSolid(f.name, f.solid!), isNull);
    });
  });
}

// --- the HATCH ------------------------------------------------------------
// The cut is made AT the sketch plane, so the exposed faces are exactly
// coplanar with the sketch. That is what makes the hatch a 2D job: it is
// drawn flat on the sketch by the Dart painter, not as a material wrapped on
// a 3D surface — which is also how Inventor draws it, and it means the
// hatching needs no native renderer work at all.
void _sectionTests() {
  OcctMeshData _mesh(List<double> pos, List<int> idx) => OcctMeshData(
        Float64List.fromList(pos),
        Float64List.fromList(List<double>.filled(pos.length, 0)),
        Int32List.fromList(idx),
        Int32List(0),
        Float64List(0),
      );

  final xy = planeFrame('xy'); // z = 0, normal +z

  group('M168 — which faces get hatched', () {
    test('a triangle IN the plane is a section face', () {
      final m = _mesh([0, 0, 0, 10, 0, 0, 0, 10, 0], [0, 1, 2]);
      final tris = sectionTrianglesAt(m, xy);
      expect(tris.length, 1);
      expect(tris.single.length, 3);
      // ... returned in the sketch's own (u,v), ready to draw
      expect(tris.single[1].dx, closeTo(10, 1e-9));
      expect(tris.single[2].dy, closeTo(10, 1e-9));
    });

    test('a triangle OFF the plane is the remaining body, not a section', () {
      final m = _mesh([0, 0, 5, 10, 0, 5, 0, 10, 5], [0, 1, 2]);
      expect(sectionTrianglesAt(m, xy), isEmpty,
          reason: 'hatching the whole body would be nonsense');
    });

    test('a triangle only PARTLY in the plane is not one either', () {
      final m = _mesh([0, 0, 0, 10, 0, 0, 0, 10, 5], [0, 1, 2]);
      expect(sectionTrianglesAt(m, xy), isEmpty);
    });

    test('a sliver with no area is dropped', () {
      // Collinear points: no meaningful normal, and nothing to fill.
      final m = _mesh([0, 0, 0, 5, 0, 0, 10, 0, 0], [0, 1, 2]);
      expect(sectionTrianglesAt(m, xy), isEmpty);
    });

    test('a mixed mesh yields only the cut face', () {
      final m = _mesh([
        0, 0, 0, 10, 0, 0, 0, 10, 0, // in plane
        0, 0, 5, 10, 0, 5, 0, 10, 5, // above it
      ], [
        0, 1, 2, 3, 4, 5,
      ]);
      expect(sectionTrianglesAt(m, xy).length, 1);
    });

    test('it works on an offset plane too, not just through the origin', () {
      final fr = offsetPlaneFrame(xy, 7);
      final m = _mesh([0, 0, 7, 10, 0, 7, 0, 10, 7], [0, 1, 2]);
      final tris = sectionTrianglesAt(m, fr);
      expect(tris.length, 1);
      expect(tris.single[0].dx, closeTo(0, 1e-9),
          reason: 'measured from the plane origin, so the hatch lands on it');
    });

    test('a truncated index list cannot crash the painter', () {
      final m = _mesh([0, 0, 0, 10, 0, 0], [0, 1, 9]);
      expect(sectionTrianglesAt(m, xy), isEmpty);
    });
  });

  group('M168 — the painter is only asked when it should be', () {
    // M222 — the painter asks per BODY now (outlines, not triangles); the
    // rule it is asking about is unchanged.
    test('no section faces while slicing is off', () async {
      final app = await _partWithSolidAndOpenSketch();
      expect(app.sectionSlices(), isEmpty);
    });
  });
}
