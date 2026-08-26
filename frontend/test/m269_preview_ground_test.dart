// M269 — a gallery still must carry the part, never the palette.
//
// The symptom: one cream card among nine charcoal ones, and it stayed cream
// across relaunches and scheme switches. The card paints T.galleryThumb behind
// the preview PNG, so a still with a ground BAKED IN is a photograph of one
// colour scheme that outlives it.
//
// M237 already asked the off-screen renderer for a transparent ground, and the
// request is not always honoured — so the app stops trusting it. These tests
// cover the check and the repair:
//
//   * detectGround only claims a ground when there really is one, because
//     clearing "the commonest colour" out of a still that has no flat border
//     would eat the drawing.
//   * keyOutGround fills INWARD FROM THE BORDER, so a shaded face that happens
//     to be the same grey as the ground keeps its pixels. This is the whole
//     reason it is a flood fill and not a colour replace.
//   * demattePng survives a real PNG round trip through the codec.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/preview_matte.dart';

/// A raw RGBA buffer from a function of (x, y) -> 0xAARRGGBB.
///
/// Only ever fully opaque or fully transparent here, which keeps premultiplied
/// and straight alpha the same thing and the expectations exact.
Uint8List _buf(int w, int h, int Function(int x, int y) argb) {
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final c = argb(x, y), i = (y * w + x) * 4;
      final a = (c >> 24) & 0xFF;
      out[i] = a == 0 ? 0 : (c >> 16) & 0xFF;
      out[i + 1] = a == 0 ? 0 : (c >> 8) & 0xFF;
      out[i + 2] = a == 0 ? 0 : c & 0xFF;
      out[i + 3] = a;
    }
  }
  return out;
}

int _alphaAt(Uint8List rgba, int w, int x, int y) => rgba[(y * w + x) * 4 + 3];
int _rgbAt(Uint8List rgba, int w, int x, int y) {
  final i = (y * w + x) * 4;
  return (rgba[i] << 16) | (rgba[i + 1] << 8) | rgba[i + 2];
}

