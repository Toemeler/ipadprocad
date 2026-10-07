// A document whose file is there but cannot be read whole is REFUSED, never
// opened as an empty document — and never written over.
//
// Before: a damaged .ptp (garbage, a copy cut short by an interrupted sync,
// part data that does not parse) opened silently as an empty part, and the
// save on close packed that empty part over the file. What a repair, an
// older backup or the other device could still have given back was gone.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/l10n/l.dart';

void damage(String path, String how) {
  final good = File(path).readAsBytesSync();
  switch (how) {
    case 'garbage':
      File(path).writeAsBytesSync(List.filled(200, 0x41));
    case 'truncated':
      File(path).writeAsBytesSync(good.sublist(0, good.length - 40));
    case 'bad json':
      // the container is fine; the document's own data is not
      final doc = DocFile.decode(Uint8List.fromList(good))!;
      final entries = {...doc.entries};
      final key = entries.keys.firstWhere((k) => k.endsWith('.json'));
      entries[key] = Uint8List.fromList(utf8.encode('{"features": ['));
      File(path).writeAsBytesSync(DocFile(doc.kind, entries).encode());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in ['part', 'assembly', 'sketch']) {
    for (final how in ['garbage', 'truncated', 'bad json']) {
      if (kind == 'sketch' && how == 'bad json') continue;
      test('a $how $kind is refused and left as it is', () async {
        final dir = Directory.systemTemp.createTempSync('m475_');
        final app = AppState()..docsDirForTest = dir;
        switch (kind) {
          case 'part':
            await app.createNamedPart('D');
          case 'assembly':
            await app.createNamedAssembly('D');
          default:
            await app.createNamedSketch('D');
        }
        await app.closeTab('D');
        final path = app.pathOfDocument('D')!;
        damage(path, how);
        final bad = File(path).readAsBytesSync();

        final app2 = AppState()..docsDirForTest = dir;
        await app2.refreshSaved();
        expect(app2.saved.map((s) => s.name), contains('D'),
            reason: 'still listed, so the user can delete or replace it');
        await app2.openDocument('D');
        expect(app2.openTabs, isNot(contains('D')));
        expect(app2.isUnreadable('D'), isTrue);
        expect(app2.message, L.current.msgCouldNotOpenDoc);
        await app2.flushAllDocuments();
        expect(File(path).readAsBytesSync(), bad,
            reason: 'the damaged file must not be overwritten');
      });
    }
  }

  test('a file that is repaired since opens on the next try', () async {
    final dir = Directory.systemTemp.createTempSync('m475r_');
    final app = AppState()..docsDirForTest = dir;
    await app.createNamedPart('D');
    await app.closeTab('D');
    final path = app.pathOfDocument('D')!;
    final good = File(path).readAsBytesSync();
    damage(path, 'truncated');
    final app2 = AppState()..docsDirForTest = dir;
    await app2.refreshSaved();
    await app2.openDocument('D');
    expect(app2.openTabs, isNot(contains('D')));
    File(path).writeAsBytesSync(good);
    await app2.openDocument('D');
    expect(app2.openTabs, contains('D'));
    expect(app2.isUnreadable('D'), isFalse);
  });

  // The drawing reads but the constraints / parameters beside it do not.
  // Before: the sketch opened with every constraint and dimension silently
  // gone, and the next save wrote it that way over the file.
  void damageEntry(String path, String suffix) {
    final doc = DocFile.decode(File(path).readAsBytesSync())!;
    final entries = {...doc.entries};
    final keys = entries.keys.where((k) => k.endsWith(suffix)).toList();
    expect(keys, isNotEmpty, reason: 'the document has a $suffix entry');
    for (final k in keys) {
      entries[k] = Uint8List.fromList(utf8.encode('[{"t": 3, "p": [{"e"'));
    }
    File(path).writeAsBytesSync(DocFile(doc.kind, entries).encode());
  }

  for (final suffix in ['.cons.json', '.params.json']) {
    test('a sketch whose $suffix is damaged is refused, not opened bare',
        () async {
      final dir = Directory.systemTemp.createTempSync('m475s_');
      final app = AppState()..docsDirForTest = dir;
      await app.createNamedSketch('D');
      await app.closeTab('D');
      final path = app.pathOfDocument('D')!;
      damageEntry(path, suffix);
      final bad = File(path).readAsBytesSync();

      final app2 = AppState()..docsDirForTest = dir;
      await app2.refreshSaved();
      await app2.openDocument('D');
      expect(app2.openTabs, isNot(contains('D')));
      expect(app2.isUnreadable('D'), isTrue);
      expect(app2.message, L.current.msgCouldNotOpenDoc);
      await app2.flushAllDocuments();
      expect(File(path).readAsBytesSync(), bad);
    });
  }

  test('a part whose sketch constraints are damaged is refused', () async {
    final dir = Directory.systemTemp.createTempSync('m475p_');
    final app = AppState()..docsDirForTest = dir;
    await app.createNamedPart('D');
    final made = await AiCad(app).run([
      const AiAction('create_sketch', {'plane': 'xy'}),
      const AiAction('sketch_rect', {'width': 40, 'height': 30}),
    ]);
    expect(made.ok, isTrue, reason: made.encode());
    expect(
        app.currentPart!.childSketches.single.model.constraints, isNotEmpty);
    await app.closeTab('D');
    final path = app.pathOfDocument('D')!;
    damageEntry(path, '.cons.json');
    final bad = File(path).readAsBytesSync();

    final app2 = AppState()..docsDirForTest = dir;
    await app2.refreshSaved();
    await app2.openDocument('D');
    expect(app2.openTabs, isNot(contains('D')));
    expect(app2.isUnreadable('D'), isTrue);
    await app2.flushAllDocuments();
    expect(File(path).readAsBytesSync(), bad);
  });
}
