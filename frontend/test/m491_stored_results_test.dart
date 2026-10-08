// Opening a part does not rebuild it.
//
// Every open used to rebuild every feature from nothing (the document holds
// the tree, not the B-Rep): a plate with 30 holes, a 120-hole pattern and a
// fillet took 5-6 s. Saving now stores each body's built result next to the
// tree (results/, see stored_results.dart) and opening uses it while the
// tree is still the one it was built from. The contract pinned here:
//   * reopening an unchanged part computes NO feature, and the body is the
//     one that was saved;
//   * an edit after reopening rebuilds and gives the same body a fresh build
//     gives;
//   * a stored result that does not fit (another kernel, damaged or missing
//     file, wrong volume, other tree) is ignored and the tree is rebuilt;
//   * the feature JSON does not change, and the first undo after opening
//     does not rebuild the chain either.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/doc_store.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/perf.dart';
import 'package:prototype/stored_results.dart';

/// A kernel whose "B-Rep" is its volume: export writes it to the file and
/// import reads it back, so a stored result round-trips like a real one.
class _Kernel implements PartKernel {
  _Kernel([this.info = 'fake-kernel-1']);

  int extrudes = 0;
  int imports = 0;

  @override
  final String info;

  @override
  bool get available => true;
  @override
  String get lastError => 'fake failure';

  KernelSolid stub(double v) => KernelSolid(
      OcctMeshData(Float64List(0), Float64List(0), Int32List(0),
          Int32List.fromList(const [0]), Float64List(0)),
      v,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
      double taperDeg, List<double> mat34) {
    extrudes++;
    return stub(height);
  }

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) =>
      stub(a.volume + b.volume);

  @override
  KernelSolid? cutSolids(KernelSolid a, KernelSolid b) =>
      stub(a.volume - b.volume);

  @override
  bool exportStep(List<KernelSolid> solids, String path) {
    File(path).writeAsStringSync(
        'FAKESTEP ${[for (final s in solids) s.volume].join(' ')}');
    return true;
  }

  @override
  List<KernelSolid> importStepSolids(String path) {
    imports++;
    final t = File(path).readAsStringSync().split(' ');
    if (t.first != 'FAKESTEP') return const [];
    return [for (final v in t.skip(1)) stub(double.parse(v))];
  }

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

Future<AppState> _app(_Kernel k, Directory docs, int n,
    {bool spareSketch = false}) async {
  final app = AppState()..partKernel = k;
  app.docsDirForTest = docs;
  await app.createNamedPart('P');
  for (var i = 1; i <= n; i++) {
    app.startPartSketch();
    app.planePicked('xy');
    final s = app.activeChild!;
    s.engine.setCurrentLayer(app.editingLayer!);
    s.engine.addLine(0, 0, 20, 0);
    s.engine.addLine(20, 0, 20, 10);
    s.engine.addLine(20, 10, 0, 10);
    s.engine.addLine(0, 10, 0, 0);
    s.refresh();
    app.finishPartSketch();
    final p = app.currentPart!;
    final f = ExtrudeFeature(
        name: 'Extrusion$i',
        bodyName: 'Solid1',
        sketchName: p.childSketches.last.model.name,
        profiles: [ProfileSel(10, 5, 200)],
        distanceA: i.toDouble());
    f.output = i == 1 ? 'new' : 'join';
    f.seq = p.nextSeq();
    p.appendFeature(f);
    recomputeAllFeatures(p, k);
  }
  if (spareSketch) {
    app.startPartSketch();
    app.planePicked('xz');
    final s = app.activeChild!;
    s.engine.setCurrentLayer(app.editingLayer!);
    s.engine.addLine(0, 0, 5, 5);
    s.refresh();
    app.finishPartSketch();
  }
  await app.savePart('P');
  return app;
}

/// Reopens 'P' in a fresh app over the same documents.
Future<AppState> _reopen(_Kernel k, Directory docs) async {
  final app = AppState()..partKernel = k;
  app.docsDirForTest = docs;
  await app.refreshSaved();
  await app.openPart('P');
  return app;
}

double _bodyVolume(PartModel p) =>
    p.features.lastWhere((f) => f.solid != null).solid!.volume;