const int _cream = 0xFCFBF8; // Chalk's viewport ground — the cream card
const int _part = 0xB0B6BE;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('detectGround — only when there really is one', () {
    test('a flat opaque border IS a ground', () {
      final b = _buf(40, 30, (x, y) => 0xFF000000 | _cream);
      expect(detectGround(b, 40, 30), _cream);
    });

    test('a still that is already transparent has nothing to repair', () {
      // The good case, and by far the commonest: the renderer honoured the
      // transparent ground the app asked for.
      final b = _buf(40, 30, (x, y) => 0x00000000);
      expect(detectGround(b, 40, 30), isNull);
    });

    test('a part running off the edge still leaves a ground to find', () {
      final b = _buf(40, 30,
          (x, y) => 0xFF000000 | (x > 30 ? _part : _cream));
      expect(detectGround(b, 40, 30), _cream);
    });

    test('a border that is not FLAT is not a ground', () {
      // Half and half: neither colour is 90% of the border, so there is no
      // single ground and guessing at one would tear the picture.
      final b = _buf(40, 30,
          (x, y) => 0xFF000000 | (x < 20 ? _cream : _part));
      expect(detectGround(b, 40, 30), isNull);
    });

    test('a gradient border is not a ground either', () {
      final b = _buf(40, 30, (x, y) => 0xFF000000 | (x * 6 << 16));
      expect(detectGround(b, 40, 30), isNull);
    });

    test('too small to have a border', () {
      expect(detectGround(_buf(2, 2, (x, y) => 0xFFFFFFFF), 2, 2), isNull);
    });
  });

  group('keyOutGround — inward from the border, and no further', () {
    test('the ground goes and the part stays', () {
      const w = 40, h = 30;
      bool inPart(int x, int y) => x >= 12 && x < 28 && y >= 8 && y < 22;
      final b = _buf(w, h,
          (x, y) => 0xFF000000 | (inPart(x, y) ? _part : _cream));
      final cleared = keyOutGround(b, w, h, _cream);
      expect(cleared, w * h - 16 * 14);
      expect(_alphaAt(b, w, 0, 0), 0);
      expect(_alphaAt(b, w, w - 1, h - 1), 0);
      expect(_alphaAt(b, w, 20, 15), 255);
      expect(_rgbAt(b, w, 20, 15), _part);
    });

    test('a face the SAME colour as the ground keeps its pixels', () {
      // The reason this is a flood fill. A flat mid-grey is a perfectly
      // ordinary colour for a shaded face, and a colour replace would punch a
      // hole straight through the middle of the part.
      const w = 40, h = 30;
      int at(int x, int y) {
        final inPart = x >= 10 && x < 30 && y >= 6 && y < 24;
        if (!inPart) return 0xFF000000 | _cream;
        final inWindow = x >= 16 && x < 24 && y >= 12 && y < 18;
        return 0xFF000000 | (inWindow ? _cream : _part);
      }

      final b = _buf(w, h, at);
      keyOutGround(b, w, h, _cream);
      // Enclosed by the part, so it is not connected to the border.
      expect(_alphaAt(b, w, 20, 15), 255);
      expect(_rgbAt(b, w, 20, 15), _cream);
      expect(_alphaAt(b, w, 0, 0), 0);
    });

    test('a cleared pixel is zeroed in all four channels', () {
      // dart:ui hands out PREMULTIPLIED RGBA: alpha 0 with the old colour left
      // behind is a malformed pixel, and some encoders keep the colour.
      final b = _buf(8, 8, (x, y) => 0xFF000000 | _cream);
      keyOutGround(b, 8, 8, _cream);
      expect(b.every((v) => v == 0), isTrue);
    });

    test('tolerance covers the renderer\'s own jitter, not a real colour', () {
      const w = 20, h = 20;
      // MSAA resolve and the sRGB round trip move a flat ground by a few
      // counts; a face 40 away is a different colour and must survive.
      const near = 0xF6F5F2; // 6 off the cream
      final b = _buf(w, h, (x, y) {
        if (x == 5 && y == 0) return 0xFF000000 | near;
        if (x == 7 && y == 0) return 0xFF000000 | _part;
        return 0xFF000000 | _cream;
      });
      keyOutGround(b, w, h, _cream);
      expect(_alphaAt(b, w, 5, 0), 0);
      expect(_alphaAt(b, w, 7, 0), 255);
    });

    test('nothing to clear when the still is already transparent', () {
      final b = _buf(20, 20, (x, y) => 0x00000000);
      expect(keyOutGround(b, 20, 20, _cream), 0);
    });
  });

  group('demattePng — through the real codec', () {
    /// A still as the renderer would have written it: a flat ground with a
    /// shape on top.
    Future<Uint8List> baked(Color ground) async {
      const w = 60.0, h = 40.0;
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
      canvas.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = ground);
      canvas.drawRect(const Rect.fromLTWH(20, 12, 20, 16),
          Paint()..color = const Color(0xFFB0B6BE));
      final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      return bytes!.buffer.asUint8List();
    }

    Future<Uint8List> rawOf(Uint8List png) async {
      final codec = await ui.instantiateImageCodec(png);
      final f = await codec.getNextFrame();
      final d = await f.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      f.image.dispose();
      codec.dispose();
      return d!.buffer.asUint8List();
    }

    test('a still baked on cream comes back transparent', () async {
      final out = await demattePng(await baked(const Color(0xFFFCFBF8)));
      expect(out, isNotNull);
      final raw = await rawOf(out!);
      expect(_alphaAt(raw, 60, 0, 0), 0, reason: 'the ground is gone');
      expect(_alphaAt(raw, 60, 59, 39), 0);
      expect(_alphaAt(raw, 60, 30, 20), 255, reason: 'the part is not');
    });

    test('a still baked on the charcoal viewport comes back transparent too',
        () async {
      // The same defect, invisible on a dark card only because the baked
      // ground happened to match. It is still a palette in a file.
      final out = await demattePng(await baked(const Color(0xFF212830)));
      expect(out, isNotNull);
      final raw = await rawOf(out!);
      expect(_alphaAt(raw, 60, 0, 0), 0);
      expect(_alphaAt(raw, 60, 30, 20), 255);
    });

    test('a still that is already right is left alone', () async {
      final out = await demattePng(await baked(const Color(0x00000000)));
      expect(out, isNull, reason: 'null means "keep the bytes you have"');
    });

    test('rubbish in is null out, not a throw', () async {
      expect(await demattePng(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });
}
