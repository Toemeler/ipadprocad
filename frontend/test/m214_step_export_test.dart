// M214 — the STEP exporter, made to tell the truth.
//
// Two bugs, both reported from the device, both reproduced here:
//
//   1. Holes and fillets were missing from the exported file while being
//      plainly visible on screen. The export collected `f.solid` from EVERY
//      feature. Each feature stores the RUNNING accumulation at its own
//      position, so a block -> hole -> fillet part handed the kernel three
//      solids (the block, the block-minus-hole, the filleted block), and the
//      kernel then UNIONED them. Union puts material back: block ∪ (block −
//      hole) is the block. The hole and the fillet were undone by the export
//      itself.
//
//   2. Sharing a part from the gallery OPENED it. The export went through
//      openPart, which adds a tab, makes the part current, clears the tool and
//      rebuilds the viewport. Tapping Share navigated the app.
//
// Nothing here needs a linked OCCT: both bugs are decisions made in Dart
// BEFORE the kernel is reached, which is exactly why a fake can pin them.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/doc_file.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

/// Records exactly what the export asked the kernel to write.
///
/// Volumes are distinct per operation (join a+b, cut a−b, new = height) so a
/// test can say WHICH solid reached the file, not merely how many.
class ExportRecorder implements PartKernel {
  /// The (name, volume) pairs of the last exportStepBodies call.
  List<(String, double)> lastExport = const [];
  int exportCalls = 0;
  String lastPath = '';
  String lastProduct = '';

  /// Set to fail the write, so the caller's failure path can be exercised.
  bool failExport = false;

  /// Set to report success WITHOUT writing anything — the "kernel said yes
  /// and produced nothing" case.
  bool writeNothing = false;

  @override
  bool get available => true;
  @override
  String get info => 'export-recorder';
  @override
  String get lastError => 'recorder failure';

  KernelSolid _solid(double vol) => KernelSolid(
      OcctMeshData(
          Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0]),
          Float64List.fromList(const [0, 0, 1, 0, 0, 1, 0, 0, 1]),
          Int32List.fromList(const [0, 1, 2]),
          Int32List.fromList(const [0, 3]),
          Float64List.fromList(const [0, 0, 0, 1, 0, 0, 0, 1, 0])),
      vol,
      null);

  @override
  KernelSolid? extrude(List<List<List<Offset>>> groups, double height,
          double taperDeg, List<double> mat34) =>
      _solid(height);

  @override
  KernelSolid? fuseSolids(KernelSolid a, KernelSolid b) =>
      _solid(a.volume + b.volume);

  @override
  KernelSolid? cutSolids(KernelSolid base, KernelSolid tool) =>
      _solid(base.volume - tool.volume);

  @override
  KernelSolid? intersectSolids(KernelSolid a, KernelSolid b) =>
      _solid(a.volume < b.volume ? a.volume : b.volume);

  /// A fillet that visibly REMOVES material, so "the fillet survived the
  /// export" is a statement about a number and not about a hope.
  @override
  KernelSolid? filletEdges(KernelSolid base, List<int> edgeIds,
          List<double> radii,
          {List<double> radii2 = const [], BlendReport? report}) =>
      _solid(base.volume - 1);

  /// One ordinary, filletable, convex straight edge — enough for a fillet
  /// feature to resolve its pick and build.
  @override
  List<OcctEdgeInfo> edgesOf(KernelSolid s) =>
      const [OcctEdgeInfo(1, 1, 0, 0, 0, 1, 0, 0, 5, 0, 2, 90, 1)];

  @override
  bool exportStep(List<KernelSolid> solids, String path) =>
      exportStepBodies([for (final s in solids) ('', s)], path);

  @override
  bool exportStepBodies(List<(String, KernelSolid)> bodies, String path,
      {String product = ''}) {
    exportCalls++;
    lastExport = [for (final (n, s) in bodies) (n, s.volume)];
    lastPath = path;
    lastProduct = product;
    if (failExport) return false;
    if (!writeNothing) {
      File(path).writeAsStringSync('ISO-10303-21;\nEND-ISO-10303-21;\n');
    }
    return true;
  }

  @override
  List<KernelSolid> importStepSolids(String path) => const [];

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

AppState makeApp() {
  final app = AppState();
  app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m212_');
  app.partKernel = ExportRecorder();
  return app;
}

ExportRecorder kernelOf(AppState app) => app.partKernel as ExportRecorder;

void addRect(SketchModel s, double x0, double y0, double x1, double y1,
    {String layer = 'Layer 1'}) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

