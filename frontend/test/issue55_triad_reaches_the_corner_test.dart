// #55 — "the Triad too should move Left when Modell Browser is retracted."
//
// Filed from a 390x844 phone on build b49fc80, alongside #54, and it splits
// into two parts that were measured rather than guessed at.
//
// The part that was already right: `NativeModelBrowser.triadInset` returns 0
// the moment the panel's occupancy reaches the collapsed figure (M207), and
// #52's fix (f59e99a) took the ribbon's own 18 pt retract strip out of the
// layout. Between them the triad's BOX is flush against the screen's left
// edge when the browser retracts. coordinate_triad_test pins the first;
// issue54_browser_reaches_the_edge_test pins the second.
//
// The part that was not: `TriadPainter` projects the world origin to the
// CENTRE of its box, because the axes swing through every direction as the
// camera orbits and the glyph has to fit whichever way they point. A 118 pt
// box therefore marks the origin 59 pt from the screen's edge however flush
// the box itself is. On an iPad that is a sixteenth of the window and nobody
// ever minded. On this reporter's 390 pt phone it is a SEVENTH of the screen,
// which is what still reads as "the triad did not move".
//
// So the phone draws a smaller triad. What this file pins is that the box
// cannot simply be trimmed to get there: the labels already reach within a
// point or two of the edge, so a smaller box needs a proportionally smaller
// world extent or it clips the X or the Z arrow at some camera angles and not
// others — the worst kind of bug to find, because it depends on where you
// last left the camera.
import 'dart:math' as math;

import 'package:flutter/painting.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/device_class.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_render.dart';
import 'package:prototype/widgets/viewport3d.dart';

/// The furthest the painter puts ink from the origin, for a square box of
/// [box] points, over a full sweep of the camera.
///
/// Measured the way the painter draws it: a label parked at 1.28 world units
/// along each axis, centred on that point, so its own [TriadPainter.labelReach]
/// stands past the anchor whichever way the axis is pointing.
double _reach(double box) {
  final size = Size(box, box);
  final centre = Offset(box / 2, box / 2);
  var worst = 0.0;
  for (var i = 0; i < 72; i++) {
    for (var j = 0; j <= 24; j++) {
      final cam = Cam3(
          PartCamera(
              az: i * math.pi / 36,
              pol: j * math.pi / 24,
              halfH: TriadPainter.halfHeightFor(box / 2)),
          size);
      for (final axis in const [
        Vec3(1, 0, 0),
        Vec3(0, 1, 0),
        Vec3(0, 0, 1),
      ]) {
        final label = cam.project(axis * 1.28) - centre;
        worst = math.max(worst, label.dx.abs() + TriadPainter.labelReach);
        worst = math.max(worst, label.dy.abs() + TriadPainter.labelReach);
      }
    }
  }
  return worst;
}

void main() {
  tearDown(() => isPhoneOverride = null);

  group('the box the triad is drawn in', () {
    test('a phone gets a smaller one, so the origin sits nearer the corner',
        () {
      isPhoneOverride = true;
      final phone = triadBox();
      isPhoneOverride = false;
      final rest = triadBox();

      expect(phone, lessThan(rest),
          reason: 'the glyph is what is left standing out in the room once '
              'the panel and the band have gone');
      // Half the box is the gap between the screen's corner and the point the
      // triad actually marks. The report's complaint, in one number.
      expect(phone / 2, lessThan(rest / 2));
      expect(phone / 2, lessThanOrEqualTo(45),
          reason: 'a seventh of a 390 pt screen was the complaint; this is '
              'nearer an eighth');
    });

    test('everything but a phone keeps the box it has always had', () {
      isPhoneOverride = false;
      expect(triadBox(), 118);
      // ...drawn at exactly the world extent it has always been drawn at.
      // 118 solves to 1.481 and the floor returns the 1.5 that shipped, so
      // the iPad's and the desktop's triad is unchanged to the pixel.
      expect(TriadPainter.halfHeightFor(59), 1.5);
    });
  });

  group('the glyph stays inside its box', () {
    // [TriadPainter.halfHeightFor] SOLVES for this, so below the 1.5 floor the
    // furthest label lands exactly on the box's edge and the real margin is
    // the point of slack inside `labelReach` itself (half a 12 pt line is 7).
    // Hence the epsilon: it is float arithmetic meeting its own equality, not
    // a bound being stretched to fit.
    const eps = 1e-6;

    test('at the size every platform but a phone draws it', () {
      isPhoneOverride = false;
      // This one has real room: the 1.5 floor is above what 118 pt needs.
      expect(_reach(triadBox()), lessThan(triadBox() / 2));
    });

    test('and at the phone size, which is the one this issue adds', () {
      isPhoneOverride = true;
      expect(_reach(triadBox()), lessThanOrEqualTo(triadBox() / 2 + eps));
    });

    test('which a box trimmed on its own would NOT do', () {
      // The change this file is guarding against: pulling the origin toward
      // the corner by shrinking the box and leaving the world extent alone.
      // At 1.5 the phone's 86 pt box puts the labels past its own edge, so
      // the arrow pointing that way is cut off — and which arrow that is
      // depends on where the camera happens to be.
      final size = const Size(86, 86);
      final cam = Cam3(PartCamera(az: 0, pol: math.pi / 2, halfH: 1.5), size);
      final label = cam.project(const Vec3(1, 0, 0) * 1.28) - const Offset(43, 43);
      expect(label.dx.abs() + TriadPainter.labelReach, greaterThan(43),
          reason: 'this is the clip halfHeightFor exists to prevent');
    });
  });
}
