// M399 — #28: "i changed which view is the front view but if i then want a
// top left corner view it still rotates the object like the old front view
// would and now its the wrong orientation."
//
// [cubePick] has always answered in world space with the document's cube
// orientation applied, so a tap on the cube sent the camera to the right
// PLACE. The roll did not follow. The snap finished with
//
//     c.setBasis(d, PartCamera.rightFor(c.az))
//
// and `rightFor` is `(cos az, 0, -sin az)` — a vector in the world XZ plane,
// which is to say "world +Y is up". After "Set Current View as Front" the
// model's own up is somewhere else, so every view off the cube came out
// rolled by the angle between the two: the right view of the wrong thing.
//
// Home was worse: `PartCamera.home()` writes az = pi/4, pol = 0.955, which is
// the front-top-right corner spelled in WORLD angles, so it went to a corner
// of nothing in particular.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/quat.dart';
import 'package:prototype/view_cube.dart';

/// The camera a tap in [dirWorld] produces, built the way _snapTo builds it.
PartCamera cameraFor(Vec3 dirWorld, Quat orient) {
  final c = PartCamera();
  final (d, r) = cubeViewBasis(dirWorld, orient);
  c.setBasis(d, r);
  return c;
}

void near(Vec3 a, Vec3 b, {String? reason, double tol = 1e-6}) {
  expect((a - b).length, lessThan(tol),
      reason: '${reason ?? ''} expected $b, got $a');
}

/// A quarter turn about world X: "front" becomes what used to be the top.
final tipped = Quat.axisAngle(const Vec3(1, 0, 0), math.pi / 2);

void main() {
  group('with front where it has always been', () {
    test('the up vector is the cube\'s own +Y', () {
      near(cameraFor(const Vec3(0, 0, 1), Quat.identity).up,
          const Vec3(0, 1, 0));
      near(cameraFor(const Vec3(1, 0, 0), Quat.identity).up,
          const Vec3(0, 1, 0));
    });

    test('a corner view keeps world up, exactly as it did', () {
      // The old code's answer for this case, reproduced: setBasis with
      // rightFor(az). Nothing about the identity orientation may change.
      final d = const Vec3(1, 1, 1).normalized();
      final old = PartCamera()
        ..az = math.atan2(d.x, d.z)
        ..setBasis(d, PartCamera.rightFor(math.atan2(d.x, d.z)));
      final now = cameraFor(d, Quat.identity);
      near(now.dir, old.dir, reason: 'direction');
      near(now.up, old.up, reason: 'up');
      expect(now.roll, closeTo(old.roll, 1e-9));
    });

    test('looking straight down, the front of the model is at the bottom', () {
      // Inventor's convention, and the one cubeOrientTop already documents.
      // Screen-up is -FRONT, so the front edge is nearest the viewer.
      near(cameraFor(const Vec3(0, 1, 0), Quat.identity).up,
          const Vec3(0, 0, -1));
      near(cameraFor(const Vec3(0, -1, 0), Quat.identity).up,
          const Vec3(0, 0, 1));
    });
  });

  group('after front has been redefined', () {
    test('up follows the model, not the world', () {
      // `tipped` turns cube +Y onto world -Z... so the model's own up is now
      // world -Z, and that is what must be up the screen.
      final upWorld = tipped.rotate(const Vec3(0, 1, 0));
      // The cube's FRONT is now world +Y; a tap on it looks from there.
      final dir = tipped.rotate(const Vec3(0, 0, 1));
      near(cameraFor(dir, tipped).up, upWorld,
          reason: 'the front view of a tipped model');
    });

    test('THE REPORT: a corner view is the model\'s corner, not the world\'s',
        () {
      // Top-left-front, in cube terms.
      const corner = Vec3(-1, 1, 1);
      final dirWorld = tipped.rotate(corner).normalized();
      final cam = cameraFor(dirWorld, tipped);

      // The camera looks from the model's own top-left-front corner...
      near(cam.dir, dirWorld, reason: 'direction');
      // ...and the model's up axis projects to the upper half of the screen,
      // which is the whole of "now its the wrong orientation".
      final modelUp = tipped.rotate(const Vec3(0, 1, 0));
      expect(cam.up.dot(modelUp), greaterThan(0.5),
          reason: 'the model must not be lying on its side');

      // What the old code did, for the record: world up, which for this
      // orientation is the model's own FRONT — a quarter turn out.
      final az = math.atan2(dirWorld.x, dirWorld.z);
      final was = PartCamera()..setBasis(dirWorld, PartCamera.rightFor(az));
      expect(was.up.dot(modelUp), lessThan(0.5),
          reason: 'the bug, pinned so the fix cannot be undone quietly');
    });

    test('every cube cell comes out with the model upright', () {
      // All 26: six faces, twelve edges, eight corners.
      for (var x = -1; x <= 1; x++) {
        for (var y = -1; y <= 1; y++) {
          for (var z = -1; z <= 1; z++) {
            if (x == 0 && y == 0 && z == 0) continue;
            final cube = Vec3(x.toDouble(), y.toDouble(), z.toDouble());
            final d = cube.normalized();
            final cam = cameraFor(tipped.rotate(d), tipped);
            final upCube = tipped.conjugate.rotate(cam.up);
            // Screen-up, brought back into cube space, is the cube's own +Y
            // with the along-view part removed — a corner view cannot show
            // +Y exactly upright, and setBasis orthogonalises. For the two
            // views along the Y axis, where +Y says nothing at all, it is the
            // documented -FRONT / +FRONT instead.
            final want = cubeUpFor(d);
            final flat = (want - d * want.dot(d)).normalized();
            near(upCube, flat, tol: 1e-6, reason: 'cell ($x,$y,$z)');
          }
        }
      }
    });

    test('Home goes to the model\'s front-top-right, not the world\'s', () {
      final cam = cameraFor(tipped.rotate(kCubeHomeDir), tipped);
      near(tipped.conjugate.rotate(cam.dir),
          kCubeHomeDir.normalized(), reason: 'the cube\'s own corner');
      // And the untouched case still lands where PartCamera.home() puts it.
      final plain = cameraFor(kCubeHomeDir, Quat.identity);
      final home = PartCamera()..home();
      near(plain.dir, home.dir, tol: 1e-3, reason: 'az=pi/4, pol=0.955');
      expect(plain.roll, closeTo(0, 1e-9));
    });
  });
}
