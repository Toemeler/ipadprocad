// M166 — a sketch on a face must follow that face when the face MOVES.
//
// Reported: make a sketch on an extrusion, do something else, then go back and
// make the first extrusion higher — the sketch stays behind.
//
// Device log (build 1fda99e):
//   09:49:39  part: extrude edited Extrusion2 (Solid1) h=20.0/0.0 ok=true
//   09:49:39  mesh Sweep1: ... bbox=-5.4,-4.1,-23.7..34.6,25.0,5.4
//
// Extrusion2 went from 5 mm to 20 mm, so its top face moved from y=10 to
// y=25. Sketch3 sits on that face and Extrusion3 stands on Sketch3 — had it
// followed, the body would reach y=30 and the bbox would say so. It says 25.
//
// M153 built the following machinery (SketchFaceSel, reanchorFaceSketches) and
// it works. The bug is ORDER. Inside one rebuild pass it must be:
//   1. build the features   (needs the sketches)
//   2. re-anchor the sketches onto the faces that just moved  (needs solids)
// so a sketch that moves in step 2 moves AFTER everything built from it, and
// nothing scheduled another rebuild. The fix is to iterate until the sketches
// stop moving.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart' show SketchModel;
import 'package:prototype/part_model.dart';


void main() {
  group('M166 — the face a sketch sits on has moved', () {
    /// Sketch3 as the device had it: anchored to the top face of a 5 mm
    /// extrusion standing on a 5 mm one, so at y=10.
    SketchFaceSel sel() => SketchFaceSel(0, 10, 0, 0, 1, 0, 4);

    test('it recognises the same face after it moved along its normal', () {
      // Extrusion2 edited 5 mm -> 20 mm: the top face is now at y=25.
      final moved = FaceRec(7, const Vec3(0, 25, 0), const Vec3(0, 1, 0), 4);
      final m = sel().bestMatch([moved]);
      expect(m, isNotNull,
          reason: 'displacement ALONG the normal is the expected motion and '
              'must not disqualify the face');
      expect(sel().alongTo(m!), closeTo(15, 1e-9),
          reason: 'exactly how far the sketch frame has to travel');
    });

    test('it prefers the face at the same place over a parallel twin', () {
      final bottom = FaceRec(1, const Vec3(0, 5, 0), const Vec3(0, 1, 0), 4);
      final top = FaceRec(2, const Vec3(0, 25, 0), const Vec3(0, 1, 0), 4);
      // Anchored at y=25 already: the nearer one wins.
      final s = SketchFaceSel(0, 25, 0, 0, 1, 0, 4);
      expect(s.bestMatch([bottom, top])!.id, 2);
    });

    test('a face pointing the other way is never the same face', () {
      // The top and the bottom of a plate are parallel and opposite.
      final under = FaceRec(3, const Vec3(0, 25, 0), const Vec3(0, -1, 0), 4);
      expect(sel().bestMatch([under]), isNull);
    });

    test('a face of a very different SIZE is not it either', () {
      final huge = FaceRec(4, const Vec3(0, 25, 0), const Vec3(0, 1, 0), 400);
      expect(sel().bestMatch([huge]), isNull,
          reason: 'area is part of the fingerprint, not just position');
    });

    test('reanchor updates the fingerprint so the next move is relative', () {
      final s = sel();
      final moved = FaceRec(7, const Vec3(0, 25, 0), const Vec3(0, 1, 0), 4);
      s.reanchor(moved);
      expect(s.alongTo(moved), closeTo(0, 1e-12),
          reason: 'settled: this is what ends the rebuild loop');
      final again = FaceRec(7, const Vec3(0, 30, 0), const Vec3(0, 1, 0), 4);
      expect(s.alongTo(again), closeTo(5, 1e-9),
          reason: 'and the next move is measured from where it now is');
    });
  });

  group('M166 — nothing to follow', () {
    test('a sketch on an origin plane has no face reference at all', () {
      final p = PartModel('P');
      p.childSketches
          .add(ChildSketch(SketchModel('Sketch1'), 'xy', null, true, false, 0));
      expect(reanchorFaceSketches(p), 0);
    });

    test('a part with no solids moves nothing', () {
      final p = PartModel('P');
      final fr = PlaneFrame('face', const Vec3(1, 0, 0), const Vec3(0, 0, 1),
          const Vec3(0, 1, 0), const Vec3(0, 10, 0));
      p.childSketches.add(
          ChildSketch(SketchModel('Sketch3'), 'face', fr, true, false, 2)
            ..faceRef = SketchFaceSel(0, 10, 0, 0, 1, 0, 4));
      expect(reanchorFaceSketches(p), 0, reason: 'no faces to anchor to');
      expect(p.childSketches.single.face!.origin.y, 10,
          reason: 'and the frame is left exactly where it was');
    });
  });
}
