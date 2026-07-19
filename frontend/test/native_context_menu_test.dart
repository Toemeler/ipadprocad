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
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:ipadprocad/app_state.dart';
import 'package:ipadprocad/widgets/home_view.dart';
import 'package:native_menu/native_menu.dart';

Directory _scratch() => Directory.systemTemp.createTempSync('ipc_ctxmenu');

AppState _app(Directory docs) => AppState()..docsDirForTest = docs;

Directory _sketchDir(Directory docs) {
  final d = Directory('${docs.path}/sketches');
  d.createSync(recursive: true);
  return d;
}

/// Writes a placeholder for EVERY sidecar so the tests notice a suffix that
/// delete/rename/duplicate forgot to carry along.
void _fakeSketch(Directory docs, String name) {
  final d = _sketchDir(docs);
  for (final suffix in AppState.sketchFileSuffixes) {
    File('${d.path}/$name$suffix').writeAsStringSync('placeholder');
  }
}

List<String> _files(Directory docs) =>
    _sketchDir(docs).listSync().map((e) => e.uri.pathSegments.last).toList()
      ..sort();

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
      await NativeMenu.setTargets([
        NativeMenuTarget(id: 'a', rect: Rect.fromLTWH(0, 0, 1, 1), groups: [])
      ]);
      expect(await NativeMenu.shareFile('/nope', anchor: Rect.zero), isFalse);
      expect(await NativeMenu.exportFile('/nope', anchor: Rect.zero), isFalse);
      NativeMenu.setSelectionHandler((_, __) {});
      NativeMenu.setSelectionHandler(null);
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
      for (final f in _files(docs)) {
        expect(f, startsWith('Keeper'), reason: '$f survived the delete');
      }
      expect(_files(docs), hasLength(AppState.sketchFileSuffixes.length));
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
      expect(File('${_sketchDir(docs).path}/Live.dxf').existsSync(), isFalse);
      // The killer regression: any later autosave must not write it back.
      await app.saveSketch('Live');
      expect(File('${_sketchDir(docs).path}/Live.dxf').existsSync(), isFalse);
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
      for (final suffix in AppState.sketchFileSuffixes) {
        expect(File('${_sketchDir(docs).path}/New$suffix').existsSync(), isTrue,
            reason: '$suffix did not follow the rename');
        expect(File('${_sketchDir(docs).path}/Old$suffix').existsSync(), isFalse,
            reason: '$suffix left behind under the old name');
      }
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
      expect(File('${_sketchDir(docs).path}/A.dxf').existsSync(), isTrue);
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

      for (final suffix in AppState.sketchFileSuffixes) {
        expect(File('${_sketchDir(docs).path}/Plate$suffix').existsSync(), isTrue);
        expect(File('${_sketchDir(docs).path}/Plate copy$suffix').existsSync(),
            isTrue,
            reason: '$suffix was not duplicated');
      }
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
