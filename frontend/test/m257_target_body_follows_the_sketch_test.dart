// M257 — the target body is the one the sketch was drawn on.
//
// The extrude session defaulted its target to the NEWEST body. That is right
// whenever there is one body and a coin flip whenever there are several, and
// the M253 bundle has what the coin flip costs — twice in one session:
//
//     notice: Zielkörper wählen — in 3D oder im Browser antippen.
//     (preview) body=Solid1 op=cut
//     kernel: cut(a: vol=15557.2693, ...) removed NOTHING
//     (preview) body=Solid3 op=cut
//     extrude: target body picked: Solid3
//
// The sketch was on a face of Solid3 the whole time, and had recorded WHICH
// face since M153 so it could follow that face when the feature under it
// changed height. Nothing had been asking that fingerprint which BODY it was
// on.
//
// The fixtures here carry REAL planar-face metadata — a mesh with triFaces and
// faceInfos — because that is what the lookup reads. A fake solid with a
// degenerate mesh would make every assertion below pass for the wrong reason.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// One planar quad, +Z, spanning [x0,y0]..[x1,y1] at height [z], as face 0.
///
/// The two buffers that matter are triFaces (which face each triangle belongs
/// to) and faceInfos (15 doubles per face: [0] is the surface type, 0 = plane,
/// and [4..6] is the normal). planarFaceRecs reads exactly those and ignores a
/// mesh that carries neither, which is every fake in this suite.
OcctMeshData _quad(double x0, double y0, double x1, double y1, double z) =>
    OcctMeshData(
      Float64List.fromList(
          [x0, y0, z, x1, y0, z, x1, y1, z, x0, y1, z]),
      Float64List.fromList([0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1]),
      Int32List.fromList([0, 1, 2, 0, 2, 3]),
      Int32List.fromList([0]),
      Float64List.fromList(const []),
      triFaces: Int32List.fromList([0, 0]),
      faceInfos: Float64List.fromList(
          [0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0]),
    );

/// The face fingerprint a sketch drawn on that quad would have recorded.
SketchFaceSel _refFor(
        double x0, double y0, double x1, double y1, double z) =>
    SketchFaceSel((x0 + x1) / 2, (y0 + y1) / 2, z, 0, 0, 1,
        (x1 - x0) * (y1 - y0));

PartFeature _body(String name, OcctMeshData mesh) => ExtrudeFeature(
      name: 'Ex$name',
      bodyName: name,
      sketchName: 'Sketch0',
      profiles: [ProfileSel(0, 0, 1)],
    )..solid = KernelSolid(mesh, 1000, null);

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m257');
  return app;
}

/// Two bodies at different heights. Solid2 is the NEWEST — so anything that
/// answers "Solid2" might just be answering "the last one", and every test
/// below that wants a real answer asks for Solid1.
(AppState, PartModel) _twoBodies() {
  final app = _app();
  final p = PartModel('Part1');
  p.features.add(_body('Solid1', _quad(0, 0, 10, 10, 5)));
  p.features.add(_body('Solid2', _quad(40, 0, 50, 10, 9)));
  app.parts['p'] = p;
  app.curTab = 'p';
  return (app, p);
}

/// A sketch drawn on the top face of [body].
ChildSketch _faceSketch(String name, SketchFaceSel ref) => ChildSketch(
      SketchModel(name),
      'face',
      PlaneFrame('face', const Vec3(1, 0, 0), const Vec3(0, 1, 0),
          const Vec3(0, 0, 1), ref.c),
      true,
      false,
      1,
      ref,
    );

