// M220 — a sketch text IS geometry.
//
// "schriften sollen tatsächlich linien sein wie in dxf üblich. in inventor
//  kann jede schrift auch exportiert werden als dxf und ist tatsächlich da
//  und jede schrift kann extrudiert werden"
//
// Before this, a text was a label: a TextPainter drew it on the canvas and
// that was the end of it. It was in no file, in no profile and in no solid.
// What is pinned here is the whole chain that makes it real:
//
//   * the OUTLINE FONT itself — that the shipped data decodes into closed
//     contours with the right topology ("O" is two loops, "l" is one) and
//     that a glyph is where the metrics say it is;
//   * the LAYOUT — the anchor contract (lower-left), lines, size scaling,
//     and that the bounding box actually bounds the curves, because that box
//     is what snapping and hit-testing use;
//   * the SKETCH — text as entities, on its own layer, obeying the layer eye
//     and the End of Sketch marker like everything else;
//   * the DXF — that the letters are IN the exported file, read back through
//     the engine, and that M112's Defpoints rule still holds beside them;
//   * the KERNEL — that a text produces profile regions with holes and that
//     an extrusion of one hands the letter's contour down.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/ffi/qcad_engine.dart';
import 'package:prototype/inserts.dart';
import 'package:prototype/params.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/text_geometry.dart';
import 'package:prototype/vector_font.dart';

/// Records the profile handed to the kernel and returns a stub solid — the
/// same trick as the M56 tests: no OCCT on host, but the GEOMETRY that would
/// have been extruded is fully observable.
class _FakeKernel implements PartKernel {
  List<List<List<Offset>>>? lastGroups;

  @override
  bool get available => true;
  @override
  String get info => 'fake';
  @override
  String get lastError => 'fake failure';

  KernelSolid _stub(double v) => KernelSolid(
      OcctMeshData(
          Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
          Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
          Int32List.fromList(const [0, 1, 2]),
          Int32List.fromList(const [0, 3]),
          Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0])),
      v,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    lastGroups = groups;
    return _stub(height);
  }

  @override
  noSuchMethod(Invocation i) => null;
}

AppState _app() => AppState()
  ..docsDirForTest = Directory.systemTemp.createTempSync('prototype_m220_');

/// A standalone sketch with one text on "Layer 1".
(SketchModel, SketchText) _sketchWithText(String s,
    {double height = 10, double x = 0, double y = 0, String? font}) {
  final sk = SketchModel('t')..layers.add('Layer 1');
  final t = SketchText(s, x, y,
      height: height, font: font ?? kDefaultTextFont, layer: 'Layer 1');
  sk.texts.add(t);
  return (sk, t);
}

Rect _boundsOf(List<List<Offset>> contours) {
  var minx = double.infinity, miny = double.infinity;
  var maxx = -double.infinity, maxy = -double.infinity;
  for (final c in contours) {
    for (final p in c) {
      minx = math.min(minx, p.dx);
      miny = math.min(miny, p.dy);
      maxx = math.max(maxx, p.dx);
      maxy = math.max(maxy, p.dy);
    }
  }
  return Rect.fromLTRB(minx, miny, maxx, maxy);
}

