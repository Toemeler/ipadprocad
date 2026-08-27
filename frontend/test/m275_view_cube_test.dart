// M275 — the ViewCube, made to agree with itself.
//
// "das highlight wenn ich darüber hovere funktioniert nur sehr schlecht. wenn
// ich eine ansicht anklicke und von einer seite schaue möchte ich pfeile haben
// wie in inventor um das objekt und die ansicht zu drehen. ich möchte die
// möglichkeit haben die aktuelle ansicht als front oder top zu definieren."
//
// The highlight was unreliable for two reasons, and only one of them was about
// drawing:
//
//   1. THE PICK USED THE LIVE CAMERA. `unprojectOnCamPlane` adds the pan in
//      world millimetres, and scaling the result to the cube's half-height
//      scales the pan with it: a view panned 50 mm at halfH 27 put the hit ray
//      1.6 cube widths off the cube. The further you panned the worse it got,
//      which is exactly what "works only very badly" looks like from the
//      outside. The roll went the other way — picked but never drawn.
//   2. AN EDGE LIT TWO WHOLE FACES. The lit set held face normals and the
//      painter filled any face whose normal was in it, so hovering near a
//      boundary flooded half the cube.
//
// These tests pin the fix at the seam: one camera for both, and a highlight
// that is the picked CELL.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/quat.dart';
import 'package:prototype/view_cube.dart';

const double _size = 84;

/// Where the cube actually lands on an 84 px canvas, head-on.
///
/// The unit cube spans -0.5..0.5 against the canvas's half-height of
/// [kCubeHalfH], so its silhouette runs 17.6..66.4 px and the outer band
/// starts at 55.7. Written out rather than guessed at with a fraction of the
/// canvas: 0.93 of it is off the cube entirely, which is a null pick and a
/// test that fails for the wrong reason.
const double _bandNear = 61; // inside the +u band, inside the silhouette
const double _bandFar = 23; // the same on the way up the screen

/// Straight at the FRONT face.
PartCamera _front() => PartCamera(az: 0, pol: math.pi / 2, halfH: 27);

/// The default three-quarter view.
PartCamera _iso() => PartCamera();

CubeHit _pickCentre(PartCamera c, {Quat orient = Quat.identity}) =>
    cubePick(c, const Offset(_size / 2, _size / 2), _size, orient: orient)!;

