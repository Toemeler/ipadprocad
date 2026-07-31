// M165 — a work plane you cannot see is a work plane that does not exist.
//
// Reported: "I didn't see any plane placed in the timeline or in the 3D view."
// Both are true, and neither is the plane code failing — the planes ARE built,
// named and saved (the user's Part4.part.json carries two). They simply never
// reached the renderer: the RealityKit payload only ever carried the three
// ORIGIN planes, so on the device a work plane was invisible from the moment
// it was created.
//
// They are also sized by the same `planeRectFor` the origin planes use, so a
// work plane frames the model instead of being a fixed square (M83/M151 kept
// that function shared precisely so the two kinds cannot drift apart).
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart';

/// The plane payload the device renderer actually receives.
List<Map<String, dynamic>> _planes(AppState app, PartModel p) =>
    (buildScenePayload(app, p)['planes'] as List).cast<Map<String, dynamic>>();

PartModel _partWithPlane({double offset = 10}) {
  final p = PartModel('P');
  final base = planeFrame('xy');
  p.workPlanes.add(WorkPlane('Work Plane1', 1, WorkPlaneKind.offset,
      'Offset from XY', offsetPlaneFrame(base, offset),
      base: base, offset: offset));
  return p;
}

void main() {
  group('M165 — the plane reaches the renderer', () {
    test('a work plane is emitted alongside the origin planes', () {
      final app = AppState();
      final p = _partWithPlane();
      final planes = _planes(app, p);
      final ids = [for (final m in planes) m['key'] as String];
      expect(ids, containsAll(kPlaneKeys),
          reason: 'the origin planes are still there');
      expect(ids, contains('wp:1'), reason: 'and so is the work plane');
    });

    test('it carries a frame, an origin and a rectangle', () {
      final app = AppState();
      final w = _planes(app, _partWithPlane())
          .firstWhere((m) => m['key'] == 'wp:1');
      expect((w['frame'] as List).length, 9);
      expect((w['origin'] as List)[2], closeTo(10.0, 1e-9),
          reason: 'offset 10 mm along the XY normal');
      expect(w['uMax'], isA<double>());
      expect(w['visible'], isTrue);
    });

    test('it is sized like an ORIGIN plane, not a fixed square', () {
      final app = AppState();
      final p = _partWithPlane();
      final w = _planes(app, p).firstWhere((m) => m['key'] == 'wp:1');
      final (uMin, uMax, vMin, vMax) = planeRectFor(p, p.workPlanes.single.frame);
      expect(w['uMin'], uMin);
      expect(w['uMax'], uMax);
      expect(w['vMin'], vMin);
      expect(w['vMax'], vMax);
    });

    test('a hidden plane says so rather than being dropped', () {
      final app = AppState();
      final p = _partWithPlane();
      p.workPlanes.single.visible = false;
      final w = _planes(app, p).firstWhere((m) => m['key'] == 'wp:1');
      expect(w['visible'], isFalse);
    });
  });

  group('M165 — moving it actually redraws', () {
    test('the scene signature contains the plane', () {
      final app = AppState();
      final bare = PartModel('P');
      expect(sceneSignature(app, bare),
          isNot(sceneSignature(app, _partWithPlane())));
    });

    test('re-offsetting changes the signature', () {
      // M95/M122's lesson: a change absent from the signature sends no
      // rebuild, and the plane would appear not to move at all.
      final app = AppState();
      final p = _partWithPlane();
      final before = sceneSignature(app, p);
      p.workPlanes.single.setOffset(25);
      expect(sceneSignature(app, p), isNot(before));
    });

    test('hiding it changes the signature', () {
      final app = AppState();
      final p = _partWithPlane();
      final before = sceneSignature(app, p);
      p.workPlanes.single.visible = false;
      expect(sceneSignature(app, p), isNot(before));
    });

    test('an unchanged part still reports the same signature', () {
      final app = AppState();
      final p = _partWithPlane();
      expect(sceneSignature(app, p), sceneSignature(app, p));
    });
  });
}
