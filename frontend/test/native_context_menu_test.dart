// Native gallery context menu (long-press a sketch card on the Home tab).
//
// The UIKit half cannot run on the host, so what is pinned here is everything
// the device build depends on:
//
//   * the MENU CONTRACT — ids, order, sections, and the destructive flag that
//     makes UIKit paint Delete red. The Swift side does not know these strings;
//     home_view and the selection handler are the only source of truth.
//   * the WIRE FORMAT — NativeMenuTarget.toMap() keys are parsed verbatim by
//     NativeMenuPlugin.parseTarget. Renaming one silently kills the menu on the
//     device while every host test stays green, so it is asserted explicitly.
//   * the FILE OPERATIONS behind the five menu items. These touch real files
//     and the open-tab bookkeeping, which is where the damage would be.
//
// Off iOS every NativeMenu entry point must be a silent no-op — the suite runs
// on Linux/macOS and must never see a MissingPluginException.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/doc_store.dart';
import 'package:prototype/widgets/home_view.dart';
import 'package:native_menu/native_menu.dart';

Directory _scratch() => Directory.systemTemp.createTempSync('ipc_ctxmenu');

AppState _app(Directory docs) => AppState()..docsDirForTest = docs;

/// Writes a sketch document carrying a placeholder for EVERY sidecar, so the
/// tests notice anything delete / rename / duplicate forgot to carry along.
///
/// M177 — a sketch is one .pts file now, and everything that belongs to it is
/// an entry inside that file. That is exactly what makes these operations
/// hard to get wrong: there is nothing beside the document to leave behind.
void _fakeSketch(Directory docs, String name) {
  writeDoc(
      '${docs.path}/$name.$kSketchExt',
      DocFile('sketch', {
        for (final suffix in AppState.sketchFileSuffixes)
          (suffix == '.png' ? kPreviewEntry : '$kSketchBase$suffix'):
              Uint8List.fromList(utf8.encode('placeholder')),
      }));
}

/// The documents in the app folder.
List<String> _files(Directory docs) => [
      for (final e in docs.listSync())
        if (e is File) e.uri.pathSegments.last
    ]..sort();

/// Every entry inside document [name]'s file.
Set<String> _entriesOf(Directory docs, String name, {String ext = kSketchExt}) =>
    readDoc('${docs.path}/$name.$ext')?.entries.keys.toSet() ?? {};