void main() {
  group('the pick uses the cube\'s own camera, not the document\'s', () {
    test('PANNING the view does not move the cube', () {
      // The bug, in one assertion. A pan is a property of the document's
      // camera and has nothing to do with a control pinned to the corner of
      // the screen.
      final a = _pickCentre(_front());
      final panned = _front()
        ..ox = 50
        ..oy = -37;
      final b = _pickCentre(panned);
      expect(b.axes.length, a.axes.length);
      expect(b.dir.x, closeTo(a.dir.x, 1e-9));
      expect(b.dir.y, closeTo(a.dir.y, 1e-9));
      expect(b.dir.z, closeTo(a.dir.z, 1e-9));
    });

    test('ZOOMING does not either', () {
      for (final h in [1.0, 27.0, 5000.0]) {
        final c = _front()..halfH = h;
        expect(_pickCentre(c).faceLabel, 'FRONT', reason: 'halfH $h');
      }
    });

    test('cubeCamera keeps the orientation and drops the rest', () {
      final c = PartCamera(az: 0.7, pol: 1.2, roll: 0.3, halfH: 900)
        ..ox = 12
        ..oy = -4;
      final cc = cubeCamera(c);
      expect(cc.az, c.az);
      expect(cc.pol, c.pol);
      expect(cc.roll, c.roll, reason: 'the cube must roll with the model');
      expect(cc.halfH, kCubeHalfH);
      expect(cc.ox, 0);
      expect(cc.oy, 0);
    });
  });

  group('what the pointer is over', () {
    test('the middle of the cube is the face you are looking at', () {
      expect(_pickCentre(_front()).faceLabel, 'FRONT');
      expect(_pickCentre(_front()).isFace, isTrue);
      final top = PartCamera(az: 0, pol: 0, halfH: 27);
      expect(_pickCentre(top).faceLabel, 'TOP');
    });

    test('a corner of a face-on cube is a CORNER, three axes deep', () {
      // Head-on, the cube fills a square centred in the canvas; its top-right
      // corner region is up and right of centre by more than the band.
      final r = cubePick(_front(), const Offset(_bandNear, _bandFar),
          _size)!;
      expect(r.isCorner, isTrue, reason: 'axes were ${r.axes.length}');
      expect(r.faceLabel, isNull);
    });

    test('an edge is two axes, and its direction is the diagonal', () {
      final r =
          cubePick(_front(), const Offset(_bandNear, _size / 2), _size)!;
      expect(r.isEdge, isTrue);
      // FRONT + RIGHT, normalised.
      expect(r.dir.x, closeTo(1 / math.sqrt2, 1e-6));
      expect(r.dir.z, closeTo(1 / math.sqrt2, 1e-6));
      expect(r.dir.y, closeTo(0, 1e-6));
    });

    test('a miss is a miss', () {
      expect(cubePick(_front(), const Offset(-40, -40), _size), isNull);
      expect(cubePick(_front(), const Offset(200, 200), _size), isNull);
    });
  });

  group('the highlight is the CELL, not the face', () {
    test('a face hit lights the middle cell of that face only', () {
      final hit = _pickCentre(_front());
      expect(cubeCell(hit, const Vec3(0, 0, 1)), (0, 0));
      // ...and nothing on the faces beside it. This is the assertion the old
      // painter would have failed: an edge lit whole neighbours.
      expect(cubeCell(hit, const Vec3(1, 0, 0)), isNull);
      expect(cubeCell(hit, const Vec3(0, 1, 0)), isNull);
    });

    test('an edge hit lights a STRIP on each of its two faces', () {
      final r =
          cubePick(_front(), const Offset(_bandNear, _size / 2), _size)!;
      // On FRONT: the strip at the +u end, spanning v.
      final onFront = cubeCell(r, const Vec3(0, 0, 1))!;
      expect(onFront.$2, 0, reason: 'a strip spans its face in v');
      expect(onFront.$1.abs(), 1, reason: 'and sits at one end in u');
      // On RIGHT: the corresponding strip, so the two fold into one edge.
      final onRight = cubeCell(r, const Vec3(1, 0, 0))!;
      expect(onRight.$1.abs() + onRight.$2.abs(), 1);
      // And nowhere else.
      expect(cubeCell(r, const Vec3(0, 1, 0)), isNull);
      expect(cubeCell(r, const Vec3(0, -1, 0)), isNull);
    });

    test('a corner hit lights a square on each of its three faces', () {
      final r = cubePick(_front(), const Offset(_bandNear, _bandFar),
          _size)!;
      var lit = 0;
      for (final (_, n) in kCubeFaces) {
        final cell = cubeCell(r, n);
        if (cell == null) continue;
        lit++;
        expect(cell.$1.abs(), 1, reason: 'a corner is at an end in both axes');
        expect(cell.$2.abs(), 1);
      }
      expect(lit, 3);
    });

    test('the cell rectangles tile the face and match the pick band', () {
      // The one number the picker and the painter must share. If these drift,
      // the region that lights up is not the region that was hit.
      expect(cubeCellRect(-1, 0).$1, -0.5);
      expect(cubeCellRect(-1, 0).$2, -kCubeBand);
      expect(cubeCellRect(0, 0).$1, -kCubeBand);
      expect(cubeCellRect(0, 0).$2, kCubeBand);
      expect(cubeCellRect(1, 0).$1, kCubeBand);
      expect(cubeCellRect(1, 0).$2, 0.5);
    });
  });

  group('redefining which way is front', () {
    void expectSnapsTo(PartCamera c, Quat orient, Vec3 cubeNormal) {
      // Picking the middle of the cube in the redefined orientation must send
      // the camera back to exactly where it is now.
      final hit = _pickCentre(c, orient: orient);
      expect(hit.dir.x, closeTo(c.dir.x, 1e-6));
      expect(hit.dir.y, closeTo(c.dir.y, 1e-6));
      expect(hit.dir.z, closeTo(c.dir.z, 1e-6));
      // ...and the face under the pointer is the one that was named.
      final n = hit.axes.single;
      expect(n.dot(cubeNormal), closeTo(1, 1e-6));
    }

    test('"as Front" makes the current view the FRONT face', () {
      final c = _iso();
      expectSnapsTo(c, cubeOrientFront(c), const Vec3(0, 0, 1));
    });

    test('"as Top" makes the current view the TOP face', () {
      final c = _iso();
      expectSnapsTo(c, cubeOrientTop(c), const Vec3(0, 1, 0));
    });

    test('it keeps the roll: what is up now stays up', () {
      // The subtlety the second fromTo exists for. Aligning the normal alone
      // leaves the cube free to spin about the view direction, and a redefined
      // front that lands rolled at a random angle is worse than none.
      final c = _iso();
      final q = cubeOrientFront(c);
      final cubeUpInWorld = q.rotate(const Vec3(0, 1, 0));
      final up = c.up;
      expect(cubeUpInWorld.x, closeTo(up.x, 1e-6));
      expect(cubeUpInWorld.y, closeTo(up.y, 1e-6));
      expect(cubeUpInWorld.z, closeTo(up.z, 1e-6));
    });

    test('"as Top" puts FRONT at the bottom of the screen, as Inventor does', () {
      // Looking down at the top of a model, its front is nearest the viewer,
      // i.e. DOWN the screen. Getting this wrong gives a cube whose FRONT is
      // behind you the moment you leave the top view.
      final c = _iso();
      final q = cubeOrientTop(c);
      final frontInWorld = q.rotate(const Vec3(0, 0, 1));
      expect(frontInWorld.dot(c.up), closeTo(-1, 1e-6));
    });

    test('a redefined front round-trips through a part document', () {
      final p = PartModel('P')..cubeOrient = cubeOrientTop(_iso());
      expect(p.toJson().containsKey('cube'), isTrue);
      final back = PartModel('P')..loadJson(p.toJson());
      expect(back.cubeOrient.rotate(const Vec3(0, 1, 0)).y,
          closeTo(p.cubeOrient.rotate(const Vec3(0, 1, 0)).y, 1e-9));
    });

    test('a document nobody redefined writes nothing extra', () {
      expect(PartModel('P').toJson().containsKey('cube'), isFalse);
      expect(PartModel('P').cubeOrient.isIdentity, isTrue);
    });

    test('identity orientation leaves every pick exactly as it was', () {
      // The whole feature has to be free when it is not used.
      final c = _iso();
      final a = _pickCentre(c);
      final b = _pickCentre(c, orient: Quat.identity);
      expect(b.dir.x, closeTo(a.dir.x, 1e-12));
      expect(b.dir.y, closeTo(a.dir.y, 1e-12));
      expect(b.dir.z, closeTo(a.dir.z, 1e-12));
    });
  });
}
