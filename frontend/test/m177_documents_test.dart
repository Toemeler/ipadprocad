// M177 — the document layer end to end: one file per document, migrating the
// folders already on the device, and Open / Save against an external file.
//
// The migration tests are the ones that matter. Everything else here can be
// fixed in the next build; a migration that drops a part cannot.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/doc_ref.dart';
import 'package:prototype/doc_store.dart';

Directory _scratch() => Directory.systemTemp.createTempSync('m177_docs');

AppState _app(Directory docs) => AppState()
  ..docsDirForTest = docs
  // The host suite keeps every scratch folder under systemTemp, which on iOS
  // IS the picker's copy location — so the volatile rule has to be stated
  // explicitly here instead of inferred. `_pickerApp` opts back in.
  ..volatileDirsForTest = const [];

/// An app that treats [pickerDir] the way the device treats tmp.
AppState _pickerApp(Directory docs, String pickerDir) =>
    _app(docs)..volatileDirsForTest = [pickerDir];

void _write(String path, String text) {
  final f = File(path);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(text);
}

List<String> _files(Directory d) => [
      for (final e in d.listSync())
        if (e is File) e.uri.pathSegments.last
    ]..sort();

/// A pre-M177 sketch: a DXF plus its sidecars, loose in `sketches/`.
void _legacySketch(Directory docs, String name,
    {String dxf = 'DXFBODY', String? imageFile}) {
  final dir = '${docs.path}/sketches';
  _write('$dir/$name.dxf', dxf);
  _write('$dir/$name.cons.json', '[]');
  _write('$dir/$name.layers.json', '{"version":3,"layers":["0"],"eos":1}');
  _write('$dir/$name.png', 'PNGBYTES');
  _write(
      '$dir/$name.images.json',
      imageFile == null
          ? '[]'
          : '[{"f":"$imageFile","x":0,"y":0,"w":10,"h":10,"l":"0"}]');
  if (imageFile != null) _write('$dir/$imageFile', 'IMAGEBYTES');
}

