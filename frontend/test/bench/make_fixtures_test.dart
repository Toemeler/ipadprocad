// Rebuilds the benchmark's fixture STEP files. Run once with the kernel:
//   AI_BENCH_FIXTURES=1 PROTOTYPE_NATIVE_DIR=... flutter test test/bench/make_fixtures_test.dart
//
// motorminimicro.stp — the micro gear motor from issues #92-#95, rebuilt from
// the faces the bug bundles measured (bug-2026-09-23T165918, faces_where and
// describe_shape): a Ø4.5 can cut flat at x = -1.85, 8.5 tall, a 1.5 × 2.4 ×
// 5 terminal block at x -3.35..-1.85, a Ø2 × 0.2 boss, and a Ø0.8 D-shaft
// 1.0 long (y 8.7..9.7) on the Y axis with its flat at x = -0.1.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

const motor = [
  AiAction('create_sketch', {'plane': 'xz'}),
  AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 4.5}),
  AiAction('extrude', {'distance': 8.5}),
  AiAction('create_sketch', {'plane': 'xz'}),
  AiAction('sketch_rect', {'x': -5, 'y': -3, 'width': 3.15, 'height': 6}),
  AiAction('extrude', {'distance': 8.5, 'operation': 'cut'}),
  AiAction('create_sketch', {'plane': 'xz'}),
  AiAction('sketch_rect',
      {'x': -2.6, 'y': 0, 'width': 1.5, 'height': 2.4, 'centered': true}),
  AiAction('extrude', {'distance': 5, 'operation': 'join'}),
  AiAction('create_sketch', {'plane': 'xz', 'offset': 8.5}),
  AiAction('sketch_circle', {'x': 0, 'y': 0, 'diameter': 2}),
  AiAction('extrude', {'distance': 0.2, 'operation': 'join'}),
  AiAction('create_sketch', {'plane': 'xz', 'offset': 8.7}),
  AiAction('sketch_path', {
    'start': [-0.1, '-sqrt(0.16-0.01)'],
    'segments': [
      {'to': [-0.1, 'sqrt(0.16-0.01)'], 'through': [0.4, 0]}
    ]
  }),
  AiAction('extrude', {'distance': 1, 'operation': 'join'}),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final kernel = OcctPartKernel();
  test('fixtures', () async {
    final app = AppState(ai: AiController())..partKernel = kernel;
    final dir = Directory.systemTemp.createTempSync('fixtures_');
    app.docsDirForTest = dir;
    await app.createNamedPart('motorminimicro');
    final r = await AiCad(app).run(motor);
    expect(r.ok, isTrue, reason: '${r.toJson()}');
    final path = await app.partExportStep('motorminimicro');
    expect(path, isNotNull);
    File(path!).copySync('test/bench/fixtures/motorminimicro.stp');
    final d = await AiCad(app).run(
        const [AiAction('describe_shape', {'detail': 'faces'})]);
    // ignore: avoid_print
    print(d.toJson());
  },
      skip: Platform.environment['AI_BENCH_FIXTURES'] == null || !kernel.available
          ? 'set AI_BENCH_FIXTURES=1 and PROTOTYPE_NATIVE_DIR'
          : false);
}