/// The entry names _fakeSketch writes.
Set<String> get _allEntries => {
      for (final suffix in AppState.sketchFileSuffixes)
        suffix == '.png' ? kPreviewEntry : '$kSketchBase$suffix'
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('menu contract', () {
    test('five items in two sections, delete destructive and alone', () {
      final groups = sketchMenuGroups();
      expect(groups, hasLength(2),
          reason: 'a second section is what separates Delete visually');
      expect([for (final i in groups[0]) i.id],
          ['rename', 'duplicate', 'export', 'share']);
      expect([for (final i in groups[1]) i.id], ['delete']);

      final all = [for (final g in groups) ...g];
      expect(all, hasLength(5));
      // UIKit colours a destructive row red on its own; nothing else may claim
      // the flag or the whole menu turns into a wall of red.
      expect(all.where((i) => i.destructive).map((i) => i.id), ['delete']);
      for (final i in all) {
        expect(i.title, isNotEmpty);
        expect(i.symbol, isNotNull, reason: '${i.id} needs an SF Symbol');
      }
    });
  });

  group('wire format', () {
    test('toMap emits exactly the keys the Swift parser reads', () {
      final target = NativeMenuTarget(
        id: 'Bracket_v2',
        title: 'Bracket_v2',
        rect: Rect.fromLTWH(10, 20, 250, 200),
        previewRect: Rect.fromLTWH(10, 20, 250, 158),
        cornerRadius: 14,
        previewImagePath: '/tmp/Bracket_v2.png',
        groups: [
          [NativeMenuItem(id: 'delete', title: 'Delete', symbol: 'trash', destructive: true)]
        ],
      );
      final m = target.toMap();
      expect(m['id'], 'Bracket_v2');
      expect(m['title'], 'Bracket_v2');
      expect(m['cornerRadius'], 14);
      expect(m['previewImagePath'], '/tmp/Bracket_v2.png');
      expect(m['rect'],
          {'left': 10.0, 'top': 20.0, 'width': 250.0, 'height': 200.0});
      expect((m['previewRect']! as Map)['height'], 158.0);

      final item = ((m['groups']! as List).first as List).first as Map;
      expect(item['id'], 'delete');
      expect(item['symbol'], 'trash');
      expect(item['destructive'], true);
    });

    test('ids travel scope-prefixed so a selection can be routed back', () {
      final t = NativeMenuTarget(
          id: 'Layer 1', rect: Rect.fromLTWH(0, 0, 2, 2), groups: const []);
      expect(t.toMap()['id'], 'Layer 1', reason: 'no prefix by default');
      expect(t.toMap(idPrefix: 'layers\u0001')['id'], 'layers\u0001Layer 1');
    });

    test('previewRect defaults to rect when omitted', () {
      final t = NativeMenuTarget(
          id: 'x', rect: Rect.fromLTWH(0, 0, 5, 6), groups: []);
      expect(t.toMap()['previewRect'], t.toMap()['rect']);
    });
  });

  group('off iOS the plugin is inert', () {
    test('isSupported is false and no call throws', () async {
      expect(NativeMenu.isSupported, isFalse);
      // Would raise MissingPluginException if the guard were ever removed.
      await NativeMenu.setTargets(NativeMenu.kGallery, [
        NativeMenuTarget(id: 'a', rect: Rect.fromLTWH(0, 0, 1, 1), groups: [])
      ]);
      expect(await NativeMenu.shareFile('/nope', anchor: Rect.zero), isFalse);
      expect(await NativeMenu.exportFile('/nope', anchor: Rect.zero), isFalse);
      expect(await NativeMenu.promptText(title: 'x'), isNull);
      expect(
          await NativeMenu.confirm(title: 'x', confirmLabel: 'y'), isFalse);
      NativeMenu.setSelectionHandler(NativeMenu.kGallery, (_, __) {});
      NativeMenu.setSelectionHandler(NativeMenu.kGallery, null);
      NativeMenu.resetForTest();
    });
  });

  group('delete', () {
    test('removes every sidecar and drops it from the gallery', () async {
      final docs = _scratch();
      final app = _app(docs);
      _fakeSketch(docs, 'Flange');
      _fakeSketch(docs, 'Keeper');
      await app.refreshSaved();
      expect(app.saved.map((s) => s.name), containsAll(['Flange', 'Keeper']));

      await app.deleteSketch('Flange');

      expect(app.saved.map((s) => s.name), ['Keeper']);
      expect(_files(docs), ['Keeper.$kSketchExt'],
          reason: 'the whole document goes, and only that document');
    });

    test('an OPEN sketch is closed first so autosave cannot resurrect it',
        () async {
      final docs = _scratch();
      final app = _app(docs);
      await app.openSketch('Live');
      await app.saveSketch('Live');
      expect(app.curTab, 'Live');

      await app.deleteSketch('Live');

      expect(app.openTabs, isNot(contains('Live')));
      expect(app.curTab, isNull);
      expect(app.isHome, isTrue);
      expect(_files(docs), isEmpty);
      // The killer regression: any later autosave must not write it back.
      await app.saveSketch('Live');
      expect(_files(docs), isEmpty);
    });
  });

  group('rename', () {
    test('carries every sidecar across', () async {
      final docs = _scratch();
      final app = _app(docs);
      _fakeSketch(docs, 'Old');
      await app.refreshSaved();

      expect(await app.renameSketch('Old', 'New'), isTrue);

      expect(app.saved.map((s) => s.name), ['New']);
      expect(_files(docs), ['New.$kSketchExt'],
          reason: 'nothing may be left behind under the old name');
      expect(_entriesOf(docs, 'New'), _allEntries,
          reason: 'the rename must not lose anything inside the document');
    });

    test('refuses collisions and names that could escape the directory',
        () async {
      final docs = _scratch();
      final app = _app(docs);
      _fakeSketch(docs, 'A');
      _fakeSketch(docs, 'B');
      await app.refreshSaved();

      expect(await app.renameSketch('A', 'B'), isFalse, reason: 'collision');
      expect(await app.renameSketch('A', '  '), isFalse, reason: 'blank');
      expect(await app.renameSketch('A', '../escape'), isFalse, reason: 'path');
      expect(await app.renameSketch('A', '.hidden'), isFalse, reason: 'dotfile');
      // Nothing moved.
      expect(_files(docs), ['A.$kSketchExt', 'B.$kSketchExt']);
      expect(app.saved.map((s) => s.name), containsAll(['A', 'B']));

      expect(app.validateSketchName('Bracket v2'), isNull);
      expect(app.validateSketchName('a/b'), isNotNull);
    });

    test('an open sketch stays open, under the new name', () async {
      final docs = _scratch();
      final app = _app(docs);
      await app.openSketch('Before');
      await app.saveSketch('Before');

      expect(await app.renameSketch('Before', 'After'), isTrue);

      expect(app.openTabs, contains('After'));
      expect(app.openTabs, isNot(contains('Before')));
      expect(app.curTab, 'After');
      expect(app.sketches.containsKey('Before'), isFalse);
    });
  });

  group('duplicate', () {
    test('copies every sidecar and leaves the original alone', () async {
      final docs = _scratch();
      final app = _app(docs);
      _fakeSketch(docs, 'Plate');
      await app.refreshSaved();

      expect(await app.duplicateSketch('Plate'), 'Plate copy');

      expect(_entriesOf(docs, 'Plate'), _allEntries,
          reason: 'the original is untouched');
      expect(_entriesOf(docs, 'Plate copy'), _allEntries,
          reason: 'the copy carries everything the original had');
      expect(app.saved.map((s) => s.name), containsAll(['Plate', 'Plate copy']));
    });

    test('walks past names that are already taken', () async {
      final docs = _scratch();
      final app = _app(docs);
      _fakeSketch(docs, 'Plate');
      await app.refreshSaved();

      expect(await app.duplicateSketch('Plate'), 'Plate copy');
      expect(await app.duplicateSketch('Plate'), 'Plate copy 2');
      expect(await app.duplicateSketch('Plate'), 'Plate copy 3');
    });

    test('a sketch with no file on disk cannot be duplicated', () async {
      final docs = _scratch();
      final app = _app(docs);
      expect(await app.duplicateSketch('Ghost'), isNull);
    });
  });

  group('export path', () {
    test('flushes an open sketch and hands back its DXF', () async {
      final docs = _scratch();
      final app = _app(docs);
      await app.openSketch('Shipme');

      final path = await app.sketchExportPath('Shipme');

      expect(path, isNotNull);
      expect(path, endsWith('Shipme.dxf'));
      expect(File(path!).existsSync(), isTrue,
          reason: 'export must never hand out a path that is not on disk yet');
    });

    test('is null for an unknown sketch', () async {
      final docs = _scratch();
      expect(await _app(docs).sketchExportPath('Nope'), isNull);
    });
  });
}
