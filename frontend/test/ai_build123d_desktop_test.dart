import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prototype/ai/ai_build123d.dart';
import 'package:prototype/ai/ai_build123d_client.dart';
import 'package:prototype/ai/ai_build123d_desktop.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/ai/ai_workspace.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final engine = Platform.environment['PROTOTYPE_CAD_ENGINE'];
  final canRun = engine != null && File(engine).existsSync();
  final skip = canRun ? false : 'needs the bundled PROTOTYPE_CAD_ENGINE';
  DesktopBuild123dTransport transport({Duration? buildTimeout}) =>
      DesktopBuild123dTransport(
        executable: File(engine!),
        assets: Directory(Platform.environment['PROTOTYPE_CAD_ASSETS'] ??
                'assets/modelling')
            .absolute,
        buildTimeout: buildTimeout ?? const Duration(seconds: 160),
      );

  test('Windows/Linux default to build123d and refuse primitive programs',
      () async {
    if (!Platform.isWindows && !Platform.isLinux) return;
    final controller = AiController()..initializeInMemory();
    final app = AppState(ai: controller);
    final workspace = AiWorkspace(app);
    addTearDown(() {
      workspace.dispose();
      controller.dispose();
    });
    expect(controller.build123dMode, isTrue);
    expect(localBuild123dTransport(), isA<DesktopBuild123dTransport>());
    final report = await controller.actionRunner!(const [
      AiAction('program', {'code': 'box(10,10,10);'}),
    ]);
    expect(report.outcomes.single.ok, isFalse);
    expect(report.outcomes.single.error, contains('real build123d Python'));
  });

  test('missing packaged engine fails explicitly without running system Python',
      () async {
    final local =
        DesktopBuild123dTransport(executable: File('/missing/cad-engine'));
    await expectLater(local.generate({'code': 'result = None'}).toList(),
        throwsA(isA<FileSystemException>()));
  });

  test('real desktop worker streams bore/fillet previews and exact history',
      () async {
    final local = transport();
    final events = await local.generate({
      'part': 'bracket',
      'code': '''
import build123d as bd
result = bd.Box(40,30,20,align=(bd.Align.CENTER,bd.Align.CENTER,bd.Align.MIN))
publish(result,'Block')
result -= bd.Cylinder(4,22,align=(bd.Align.CENTER,bd.Align.CENTER,bd.Align.MIN)).translate((0,0,-1))
publish(result,'Bore')
result = bd.fillet(result.edges().filter_by(bd.Axis.Z),radius=2)
publish(result,'Fillet')
''',
      'checks': {
        'size_mm': [40, 30, 20],
        'solids': 1
      }
    }).toList();
    expect(events.map((e) => e['type']),
        ['preview', 'preview', 'preview', 'complete']);
    expect(events.map((e) => e['label']).take(3), ['Block', 'Bore', 'Fillet']);
    expect(events.last['problems'], isEmpty);
    final metrics = events.last['metrics'] as Map;
    expect(metrics['volume_mm3'],
        closeTo(24000 - pi * 16 * 20 - (4 - pi) * 4 * 20, .001));
    final nodes = (events.last['history'] as Map)['nodes'] as List;
    expect(nodes.map((n) => n['op']), ['extrude', 'extrude', 'cut', 'fillet']);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test(
      'desktop Python errors, blocked networking and restart use isolated jobs',
      () async {
    final local = transport();
    final failed = await local.generate({
      'code': '''
import build123d as bd
print('not an event')
result = bd.Box(10,10,10)
publish(result,'Before failure')
assert False, 'deliberate failure'
'''
    }).toList();
    expect(failed.map((e) => e['type']), ['preview', 'error']);
    expect(failed.last['error'], contains('deliberate failure'));
    expect(failed.last['traceback'], contains('model.py'));
    final restarted = await local.generate({
      'code': """
import js
request = js.XMLHttpRequest.new()
request.open('GET', 'https://example.com/forbidden', False)
blocked = False
try:
    request.send()
except Exception:
    blocked = True
assert blocked, 'external networking unexpectedly allowed'
assert not hasattr(js, 'process') and not hasattr(js, 'require')
import build123d as bd
result = bd.Box(10,10,10)
"""
    }).toList();
    expect(restarted.last['type'], 'complete');
    expect(restarted.last['metrics']['volume_mm3'], closeTo(1000, .001));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));

  test('cancel kills a stuck Python worker and the next desktop build succeeds',
      () async {
    final local = transport();
    final preview = Completer<void>();
    final stream = local.generate({
      'code': '''
import build123d as bd
result = bd.Box(10,10,10)
publish(result,'Before loop')
while True: pass
'''
    });
    final done = stream.forEach((event) {
      if (event['type'] == 'preview' && !preview.isCompleted)
        preview.complete();
    });
    // Install the error observer before cancelling the active operation.
    final check = expectLater(done, throwsA(isA<StateError>()));
    await preview.future.timeout(const Duration(seconds: 90));
    local.cancel();
    await check;
    final next = await local.generate(
        {'code': 'import build123d as bd\nresult=bd.Box(2,3,4)'}).toList();
    expect(next.last['type'], 'complete');
    expect(next.last['metrics']['volume_mm3'], closeTo(24, .001));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 4)));

  final kernel = OcctPartKernel();
  test(
      'configured desktop verification includes engine, assets and native kernel',
      () {
    if (engine == null) return;
    expect(File(engine).existsSync(), isTrue, reason: 'packaged CAD engine');
    expect(
        File('${transport().assets.path}/manifest.json').existsSync(), isTrue,
        reason: 'packaged Python/WASM dependencies');
    if (Platform.environment['PROTOTYPE_CAD_REQUIRE_NATIVE'] == '1') {
      expect(kernel.available, isTrue,
          reason: 'native editable CAD replay must run');
    }
  });
  test('actual desktop mug commits editable sketches, rebuilds and reopens',
      () async {
    final controller = AiController()..initializeInMemory();
    final app = AppState(ai: controller)..partKernel = kernel;
    final dir = Directory.systemTemp.createTempSync('desktop-mug-');
    app.docsDirForTest = dir;
    addTearDown(() {
      controller.dispose();
      dir.deleteSync(recursive: true);
    });
    await app.createNamedPart('Mug');
    final cad = AiCad(app)..wantsImages = false;
    var previews = 0;
    final runner = AiBuild123d(app, cad, transport: transport());
    final result = await runner.run([
      AiAction('build123d', {
        'part': 'mug',
        'code': File('test/fixtures/build123d/mug-with-handle.py')
            .readAsStringSync(),
        'checks': {'solids': 1},
      })
    ], onStep: (_op, _step, _total) {
      previews++;
    });
    expect(result.outcomes.single.ok, isTrue,
        reason: '${result.outcomes.single.error}');
    final part = app.parts['Mug']!;
    expect(previews, greaterThanOrEqualTo(3));
    expect(part.childSketches.length, 3);
    expect(part.features.whereType<ExtrudeFeature>().length, 3);
    expect(part.features.whereType<ExtrudeFeature>().every((f) => !f.imported),
        isTrue);
    expect(part.aiPreviewSolids, isEmpty);
    final volume = partExportBodies(part).single.$2.volume;
    for (final feature in part.features) {
      feature.disposeSolid();
    }
    expect(recomputeAllFeatures(part, kernel), isTrue);
    expect(partExportBodies(part).single.$2.volume, closeTo(volume, .001));
    await app.closeTab('Mug');
    await app.openPart('Mug');
    final reopened = app.currentPart!;
    expect(reopened.childSketches.length, 3);
    expect(
        reopened.features.whereType<ExtrudeFeature>().every((f) => !f.imported),
        isTrue);
    expect(partExportBodies(reopened).single.$2.volume, closeTo(volume, .001));
  },
      skip: canRun && kernel.available
          ? false
          : 'needs desktop engine and native kernel',
      timeout: const Timeout(Duration(minutes: 3)));
}