void main() {
  group('M257 — which body owns this face', () {
    test('the OLDER body, when its face is the one drawn on', () {
      final (_, p) = _twoBodies();
      final cs = _faceSketch('Sketch1', _refFor(0, 0, 10, 10, 5));
      p.childSketches.add(cs);
      expect(bodyOfFaceSketch(p, cs), 'Solid1',
          reason: 'the newest body is Solid2 — answering that would be the '
              'coin flip this replaces');
    });

    test('and the newer one when THAT is the face', () {
      final (_, p) = _twoBodies();
      final cs = _faceSketch('Sketch1', _refFor(40, 0, 50, 10, 9));
      p.childSketches.add(cs);
      expect(bodyOfFaceSketch(p, cs), 'Solid2');
    });

    test('an origin-plane sketch has no opinion', () {
      final (_, p) = _twoBodies();
      final cs = ChildSketch(SketchModel('Sketch1'), 'xy');
      p.childSketches.add(cs);
      expect(bodyOfFaceSketch(p, cs), isNull,
          reason: 'no face, no answer — the caller keeps its own default');
    });

    test('a face on no body at all has no opinion either', () {
      final (_, p) = _twoBodies();
      // Same size and normal, nowhere near either body: the fingerprint is
      // scored, loses on distance, and is refused by the tolerance rather
      // than handed back as the nearest of two wrong answers.
      final cs = _faceSketch('Sketch1', _refFor(0, 900, 10, 910, 5));
      p.childSketches.add(cs);
      expect(bodyOfFaceSketch(p, cs), isNull);
    });

    test('a face that has MOVED along its normal is still that face', () {
      // The motion M153 exists to follow: the feature under the sketch got
      // taller. It must not cost the sketch its body.
      final (_, p) = _twoBodies();
      final cs = _faceSketch('Sketch1', _refFor(0, 0, 10, 10, 3));
      p.childSketches.add(cs);
      expect(bodyOfFaceSketch(p, cs), 'Solid1');
    });
  });

  group('M257 — and the session uses it', () {
    test('opening Extrude targets the body the sketch is on', () {
      final (app, p) = _twoBodies();
      p.childSketches.add(_faceSketch('Sketch1', _refFor(0, 0, 10, 10, 5)));
      app.openExtrude();
      expect(app.extrudeSession!.bodyName, 'Solid1',
          reason: 'it defaulted to Solid2, the newest, and the user had to '
              'find and tap the right one');
      expect(app.extrudeSession!.output, 'join',
          reason: 'M256 still starts on Join');
    });

    test('the base feature is untouched — there is no body to be wrong about',
        () {
      final app = _app();
      final p = PartModel('Part1');
      p.childSketches.add(ChildSketch(SketchModel('Sketch1'), 'xy'));
      app.parts['p'] = p;
      app.curTab = 'p';
      app.openExtrude();
      expect(app.extrudeSession!.output, 'new');
      expect(app.extrudeSession!.bodyName, isNotEmpty);
    });

    test('a body picked by hand is never argued with', () {
      final (app, p) = _twoBodies();
      p.childSketches.add(_faceSketch('Sketch1', _refFor(0, 0, 10, 10, 5)));
      app.openExtrude();
      expect(app.extrudeSession!.bodyName, 'Solid1');
      app.pickBody('Solid2'); // the user means Solid2, whatever the face says
      expect(app.extrudeSession!.bodyName, 'Solid2');
      expect(app.extrudeSession!.bodyIsTheirs, isTrue);
      // ...and re-running the rule leaves it alone.
      app.openExtrude(); // toggles the panel shut
      app.openExtrude(); // and open again — a fresh session, fresh suggestion
      expect(app.extrudeSession!.bodyName, 'Solid1',
          reason: 'the lock belongs to the session, not to the document');
    });

    test('editing an existing feature keeps ITS body', () {
      final (app, p) = _twoBodies();
      p.childSketches.add(_faceSketch('Sketch1', _refFor(0, 0, 10, 10, 5)));
      // A feature on Solid2 built from a sketch that sits on Solid1. Contrived
      // on purpose: it is the case where the rule and the record disagree, and
      // the record is a decision the user already made.
      final f = ExtrudeFeature(
        name: 'Extrusion7',
        bodyName: 'Solid2',
        sketchName: 'Sketch1',
        profiles: [ProfileSel(5, 5, 100)],
        output: 'cut',
      );
      p.appendFeature(f);
      app.openExtrude(f);
      expect(app.extrudeSession!.bodyName, 'Solid2');
      expect(app.extrudeSession!.bodyIsTheirs, isTrue);
    });
  });
}
