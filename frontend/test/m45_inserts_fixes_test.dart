// M45 — Geräte-Test-Fixes + Text-Fenster/Bounding-Rect.
//   * Bild traegt jetzt den Editier-Layer; Move/Resize wie gehabt
//   * DXF-Import re-zentriert die Bounding-Box auf den Ursprung (weit
//     entfernte Modellkoordinaten landen sonst ausserhalb der Ansicht)
//   * SketchText: font + layer round-trippen; Rendern nutzt den Font
//   * textBoundsWorld/textSnapPoints: automatische Groesse, Ecken als
//     Snap-Punkte, nur auf dem Editier-Layer

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/inserts.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  app.docsDirForTest = Directory.systemTemp.createTempSync('m45docs');
  return app;
}

/// A deterministic measurer for tests (no real font metrics): width scales
/// with character count and cap height, height == cap height.
Size fakeMeasure(SketchText t, String rendered) =>
    Size(rendered.length * t.height * 0.6, t.height);

void main() {
  test('image carries the editing layer and view-relative width', () {
    final app = makeApp();
    app.editingLayer = kDefaultLayer;
    final src = File(
        '${Directory.systemTemp.createTempSync('m45').path}/p.png')
      ..writeAsBytesSync([1, 2, 3]);
    final i = app.addImage(src.path, const Offset(3, 4),
        pxW: 100, pxH: 50, w: 200);
    expect(i.layer, kDefaultLayer);
    expect(i.x, closeTo(3, 1e-9));
    expect(i.w, closeTo(200, 1e-9));
    expect(i.h, closeTo(100, 1e-9)); // aspect
    // round-trips the layer
    final back = SketchImage.fromJson(i.toJson());
    expect(back.layer, kDefaultLayer);
  });

  test('text font + layer round-trip; rendering substitutes params', () {
    final app = makeApp();
    final t = app.addText(const Offset(0, 0), 'L=<d0>',
        height: 10, font: 'Courier');
    expect(t.font, 'Courier');
    expect(t.layer, kDefaultLayer);
    final back = SketchText.fromJson(t.toJson());
    expect(back.font, 'Courier');
    expect(back.layer, kDefaultLayer);
    expect(back.height, closeTo(10, 1e-9));
    // default font is omitted from JSON to keep sidecars lean
    final plain = SketchText('x', 0, 0);
    expect(plain.toJson().containsKey('f'), isFalse);
  });

  test('text bounding rect auto-sizes and exposes corner snap points', () {
    final app = makeApp();
    final s = app.current!;
    final t = app.addText(const Offset(10, 20), 'ABCD', height: 8);
    final r = app.textBoundsWorld(s, t, measure: fakeMeasure);
    // fake width = 4 chars * 8 * 0.6 = 19.2; height = 8; + padding 2 (0.25*8)
    expect(r.width, closeTo(19.2 + 4, 1e-6));
    expect(r.height, closeTo(8 + 4, 1e-6));
    expect(r.left, closeTo(10 - 2, 1e-6)); // anchor is lower-left, minus pad
    final pts = app.textSnapPoints(s, measure: fakeMeasure);
    expect(pts, hasLength(8)); // 4 corners + 4 edge midpoints
    expect(pts, contains(r.topLeft));
    expect(pts, contains(r.bottomRight));
    expect(pts, contains(r.center.translate(0, -r.height / 2))); // topCenter
  });

  test('text snap points only for texts on the edited layer', () {
    final app = makeApp();
    final s = app.current!;
    app.addText(const Offset(0, 0), 'A', height: 8); // on Layer 1 (edited)
    // a text on another layer must not contribute snap points while editing
    final other = SketchText('B', 5, 5, height: 8, layer: 'Layer 2');
    s.texts.add(other);
    final editing = app.textSnapPoints(s, measure: fakeMeasure);
    expect(editing, hasLength(8)); // only the edited-layer text
    // when no layer is being edited, all texts contribute
    app.editingLayer = null;
    final all = app.textSnapPoints(s, measure: fakeMeasure);
    expect(all, hasLength(16));
  });

  test('DXF import recentres far-flung geometry onto the origin', () {
    final dir = Directory.systemTemp.createTempSync('m45dxf');
    final author = SketchModel('_author');
    author.engine.addLine(10000, -2600, 10100, -2600);
    if (!author.engine.isRealBackend) {
      author.dispose();
      return; // native backend only (host uses the Dart fallback)
    }
    author.engine.addLine(10100, -2600, 10100, -2500);
    final path = '${dir.path}/far.dxf';
    expect(author.engine.saveDxf(path), isTrue);
    author.dispose();

    final app = makeApp();
    final s = app.current!;
    expect(app.importDxf(path), isTrue);
    // the imported geometry's bounding-box centre must be at (0,0)
    double minX = 1e18, minY = 1e18, maxX = -1e18, maxY = -1e18;
    for (final g in s.geometry) {
      for (var k = 0; k + 1 < g.data.length; k += 2) {
        minX = g.data[k] < minX ? g.data[k] : minX;
        maxX = g.data[k] > maxX ? g.data[k] : maxX;
        minY = g.data[k + 1] < minY ? g.data[k + 1] : minY;
        maxY = g.data[k + 1] > maxY ? g.data[k + 1] : maxY;
      }
    }
    expect((minX + maxX) / 2, closeTo(0, 1e-6));
    expect((minY + maxY) / 2, closeTo(0, 1e-6));
  });

  test('editing-session lifecycle: new empty text is dropped on cancel', () {
    final app = makeApp();
    final s = app.current!;
    final t = app.addText(const Offset(0, 0), ''); // placeholder
    app.beginTextEdit(t, isNew: true);
    expect(app.editingText, same(t));
    app.endTextEdit(keep: false); // cancel a brand-new text
    expect(s.texts, isEmpty);
    // editing an existing text and cancelling keeps it
    final t2 = app.addText(const Offset(1, 1), 'keep');
    app.beginTextEdit(t2, isNew: false);
    app.endTextEdit(keep: false);
    expect(s.texts, hasLength(1));
    expect(s.texts.single.template, 'keep');
  });
}
