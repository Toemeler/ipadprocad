// M258 — the Plane command works out what you meant.
//
// THE REPORT. "wenn ich das ebenen tool benutzt soll es intelligent addieren
// ... wenn ich klicke und ein anderes face anklicke soll es direkt inbetween
// eine ebene machen. wenn ich klicke und ziehe offset wie hier."
//
// The log behind it is three seconds long and says the whole thing: the user
// armed Plane, TAPPED a face, got "drag away to set the offset", re-armed from
// the ribbon, and then dragged. The generic button was Offset in disguise —
// Offset reads its distance from a drag, so a tap had nothing to do and
// cancelled the command outright.
//
// WHAT THIS PINS. Two halves that have to stay two halves:
//
//   * the GESTURE. Press and drag on a face is still an offset plane, still
//     with a live distance, and it never reaches the inference.
//   * the PICKS. A tap is a pick now, and the picks decide which of Inventor's
//     methods was meant — the midplane first, because two parallel faces is
//     what the report asked for and what people reach for most.
//
// and the seam between them: a tap must LEAVE THE COMMAND ARMED. That single
// behaviour is the bug, and the test for it is `a tap does not cancel`.
//
// The inference is a priority table over what a pick can stand in for (see
// _autoPlane), and a table is only worth having if every row is pinned. Each
// row below is one test, including the rows that deliberately REFUSE.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/work_features.dart';
import 'package:prototype/l10n/l.dart';

import 'm56_part_test.dart' show FakeKernel;

WorkRef _pt(String label, double x, double y, double z) =>
    WorkRef.point(label, Vec3(x, y, z));

WorkRef _line(String label, Vec3 a, Vec3 b) => WorkRef.line(label, a, b);

WorkRef _plane(String label, Vec3 at, Vec3 n) => WorkRef.plane(label, at, n);

WorkAttempt<WorkPlaneSolution> _auto(List<WorkRef> refs,
        {double angleDeg = 45}) =>
    solveWorkPlane(WorkPlaneMethod.auto, refs, angleDeg: angleDeg);

WorkPlaneSolution _built(List<WorkRef> refs, {double angleDeg = 45}) {
  final r = _auto(refs, angleDeg: angleDeg);
  expect(r.outcome, WorkPickOutcome.complete,
      reason: 'expected a plane, got: ${r.message}');
  return r.solution!;
}

void _contains(WorkPlaneSolution s, Vec3 p) {
  expect((p - s.at).dot(s.n).abs(), lessThan(1e-9),
      reason: 'the point must lie ON the plane, not near it');
}

AppState _app() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m258_');
  app.partKernel = FakeKernel();
  return app;
}

/// The two faces of a 20 mm block, 20 mm apart on Z. Their normals point AWAY
/// from each other, which is what a real pair of opposite faces does and the
/// case the midplane has to get right.
final _bottom = _plane('Bottom Face', const Vec3(3, -7, 0), const Vec3(0, 0, -1));
final _top = _plane('Top Face', const Vec3(-4, 2, 20), const Vec3(0, 0, 1));

