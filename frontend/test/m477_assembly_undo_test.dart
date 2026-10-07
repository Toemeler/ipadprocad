// Assemblies have Undo / Redo.
//
// Until now an assembly had no journal at all: deleting a component (and
// with it every relationship it had), a pattern or a constraint was final,
// and Ctrl+Z / the Undo button in an assembly only said "nothing to undo".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/asm_constraints.dart';
import 'package:prototype/part_model.dart';

Future<AppState> rig(String tag) async {
  final app = AppState()
    ..docsDirForTest = Directory.systemTemp.createTempSync(tag);
  expect(await app.createNamedPart('Bolt'), isTrue);
  await app.closeTab('Bolt');
  expect(await app.createNamedAssembly('Gearbox'), isTrue);
  expect(await app.placeComponent('Bolt'), isNotNull);
  expect(await app.placeComponent('Bolt'), isNotNull);
  final a = app.currentAssembly!;
  a.constraints.add(AsmConstraint(
    name: 'Mate:1',
    kind: AsmKind.mate,
    solution: solutionsFor(AsmKind.mate).first,
    a: const AsmRef('Bolt:1', AsmGeom.plane(Vec3.zero, Vec3(0, 0, 1)), 'Face'),
    b: const AsmRef('Bolt:2', AsmGeom.plane(Vec3.zero, Vec3(0, 0, -1)), 'Face'),
  ));
  await app.saveAssembly('Gearbox');
  return app;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a deleted component comes back with its relationship', () async {
    final app = await rig('m477a_');
    final a = app.currentAssembly!;
    app.deleteOccurrence(a.byId('Bolt:2')!);
    await Future<void>.delayed(Duration.zero);
    expect(a.occurrences, hasLength(1));
    expect(a.constraints, isEmpty);
    expect(app.canUndoPart, isTrue, reason: 'the Undo button is lit');

    await app.undoPart();
    expect(a.occurrences.map((o) => o.id), ['Bolt:1', 'Bolt:2']);
    expect(a.constraints.single.name, 'Mate:1');
    expect(a.byId('Bolt:2')!.part, isNotNull, reason: 'and it is drawn');

    expect(app.canRedoPart, isTrue);
    await app.redoPart();
    expect(a.occurrences, hasLength(1));
    expect(a.constraints, isEmpty);
  });

  test('undo goes step by step, back to the opened document', () async {
    final app = await rig('m477b_');
    final a = app.currentAssembly!;
    await app.undoPart(); // the constraint
    expect(a.constraints, isEmpty);
    expect(a.occurrences, hasLength(2));
    await app.undoPart(); // the second placement
    expect(a.occurrences, hasLength(1));
  });

  test('looking around is not undone', () async {
    final app = await rig('m477c_');
    final a = app.currentAssembly!;
    app.deleteOccurrence(a.byId('Bolt:2')!);
    await Future<void>.delayed(Duration.zero);
    a.camera.az = 1.234;
    await app.undoPart();
    expect(a.camera.az, 1.234);
  });

  test('a part renamed since comes back under its new name', () async {
    final app = await rig('m477d_');
    final a = app.currentAssembly!;
    app.deleteOccurrence(a.byId('Bolt:2')!);
    await Future<void>.delayed(Duration.zero);
    expect(await app.renamePart('Bolt', 'Nut'), isTrue);
    expect(a.occurrences.single.id, 'Nut:1');
    await app.undoPart();
    expect(a.occurrences.map((o) => o.id), ['Nut:1', 'Nut:2']);
    expect(a.occurrences.every((o) => o.part != null), isTrue);
  });

  test('hiding a component is saved at once and is its own undo step',
      () async {
    final app = await rig('m477e_');
    final a = app.currentAssembly!;
    app.setOccurrenceVisible(a.byId('Bolt:2')!, false);
    await Future<void>.delayed(Duration.zero);
    // On disk now, not only when the tab closes: a second session (a crash
    // and restart) sees it hidden.
    final again = AppState()..docsDirForTest = app.docsDirForTest;
    await again.openAssembly('Gearbox');
    expect(again.currentAssembly!.byId('Bolt:2')!.visible, isFalse);

    // Ctrl+Z takes back the hide, and only the hide.
    expect(app.canUndoPart, isTrue);
    await app.undoPart();
    expect(a.byId('Bolt:2')!.visible, isTrue);
    expect(a.constraints.single.name, 'Mate:1');
    await app.redoPart();
    expect(a.byId('Bolt:2')!.visible, isFalse);
  });
}
