// A sketch on a work plane goes where the plane goes.
//
// Inventor: re-offset (or re-angle) a work plane and every sketch on it, and
// every feature built from those sketches, follows. Here the sketch kept a
// COPY of the plane's frame from the moment it was made, so editing the plane
// moved the plane alone and left the boss built on it where it was.
//
// Runs on the real kernel (PROTOTYPE_NATIVE_DIR); SKIPS without it.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

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

  double topY(AppState app) {
    final p = app.currentPart!;
    var hi = -1e9;
    for (final (name, _) in p.solidBodies()) {
      final m = currentBodySolid(p, name)?.mesh;
      if (m == null) continue;
      for (var i = 1; i < m.positions.length; i += 3) {
        hi = math.max(hi, m.positions[i]);
      }
    }
    return hi;
  }

  /// A 40 x 30 x 10 plate, a work plane 20 mm above the ground, and a Ø10
  /// boss sketched on that plane and extruded 15 mm back down into the plate.
  Future<(AppState, WorkPlane)> build() async {
    final app = AppState()..partKernel = kernel;
    app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m481_');
    await app.createNamedPart('Work');
    final cad = AiCad(app);
    var r = await cad.run([
      const AiAction('create_sketch', {'plane': 'xz'}),
      const AiAction('sketch_rect',
          {'x': 0, 'y': 0, 'width': 40, 'height': 30, 'centered': true}),
      const AiAction('extrude', {'distance': 10}),
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    final p = app.currentPart!;
    final base = planeFrame('xz');
    final w = WorkPlane('Work Plane1', p.nextSeq(), WorkPlaneKind.offset,
        'Offset 20.00 mm from XZ Plane', offsetPlaneFrame(base, 20),
        base: base, offset: 20);
    p.workPlanes.add(w);
    app.startSketchOnWorkPlane(w);
    final sketch = app.activeChild!.name;
    app.finishPartSketch();
    r = await cad.run([
      AiAction('sketch_circle',
          {'sketch': sketch, 'x': 0, 'y': 0, 'diameter': 10}),
      AiAction('extrude', {
        'sketch': sketch,
        'distance': 15,
        'direction': 'flipped',
        'operation': 'join'
      }),
    ]);
    expect(r.ok, isTrue, reason: r.encode());
    expect(topY(app), closeTo(20, 1e-6));
    expect(volume(app), closeTo(12000 + math.pi * 25 * 10, 0.05));
    return (app, w);
  }

  test('re-offsetting the plane carries the boss with it', () async {
    final (app, w) = await build();
    expect(app.setWorkPlaneOffset(w, 22), isTrue);
    // y 7..22 now: 12 mm of it stands above the plate
    expect(topY(app), closeTo(22, 1e-6));
    expect(volume(app), closeTo(12000 + math.pi * 25 * 12, 0.05));
    for (final f in app.currentPart!.features) {
      expect(f.computeError, isNull, reason: f.name);
    }
  }, skip: skip);

  test('the link is saved with the sketch', () async {
    final (app, w) = await build();
    final j = app.currentPart!.toJson();
    final rows = (j['sketches'] as List).cast<Map>();
    expect(rows.where((m) => m['workPlane'] == w.id), hasLength(1));
  }, skip: skip);
}
