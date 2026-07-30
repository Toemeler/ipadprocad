// M153 — a sketch drawn on a face now follows that face.
//
// Reported: draw a sketch on the top of an extrusion, change the extrusion's
// height, and the sketch stays at the old height while its face walks off.
// ChildSketch stored only the frame baked at pick time (M58) — there was
// nothing that could have made it follow.
//
// SketchFaceSel is the twin of EdgeSel and is shaped by one asymmetry:
// movement ALONG the face normal is exactly what "the extrusion got taller"
// looks like and must be free, while sideways drift means a different face and
// must not be. Area is the third term, separating coaxial faces — the top of a
// boss and the top of the cylinder under it share a normal and very nearly
// share a centre axis, which is the confusion that put a chamfer on the wrong
// rim in M152.
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart' show SketchModel;
import 'package:prototype/part_model.dart';

FaceRec top(int id, double r, double z) =>
    FaceRec(id, Vec3(0, 0, z), const Vec3(0, 0, 1), 3.14159265 * r * r);

const eps = 1e-9;

void main() {
  group('following the face', () {
    test('a face that moved along its normal is still the same face', () {
      final sel = SketchFaceSel.of(top(1, 20, 10));
      final grown = top(1, 20, 25); // extrusion got 15 mm taller
      final m = sel.bestMatch([grown]);
      expect(m, isNotNull);
      expect(sel.alongTo(m!), closeTo(15, eps));
    });

    test('the shift is reported even when the face id changes', () {
      // Face indices are not stable across a rebuild; that is the entire
      // reason this class exists rather than a stored id.
      final sel = SketchFaceSel.of(top(1, 20, 0));
      expect(sel.bestMatch([top(9, 20, 8)])!.id, 9);
    });

    test('re-anchoring makes the shift relative to the NEW position', () {
      // Otherwise every rebuild would re-apply the whole accumulated offset.
      final sel = SketchFaceSel.of(top(1, 20, 0));
      final a = top(1, 20, 10);
      expect(sel.alongTo(a), closeTo(10, eps));
      sel.reanchor(a);
      expect(sel.alongTo(a), closeTo(0, eps));
      expect(sel.alongTo(top(1, 20, 14)), closeTo(4, eps));
    });
  });

  group('not following the wrong face', () {
    test('the opposite face of a plate is not a match', () {
      // Parallel but oppositely oriented: the bottom of the plate.
      final sel = SketchFaceSel.of(top(1, 20, 10));
      final bottom = FaceRec(2, const Vec3(0, 0, 0), const Vec3(0, 0, -1),
          3.14159265 * 20 * 20);
      expect(sel.bestMatch([bottom]), isNull);
    });

    test('a coaxial face of a different size is rejected on area', () {
      // The boss top and the cylinder top: same normal, both centred on the
      // axis, so position alone says they are identical.
      final boss = top(1, 20, 30);
      final cyl = top(2, 60, 0);
      expect(sel_(boss).bestMatch([cyl, boss])!.id, 1);
      expect(sel_(cyl).bestMatch([cyl, boss])!.id, 2);
    });

    test('a face that slid sideways is not followed', () {
      final sel = SketchFaceSel.of(top(1, 5, 0));
      final moved = FaceRec(2, const Vec3(80, 0, 0), const Vec3(0, 0, 1),
          3.14159265 * 25);
      expect(sel.bestMatch([moved]), isNull);
    });

    test('when the face is gone the sketch is left alone, not relocated', () {
      // Stuck at the old height is visible and fixable. Silently moved onto
      // some other face is the bug M152 paid for.
      final sel = SketchFaceSel.of(top(1, 20, 0));
      expect(sel.bestMatch(const []), isNull);
    });
  });

  group('reanchorFaceSketches', () {
    test('a sketch with no faceRef is never touched', () {
      // Pre-M153 documents keep the old frozen behaviour rather than being
      // re-anchored onto a face nobody chose.
      final p = PartModel('P');
      final frame = planeFrame('xy');
      p.childSketches.add(ChildSketch(SketchModel('S'), 'face', frame));
      expect(reanchorFaceSketches(p), 0);
      expect(p.childSketches.first.face!.origin.z, closeTo(0, eps));
    });

    test('origin-plane sketches are never touched', () {
      final p = PartModel('P');
      p.childSketches.add(ChildSketch(SketchModel('S'), 'xy'));
      expect(reanchorFaceSketches(p), 0);
    });
  });

  group('persistence', () {
    test('the reference round-trips', () {
      final sel = SketchFaceSel.of(top(1, 20, 7));
      final back = SketchFaceSel.fromJson(sel.toJson())!;
      expect(back.cz, closeTo(7, eps));
      expect(back.nz, closeTo(1, eps));
      expect(back.area, closeTo(sel.area, eps));
    });

    test('a malformed reference is dropped rather than fatal', () {
      expect(SketchFaceSel.fromJson({'c': [1, 2]}), isNull);
    });
  });
}

SketchFaceSel sel_(FaceRec f) => SketchFaceSel.of(f);