/// The packed document's entries, by name.
Map<String, Uint8List> _entries(AppState app) =>
    readDoc(app.library['P']!.path)!.entries;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reopening an unchanged part computes no feature', () async {
    final docs = Directory.systemTemp.createTempSync('prototype_m491_');
    final k = _Kernel();
    final a = await _app(k, docs, 3);
    expect(_bodyVolume(a.currentPart!), 6);
    final e = _entries(a);
    expect(e.keys.where((n) => n.startsWith('results/')), hasLength(2),
        reason: 'one body: its index and its stored result');
    final meta = utf8.decode(e[kMetaEntry]!);
    expect(meta.contains('"cache"'), isFalse,
        reason: 'the stored result is not part of the model');

    k.extrudes = 0;
    final b = await _reopen(k, docs);
    final p = b.currentPart!;
    expect(k.extrudes, 0, reason: 'nothing is rebuilt on open');
    expect(_bodyVolume(p), 6);
    expect(p.features.every((f) => f.computeError == null), isTrue);

    // Saving the reopened part keeps the stored result (same key: same file).
    k.imports = 0;
    p.dirty = true;
    await b.savePart('P');
    final again = await _reopen(k, docs);
    expect(k.extrudes, 0);
    expect(_bodyVolume(again.currentPart!), 6);
  });

  test('an edit after reopening rebuilds, and right', () async {
    final docs = Directory.systemTemp.createTempSync('prototype_m491_');
    final k = _Kernel();
    await _app(k, docs, 3);
    final b = await _reopen(k, docs);
    final p = b.currentPart!;
    k.extrudes = 0;
    (p.features[1] as ExtrudeFeature).distanceA = 7;
    recomputeAllFeatures(p, k);
    expect(_bodyVolume(p), 1 + 7 + 3);
    expect(k.extrudes, 3, reason: 'the stored result no longer applies');
    await b.savePart('P');
    k.extrudes = 0;
    final c = await _reopen(k, docs);
    expect(k.extrudes, 0, reason: 'the edited body was stored in its place');
    expect(_bodyVolume(c.currentPart!), 11);
    final names = _entries(c).keys.where((n) => n.endsWith('.step.gz'));
    expect(names, hasLength(1), reason: 'the stale body was dropped');
  });

  test('a stored result that does not fit is ignored', () async {
    Future<void> check(String why, void Function(Directory stage) spoil,
        {_Kernel? reader}) async {
      final docs = Directory.systemTemp.createTempSync('prototype_m491_');
      final k = _Kernel();
      final a = await _app(k, docs, 3);
      // Spoil the packed document's results/ the way [spoil] says.
      final path = a.library['P']!.path;
      final stage = Directory.systemTemp.createTempSync('prototype_m491s_');
      unpackDoc(readDoc(path)!, stage);
      spoil(Directory('${stage.path}/results'));
      writeDoc(path, packDir(stage, 'part'));
      final r = reader ?? k;
      r.extrudes = 0;
      final b = await _reopen(r, docs);
      expect(r.extrudes, 3, reason: '$why: rebuilt');
      expect(_bodyVolume(b.currentPart!), 6, reason: why);
    }

    File body(Directory d) =>
        d.listSync().whereType<File>().firstWhere((f) => f.path.endsWith('.gz'));
    await check('another kernel build', (_) {}, reader: _Kernel('fake-kernel-2'));
    await check('a damaged file', (d) => body(d).writeAsStringSync('garbage'));
    await check('a missing file', (d) => body(d).deleteSync());
    await check('a body of another volume', (d) {
      body(d).writeAsBytesSync(gzip.encode(utf8.encode('FAKESTEP 999')));
    });
    await check('a damaged index',
        (d) => File('${d.path}/index.json').writeAsStringSync('{"format":'));
    await check('a result keyed to another tree', (d) {
      final f = File('${d.path}/index.json');
      f.writeAsStringSync(f.readAsStringSync().replaceAll(
          RegExp(r'"sig":"[0-9a-f]+"'), '"sig":"${'0' * 64}"'));
    });
  });

  test('the first undo after reopening does not rebuild the chain', () async {
    final docs = Directory.systemTemp.createTempSync('prototype_m491_');
    final k = _Kernel();
    await _app(k, docs, 3, spareSketch: true);
    final b = await _reopen(k, docs);
    final p = b.currentPart!;
    final spare = p.childSketches.last;
    expect(firstConsumerOf(p, spare.model.name), isNull);
    expect(b.deleteChildSketch(spare), isTrue);
    k.extrudes = 0;
    await b.undoPart();
    expect(b.currentPart!.childSketches, hasLength(4));
    expect(k.extrudes, 0, reason: 'the stored result came back with the step');
    expect(_bodyVolume(b.currentPart!), 6);
  });

  test('entries round-trip, and foreign file names are refused', () {
    const s = FaceSurface(3, 1, Vec3(1, 2, 3), Vec3(0, 0, 1), 2.5,
        Vec3(-1, -1, -1), Vec3(1, 1, 1), Vec3(0, 0, 0.5), 7);
    final back = faceSurfaceFromList(faceSurfaceToList(s))!;
    expect(back.sameSurfaceAs(s, 1e-9), isTrue);
    expect(back.area, 7);
    final idx = decodeStoredResultsIndex(
        jsonEncode({
          'format': kStoredResultsFormat,
          'kernel': 'k',
          'bodies': [
            {
              'feature': 'F', 'kind': 'extrude', 'body': 'Solid1', //
              'sig': 'ab', 'file': '../../etc/x.step.gz', 'volume': 1,
            }
          ],
        }),
        'k');
    expect(idx, isEmpty);
  });

  group('on the real kernel', () {
    final kernel = OcctPartKernel();
    final skip = kernel.available
        ? false
        : 'no kernel library — set PROTOTYPE_NATIVE_DIR (see LINUX.md)';

    int kernelFeatures() => Perf.stats['kernel.feature']?.count ?? 0;

    Future<AppState> open(Directory docs) async {
      final app = AppState()..partKernel = kernel;
      app.docsDirForTest = docs;
      await app.refreshSaved();
      await app.openPart('Plate');
      return app;
    }

    test('a plate with holes, a pattern and a fillet opens without a rebuild',
        () async {
      final docs = Directory.systemTemp.createTempSync('prototype_m491k_');
      final app = AppState()..partKernel = kernel;
      app.docsDirForTest = docs;
      await app.createNamedPart('Plate');
      final r = await AiCad(app).run(const [
        AiAction('create_sketch', {'plane': 'xz'}),
        AiAction('sketch_rect', {'width': 120, 'height': 80}),
        AiAction('extrude', {'distance': 10}),
        AiAction('hole', {
          'places': [
            [15, 15],
            [35, 15]
          ],
          'diameter': 5,
          'through_all': true
        }),
        AiAction('hole', {
          'places': [
            [20, 40]
          ],
          'diameter': 4,
          'through_all': true
        }),
        AiAction('pattern', {
          'kind': 'rect', 'features': ['Hole2'], //
          'direction': 'x', 'count': 4, 'spacing': 20,
          'direction2': 'z', 'count2': 2, 'spacing2': 15,
        }),
        AiAction('fillet', {'edges': 'vertical', 'radius': 3}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      final p = app.currentPart!;
      final n = p.features.length;
      final end = p.features.last;
      final volume = end.solid!.volume;
      final faces = attributeFaces(p, end.bodyName, end.solid!);
      final byFeature = <String, int>{};
      for (final v in faces.values) {
        byFeature[v] = (byFeature[v] ?? 0) + 1;
      }
      await app.savePart('Plate');
      await app.closeTab('Plate');

      Perf.resetForTest();
      final b = await open(docs);
      final q = b.currentPart!;
      expect(kernelFeatures(), 0, reason: 'nothing is rebuilt on open');
      expect(q.features, hasLength(n));
      final qEnd = q.features.last;
      expect(qEnd.solid!.volume, closeTo(volume, 1e-6 * volume));
      expect(q.features.every((f) => f.computeError == null), isTrue);
      // Clicking a face still selects the feature that made it.
      final qFaces = attributeFaces(q, qEnd.bodyName, qEnd.solid!);
      final qBy = <String, int>{};
      for (final v in qFaces.values) {
        qBy[v] = (qBy[v] ?? 0) + 1;
      }
      expect(qBy, byFeature);
      expect((q.features.whereType<PatternFeature>().single).occurrenceCount, 8);

      // Editing the first hole rebuilds the chain from it and gives the body
      // a fresh build gives.
      final hole = q.features.whereType<HoleFeature>().first;
      hole.dia = 6;
      Perf.resetForTest();
      expect(recomputeAllFeatures(q, kernel), isTrue);
      expect(kernelFeatures(), n, reason: 'stored result dropped: rebuilt');
      final edited = q.features.last.solid!.volume;
      expect(edited, lessThan(volume));
      recomputeAllFeatures(q, kernel, force: true);
      expect(q.features.last.solid!.volume, closeTo(edited, 1e-6 * edited));

      // Size: the stored body is a small share of the document.
      final doc = File(b.library['Plate']!.path).lengthSync();
      final gz = readDoc(b.library['Plate']!.path)!
          .entries
          .entries
          .where((e) => e.key.endsWith('.step.gz'))
          .fold<int>(0, (a, e) => a + e.value.length);
      expect(gz, greaterThan(0));
      expect(gz, lessThan(200 * 1024), reason: 'doc $doc bytes');
    }, skip: skip, timeout: const Timeout(Duration(minutes: 5)));
  });
}
