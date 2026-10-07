// Part Ctrl+Z belongs to the PART it was recorded in.
//
// The part journal was one stack for the whole session. Edit part A, switch
// to part B, press Ctrl+Z: A's snapshot was restored INTO B — B's features
// replaced by A's, and saved that way.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

void addRect(SketchModel s, double x0, double y0, double x1, double y1,
    {String layer = 'Layer 1'}) {
  s.engine.setCurrentLayer(layer);
  s.engine.addLine(x0, y0, x1, y0);
  s.engine.addLine(x1, y0, x1, y1);
  s.engine.addLine(x1, y1, x0, y1);
  s.engine.addLine(x0, y1, x0, y0);
  s.refresh();
}

Future<void> block(AppState app, String name, double w) async {
  await app.createNamedPart(name);
  app.startPartSketch();
  app.planePicked('xy');
  addRect(app.activeChild!, 0, 0, w, 10, layer: app.editingLayer!);
  app.finishPartSketch();
  app.openExtrude();
  app.setExtrude(exprA: '5 mm');
  await app.applyExtrude();
}

List<String> featureNames(PartModel p) => [for (final f in p.features) f.name];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('undo in another part does not restore this part into it', () async {
    final app = AppState()
      ..docsDirForTest = Directory.systemTemp.createTempSync('m476_');
    await block(app, 'A', 20);
    final a = app.parts['A']!;
    expect(a.features, hasLength(1));
    // a journalled edit in A
    await app.deleteFeature(a.features.single);
    expect(a.features, isEmpty);

    await app.createNamedPart('B');
    expect(app.curTab, 'B');
    final b = app.parts['B']!;
    expect(app.canUndoPart, isFalse, reason: 'B has no history of its own');
    await app.undoPart();
    expect(featureNames(b), isEmpty,
        reason: "A's extrusion must not appear in B");

    // back in A, its own history is still there
    await app.openDocument('A');
    expect(app.curTab, 'A');
    expect(app.canUndoPart, isTrue);
    await app.undoPart();
    expect(featureNames(app.parts['A']!), hasLength(1));
  });

  test('the history follows a rename and goes with a delete', () async {
    final app = AppState()
      ..docsDirForTest = Directory.systemTemp.createTempSync('m476r_');
    await block(app, 'A', 20);
    await app.deleteFeature(app.parts['A']!.features.single);
    expect(await app.renamePart('A', 'Plate'), isTrue);
    expect(app.curTab, 'Plate');
    expect(app.canUndoPart, isTrue);
    await app.undoPart();
    expect(featureNames(app.parts['Plate']!), hasLength(1));

    await app.deleteFeature(app.parts['Plate']!.features.single);
    await app.deletePart('Plate');
    await app.createNamedPart('Plate');
    expect(app.canUndoPart, isFalse,
        reason: 'a new part must not inherit a deleted one\'s history');
  });
}
