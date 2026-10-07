// Renaming a part an assembly places carries EVERY reference to its
// components with it — not only the constraints.
//
// An occurrence is named after its document ("Bolt:1"), so a part rename
// renames the occurrence. A pattern names its seeds by that id, every pattern
// element names the seed it repeats, a work plane names the component it was
// built on and a view representation names the components it hides. Each of
// those left pointing at the old id is lost: the pattern regenerates its row
// from scratch (dropping the relationships on the old elements) and is dropped
// on the next open, the work plane is dropped on the next open, and the hidden
// component comes back visible.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/asm_constraints.dart';
import 'package:prototype/asm_pattern.dart';
import 'package:prototype/asm_reps.dart';
import 'package:prototype/asm_work_features.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/ffi/occt_engine.dart';
import 'package:prototype/part_model.dart';

KernelSolid boxSolid() {
  final pos = <double>[0, 0, 0, 10, 0, 0, 0, 10, 0, 0, 0, 10];
  return KernelSolid(
    OcctMeshData(
      Float64List.fromList(pos),
      Float64List.fromList(List.filled(12, 0.0)),
      Int32List.fromList(const [0, 1, 2, 0, 1, 3, 0, 2, 3, 1, 2, 3]),
      Int32List.fromList(const [0]),
      Float64List(0),
    ),
    1000,
    null,
  );
}

PartModel boltPart(String name) {
  final p = PartModel(name);
  p.features.add(ExtrudeFeature(
    name: 'Extrusion1',
    bodyName: 'Solid1',
    sketchName: 'Sketch1',
    profiles: [ProfileSel(0, 0, 10)],
    direction: ExtrudeDirection.defaultDir,
    distanceA: 10,
    distanceB: 0,
    extent: FeatureExtent.distance,
  )..solid = boxSolid());
  return p;
}

/// Bolt:1 grounded, Bolt:2 mated to it, a 3x pattern of Bolt:1 along X, a
/// work plane offset from Bolt:1's XY plane and a view rep hiding Bolt:2.
AssemblyModel rig() {
  final part = boltPart('Bolt');
  final a = AssemblyModel('Gearbox');
  a.occurrences.add(AssemblyOccurrence(
      id: 'Bolt:1', source: 'Bolt', part: part, offset: Vec3.zero,
      grounded: true));
  a.occurrences.add(AssemblyOccurrence(
      id: 'Bolt:2', source: 'Bolt', part: part, offset: const Vec3(0, 40, 0)));
  a.patterns.add(AsmPattern(
    name: 'RectangularPattern1',
    mode: PatternKind.rectangular,
    sources: ['Bolt:1'],
    refDirA: const AsmRef(
        kAssemblyOrigin, AsmGeom.axis(Vec3.zero, Vec3(1, 0, 0)), 'X Axis'),
  )
    ..countA = 3
    ..distanceA = 25
    ..distributionA = PatternDistribution.spacing);
  regenerateAsmPatterns(a);
  a.workPlanes.add(AsmWorkPlane(
    'Work Plane1',
    a.nextWorkSeq(),
    WorkPlaneKind.offset,
    'offset',
    workPlaneFrameAt(const Vec3(0, 0, 5), const Vec3(0, 0, 1)),
    refs: [
      const AsmRef('Bolt:1',
          AsmGeom.plane(Vec3.zero, Vec3(0, 0, 1)), 'XY Plane'),
    ],
    offset: 5,
  ));
  a.viewReps.add(AsmViewRep(name: 'View1', hidden: {'Bolt:2': true}));
  return a;
}

