// M44 — Parametrischer Text, Bild-Einfuegen, DXF-Import.
//   * Template-Rendering: <Name> → aktueller Wert (Zahl getrimmt),
//     Unbekanntes bleibt woertlich; Parameter-RENAME zieht Templates nach
//   * Text-CRUD + Move committen Journal-Schritte; Undo/Redo exakt
//   * Bild-Modell: Codec, Move/Resize (Aspekt fix), Journal
//   * DXF-Import: mit dem Backend-Loader geparste Entities landen als EIN
//     Journal-Schritt auf dem Editier-Layer der aktuellen Skizze

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/constraints.dart';
import 'package:ipadprocad/ffi/qcad_engine.dart';
import 'package:ipadprocad/inserts.dart';

AppState makeApp() {
  final app = AppState();
  final s = SketchModel('t');
  app.sketches['t'] = s;
  app.curTab = 't';
  app.editingLayer = kDefaultLayer;
  return app;
}

int drawLine(AppState app, Offset a, Offset b) {
  app.tool = Tool.line;
  app.toolClick(a);
  app.toolClick(b);
  app.tool = Tool.none;
  return app.current!.geometry.length - 1;
}

Constraint dimLine(AppState app, int e, String text) {
  final d = Constraint(CType.dimension,
      pts: [PRef(e, 0), PRef(e, 1)],
      dimKind: 'dist',
      textPos: const Offset(0, -10));
  app.pendingDim = d;
  app.confirmDimensionText(text);
  return d;
}

void main() {
  test('template rendering: substitution, trimming, unknowns literal', () {
    final p = {'Width': 40.0, 'd0': 12.5, 'Th': 3.125};
    expect(renderTemplate('W = <Width> mm', p), 'W = 40 mm');
    expect(renderTemplate('<d0> x <Th>', p), '12.5 x 3.125');
    expect(renderTemplate('spacing < Width >!', p), 'spacing 40!');
    expect(renderTemplate('<Ghost> stays', p), '<Ghost> stays');
    expect(renderTemplate('a<b', p), 'a<b'); // lone < is not a placeholder
    expect(templateRefs('<Width>+<d0> and <Width>'), {'Width', 'd0'});
    expect(renameInTemplate('<Width> vs <Wide>', 'Width', 'Breite'),
        '<Breite> vs <Wide>');
  });

  test('parametric text follows values AND renames; CRUD journals', () {
    final app = makeApp();
    final e0 = drawLine(app, const Offset(0, 0), const Offset(50, 0));
    final a = dimLine(app, e0, '40');
    final t = app.addText(const Offset(5, 5), 'L = <${a.paramName}> mm');
    final s = app.current!;
    expect(app.textDisplay(s, t), 'L = 40 mm');
    app.setDimensionValue(a, 60);
    expect(app.textDisplay(s, t), 'L = 60 mm'); // follows the value
    app.setDimensionText(a, 'Len = 60');
    expect(t.template, 'L = <Len> mm'); // rename swept the template
    expect(app.textDisplay(s, t), 'L = 60 mm');
    // move + edit + undo peel exactly
    app.moveText(t, const Offset(9, 9), commit: true);
    app.updateText(t, 'fixed', 10);
    expect(app.textDisplay(s, t), 'fixed');
    app.undo();
    expect(s.texts.single.template, 'L = <Len> mm');
    expect(s.texts.single.x, closeTo(9, 1e-9));
    app.undo();
    expect(s.texts.single.x, closeTo(5, 1e-9));
    app.deleteText(s.texts.single);
    expect(s.texts, isEmpty);
    app.undo();
    expect(s.texts, hasLength(1));
  });

  test('text and image sidecar codecs round-trip', () {
    final ts = [SketchText('W = <Width>', 3, 4, height: 12.5)];
    final tb = decodeTexts(encodeTexts(ts)).single;
    expect(tb.template, 'W = <Width>');
    expect(tb.height, closeTo(12.5, 1e-12));
    final ims = [SketchImage('img_1.png', 1, 2, 100, 62.5)];
    final ib = decodeImages(encodeImages(ims)).single;
    expect(ib.file, 'img_1.png');
    expect(ib.h, closeTo(62.5, 1e-12));
  });

  test('image insert/move/resize keeps aspect and journals', () async {
    final app = makeApp();
    app.docsDirForTest = Directory.systemTemp.createTempSync('m44docs');
    // a real (tiny) file to copy — content is irrelevant for the model
    final src = File(
        '${Directory.systemTemp.createTempSync('m44').path}/pic.png')
      ..writeAsBytesSync([1, 2, 3]);
    final i = app.addImage(src.path, const Offset(10, 20),
        pxW: 200, pxH: 100, w: 80);
    expect(i.h, closeTo(40, 1e-9)); // aspect from pixels
    expect(File(app.imagePath(i)).existsSync(), isTrue); // copied
    app.moveImage(i, const Offset(0, 0), commit: true);
    app.resizeImage(i, 160, commit: true);
    expect(i.h, closeTo(80, 1e-9)); // aspect preserved
    final s = app.current!;
    app.undo();
    expect(s.images.single.w, closeTo(80, 1e-9));
    app.undo();
    expect(s.images.single.x, closeTo(10, 1e-9));
    app.deleteImage(s.images.single);
    expect(s.images, isEmpty);
    app.undo();
    expect(s.images.single.file, i.file);
  });

  test('DXF import merges entities onto the editing layer as one undo step',
      () {
    // author a DXF with the same backend the import uses
    final dir = Directory.systemTemp.createTempSync('m44dxf');
    final author = SketchModel('_author');
    // DXF save/load lives only in the native backend; on the Dart fallback
    // (host `flutter test`) saveDxf is a no-op, so this test is a CI-only
    // check — same as the app's existing DXF round-trip coverage.
    author.engine.addLine(0, 0, 30, 0);
    if (!author.engine.isRealBackend) {
      author.dispose();
      return; // skipped on the Dart fallback engine
    }
    author.engine.addLine(30, 0, 30, 20);
    author.engine.addCircle(10, 10, 5);
    final path = '${dir.path}/in.dxf';
    expect(author.engine.saveDxf(path), isTrue);
    author.dispose();

    final app = makeApp();
    drawLine(app, const Offset(-50, -50), const Offset(-20, -50));
    final s = app.current!;
    final before = s.geometry.length;
    final depthBefore = s.undoDepth;
    expect(app.importDxf(path), isTrue);
    expect(s.geometry.length, before + 3);
    for (final g in s.geometry) {
      expect(g.layer, kDefaultLayer); // re-homed onto the editing layer
    }
    expect(s.undoDepth, depthBefore + 1); // ONE journal step
    app.undo();
    expect(s.geometry.length, before);
    app.redo();
    expect(s.geometry.length, before + 3);
    // a garbage file is refused without side effects
    final bad = File('${dir.path}/bad.dxf')..writeAsStringSync('not a dxf');
    final n = s.geometry.length;
    app.importDxf(bad.path);
    expect(s.geometry.length, n);
  });
}
