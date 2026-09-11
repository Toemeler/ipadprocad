// #50 — "the main workplanes when highlighted have these round circle corners
// which look awfull. the corners should be very small quadratic points".
//
// This was first read as the BORDER: a plane's outline is a closed rectangle,
// and in the RealityKit renderer it was stroked as four independent round
// tubes whose circular cross-sections show past a sharp 90° corner. That was a
// real defect and b49fc80 fixed it — but it was not what the report is about.
// The screenshot that came with the follow-up arrows the small round MARKERS
// standing on each corner of a highlighted plane, and "when highlighted" in
// the report says the same thing: the border is drawn whether the plane is hot
// or not, and those markers only exist while it is.
//
// So the marker is the subject, and it is Dart in both viewports — the CPU
// painter and the iOS screen-space overlay — which is why it now goes through
// one function, and why these tests can measure it.
//
// They measure it by RASTERISING it. "The code calls drawRect" would pass on a
// rect nobody could tell from the dot it replaced; what the report is about is
// what reaches the screen, so the mark is painted into a real image and read
// back:
//
//   * the CORNER pixel of its box is painted;
//   * it is small: 5 across, where the dot was 8.
//
// The two together are what pin the shape, and neither would on its own: a
// round dot big enough covers a small box's corners, and a small enough round
// dot is small. A marker that is BOTH 5 across and filled out to the corners
// of those 5 is a square. `the round dot this replaced fails both of these`
// runs the exact old call through the same two measurements and holds it to
// failing them, so the state this issue reports cannot quietly come back.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/widgets/viewport3d.dart';

/// A canvas of [_side], with the marker centred on a pixel BOUNDARY so a
/// 5-wide box covers whole pixels either side of it and there is no
/// antialiasing at its edges to argue about.
const int _side = 21;
const Offset _centre = Offset(10.5, 10.5);

/// The pixels a 5-wide mark centred on [_centre] covers: x and y in 8..12. So
/// 8 and 12 are its extremes and 7 and 13 are outside it.
const int _in = 8, _out = 7;

/// Paints [draw] into an [_side]x[_side] RGBA buffer over a transparent
/// ground, so "painted here" is just "alpha here".
Future<Uint8List> _raster(void Function(Canvas) draw) async {
  final rec = ui.PictureRecorder();
  final side = _side.toDouble();
  draw(Canvas(rec, Rect.fromLTWH(0, 0, side, side)));
  final img = await rec.endRecording().toImage(_side, _side);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return bytes!.buffer.asUint8List();
}

bool _painted(Uint8List rgba, int x, int y) =>
    rgba[(y * _side + x) * 4 + 3] > 200;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final paint = Paint()..color = const Color(0xFF00FF00);

  test('a corner mark is SQUARE — the corners of its box are painted',
      () async {
    final px = await _raster((c) => drawPlaneCornerMark(c, _centre, paint));

    // All four diagonal extremes covered. A circle inscribed in the same box
    // cannot do this, which is the whole report — and the next test is what
    // stops a circle from passing by simply being bigger than the box.
    for (final x in [_in, 20 - _in]) {
      for (final y in [_in, 20 - _in]) {
        expect(_painted(px, x, y), isTrue,
            reason: 'corner ($x, $y) of the mark must be filled');
      }
    }
    expect(_painted(px, 10, 10), isTrue, reason: 'and it is solid, not a ring');
  });

  test('...and very small: 5 across, and nothing beyond that', () async {
    expect(kPlaneCornerMark, 5);
    final px = await _raster((c) => drawPlaneCornerMark(c, _centre, paint));
    for (final d in [_out, 20 - _out]) {
      expect(_painted(px, d, 10), isFalse, reason: 'it stops at 5 across ($d)');
      expect(_painted(px, 10, d), isFalse, reason: 'in both axes ($d)');
    }
  });

  test('the round dot this replaced fails both of these', () async {
    // The exact call both painters made: `canvas.drawCircle(p, 4, paint)`.
    final px = await _raster((c) => c.drawCircle(_centre, 4, paint));

    // A corner of ITS box (x, y in 7..13) is 4*sqrt(2) from the centre, so the
    // box reads as a circle with four bites out of it — the report, measured.
    expect(_painted(px, _out, _out), isFalse,
        reason: 'which is what "round circle corners" was looking at');
    // And it is 8 across where the mark is 5, so it is not small either: it is
    // still going at the pixel the mark has already stopped at.
    expect(_painted(px, 20 - _out, 10), isTrue,
        reason: 'the dot reaches past the mark on every side');
  });

  test('both viewports draw the corner through the one function', () {
    // M254 was reported against the CPU painter and the iOS overlay painter
    // disagreeing about this very marker, so they must not drift apart again —
    // and a rasterised test can only reach the function, not its callers.
    final src = File('lib/widgets/viewport3d.dart').readAsStringSync();
    final sites = 'for (final c in corners) {'.allMatches(src).toList();
    expect(sites.length, 2,
        reason: 'the CPU painter and the iOS overlay painter');
    for (final m in sites) {
      // The loop's own body and no further: its closing brace is the first
      // one after it, because nothing in it nests.
      final body = src.substring(m.end).split('}').first;
      expect(body, contains('drawPlaneCornerMark'));
      expect(body, isNot(contains('drawCircle')),
          reason: 'a plane corner is not a dot any more');
    }
  });
}
