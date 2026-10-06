// M471 — parts a mechanical engineer would model, on the REAL kernel, with
// volumes and topology checked against numbers worked out by hand.
//
// Runs wherever the kernel library is found: set PROTOTYPE_NATIVE_DIR to the
// directory holding libprototype_native.so. Without it every test SKIPS.
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

  Future<(AppState, AiCad)> fresh() async {
    final app = AppState()..partKernel = kernel;
    app.docsDirForTest = Directory.systemTemp.createTempSync('prototype_m471_');
    await app.createNamedPart('Work');
    return (app, AiCad(app));
  }

  double volume(AppState app) {
    final p = app.currentPart!;
    var v = 0.0;
    for (final (name, _) in p.solidBodies()) {
      v += currentBodySolid(p, name)?.volume ?? 0;
    }
    return v;
  }

  /// A 40 x 30 x 10 plate extruded up (+Y) from the XZ origin plane.
  const plate = [
    AiAction('create_sketch', {'plane': 'xz'}),
    AiAction('sketch_rect', {'width': 40, 'height': 30}),
    AiAction('extrude', {'distance': 10}),
  ];

  group('holes', () {
    test('a Through All hole sketched on the plane the plate grew from goes '
        'through, not 1 mm deep', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        ...plate,
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('hole',
            {'places': [[20, 15]], 'diameter': 8, 'through_all': true}),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      // pi * 4^2 * 10, all the way through the 10 mm plate.
      expect(volume(app), closeTo(12000 - math.pi * 16 * 10, 0.05));
    }, skip: skip);

    test('a counterbored hole from that plane opens at the plate face it '
        'sits on', () async {
      final (app, cad) = await fresh();
      final r = await cad.run([
        ...plate,
        const AiAction('create_sketch', {'plane': 'xz'}),
        const AiAction('hole', {
          'places': [[20, 15]], 'diameter': 6, 'depth': 10, //
          'type': 'counterbore', 'cb_diameter': 10, 'cb_depth': 3,
        }),
      ]);
      expect(r.ok, isTrue, reason: r.encode());
      // Drilled into the plate by the feature itself — the panel's path has
      // no assistant to turn it round afterwards.
      expect(r.outcomes.last.detail?['directionFixed'], isNull);
      final removed = math.pi * 9 * 10 + math.pi * (25 - 9) * 3;
      expect(volume(app), closeTo(12000 - removed, 0.05));
    }, skip: skip);
  });
}