void expectRenamed(AssemblyModel a) {
  final ids = a.occurrences.map((o) => o.id).toSet();
  expect(ids.every((id) => id.startsWith('Nut:')), isTrue, reason: '$ids');
  final p = a.patterns.single;
  expect(p.seeds, ['Nut:1'], reason: 'the pattern still names its seed');
  final els = a.elementsOf('RectangularPattern1');
  expect(els, hasLength(2));
  for (final e in els) {
    expect(e.patternSeed, 'Nut:1');
  }
  expect(a.workPlanes.single.refs.single.occurrence, 'Nut:1');
  expect(a.viewRepNamed('View1')!.hidden.keys, ['Nut:2']);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renaming in memory re-points patterns, work features and view reps',
      () {
    final a = rig();
    final before = {for (final e in a.elementsOf('RectangularPattern1')) e.id};
    for (final o in [...a.occurrences]) {
      a.rename(o, 'Nut:${o.id.split(':').last}', 'Nut');
    }
    expectRenamed(a);
    // The row is the SAME occurrences, renamed — not a fresh row the next
    // regeneration had to make because it could not find the old one.
    regenerateAsmPatterns(a);
    expect({for (final e in a.elementsOf('RectangularPattern1')) e.id},
        {for (final id in before) 'Nut:${id.split(':').last}'});
    // and it survives the save and the reload
    final b = AssemblyModel('Gearbox')
      ..loadJson(jsonDecode(jsonEncode(a.toJson())) as Map<String, dynamic>);
    expect(b.patterns, hasLength(1), reason: 'pattern dropped on reopen');
    expect(b.workPlanes, hasLength(1), reason: 'work plane dropped on reopen');
    expect(b.viewRepNamed('View1')!.hidden.keys, ['Nut:2']);
  });

  test('a painted component keeps its colour through a part rename', () {
    final a = rig();
    a.byId('Bolt:2')!.material = 'Copper';
    a.rename(a.byId('Bolt:2')!, 'Nut:2', 'Nut');
    expect(a.byId('Nut:2')!.material, 'Copper');
  });

  test('renaming the part re-points a CLOSED assembly on disk too', () async {
    final app = AppState()
      ..docsDirForTest = Directory.systemTemp.createTempSync('m474_');
    expect(await app.createNamedPart('Bolt'), isTrue);
    await app.closeTab('Bolt');
    expect(await app.createNamedAssembly('Gearbox'), isTrue);
    final live = app.assemblies['Gearbox']!;
    final r = rig();
    live.occurrences.addAll(r.occurrences);
    live.patterns.addAll(r.patterns);
    live.workPlanes.addAll(r.workPlanes);
    live.viewReps.addAll(r.viewReps);
    expect(await app.saveAssembly('Gearbox'), isTrue);
    await app.closeTab('Gearbox');
    expect(app.assemblies.containsKey('Gearbox'), isFalse);

    expect(await app.renamePart('Bolt', 'Nut'), isTrue);

    await app.openAssembly('Gearbox');
    final a = app.assemblies['Gearbox']!;
    expect(a.patterns, hasLength(1), reason: 'pattern dropped on reopen');
    expect(a.workPlanes, hasLength(1), reason: 'work plane dropped on reopen');
    expectRenamed(a);
  });

  group('renaming a SUBASSEMBLY', () {
    Future<AppState> nested() async {
      final app = AppState()
        ..docsDirForTest = Directory.systemTemp.createTempSync('m474s_');
      expect(await app.createNamedPart('Bolt'), isTrue);
      await app.closeTab('Bolt');
      expect(await app.createNamedAssembly('Sub'), isTrue);
      expect(await app.placeComponent('Bolt'), isNotNull);
      await app.saveAssembly('Sub');
      await app.closeTab('Sub');
      expect(await app.createNamedAssembly('Top'), isTrue);
      final o = await app.placeComponent('Sub');
      expect(o, isNotNull);
      expect(o!.id, 'Sub:1');
      await app.saveAssembly('Top');
      return app;
    }

    void expectFollowed(AssemblyModel top) {
      final o = top.occurrences.single;
      expect(o.source, 'Gear', reason: 'the parent still names the old file');
      expect(o.id, 'Gear:1');
      expect(o.sub, isNotNull, reason: 'the component lost its geometry');
    }

    test('an OPEN parent follows it', () async {
      final app = await nested();
      expect(await app.renameDocument('Sub', 'Gear'), isTrue);
      expectFollowed(app.assemblies['Top']!);
    });

    test('an open parent follows it while the subassembly is open too',
        () async {
      final app = await nested();
      await app.openAssembly('Sub');
      expect(await app.renameDocument('Sub', 'Gear'), isTrue);
      expectFollowed(app.assemblies['Top']!);
      expect(identical(app.assemblies['Top']!.occurrences.single.sub,
              app.assemblies['Gear']), isTrue,
          reason: 'linked to the very model open in the tab');
    });

    test('a CLOSED parent follows it on disk', () async {
      final app = await nested();
      await app.closeTab('Top');
      expect(await app.renameDocument('Sub', 'Gear'), isTrue);
      await app.openAssembly('Top');
      expectFollowed(app.assemblies['Top']!);
    });
  });

  test('renaming a part reaches a subassembly held only as a component',
      () async {
    final app = AppState()
      ..docsDirForTest = Directory.systemTemp.createTempSync('m474p_');
    expect(await app.createNamedPart('Bolt'), isTrue);
    await app.closeTab('Bolt');
    expect(await app.createNamedAssembly('Sub'), isTrue);
    expect(await app.placeComponent('Bolt'), isNotNull);
    await app.saveAssembly('Sub');
    await app.closeTab('Sub');
    expect(await app.createNamedAssembly('Top'), isTrue);
    expect(await app.placeComponent('Sub'), isNotNull);
    expect(await app.renamePart('Bolt', 'Nut'), isTrue);
    final inner = app.assemblies['Top']!.occurrences.single.sub!;
    final bolt = inner.occurrences.single;
    expect(bolt.source, 'Nut', reason: 'the loaded subassembly is stale');
    expect(bolt.id, 'Nut:1');
    expect(bolt.part, isNotNull,
        reason: 'the bolt vanished from the parent assembly');
    // and what reaches the disk is the renamed one, not the stale copy
    await app.closeTab('Top');
    await app.openAssembly('Sub');
    expect(app.assemblies['Sub']!.occurrences.single.source, 'Nut');
  });
}
