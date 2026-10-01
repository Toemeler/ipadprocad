// M468 — Open takes an Autodesk Inventor part (.ipt) directly, and Export
// gives it back.
//
// Needs the native kernel (PROTOTYPE_NATIVE_DIR) and an Inventor part
// (IPT_FIXTURE: a .ipt). Both are machine-local, so the test skips without
// them; the pieces it is built from are covered without them by m467 (zstd)
// and m469 (container, sketches, export rule).
//
// What it pins down:
//   * Open converts the .ipt into a NEW part, in the app folder, with every
//     sketch and feature of Inventor's tree and no feature in error;
//   * the bodies on screen are Inventor's exact bodies (the stored results);
//   * every sketch is exactly as Inventor solved it -- the solver moves
//     nothing;
//   * Export -> IPT writes the original back byte for byte while the part is
//     unchanged, and refuses once an edit made the original stale.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/doc_store.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/inventor/convert.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/solver.dart';

import 'support/native_host.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture = Platform.environment['IPT_FIXTURE'] ?? '';

  test('an .ipt opens as a part with its tree, and exports back unchanged', () async {
    if (!kNativeHost || fixture.isEmpty || !File(fixture).existsSync()) {
      return markTestSkipped('needs PROTOTYPE_NATIVE_DIR and IPT_FIXTURE');
    }
    final app = AppState()..partKernel = OcctPartKernel();
    expect(app.partKernel.available, isTrue);
    final dir = Directory.systemTemp.createTempSync('prototype_m468_');
    app.docsDirForTest = dir;
    await app.refreshSaved();

    final name = await app.importAsNewDocument(fixture);
    expect(name, isNotNull);
    expect(File('${dir.path}/$name.$kPartExt').existsSync(), isTrue,
        reason: 'a new part in the app folder');
    final p = app.currentPart!;
    final doc = readDoc('${dir.path}/$name.$kPartExt')!;
    final info = jsonDecode(utf8.decode(doc.entries[kIptInfoEntry]!)) as Map;
    expect(info['converter'], kIptConverterFull, reason: 'the full tree, not just bodies');

    // the tree
    final tree = [for (final f in info['features'] as List) (f as List)[0]];
    expect([for (final f in p.features) f.name], tree);
    expect(p.features.whereType<ExtrudeFeature>(), isNotEmpty);
    expect(p.features.whereType<FilletFeature>(), isNotEmpty);
    for (final f in p.features) {
      expect(f.computeError, isNull, reason: '${f.name}: ${f.computeError}');
    }
    // the bodies are Inventor's
    final cached = [for (final f in p.features) if (f.resultCache != null) f];
    expect(cached.length, (info['bodies'] as List).length);
    for (final f in cached) {
      expect(f.solid, isNotNull);
      expect(identical(f.solid, f.resultCache!.solid), isTrue);
    }
    // the sketches, as Inventor solved them
    expect(p.childSketches, isNotEmpty);
    for (final c in p.childSketches) {
      expect(c.model.geometry, isNotEmpty);
      final before = [for (final g in c.model.geometry) List<double>.of(g.data)];
      final gs = List.of(c.model.geometry);
      expect(solveConstraints(gs, c.model.constraints), isTrue);
      var moved = 0.0;
      for (var i = 0; i < gs.length; i++) {
        for (var k = 0; k < before[i].length && k < gs[i].data.length; k++) {
          moved = [moved, (gs[i].data[k] - before[i][k]).abs()].reduce((a, b) => a > b ? a : b);
        }
      }
      expect(moved, lessThan(1e-6), reason: '${c.model.name}: nothing moves');
    }

    // back out as the .ipt it was
    expect(app.partCameFromInventor(name!), isTrue);
    final out = await app.partExportIpt(name);
    expect(out, isNotNull);
    expect(File(out!).readAsBytesSync(), File(fixture).readAsBytesSync(),
        reason: 'the Inventor original, byte for byte');

    // Inventor's results survive a save and a reopen: the document's numbers
    // lose their last digits on the way, the stored results must not care
    await app.closeTab(name);
    await app.openDocument(name);
    final q = app.currentPart!;
    expect([for (final f in q.features) if (f.resultCache?.solid != null) f.name],
        [for (final f in cached) f.name],
        reason: 'still Inventor\'s bodies after a reopen');
    recomputeAllFeatures(q, app.partKernel, force: true);
    expect([for (final f in q.features) if (f.resultCache?.solid != null) f.name],
        [for (final f in cached) f.name],
        reason: 'and after a forced rebuild');

    // an edit rebuilds the tree in the app's kernel: every extrusion builds,
    // and a blend the kernel cannot make is a sick feature, not a dead body
    final cut = q.features.whereType<ExtrudeFeature>().firstWhere((f) => f.output == 'cut');
    cut.distanceA = cut.distanceA + 0.5;
    recomputeAllFeatures(q, app.partKernel, force: true);
    for (final f in q.features.whereType<ExtrudeFeature>()) {
      expect(f.computeError, isNull, reason: '${f.name}: ${f.computeError}');
      expect(f.solid, isNotNull, reason: f.name);
    }
    for (final f in q.features) {
      expect(f.computeError ?? '', isNot(contains('nothing further')), reason: f.name);
    }

    // ... and the original is stale now, so it is not handed out
    expect(await app.partExportIpt(name), isNull);
  }, timeout: const Timeout(Duration(minutes: 10)));
}
