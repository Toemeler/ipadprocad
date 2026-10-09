import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prototype/ai/ai_backend.dart';
import 'package:prototype/ai/ai_build123d.dart';
import 'package:prototype/ai/ai_build123d_client.dart';
import 'package:prototype/ai/ai_cad.dart';
import 'package:prototype/ai/ai_controller.dart';
import 'package:prototype/app_state.dart';
import 'package:prototype/part_model.dart';
import 'package:prototype/reality_scene.dart' show visibleSolids;

class Transport implements Build123dTransport {
  Transport(this.script);
  final Stream<Map<String, dynamic>> Function(Map<String, dynamic>) script;
  final jobs = <Map<String, dynamic>>[];
  void Function()? onCancel;
  @override
  Stream<Map<String, dynamic>> generate(Map<String, dynamic> job) {
    jobs.add(job);
    return script(job);
  }

  @override
  void cancel() => onCancel?.call();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final kernel = OcctPartKernel();
  final skip = kernel.available ? false : 'needs PROTOTYPE_NATIVE_DIR';
  final step = base64Encode(
      File('test/fixtures/build123d/bracket.step').readAsBytesSync());
  Map<String, dynamic> history(String name) => Map<String, dynamic>.from(
      jsonDecode(File('test/fixtures/build123d/$name-history.json')
          .readAsStringSync()) as Map);
  Map<String, dynamic> event(String type,
          {List<String> problems = const [],
          String construction = 'bracket'}) =>
      {
        'type': type,
        'step': step,
        'label': 'Bracket',
        'history': history(construction),
        'metrics': {
          'valid': true,
          'solids': 1,
          'size_mm': [40, 30, 20]
        },
        if (type == 'complete') 'problems': problems,
      };
  AiAction build(
          {String name = 'bracket', Map<String, dynamic> extra = const {}}) =>
      AiAction('build123d', {
        'part': name,
        'code':
            'import build123d as bd\nresult=bd.Box(40,30,20)\npublish(result,"Body")',
        ...extra
      });
  Future<(AppState, AiCad)> fresh({AiController? controller}) async {
    final ai = controller ?? (AiController()..initializeInMemory());
    final app = AppState(ai: ai)..partKernel = kernel;
    final dir = Directory.systemTemp.createTempSync('build123d-test-');
    app.docsDirForTest = dir;
    addTearDown(() {
      ai.dispose();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    await app.createNamedPart('Bracket');
    return (app, AiCad(app)..wantsImages = false);
  }

  test(
      'large streamed Python recovers into a live mug with editable native history',
      () async {
    const vault = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            vault, (call) async => call.method == 'read' ? 'test-key' : null);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(vault, null));
    final source =
        File('test/fixtures/build123d/mug-with-handle.py').readAsStringSync() +
            '\n${'# Named controlling dimensions and feature notes.\n' * 400}';
    final block = '```cad\n${jsonEncode({
          'title': 'Tasse bauen',
          'actions': [
            {
              'op': 'build123d',
              'part': 'mug',
              'code': source,
              'checks': {'solids': 1}
            }
          ]
        })}\n```';
    var requests = 0;
    var largestWireBytes = 0;
    final backend = DeviceAiBackend(
        clientFactory: () => MockClient.streaming((r, bodyStream) async {
              requests++;
              final body =
                  jsonDecode(await utf8.decodeStream(bodyStream)) as Map;
              expect(
                  body['messages'][0]['content'], contains('REAL build123d'));
              final answer = requests <= 2
                  ? block
                  : '```cad\n{"title":"Tasse fertig","say":"Tasse mit Henkel aufgebaut."}\n```';
              final packets = <List<int>>[];
              for (var i = 0; i < answer.length; i += 2) {
                packets.add(utf8.encode('data: ${jsonEncode({
                      'id': 'chatcmpl-0123456789abcdef0123456789abcdef',
                      'object': 'chat.completion.chunk',
                      'created': 1791581547,
                      'model': 'deepseek-flash',
                      'system_fingerprint': 'fp_0123456789abcdef',
                      'choices': [
                        {
                          'index': 0,
                          'delta': {
                            'content': answer.substring(
                                i, (i + 2).clamp(0, answer.length))
                          },
                          'finish_reason': null
                        }
                      ],
                      'usage': null,
                    })}\n\n'));
              }
              packets.add(utf8.encode('data: ${jsonEncode({
                    'choices': [
                      {
                        'delta': {},
                        'finish_reason': requests == 1 ? 'aborted' : 'stop'
                      }
                    ]
                  })}\n\ndata: [DONE]\n\n'));
              final wireBytes =
                  packets.fold<int>(0, (sum, packet) => sum + packet.length);
              if (wireBytes > largestWireBytes) largestWireBytes = wireBytes;
              return http.StreamedResponse(Stream.fromIterable(packets), 200);
            }));
    final controller = AiController(backend: backend)..initializeInMemory();
    final (app, cad) = await fresh(controller: controller);
    controller.build123dMode = true;
    const document = AiDocument(id: 'mug', name: 'Bracket', kind: 'part');
    controller.updateWorkspace(current: document, documents: const [document]);
    controller.contextReader = (id) async => {'id': id, 'name': 'Bracket'};
    final p = app.currentPart!;
    final transport = Transport((job) async* {
      expect(job['code'], source);
      final payload = event('preview', construction: 'mug-with-handle');
      payload['step'] = base64Encode(
          File('test/fixtures/build123d/mug-with-handle.step')
              .readAsBytesSync());
      yield payload;
      expect(p.aiPreviewSolids, hasLength(1));
      expect(p.features, isEmpty);
      yield {...payload, 'type': 'complete', 'problems': <String>[]};
    });
    final engine = AiBuild123d(app, cad, transport: transport);
    controller.actionRunner = (actions, {onStep}) =>
        actions.any((a) => a.op == 'build123d')
            ? engine.run(actions, onStep: onStep)
            : cad.run(actions, onStep: onStep);
    await controller.configure(
        provider: AiProvider.deepseek, model: 'deepseek-flash');
    controller.updateDraft(
        'mach mir eine Tasse mit Henkel, komplett 3d druckbar aus pla');
    await controller.send();
    expect(controller.error, isNull);
    expect(largestWireBytes, greaterThan(2097325),
        reason: 'exceeds the physical-iPad failure threshold');
    expect(requests, 3,
        reason: 'one aborted request, one completed script, one review');
    expect(transport.jobs, hasLength(1),
        reason: 'the aborted script was never executed');
    expect(p.aiPreviewSolids, isEmpty);
    expect(p.childSketches, hasLength(3));
    expect(p.features.map((f) => f.kind), ['extrude', 'extrude', 'extrude']);
    expect(p.features.whereType<ExtrudeFeature>().every((f) => !f.imported),
        isTrue);
    expect(partExportBodies(p), hasLength(1));
    expect(p.aiBuild123d['mug']!['code'], source);
  }, skip: skip);

  test('WASM previews become editable sketches and features in one undo',
      () async {
    final (app, cad) = await fresh();
    final p = app.currentPart!;
    final transport = Transport((_) async* {
      yield event('preview');
      expect(p.aiPreviewSolids, hasLength(1));
      expect(visibleSolids(app, p), hasLength(1));
      expect(p.features, isEmpty);
      expect(partExportBodies(p), isEmpty);
      expect(p.toJson().containsKey('aiPreviewSolids'), isFalse);
      yield event('complete');
    });
    final report =
        await AiBuild123d(app, cad, transport: transport).run([build()]);
    expect(report.ok, isTrue, reason: report.encode());
    expect(p.aiPreviewSolids, isEmpty);
    expect(p.features.map((f) => f.kind), ['extrude', 'extrude', 'fillet']);
    expect(p.features.whereType<ExtrudeFeature>().every((f) => !f.imported),
        isTrue);
    expect(p.childSketches, hasLength(2));
    expect(p.childSketches.last.model.geometry.single.type, 2);
    expect((p.features[1] as ExtrudeFeature).output, 'cut');
    final solid = currentBodySolid(p, p.bodyNames.single)!;
    expect(solid.volume, closeTo(22926.017763, 0.001));
    final bbox = solid.shape!.bbox()!;
    expect(bbox[3] - bbox[0], closeTo(40, 0.001));
    expect(bbox[4] - bbox[1], closeTo(20, 0.001));
    expect(bbox[5] - bbox[2], closeTo(30, 0.001));
    expect((build123dContext(p)['models'] as List).single['matchesTimeline'],
        isTrue);
    await app.undoPart();
    expect(p.features, isEmpty);
    expect(p.aiBuild123d, isEmpty);
    await app.redoPart();
    expect(p.features, hasLength(3));
    expect(currentBodySolid(p, p.bodyNames.single)!.volume,
        closeTo(22926.017763, 0.001));
    expect(p.aiBuild123d['bracket']!['code'], contains('build123d'));
  }, skip: skip);
  test('Python failure after preview preserves existing model and source',
      () async {
    final (app, cad) = await fresh();
    final good = Transport((_) async* {
      yield event('complete');
    });
    expect((await AiBuild123d(app, cad, transport: good).run([build()])).ok,
        isTrue);
    final before = jsonEncode(app.currentPart!.toJson());
    final bad = Transport((_) async* {
      yield event('preview');
      yield {
        'type': 'error',
        'error': 'fillet failed',
        'traceback': 'model.py line 12'
      };
    });
    final report = await AiBuild123d(app, cad, transport: bad).run([build()]);
    expect(report.ok, isFalse);
    expect(report.encode(), contains('model.py line 12'));
    expect(app.currentPart!.aiPreviewSolids, isEmpty);
    expect(jsonEncode(app.currentPart!.toJson()), before);
  }, skip: skip);
  test(
      'replace preserves native history and revisions reuse original input geometry',
      () async {
    final (app, cad) = await fresh();
    final native = await cad.run(const [
      AiAction('program', {
        'part': 'base',
        'steps': [
          {
            'box': {
              'size': [40, 20, 30],
              'base': [0, 0, 0]
            }
          }
        ]
      })
    ]);
    expect(native.ok, isTrue, reason: native.encode());
    final p = app.currentPart!;
    final body = p.bodyNames.single;
    final original = currentBodySolid(p, body)!.volume;
    final transport = Transport((_) async* {
      yield event('complete', construction: 'replace');
    });
    final engine = AiBuild123d(app, cad, transport: transport);
    final report = await engine.run([
      build(extra: {
        'inputs': [body],
        'replace': [body]
      })
    ]);
    expect(report.ok, isTrue, reason: report.encode());
    expect(partExportBodies(p), hasLength(1));
    expect(p.features, hasLength(3));
    expect(p.features.first.consumedByJoin, isTrue);
    expect(currentBodySolid(p, body)!.volume, lessThan(original));
    final input = transport.jobs.single['inputs'];
    expect((await engine.run([build()])).ok, isTrue);
    expect(transport.jobs.last['inputs'], input);
    expect(p.features, hasLength(3));
    final sourceFingerprint = p.aiBuild123d['bracket']!['fingerprint'];
    p.childSketches.first.face = planeFrame('xy');
    expect(build123dFingerprint(p, [body]), isNot(sourceFingerprint));
    final stale = await engine.run([build()]);
    expect(stale.ok, isFalse,
        reason: 'upstream sketch edits cannot be overwritten');
    await app.undoPart();
    await app.undoPart();
    expect(p.features, hasLength(1));
    expect(currentBodySolid(p, body)!.volume, closeTo(original, 0.001));
  }, skip: skip);
  test('manual edits prevent stale replay without overwriting the user',
      () async {
    final (app, cad) = await fresh();
    final transport = Transport((_) async* {
      yield event('complete');
    });
    final engine = AiBuild123d(app, cad, transport: transport);
    expect((await engine.run([build()])).ok, isTrue);
    final p = app.currentPart!;
    p.features.first.name = 'Manually renamed';
    final report = await engine.run([build()]);
    expect(report.ok, isFalse);
    expect(report.encode(), contains('edited manually'));
    expect(p.features.first.name, 'Manually renamed');
    expect(transport.jobs, hasLength(1));
  }, skip: skip);
  test('user edit during preview is retained and prevents commit', () async {
    final (app, cad) = await fresh();
    final p = app.currentPart!;
    final transport = Transport((_) async* {
      yield event('preview');
      p.solidN = 42;
      yield event('complete');
    });
    expect(
        (await AiBuild123d(app, cad, transport: transport).run([build()])).ok,
        isFalse);
    expect(p.features, isEmpty);
    expect(p.solidN, 42);
    expect(p.aiPreviewSolids, isEmpty);
  }, skip: skip);
  test('cancel removes only preview and terminates the active execution',
      () async {
    final (app, cad) = await fresh();
    final stream = StreamController<Map<String, dynamic>>();
    final transport = Transport((_) => stream.stream);
    transport.onCancel = () {
      stream.add({'type': 'error', 'error': 'cancelled'});
      unawaited(stream.close());
    };
    final engine = AiBuild123d(app, cad, transport: transport);
    final run = engine.run([build()]);
    stream.add(event('preview'));
    for (var i = 0; i < 100 && app.currentPart!.aiPreviewSolids.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(app.currentPart!.aiPreviewSolids, hasLength(1));
    await engine.abort();
    expect((await run).ok, isFalse);
    expect(app.currentPart!.features, isEmpty);
    expect(app.currentPart!.aiPreviewSolids, isEmpty);
  }, skip: skip);
  test('measured requirement failures reach the AI for repair', () async {
    final (app, cad) = await fresh();
    final transport = Transport((_) async* {
      yield event('complete', problems: ['height required 25, measured 20']);
    });
    final report =
        await AiBuild123d(app, cad, transport: transport).run([build()]);
    expect(report.ok, isTrue);
    expect(report.problems, hasLength(1));
    expect(report.problems.single, contains('height required'));
  }, skip: skip);
  test(
      'editable bore sketch changes real geometry and makes Python source stale',
      () async {
    final (app, cad) = await fresh();
    final transport = Transport((_) async* {
      yield event('complete');
    });
    final engine = AiBuild123d(app, cad, transport: transport);
    expect((await engine.run([build()])).ok, isTrue);
    final p = app.currentPart!;
    final body = p.bodyNames.single;
    final before = currentBodySolid(p, body)!.volume;
    final bore = p.childSketches.last.model;
    final circle = bore.geometry.single;
    app.aiCommitSketch(bore, [
      circle.withData([circle.data[0], circle.data[1], 5])
    ]);
    app.aiForgetRegions(bore.name);
    expect(recomputeAllFeatures(p, app.partKernel), isTrue);
    expect(currentBodySolid(p, body)!.volume,
        closeTo(before - 3.141592653589793 * (25 - 16) * 20, 0.001));
    expect((build123dContext(p)['models'] as List).single['matchesTimeline'],
        isFalse);
    expect((await engine.run([build()])).ok, isFalse);
  }, skip: skip);
  test(
      'missing history and mismatched native geometry cannot commit an imported solid',
      () async {
    final (app, cad) = await fresh();
    for (final failure in ['missing', 'wrong-volume', 'wrong-position']) {
      final transport = Transport((_) async* {
        final payload = event('complete');
        if (failure == 'missing') {
          payload.remove('history');
        } else {
          final construction = history('base');
          if (failure == 'wrong-position') {
            final nodes = construction['nodes'] as List;
            final frame = nodes.first['profiles'][0]['frame'] as List;
            frame[9] = (frame[9] as num) + 5;
            payload['step'] = base64Encode(
                File('test/fixtures/build123d/base.step').readAsBytesSync());
          }
          payload['history'] = construction;
        }
        yield payload;
      });
      final result =
          await AiBuild123d(app, cad, transport: transport).run([build()]);
      expect(result.ok, isFalse);
      expect(app.currentPart!.features, isEmpty);
      expect(app.currentPart!.childSketches, isEmpty);
      expect(app.currentPart!.aiBuild123d, isEmpty);
    }
  }, skip: skip);
  for (final model in [
    'placed-chamfer',
    'symmetric-straight',
    'symmetric-taper',
    'sphere',
    'cone',
    'torus',
    'shell',
    'sweep',
    'revolved-cup',
    'mug-with-handle',
    'builder-cut',
    'loft',
    'text'
  ]) {
    test('real WASM $model becomes independently rebuilding native features',
        () async {
      final (app, cad) = await fresh();
      final transport = Transport((_) async* {
        final payload = event('complete', construction: model);
        payload['step'] = base64Encode(
            File('test/fixtures/build123d/$model.step').readAsBytesSync());
        yield payload;
      });
      final report = await AiBuild123d(app, cad, transport: transport)
          .run([build(name: model)]);
      expect(report.ok, isTrue, reason: report.encode());
      final p = app.currentPart!;
      expect(p.childSketches, isNotEmpty);
      expect(p.features.whereType<ExtrudeFeature>().any((f) => f.imported),
          isFalse);
      expect(p.features.every((f) => f.resultCache == null), isTrue);
      final volume = partExportBodies(p)
          .fold<double>(0, (sum, entry) => sum + entry.$2.volume);
      for (final f in p.features) f.disposeSolid();
      expect(recomputeAllFeatures(p, app.partKernel), isTrue);
      expect(
          partExportBodies(p)
              .fold<double>(0, (sum, entry) => sum + entry.$2.volume),
          closeTo(volume, 0.001));
      await app.closeTab('Bracket');
      await app.openPart('Bracket');
      final opened = app.currentPart!;
      expect(opened.features.map((f) => f.kind), p.features.map((f) => f.kind));
      expect(opened.childSketches.length, p.childSketches.length);
      expect(
          partExportBodies(opened)
              .fold<double>(0, (sum, entry) => sum + entry.$2.volume),
          closeTo(volume, 0.001));
    }, skip: skip);
  }
}
