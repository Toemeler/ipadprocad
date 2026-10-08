// Part-wide parameters (Inventor's fx table for a part).
//
// A user parameter defined on the PART drives feature fields — the plate's
// extrusion distance, a hole's diameter — and sketch dimensions; changing it
// rebuilds only what reads it; cycles and unknown names are refused; deleting
// it freezes what used it at its last value; undo, redo and reopen keep it.
//
// Runs on the real kernel (PROTOTYPE_NATIVE_DIR); SKIPS without it.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/part_params.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final kernel = OcctPartKernel();
  final skip = kernel.available
      ? false
      : 'no kernel library — set PROTOTYPE_NATIVE_DIR (see LINUX.md)';

  double volume(AppState app) {
    final p = app.currentPart!;
    var v = 0.0;
    for (final (name, _) in p.solidBodies()) {
      v += currentBodySolid(p, name)?.volume ?? 0;
    }
    return v;
  }

  ExtrudeFeature plateOf(AppState app) =>
      app.currentPart!.features.whereType<ExtrudeFeature>().first;

  /// A 40 x 30 plate, 10 thick, and a part parameter Thick = 10 driving it
  /// through the extrusion panel.
  Future<(AppState, PartParam, Directory)> build() async {
    final docs = Directory.systemTemp.createTempSync('prototype_m500_');
    final app = AppState()
      ..partKernel = kernel
      ..docsDirForTest = docs;
    await app.createNamedPart('Params');
    final cad = AiCad(app);
    final r = await cad.run([
      const AiAction('create_sketch', {'plane': 'xz'}),
      const AiAction('sketch_rect',
          {'x': 0, 'y': 0, 'width': 40, 'height': 30, 'centered': true}),
      const AiAction('extrude', {'distance': 10, 'id': 'plate'}),
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final thick = app.addPartParam(raw: 'Thick = 10')!;
    expect(thick.value, 10);
    app.openExtrude(plateOf(app));
    app.setExtrude(exprA: 'Thick');
    expect(await app.applyExtrude(), isTrue);
    expect(plateOf(app).exprA, 'Thick');
    expect(volume(app), closeTo(12000, 0.05));
    return (app, thick, docs);
  }

  test('a part parameter drives an extrusion distance', () async {
    final (app, thick, _) = await build();
    expect(app.setPartParamText(thick, '14'), isTrue);
    expect(plateOf(app).distanceA, 14);
    expect(volume(app), closeTo(40 * 30 * 14, 0.05));
    // equations of parameters chain: Thick = Base + 2, Base = 6 -> 8
    final base = app.addPartParam(raw: 'Base = 6')!;
    expect(app.setPartParamText(thick, 'Base + 2'), isTrue);
    expect(volume(app), closeTo(40 * 30 * 8, 0.05));
    expect(app.setPartParamText(base, '3,5'), isTrue, reason: 'comma decimal');
    expect(thick.value, closeTo(5.5, 1e-9));
    expect(volume(app), closeTo(40 * 30 * 5.5, 0.05));
    expect(app.currentPart!.features.every((f) => f.computeError == null),
        isTrue);
  }, skip: skip);

  test('cycles and unknown names are refused, nothing changes', () async {
    final (app, thick, _) = await build();
    final a = app.addPartParam(raw: 'A = Thick * 2')!;
    expect(a.value, 20);
    expect(app.setPartParamText(thick, 'A / 2'), isFalse, reason: 'cycle');
    expect(app.setPartParamText(thick, 'Thick + 1'), isFalse,
        reason: 'self reference');
    expect(app.setPartParamText(thick, 'Nope * 2'), isFalse,
        reason: 'unknown name');
    expect(app.addPartParam(raw: 'Thick = 3'), isNull,
        reason: 'name in use');
    expect(thick.expr, isNull);
    expect(thick.value, 10);
    expect(volume(app), closeTo(12000, 0.05));
    expect(app.partParamTextValid(thick, 'A/2'), isFalse);
    expect(app.partParamTextValid(thick, '12 mm'), isTrue);
  }, skip: skip);

  test('only what reads the parameter rebuilds', () async {
    final (app, thick, _) = await build();
    final cad = AiCad(app);
    final r = await cad.run([
      const AiAction('create_sketch', {'plane': 'xz'}),
      const AiAction('sketch_circle', {'x': 60, 'y': 0, 'diameter': 10}),
      const AiAction('extrude',
          {'distance': 5, 'operation': 'new', 'id': 'pin'}),
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final pin = app.currentPart!.features.last;
    final pinSolid = pin.solid;
    final plateSolid = plateOf(app).solid;
    expect(app.setPartParamText(thick, '12'), isTrue);
    expect(identical(pin.solid, pinSolid), isTrue,
        reason: 'the pin does not read Thick — reused, not rebuilt');
    expect(identical(plateOf(app).solid, plateSolid), isFalse);
    expect(volume(app), closeTo(40 * 30 * 12 + math.pi * 25 * 5, 0.05));
  }, skip: skip);

  test('deleting a parameter freezes what used it at its last value',
      () async {
    final (app, thick, _) = await build();
    expect(app.setPartParamText(thick, '13'), isTrue);
    app.deletePartParam(thick);
    expect(app.currentPart!.params, isEmpty);
    expect(plateOf(app).exprA, '13 mm');
    expect(plateOf(app).distanceA, 13);
    expect(volume(app), closeTo(40 * 30 * 13, 0.05));
    // and Undo brings the parameter back, still driving the plate
    await app.undoPart();
    final back = app.currentPart!.params.single;
    expect(back.name, 'Thick');
    expect(plateOf(app).exprA, 'Thick');
    expect(app.setPartParamText(back, '9'), isTrue);
    expect(volume(app), closeTo(40 * 30 * 9, 0.05));
    await app.undoPart();
    expect(volume(app), closeTo(40 * 30 * 13, 0.05));
    await app.redoPart();
    expect(volume(app), closeTo(40 * 30 * 9, 0.05));
  }, skip: skip);

  test('a renamed parameter takes its references along', () async {
    final (app, thick, _) = await build();
    expect(app.renamePartParam(thick, 'Plate_T'), isTrue);
    expect(plateOf(app).exprA, 'Plate_T');
    expect(app.setPartParamText(thick, 'Wall = 11'), isTrue);
    expect(thick.name, 'Wall');
    expect(plateOf(app).exprA, 'Wall');
    expect(volume(app), closeTo(40 * 30 * 11, 0.05));
  }, skip: skip);

  test('the table and the references survive save and reopen', () async {
    final (app, thick, docs) = await build();
    expect(app.setPartParamText(thick, '12'), isTrue);
    app.addPartParam(raw: 'Tilt = 30', unit: 'deg');
    await app.savePart('Params');
    final b = AppState()
      ..partKernel = kernel
      ..docsDirForTest = docs;
    await b.openPart('Params');
    final p = b.currentPart!;
    expect([for (final u in p.params) '${u.name}:${u.value}:${u.unit}'],
        ['Thick:12.0:mm', 'Tilt:30.0:deg']);
    expect(plateOf(b).exprA, 'Thick');
    expect(volume(b), closeTo(40 * 30 * 12, 0.05));
    expect(b.setPartParamText(p.params.first, '7'), isTrue);
    expect(volume(b), closeTo(40 * 30 * 7, 0.05));
  }, skip: skip);

  test('a document written before part parameters opens unchanged', () {
    final p = PartModel('Old');
    p.loadJson({
      'version': 1,
      'type': 'part',
      'features': [
        {'kind': 'extrude', 'name': 'Extrusion1', 'a': 7, 'exprA': '7 mm'}
      ],
    });
    expect(p.params, isEmpty);
    expect(p.toJson().containsKey('params'), isFalse);
    expect(resolvePartExpressions(p), isEmpty);
    expect((p.features.single as ExtrudeFeature).distanceA, 7);
  });

  test('dialog values name part parameters (fields of every panel)', () async {
    final (app, _, _) = await build();
    expect(parseValueExpr('Thick / 2'), 5);
    expect(parseValueExpr('Thick*2 mm'), 20);
    expect(parseValueExpr('Missing + 1'), isNull);
    expect(parseValueExpr('3,5 mm'), 3.5);
    expect(app.currentPart!.params.single.name, 'Thick');
  }, skip: skip);

  test('a work plane offset typed as an equation follows the parameter',
      () async {
    final (app, thick, docs) = await build();
    final p = app.currentPart!;
    final base = planeFrame('xz');
    final w = WorkPlane('Work Plane1', p.nextSeq(), WorkPlaneKind.offset,
        'Offset 20.00 mm from XZ Plane', offsetPlaneFrame(base, 20),
        base: base, offset: 20);
    p.workPlanes.add(w);
    app.selectWorkPlane(w);
    expect(app.commitWorkPlaneOffset('Thick + 10'), isTrue);
    expect(w.offset, 20);
    expect(w.valueExpr, 'Thick + 10');
    app.startSketchOnWorkPlane(w);
    final sketch = app.activeChild!.name;
    app.finishPartSketch();
    final r = await AiCad(app).run([
      AiAction('sketch_circle',
          {'sketch': sketch, 'x': 0, 'y': 0, 'diameter': 10}),
      AiAction('extrude', {
        'sketch': sketch,
        'distance': 5,
        'direction': 'flipped',
        'operation': 'new'
      }),
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    expect(app.setPartParamText(thick, '12'), isTrue);
    expect(w.offset, 22);
    expect(w.frame.origin.y, closeTo(22, 1e-9));
    final boss = p.features.last;
    expect(boss.computeError, isNull);
    // the boss on the plane rode up with it: y 17..22
    final m = boss.solid!.mesh;
    var hi = -1e9;
    for (var i = 1; i < m.positions.length; i += 3) {
      hi = math.max(hi, m.positions[i]);
    }
    expect(hi, closeTo(22, 1e-6));
    // saved with its equation
    await app.savePart('Params');
    final b = AppState()
      ..partKernel = kernel
      ..docsDirForTest = docs;
    await b.openPart('Params');
    expect(b.currentPart!.workPlanes.single.valueExpr, 'Thick + 10');
  }, skip: skip);

  test('a sketch dimension reads a part parameter, and follows it', () async {
    final docs = Directory.systemTemp.createTempSync('prototype_m500_');
    final app = AppState()
      ..partKernel = kernel
      ..docsDirForTest = docs;
    await app.createNamedPart('Dims');
    final cad = AiCad(app);
    var r = await cad.run([
      const AiAction('create_sketch', {'plane': 'xz'}),
      const AiAction('sketch_rect', {'width': 40, 'height': 30}),
      const AiAction('sketch_dimension',
          {'kind': 'dist', 'value': 40, 'near': [[20, 0]]}),
      const AiAction('extrude', {'distance': 10}),
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final width = app.addPartParam(raw: 'Width = 50')!;
    app.openChildSketch('Sketch1');
    final s = app.current!;
    final dim = s.constraints.firstWhere((c) => c.value == 40);
    expect(app.dimTextValid(dim, 'Width'), isTrue);
    expect(app.setDimensionText(dim, 'Width'), isTrue);
    expect(dim.value, 50);
    app.finishPartSketch();
    expect(volume(app), closeTo(50 * 30 * 10, 0.05));
    // the table moves -> the sketch re-solves -> the plate follows
    expect(app.setPartParamText(width, '60'), isTrue);
    expect(dim.value, 60);
    expect(volume(app), closeTo(60 * 30 * 10, 0.05));
    // a part parameter may read that dimension back (by its part-wide name)
    final half = app.addPartParam(raw: 'Half = ${dim.paramName} / 2')!;
    expect(half.value, 30);
    // ...but not so that the loop closes
    expect(app.setPartParamText(width, 'Half * 2'), isFalse);
    expect(width.value, 60);
    // a second sketch numbers its dimensions on from the first one's
    r = await cad.run([
      const AiAction('create_sketch', {'plane': 'xy'}),
      const AiAction('sketch_line', {'x1': 0, 'y1': 60, 'x2': 30, 'y2': 60}),
      const AiAction('sketch_dimension',
          {'kind': 'dist', 'value': 45, 'near': [[15, 60]]}),
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final names = [
      for (final cs in app.currentPart!.childSketches)
        for (final c in cs.model.constraints)
          if (c.paramName != null) c.paramName!
    ];
    expect(names.toSet().length, names.length,
        reason: 'dimension names are unique across the part: $names');
    // deleting the parameter leaves the dimension at its last value
    app.deletePartParam(width);
    expect(dim.expr, isNull);
    expect(dim.value, 60);
    expect(volume(app), closeTo(60 * 30 * 10, 0.05));
  }, skip: skip);
}
