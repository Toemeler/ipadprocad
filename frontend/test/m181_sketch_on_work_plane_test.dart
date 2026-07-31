// M181 — a sketch on a work plane, by NAMING the plane instead of hitting it.
//
// "I still can't make a sketch on a placed work plane" has now been reported
// four times, and every fix so far went into the 3D tap: M151 built the path,
// M167 taught planePicked the `wp:N` key, M173 added a log line saying which
// surface won. Reading the pick again finds nothing obviously wrong with it —
// which is itself the finding. That tap has to beat a solid face under the
// same pixel and, on an empty part, the three origin planes the command has
// just switched on, and it was the ONLY way in: the browser's work-plane menu
// offered Edit Offset, Hide and Delete and no way to sketch on the thing,
// though that is the FIRST entry in Inventor's.
//
// So the command now exists as a command — it takes the plane as an argument,
// there is nothing to miss — and the tap routes through it. What is pinned
// here is that command, because it is the part that cannot be flaky: no ray,
// no camera, no depth race.
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/widgets/native_browser.dart';

WorkPlane _plane({double offset = 20, String base = 'xy', int seq = 1}) {
  final b = planeFrame(base);
  return WorkPlane('Work Plane$seq', seq, WorkPlaneKind.offset,
      'Offset ${offset.toStringAsFixed(2)} mm from ${base.toUpperCase()}',
      offsetPlaneFrame(b, offset),
      base: b, offset: offset);
}

AppState _partApp({WorkPlane? plane}) {
  final app = AppState();
  final p = PartModel('P');
  if (plane != null) p.workPlanes.add(plane);
  app.parts['P'] = p;
  app.curTab = 'P';
  return app;
}

