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
//   * the CORNER pixel of its box is painted SOLID;
//   * it is small: 3 across, where the dot was 8 and the first square was 5.
//
// The two together are what pin the shape, and neither would on its own: a
// round dot big enough covers a small box's corners, and a small enough round
// dot is small. A marker that is BOTH 3 across and filled out to the corners
// of those 3 is a square. There is one negative control for each measurement,
// so neither can quietly stop measuring: the 8-across dot both painters used
// to draw is held to failing the SIZE test, and a circle inscribed in the
// mark's own 3-wide box is held to failing the CORNER test — at this size it
// leaves that corner pixel part-covered where the square fills it.
//
// 5 across was reported too, on 2026-09-12: "the rectangles on the corners of
// the workplane highlight are still way too big". The size these tests pin is
// the third answer to the same sentence and the first one set against
// something — the 1 pt border the mark stands on — rather than against the
// thing it replaced.
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/widgets/viewport3d.dart';

/// A canvas of [_side], with the marker centred on a pixel BOUNDARY so an
/// odd-width box covers whole pixels either side of it and there is no
/// antialiasing at its edges to argue about.
const int _side = 21;
const Offset _centre = Offset(10.5, 10.5);

/// The pixels a 3-wide mark centred on [_centre] covers: x and y in 9..11. So
/// 9 and 11 are its extremes and 8 and 12 are outside it.
const int _in = 9, _out = 8;

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

  test('...and very small: 3 across, and nothing beyond that', () async {
    expect(kPlaneCornerMark, 3);
    final px = await _raster((c) => drawPlaneCornerMark(c, _centre, paint));
    for (final d in [_out, 20 - _out]) {
      expect(_painted(px, d, 10), isFalse, reason: 'it stops at 3 across ($d)');
      expect(_painted(px, 10, d), isFalse, reason: 'in both axes ($d)');
    }
  });

  test('NEGATIVE CONTROL: the round dot this replaced is not small', () async {
    // The exact call both painters made: `canvas.drawCircle(p, 4, paint)`.
    final px = await _raster((c) => c.drawCircle(_centre, 4, paint));
    // 8 across where the mark is 3: still going well past the pixel the mark
    // has already stopped at, in every direction.
    for (final d in [_out, 20 - _out]) {
      expect(_painted(px, d, 10), isTrue,
          reason: 'the dot reaches past the mark ($d)');
      expect(_painted(px, 10, d), isTrue, reason: 'in both axes ($d)');
    }
    // A corner of ITS OWN box (7, 7) is 4*sqrt(2) away, so it reads as a
    // circle with four bites out of it — "round circle corners", measured.
    expect(_painted(px, 7, 7), isFalse);
  });

  test('NEGATIVE CONTROL: a circle of the mark\'s own size is not square',
      () async {
    // Small enough to pass the size test, so only the corner test can tell it
    // apart — and it does: inscribed in the same 3-wide box, the corner pixel
    // is part-covered where the square fills it.
    final px =
        await _raster((c) => c.drawCircle(_centre, kPlaneCornerMark / 2, paint));
    for (final d in [_out, 20 - _out]) {
      expect(_painted(px, d, 10), isFalse, reason: 'small enough ($d)');
    }
    expect(_painted(px, _in, _in), isFalse,
        reason: 'but round, so its box corner is not filled');
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
