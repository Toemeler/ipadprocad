// M245 — a component IS its part, not a photograph of it.
//
// "A part in an assembly should be linked to the part at all times. So when
// the part updates, it updates in assembly. All the time."
//
// M240 gave every occurrence a PRIVATE copy of the part, loaded once when the
// assembly was opened. Nothing about that is visible until you change the
// part — and then the assembly goes on drawing what the part used to look
// like, with no error and nothing to click. It is the worst shape a bug can
// have: silent, and the document on screen is a lie.
//
// The rule now is that there is exactly ONE PartModel per part document in
// the app, and every occurrence of it points at that one. This suite is about
// the identity — `same()`, not `equals()` — because identity is the whole
// mechanism: if the assembly holds the same object the editor holds, there is
// nothing left to keep in step.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/asm_constraints.dart';
import 'package:prototype/assembly.dart';
import 'package:prototype/part_model.dart';

AppState freshApp(String tag) =>
    AppState()..docsDirForTest = Directory.systemTemp.createTempSync(tag);

/// A saved part with one named feature, so a change to it is nameable.
Future<void> makePart(AppState app, String name, {double size = 10}) async {
  expect(await app.createNamedPart(name), isTrue);
  final p = app.parts[name]!;
  p.features.add(ExtrudeFeature(
    name: 'Extrusion1',
    bodyName: 'Solid1',
    sketchName: 'Sketch1',
    profiles: [ProfileSel(0, 0, 10)],
    direction: ExtrudeDirection.defaultDir,
    distanceA: size,
    distanceB: 0,
    extent: FeatureExtent.distance,
  ));
  await app.savePart(name);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('one model per document', () {
    test('a component points at the very model the part tab is editing',
        () async {
      final app = freshApp('ipc_m245_same');
      await makePart(app, 'Bracket');
      app.goHome();
      expect(await app.createNamedAssembly('Gearbox'), isTrue);
      final occ = await app.placeComponent('Bracket');
      expect(occ, isNotNull);

      // The part is still open in its own tab, so the component must be
      // holding THAT object — not a copy of it.
      expect(occ!.part, same(app.parts['Bracket']),
          reason: 'a component that holds a copy is a photograph');
    });

    test('an edit to the part is in the assembly with nothing propagated',
        () async {
      final app = freshApp('ipc_m245_edit');
      await makePart(app, 'Bracket');
      app.goHome();
      await app.createNamedAssembly('Gearbox');
      final occ = (await app.placeComponent('Bracket'))!;
      expect(occ.part!.features, hasLength(1));

      // Edit the part the way the editor does — through the model AppState
      // holds — and look at the assembly. Nothing in between.
      app.parts['Bracket']!.features.add(ExtrudeFeature(
        name: 'Extrusion2',
        bodyName: 'Solid1',
        sketchName: 'Sketch1',
        profiles: [ProfileSel(0, 0, 10)],
        direction: ExtrudeDirection.defaultDir,
        distanceA: 4,
        distanceB: 0,
        extent: FeatureExtent.distance,
      ));
      expect(occ.part!.features, hasLength(2),
          reason: 'the component sees the edit because it IS the part');
      expect(occ.part!.features.last.name, 'Extrusion2');
    });

    test('two occurrences of one part share one model', () async {
      final app = freshApp('ipc_m245_two');
      await makePart(app, 'Bracket');
      app.goHome();
      await app.createNamedAssembly('Gearbox');
      final a = (await app.placeComponent('Bracket'))!;
      final b = (await app.placeComponent('Bracket'))!;
      expect(a.id, isNot(b.id));
      expect(a.part, same(b.part),
          reason: 'one document, one model, however many times it is placed');
    });

    test('re-opening the assembly links to the model, not to a fresh copy',
        () async {
      final app = freshApp('ipc_m245_reopen');
      await makePart(app, 'Bracket');
      app.goHome();
      await app.createNamedAssembly('Gearbox');
      await app.placeComponent('Bracket');
      await app.saveAssembly('Gearbox');
      await app.closeTab('Gearbox');

      await app.openAssembly('Gearbox');
      final occ = app.currentAssembly!.occurrences.single;
      expect(occ.part, isNotNull, reason: 'the geometry is loaded on open');
      expect(occ.part, same(app.parts['Bracket']),
          reason: 'and it is the open part tab\'s own model');
    });
  });

  group('the model survives the tabs moving under it', () {
    test('closing the part tab does not blank the component', () async {
      final app = freshApp('ipc_m245_close');
      await makePart(app, 'Bracket');
      app.goHome();
      await app.createNamedAssembly('Gearbox');
      final occ = (await app.placeComponent('Bracket'))!;
      final model = occ.part;
      expect(model, isNotNull);

      // Closing the part used to dispose the model the assembly was drawing.
      await app.closeTab('Bracket');
      expect(app.parts.containsKey('Bracket'), isFalse);
      expect(occ.part, same(model),
          reason: 'the assembly is still drawing it, so it is still here');
      // Not `solids`: there is no kernel on the host, so no feature ever
      // acquires one. The FEATURES are what says the model is still whole.
      expect(occ.part!.features, hasLength(1));
    });

    test('re-opening the part promotes the shared model rather than '
        'reading the file again', () async {
      final app = freshApp('ipc_m245_promote');
      await makePart(app, 'Bracket');
      app.goHome();
      await app.createNamedAssembly('Gearbox');
      final occ = (await app.placeComponent('Bracket'))!;
      await app.closeTab('Bracket');
      final held = occ.part;

      await app.openPart('Bracket');
      expect(app.parts['Bracket'], same(held),
          reason: 'one model per document, across a tab opening');
      expect(occ.part, same(app.parts['Bracket']));
    });

    test('closing the ASSEMBLY frees what nothing places any more', () async {
      final app = freshApp('ipc_m245_evict');
      await makePart(app, 'Bracket');
      app.goHome();
      await app.createNamedAssembly('Gearbox');
      await app.placeComponent('Bracket');
      await app.closeTab('Bracket');
      await app.closeTab('Gearbox');
      // Nothing open holds it. Re-opening reads it afresh, which is the
      // observable half of "it was let go"; the other half is that this does
      // not throw on a disposed model.
      await app.openAssembly('Gearbox');
      expect(app.currentAssembly!.occurrences.single.part, isNotNull);
    });
  });

  group('the link follows the document', () {
    test('deleting the part leaves the row and drops the geometry', () async {
      final app = freshApp('ipc_m245_del');
      await makePart(app, 'Bracket');
      app.goHome();
      await app.createNamedAssembly('Gearbox');
      final occ = (await app.placeComponent('Bracket'))!;
      expect(occ.loaded, isTrue);

      await app.deletePart('Bracket');
      expect(occ.loaded, isFalse,
          reason: 'a component of a part that is gone draws nothing...');
      expect(app.assemblies['Gearbox']!.occurrences, hasLength(1),
          reason: '...and keeps its row, which is how you find out');
    });

    test('renaming the part follows it into an OPEN assembly, constraints '
        'and all', () async {
      final app = freshApp('ipc_m245_rename_open');
      await makePart(app, 'Bracket');
      await makePart(app, 'Shaft');
      app.goHome();
      await app.createNamedAssembly('Gearbox');
      await app.placeComponent('Bracket');
      await app.placeComponent('Shaft');
      final a = app.assemblies['Gearbox']!;
      a.constraints.add(AsmConstraint(
        name: 'Mate:1',
        kind: AsmKind.mate,
        solution: AsmSolution.mate,
        a: AsmRef('Bracket:1',
            const AsmGeom.plane(Vec3.zero, Vec3(0, 0, 1)), 'Face'),
        b: AsmRef('Shaft:1',
            const AsmGeom.plane(Vec3.zero, Vec3(0, 0, -1)), 'Face'),
      ));

      expect(await app.renamePart('Bracket', 'Halter'), isTrue);
      final occ = a.occurrences.first;
      expect(occ.source, 'Halter');
      expect(occ.id, 'Halter:1', reason: 'the occurrence is named after it');
      expect(occ.part, isNotNull, reason: 'and it still has its geometry');
      expect(a.constraints.single.a.occurrence, 'Halter:1',
          reason: 'a relationship to an id that is gone is sick for ever');
    });

    test('renaming the part follows it into an assembly ON DISK', () async {
      final app = freshApp('ipc_m245_rename_disk');
      await makePart(app, 'Bracket');
      app.goHome();
      await app.createNamedAssembly('Gearbox');
      await app.placeComponent('Bracket');
      await app.saveAssembly('Gearbox');
      await app.closeTab('Gearbox');
      // The assembly is now only a file. A link that survives just while a
      // document happens to be open is not a link.
      expect(await app.renamePart('Bracket', 'Halter'), isTrue);

      await app.openAssembly('Gearbox');
      final occ = app.currentAssembly!.occurrences.single;
      expect(occ.source, 'Halter');
      expect(occ.id, 'Halter:1');
      expect(occ.part, isNotNull,
          reason: 'the component of a renamed part still draws');
    });
  });
}