void main() {
  // English, for m223's reason: what is pinned here is which method fired and
  // what it refused, and those sentences are geometry rather than interface.
  setUp(() => L.set(kEn));
  tearDown(() => L.set(kDe));

  // -------------------------------------------------------------------------
  group('M258 — one pick is never enough on its own', () {
    test('a planar face waits, and the prompt names BOTH ways on', () {
      final r = _auto([_top]);
      expect(r.outcome, WorkPickOutcome.needMore);
      // The prompt is the only place the command can teach what it can do.
      expect(r.message.toLowerCase(), contains('parallel'));
      expect(r.message.toLowerCase(), contains('drag'));
    });

    test('an edge waits, and a vertex waits', () {
      expect(_auto([_line('Edge', Vec3.zero, const Vec3(10, 0, 0))]).outcome,
          WorkPickOutcome.needMore);
      expect(_auto([_pt('Vertex', 1, 2, 3)]).outcome, WorkPickOutcome.needMore);
    });

    test('a TORUS answers by itself, as it does for the auto axis', () {
      final s = _built(
          [WorkRef.torus('Toroidal Face', const Vec3(0, 0, 4), const Vec3(0, 0, 1))]);
      expect(s.def, 'Midplane of Toroidal Face');
      expect(s.via, WorkPlaneMethod.midplaneOfTorus);
      expect((s.n - const Vec3(0, 0, 1)).length, lessThan(1e-9));
      _contains(s, const Vec3(0, 0, 4));
    });

    test('a CYLINDER waits rather than guessing a tangent side', () {
      // The three Tangent to Surface methods need the side of the barrel you
      // clicked as well as the picks, and guessing a side is how a plane
      // lands on the far side of the part. The generic command deliberately
      // cannot reach them; the flyout entries can.
      final r = _auto([
        WorkRef.cylinder('Cylindrical Face', Vec3.zero, const Vec3(0, 0, 1),
            radius: 5, hitAt: const Vec3(5, 0, 3)),
      ]);
      expect(r.outcome, WorkPickOutcome.needMore);
    });
  });

  // -------------------------------------------------------------------------
  group('M258 — two parallel faces are the midplane', () {
    test('halfway between them, on the shared normal', () {
      final s = _built([_bottom, _top]);
      expect(s.via, WorkPlaneMethod.auto);
      expect(s.def, 'Midplane between Bottom Face and Top Face');
      // 20 mm apart, so the answer is z = 10 whatever the faces' own reference
      // points were — and those are deliberately off in x and y.
      _contains(s, const Vec3(0, 0, 10));
      _contains(s, const Vec3(50, -50, 10));
      expect(s.n.cross(const Vec3(0, 0, 1)).length, lessThan(1e-9));
    });

    test('the tap order does not change the plane', () {
      final a = _built([_bottom, _top]);
      final b = _built([_top, _bottom]);
      expect((a.at - b.at).length, lessThan(1e-9));
      expect(a.n.cross(b.n).length, lessThan(1e-9));
    });

    test('it agrees to the last digit with the NAMED Midplane command', () {
      // Two entry points, one arithmetic. If these ever disagree, one of the
      // two flyout rows is quietly building a different plane.
      final s = _built([_bottom, _top]);
      final named = midPlaneFrame(
          workPlaneFrameAt(_bottom.planeAt!, _bottom.planeNormal!),
          workPlaneFrameAt(_top.planeAt!, _top.planeNormal!))!;
      expect(named.n.dot(s.at) - named.n.dot(named.origin), closeTo(0, 1e-12));
      expect(s.n.cross(named.n).length, lessThan(1e-12));
    });

    test('two CROSSING faces are refused, and say why', () {
      final r = _auto([_top, _plane('Side Face', Vec3.zero, const Vec3(1, 0, 0))]);
      expect(r.outcome, WorkPickOutcome.rejected);
      expect(r.message.toLowerCase(), contains('parallel'));
    });

    test('two faces on the SAME plane still give that plane back', () {
      // Degenerate but not wrong: the midplane of a plane and itself is it.
      final s = _built([_top, _plane('Other', const Vec3(9, 9, 20), const Vec3(0, 0, 1))]);
      _contains(s, const Vec3(0, 0, 20));
    });
  });

  // -------------------------------------------------------------------------
  group('M258 — the rest of the table', () {
    test('a face and a VERTEX run parallel through it, either order', () {
      final v = _pt('Vertex', 3, 4, 32);
      final s = _built([_top, v]);
      expect(s.via, WorkPlaneMethod.parallelToPlaneThroughPoint);
      _contains(s, const Vec3(3, 4, 32));
      expect(s.n.cross(const Vec3(0, 0, 1)).length, lessThan(1e-9));
      final flipped = _built([v, _top]);
      expect((flipped.at - s.at).length, lessThan(1e-9));
    });

    test('a face and an EDGE IN IT are the angle plane, at the angle given',
        () {
      // The edge runs along X in the z = 20 face, so a 90 deg turn about it
      // stands the plane up: its normal leaves +Z and lands on -Y (or +Y).
      final edge = _line('Edge', const Vec3(-5, 0, 20), const Vec3(5, 0, 20));
      final s = _built([_top, edge], angleDeg: 90);
      expect(s.via, WorkPlaneMethod.angleToPlaneAroundEdge);
      expect(s.n.dot(const Vec3(0, 0, 1)).abs(), lessThan(1e-9),
          reason: 'a quarter turn takes the normal out of Z entirely');
      _contains(s, const Vec3(0, 0, 20));
    });

    test('an EDGE beats its own midpoint — priority, not chance', () {
      // WorkRef.line offers a midpoint too, so this pair satisfies BOTH the
      // angle method and parallel-through-point. The edge is the specific
      // reading and it has to win, or the same two taps would mean different
      // things on different geometry.
      final edge = _line('Edge', const Vec3(-5, 0, 20), const Vec3(5, 0, 20));
      expect(_built([_top, edge], angleDeg: 30).via,
          WorkPlaneMethod.angleToPlaneAroundEdge);
      // ...and a VERTEX, which can only be a point, gets the other one.
      expect(_built([_top, _pt('Vertex', 0, 0, 20)]).via,
          WorkPlaneMethod.parallelToPlaneThroughPoint);
    });

    test('two coplanar edges give the plane they share', () {
      final s = _built([
        _line('Edge1', Vec3.zero, const Vec3(10, 0, 0)),
        _line('Edge2', const Vec3(0, 5, 0), const Vec3(10, 5, 0)),
      ]);
      expect(s.via, WorkPlaneMethod.twoCoplanarEdges);
      expect(s.n.cross(const Vec3(0, 0, 1)).length, lessThan(1e-9));
      _contains(s, Vec3.zero);
    });

    test('an axis and a vertex give the plane the axis pierces', () {
      final s = _built([
        WorkRef.axis('Z Axis', Vec3.zero, const Vec3(0, 0, 1)),
        _pt('Vertex', 1, 2, 7),
      ]);
      expect(s.via, WorkPlaneMethod.normalToAxisThroughPoint);
      expect(s.n.cross(const Vec3(0, 0, 1)).length, lessThan(1e-9));
      _contains(s, const Vec3(1, 2, 7));
    });

    test('three vertices; two of them are not enough yet', () {
      final a = _pt('A', 0, 0, 0), b = _pt('B', 10, 0, 0), c = _pt('C', 0, 10, 0);
      expect(_auto([a, b]).outcome, WorkPickOutcome.needMore);
      final s = _built([a, b, c]);
      expect(s.via, WorkPlaneMethod.threePoints);
      _contains(s, Vec3.zero);
      _contains(s, const Vec3(10, 0, 0));
      _contains(s, const Vec3(0, 10, 0));
    });

    test('a third pick that is not a point is refused, not guessed at', () {
      final r = _auto([_pt('A', 0, 0, 0), _pt('B', 10, 0, 0), _top]);
      expect(r.outcome, WorkPickOutcome.rejected);
    });
  });

  // -------------------------------------------------------------------------
  group('M258 — the command in the app', () {
    test('the generic Plane entry arms the inference, and toggles', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.auto);
      expect(app.workPlaneAutoArmed, isTrue);
      expect(app.pickWorkGeometry, isTrue,
          reason: 'the viewport has to offer geometry while it is armed');
      app.startWorkPlaneMethod(WorkPlaneMethod.auto);
      expect(app.workPlaneAutoArmed, isFalse, reason: 'the same entry cancels');
    });

    test('Esc puts an armed work-feature command down', () async {
      // It had no Esc at all: escape3D knew about the Offset flow and not
      // about the command that replaced it, so the only way out of an armed
      // Axis, Point or Plane was the ribbon entry you came in through.
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.auto);
      expect(app.workFeaturePick(_top), isTrue);
      app.escape3D();
      expect(app.workPlaneAutoArmed, isFalse);
      expect(app.pickWorkGeometry, isFalse);
      expect(app.workFeaturePickCount, 0,
          reason: 'and the half-built selection goes with it');
      expect(app.currentPart!.workPlanes, isEmpty);
    });

    test('Esc reaches an armed work AXIS too, not just the plane', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkAxis(WorkAxisMethod.auto);
      expect(app.pickWorkGeometry, isTrue);
      app.escape3D();
      expect(app.pickWorkGeometry, isFalse);
    });

    test('TAP a face, TAP the opposite face, get the midplane — the report',
        () async {
      final app = _app();
      await app.createNamedPart('P');
      final p = app.currentPart!;
      app.startWorkPlaneMethod(WorkPlaneMethod.auto);

      expect(app.workFeaturePick(_bottom), isTrue);
      expect(p.workPlanes, isEmpty, reason: 'one face is not a plane yet');
      expect(app.workPlaneAutoArmed, isTrue,
          reason: 'the command has to survive the first pick');

      expect(app.workFeaturePick(_top), isTrue);
      expect(p.workPlanes.length, 1);
      final wp = p.workPlanes.single;
      expect(wp.def, 'Midplane between Bottom Face and Top Face');
      expect(wp.frame.origin.dot(const Vec3(0, 0, 1)), closeTo(10, 1e-9));
      expect(wp.kind, WorkPlaneKind.constructed);
      expect(app.workPlaneAutoArmed, isFalse, reason: 'the command is done');
    });

    test('a crossing second face costs that tap and nothing else', () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.auto);
      expect(app.workFeaturePick(_top), isTrue);
      expect(
          app.workFeaturePick(_plane('Side', Vec3.zero, const Vec3(1, 0, 0))),
          isFalse);
      expect(app.workPlaneAutoArmed, isTrue,
          reason: 'still armed — one mis-tap must not end the command');
      // ...and the FIRST pick survived, so the next tap completes it.
      expect(app.workFeaturePick(_bottom), isTrue);
      expect(app.currentPart!.workPlanes.length, 1);
    });

    test('an inferred ANGLE plane keeps its editable number', () async {
      // The kind is read from what the inference RESOLVED to, not from the
      // `auto` the caller armed — otherwise a plane you angled by tapping
      // would have no angle you could re-type.
      final app = _app();
      await app.createNamedPart('P');
      app.workPlaneAngle = 30;
      app.startWorkPlaneMethod(WorkPlaneMethod.auto);
      expect(app.workFeaturePick(_top), isTrue);
      expect(
          app.workFeaturePick(
              _line('Edge', const Vec3(-5, 0, 20), const Vec3(5, 0, 20))),
          isTrue);
      final wp = app.currentPart!.workPlanes.single;
      expect(wp.kind, WorkPlaneKind.angle);
      expect(wp.angleEditable, isTrue,
          reason: 'the one number it has must stay re-typable');
      expect(wp.angle, 30);
    });
  });

  // -------------------------------------------------------------------------
  group('M258 — the gesture half', () {
    PlaneFrame face() => workPlaneFrameAt(const Vec3(0, 0, 20), const Vec3(0, 0, 1));

    test('a tap does NOT cancel the command — the bug itself', () async {
      // The device log: arm, tap, "drag away to set the offset", re-arm from
      // the ribbon, drag. The toast was the command giving up on a press that
      // never moved, which under the inferring command is simply a pick.
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.auto);
      app.beginWorkPlaneCreate(face(), 'face');
      expect(app.wpCreatePreview, isNotNull, reason: 'the preview is live');
      app.commitWorkPlaneCreate(); // released without moving
      expect(app.currentPart!.workPlanes, isEmpty,
          reason: 'a zero-distance offset is never what was meant');
      expect(app.workPlaneAutoArmed, isTrue,
          reason: 'THE FIX: the tap is a pick, so the command stays armed');
      expect(app.wpCreatePreview, isNull, reason: 'but the preview is gone');
    });

    test('a real drag still makes an offset plane, and disarms cleanly',
        () async {
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.auto);
      app.beginWorkPlaneCreate(face(), 'face');
      app.updateWorkPlaneCreate(16.01);
      app.commitWorkPlaneCreate();

      final wp = app.currentPart!.workPlanes.single;
      expect(wp.kind, WorkPlaneKind.offset);
      expect(wp.offset, closeTo(16.01, 1e-9));
      expect(wp.offsetEditable, isTrue);
      expect(wp.frame.origin.dot(const Vec3(0, 0, 1)), closeTo(36.01, 1e-9));
      // Nothing may be left armed or half-picked behind it.
      expect(app.workPlaneAutoArmed, isFalse);
      expect(app.workFeaturePickCount, 0);
    });

    test('the OFFSET command still refuses a tap, exactly as it did', () async {
      // The narrow entry is unchanged: it takes one plane and a distance, and
      // a press that never moved cannot express one.
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlane(WorkPlaneKind.offset);
      app.beginWorkPlaneCreate(face(), 'face');
      app.commitWorkPlaneCreate();
      expect(app.currentPart!.workPlanes, isEmpty);
      expect(app.workPlaneArm, isNull,
          reason: 'Offset alone has nothing else to do with a tap');
    });

    test('a drag after a pending pick still builds the offset', () async {
      // Mixed intent: one face tapped, then a different face dragged. The
      // drag wins and nothing is left over — the alternative is a command
      // that quietly remembers a pick you have visibly moved on from.
      final app = _app();
      await app.createNamedPart('P');
      app.startWorkPlaneMethod(WorkPlaneMethod.auto);
      expect(app.workFeaturePick(_top), isTrue);
      expect(app.workFeaturePickCount, 1);
      app.beginWorkPlaneCreate(face(), 'face');
      app.updateWorkPlaneCreate(5);
      app.commitWorkPlaneCreate();
      expect(app.currentPart!.workPlanes.single.kind, WorkPlaneKind.offset);
      expect(app.workFeaturePickCount, 0);
      expect(app.workPlaneAutoArmed, isFalse);
    });
  });
}
