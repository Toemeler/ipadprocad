// M151 — work planes: offset from a plane or face, and midplane between two
// planes or faces (M401: parallel, or crossing — then the bisector).
//
// The geometry is pure and is the part that can be quietly wrong: an offset
// that rotates its sketch axes, a midplane that lands on one of its parents,
// a non-parallel pair that silently produces something plausible. All of that
// is pinned here. The pick flow is tested through AppState because the two
// entry points (an origin plane and a solid face) must be interchangeable —
// by the time they arrive they are both just a PlaneFrame.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('ipc_m151');
  final p = PartModel('P');
  app.parts['P'] = p;
  app.openTabs.add('P');
  app.curTab = 'P';
  return app;
}

const eps = 1e-9;

void main() {
  group('offset geometry', () {
    test('moves along the normal and keeps the sketch axes', () {
      final base = planeFrame('xy');
      final o = offsetPlaneFrame(base, 10);
      expect(o.origin.z, closeTo(10, eps));
      expect(o.origin.x, closeTo(0, eps));
      // The axes MUST be inherited: a sketch on the offset plane has to come
      // out oriented like one on the base, or every dimension on it is turned.
      expect(o.u.x, base.u.x);
      expect(o.v.y, base.v.y);
      expect(o.n.z, base.n.z);
    });

    test('a negative distance goes the other way', () {
      // This is why the value is signed and there is no Flip button.
      expect(offsetPlaneFrame(planeFrame('xy'), -4).origin.z, closeTo(-4, eps));
    });

    test('offsets from an already-offset plane compose', () {
      final a = offsetPlaneFrame(planeFrame('xy'), 10);
      expect(offsetPlaneFrame(a, 5).origin.z, closeTo(15, eps));
    });

    test('it offsets along the plane\'s own normal, not global Z', () {
      final o = offsetPlaneFrame(planeFrame('yz'), 7);
      expect(o.origin.x, closeTo(7, eps));
      expect(o.origin.z, closeTo(0, eps));
    });
  });

  group('midplane geometry', () {
    test('lands halfway between two parallel planes', () {
      final a = planeFrame('xy');
      final b = offsetPlaneFrame(a, 20);
      final m = midPlaneFrame(a, b)!;
      expect(m.origin.z, closeTo(10, eps));
    });

    test('anti-parallel normals still count as parallel', () {
      // Two opposite faces of a block are the commonest input there is, and
      // their normals point away from each other.
      final a = planeFrame('xy');
      final flipped = PlaneFrame(
          kWorkPlaneKey, a.u, a.v, a.n * -1, a.origin + a.n * 20);
      final m = midPlaneFrame(a, flipped);
      expect(m, isNotNull);
      expect(m!.origin.z, closeTo(10, eps));
    });

    test('crossing input gives the bisector through their shared line', () {
      // M401 — this used to assert `isNull`, on the reasoning that "an angled
      // bisector is a different feature". #27 disagreed, and was right: it is
      // the same feature — the points equidistant from both faces — evaluated
      // where the faces meet. A chamfer pair is the commonest angled input.
      final m = midPlaneFrame(planeFrame('xy'), planeFrame('yz'))!;
      // xy is z=0, yz is x=0; they share the y axis, and every point of the
      // bisector is as far from one as from the other.
      for (final t in [-8.0, 0.0, 13.0]) {
        expect(m.n.dot(Vec3(0, t, 0) - m.origin).abs(), lessThan(eps),
            reason: 'the shared line must lie in it');
      }
      for (final p in [m.origin, m.origin + m.u * 6, m.origin + m.v * -4]) {
        expect(p.z, closeTo(p.x, eps),
            reason: 'equidistant from z=0 and x=0, at $p');
      }
    });

    test('two coincident planes give back the same plane', () {
      final a = planeFrame('xz');
      expect(midPlaneFrame(a, a)!.origin.y, closeTo(0, eps));
    });
  });

  group('creation flow', () {
    test('offset needs one pick and commits immediately', () {
      final app = makeApp();
      app.workPlaneOffset = 12;
      app.startWorkPlane(WorkPlaneKind.offset);
      expect(app.pickPlane, isTrue, reason: 'the viewport must be armed');

      app.planePicked('xy');
      final p = app.currentPart!;
      expect(p.workPlanes.length, 1);
      expect(p.workPlanes.first.frame.origin.z, closeTo(12, eps));
      expect(app.workPlaneArm, isNull, reason: 'the flow disarms itself');
      expect(app.pickPlane, isFalse);
    });

    test('midplane waits for the second pick', () {
      final app = makeApp();
      app.startWorkPlane(WorkPlaneKind.midplane);
      app.planePicked('xy');
      expect(app.currentPart!.workPlanes, isEmpty);
      expect(app.workPlaneArm, isNotNull, reason: 'still collecting');

      app.facePicked(offsetPlaneFrame(planeFrame('xy'), 30));
      expect(app.currentPart!.workPlanes.length, 1);
      expect(app.currentPart!.workPlanes.first.frame.origin.z, closeTo(15, eps));
    });

    test('a crossing second pick builds the bisector', () {
      // M401 — this used to assert the pick was REJECTED and the flow left
      // armed. #27: "it should just make a middle plane like it would with
      // parallel faces", and it does.
      final app = makeApp();
      app.startWorkPlane(WorkPlaneKind.midplane);
      app.planePicked('xy');
      app.planePicked('yz');
      final planes = app.currentPart!.workPlanes;
      expect(planes.length, 1, reason: 'the two faces do define a midplane');
      // Equidistant from z=0 and x=0: the plane x=z.
      final f = planes.first.frame;
      for (final q in [f.origin, f.origin + f.u * 5, f.origin + f.v * -3]) {
        expect(q.z, closeTo(q.x, eps), reason: 'at $q');
      }
      expect(app.workPlaneArm, isNull, reason: 'and the flow is done');
    });

    test('a second pick that defines nothing still keeps the flow alive', () {
      // The recovery path M151 built is still there — it just has almost
      // nothing left that can reach it, now that crossing planes are an
      // answer rather than an error. Picking the SAME plane twice is a
      // midplane of one thing, which is that plane; picking a second one
      // always resolves. So this asserts the survivable shape rather than
      // inventing an impossible input: after a first pick the command waits,
      // and cancelling leaves the part untouched.
      final app = makeApp();
      app.startWorkPlane(WorkPlaneKind.midplane);
      app.planePicked('xy');
      expect(app.currentPart!.workPlanes, isEmpty);
      expect(app.workPlaneArm, WorkPlaneKind.midplane,
          reason: 'still collecting');
      app.cancelWorkPlane();
      expect(app.currentPart!.workPlanes, isEmpty);
      expect(app.workPlaneArm, isNull);
    });

    test('a face and an origin plane are interchangeable inputs', () {
      final app = makeApp();
      app.workPlaneOffset = 5;
      app.startWorkPlane(WorkPlaneKind.offset);
      app.facePicked(planeFrame('xz'));
      expect(app.currentPart!.workPlanes.length, 1);
      expect(app.currentPart!.workPlanes.first.frame.origin.y, closeTo(5, eps));
    });

    test('arming the same kind twice cancels', () {
      final app = makeApp();
      app.startWorkPlane(WorkPlaneKind.offset);
      app.startWorkPlane(WorkPlaneKind.offset);
      expect(app.workPlaneArm, isNull);
      expect(app.pickPlane, isFalse);
    });

    test('an armed flow does NOT create a sketch', () {
      // The regression that matters: planePicked used to mean "start a
      // sketch", and the work plane flow reuses that entry point.
      final app = makeApp();
      app.startWorkPlane(WorkPlaneKind.offset);
      app.planePicked('xy');
      expect(app.currentPart!.childSketches, isEmpty);
    });
  });

  group('persistence', () {
    test('work planes survive a round trip', () {
      final p = PartModel('P');
      p.workPlanes.add(WorkPlane('Work Plane1', 3, WorkPlaneKind.offset,
          'Offset 10.00 mm from XY', offsetPlaneFrame(planeFrame('xy'), 10)));
      final back = PartModel('P')..loadJson(p.toJson());
      expect(back.workPlanes.length, 1);
      expect(back.workPlanes.first.name, 'Work Plane1');
      expect(back.workPlanes.first.frame.origin.z, closeTo(10, eps));
      expect(back.workPlanes.first.id, 'wp:3');
    });

    test('a part with no work planes writes no key at all', () {
      // An untouched part's file must stay byte-identical to what it was
      // before this milestone existed.
      expect(PartModel('P').toJson().containsKey('workPlanes'), isFalse);
    });

    test('a corrupt entry is dropped, not fatal', () {
      final back = PartModel('P')
        ..loadJson({
          'workPlanes': [
            {'name': 'bad'}, // no vectors
          ]
        });
      expect(back.workPlanes, isEmpty);
    });
  });

  group('picking', () {
    test('a work plane is addressable by key like an origin plane', () {
      final p = PartModel('P');
      final wp = WorkPlane('Work Plane1', 7, WorkPlaneKind.offset, '',
          offsetPlaneFrame(planeFrame('xy'), 10));
      p.workPlanes.add(wp);
      expect(frameForPlaneKey(p, 'wp:7')!.origin.z, closeTo(10, eps));
      expect(frameForPlaneKey(p, 'xy')!.origin.z, closeTo(0, eps));
      expect(frameForPlaneKey(p, 'wp:99'), isNull);
    });
  });
}
