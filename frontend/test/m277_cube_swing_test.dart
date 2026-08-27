// M277 — the view swings, and Home means home.
//
// "when i change angle with the cube it should always animate smooth not jump."
//
// The ViewCube wrote the camera in one frame. That is disorienting for the
// reason M88 gives about entering a sketch — the model appears at an unrelated
// orientation and you lose track of which side you were on — and a quarter turn
// is the case where it matters most: the front and the back of a symmetric part
// are the same picture, and only the motion between them says which you are on.
//
// The swing itself is an AnimationController and belongs to the widget. What
// can be pinned here is the ARITHMETIC it drives, and the two properties that
// make an interrupted swing behave: a camera can be copied without aliasing,
// and it can be written in place so the viewport, the cube and the renderer
// push all keep turning the same one.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/part_model.dart';

PartCamera _iso() => PartCamera();

void main() {
  group('a camera can be copied and written in place', () {
    test('copy() is independent', () {
      final a = _iso();
      final b = a.copy();
      b.az = 1.5;
      b.pol = 0.2;
      b.roll = 0.7;
      b.halfH = 3;
      b.ox = 9;
      b.oy = -4;
      expect(a.az, _iso().az, reason: 'the original must not have moved');
      expect(a.pol, _iso().pol);
      expect(a.roll, 0);
      expect(a.halfH, 27);
    });

    test('setFrom overwrites all six numbers, in place', () {
      // In place, not by replacement: the camera is owned by the document and
      // referenced by the viewport, the cube and the renderer push. Handing
      // any of them a new instance would leave the others turning the old one.
      final live = _iso();
      final want = PartCamera(
          az: 1.1, pol: 0.4, halfH: 55, ox: 3, oy: -2, roll: 0.9);
      final identity = live; // the SAME object must end up carrying it
      live.setFrom(want);
      expect(identical(identity, live), isTrue);
      expect(live.az, 1.1);
      expect(live.pol, 0.4);
      expect(live.roll, 0.9);
      expect(live.halfH, 55);
      expect(live.ox, 3);
      expect(live.oy, -2);
    });
  });

  group('the swing itself', () {
    test('it starts where it started and lands where it was sent', () {
      final from = _iso();
      final to = _iso()
        ..pol = 0
        ..az = 0;
      expect(PartCamera.lerp(from, to, 0).pol, closeTo(from.pol, 1e-12));
      expect(PartCamera.lerp(from, to, 1).pol, closeTo(to.pol, 1e-12));
    });

    test('a half turn goes the SHORT way round, not most of a circle', () {
      // az comes from atan2, so a pair straddling +/-pi is the common case
      // rather than the exotic one. Plain interpolation would spin the model
      // the long way and read as a glitch rather than as a turn.
      final from = PartCamera(az: 3.0);
      final to = PartCamera(az: -3.0);
      final mid = PartCamera.lerp(from, to, 0.5).az;
      expect(mid.abs(), greaterThan(3.0),
          reason: 'the midpoint is past pi, i.e. it went the short way');
    });

    test('the zoom is interpolated geometrically', () {
      // Zoom is multiplicative. The linear midpoint between 27 and 2700 is
      // 1363, which is visually almost all the way there; the geometric one is
      // 270, which is the true halfway.
      final mid =
          PartCamera.lerp(PartCamera(halfH: 27), PartCamera(halfH: 2700), 0.5);
      expect(mid.halfH, closeTo(270, 1e-6));
    });

    test('an interrupted swing restarts from what is on screen', () {
      // The cube writes into the LIVE camera every tick, so a second tap can
      // simply copy it. This is that property, expressed as arithmetic: the
      // state at t is a valid starting camera for the next swing.
      final from = _iso();
      final to = PartCamera(az: 0, pol: 0, halfH: 27);
      final caught = PartCamera.lerp(from, to, 0.37);
      final rest = PartCamera.lerp(caught, to, 1);
      expect(rest.az, closeTo(to.az, 1e-9));
      expect(rest.pol, closeTo(to.pol, 1e-9));
      expect(rest.halfH, closeTo(to.halfH, 1e-9));
    });
  });

  group('Home is a home VIEW', () {
    test('it resets the roll as well as the orbit', () {
      // M277 — roll arrived in M80 for sketch cameras, which are built rather
      // than navigated, so nothing the user could reach ever set it. The
      // ViewCube's roll arrows are the first control that puts a roll on an
      // ordinary view, and a Home that leaves the model lying on its side is
      // not a home view.
      final c = PartCamera(az: 2, pol: 2, halfH: 900, ox: 40, oy: -12)
        ..roll = math.pi / 2;
      c.home();
      expect(c.roll, 0);
      expect(c.az, closeTo(math.pi / 4, 1e-12));
      expect(c.pol, closeTo(0.955, 1e-12));
      expect(c.halfH, 27);
      expect(c.ox, 0);
      expect(c.oy, 0);
    });
  });
}
