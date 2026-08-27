// M283 — mouse navigation.
//
//   "scroll to zoom is not smooth its in steps when using the mouse wheel ...
//    shift and middle mouse click is orbit and only middle mouse click is pan
//    ... the mouse also seems to always make a step back when i let go. and it
//    should be smoothed ... the cube on the top right when i click on a
//    viewing direction the zoom should also animate so that the whole model is
//    visible"
//
// Four complaints with one cause: every navigation gesture in this app was
// written for a finger, a Pencil or a trackpad, and the mouse got what fell
// out of that. The wheel zoomed a fixed step per EVENT and discarded how far
// it had actually turned; the middle button orbited (pan needed shift with it)
// where Inventor pans; a middle-button drag was fought over by the raw
// [Listener] and the [ScaleGestureRecognizer], which both wrote the same
// anchor field; and the ViewCube set a flat halfH = 27 on every view it sent
// the camera to, which frames a model of exactly one size.
//
// The wheel's DIRECTION is not in here on purpose — that is the system's own
// scroll-direction setting and not the app's to invert.
//
// These tests pin [mouse_nav.dart], which the part, assembly and sketch
// viewports all call so that a mouse means the same thing in all three, and
// [fitPartView], which is what the cube now frames a view with.
import 'dart:math' as math;

import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ffi/occt_engine.dart' show OcctMeshData;
import 'package:prototype/mouse_nav.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';

/// Runs [z] to completion at 60 Hz and returns the total half-height factor,
/// plus the largest single frame's factor — the number that says whether it
/// glided or jumped.
({double total, double biggestStep, int frames}) _glide(WheelZoom z,
    {double dt = 1 / 60, int limit = 600}) {
  var total = 1.0, biggest = 1.0;
  var frames = 0;
  while (z.active && frames < limit) {
    final f = z.takeHalfHeightFactor(dt);
    total *= f;
    final step = f < 1 ? 1 / f : f;
    if (step > biggest) biggest = step;
    frames++;
  }
  return (total: total, biggestStep: biggest, frames: frames);
}