/// A pre-M177 part: <name>.part.json, a parts/<name>/sketches/ tree, a png,
/// and a <name>_imports/ folder for anything imported from STEP.
void _legacyPart(Directory docs, String name,
    {List<String> children = const ['Sketch1'], String? importFile}) {
  final dir = '${docs.path}/sketches';
  _write(
      '$dir/$name.part.json',
      jsonEncode({
        'name': name,
        'sketches': [
          for (final c in children) {'name': c, 'plane': 'xy', 'vis': true}
        ],
        'features': const [],
      }));
  _write('$dir/$name.png', 'PARTPNG');
  for (final c in children) {
    _write('$dir/parts/$name/sketches/$c.dxf', 'CHILD $c');
    _write('$dir/parts/$name/sketches/$c.cons.json', '[]');
  }
  if (importFile != null) {
    _write('$dir/${name}_imports/$importFile', 'ISO-10303-21;');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M177 migration', () {
    test('a legacy sketch becomes one .pts with everything inside it', () {
      final docs = _scratch();
      _legacySketch(docs, 'Flange');
      final app = _app(docs);

      expect(app.migrateLegacyDocuments(), 1);

      expect(_files(docs), ['Flange.$kSketchExt']);
      final doc = readDoc('${docs.path}/Flange.$kSketchExt')!;
      expect(doc.kind, 'sketch');
      expect(doc.textOf('$kSketchBase.dxf'), 'DXFBODY');
      expect(doc.textOf('$kSketchBase.cons.json'), '[]');
      expect(doc.textOf('$kSketchBase.layers.json'), contains('"eos":1'));
      expect(doc.textOf(kPreviewEntry), 'PNGBYTES',
          reason: 'the thumbnail moves inside the document');
      docs.deleteSync(recursive: true);
    });

    test('a legacy part carries its child sketches, preview and imports', () {
      final docs = _scratch();
      _legacyPart(docs, 'Bracket',
          children: ['Sketch1', 'Sketch2'], importFile: 'flange.step');
      final app = _app(docs);

      expect(app.migrateLegacyDocuments(), 1);

      final doc = readDoc('${docs.path}/Bracket.$kPartExt')!;
      expect(doc.kind, 'part');
      expect(jsonDecode(doc.textOf(kMetaEntry)!)['name'], 'Bracket');
      expect(doc.textOf('sketches/Sketch1.dxf'), 'CHILD Sketch1');
      expect(doc.textOf('sketches/Sketch2.dxf'), 'CHILD Sketch2');
      expect(doc.textOf('sketches/Sketch1.cons.json'), '[]');
      expect(doc.textOf(kPreviewEntry), 'PARTPNG');
      expect(doc.textOf('imports/flange.step'), 'ISO-10303-21;',
          reason: 'an imported body would come back empty without its STEP');
      docs.deleteSync(recursive: true);
    });

    test('inserted images move into the document that uses them', () {
      // Images used to sit loose in the shared folder, so a sketch that was
      // moved or sent arrived with its pictures missing.
      final docs = _scratch();
      _legacySketch(docs, 'Plan', imageFile: 'img_1234.png');
      _app(docs).migrateLegacyDocuments();

      final doc = readDoc('${docs.path}/Plan.$kSketchExt')!;
      expect(doc.textOf('images/img_1234.png'), 'IMAGEBYTES');
      docs.deleteSync(recursive: true);
    });

    test('the old folder is PARKED, never deleted', () {
      final docs = _scratch();
      _legacySketch(docs, 'Flange');
      _app(docs).migrateLegacyDocuments();

      expect(Directory('${docs.path}/sketches').existsSync(), isFalse,
          reason: 'out of the gallery scan');
      final backup =
          File('${docs.path}/.cache/pre-m177-backup/Flange.dxf');
      expect(backup.existsSync(), isTrue,
          reason: 'if the migration got something subtly wrong, the '
              'originals must still be there to go back to');
      expect(backup.readAsStringSync(), 'DXFBODY');
      docs.deleteSync(recursive: true);
    });

    test('a mixed folder migrates parts and sketches together', () {
      final docs = _scratch();
      _legacyPart(docs, 'Bracket');
      _legacySketch(docs, 'Flange');
      _legacySketch(docs, 'Plate');

      expect(_app(docs).migrateLegacyDocuments(), 3);
      expect(_files(docs),
          ['Bracket.$kPartExt', 'Flange.$kSketchExt', 'Plate.$kSketchExt']);
      docs.deleteSync(recursive: true);
    });

    test('a part whose name also has a stray .dxf migrates ONCE, as a part', () {
      // A shared export leaves "<part>.dxf" beside "<part>.part.json"; that
      // export is not a second document.
      final docs = _scratch();
      _legacyPart(docs, 'Bracket');
      _write('${docs.path}/sketches/Bracket.dxf', 'STALE EXPORT');

      expect(_app(docs).migrateLegacyDocuments(), 1);
      expect(_files(docs), ['Bracket.$kPartExt']);
      docs.deleteSync(recursive: true);
    });

    test('running twice is harmless', () {
      final docs = _scratch();
      _legacySketch(docs, 'Flange');
      final app = _app(docs);
      expect(app.migrateLegacyDocuments(), 1);
      expect(app.migrateLegacyDocuments(), 0, reason: 'nothing left to do');
      expect(_files(docs), ['Flange.$kSketchExt']);
      docs.deleteSync(recursive: true);
    });

    test('an already-migrated document is never overwritten', () {
      // The previous launch wrote the document but could not park the folder.
      final docs = _scratch();
      _legacySketch(docs, 'Flange');
      writeDoc(
          '${docs.path}/Flange.$kSketchExt',
          DocFile('sketch',
              {'$kSketchBase.dxf': Uint8List.fromList(utf8.encode('NEWER'))}));

      _app(docs).migrateLegacyDocuments();

      expect(readDoc('${docs.path}/Flange.$kSketchExt')!.textOf('$kSketchBase.dxf'),
          'NEWER',
          reason: 'the migration must not clobber real work');
      docs.deleteSync(recursive: true);
    });

    test('no legacy folder is a no-op', () {
      final docs = _scratch();
      expect(_app(docs).migrateLegacyDocuments(), 0);
      expect(_files(docs), isEmpty);
      docs.deleteSync(recursive: true);
    });

    test('an empty legacy folder is parked without migrating anything', () {
      final docs = _scratch();
      Directory('${docs.path}/sketches').createSync(recursive: true);
      expect(_app(docs).migrateLegacyDocuments(), 0);
      expect(Directory('${docs.path}/sketches').existsSync(), isFalse);
      docs.deleteSync(recursive: true);
    });

    test('a migrated sketch opens with its geometry and layers intact',
        () async {
      final docs = _scratch();
      // Produce a REAL legacy layout by writing with the old code path: save
      // through the app, then move the document back out into sketches/.
      final maker = _app(docs);
      await maker.createNamedSketch('Real');
      maker.current!.engine.addLine(0, 0, 40, 0);
      maker.current!.engine.addLine(40, 0, 40, 25);
      maker.current!.refresh();
      await maker.saveSketch('Real');
      final doc = readDoc(maker.pathOfDocument('Real')!)!;
      File(maker.pathOfDocument('Real')!).deleteSync();
      final legacy = Directory('${docs.path}/sketches')
        ..createSync(recursive: true);
      for (final e in doc.entries.entries) {
        final name = e.key == kPreviewEntry
            ? 'Real.png'
            : 'Real${e.key.substring(kSketchBase.length)}';
        File('${legacy.path}/$name').writeAsBytesSync(e.value);
      }

      final app = _app(docs);
      expect(app.migrateLegacyDocuments(), 1);
      await app.refreshSaved();
      await app.openSketch('Real');
      expect(app.current!.geometry, hasLength(2),
          reason: 'the geometry survived the round trip through the document');
      docs.deleteSync(recursive: true);
    });
  });

  group('M177 the app folder is the library', () {
    test('a document dropped in is listed with no import step', () async {
      final docs = _scratch();
      final app = _app(docs);
      await app.refreshSaved();
      expect(app.saved, isEmpty);

      // AirDrop / Files: the file simply appears.
      writeDoc(
          '${docs.path}/Dropped.$kPartExt',
          DocFile('part',
              {kMetaEntry: Uint8List.fromList(utf8.encode('{"name":"x"}'))}));
      await app.refreshSaved();

      expect(app.saved.map((s) => s.name), ['Dropped']);
      expect(app.saved.single.kind, 'part');
      expect(app.isPartName('Dropped'), isTrue);
      docs.deleteSync(recursive: true);
    });

    test('the cache folder is never mistaken for a document', () async {
      final docs = _scratch();
      final app = _app(docs);
      await app.createNamedSketch('S');
      await app.saveSketch('S');
      await app.refreshSaved();
      expect(app.saved.map((s) => s.name), ['S']);
      expect(Directory('${docs.path}/.cache').existsSync(), isTrue);
      docs.deleteSync(recursive: true);
    });

    test('a foreign file in the folder is ignored', () async {
      final docs = _scratch();
      _write('${docs.path}/notes.txt', 'hello');
      _write('${docs.path}/render.png', 'x');
      final app = _app(docs);
      await app.refreshSaved();
      expect(app.saved, isEmpty);
      docs.deleteSync(recursive: true);
    });
  });

  group('M177 Open', () {
    test('a STEP or DXF is converted into a NEW document here', () async {
      final docs = _scratch();
      final source = _scratch();
      _write('${source.path}/flange.dxf', '0\nSECTION\n0\nENDSEC\n0\nEOF\n');
      final app = _app(docs);

      final name = await app.openPath('${source.path}/flange.dxf');

      expect(name, 'flange');
      expect(File('${docs.path}/flange.$kSketchExt').existsSync(), isTrue,
          reason: 'the import belongs in the app folder');
      expect(app.isExternal('flange'), isFalse);
      expect(File('${source.path}/flange.dxf').existsSync(), isTrue,
          reason: 'the source file is never touched');
      docs.deleteSync(recursive: true);
      source.deleteSync(recursive: true);
    });

    test('one of ours from elsewhere opens in place and is remembered',
        () async {
      final docs = _scratch();
      final elsewhere = _scratch();
      // A document the user made on another iPad and put in iCloud.
      final maker = _app(elsewhere);
      await maker.createNamedSketch('Adapter');
      maker.current!.engine.addLine(0, 0, 10, 0);
      maker.current!.refresh();
      await maker.saveSketch('Adapter');
      final external = '${elsewhere.path}/Adapter.$kSketchExt';

      final app = _app(docs);
      final name = await app.openPath(external);

      expect(name, 'Adapter');
      expect(app.isExternal('Adapter'), isTrue);
      expect(app.pathOfDocument('Adapter'), external);
      expect(File('${docs.path}/Adapter.$kSketchExt').existsSync(), isFalse,
          reason: 'opening must not fork an internal copy');
      expect(app.current!.geometry, hasLength(1));
      docs.deleteSync(recursive: true);
      elsewhere.deleteSync(recursive: true);
    });

    test('Save writes an external document BACK to where it came from',
        () async {
      final docs = _scratch();
      final elsewhere = _scratch();
      final maker = _app(elsewhere);
      await maker.createNamedSketch('Adapter');
      await maker.saveSketch('Adapter');
      final external = '${elsewhere.path}/Adapter.$kSketchExt';

      final app = _app(docs);
      await app.openPath(external);
      app.current!.engine.addCircle(5, 5, 3);
      app.current!.refresh();
      await app.saveCurrentDocument();

      expect(File('${docs.path}/Adapter.$kSketchExt').existsSync(), isFalse,
          reason: 'THE bug this exists to prevent: you edit a file, save, '
              'and your edits are not in the file you opened');
      final reopened = _app(docs);
      await reopened.openPath(external);
      expect(reopened.current!.geometry, hasLength(1));
      docs.deleteSync(recursive: true);
      elsewhere.deleteSync(recursive: true);
    });

    test('an external document is in the gallery on the NEXT launch', () async {
      final docs = _scratch();
      final elsewhere = _scratch();
      final maker = _app(elsewhere);
      await maker.createNamedPart('Housing');
      await maker.savePart('Housing');
      final external = '${elsewhere.path}/Housing.$kPartExt';

      final app = _app(docs);
      await app.openPath(external);

      // A cold app, same documents folder: the remembered list is on disk.
      final next = _app(docs);
      next.loadRememberedForTest();
      await next.refreshSaved();
      expect(next.saved.map((s) => s.name), ['Housing']);
      expect(next.isExternal('Housing'), isTrue);
      docs.deleteSync(recursive: true);
      elsewhere.deleteSync(recursive: true);
    });

    test('an external whose file has gone is dropped from the gallery',
        () async {
      final docs = _scratch();
      final elsewhere = _scratch();
      final maker = _app(elsewhere);
      await maker.createNamedSketch('Temp');
      await maker.saveSketch('Temp');
      final external = '${elsewhere.path}/Temp.$kSketchExt';

      final app = _app(docs);
      await app.openPath(external);
      File(external).deleteSync();

      final next = _app(docs);
      next.loadRememberedForTest();
      await next.refreshSaved();
      expect(next.saved, isEmpty);
      docs.deleteSync(recursive: true);
      elsewhere.deleteSync(recursive: true);
    });

    test('opening one of ours already in the app folder just opens it',
        () async {
      final docs = _scratch();
      final app = _app(docs);
      await app.createNamedSketch('Here');
      await app.saveSketch('Here');
      app.goHome();

      final name = await app.openPath('${docs.path}/Here.$kSketchExt');
      expect(name, 'Here');
      expect(app.isExternal('Here'), isFalse);
      expect(_files(docs), ['Here.$kSketchExt']);
      docs.deleteSync(recursive: true);
    });

    test('a picker copy in tmp is taken into the app folder, not remembered',
        () async {
      // What the ordinary iOS file picker actually hands over. Remembering it
      // would list a document the system is about to delete.
      final docs = _scratch();
      final maker = _app(_scratch());
      await maker.createNamedSketch('Adapter');
      maker.current!.engine.addLine(0, 0, 8, 0);
      maker.current!.refresh();
      await maker.saveSketch('Adapter');
      final pickerDir = Directory.systemTemp.createTempSync('pickercopy');
      final copy = '${pickerDir.path}/Adapter.$kSketchExt';
      File(maker.pathOfDocument('Adapter')!).copySync(copy);

      final app = _pickerApp(docs, pickerDir.path);
      final name = await app.openPath(copy);

      expect(name, 'Adapter');
      expect(app.isExternal('Adapter'), isFalse);
      expect(app.pathOfDocument('Adapter'), '${docs.path}/Adapter.$kSketchExt');
      expect(app.current!.geometry, hasLength(1),
          reason: 'the document itself came across, not just its name');
      docs.deleteSync(recursive: true);
    });

    test('adopting past a name that is taken keeps both documents', () async {
      final docs = _scratch();
      final app = _app(docs);
      await app.createNamedSketch('Adapter');
      await app.saveSketch('Adapter');

      final pickerDir = Directory.systemTemp.createTempSync('pickercopy');
      final copy = '${pickerDir.path}/Adapter.$kSketchExt';
      File(app.pathOfDocument('Adapter')!).copySync(copy);
      app.volatileDirsForTest = [pickerDir.path];

      expect(await app.openPath(copy), 'Adapter 2');
      expect(_files(docs),
          ['Adapter 2.$kSketchExt', 'Adapter.$kSketchExt']);
      docs.deleteSync(recursive: true);
    });

    test('a file we cannot read is refused, not half-opened', () async {
      final docs = _scratch();
      final source = _scratch();
      _write('${source.path}/notes.txt', 'hello');
      _write('${source.path}/broken.$kPartExt', 'not a document');
      final app = _app(docs);

      expect(await app.openPath('${source.path}/notes.txt'), isNull);
      expect(await app.openPath('${source.path}/broken.$kPartExt'), isNull);
      expect(app.saved, isEmpty);
      expect(app.curTab, isNull);
      docs.deleteSync(recursive: true);
      source.deleteSync(recursive: true);
    });

    test('an external and an internal of the same name both stay listed',
        () async {
      final docs = _scratch();
      final elsewhere = Directory('${_scratch().path}/Shared')
        ..createSync(recursive: true);
      final app = _app(docs);
      await app.createNamedSketch('Bracket');
      await app.saveSketch('Bracket');

      final maker = _app(elsewhere);
      await maker.createNamedSketch('Bracket');
      await maker.saveSketch('Bracket');

      await app.openPath('${elsewhere.path}/Bracket.$kSketchExt');
      expect(app.saved.map((s) => s.name),
          containsAll(['Bracket', 'Bracket (Shared)']),
          reason: 'neither may silently replace the other in the gallery');
      docs.deleteSync(recursive: true);
    });

    test('forgetting an external leaves the file alone', () async {
      final docs = _scratch();
      final elsewhere = _scratch();
      final maker = _app(elsewhere);
      await maker.createNamedSketch('Temp');
      await maker.saveSketch('Temp');
      final external = '${elsewhere.path}/Temp.$kSketchExt';

      final app = _app(docs);
      await app.openPath(external);
      app.goHome();
      await app.forgetExternal('Temp');

      expect(app.saved, isEmpty);
      expect(File(external).existsSync(), isTrue);
      docs.deleteSync(recursive: true);
      elsewhere.deleteSync(recursive: true);
    });
  });

  group('M177 documents are self-contained', () {
    test('a part round-trips through its file into a fresh app', () async {
      final docs = _scratch();
      final app = _app(docs);
      await app.createNamedPart('Bracket');
      app.startPartSketch();
      app.planePicked('xy');
      app.activeChild!.engine.addLine(0, 0, 20, 0);
      app.activeChild!.engine.addLine(20, 0, 20, 10);
      app.activeChild!.refresh();
      app.finishPartSketch();
      await app.savePart('Bracket');

      final next = _app(docs);
      await next.refreshSaved();
      await next.openPart('Bracket');
      final part = next.parts['Bracket']!;
      expect(part.childSketches, hasLength(1));
      expect(part.childSketches.single.model.geometry, hasLength(2));
      docs.deleteSync(recursive: true);
    });

    test('a deleted child sketch is not carried in the document forever',
        () async {
      final docs = _scratch();
      final app = _app(docs);
      await app.createNamedPart('P');
      app.startPartSketch();
      app.planePicked('xy');
      app.activeChild!.engine.addLine(0, 0, 5, 0);
      app.activeChild!.refresh();
      app.finishPartSketch();
      await app.savePart('P');
      final child = app.parts['P']!.childSketches.single.model.name;
      expect(readDoc(app.pathOfDocument('P')!)!.entries.keys,
          contains('sketches/$child.dxf'));

      app.parts['P']!.childSketches.clear();
      await app.savePart('P');
      expect(
          readDoc(app.pathOfDocument('P')!)!
              .entries
              .keys
              .where((k) => k.startsWith('sketches/')),
          isEmpty,
          reason: 'dead weight in every copy and every AirDrop');
      docs.deleteSync(recursive: true);
    });

    test('the staging folder is a cache: deleting it loses nothing', () async {
      final docs = _scratch();
      final app = _app(docs);
      await app.createNamedSketch('S');
      app.current!.engine.addLine(0, 0, 12, 0);
      app.current!.refresh();
      await app.saveSketch('S');

      final next = _app(docs);
      Directory('${docs.path}/.cache/docs').deleteSync(recursive: true);
      await next.refreshSaved();
      await next.openSketch('S');
      expect(next.current!.geometry, hasLength(1));
      docs.deleteSync(recursive: true);
    });
  });
}
