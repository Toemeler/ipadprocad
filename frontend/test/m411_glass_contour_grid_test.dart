// M411 — #31: "there is a weird black border around or next to every liquid
// glass element on windows."
//
// The material's outer line is DEFINED as one device pixel. It was measured
// off the iPad, where a backdrop of 236 comes out 173 and one of 138 comes out
// 75 — one column, with the untouched backdrop beside it — and off iOS the app
// draws it itself, because the shader is a backdrop filter and the clip cuts
// it at the panel's edge, which is the one place the line is not.
//
// Drawing it as a stroke `1 / ratio` points wide is that line only when the
// panel's edge lands ON a device pixel boundary. On the iPad it always does:
// the ratio is 2 or 3 and the layout is whole points. On Windows the ratio is
// the display scale, 1.25 at the commonest setting, and then every ODD logical
// coordinate lands on a half pixel — so the one dark column is rasterised as
// two half-dark ones. Twice as wide, half as dark, soft on both sides: a
// border where the material has a hairline, on the one platform that reported
// a border.
//
// The property, and it is the only one worth testing: WHATEVER the ratio and
// WHEREVER the panel landed, the stroke covers whole device pixels.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_menu/native_menu.dart';
import 'package:prototype/bug_capture.dart' show captureDisplay;

/// The stroke's outer and inner edges in DEVICE pixels, which is where the
/// question is. `unit` is device pixels per local point.
({double outer, double inner}) _edges(
    double globalLeft, double dpr, GlassContourRing r, double unit) {
  final centre = globalLeft * dpr + r.rect.left * unit;
  final half = r.width * unit / 2;
  return (outer: centre - half, inner: centre + half);
}

bool _whole(double v) => (v - v.roundToDouble()).abs() < 1e-9;

GlassContourRing _ring({
  required Offset at,
  required Size size,
  required double dpr,
  double radius = 18,
  double scale = 1,
}) =>
    glassContourRing(
      topLeftGlobal: at,
      bottomRightGlobal: at + Offset(size.width, size.height) * scale,
      localSize: size,
      devicePixelRatio: dpr,
      cornerRadius: radius,
    );

void main() {
  group('THE REPORT: the line lands on whole device pixels', () {
    // 1.25 and 1.5 are Windows' 125% and 150%; 2 and 3 are the iPad's. The
    // panel positions are the app's own — the browser card starts at 14, the
    // compact rail is 46 wide — plus the odd ones that are the whole problem.
    for (final dpr in [1.0, 1.25, 1.5, 1.75, 2.0, 3.0]) {
      for (final left in [0.0, 14.0, 45.0, 46.0, 110.5, 263.3]) {
        test('ratio $dpr, panel at $left', () {
          final r = _ring(
              at: Offset(left, left), size: const Size(250, 400), dpr: dpr);
          final e = _edges(left, dpr, r, dpr);
          expect(_whole(e.outer), isTrue,
              reason: 'the outside of the line is at ${e.outer}');
          expect(_whole(e.inner), isTrue,
              reason: 'the inside of the line is at ${e.inner}');
          expect(e.inner - e.outer, closeTo(1, 1e-9),
              reason: 'and it is ONE pixel wide, not two half-lit ones');
        });
      }
    }
  });

  test('the iPad case is arithmetic that lands where it already did', () {
    // The old form was `bounds.inflate(w/2)` stroked at `w = 1/ratio`. At a
    // whole ratio with a whole-point panel that is already the pixel column
    // beside the panel, and this must not move it — the material is tuned
    // against the device and the line is the most visible part of it.
    const dpr = 2.0;
    final r = _ring(at: const Offset(14, 55), size: const Size(250, 400), dpr: dpr);
    expect(r.width, closeTo(1 / dpr, 1e-9));
    expect(r.rect.left, closeTo(-1 / dpr / 2, 1e-9));
    expect(r.rect.top, closeTo(-1 / dpr / 2, 1e-9));
    expect(r.rect.right, closeTo(250 + 1 / dpr / 2, 1e-9));
    expect(r.rect.bottom, closeTo(400 + 1 / dpr / 2, 1e-9));
    expect(r.radius, closeTo(18 + 1 / dpr / 2, 1e-9));
  });

  test('a half-pixel panel is pulled onto the grid, not left across two', () {
    // 45 logical at 1.25 is device 56.25. Without the snap the stroke runs
    // 55.25..56.25 and lights two columns at a quarter and three quarters.
    const dpr = 1.25;
    final r = _ring(at: const Offset(45, 45), size: const Size(250, 400), dpr: dpr);
    final e = _edges(45, dpr, r, dpr);
    expect(e.outer, closeTo(55, 1e-9));
    expect(e.inner, closeTo(56, 1e-9));
  });

  test('an ancestor scale is followed, because the shader follows it', () {
    // The line and the rim it sits beside are measured from the same
    // rectangle (glassDeviceRect) or they disagree about where the panel is by
    // exactly the amount that shows.
    const dpr = 2.0;
    final r = _ring(
        at: const Offset(10, 10),
        size: const Size(100, 100),
        dpr: dpr,
        scale: 2);
    // 100 local points cover 400 device pixels: one device pixel is a quarter
    // of a local point, and the stroke has to be that.
    expect(r.width, closeTo(1 / (dpr * 2), 1e-9));
    final e = _edges(10, dpr, r, dpr * 2);
    expect(_whole(e.outer), isTrue);
    expect(e.inner - e.outer, closeTo(1, 1e-9));
  });

  test('a full-bleed surface asks for no corner', () {
    // The ribbon band is cornerRadius 0 (RibbonMetrics.radius) and is stroked
    // as a plain rectangle; a radius grown by half a pixel there would round
    // an edge the app deliberately runs square to the window.
    final r = _ring(
        at: Offset.zero, size: const Size(84, 900), dpr: 1.25, radius: 0);
    expect(r.radius, 0);
  });

  test('a degenerate panel does not divide by zero', () {
    final r = _ring(at: Offset.zero, size: Size.zero, dpr: 1.25);
    expect(r.width.isFinite, isTrue);
    expect(r.rect.left.isFinite, isTrue);
  });

  // -------------------------------------------------------------------------
  // The other half of #31, which is not a fix but the reason the next report
  // can be answered: "also it seems that text somehow doesnt look completely
  // sharp in the whole app in windows idk why", and from the same machine a
  // few hours earlier, "i think theres an issue because of the scaling".
  //
  // Both are questions about the device pixel ratio, and the bundle could not
  // answer either — the screenshot is captured at a fixed ratio of its own, so
  // its size says nothing about the display's.
  group('the bundle records the display', () {
    test('the ratio, the logical size and the physical size', () {
      final d = captureDisplay();
      expect(d['display'], isNotNull);
      // The ratio leads, because "1.25" is a different bug from "2".
      expect(d['display'], matches(RegExp(r'^[0-9.]+x — ')));
      expect(d['display'], contains('logical'));
      expect(d['display'], contains('physical'));
      expect(d['text scale'], isNotNull);
    });

    test('and it never throws — a bug reporter that fails is worse than none',
        () {
      expect(captureDisplay, returnsNormally);
    });
  });
}