void main() {
  group('the wheel is proportional, not stepped', () {
    // The old code zoomed exactly 1.1x however far the wheel had turned. This
    // is the difference: twice the travel is twice the zoom, in doublings.
    test('twice the travel is twice the zoom', () {
      final a = wheelDoublings(-60);
      final b = wheelDoublings(-120);
      expect(b, closeTo(2 * a, 1e-12));
    });

    test('a small delta is a small zoom, not a whole step', () {
      final z = WheelZoom()
        ..add(wheelDoublings(-6), Offset.zero);
      final g = _glide(z);
      // 6 px of travel: well under a percent, where the old code would have
      // taken the full 10% step for it.
      expect(1 - g.total, lessThan(0.02));
      expect(1 - g.total, greaterThan(0));
    });

    test('a notch is a sane amount of zoom', () {
      final z = WheelZoom()
        ..add(wheelDoublings(-120), Offset.zero);
      final g = _glide(z);
      expect(g.total, closeTo(math.pow(0.5, 120 / kWheelPixelsPerDoubling), 1e-6));
      expect(g.total, greaterThan(0.5)); // never more than a halving per notch
      expect(g.total, lessThan(1.0)); // and it did zoom in
    });
  });

  group('the zoom glides in instead of jumping', () {
    test('a notch takes several frames and no frame carries most of it', () {
      final z = WheelZoom()
        ..add(wheelDoublings(-120), Offset.zero);
      final g = _glide(z);
      expect(g.frames, greaterThan(3), reason: 'a jump is one frame');
      // The largest single frame is a small fraction of the whole movement.
      expect(g.biggestStep, lessThan(1.15));
    });

    test('what glides in is exactly what was asked for', () {
      // Nothing is lost or gained on the way: the sum of the frames is the
      // zoom the wheel asked for, so the model does not drift.
      for (final d in [0.25, 1.0, -0.5, -2.0]) {
        final z = WheelZoom()..add(d, Offset.zero);
        expect(_glide(z).total, closeTo(math.pow(0.5, d).toDouble(), 1e-6),
            reason: '$d doublings');
      }
    });

    test('scrolling again mid-glide adds instead of restarting', () {
      final z = WheelZoom()..add(0.5, Offset.zero);
      z.takeHalfHeightFactor(1 / 60); // part-way through
      final soFar = 0.5 - z.owed;
      z.add(0.5, Offset.zero);
      expect(z.owed, closeTo(1.0 - soFar, 1e-12));
    });

    test('a violent flick is capped', () {
      final z = WheelZoom()
        ..add(wheelDoublings(-20000), Offset.zero);
      expect(z.owed, kWheelMaxDoublings);
      expect(_glide(z).total,
          closeTo(math.pow(0.5, kWheelMaxDoublings).toDouble(), 1e-6));
    });

    test('a frame after a stall does not pay the whole glide at once', () {
      // A kernel call or a file read can leave a two-second gap between
      // frames. Un-clamped, that frame lands the entire zoom in one step —
      // the jump this exists to remove.
      final z = WheelZoom()..add(3.0, Offset.zero);
      final f = z.takeHalfHeightFactor(2.0);
      // The clamp caps a frame at 50 ms of glide, so whatever the gap was,
      // nearly half of the pending zoom is still ahead of us.
      expect(z.active, isTrue);
      expect(z.owed, greaterThan(3.0 * 0.4));
      expect(f, greaterThan(math.pow(0.5, 3.0).toDouble()));
    });

    test('a frame with no time in it does nothing', () {
      final z = WheelZoom()..add(1.0, Offset.zero);
      expect(z.takeHalfHeightFactor(0), 1.0);
      expect(z.takeHalfHeightFactor(-1), 1.0);
      expect(z.takeHalfHeightFactor(double.nan), 1.0);
      expect(z.owed, 1.0);
    });

    test('an idle zoomer costs nothing', () {
      final z = WheelZoom();
      expect(z.active, isFalse);
      expect(z.takeHalfHeightFactor(1 / 60), 1.0);
    });

    test('a drag or a gesture cancels what is still owed', () {
      final z = WheelZoom()..add(2.0, const Offset(10, 10));
      z.cancel();
      expect(z.active, isFalse);
      expect(z.takeHalfHeightFactor(1 / 60), 1.0);
    });

    test('the anchor is the last one the wheel named', () {
      final z = WheelZoom()..add(0.2, const Offset(3, 4));
      expect(z.focus, const Offset(3, 4));
      z.add(0.2, const Offset(9, 9));
      expect(z.focus, const Offset(9, 9));
    });

    test('the sketch camera gets the same glide, the other way up', () {
      // The 2D canvas stores a zoom SCALE, not a half-height, so its factors
      // are the reciprocals — greater than 1 zooms in.
      final a = WheelZoom()..add(1.0, Offset.zero);
      final b = WheelZoom()..add(1.0, Offset.zero);
      expect(b.takeZoomFactor(1 / 60),
          closeTo(1 / a.takeHalfHeightFactor(1 / 60), 1e-12));
    });
  });

  group('the middle button pans, shift with it orbits', () {
    const mouse = PointerDeviceKind.mouse;

    // Inventor's binding, and the exact inverse of what this app did: the
    // middle button used to ORBIT and shift+middle used to pan.
    test('the middle button alone pans', () {
      expect(mouseDrag(mouse, kMiddleMouseButton, shift: false), MouseDrag.pan);
    });

    test('shift with the middle button orbits', () {
      expect(
          mouseDrag(mouse, kMiddleMouseButton, shift: true), MouseDrag.orbit);
    });

    // A plain left drag is how a mouse picks, box-selects and drags a grip,
    // and a right drag cycles the modify tools in a sketch. Neither becomes
    // navigation, with or without shift — shift is also the modifier that
    // EXTENDS a selection, and a shift-click must stay a shift-click.
    test('no other button navigates, shift or not', () {
      for (final b in [kPrimaryMouseButton, kSecondaryMouseButton]) {
        expect(mouseDrag(mouse, b, shift: false), MouseDrag.none);
        expect(mouseDrag(mouse, b, shift: true), MouseDrag.none);
      }
    });

    test('no button at all navigates nothing', () {
      expect(mouseDrag(mouse, 0, shift: false), MouseDrag.none);
      expect(mouseDrag(mouse, 0, shift: true), MouseDrag.none);
    });

    test('the middle button held with another one still navigates', () {
      expect(mouseDrag(mouse, kPrimaryMouseButton | kMiddleMouseButton,
          shift: false), MouseDrag.pan);
      expect(mouseDrag(mouse, kPrimaryMouseButton | kMiddleMouseButton,
          shift: true), MouseDrag.orbit);
    });

    test('only a mouse navigates this way', () {
      for (final k in [
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.unknown,
      ]) {
        expect(mouseDrag(k, kMiddleMouseButton, shift: false), MouseDrag.none,
            reason: '$k');
        expect(mouseDrag(k, kMiddleMouseButton, shift: true), MouseDrag.none,
            reason: '$k');
      }
    });
  });

  // THE STEP BACK ON RELEASE was not arithmetic — a middle-button drag drove
  // the raw Listener AND the GestureDetector's ScaleGestureRecognizer, which
  // accepts any button, and both wrote the same _mmbLast anchor. onScaleStart
  // reports the focal point the gesture STARTED at, so the moment the
  // recognizer won the arena it rewound the anchor to the press position and
  // the next move re-applied travel the view had already made. That fix is a
  // field per owner in the viewports; what CAN be pinned here is that the
  // navigation verdict is taken once, at the press, and is a pure function of
  // the press — nothing about it can change mid-drag.
  group('the verdict is fixed at the press', () {
    test('the same press always gives the same answer', () {
      for (var i = 0; i < 3; i++) {
        expect(mouseDrag(PointerDeviceKind.mouse, kMiddleMouseButton,
            shift: false), MouseDrag.pan);
      }
    });
  });

  group('the ViewCube frames the model it turns to', () {
    // "when i click on a viewing direction the zoom should also animate so
    // that the whole model is visible". The cube used to set halfH = 27 — a
    // fixed 54 mm of view height — on every face, edge, corner and step arrow.
    const size = Size(400, 300);

    test('the zoom follows the model, not a constant', () {
      final small = PartCamera()..halfH = 27;
      final big = PartCamera()..halfH = 27;
      fitPartView(small, [_box(10)], size);
      fitPartView(big, [_box(250)], size);
      expect(big.halfH, greaterThan(small.halfH * 10),
          reason: 'a 25x bigger model needs a much bigger view');
      expect(small.halfH, lessThan(27),
          reason: 'a 10 mm cube used to be lost in a 54 mm frame');
    });

    test('the orientation is read, never written', () {
      // The cube has already turned the camera by the time it frames it. A fit
      // that touched the direction would undo the very command that ran it.
      final c = PartCamera(az: 1.1, pol: 0.7, roll: 0.3);
      fitPartView(c, [_box(30)], size);
      expect(c.az, 1.1);
      expect(c.pol, 0.7);
      expect(c.roll, 0.3);
    });

    test('the model ends up centred', () {
      // A box spanning 0..40 has its centre at (20, 20, 20), and the origin is
      // one of its CORNERS — which is exactly what the old `ox = 0; oy = 0`
      // put in the middle of the screen. Seen from the front (dir = +Z, right
      // = +X, up = +Y) the centre projects to (20, 20).
      final c = PartCamera(az: 0, pol: math.pi / 2);
      fitPartView(c, [_box(40)], size);
      expect(c.ox, closeTo(20, 1e-9));
      expect(c.oy, closeTo(20, 1e-9));
    });

    test('nothing to frame leaves the camera exactly as it was', () {
      // An empty document must not be zoomed to a degenerate view.
      final c = PartCamera(az: 0.5, pol: 0.6, halfH: 27, ox: 3, oy: 4);
      fitPartView(c, const [], size);
      expect(c.halfH, 27);
      expect(c.ox, 3);
      expect(c.oy, 4);
    });

    // The swing animates it for free: PartCamera.lerp interpolates ox, oy and
    // halfH along with the angles, and halfH geometrically — so the zoom
    // glides between the two framings instead of stepping.
    test('the framing is what the swing interpolates', () {
      final from = PartCamera()..halfH = 27;
      final to = PartCamera()..halfH = 27;
      fitPartView(to, [_box(200)], size);
      final mid = PartCamera.lerp(from, to, 0.5);
      expect(mid.halfH, greaterThan(from.halfH));
      expect(mid.halfH, lessThan(to.halfH));
      expect(mid.ox, closeTo((from.ox + to.ox) / 2, 1e-9));
    });
  });
}

/// A cube spanning 0..[s] mm on every axis — enough mesh for the fitter to
/// measure a silhouette against.
KernelSolid _box(double s) {
  final pos = <double>[], nor = <double>[], idx = <int>[];
  void quad(List<List<double>> p, List<double> n) {
    final base = pos.length ~/ 3;
    for (final v in p) {
      pos.addAll(v);
      nor.addAll(n);
    }
    idx.addAll([base, base + 1, base + 2, base, base + 2, base + 3]);
  }

  quad([
    [0, 0, 0],
    [s, 0, 0],
    [s, s, 0],
    [0, s, 0]
  ], [
    0,
    0,
    -1
  ]);
  quad([
    [0, 0, s],
    [s, 0, s],
    [s, s, s],
    [0, s, s]
  ], [
    0,
    0,
    1
  ]);
  final mesh = OcctMeshData(
    Float64List.fromList(pos),
    Float64List.fromList(nor),
    Int32List.fromList(idx),
    Int32List.fromList([0]),
    Float64List(0),
    triFaces: Int32List.fromList(List<int>.filled(idx.length ~/ 3, 0)),
  );
  return KernelSolid(mesh, s * s * s, null);
}