void main() {
  group('M181 — the command', () {
    test('it creates a child sketch ON the plane and opens it', () {
      final w = _plane();
      final app = _partApp(plane: w);
      final p = app.currentPart!;
      expect(p.childSketches, isEmpty);

      app.startSketchOnWorkPlane(w);

      expect(p.childSketches.length, 1);
      final cs = p.childSketches.single;
      expect(app.activeChild, same(cs.model),
          reason: 'the editor opens on it, like every other sketch route');
      expect(sketchFrameOf(cs).origin, w.frame.origin,
          reason: 'the sketch sits ON the plane, not at the world origin');
      expect(sketchFrameOf(cs).n, w.frame.n);
    });

    test('it is a WORK PLANE sketch, not a face sketch', () {
      // The tap used to store it as a face sketch with a bare frame — a second
      // encoding of one thing, and the reason the two routes could not be
      // reasoned about together. A face sketch also invites the M153/M166
      // face-following pass to move it, and a work plane moves because the
      // USER moves it, not because a solid did.
      final w = _plane();
      final app = _partApp(plane: w);
      app.startSketchOnWorkPlane(w);
      final cs = app.currentPart!.childSketches.single;
      expect(cs.plane, kWorkPlaneKey);
      expect(cs.faceRef, isNull);
      expect(reanchorFaceSketches(app.currentPart!), 0,
          reason: 'nothing may drag a work-plane sketch onto a solid face');
    });

    test('it drops straight into edit mode, ready to draw', () {
      final w = _plane();
      final app = _partApp(plane: w);
      app.startSketchOnWorkPlane(w);
      expect(app.inEditMode, isTrue,
          reason: 'a sketch you cannot draw on is not a sketch');
      expect(app.editingLayer, isNotNull);
      expect(app.current!.layers, contains(app.editingLayer));
    });

    test('it disarms the plane pick and puts the origin planes back', () {
      final w = _plane();
      final app = _partApp(plane: w);
      app.startPartSketch(); // empty part: the three planes come on
      expect(app.pickPlane, isTrue);
      expect(app.currentPart!.vis['xy'], isTrue);

      app.startSketchOnWorkPlane(w);
      expect(app.pickPlane, isFalse);
      expect(app.currentPart!.vis['xy'], isFalse,
          reason: 'planes the command switched on go back off, as after any '
              'other plane pick');
    });

    test('it faces the plane from the side the camera is already on', () {
      // A plane can be faced from either side; taking the far one turns the
      // model around behind you the moment the editor opens.
      final w = _plane(); // XY offset -> normal +Z
      final app = _partApp(plane: w);
      final cam = app.currentPart!.camera;
      cam.az = 0;
      cam.pol = 1.5; // looking from +Z-ish
      app.startSketchOnWorkPlane(w);
      expect(cam.dir.dot(w.frame.n), greaterThan(0),
          reason: 'the camera stayed on the side it was on');
    });

    test('reached from the browser it cancels whatever was armed', () {
      final w = _plane();
      final app = _partApp(plane: w);
      app.startWorkPlane(WorkPlaneKind.midplane); // half-finished command
      expect(app.workPlaneArm, isNotNull);

      app.startSketchOnWorkPlane(w);
      expect(app.workPlaneArm, isNull,
          reason: 'the pick was for a plane definition; the user moved on');
      expect(app.currentPart!.childSketches.length, 1);
    });

    test('a second sketch on the same plane is a second sketch', () {
      final w = _plane();
      final app = _partApp(plane: w);
      app.startSketchOnWorkPlane(w);
      app.finishPartSketch();
      app.startSketchOnWorkPlane(w);
      final p = app.currentPart!;
      expect(p.childSketches.length, 2);
      expect(p.childSketches[0].model.name,
          isNot(p.childSketches[1].model.name));
    });

    test('no part, no crash', () {
      final app = AppState();
      app.startSketchOnWorkPlane(_plane());
      expect(app.activeChild, isNull);
    });
  });

  group('M181 — the route that cannot miss', () {
    List<GlassMenuItem> planeMenu(AppState app) {
      final rows = buildBrowserRows(app, expanded: {kIdOrigin});
      final row = rows.firstWhere((r) => r.id.startsWith(kIdWorkPlane));
      return [for (final g in row.menu) ...g];
    }

    test('the browser offers Create Sketch on a work plane, first', () {
      final w = _plane();
      final app = _partApp(plane: w);
      final items = planeMenu(app);
      expect(items.first.id, 'wpSketch',
          reason: "Inventor's work-plane menu leads with it, and it is the "
              'only route into a sketch that cannot lose a depth race');
      expect([for (final i in items) i.id],
          containsAll(['wpSketch', 'wpOffset', 'wpVis', 'wpDelete']),
          reason: 'nothing that was there before was displaced');
    });

    test('a midplane gets it too, though it has no offset to edit', () {
      final w = WorkPlane('Work Plane1', 1, WorkPlaneKind.midplane,
          'Midplane between XY and XY', planeFrame('xy'));
      final app = _partApp(plane: w);
      final ids = [for (final i in planeMenu(app)) i.id];
      expect(ids, contains('wpSketch'));
      expect(ids, isNot(contains('wpOffset')),
          reason: 'M157: an entry that does nothing is worse than no entry');
    });
  });

  group('M181 — the tap agrees with the command', () {
    test('planePicked on a wp: key goes through the same door', () {
      final w = _plane(seq: 3);
      final app = _partApp(plane: w);
      app.startPartSketch();
      app.planePicked(w.id);
      final cs = app.currentPart!.childSketches.single;
      expect(cs.plane, kWorkPlaneKey);
      expect(sketchFrameOf(cs).origin, w.frame.origin);
      expect(app.activeChild, same(cs.model));
    });

    test('a stale wp: key creates nothing', () {
      final app = _partApp(plane: _plane(seq: 1));
      app.startPartSketch();
      app.planePicked('wp:99');
      expect(app.currentPart!.childSketches, isEmpty);
    });

    test('an origin plane still takes the origin-plane path', () {
      final app = _partApp();
      app.startPartSketch();
      app.planePicked('xy');
      final cs = app.currentPart!.childSketches.single;
      expect(cs.plane, 'xy');
      expect(cs.face, isNull, reason: 'an origin plane needs no stored frame');
    });
  });
}