/// The geometry a DXF actually holds, read back through the engine — so the
/// assertion is about the FILE, not about the model that wrote it.
List<Geo> _readDxf(String path) {
  final s = SketchModel('_read');
  try {
    expect(s.engine.loadDxf(path), isTrue, reason: 'the DXF must be readable');
    s.refresh();
    return List<Geo>.of(s.geometry);
  } finally {
    s.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the outline font', () {
    test('every shipped family decodes with usable metrics', () {
      for (final name in kVectorFontNames) {
        final f = VectorFont.of(name);
        expect(f.ascent, greaterThan(0), reason: name);
        expect(f.descent, lessThan(0), reason: name);
        expect(f.capHeight, greaterThan(0.5), reason: name);
        expect(f.lineHeight, greaterThan(f.capHeight), reason: name);
        // the whole printable ASCII range, or the app could not write a note
        for (var cp = 0x20; cp <= 0x7E; cp++) {
          expect(f.has(cp), isTrue, reason: '$name lacks U+${cp.toRadixString(16)}');
        }
        // German is the language this app is used in: the umlauts and the
        // sharp s are not optional.
        for (final ch in ['ä', 'ö', 'ü', 'Ä', 'Ö', 'Ü', 'ß', '°', 'µ']) {
          expect(f.has(ch.runes.first), isTrue, reason: '$name lacks $ch');
        }
      }
    });

    test('a counter is a contour of its own, and a stem is not', () {
      final f = VectorFont.of('CAD Sans');
      expect(f.glyph('O'.runes.first)!.contours.length, 2,
          reason: 'outer ring + counter — this is what makes a hole a hole');
      expect(f.glyph('l'.runes.first)!.contours.length, 1);
      expect(f.glyph('i'.runes.first)!.contours.length, 2,
          reason: 'stem + tittle, two separate closed contours');
      expect(f.glyph('8'.runes.first)!.contours.length, 3);
    });

    test('a space draws nothing but still advances', () {
      final f = VectorFont.of('CAD Sans');
      final sp = f.glyph(0x20)!;
      expect(sp.contours, isEmpty);
      expect(sp.advance, greaterThan(0.1));
    });

    test('every contour is closed, non-degenerate and inside the em box', () {
      for (final name in kVectorFontNames) {
        final f = VectorFont.of(name);
        for (var cp = 0x21; cp <= 0x7E; cp++) {
          for (final c in f.glyph(cp)!.contours) {
            expect(c.length, greaterThanOrEqualTo(3),
                reason: '$name U+${cp.toRadixString(16)}');
            // implicitly closed: the last point must NOT repeat the first,
            // or every loop would carry a zero-length edge into the kernel
            expect((c.first - c.last).distance, greaterThan(1e-9),
                reason: '$name U+${cp.toRadixString(16)}');
            for (final p in c) {
              expect(p.dx.abs(), lessThan(4));
              expect(p.dy.abs(), lessThan(4));
            }
          }
        }
      }
    });

    test('the mono family is monospaced and the sans one is not', () {
      final mono = VectorFont.of('CAD Mono');
      final sans = VectorFont.of('CAD Sans');
      final mi = mono.glyph('i'.runes.first)!.advance;
      final mw = mono.glyph('W'.runes.first)!.advance;
      expect(mi, closeTo(mw, 1e-9));
      expect(sans.glyph('i'.runes.first)!.advance,
          lessThan(sans.glyph('W'.runes.first)!.advance));
    });

    test('a legacy screen-font name maps onto a family that exists', () {
      expect(vectorFontName('Roboto'), 'CAD Sans');
      expect(vectorFontName('Helvetica'), 'CAD Sans');
      expect(vectorFontName('Menlo'), 'CAD Mono');
      expect(vectorFontName('Courier'), 'CAD Mono');
      expect(vectorFontName('Georgia'), 'CAD Serif');
      expect(vectorFontName('something nobody ships'), 'CAD Sans');
      for (final n in kVectorFontNames) {
        expect(vectorFontName(n), n, reason: 'a real name maps to itself');
      }
    });
  });

  group('layout', () {
    test('the anchor is the lower-left of the box, and the box bounds the '
        'curves', () {
      const anchor = Offset(5, 7);
      final l = layoutText('Hg', 'CAD Sans', 10, origin: anchor);
      // NB: sketch space is y-UP, so `top` is the smallest y here.
      final b = _boundsOf(l.contours);
      final (minX, minY) = (b.left, b.top);
      final (maxX, maxY) = (b.right, b.bottom);
      expect(minX, greaterThanOrEqualTo(anchor.dx - 1e-9));
      expect(maxX, lessThanOrEqualTo(anchor.dx + l.size.width + 1e-9));
      expect(minY, greaterThanOrEqualTo(anchor.dy - 1e-9),
          reason: "the g's descender may reach the bottom edge, not cross it");
      expect(maxY, lessThanOrEqualTo(anchor.dy + l.size.height + 1e-9));
      // The baseline sits |descent| above the anchor, and a capital H stands
      // exactly cap height above the baseline. That is the whole contract
      // between the box, the letters and everything that snaps to either.
      final f = VectorFont.of('CAD Sans');
      final baseline = anchor.dy - f.descent * 10;
      expect(maxY, closeTo(baseline + f.capHeight * 10, 0.05));
      expect(minY, lessThan(baseline),
          reason: 'the g descends below the baseline');
    });

    test('size scales linearly and the anchor only translates', () {
      final a = layoutText('Ab', 'CAD Sans', 10);
      final b = layoutText('Ab', 'CAD Sans', 20);
      expect(b.size.width, closeTo(a.size.width * 2, 1e-9));
      expect(b.size.height, closeTo(a.size.height * 2, 1e-9));
      final c = layoutText('Ab', 'CAD Sans', 10, origin: const Offset(3, -4));
      expect(c.contours.length, a.contours.length);
      for (var i = 0; i < c.contours.length; i++) {
        for (var k = 0; k < c.contours[i].length; k++) {
          expect((c.contours[i][k] - a.contours[i][k] - const Offset(3, -4))
              .distance,
              lessThan(1e-9));
        }
      }
    });

    test('a newline starts a second line, below the first', () {
      final one = layoutText('AB', 'CAD Sans', 10);
      final two = layoutText('AB\nAB', 'CAD Sans', 10);
      expect(two.size.height, closeTo(one.size.height * 2, 1e-9));
      expect(two.size.width, closeTo(one.size.width, 1e-9));
      expect(two.contours.length, one.contours.length * 2);
      // the FIRST line sits on top: same shape as the single line, lifted by
      // exactly one line height
      final dy = one.size.height;
      expect((two.contours.first.first -
              one.contours.first.first -
              Offset(0, dy))
          .distance,
          lessThan(1e-9));
    });

    test('measureText agrees with the laid-out box', () {
      for (final s in ['A', 'Hello', 'Ø 12 mm', 'ÄÖÜ\nß']) {
        final l = layoutText(s, 'CAD Serif', 7);
        final m = measureText(s, 'CAD Serif', 7);
        expect(m.width, closeTo(l.size.width, 1e-9), reason: s);
        expect(m.height, closeTo(l.size.height, 1e-9), reason: s);
      }
    });

    test('an unknown codepoint costs a blank, never a crash', () {
      final l = layoutText('A\u{1F600}B', 'CAD Sans', 10);
      expect(l.contours, isNotEmpty);
      expect(l.size.width, greaterThan(measureText('AB', 'CAD Sans', 10).width));
    });

    test('a zero or negative height produces nothing', () {
      expect(layoutText('A', 'CAD Sans', 0).contours, isEmpty);
      expect(measureText('A', 'CAD Sans', -3), Size.zero);
    });
  });

  group('the text as sketch geometry', () {
    test('every contour becomes a CLOSED polyline on the text layer', () {
      final (sk, _) = _sketchWithText('OK');
      final gs = textGeometry(sk);
      expect(gs, isNotEmpty);
      for (final g in gs) {
        expect(g.type, Geo.polyline);
        expect(g.data[0], 1, reason: 'closed — a letter is not an open chain');
        expect(g.data[1].toInt(), greaterThanOrEqualTo(3));
        expect(g.data.length, 2 + 2 * g.data[1].toInt());
        expect(g.layer, 'Layer 1');
      }
      // O = ring + counter, K = one contour
      expect(gs.length, 3);
    });

    test('a placeholder is resolved before the outline is built', () {
      final sk = SketchModel('t')..layers.add('Layer 1');
      sk.userParams.add(UserParam('Width', 12));
      sk.texts.add(SketchText('<Width>', 0, 0, height: 10, layer: 'Layer 1'));
      // "12" is two glyphs, one contour each; the raw token would be seven
      expect(textGeometry(sk).length, 2);
      sk.userParams.first.value = 8;
      expect(textGeometry(sk).length, 3,
          reason: 'an 8 is three contours — the geometry follows the '
              'parameter, it is not a stale bake');
    });

    test('an empty text is no geometry at all', () {
      final (sk, _) = _sketchWithText('');
      expect(textGeometry(sk), isEmpty);
      expect(profileLoops(sk), isEmpty);
    });
  });

  group('the text as a profile', () {
    test('a letter with a counter is a region with a hole', () {
      final (sk, _) = _sketchWithText('O', height: 20);
      final loops = profileLoops(sk);
      expect(loops.length, 2);
      final regions = regionsFrom(loops);
      final ring = regions.firstWhere((r) => r.holes.isNotEmpty);
      expect(ring.holes.length, 1);
      expect(ring.outer.area, greaterThan(ring.holes.first.area));
    });

    test('loop ids stay unique next to ordinary geometry', () {
      final (sk, _) = _sketchWithText('O', height: 20, x: 100);
      sk.engine.setCurrentLayer('Layer 1');
      sk.engine.addCircle(5, 5, 3);
      sk.refresh();
      final loops = profileLoops(sk);
      expect(loops.length, 3, reason: 'the circle plus the two text contours');
      expect(loops.map((l) => l.id).toSet().length, 3,
          reason: 'a duplicate id would merge two loops in regionsFrom');
    });

    test('every loop is counter-clockwise, as the profile contract says', () {
      final (sk, _) = _sketchWithText('Ag8', height: 12);
      for (final l in profileLoops(sk)) {
        var a = 0.0;
        for (var i = 0; i < l.pts.length; i++) {
          final p = l.pts[i], q = l.pts[(i + 1) % l.pts.length];
          a += p.dx * q.dy - q.dx * p.dy;
        }
        expect(a / 2, greaterThan(0));
        expect(l.area, closeTo(a / 2, 1e-6));
      }
    });

    test('the layer eye and the End of Sketch marker apply to a text too', () {
      final (sk, _) = _sketchWithText('O', height: 20);
      expect(profileLoops(sk).length, 2);

      sk.hiddenLayers.add('Layer 1');
      expect(profileLoops(sk), isEmpty, reason: 'hidden is not a profile');
      sk.hiddenLayers.clear();

      sk.eosAfter = 0; // the layer is rolled back
      expect(profileLoops(sk), isEmpty, reason: 'below the marker is not one');
      sk.eosAfter = 1;
      expect(profileLoops(sk).length, 2);
    });

    test('a text on layer "" is on layer 0, not on a layer of its own', () {
      final sk = SketchModel('t')..layers.add('Layer 1');
      sk.texts.add(SketchText('I', 0, 0, height: 10));
      expect(textGeometry(sk).single.layer, kDefaultLayer);
      expect(profileLoops(sk).length, 1,
          reason: 'layer 0 is not in the layer list, and is not rolled back');
    });
  });

  group('the DXF', () {
    test('the letters are IN the exported file', () async {
      final app = _app();
      await app.openSketch('Plate');
      final s = app.current!;
      s.engine.setCurrentLayer(app.editingLayer ?? 'Layer 1');
      s.engine.addLine(0, 0, 50, 0);
      s.refresh();
      app.addText(const Offset(2, 5), 'OK', height: 8);
      await app.saveSketch('Plate');

      final path = await app.sketchExportPath('Plate');
      expect(path, isNotNull);
      final gs = _readDxf(path!);
      final polys = gs.where((g) => g.type == Geo.polyline).toList();
      expect(polys.length, 3,
          reason: 'O is two contours, K is one — all three in the file');
      expect(gs.where((g) => g.type == Geo.line).length, 1,
          reason: 'the drawing itself is still there, untouched');
      for (final p in polys) {
        expect(p.data[0], 1, reason: 'a letter arrives closed');
        expect(p.data[1].toInt(), greaterThan(3));
      }
      // and where the text was put, not at the origin
      final xs = <double>[];
      for (final p in polys) {
        final n = p.data[1].toInt();
        for (var i = 0; i < n; i++) {
          xs.add(p.data[2 + 2 * i]);
        }
      }
      expect(xs.reduce(math.min), greaterThanOrEqualTo(2 - 1e-9));
    });

    test('construction geometry still goes to Defpoints beside the text',
        () async {
      final app = _app();
      await app.openSketch('Plate');
      final s = app.current!;
      final layer = app.editingLayer ?? 'Layer 1';
      s.engine.setCurrentLayer(layer);
      s.engine.addLine(0, 0, 50, 0);
      s.engine.addCircle(10, 10, 4);
      s.refresh();
      s.geometry[1] = s.geometry[1].withStyle(Geo.styleConstruction);
      app.addText(const Offset(2, 5), 'I', height: 8);
      await app.saveSketch('Plate');

      final gs = _readDxf((await app.sketchExportPath('Plate'))!);
      final circle = gs.firstWhere((g) => g.type == Geo.circle);
      expect(circle.layer, AppState.kDxfConstructionLayer,
          reason: 'M112 — scaffolding must never reach the cutter');
      final poly = gs.firstWhere((g) => g.type == Geo.polyline);
      expect(poly.layer, isNot(AppState.kDxfConstructionLayer),
          reason: 'the text is real geometry, not scaffolding');
    });

    test('a sketch without text still ships its storage file unchanged',
        () async {
      // The cheap path (copy the sketch's own DXF) must survive M220: it is
      // only the presence of a text that forces the rebuild.
      final app = _app();
      await app.openSketch('Plain');
      final s = app.current!;
      s.engine.setCurrentLayer(app.editingLayer ?? 'Layer 1');
      s.engine.addLine(0, 0, 10, 0);
      s.refresh();
      await app.saveSketch('Plain');
      final gs = _readDxf((await app.sketchExportPath('Plain'))!);
      expect(gs.length, 1);
      expect(gs.single.type, Geo.line);
    });
  });

  group('the kernel', () {
    test('a text extrudes: the letter contour is what the kernel gets',
        () async {
      final app = _app();
      final fake = _FakeKernel();
      app.partKernel = fake;
      await app.createNamedPart('Sign');
      app.startPartSketch();
      app.planePicked('xy');
      app.addText(const Offset(0, 0), 'I', height: 10);
      app.finishPartSketch();

      app.openExtrude();
      final sess = app.extrudeSession!;
      expect(sess.profiles.length, 1,
          reason: 'the single letter is the only profile, so it is pre-picked');
      app.setExtrude(exprA: '3 mm');
      expect(await app.applyExtrude(), isTrue);

      final loop = fake.lastGroups!.single.single;
      expect(loop.length, greaterThanOrEqualTo(4));
      final b = _boundsOf([loop]);
      expect(b.height, closeTo(VectorFont.of('CAD Sans').capHeight * 10, 0.5),
          reason: 'a capital I is exactly cap height tall');
      expect(app.currentPart!.features.single.computeError, isNull);
    });

    test('the counter of an O is handed down as a HOLE of the profile',
        () async {
      final app = _app();
      final fake = _FakeKernel();
      app.partKernel = fake;
      await app.createNamedPart('Sign');
      app.startPartSketch();
      app.planePicked('xy');
      app.addText(const Offset(0, 0), 'O', height: 20);
      app.finishPartSketch();

      app.openExtrude();
      final regions = app.sessionRegions(app.currentPart!.childSketches.single);
      final ring = regions.firstWhere((r) => r.holes.isNotEmpty);
      app.toggleSessionProfile(
          app.currentPart!.childSketches.single.model.name, ring);
      app.setExtrude(exprA: '2 mm');
      expect(await app.applyExtrude(), isTrue);
      expect(fake.lastGroups!.single.length, 2,
          reason: 'outer contour + counter, so the letter is not filled in');
    });
  });

  group('editing keeps working', () {
    test('the bounding box follows the text, and so do its snap points', () {
      final app = _app();
      final (sk, t) = _sketchWithText('Hg', height: 10, x: 4, y: 3);
      final r = app.textBoundsWorld(sk, t);
      final b = _boundsOf(textContours(sk, t));
      expect(r.left, lessThan(b.left), reason: 'the box has breathing room');
      expect(r.right, greaterThan(b.right));
      expect(app.textSnapPoints(sk).length, 8);
      t.x = 40;
      final moved = app.textBoundsWorld(sk, t);
      expect(moved.left - r.left, closeTo(36, 1e-9));
      expect(_boundsOf(textContours(sk, t)).left - b.left, closeTo(36, 1e-9),
          reason: 'the cached outline must follow the anchor');
    });

    test('changing the font changes the curve', () {
      final (sk, t) = _sketchWithText('R', height: 10, font: 'CAD Sans');
      final sans = _boundsOf(textContours(sk, t));
      t.font = 'CAD Serif';
      final serif = _boundsOf(textContours(sk, t));
      expect(serif, isNot(sans), reason: 'a different face is a different shape');
    });

    test('a text still round-trips through its sidecar', () {
      final t = SketchText('Ø<D>', 3, 4, height: 6, font: 'CAD Mono',
          layer: 'Layer 2');
      final back = decodeTexts(encodeTexts([t])).single;
      expect(back.template, 'Ø<D>');
      expect(back.x, 3);
      expect(back.y, 4);
      expect(back.height, 6);
      expect(back.font, 'CAD Mono');
      expect(back.layer, 'Layer 2');
    });

    test('a pre-M220 sidecar loads and produces geometry', () {
      // Written before outline fonts existed: no "f" meant Roboto.
      final old = '[{"t":"A","x":1,"y":2,"h":5},'
          '{"t":"B","x":0,"y":0,"h":5,"f":"Georgia"}]';
      final ts = decodeTexts(old);
      expect(ts.first.font, kDefaultTextFont);
      expect(vectorFontName(ts.last.font), 'CAD Serif');
      final sk = SketchModel('t')..layers.add('Layer 1');
      sk.texts.addAll(ts);
      expect(textGeometry(sk).length, greaterThanOrEqualTo(2),
          reason: 'an old text draws with the family that replaced its own');
    });
  });
}