/// A part with one body: a 20x10 rectangle extruded [height] mm.
Future<AppState> baseBlock({String height = '8 mm'}) async {
  final app = makeApp();
  await app.createNamedPart('Part1');
  app.startPartSketch();
  app.planePicked('xy');
  addRect(app.activeChild!, 0, 0, 20, 10, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
  app.setExtrude(exprA: height);
  await app.applyExtrude();
  return app;
}

/// Adds a second profile and extrudes it with [output] against the base body.
Future<void> addFeature(AppState app, String output,
    {String height = '3 mm',
    double x0 = 4,
    double y0 = 2,
    double x1 = 12,
    double y1 = 8}) async {
  app.startPartSketch();
  app.planePicked('xy');
  addRect(app.activeChild!, x0, y0, x1, y1, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
  app.setExtrude(exprA: height, output: output);
  await app.applyExtrude();
}

/// Appends a 1 mm fillet on the single edge [ExportRecorder.edgesOf] reports.
/// The EdgeSel fingerprint matches that edge exactly (same midpoint, length
/// and kind), so resolveEdges finds it and the feature builds. It takes a real
/// timeline slot, so End of Part sees it where it actually is.
FilletFeature addFillet(PartModel p) {
  final f = FilletFeature(
      name: 'Fillet1',
      bodyName: p.features.last.bodyName,
      edges: [EdgeSel(0, 0, 0, 5, 1, 0)],
      radii: const [1.0])
    ..seq = p.nextSeq();
  p.features.add(f);
  return f;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('partExportBodies — the model, not its history', () {
    test('a hole is a hole: the cut result is exported, not the block',
        () async {
      final app = await baseBlock(height: '8 mm'); // block volume 8
      await addFeature(app, 'cut', height: '3 mm'); // cut -> 8 - 3 = 5
      final p = app.currentPart!;

      expect(p.features.length, 2, reason: 'block + cut');
      // Both features carry a solid — that is the trap the old export fell in.
      expect(p.features.every((f) => f.solid != null), isTrue);

      final bodies = partExportBodies(p);
      expect(bodies.length, 1,
          reason: 'one body; the pre-cut block is consumed, not a second body');
      expect(bodies.single.$2.volume, 5,
          reason: 'the CUT result. 8 would mean the hole was exported away');
    });

    test('a fillet is a fillet: the filleted body is exported', () async {
      final app = await baseBlock(height: '8 mm');
      final p = app.currentPart!;
      // Fillet the one edge the recorder reports, removing 1 unit of volume.
      addFillet(p);
      recomputeAllFeatures(p, app.partKernel);

      final bodies = partExportBodies(p);
      expect(bodies.length, 1);
      expect(bodies.single.$2.volume, 7,
          reason: '8 would mean the un-filleted block was exported over it');
    });

    test('block -> hole -> fillet exports ONE body, the last one', () async {
      final app = await baseBlock(height: '8 mm');
      await addFeature(app, 'cut', height: '3 mm'); // -> 5
      final p = app.currentPart!;
      addFillet(p);
      recomputeAllFeatures(p, app.partKernel);

      expect(p.features.length, 3);
      final bodies = partExportBodies(p);
      expect(bodies.length, 1,
          reason: 'three features, one body — this is the reported bug');
      expect(bodies.single.$2.volume, 4,
          reason: '8 - 3 (hole) - 1 (fillet). Any other number means a '
              'stale intermediate solid reached the file');
    });

    test('two separate bodies stay two bodies', () async {
      final app = await baseBlock(height: '8 mm');
      await addFeature(app, 'new',
          height: '5 mm', x0: 40, y0: 0, x1: 50, y1: 5);
      final p = app.currentPart!;

      final bodies = partExportBodies(p);
      expect(bodies.length, 2, reason: 'two bodies must not be fused into one');
      expect(bodies.map((b) => b.$2.volume).toList(), [8, 5]);
      expect(bodies.map((b) => b.$1).toSet().length, 2,
          reason: 'and they must carry DISTINCT names into the STEP products');
    });

    test('a body below End of Part is not in the file', () async {
      final app = await baseBlock(height: '8 mm');
      await addFeature(app, 'new',
          height: '5 mm', x0: 40, y0: 0, x1: 50, y1: 5);
      final p = app.currentPart!;
      expect(partExportBodies(p).length, 2);

      // Roll the marker back over the second body.
      app.setEndOfPart(partTimeline(p).length - 1);
      final bodies = partExportBodies(p);
      expect(bodies.length, 1,
          reason: 'rolled back is not part of the model yet');
      expect(bodies.single.$2.volume, 8);
    });

    test('a HIDDEN body is still exported (visibility is a display property)',
        () async {
      final app = await baseBlock(height: '8 mm');
      final p = app.currentPart!;
      p.features.single.visible = false;

      expect(partExportBodies(p).length, 1,
          reason: 'hiding a body to see past it must not drop it from the '
              'file you send to the shop');
    });
  });

  group('partExportStep — what actually reaches the kernel', () {
    test('the kernel is handed the live bodies, never the intermediates',
        () async {
      final app = await baseBlock(height: '8 mm');
      await addFeature(app, 'cut', height: '3 mm');
      final k = kernelOf(app);

      final path = await app.partExportStep('Part1');
      expect(path, isNotNull);
      expect(k.exportCalls, 1);
      expect(k.lastExport.length, 1);
      expect(k.lastExport.single.$2, 5,
          reason: 'the cut result, not the block it was cut from');
    });

    test('the document name is carried into the file as the product name',
        () async {
      final app = await baseBlock();
      await app.partExportStep('Part1');
      expect(kernelOf(app).lastProduct, 'Part1');
    });

    test('the written file is named after the document', () async {
      final app = await baseBlock();
      final path = await app.partExportStep('Part1');
      expect(path, isNotNull);
      expect(path!.endsWith('/Part1.step'), isTrue);
      expect(File(path).existsSync(), isTrue);
      expect(kernelOf(app).lastPath, path,
          reason: 'the kernel wrote the same file the share sheet is handed');
    });

    test('a failed write reports failure and leaves no stale file behind',
        () async {
      final app = await baseBlock();
      // First export succeeds and leaves a file.
      final good = await app.partExportStep('Part1');
      expect(good, isNotNull);
      expect(File(good!).existsSync(), isTrue);

      // The next one fails. The PREVIOUS file must not survive to be shared
      // in its place — that would hand over yesterday's geometry silently.
      kernelOf(app).failExport = true;
      expect(await app.partExportStep('Part1'), isNull);
      expect(File(good).existsSync(), isFalse,
          reason: 'the stale export must be cleared before the write');
    });

    test('a kernel that succeeds without writing is reported, not shared',
        () async {
      final app = await baseBlock();
      kernelOf(app).writeNothing = true;
      expect(await app.partExportStep('Part1'), isNull,
          reason: 'a zero-byte STEP file must never reach the share sheet');
    });

    test('an empty part exports nothing and says so', () async {
      final app = makeApp();
      await app.createNamedPart('Empty1');
      expect(await app.partExportStep('Empty1'), isNull);
      expect(kernelOf(app).exportCalls, 0);
    });
  });

  group('exporting is not navigation', () {
    test('sharing a CLOSED part does not open it', () async {
      final app = await baseBlock();
      await app.closeTab('Part1');
      app.goHome();
      expect(app.parts.containsKey('Part1'), isFalse);
      final tabsBefore = List<String>.of(app.openTabs);
      final tabBefore = app.curTab;

      final path = await app.partExportStep('Part1');
      expect(path, isNotNull, reason: 'it still has to EXPORT');

      expect(app.openTabs, tabsBefore,
          reason: 'Share must not add the part to the tab bar');
      expect(app.curTab, tabBefore,
          reason: 'Share must not make the part the current document');
      expect(app.parts.containsKey('Part1'), isFalse,
          reason: 'the headless copy must not be left in the session');
    });

    test('the closed part is still exported in full', () async {
      final app = await baseBlock(height: '8 mm');
      await addFeature(app, 'cut', height: '3 mm');
      await app.closeTab('Part1');
      app.goHome();

      final k = kernelOf(app);
      final path = await app.partExportStep('Part1');
      expect(path, isNotNull);
      expect(k.lastExport.length, 1);
      expect(k.lastExport.single.$2, 5,
          reason:
              'a part loaded headlessly must fold exactly like an open one');
    });

    test('sharing an OPEN part leaves it open and current', () async {
      final app = await baseBlock();
      expect(app.curTab, 'Part1');

      await app.partExportStep('Part1');
      expect(app.curTab, 'Part1');
      expect(app.parts.containsKey('Part1'), isTrue,
          reason: 'an open part must survive its own export');
      expect(app.currentPart!.features.single.solid, isNotNull,
          reason: 'and must not have had its solids disposed under it');
    });

    test('sharing a closed part does not rewrite the document', () async {
      final app = await baseBlock();
      await app.closeTab('Part1');
      app.goHome();
      final doc = app.docsDirForTest!
          .listSync()
          .whereType<File>()
          .firstWhere((f) => f.uri.pathSegments.last.startsWith('Part1.'));
      expect(doc.path.endsWith('.$kPartExt'), isTrue,
          reason: 'the document is on disk as a part file');

      // Backdated so a resave is unmistakable rather than a same-second tie.
      // Read the stamp BACK: some filesystems quantise mtimes, and the test is
      // about "did it change", not about sub-second fidelity.
      doc.setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 3)));
      final before = doc.lastModifiedSync();

      final path = await app.partExportStep('Part1');
      expect(path, isNotNull);
      expect(doc.lastModifiedSync(), before,
          reason: 'exporting a part nobody edited must not rewrite it — that '
              'reorders the gallery and rewrites the file you are sharing');
    });
  });

  group('no kernel', () {
    test('export is refused honestly rather than faked', () async {
      final app = await baseBlock();
      app.partKernel = _NoKernel();
      expect(await app.partExportStep('Part1'), isNull);
    });
  });
}

class _NoKernel implements PartKernel {
  @override
  bool get available => false;
  @override
  String get info => 'none';
  @override
  String get lastError => 'no 3D kernel linked';
  @override
  dynamic noSuchMethod(Invocation i) => null;
}
