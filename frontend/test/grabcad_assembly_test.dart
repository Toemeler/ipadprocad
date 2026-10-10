import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/quat.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/l10n/l.dart';
import 'package:prototype/widgets/ribbon.dart';
import 'package:prototype/widgets/grabcad_browser.dart';

import 'm240_assembly_test.dart' show boxSolid;

class ImportKernel implements PartKernel {
  ImportKernel({this.empty = false, this.assembly = false});
  final bool empty, assembly;
  @override
  bool get available => true;
  @override
  String get info => 'test import';
  @override
  String get lastError => '';
  @override
  List<KernelSolid> importStepSolids(String path) => empty ? [] : [boxSolid()];
  @override
  StepAssembly? importStepAssembly(String path) => !assembly
      ? null
      : StepAssembly(const [
          StepPiece(-1, 0, -1, Quat.identity, Vec3.zero, 'Imported gearbox'),
          StepPiece(0, 1, 0, Quat.identity, Vec3.zero, 'Imported gear'),
          StepPiece(0, 1, 0, Quat.identity, Vec3(30, 0, 0), 'Imported gear'),
        ], [
          boxSolid()
        ], 2);
  @override
  noSuchMethod(Invocation invocation) => null;
}

void main() {
  late Directory docs, downloads;
  late AppState app;
  setUp(() async {
    docs = Directory.systemTemp.createTempSync('grabcad_assembly_docs_');
    downloads =
        Directory.systemTemp.createTempSync('grabcad_assembly_download_');
    app = AppState()
      ..docsDirForTest = docs
      ..partKernel = ImportKernel();
    await app.createNamedAssembly('Machine');
  });
  tearDown(() {
    app.dispose();
    docs.deleteSync(recursive: true);
    downloads.deleteSync(recursive: true);
  });

  String source(String name) => (File('${downloads.path}/$name')
        ..writeAsStringSync('ISO-10303-21; END-ISO-10303-21;'))
      .path;

  test('imports into the initiating assembly, selects and saves the occurrence',
      () async {
    final target = app.currentAssembly!;
    final placed = await app.importAndPlaceComponent(source('Bearing.step'),
        assemblyName: 'Machine');
    expect(placed, isNotNull);
    expect(app.currentAssembly, same(target));
    expect(app.curTab, 'Machine');
    expect(target.occurrences.single, same(placed));
    expect(target.selected, same(placed));
    expect(placed!.source, 'Bearing');
    expect(placed.grounded, isTrue);
    expect(placed.part!.features.single.solid, isNotNull);
    expect(app.docNameExists('Bearing'), isTrue);
    expect(File('${docs.path}/Machine.pas').existsSync(), isTrue);
    await app.undoPart();
    expect(target.occurrences, isEmpty);
    await app.redoPart();
    expect(target.occurrences.single.source, 'Bearing');
  });

  test('structured STEP is inserted as a linked subassembly', () async {
    app.partKernel = ImportKernel(assembly: true);
    final target = app.currentAssembly!;
    final placed = await app.importAndPlaceComponent(source('Gearbox.step'),
        assemblyName: 'Machine');
    expect(app.currentAssembly, same(target));
    expect(placed, isNotNull);
    expect(placed!.source, 'Imported gearbox');
    expect(placed.sub, isNotNull);
    expect(placed.sub!.occurrences, hasLength(2));
    expect(
        placed.sub!.occurrences[0].part, same(placed.sub!.occurrences[1].part));
  });

  test('repeated downloads keep both local models and normal placement rules',
      () async {
    final path = source('Bearing.step');
    final first =
        await app.importAndPlaceComponent(path, assemblyName: 'Machine');
    final second =
        await app.importAndPlaceComponent(path, assemblyName: 'Machine');
    expect(first!.source, 'Bearing');
    expect(second!.source, 'Bearing 2');
    expect(first.grounded, isTrue);
    expect(second.grounded, isFalse);
    expect(app.currentAssembly!.occurrences, hasLength(2));
    expect(app.docNameExists('Bearing'), isTrue);
    expect(app.docNameExists('Bearing 2'), isTrue);
  });

  test('failed import restores the assembly without changing its components',
      () async {
    app.partKernel = ImportKernel(empty: true);
    final target = app.currentAssembly!;
    expect(
        await app.importAndPlaceComponent(source('Broken.step'),
            assemblyName: 'Machine'),
        isNull);
    expect(app.currentAssembly, same(target));
    expect(target.occurrences, isEmpty);
    expect(app.docNameExists('Broken'), isFalse);
  });

  test('a drawing is refused without opening a new document', () async {
    final target = app.currentAssembly!;
    expect(
        await app.importAndPlaceComponent(source('Drawing.dxf'),
            assemblyName: 'Machine'),
        isNull);
    expect(app.currentAssembly, same(target));
    expect(app.docNameExists('Drawing'), isFalse);
  });

  testWidgets('empty assembly Place offers GrabCAD search', (tester) async {
    const channel = MethodChannel('prototype/native_menu');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'grabcadSignIn') return true;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final old = L.locale.value;
    L.set(kEn);
    addTearDown(() => L.set(old));
    await tester
        .pumpWidget(MaterialApp(home: Scaffold(body: Ribbon(app: app))));
    await tester.pump();
    await tester.tap(find.byTooltip('Place').first);
    await tester.pumpAndSettle();
    expect(find.text('Search GrabCAD'), findsOneWidget);
    await tester.tap(find.text('Search GrabCAD'));
    await tester.pumpAndSettle();
    expect(find.byType(GrabCadBrowser), findsOneWidget);
    expect(
        tester
            .widget<GrabCadBrowser>(find.byType(GrabCadBrowser))
            .componentOnly,
        isTrue);
    expect(app.curTab, 'Machine');
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(app.currentAssembly!.occurrences, isEmpty);
  });
}
